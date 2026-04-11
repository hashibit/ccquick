import XCTest
@testable import CCQuick

final class CCTaskTests: XCTestCase {

    // MARK: - elapsedSeconds

    func testElapsedSeconds_usesFinishedAt() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1030)
        let task = CCTask(
            id: "test-task",
            workDir: "/tmp/test",
            status: .completed,
            startedAt: start,
            finishedAt: end,
            viewed: false
        )
        XCTAssertEqual(task.elapsedSeconds, 30)
    }

    func testElapsedSeconds_usesNowForRunningTask() {
        let start = Date(timeIntervalSinceNow: -60)
        let task = CCTask(
            id: "test-running",
            workDir: "/tmp/test",
            status: .running,
            startedAt: start,
            finishedAt: nil,
            viewed: false
        )
        XCTAssertGreaterThanOrEqual(task.elapsedSeconds, 60)
    }

    // MARK: - elapsedString

    func testElapsedString_formatsCorrectly() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 150) // 2:30
        let task = CCTask(
            id: "test",
            workDir: "/tmp/test",
            status: .completed,
            startedAt: start,
            finishedAt: end,
            viewed: false
        )
        XCTAssertEqual(task.elapsedString, "02:30")
    }

    func testElapsedString_lessThanMinute() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 30)
        let task = CCTask(
            id: "test",
            workDir: "/tmp/test",
            status: .completed,
            startedAt: start,
            finishedAt: end,
            viewed: false
        )
        XCTAssertEqual(task.elapsedString, "00:30")
    }

    func testElapsedString_overAnHour() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 3661) // 1:01:01
        let task = CCTask(
            id: "test",
            workDir: "/tmp/test",
            status: .completed,
            startedAt: start,
            finishedAt: end,
            viewed: false
        )
        XCTAssertEqual(task.elapsedString, "61:01")
    }

    // MARK: - Codable

    func testCodableRoundtrip() throws {
        let original = CCTask(
            id: "202604061120-test-task",
            workDir: "/Users/test/.ccquick/202604061120-test-task",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1712390400),
            finishedAt: Date(timeIntervalSince1970: 1712390490),
            viewed: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CCTask.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.workDir, original.workDir)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.startedAt, original.startedAt)
        XCTAssertEqual(decoded.finishedAt, original.finishedAt)
        XCTAssertEqual(decoded.viewed, original.viewed)
    }

    // MARK: - TaskStatus Codable

    func testTaskStatusRoundtrip() throws {
        let statuses: [TaskStatus] = [.running, .completed, .failed, .stopped]

        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(TaskStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testTaskStatusRawValues() {
        XCTAssertEqual(TaskStatus.running.rawValue, "running")
        XCTAssertEqual(TaskStatus.completed.rawValue, "completed")
        XCTAssertEqual(TaskStatus.failed.rawValue, "failed")
        XCTAssertEqual(TaskStatus.stopped.rawValue, "stopped")
    }

    // MARK: - Hashable

    func testTaskHashable() {
        // Same id and same properties → equal
        let start = Date()
        let task1 = CCTask(
            id: "test", workDir: "/tmp", status: .running,
            startedAt: start, finishedAt: nil, viewed: false
        )
        let task2 = CCTask(
            id: "test", workDir: "/tmp", status: .running,
            startedAt: start, finishedAt: nil, viewed: false
        )
        XCTAssertEqual(task1, task2)
        XCTAssertEqual(task1.hashValue, task2.hashValue)

        // Different status → not equal
        let task3 = CCTask(
            id: "test", workDir: "/tmp", status: .completed,
            startedAt: start, finishedAt: .now, viewed: false
        )
        XCTAssertNotEqual(task1, task3)
    }
}

final class SessionMessageTests: XCTestCase {

    func testInitWithDefaults() {
        let msg = SessionMessage(type: .user, content: "hello")
        XCTAssertEqual(msg.type, .user)
        XCTAssertEqual(msg.content, "hello")
        XCTAssertFalse(msg.isStreaming)
        XCTAssertNotNil(msg.id)
        XCTAssertNotNil(msg.timestamp)
    }

    func testInitWithCustomValues() {
        let now = Date(timeIntervalSince1970: 1000)
        let msg = SessionMessage(
            type: .assistant,
            content: "response",
            timestamp: now,
            isStreaming: true
        )
        XCTAssertEqual(msg.type, .assistant)
        XCTAssertEqual(msg.content, "response")
        XCTAssertEqual(msg.timestamp, now)
        XCTAssertTrue(msg.isStreaming)
    }

    func testCodableRoundtrip() throws {
        let original = SessionMessage(
            type: .user,
            content: "test prompt",
            timestamp: Date(timeIntervalSince1970: 1712390400),
            isStreaming: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionMessage.self, from: data)

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.isStreaming, original.isStreaming)
    }

    func testMessageTypeRawValues() {
        XCTAssertEqual(MessageType.user.rawValue, "user")
        XCTAssertEqual(MessageType.assistant.rawValue, "assistant")
    }
}
