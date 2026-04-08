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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logManager.logs) { entry in
                            HStack(alignment: .top, spacing: 4) {
                                Text(entry.formattedTime)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Text("[\(entry.level.rawValue)]")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(levelColor(entry.level))
                                Text("[\(entry.category)]")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .id(entry.id)
                        }
                    }
                }
                .onChange(of: logManager.logs.count) {
                    if autoScroll, let last = logManager.logs.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func levelColor(_ level: LogManager.LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .tool: return .purple
        case .warning: return .orange
        case .error: return .red
        }
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

    private func makeIcon(running: Bool, frame: Int, badgeCount: Int) -> NSImage? {
        // 根据状态选择图标
        let imageName: String
        if running {
            // 忙碌时：airplane.path.dotted 和 airplane 交替动画
            let frames = ["TrayIconPathDotted", "TrayIconAirplane"]
            imageName = frames[frame % frames.count]
        } else if badgeCount > 0 {
            imageName = "TrayIconCloud"
        } else {
            imageName = "TrayIconLanded"
        }

        let image = NSImage(named: imageName)
        image?.isTemplate = true
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
        // 直接打开独立任务详情窗口
        let controller = TaskDetailWindowController(taskId: taskId)
        controller.show()
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
