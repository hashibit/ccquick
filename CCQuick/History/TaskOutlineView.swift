import SwiftUI
import AppKit

/// NSOutlineView 桥接，支持单击选择 + 双击打开
final class TaskOutlineView: NSOutlineView {
    var onDoubleClick: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // 双击动作
        doubleAction = #selector(handleDoubleClick(_:))
        target = self

        // 添加一个列（必需）
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TaskColumn"))
        column.width = 300
        column.minWidth = 100
        column.maxWidth = 500
        column.resizingMask = .userResizingMask
        addTableColumn(column)

        // 行高
        rowHeight = 64
        intercellSpacing = NSSize(width: 0, height: 0)

        // 不显示列头
        headerView = nil

        // 允许空选择
        allowsEmptySelection = true

        // 单选
        allowsMultipleSelection = false

        // 选中高亮样式
        selectionHighlightStyle = .regular
    }

    @objc private func handleDoubleClick(_ sender: Any) {
        let clickedRow = self.clickedRow
        if clickedRow >= 0 {
            let item = self.item(atRow: clickedRow)
            if let task = item as? CCTask {
                onDoubleClick?(task.id)
            }
        }
    }
}

/// SwiftUI 包装
struct TaskOutlineViewWrapper: NSViewRepresentable {
    let tasks: [CCTask]
    @Binding var selectedTaskId: String?
    let onDoubleClick: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let outline = TaskOutlineView()
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.onDoubleClick = { taskId in
            onDoubleClick(taskId)
        }

        // 用 NSScrollView 包装，确保正确布局
        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // 使用标准的控制背景色
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.controlBackgroundColor

        // 保存 outline 引用到 coordinator
        context.coordinator.outlineView = outline

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outline = context.coordinator.outlineView else { return }
        context.coordinator.tasks = tasks

        // 保存当前选中
        let previousSelectedId = selectedTaskId

        outline.reloadData()

        // 恢复选中状态
        if let selectedId = previousSelectedId {
            if let task = tasks.first(where: { $0.id == selectedId }) {
                let row = outline.row(forItem: task)
                if row >= 0 && outline.selectedRow != row {
                    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
            } else {
                // 任务已被删除，清除选择
                outline.selectRowIndexes(IndexSet(), byExtendingSelection: false)
                DispatchQueue.main.async {
                    selectedTaskId = nil
                }
            }
        } else {
            outline.selectRowIndexes(IndexSet(), byExtendingSelection: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tasks: tasks, selectedId: $selectedTaskId)
    }

    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var tasks: [CCTask]
        @Binding var selectedId: String?
        weak var outlineView: TaskOutlineView?

        init(tasks: [CCTask], selectedId: Binding<String?>) {
            self.tasks = tasks
            self._selectedId = selectedId
        }

        // MARK: - DataSource

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return tasks[index]
            }
            return tasks[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            return false
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return tasks.count
            }
            return 0
        }

        func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
            return nil
        }

        // MARK: - Delegate

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let rowView = TaskRowView()
            let row = outlineView.row(forItem: item)
            rowView.setRowNumber(row)
            return rowView
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let task = item as? CCTask else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("TaskRow")
            var cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView

            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = identifier

                // 左侧状态条 - 使用更柔和的颜色
                let statusBar = NSView()
                statusBar.identifier = NSUserInterfaceItemIdentifier("StatusBar")
                statusBar.wantsLayer = true

                // 标题
                let titleField = NSTextField()
                titleField.identifier = NSUserInterfaceItemIdentifier("Title")
                titleField.isEditable = false
                titleField.isBordered = false
                titleField.drawsBackground = false
                titleField.lineBreakMode = .byTruncatingTail

                // 预览
                let previewField = NSTextField()
                previewField.identifier = NSUserInterfaceItemIdentifier("Preview")
                previewField.isEditable = false
                previewField.isBordered = false
                previewField.drawsBackground = false
                previewField.lineBreakMode = .byTruncatingTail

                // 底部信息行
                let infoField = NSTextField()
                infoField.identifier = NSUserInterfaceItemIdentifier("Info")
                infoField.isEditable = false
                infoField.isBordered = false
                infoField.drawsBackground = false

                cell?.addSubview(statusBar)
                cell?.addSubview(titleField)
                cell?.addSubview(previewField)
                cell?.addSubview(infoField)

                statusBar.translatesAutoresizingMaskIntoConstraints = false
                titleField.translatesAutoresizingMaskIntoConstraints = false
                previewField.translatesAutoresizingMaskIntoConstraints = false
                infoField.translatesAutoresizingMaskIntoConstraints = false

                NSLayoutConstraint.activate([
                    // 状态条：左侧，垂直居中
                    statusBar.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 2),
                    statusBar.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                    statusBar.widthAnchor.constraint(equalToConstant: 3),
                    statusBar.heightAnchor.constraint(equalToConstant: 36),

                    // 标题：状态条右侧
                    titleField.leadingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: 8),
                    titleField.topAnchor.constraint(equalTo: cell!.topAnchor, constant: 10),
                    titleField.trailingAnchor.constraint(lessThanOrEqualTo: cell!.trailingAnchor, constant: -12),

                    // 预览：标题下方
                    previewField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                    previewField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),
                    previewField.trailingAnchor.constraint(lessThanOrEqualTo: cell!.trailingAnchor, constant: -12),

                    // 信息行：预览下方
                    infoField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                    infoField.topAnchor.constraint(equalTo: previewField.bottomAnchor, constant: 3),
                    infoField.trailingAnchor.constraint(lessThanOrEqualTo: cell!.trailingAnchor, constant: -12),
                ])
            }

            // 更新内容
            if let statusBar = cell?.viewWithIdentifier("StatusBar") as? NSView {
                statusBar.layer?.backgroundColor = statusColor(for: task).cgColor
                statusBar.layer?.cornerRadius = 1.5
            }

            if let titleField = cell?.viewWithIdentifier("Title") as? NSTextField {
                titleField.stringValue = TaskStore.shared.getShortPrompt(id: task.id)
                titleField.font = NSFont.preferredFont(forTextStyle: .body)
                titleField.textColor = NSColor.labelColor
            }

            if let previewField = cell?.viewWithIdentifier("Preview") as? NSTextField {
                if task.status == .running {
                    previewField.stringValue = L10n.statusRunningEllipsis
                    previewField.font = NSFont.preferredFont(forTextStyle: .caption1)
                    previewField.textColor = NSColor.systemBlue
                } else {
                    let lastResponse = TaskStore.shared.getLastResponse(id: task.id) ?? ""
                    let preview = String(lastResponse.prefix(60)).replacingOccurrences(of: "\n", with: " ")
                    previewField.stringValue = preview.isEmpty ? L10n.statusNoContent : preview
                    previewField.font = NSFont.preferredFont(forTextStyle: .caption1)
                    previewField.textColor = NSColor.secondaryLabelColor
                }
            }

            if let infoField = cell?.viewWithIdentifier("Info") as? NSTextField {
                var infoText = task.startedAt.formatted(date: .abbreviated, time: .shortened)
                if task.status == .completed {
                    infoText += " · \(task.elapsedString)"
                }
                infoField.stringValue = infoText
                infoField.font = NSFont.preferredFont(forTextStyle: .caption2)
                infoField.textColor = NSColor.tertiaryLabelColor
            }

            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let row = outlineView.selectedRow
            if row >= 0 {
                let item = outlineView.item(atRow: row)
                selectedId = (item as? CCTask)?.id
            } else {
                selectedId = nil
            }
        }

        private func statusColor(for task: CCTask) -> NSColor {
            switch task.status {
            case .completed: return NSColor.systemGreen.withAlphaComponent(0.85)
            case .failed: return NSColor.systemRed.withAlphaComponent(0.85)
            case .running: return NSColor.systemBlue.withAlphaComponent(0.85)
            case .stopped: return NSColor.systemOrange.withAlphaComponent(0.85)
            }
        }
    }
}

// MARK: - 自定义行视图

class TaskRowView: NSTableRowView {
    private var rowNumber: Int = 0

    func setRowNumber(_ row: Int) {
        rowNumber = row
    }

    override func draw(_ dirtyRect: NSRect) {
        // 绘制交替行背景（奇数行有浅色背景）
        if !isSelected && rowNumber % 2 == 1 {
            NSColor.controlBackgroundColor.withAlphaComponent(0.5).setFill()
            bounds.fill()
        }

        // 绘制选中背景
        if isSelected {
            NSColor.selectedContentBackgroundColor.setFill()
            let selectionRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            let path = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4)
            path.fill()
        }

        super.draw(dirtyRect)
    }
}

// MARK: - NSTableCellView 扩展

extension NSTableCellView {
    func viewWithIdentifier(_ identifier: String) -> NSView? {
        return subviews.first { $0.identifier?.rawValue == identifier }
    }
}