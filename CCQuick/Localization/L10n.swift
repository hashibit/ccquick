import Foundation

// MARK: - Localized Strings

enum L10n {
    // MARK: - Menu
    static let menuInvoke = NSLocalizedString("menu.invoke", comment: "")
    static let menuSessions = NSLocalizedString("menu.sessions", comment: "")
    static let menuSettings = NSLocalizedString("menu.settings", comment: "")
    static let menuQuit = NSLocalizedString("menu.quit", comment: "")
    static func menuRunningCount(_ count: Int) -> String {
        String(format: NSLocalizedString("menu.running_count", comment: ""), count)
    }
    static func menuUnviewedCount(_ count: Int) -> String {
        String(format: NSLocalizedString("menu.unviewed_count", comment: ""), count)
    }

    // MARK: - Log Window
    static let logTitle = NSLocalizedString("log.title", comment: "")
    static let logAutoScroll = NSLocalizedString("log.auto_scroll", comment: "")
    static let logClear = NSLocalizedString("log.clear", comment: "")
    static let logCopyAll = NSLocalizedString("log.copy_all", comment: "")

    // MARK: - Input
    static let inputPlaceholder = NSLocalizedString("input.placeholder", comment: "")

    // MARK: - Sessions (History)
    static let sessionsTitle = NSLocalizedString("sessions.title", comment: "")
    static let sessionsSearch = NSLocalizedString("sessions.search", comment: "")
    static let sessionsDelete = NSLocalizedString("sessions.delete", comment: "")
    static let sessionsDeleteHelp = NSLocalizedString("sessions.delete_help", comment: "")
    static let sessionsSelectRecord = NSLocalizedString("sessions.select_record", comment: "")
    static func sessionsCreateHint(_ hotkey: String) -> String {
        String(format: NSLocalizedString("sessions.create_hint", comment: ""), hotkey)
    }
    static let sessionsNew = NSLocalizedString("sessions.new", comment: "")

    // MARK: - Task
    static let taskDetailTitle = NSLocalizedString("task.detail_title", comment: "")
    static let taskStop = NSLocalizedString("task.stop", comment: "")
    static let taskStopHelp = NSLocalizedString("task.stop_help", comment: "")
    static let taskCopy = NSLocalizedString("task.copy", comment: "")
    static let taskCopyHelp = NSLocalizedString("task.copy_help", comment: "")
    static let taskFolder = NSLocalizedString("task.folder", comment: "")
    static let taskFolderHelp = NSLocalizedString("task.folder_help", comment: "")
    static let taskTyping = NSLocalizedString("task.typing", comment: "")
    static let taskFollowUp = NSLocalizedString("task.follow_up", comment: "")
    static let taskSend = NSLocalizedString("task.send", comment: "")
    static let taskNoOutput = NSLocalizedString("task.no_output", comment: "")
    static func taskElapsed(_ time: String) -> String {
        String(format: NSLocalizedString("task.elapsed", comment: ""), time)
    }
    static let taskFallbackName = NSLocalizedString("task.fallback_name", comment: "")

    // MARK: - Status
    static let statusCompleted = NSLocalizedString("status.completed", comment: "")
    static let statusFailed = NSLocalizedString("status.failed", comment: "")
    static let statusRunning = NSLocalizedString("status.running", comment: "")
    static let statusStopped = NSLocalizedString("status.stopped", comment: "")
    static let statusRunningEllipsis = NSLocalizedString("status.running_ellipsis", comment: "")
    static let statusNoContent = NSLocalizedString("status.no_content", comment: "")

    // MARK: - Task Groups
    static let groupAll = NSLocalizedString("group.all", comment: "")
    static let groupRunning = NSLocalizedString("group.running", comment: "")
    static let groupCompleted = NSLocalizedString("group.completed", comment: "")
    static let groupFailed = NSLocalizedString("group.failed", comment: "")
    static let groupStopped = NSLocalizedString("group.stopped", comment: "")

    // MARK: - Notifications
    static let notificationCompleted = NSLocalizedString("notification.completed", comment: "")
    static let notificationCompletedBody = NSLocalizedString("notification.completed_body", comment: "")

    // MARK: - Settings
    static let settingsTitle = NSLocalizedString("settings.title", comment: "")
    static let settingsEngine = NSLocalizedString("settings.engine", comment: "")
    static let settingsAccount = NSLocalizedString("settings.account", comment: "")
    static let settingsApiKeyPlaceholder = NSLocalizedString("settings.api_key_placeholder", comment: "")
    static let settingsApiKeyHint = NSLocalizedString("settings.api_key_hint", comment: "")
    static let settingsClaudeHint = NSLocalizedString("settings.claude_hint", comment: "")
    static let settingsChecking = NSLocalizedString("settings.checking", comment: "")
    static let settingsCheckAvailability = NSLocalizedString("settings.check_availability", comment: "")
    static let settingsHotkey = NSLocalizedString("settings.hotkey", comment: "")
    static let settingsOpenInput = NSLocalizedString("settings.open_input", comment: "")
    static let settingsOpenSessions = NSLocalizedString("settings.open_sessions", comment: "")
    static let settingsOpenSettings = NSLocalizedString("settings.open_settings", comment: "")
    static let settingsMenuLabel = NSLocalizedString("settings.menu_label", comment: "")
    static let settingsBehavior = NSLocalizedString("settings.behavior", comment: "")
    static let settingsNotifications = NSLocalizedString("settings.notifications", comment: "")
    static let settingsAppearance = NSLocalizedString("settings.appearance", comment: "")
    static let settingsTheme = NSLocalizedString("settings.theme", comment: "")
    static let settingsPressHotkey = NSLocalizedString("settings.press_hotkey", comment: "")
    static let settingsApiKeyEmpty = NSLocalizedString("settings.api_key_empty", comment: "")
    static let settingsUsingCli = NSLocalizedString("settings.using_cli", comment: "")

    // MARK: - Appearance
    static let appearanceSystem = NSLocalizedString("appearance.system", comment: "")
    static let appearanceLight = NSLocalizedString("appearance.light", comment: "")
    static let appearanceDark = NSLocalizedString("appearance.dark", comment: "")

    // MARK: - Execution Account
    static let accountClaude = NSLocalizedString("account.claude", comment: "")
    static let accountCodingPlan = NSLocalizedString("account.coding_plan", comment: "")

    // MARK: - Toolbar
    static let toolbarCopyPlain = NSLocalizedString("toolbar.copy_plain", comment: "")
    static let toolbarCopyMarkdown = NSLocalizedString("toolbar.copy_markdown", comment: "")
}
