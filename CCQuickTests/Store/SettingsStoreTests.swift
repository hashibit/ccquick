import XCTest
import Carbon
@testable import CCQuick

final class SettingsStoreTests: XCTestCase {

    func testDefaultValues() {
        let defaults = AppSettings()
        XCTAssertEqual(defaults.executionAccount, .claudeSubscription)
        XCTAssertEqual(defaults.codingPlanApiKey, "")
        XCTAssertEqual(defaults.hotkeyModifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(defaults.hotkeyKeyCode, 49) // Space
        XCTAssertEqual(defaults.appearance, .system)
    }

    func testHotkeyDisplayString_default() {
        // Default: cmd+shift+space
        let settings = AppSettings(
            executionAccount: .claudeSubscription,
            codingPlanApiKey: "",
            hotkeyModifiers: UInt32(cmdKey | shiftKey),
            hotkeyKeyCode: 49,
            appearance: .system
        )
        AppSettings.save(settings)

        let display = AppSettings.hotkeyDisplayString
        XCTAssertTrue(display.contains("⌘"))
        XCTAssertTrue(display.contains("⇧"))
        XCTAssertTrue(display.contains("Space"))

        // Restore defaults
        AppSettings.save(AppSettings())
    }

    func testHotkeyDisplayString_customKey() {
        let settings = AppSettings(
            executionAccount: .claudeSubscription,
            codingPlanApiKey: "",
            hotkeyModifiers: UInt32(cmdKey),
            hotkeyKeyCode: 0, // 'A'
            appearance: .system
        )
        AppSettings.save(settings)

        XCTAssertEqual(AppSettings.hotkeyDisplayString, "⌘A")

        AppSettings.save(AppSettings())
    }

    func testHotkeyDisplayString_allModifiers() {
        let settings = AppSettings(
            executionAccount: .claudeSubscription,
            codingPlanApiKey: "",
            hotkeyModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey),
            hotkeyKeyCode: 49,
            appearance: .system
        )
        AppSettings.save(settings)

        let display = AppSettings.hotkeyDisplayString
        XCTAssertTrue(display.contains("⌘"))
        XCTAssertTrue(display.contains("⇧"))
        XCTAssertTrue(display.contains("⌥"))
        XCTAssertTrue(display.contains("⌃"))
        XCTAssertTrue(display.contains("Space"))

        AppSettings.save(AppSettings())
    }

    func testAppAppearance_displayNames() {
        XCTAssertEqual(AppAppearance.system.displayName, "跟随系统")
        XCTAssertEqual(AppAppearance.light.displayName, "浅色")
        XCTAssertEqual(AppAppearance.dark.displayName, "深色")
    }

    func testAppAppearance_colorScheme() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testExecutionAccount_displayNames() {
        XCTAssertEqual(ExecutionAccount.claudeSubscription.displayName, "默认 Claude 订阅")
        XCTAssertEqual(ExecutionAccount.codingPlan.displayName, "CodingPlan 订阅")
    }

    func testAppSettings_saveLoadRoundtrip() throws {
        let settings = AppSettings(
            executionAccount: .codingPlan,
            codingPlanApiKey: "sk-test-key",
            hotkeyModifiers: UInt32(cmdKey | optionKey),
            hotkeyKeyCode: 13, // 'W'
            appearance: .dark
        )

        AppSettings.save(settings)

        let loaded = AppSettings.current
        XCTAssertEqual(loaded.executionAccount, .codingPlan)
        XCTAssertEqual(loaded.codingPlanApiKey, "sk-test-key")
        XCTAssertEqual(loaded.hotkeyModifiers, UInt32(cmdKey | optionKey))
        XCTAssertEqual(loaded.hotkeyKeyCode, 13)
        XCTAssertEqual(loaded.appearance, .dark)

        // Restore
        AppSettings.save(AppSettings())
    }
}
