import SwiftUI

@main
struct CCQuickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 使用 Settings 而非 WindowGroup，不会创建默认窗口
        Settings {
            EmptyView()
        }
    }
}

private struct EmptyView: View {
    var body: some View {
        // 空视图，不会显示
        Color.clear.frame(width: 0, height: 0)
    }
}