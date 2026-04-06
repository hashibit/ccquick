import SwiftUI

extension Notification.Name {
    static let selectHistoryTask = Notification.Name("selectHistoryTask")
}

// MARK: - 分组枚举

enum TaskGroup: String, CaseIterable, Identifiable {
    case all = "全部"
    case running = "运行中"
    case completed = "已完成"
    case failed = "失败"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "tray.full.fill"
        case .running: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: return .accentColor
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - 主视图

struct HistoryView: View {
    @ObservationIgnored @Bindable private var taskManager = TaskManager.shared
    @State private var tasks: [CCTask] = []
    @State private var searchText = ""
    @State private var filteredTasks: [CCTask] = []
    @State private var selectedTaskId: String?
    @State private var selectedGroup: TaskGroup = .all

    // 布局状态
    @State private var sidebarWidth: CGFloat = 220
    @State private var listWidth: CGFloat = 320
    @State private var isSidebarCollapsed: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // 拖拽状态
    @State private var sidebarDragOffset: CGFloat = 0
    @State private var listDragOffset: CGFloat = 0

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 左侧分组侧边栏
            groupSidebar
        } content: {
            // 中间任务列表
            taskList
        } detail: {
            // 右侧详情
            detailView
                .background(Color(NSColor.textBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新建任务", systemImage: "square.and.pencil") {
                    InputWindowController.shared.show()
                }
                .help("新建任务 (⌘⇧Space)")
            }
        }
        .onAppear {
            loadLayoutConfig()
            reload()
        }
        .onChange(of: taskManager.runningTasks.count) { reload() }
        .onChange(of: taskManager.unviewedTasks.count) { reload() }
        .onChange(of: searchText) { updateFilteredTasks() }
        .onChange(of: selectedGroup) { updateFilteredTasks() }
        .onReceive(NotificationCenter.default.publisher(for: .selectHistoryTask)) { notif in
            guard let taskId = notif.userInfo?["taskId"] as? String else { return }
            reload()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                selectedTaskId = taskId
                if columnVisibility != .all {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        columnVisibility = .all
                    }
                }
            }
        }
    }

    // MARK: - 分组侧边栏

    private var groupSidebar: some View {
        List(selection: $selectedGroup) {
            Section {
                ForEach(TaskGroup.allCases) { group in
                    Label {
                        HStack {
                            Text(group.rawValue)
                            Spacer()
                            Text("\(countForGroup(group))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    } icon: {
                        Image(systemName: group.icon)
                            .foregroundStyle(group.color)
                    }
                    .tag(group)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索")
    }

    // MARK: - 任务列表

    private var taskList: some View {
        List(selection: $selectedTaskId) {
            ForEach(filteredTasks) { task in
                TaskRow(task: task)
                    .tag(task.id)
            }
            .onDelete { indexSet in
                deleteTasks(at: indexSet)
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.enabled)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("删除", systemImage: "trash") {
                    if let selectedId = selectedTaskId {
                        deleteTask(id: selectedId)
                    }
                }
                .disabled(selectedTaskId == nil)
                .help("删除选中任务")
            }
        }
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            let task = filteredTasks[index]
            deleteTask(id: task.id)
        }
    }

    private func deleteTask(id: String) {
        // 从磁盘删除
        TaskStore.shared.delete(id: id)
        // 从列表移除
        tasks.removeAll { $0.id == id }
        filteredTasks.removeAll { $0.id == id }
        // 清除选择
        if selectedTaskId == id {
            selectedTaskId = nil
        }
    }

    // MARK: - 详情视图

    @ViewBuilder
    private var detailView: some View {
        if let taskId = selectedTaskId {
            TaskDetailView(taskId: taskId)
                .id(taskId)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.quaternary)
                VStack(spacing: 4) {
                    Text("选择一条记录")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("或按 ⌘⇧Space 创建新任务")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    // MARK: - 辅助方法

    private func loadLayoutConfig() {
        let defaults = UserDefaults.standard
        sidebarWidth = CGFloat(defaults.double(forKey: "sidebarWidth"))
        if sidebarWidth < 180 { sidebarWidth = 220 }
        listWidth = CGFloat(defaults.double(forKey: "listWidth"))
        if listWidth < 280 { listWidth = 320 }
        columnVisibility = defaults.bool(forKey: "isSidebarCollapsed") ? .detailOnly : .all
    }

    private func saveLayoutConfig() {
        let defaults = UserDefaults.standard
        defaults.set(sidebarWidth, forKey: "sidebarWidth")
        defaults.set(listWidth, forKey: "listWidth")
        defaults.set(columnVisibility != .all, forKey: "isSidebarCollapsed")
    }

    private func countForGroup(_ group: TaskGroup) -> Int {
        switch group {
        case .all: return tasks.count
        case .running: return tasks.filter { $0.status == .running }.count
        case .completed: return tasks.filter { $0.status == .completed }.count
        case .failed: return tasks.filter { $0.status == .failed }.count
        }
    }

    private func reload() {
        let fromDisk = TaskStore.shared.loadAll()
        let runningNotOnDisk = taskManager.runningTasks.filter { r in
            !fromDisk.contains { $0.id == r.id }
        }
        tasks = (runningNotOnDisk + fromDisk).sorted { $0.startedAt > $1.startedAt }
        updateFilteredTasks()
    }

    private func updateFilteredTasks() {
        var result = tasks

        // 按分组过滤
        switch selectedGroup {
        case .all: break
        case .running: result = result.filter { $0.status == .running }
        case .completed: result = result.filter { $0.status == .completed }
        case .failed: result = result.filter { $0.status == .failed }
        }

        // 按搜索文本过滤
        if !searchText.isEmpty {
            result = result.filter { $0.prompt.localizedStandardContains(searchText) }
        }

        filteredTasks = result
    }
}

// MARK: - 任务行（类似备忘录列表项）

struct TaskRow: View {
    let task: CCTask

    private var statusColor: Color {
        switch task.status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 左侧状态颜色条
            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                // 标题
                Text(task.shortPrompt)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                // 预览或状态
                if task.status == .running {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("运行中...")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                } else if !task.response.isEmpty {
                    Text(String(task.response.prefix(60)).replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // 日期
                HStack(spacing: 6) {
                    Text(task.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if task.status == .completed {
                        Text("· \(task.elapsedString)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - 任务详情视图

struct TaskDetailView: View {
    let taskId: String
    @State private var task: CCTask?
    @State private var followUpText = ""
    @ObservationIgnored @Bindable private var taskManager = TaskManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if let t = task {
                // 头部信息区
                headerView(task: t)

                Divider()

                // 内容区
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(taskContent(t.response))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider()

                // 底部追问区
                followUpBar(task: t)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear { refresh() }
        .onChange(of: taskId) { refresh() }
        .onChange(of: taskManager.runningTasks) { refresh() }
        .onChange(of: taskManager.unviewedTasks) { refresh() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if task?.status == .running { refresh() }
        }
    }

    // MARK: - 头部视图

    private func headerView(task: CCTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 状态和时间
            HStack(spacing: 12) {
                statusLabel(task: task)

                Spacer()

                if let finished = task.finishedAt {
                    Text(finished.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if task.status == .completed {
                    Text("耗时 \(task.elapsedString)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // 原始提示
            Text(task.prompt)
                .font(.headline)
                .lineLimit(3)

            // 操作按钮
            HStack(spacing: 12) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(task.response, forType: .string)
                } label: {
                    Label("复制响应", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    let workDirURL = URL(fileURLWithPath: task.workDir)
                    NSWorkspace.shared.open(workDirURL)
                } label: {
                    Label("打开目录", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - 状态标签

    private func statusLabel(task: CCTask) -> some View {
        let (text, icon, color): (String, String, Color) = {
            switch task.status {
            case .completed: return ("已完成", "checkmark.circle.fill", .green)
            case .failed: return ("失败", "xmark.circle.fill", .red)
            case .running: return ("运行中", "arrow.clockwise", .blue)
            }
        }()

        return Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - 追问栏

    private func followUpBar(task: CCTask) -> some View {
        HStack(spacing: 10) {
            if task.status == .running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在执行...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.tertiary)
                    .font(.body)

                TextField("继续追问...", text: $followUpText)
                    .textFieldStyle(.plain)
                    .onSubmit { submitFollowUp() }

                Button("发送") {
                    submitFollowUp()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(followUpText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - 辅助方法

    private func taskContent(_ response: String) -> String {
        response.isEmpty ? "（无输出）" : response
    }

    private func refresh() {
        if let running = taskManager.runningTasks.first(where: { $0.id == taskId }) {
            self.task = running
        } else if let fromDisk = TaskStore.shared.load(id: taskId) {
            self.task = fromDisk
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            NotificationCenter.default.post(
                name: .selectHistoryTask,
                object: nil,
                userInfo: ["taskId": TaskManager.shared.runningTasks.last?.id ?? ""]
            )
        }
    }
}