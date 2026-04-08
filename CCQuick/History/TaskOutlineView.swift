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

        // source list 样式
        style = .sourceList

        // 行高
        rowHeight = 56
        intercellSpacing = NSSize(width: 0, height: 0)

        // 不显示列头
        headerView = nil

        // 允许空选择
        allowsEmptySelection = true

        // 单选
        allowsMultipleSelection = false
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
        scrollView.drawsBackground = false

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
            // 根节点返回任务列表中的项
            if item == nil {
                return tasks[index]
            }
            return tasks[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            return false
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            // 根节点返回任务数量
            if item == nil {
                return tasks.count
            }
            return 0
        }

        func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
            return nil
        }

        // MARK: - Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let task = item as? CCTask else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("TaskRow")
            var cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView

            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = identifier

                // 左侧状态条
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

                // 日期
                let dateField = NSTextField()
                dateField.identifier = NSUserInterfaceItemIdentifier("Date")
                dateField.isEditable = false
                dateField.isBordered = false
                dateField.drawsBackground = false

                cell?.addSubview(statusBar)
                cell?.addSubview(titleField)
                cell?.addSubview(previewField)
                cell?.addSubview(dateField)

                statusBar.translatesAutoresizingMaskIntoConstraints = false
                titleField.translatesAutoresizingMaskIntoConstraints = false
                previewField.translatesAutoresizingMaskIntoConstraints = false
                dateField.translatesAutoresizingMaskIntoConstraints = false

                NSLayoutConstraint.activate([
                    statusBar.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                    statusBar.topAnchor.constraint(equalTo: cell!.topAnchor, constant: 6),
                    statusBar.bottomAnchor.constraint(equalTo: cell!.bottomAnchor, constant: -6),
                    statusBar.widthAnchor.constraint(equalToConstant: 4),

                    titleField.leadingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: 12),
                    titleField.topAnchor.constraint(equalTo: cell!.topAnchor, constant: 6),
                    titleField.trailingAnchor.constraint(lessThanOrEqualTo: cell!.trailingAnchor, constant: -8),

                    previewField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                    previewField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
                    previewField.trailingAnchor.constraint(lessThanOrEqualTo: cell!.trailingAnchor, constant: -8),

                    dateField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                    dateField.topAnchor.constraint(equalTo: previewField.bottomAnchor, constant: 2),
                    dateField.trailingAnchor.constraint(lessThanOrEqualTo: cell!.trailingAnchor, constant: -8),
                ])
            }

            // 更新内容
            if let statusBar = cell?.viewWithIdentifier("StatusBar") as? NSView {
                statusBar.layer?.backgroundColor = statusColor(for: task).cgColor
                statusBar.layer?.cornerRadius = 2
            }

            if let titleField = cell?.viewWithIdentifier("Title") as? NSTextField {
                titleField.stringValue = task.shortPrompt
                titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
                titleField.textColor = NSColor.labelColor
            }

            if let previewField = cell?.viewWithIdentifier("Preview") as? NSTextField {
                if task.status == .running {
                    previewField.stringValue = "运行中..."
                    previewField.font = NSFont.systemFont(ofSize: 11)
                    previewField.textColor = NSColor.systemBlue
                } else {
                    let preview = String(task.response.prefix(60)).replacingOccurrences(of: "\n", with: " ")
                    previewField.stringValue = preview.isEmpty ? "无响应内容" : preview
                    previewField.font = NSFont.systemFont(ofSize: 11)
                    previewField.textColor = NSColor.secondaryLabelColor
                }
            }

            if let dateField = cell?.viewWithIdentifier("Date") as? NSTextField {
                dateField.stringValue = task.startedAt.formatted(date: .abbreviated, time: .shortened)
                dateField.font = NSFont.systemFont(ofSize: 10)
                dateField.textColor = NSColor.tertiaryLabelColor
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
            case .completed: return NSColor.systemGreen
            case .failed: return NSColor.systemRed
            case .running: return NSColor.systemBlue
            }
        }
    }
}

// MARK: - NSTableCellView 扩展

extension NSTableCellView {
    func viewWithIdentifier(_ identifier: String) -> NSView? {
        return subviews.first { $0.identifier?.rawValue == identifier }
    }
}