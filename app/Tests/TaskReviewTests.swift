import Foundation
import XCTest
@testable import TaskFlow

final class TaskReviewTests: XCTestCase {
    func testOwnerActionSubmissionCapturesTrimmedCommentBeforeClosingAlert() {
        XCTAssertEqual(
            TaskFormViewModel.ownerActionCommentForSubmission("  поправь обработку ответа  "),
            "поправь обработку ответа"
        )
    }

    func testOwnerActionPreservesServerReason() {
        let error = APIError.server(
            status: 400,
            message: "нужен комментарий: что не так и что нужно доработать"
        )

        XCTAssertEqual(
            TaskFormViewModel.ownerActionErrorMessage(error),
            "нужен комментарий: что не так и что нужно доработать"
        )
    }

    func testApproveCurrentTaskVersionReadsCurrentVersionAndRecordsApproval() async throws {
        var requests: [URLRequest] = []
        TaskReviewURLProtocol.handler = { request in
            requests.append(request)
            switch request.url?.path {
            case "/api/tasks/task-1/versions":
                return (200, Data(#"""
                    {
                    "current_version_id":"version-2",
                    "versions":[
                        {"id":"version-1","task_id":"task-1","version_no":1,"task_revision":1,"result":"old","evidence_json":"[]","artifact_hash":"old-hash","created_by":"agent","created_at":"2026-09-12 10:00:00","is_current":false,"reviews":[]},
                        {"id":"version-2","task_id":"task-1","version_no":2,"task_revision":2,"result":"new","evidence_json":"[]","artifact_hash":"new-hash","created_by":"agent","created_at":"2026-09-12 10:05:00","is_current":true,"reviews":[]}
                    ]
                    }
                """#.utf8))
            case "/api/reviews":
                let body = try XCTUnwrap(requestBody(request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["task_id"] as? String, "task-1")
                XCTAssertEqual(json["version_id"] as? String, "version-2")
                XCTAssertEqual(json["artifact_hash"] as? String, "new-hash")
                XCTAssertEqual(json["task_revision"] as? Int, 2)
                XCTAssertEqual(json["criteria_version"] as? String, "taskflow-native-v1")
                XCTAssertEqual(json["verdict"] as? String, "approved")
                return (201, Data(#"""
                    {
                    "review_id":"review-1","task_id":"task-1","version_id":"version-2",
                    "task_revision":2,"reviewer_id":"owner","artifact_hash":"new-hash",
                    "criteria_version":"taskflow-native-v1","verdict":"approved","findings":null
                    }
                """#.utf8))
            default:
                XCTFail("Unexpected request: \(request.url?.path ?? "nil")")
                return (404, Data(#"{"error":"unexpected request"}"#.utf8))
            }
        }
        defer { TaskReviewURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TaskReviewURLProtocol.self]
        let client = APIClient(session: URLSession(configuration: configuration))

        try await client.approveCurrentTaskVersion(taskID: "task-1")

        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/tasks/task-1/versions", "/api/reviews"])
    }
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let httpBody = request.httpBody { return httpBody }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private final class TaskReviewURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (status: Int, data: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let result = try XCTUnwrap(Self.handler)(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: result.status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
