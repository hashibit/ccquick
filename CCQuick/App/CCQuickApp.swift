import SwiftUI

@main
struct CCQuickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 空的 WindowGroup，仅用于满足 SwiftUI 需要至少一个 Scene 的要求
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}
