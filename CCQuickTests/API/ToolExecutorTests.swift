import XCTest
@testable import CCQuick

final class ToolExecutorTests: XCTestCase {

    // MARK: - Note
    // ToolExecutor and ToolError are private in APIClient, so we can't test them directly.
    // We test the public APIClientError enum and TaskRunner's findClaudePath.

    // MARK: - Claude path detection

    func testTaskRunner_findClaudePath_returnsOptional() {
        // findClaudePath should not crash, returns nil or a path
        let path = TaskRunner.findClaudePath()
        // On a dev machine this may or may not exist; just verify it doesn't crash
        if let p = path {
            XCTAssertTrue(FileManager.default.fileExists(atPath: p))
        }
    }

    // MARK: - APIClientError descriptions

    func testAPIClientErrorDescriptions() {
        XCTAssertEqual(APIClientError.invalidResponse.errorDescription, "无效的响应")
        XCTAssertEqual(APIClientError.invalidJSON.errorDescription, "无效的 JSON 格式")
        XCTAssertEqual(APIClientError.invalidContent.errorDescription, "无法解析响应内容")
        XCTAssertEqual(APIClientError.maxToolUseRounds.errorDescription, "工具调用轮数超过上限")

        let httpErr = APIClientError.httpError(statusCode: 401, message: "Unauthorized")
        XCTAssertTrue(httpErr.errorDescription?.contains("401") == true)
        XCTAssertTrue(httpErr.errorDescription?.contains("Unauthorized") == true)
    }

    func testAPIClientError_localizedDescription() {
        let httpErr = APIClientError.httpError(statusCode: 429, message: "Rate limited")
        XCTAssertTrue(httpErr.localizedDescription.contains("429"))
    }

    func testAPIClientError_isLocalized() {
        for error in [
            APIClientError.invalidResponse,
            APIClientError.invalidJSON,
            APIClientError.invalidContent,
            APIClientError.maxToolUseRounds,
            APIClientError.httpError(statusCode: 500, message: "Server error")
        ] {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error) has empty description")
        }
    }
}
