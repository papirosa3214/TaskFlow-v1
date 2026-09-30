import Foundation
import XCTest
@testable import TaskFlow

@MainActor
final class TaskStructureTests: XCTestCase {
    func testStructureAppliesServerFieldsToNewTask() async throws {
        TaskStructureURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/ai/structure-task")
            return (200, Data(#"{"title":"Купить продукты","description":"Купить хлеб и молоко","subtasks":["Купить хлеб","Купить молоко"],"dueDate":"2026-09-12","priority":2}"#.utf8))
        }
        defer { TaskStructureURLProtocol.handler = nil }

        let viewModel = TaskFormViewModel(taskID: nil, apiClient: testAPIClient())
        viewModel.title = "Купить продукты"
        viewModel.taskDescription = "Хлеб и молоко"

        await viewModel.structureWithAI()

        XCTAssertEqual(viewModel.aiStructureStatus, .completed)
        XCTAssertEqual(viewModel.title, "Купить продукты")
        XCTAssertEqual(viewModel.taskDescription, "Купить хлеб и молоко")
        XCTAssertEqual(viewModel.subtaskDrafts.map(\.title), ["Купить хлеб", "Купить молоко"])
        XCTAssertEqual(viewModel.priority, .high)
        XCTAssertEqual(viewModel.dueDate.map(DateFormats.calendarDateString), "2026-09-12")
    }

    func testStructureShowsServerError() async {
        TaskStructureURLProtocol.handler = { _ in
            (500, Data(#"{"error":"AI временно недоступен"}"#.utf8))
        }
        defer { TaskStructureURLProtocol.handler = nil }

        let viewModel = TaskFormViewModel(taskID: nil, apiClient: testAPIClient())
        viewModel.title = "Черновик"

        await viewModel.structureWithAI()

        XCTAssertEqual(viewModel.aiStructureStatus, .failed("AI временно недоступен"))
        XCTAssertEqual(viewModel.title, "Черновик")
    }

    private func testAPIClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TaskStructureURLProtocol.self]
        return APIClient(session: URLSession(configuration: configuration))
    }
}

private final class TaskStructureURLProtocol: URLProtocol {
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
