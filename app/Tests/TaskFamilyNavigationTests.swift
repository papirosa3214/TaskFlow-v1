import Foundation
import XCTest
@testable import TaskFlow

@MainActor
final class TaskFamilyNavigationTests: XCTestCase {
    private let original = #"{"id":"card-1","title":"Before","status":"active","labels":[],"subtasks":[]}"#
    private let updated = #"{"task":{"id":"card-1","title":"After","status":"active","labels":[],"subtasks":[]}}"#

    func testRejectedSaveKeepsLocalTextAndReportsFailure() async {
        let before = Data(original.utf8)
        CardSaveURLProtocol.handler = { request in
            request.httpMethod == "PATCH" ? (503, Data(#"{"error":"Save rejected"}"#.utf8)) : (200, before)
        }
        defer { CardSaveURLProtocol.handler = nil }
        let api = makeAPI(), store = TaskStore(apiClient: makeAPI())
        let model = TaskFormViewModel(taskID: "card-1", apiClient: api)
        await model.loadIfNeeded()
        XCTAssertNil(model.loadErrorMessage)
        model.title = "After"
        let saved = await model.save(taskStore: store)
        XCTAssertFalse(saved)
        XCTAssertEqual(model.title, "After")
        XCTAssertEqual(model.loadedTask?.title, "Before")
        XCTAssertTrue(model.saveErrorMessage?.contains("Save rejected") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testConfirmedSaveRefreshesSnapshotAndDoesNotResendUnchangedFields() async {
        let before = Data(original.utf8), after = Data(updated.utf8)
        var patches = 0
        CardSaveURLProtocol.handler = { request in
            if request.httpMethod == "PATCH" { patches += 1; return (200, after) }
            return (200, before)
        }
        defer { CardSaveURLProtocol.handler = nil }
        let api = makeAPI(), store = TaskStore(apiClient: makeAPI())
        let model = TaskFormViewModel(taskID: "card-1", apiClient: api)
        await model.loadIfNeeded()
        XCTAssertNil(model.loadErrorMessage)
        model.title = "After"
        let first = await model.save(taskStore: store)
        let second = await model.save(taskStore: store)
        XCTAssertTrue(first && second)
        XCTAssertEqual(model.loadedTask?.title, "After")
        XCTAssertEqual(store.tasks.first?.title, "After")
        XCTAssertEqual(patches, 1)
    }

    func testLabelOnlyChangeIsPersistedAndRefreshesSnapshot() async throws {
        let before = Data(original.utf8)
        let after = Data(#"{"task":{"id":"card-1","title":"Before","status":"active","labels":[{"id":"label-1","name":"Imported"}],"subtasks":[]}}"#.utf8)
        var receivedLabels: [String]?
        CardSaveURLProtocol.handler = { request in
            guard request.httpMethod == "PATCH" else { return (200, before) }
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            receivedLabels = body?["label_ids"] as? [String]
            return (200, after)
        }
        defer { CardSaveURLProtocol.handler = nil }
        let model = TaskFormViewModel(taskID: "card-1", apiClient: makeAPI())
        let store = TaskStore(apiClient: makeAPI())
        await model.loadIfNeeded()
        model.selectedLabelIds = ["label-1"]
        let saved = await model.save(taskStore: store)
        XCTAssertTrue(saved)
        XCTAssertEqual(receivedLabels, ["label-1"])
        XCTAssertEqual(model.loadedTask?.labels.map(\.id), ["label-1"])
    }

    private func makeAPI() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CardSaveURLProtocol.self]
        return APIClient(session: URLSession(configuration: configuration))
    }
}

private final class CardSaveURLProtocol: URLProtocol {
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
