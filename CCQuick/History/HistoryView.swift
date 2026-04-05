import SwiftUI

extension Notification.Name {
    static let selectHistoryTask = Notification.Name("selectHistoryTask")
}

struct HistoryView: View {
    @ObservedObject private var taskManager = TaskManager.shared
    @State private var tasks: [CCTask] = []
    @State private var searchText = ""
    @State private var selectedTaskId: String?
    @State private var sidebarWidth: CGFloat = 280
    @State private var isSidebarCollapsed = false

    var filtered: [CCTask] {
        guard !searchText.isEmpty else { return tasks }
        return tasks.filter { $0.prompt.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HSplitView {
            // 侧边栏
            if !isSidebarCollapsed {
                sidebar
                    .frame(minWidth: 200, idealWidth: sidebarWidth, maxWidth: 400)
            }

            // 详情
            detailView
                .frame(minWidth: 400)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    // 搜索框
                    TextField("搜索", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                    // 侧边栏切换
                    Button {
                        withAnimation { isSidebarCollapsed.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help(isSidebarCollapsed ? "显示侧边栏" : "隐藏侧边栏")

                    // 新建任务
                    Button {
                        InputWindowController.shared.show()
                    } label: {
                        Label("新建任务", systemImage: "square.and.pencil")
                    }
                    .help("新建任务 (⌘⇧Space)")
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: taskManager.runningTasks.count) { _ in reload() }
        .onChange(of: taskManager.unviewedTasks.count) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .selectHistoryTask)) { notif in
            guard let taskId = notif.userInfo?["taskId"] as? String else { return }
            reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                selectedTaskId = taskId
                if isSidebarCollapsed { isSidebarCollapsed = false }
            }
        }
    }

    private var sidebar: some View {
        List(filtered, selection: $selectedTaskId) { task in
            HistoryRow(task: task)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let taskId = selectedTaskId {
            TaskDetailView(taskId: taskId)
                .id(taskId)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("选择一条记录查看详情")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reload() {
        let fromDisk = TaskStore.shared.loadAll()
        let runningNotOnDisk = taskManager.runningTasks.filter { r in
            !fromDisk.contains { $0.id == r.id }
        }
        tasks = (runningNotOnDisk + fromDisk).sorted { $0.startedAt > $1.startedAt }
    }
}

// MARK: - 任务详情（含追问）

struct TaskDetailView: View {
    let taskId: String
    @State private var task: CCTask?
    @State private var followUpText = ""
    @ObservedObject private var taskManager = TaskManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if let t = task {
                ResultView(task: t)

                Divider()

                HStack(spacing: 10) {
                    if t.status == .running {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("运行中，请稍候…")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    } else {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(.secondary)
                        TextField("继续追问…", text: $followUpText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { submitFollowUp() }
                        Button("发送") { submitFollowUp() }
                            .disabled(followUpText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(12)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { refresh() }
        .onChange(of: taskId) { _ in refresh() }
        .onChange(of: taskManager.runningTasks) { _ in refresh() }
        .onChange(of: taskManager.unviewedTasks) { _ in refresh() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if task?.status == .running { refresh() }
        }
    }

    private func refresh() {
        if let running = taskManager.runningTasks.first(where: { $0.id == taskId }) {
            task = running
        } else if let fromDisk = TaskStore.shared.load(id: taskId) {
            task = fromDisk
            if fromDisk.status == .completed && !fromDisk.viewed {
                taskManager.markViewed(taskId: taskId)
            }
        }
    }

    private func submitFollowUp() {
        guard let t = task, t.status != .running else { return }
        let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let responsePreview = String(t.response.prefix(2000))
        let prompt = """
        【上下文】原始需求：\(t.prompt)

        【Claude 的回复】
        \(responsePreview)

        ---

        【追问】\(text)
        """
        TaskManager.shared.submit(prompt: prompt)
        followUpText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: .selectHistoryTask,
                object: nil,
                userInfo: ["taskId": TaskManager.shared.runningTasks.last?.id ?? ""]
            )
        }
    }
}

// MARK: - 列表行

struct HistoryRow: View {
    let task: CCTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.shortPrompt)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 6) {
                statusDot
                Text(task.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if task.status == .completed {
                    Text("· \(task.elapsedString)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if task.status == .running {
                    Text("运行中…")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusDot: some View {
        switch task.status {
        case .completed: Circle().fill(.green).frame(width: 6, height: 6)
        case .failed:    Circle().fill(.red).frame(width: 6, height: 6)
        case .running:   Circle().fill(.blue).frame(width: 6, height: 6)
        }
    }
}