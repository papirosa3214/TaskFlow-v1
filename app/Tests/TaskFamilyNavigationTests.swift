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

    /// Приклеенная к входящей карточке закладка и активная закладка слева
    /// стоят по одной геометрии: центр слота относительно центра колонки.
    func testSlotCenterOffsetsAreSymmetricAroundColumnCenter() {
        let height: CGFloat = 800
        let slot = TaskFamilyEdgeTabs.slotHeight(height: height, count: 3)
        XCTAssertEqual(TaskFamilyEdgeTabs.slotCenterOffset(index: 1, count: 3, height: height), 0, accuracy: 0.001)
        XCTAssertEqual(TaskFamilyEdgeTabs.slotCenterOffset(index: 0, count: 3, height: height),
                       -(slot + TaskFamilyEdgeTabs.spacing), accuracy: 0.001)
        XCTAssertEqual(TaskFamilyEdgeTabs.slotCenterOffset(index: 0, count: 1, height: height), 0, accuracy: 0.001)
    }

    func testReleaseCommitsOnDistanceOrFlickAndCancelsOnFlickBack() {
        let width: CGFloat = 400
        // Далеко вытянули и отпустили без скорости — открываем.
        XCTAssertTrue(TaskFamilyEdgeTabs.shouldCommit(pull: 130, velocity: 0, width: width))
        // Чуть потянули и отпустили — возвращаем.
        XCTAssertFalse(TaskFamilyEdgeTabs.shouldCommit(pull: 60, velocity: 0, width: width))
        // Короткий, но быстрый бросок по ходу перехода — открываем.
        XCTAssertTrue(TaskFamilyEdgeTabs.shouldCommit(pull: 60, velocity: 800, width: width))
        // Бросок обратно отменяет даже далёкое вытягивание.
        XCTAssertFalse(TaskFamilyEdgeTabs.shouldCommit(pull: 300, velocity: -600, width: width))
    }

    func testPullKeepsOtherTabsShiftWithinLimit() {
        let pull = TaskFamilyPull()
        pull.follow(40)
        XCTAssertEqual(pull.tabsShift, 18, accuracy: 0.001)
        pull.follow(400)
        XCTAssertEqual(pull.tabsShift, 40, accuracy: 0.001)
        XCTAssertEqual(pull.progress(width: 400), 1, accuracy: 0.001)
        pull.handoff = true
        XCTAssertEqual(pull.progress(width: 400), 0, accuracy: 0.001)
        XCTAssertEqual(pull.rawProgress(width: 400), 1, accuracy: 0.001)
    }

    /// Справа — дети, слева — родитель: к родителю переход идёт назад.
    func testParentIsBackAndChildrenAreForward() {
        XCTAssertEqual(TaskFamilyPullDirection.toward("parent", parentID: "parent"), .back)
        XCTAssertEqual(TaskFamilyPullDirection.toward("child-2", parentID: "parent"), .forward)
        XCTAssertEqual(TaskFamilyPullDirection.toward("child-2", parentID: nil), .forward)
    }

    /// Закладка родителя уходит под левую кромку, только пока въезжает
    /// ребёнок; по пути к родителю её не трогает сдвиг — она тает сама.
    func testParentTabSlidesAwayOnlyWhenGoingForward() {
        let pull = TaskFamilyPull()
        pull.follow(400)
        XCTAssertEqual(pull.leadingShift, -TaskFamilyEdgeTabs.expandedWidth, accuracy: 0.001)
        pull.leadingShift = 0
        pull.direction = .back
        pull.follow(400)
        XCTAssertEqual(pull.leadingShift, 0, accuracy: 0.001)
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
