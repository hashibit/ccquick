import SwiftUI

@main
struct CCQuickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 用 Settings 托管 HistoryWindowLauncher，监听打开历史窗口的通知
        Settings {
            HistoryWindowLauncher()
        }

        // 历史窗口用 SwiftUI Window scene 管理，toolbar 完全由 SwiftUI 处理
        Window("历史记录", id: "history") {
            HistoryView()
        }
        .defaultSize(width: 1000, height: 680)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
    }
}

/// AppKit → SwiftUI 桥接：监听通知后用 openWindow 打开历史窗口
struct HistoryWindowLauncher: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openHistoryWindow)) { _ in
                openWindow(id: "history")
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
