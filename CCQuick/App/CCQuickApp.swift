import SwiftUI

@main
struct CCQuickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // 在应用启动时立即隐藏 SwiftUI 创建的窗口
        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                window.orderOut(nil)
            }
        }
    }

    var body: some Scene {
        // 不需要任何 Scene，完全使用 AppKit
        // 但 SwiftUI 要求至少一个 Scene，所以创建一个隐藏的
        WindowGroup {
            Color.clear
                .frame(width: 1, height: 1)
                .onAppear {
                    if let window = NSApp.windows.first {
                        window.orderOut(nil)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
