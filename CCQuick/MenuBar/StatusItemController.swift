import AppKit
import Combine

class StatusItemController {
    private let statusItem: NSStatusItem
    let taskManager = TaskManager.shared
    private var cancellables = Set<AnyCancellable>()
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
        taskManager.$runningTasks
            .combineLatest(taskManager.$unviewedTasks)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running, unviewed in
                self?.onStateChanged(running: running, unviewed: unviewed)
            }
            .store(in: &cancellables)

        taskManager.onTaskCompleted = { [weak self] task in
            NotificationService.shared.notify(task: task)
            self?.updateIcon()
        }
    }

    private func onStateChanged(running: [CCTask], unviewed: [CCTask]) {
        if running.isEmpty {
            stopAnimation()
        } else {
            startAnimation()
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
        image.isTemplate = (badgeCount == 0 && !running)
        return image
    }

    // MARK: - Animation

    private func startAnimation() {
        guard animationTimer == nil else { return }
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
        let historyItem = NSMenuItem(title: "历史记录…", action: #selector(showHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        // 设置
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 CCQuick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
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
}
