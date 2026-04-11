import XCTest
@testable import CCQuick

final class TaskStoreTests: XCTestCase {

    // MARK: - makeTaskId

    func testMakeTaskId_englishPrompt() {
        let taskId = TaskStore.shared.makeTaskId(prompt: "fix the login bug")
        // Should start with timestamp pattern and contain slug
        XCTAssertTrue(taskId.hasPrefix("20"))
        XCTAssertTrue(taskId.contains("fix-the-login-bug"))
    }

    func testMakeTaskId_chinesePrompt() {
        let taskId = TaskStore.shared.makeTaskId(prompt: "帮我写一个登录页")
        XCTAssertTrue(taskId.hasPrefix("20"))
        // Chinese chars pass through alphanumerics filter as-is
        XCTAssertTrue(taskId.hasSuffix("-帮我写一个登录页"))
    }

    func testMakeTaskId_specialCharacters() {
        let taskId = TaskStore.shared.makeTaskId(prompt: "!!!***")
        XCTAssertTrue(taskId.hasPrefix("20"))
        XCTAssertTrue(taskId.hasSuffix("-task"))
    }

    func testMakeTaskId_truncatesTo30Chars() {
        let longPrompt = String(repeating: "a", count: 50)
        let taskId = TaskStore.shared.makeTaskId(prompt: longPrompt)
        let slugPart = taskId.components(separatedBy: "-").dropFirst().joined(separator: "-")
        XCTAssertLessThanOrEqual(slugPart.count, 30)
    }

    func testMakeTaskId_emptyPrompt() {
        let taskId = TaskStore.shared.makeTaskId(prompt: "   ")
        XCTAssertTrue(taskId.hasPrefix("20"))
        XCTAssertTrue(taskId.hasSuffix("-task"))
    }

    func testMakeTaskId_mixedContent() {
        let taskId = TaskStore.shared.makeTaskId(prompt: "Fix bug in 用户认证.ts")
        XCTAssertTrue(taskId.hasPrefix("20"))
    }

    // MARK: - save / load roundtrip

    func testSaveLoadRoundtrip() throws {
        let task = CCTask(
            id: "test-save-load-task",
            workDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ccquick/test-save-load-task").path,
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1712390400),
            finishedAt: Date(timeIntervalSince1970: 1712390490),
            viewed: false
        )

        try TaskStore.shared.save(task)

        let loaded = TaskStore.shared.load(id: task.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, task.id)
        XCTAssertEqual(loaded?.workDir, task.workDir)
        XCTAssertEqual(loaded?.status, task.status)
        XCTAssertEqual(loaded?.viewed, task.viewed)

        // Cleanup
        TaskStore.shared.delete(id: task.id)
    }

    // MARK: - loadAll

    func testLoadAll_sortsByStartedAtDescending() throws {
        // Create two tasks with different timestamps
        let task1 = CCTask(
            id: "test-all-task1",
            workDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ccquick/test-all-task1").path,
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1000),
            finishedAt: nil,
            viewed: false
        )
        let task2 = CCTask(
            id: "test-all-task2",
            workDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ccquick/test-all-task2").path,
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 2000),
            finishedAt: nil,
            viewed: false
        )

        try TaskStore.shared.save(task1)
        try TaskStore.shared.save(task2)

        let all = TaskStore.shared.loadAll()
        // Both tasks should exist, task2 (later startedAt) should come first
        let savedTasks = all.filter { ["test-all-task1", "test-all-task2"].contains($0.id) }
        XCTAssertGreaterThanOrEqual(savedTasks.count, 2)
        if savedTasks.count >= 2 {
            XCTAssertEqual(savedTasks[0].id, "test-all-task2")
        }

        // Cleanup
        TaskStore.shared.delete(id: "test-all-task1")
        TaskStore.shared.delete(id: "test-all-task2")
    }

    // MARK: - delete

    func testDelete_removesDirectory() throws {
        let task = CCTask(
            id: "test-delete-task",
            workDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ccquick/test-delete-task").path,
            status: .running,
            startedAt: .now,
            finishedAt: nil,
            viewed: false
        )

        try TaskStore.shared.save(task)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: TaskStore.shared.baseDir.appendingPathComponent(task.id).path
        ))

        TaskStore.shared.delete(id: task.id)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: TaskStore.shared.baseDir.appendingPathComponent(task.id).path
        ))
    }

    // MARK: - Session Messages (JSONL)

    func testAppendAndLoadMessages() throws {
        let id = "test-jsonl-msg"
        let task = CCTask(
            id: id,
            workDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ccquick/\(id)").path,
            status: .running,
            startedAt: .now,
            finishedAt: nil,
            viewed: false
        )
        try TaskStore.shared.save(task)

        let msg1 = SessionMessage(type: .user, content: "Hello")
        try TaskStore.shared.appendMessage(id: id, message: msg1)

        let msg2 = SessionMessage(type: .assistant, content: "Hi there!")
        try TaskStore.shared.appendMessage(id: id, message: msg2)

        let loaded = TaskStore.shared.loadMessages(id: id)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].type, .user)
        XCTAssertEqual(loaded[0].content, "Hello")
        XCTAssertEqual(loaded[1].type, .assistant)
        XCTAssertEqual(loaded[1].content, "Hi there!")

        // Cleanup
        TaskStore.shared.delete(id: id)
    }

    func testLoadMessages_nonExistent() {
        let msgs = TaskStore.shared.loadMessages(id: "nonexistent-task")
        XCTAssertTrue(msgs.isEmpty)
    }

    func testGetFirstPrompt() throws {
        let id = "test-first-prompt"
        let task = CCTask(
            id: id,
            workDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ccquick/\(id)").path,
            status: .running,
            startedAt: .now,
            finishedAt: nil,
            viewed: false
        )
        try TaskStore.shared.save(task)

        try TaskStore.shared.appendMessage(id: id, message: SessionMessage(type: .user, content: "What is Swift?"))

        let prompt = TaskStore.shared.getFirstPrompt(id: id)
        XCTAssertEqual(prompt, "What is Swift?")

        TaskStore.shared.delete(id: id)
    }

    func testGetFirstPrompt_nonExistent() {
        XCTAssertNil(TaskStore.shared.getFirstPrompt(id: "nonexistent"))
    }

    func testGetLastResponse() throws {
        let id = "test-last-response"
        let task = CCTask(
            id: id,
            workDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ccquick/\(id)").path,
            status: .running,
            startedAt: .now,
            finishedAt: nil,
            viewed: false
        )
        try TaskStore.shared.save(task)

        try TaskStore.shared.appendMessage(id: id, message: SessionMessage(type: .user, content: "Q"))
        try TaskStore.shared.appendMessage(id: id, message: SessionMessage(type: .assistant, content: "Answer 1"))
        try TaskStore.shared.appendMessage(id: id, message: SessionMessage(type: .user, content: "Follow up"))
        try TaskStore.shared.appendMessage(id: id, message: SessionMessage(type: .assistant, content: "Answer 2"))

        let response = TaskStore.shared.getLastResponse(id: id)
        XCTAssertEqual(response, "Answer 2")

        TaskStore.shared.delete(id: id)
    }

    func testGetShortPrompt_truncatesAt80() throws {
        let id = "test-short-prompt"
        let task = CCTask(
            id: id,
            workDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ccquick/\(id)").path,
            status: .running,
            startedAt: .now,
            finishedAt: nil,
            viewed: false
        )
        try TaskStore.shared.save(task)

        let longPrompt = String(repeating: "a", count: 100)
        try TaskStore.shared.appendMessage(id: id, message: SessionMessage(type: .user, content: longPrompt))

        let short = TaskStore.shared.getShortPrompt(id: id)
        XCTAssertEqual(short.count, 81) // 80 chars + "…"
        XCTAssertTrue(short.hasSuffix("…"))

        TaskStore.shared.delete(id: id)
    }

    func testGetShortPrompt_fallback() {
        XCTAssertEqual(TaskStore.shared.getShortPrompt(id: "no-prompt"), "任务")
    }

    // MARK: - updateLastAssistantMessage

    func testUpdateLastAssistantMessage() throws {
        let id = "test-update-assistant"
        let task = CCTask(
            id: id,
            workDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ccquick/\(id)").path,
            status: .running,
            startedAt: .now,
            finishedAt: nil,
            viewed: false
        )
        try TaskStore.shared.save(task)

        let streaming = SessionMessage(type: .user, content: "Q")
        try TaskStore.shared.appendMessage(id: id, message: streaming)
        let originalTs = Date(timeIntervalSince1970: 1712390400)
        try TaskStore.shared.appendMessage(id: id, message: SessionMessage(
            type: .assistant, content: "partial...", timestamp: originalTs, isStreaming: true
        ))

        try TaskStore.shared.updateLastAssistantMessage(id: id, content: "full answer")

        let loaded = TaskStore.shared.loadMessages(id: id)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[1].content, "full answer")
        XCTAssertEqual(loaded[1].isStreaming, false)
        XCTAssertEqual(loaded[1].timestamp, originalTs)

        TaskStore.shared.delete(id: id)
    }

    // MARK: - baseDir exists

    func testBaseDir_isCreated() {
        // baseDir should always exist after TaskStore init
        let dir = TaskStore.shared.baseDir
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }
}
