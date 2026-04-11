import XCTest
@testable import CCQuick

final class TaskGroupTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(TaskGroup.allCases.count, 5)
        XCTAssertEqual(TaskGroup.allCases, [.all, .running, .completed, .failed, .stopped])
    }

    func testRawValues() {
        XCTAssertEqual(TaskGroup.all.rawValue, "全部")
        XCTAssertEqual(TaskGroup.running.rawValue, "运行中")
        XCTAssertEqual(TaskGroup.completed.rawValue, "已完成")
        XCTAssertEqual(TaskGroup.failed.rawValue, "失败")
        XCTAssertEqual(TaskGroup.stopped.rawValue, "已停止")
    }

    func testIcons() {
        for group in TaskGroup.allCases {
            XCTAssertFalse(group.icon.isEmpty, "\(group) has empty icon")
        }
    }

    func testColors() {
        for group in TaskGroup.allCases {
            // Colors should be non-nil SwiftUI Color values
            // Just verify they don't crash
            _ = group.color
        }
    }

    func testIdentifiable() {
        for group in TaskGroup.allCases {
            XCTAssertEqual(group.id, group.rawValue)
        }
    }
}

final class LogManagerTests: XCTestCase {

    @MainActor
    func testAddLog() {
        let before = LogManager.shared.logs.count
        LogManager.shared.debug("test debug message", category: "Test")
        XCTAssertEqual(LogManager.shared.logs.count, before + 1)

        let last = LogManager.shared.logs.last
        XCTAssertEqual(last?.level, .debug)
        XCTAssertEqual(last?.message, "test debug message")
        XCTAssertEqual(last?.category, "Test")
    }

    @MainActor
    func testLogLevelColors() {
        XCTAssertNotNil(LogManager.LogLevel.debug.color)
        XCTAssertNotNil(LogManager.LogLevel.info.color)
        XCTAssertNotNil(LogManager.LogLevel.tool.color)
        XCTAssertNotNil(LogManager.LogLevel.ai.color)
        XCTAssertNotNil(LogManager.LogLevel.warning.color)
        XCTAssertNotNil(LogManager.LogLevel.error.color)
    }

    @MainActor
    func testLogLevelRawValues() {
        XCTAssertEqual(LogManager.LogLevel.debug.rawValue, "DEBUG")
        XCTAssertEqual(LogManager.LogLevel.info.rawValue, "INFO")
        XCTAssertEqual(LogManager.LogLevel.tool.rawValue, "TOOL")
        XCTAssertEqual(LogManager.LogLevel.ai.rawValue, "AI")
        XCTAssertEqual(LogManager.LogLevel.warning.rawValue, "WARN")
        XCTAssertEqual(LogManager.LogLevel.error.rawValue, "ERROR")
    }

    @MainActor
    func testClearLogs() {
        LogManager.shared.clear()
        XCTAssertTrue(LogManager.shared.logs.isEmpty)
    }

    @MainActor
    func testLogEntryFormattedTime() {
        let entry = LogManager.LogEntry(
            timestamp: Date(),
            level: .info,
            category: "Test",
            message: "test"
        )
        XCTAssertFalse(entry.formattedTime.isEmpty)
        // Format is HH:mm:ss
        let components = entry.formattedTime.components(separatedBy: ":")
        XCTAssertEqual(components.count, 3)
    }

    @MainActor
    func testLogLimit() {
        LogManager.shared.clear()
        for i in 0..<510 {
            LogManager.shared.debug("message \(i)", category: "Test")
        }
        XCTAssertLessThanOrEqual(LogManager.shared.logs.count, 500)
    }
}
