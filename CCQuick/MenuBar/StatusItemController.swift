import AppKit
import SwiftUI

// MARK: - 日志窗口

class LogWindowController: NSObject {
    static let shared = LogWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = LogView()
            let hostingView = NSHostingView(rootView: view)
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "日志"
            newWindow.center()
            newWindow.minSize = NSSize(width: 500, height: 300)
            newWindow.contentView = hostingView
            newWindow.delegate = self
            window = newWindow
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 显示 Dock 图标
        NSApp.setActivationPolicy(.regular)
    }

    private func checkHideDockIcon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible &&
                window.styleMask.contains(.titled) &&
                window !== self.window
            }
            if !hasVisibleWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

extension LogWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        checkHideDockIcon()
    }
}

struct LogView: View {
    @ObservedObject var logManager = LogManager.shared
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("自动滚动", isOn: $autoScroll)
                Spacer()
                Button("清空") { logManager.clear() }
                Button("复制全部") {
                    let text = logManager.logs.map { "[\($0.formattedTime)][\($0.level.rawValue)][\($0.category)] \($0.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

//            ScrollViewReader { proxy in
//                SelectableTextView(logManager: logManager)
//                    .onChange(of: logManager.logs.count) { _, _ in
//                        if autoScroll, let last = logManager.logs.last {
//                            proxy.scrollTo(last.id, anchor: .bottom)
//                        }
//                    }
//            }

        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - StatusItemController

@MainActor
class StatusItemController {
    private let statusItem: NSStatusItem
    let taskManager = TaskManager.shared
    private var animationTimer: Timer?
    private var animationFrame = 0

    // 结果查看窗口
    private var resultController: ResultWindowController?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        updateIcon()
    }

    func startObserving() {
        // 使用 Observation 框架的 withObservationTracking 来监听变化
        Task {
            while true {
                withObservationTracking {
                    _ = taskManager.runningTasks
                    _ = taskManager.unviewedTasks
                } onChange: { [weak self] in
                    Task { @MainActor in
                        self?.onStateChanged()
                    }
                }
                // 等待变化触发后继续
                try? await Task.sleep(for: .seconds(0.1))
            }
        }

        taskManager.onTaskCompleted = { [weak self] task in
            NotificationService.shared.notify(task: task)
            self?.updateIcon()
        }
    }

    private func onStateChanged() {
        if taskManager.hasRunning {
            startAnimation()
        } else {
            stopAnimation()
        }
        updateIcon()
    }

    // MARK: - Icon

    private func updateIcon() {
        let isRunning = taskManager.hasRunning
        let count = taskManager.unviewedCount
        statusItem.button?.image = makeIcon(running: isRunning, frame: animationFrame, badgeCount: count)
    }

    private func makeIcon(running: Bool, frame: Int, badgeCount: Int) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            // 基础图标
            let symbolName: String
            if running {
                // 用不同帧模拟旋转动画
                let frames = [
                    "arrow.clockwise.circle",
                    "arrow.clockwise.circle.fill",
                    "arrow.clockwise.circle",
                    "arrow.clockwise.circle.fill"
                ]
                symbolName = frames[frame % frames.count]
            } else {
                symbolName = "bolt.fill"
            }

            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                symbol.draw(in: NSRect(x: 2, y: 2, width: 14, height: 14))
            }

            // Badge 数字
            if badgeCount > 0 {
                let badgeRect = NSRect(x: 13, y: 13, width: 9, height: 9)
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: badgeRect).fill()

                let str = badgeCount > 9 ? "9+" : "\(badgeCount)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 6),
                    .foregroundColor: NSColor.white
                ]
                let attrStr = NSAttributedString(string: str, attributes: attrs)
                let strSize = attrStr.size()
                attrStr.draw(at: NSPoint(
                    x: badgeRect.midX - strSize.width / 2,
                    y: badgeRect.midY - strSize.height / 2
                ))
            }
            return true
        }
        // 始终使用 template，让系统自动适配颜色（浅色模式白色，深色模式黑色）
        image.isTemplate = true
        return image
    }

    // MARK: - Animation

    private func startAnimation() {
        guard animationTimer == nil else { return }

        // 检查用户是否启用了 Reduce Motion
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            updateIcon()
            return
        }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationFrame += 1
            self.updateIcon()
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrame = 0
        updateIcon()
    }

    // MARK: - Menu

    @objc private func statusItemClicked() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 快速输入入口（备用）
        let inputItem = NSMenuItem(title: "快速输入…", action: #selector(showInput), keyEquivalent: "")
        inputItem.target = self
        menu.addItem(inputItem)

        // 快捷键状态
        let hotkeyStr = AppSettings.hotkeyDisplayString
        let hotkeyItem = NSMenuItem(
            title: "快捷键 \(hotkeyStr)",
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)

        menu.addItem(.separator())

        // 正在执行的任务
        let running = taskManager.runningTasks
        if !running.isEmpty {
            let header = NSMenuItem(title: "正在执行 (\(running.count))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for task in running {
                let item = NSMenuItem(
                    title: "  \(task.shortPrompt)  [\(task.elapsedString)]",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        // 已完成待查看
        let unviewed = taskManager.unviewedTasks
        if !unviewed.isEmpty {
            let header = NSMenuItem(title: "已完成，待查看 (\(unviewed.count))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for task in unviewed {
                let item = NSMenuItem(
                    title: "  \(task.shortPrompt)",
                    action: #selector(viewResult(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = task.id
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        // 历史记录
        let historyItem = NSMenuItem(title: "历史记录…", action: #selector(showHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        // 设置
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 日志
        let logItem = NSMenuItem(title: "日志…", action: #selector(showLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 CCQuick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        return menu
    }

    @objc private func showInput() {
        InputWindowController.shared.show()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func viewResult(_ sender: NSMenuItem) {
        guard let taskId = sender.representedObject as? String else { return }
        showResult(for: taskId)
    }

    func showResult(for taskId: String) {
        taskManager.markViewed(taskId: taskId)
        updateIcon()
        HistoryWindowController.shared.show(selectingTaskId: taskId)
    }

    @objc private func showHistory() {
        HistoryWindowController.shared.show()
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func showLog() {
        LogWindowController.shared.show()
    }
}
