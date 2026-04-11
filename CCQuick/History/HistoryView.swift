import SwiftUI
import MarkdownUI

// MARK: - 主视图

struct HistoryView: View {
    @Bindable private var taskManager = TaskManager.shared
    @State private var tasks: [CCTask] = []
    @State private var searchText = ""
    @State private var filteredTasks: [CCTask] = []
    @State private var selectedTaskId: String?
    @State private var selectedGroup: TaskGroup = .all

    // 布局状态 - 使用 @AppStorage 持久化列宽
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 220
    @AppStorage("listWidth") private var listWidth: Double = 320
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 左侧分组侧边栏
            groupSidebar
                .navigationTitle("")
                .navigationSplitViewColumnWidth(min: 150, ideal: sidebarWidth, max: 400)
        } content: {
            // 中间任务列表
            taskList
                .navigationTitle("")
                .navigationSplitViewColumnWidth(min: 250, ideal: listWidth, max: 500)
        } detail: {
            // 右侧详情
            detailView
                .navigationTitle("")
                .background(Color(NSColor.textBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            reload()
        }
        .onChange(of: taskManager.runningTasks.count) { reload() }
        .onChange(of: taskManager.unviewedTasks.count) { reload() }
        .onChange(of: searchText) { updateFilteredTasks() }
        .onChange(of: selectedGroup) { updateFilteredTasks() }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedHistoryTask)) { _ in
            if let selectedId = selectedTaskId {
                deleteTask(id: selectedId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectHistoryTask)) { notif in
            guard let taskId = notif.userInfo?["taskId"] as? String else { return }
            reload()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                selectedTaskId = taskId
                if columnVisibility != .all {
                    withAnimation(.easeInOut(duration: 0.3)) { columnVisibility = .all }
                }
            }
        }
        .onDisappear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let hasVisibleWindows = NSApp.windows.contains {
                    $0.isVisible && $0.styleMask.contains(.titled)
                }
                if !hasVisibleWindows {
                    NSApp.setActivationPolicy(.accessory)
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

    // MARK: - 任务列表（NSOutlineView 桥接，支持单击选择 + 双击打开）

    private var taskList: some View {
        TaskOutlineViewWrapper(
            tasks: filteredTasks,
            selectedTaskId: $selectedTaskId,
            onDoubleClick: { taskId in
                openTaskDetailWindow(taskId: taskId)
            }
        )
        .navigationTitle("")
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

    /// 双击打开任务详情独立窗口
    private func openTaskDetailWindow(taskId: String) {
        TaskDetailWindowController.showOrCreate(taskId: taskId)
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
                .toolbar {
                    TaskToolbarContent(
                        taskId: taskId,
                        selectedTaskId: selectedTaskId,
                        onNewTask: { InputWindowController.shared.show() }
                    )
                }
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("新建", systemImage: "square.and.pencil") {
                        InputWindowController.shared.show()
                    }
                }
            }
        }
    }

    // MARK: - 辅助方法

    private func countForGroup(_ group: TaskGroup) -> Int {
        switch group {
        case .all: return tasks.count
        case .running: return tasks.filter { $0.status == .running }.count
        case .completed: return tasks.filter { $0.status == .completed }.count
        case .failed: return tasks.filter { $0.status == .failed }.count
        case .stopped: return tasks.filter { $0.status == .stopped }.count
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
        case .stopped: result = result.filter { $0.status == .stopped }
        }

        // 按搜索文本过滤（从 session.jsonl 读取 prompt）
        if !searchText.isEmpty {
            result = result.filter { taskId in
                if let prompt = TaskStore.shared.getFirstPrompt(id: taskId.id) {
                    return prompt.localizedStandardContains(searchText)
                }
                return false
            }
        }

        filteredTasks = result
    }
}

// MARK: - 任务详情视图

struct TaskDetailView: View {
    let taskId: String
    @State private var task: CCTask?
    @State private var messages: [SessionMessage] = []
    @State private var followUpText = ""
    @State private var pendingFollowUpText = ""
    @ObservationIgnored @Bindable private var taskManager = TaskManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if let t = task {
                chatContent(task: t)

                Divider()
                followUpBar(task: t)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear { refresh() }
        .onChange(of: taskId) { refresh() }
        .onChange(of: taskManager.runningTasks.count) { refresh() }
        .onChange(of: taskManager.unviewedTasks.count) { refresh() }
        .onChange(of: task?.status) { _, newStatus in
            if newStatus != .running { pendingFollowUpText = "" }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if task?.status == .running { refresh() }
        }
    }

    // MARK: - 聊天内容

    @ViewBuilder
    private func chatContent(task: CCTask) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    chatBubbles(task: task)
                }
                .padding(16)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMsg = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMsg.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: pendingFollowUpText) { _, newValue in
                if !newValue.isEmpty {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("pending-followup", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - 聊天气泡列表

    @ViewBuilder
    private func chatBubbles(task: CCTask) -> some View {
        // 从 session.jsonl 读取的消息
        ForEach(messages) { msg in
            ChatBubble(
                role: msg.type == .user ? .user : .assistant,
                content: msg.content,
                time: msg.timestamp,
                isStreaming: task.status == .running && msg.id == messages.last?.id && msg.type == .assistant
            )
        }

        // 正在运行但还没有 assistant 消息
        if task.status == .running && (messages.isEmpty || messages.last?.type == .user) {
            ChatBubble(role: .assistant, content: "", time: nil, isStreaming: true)
        }

        // 刚提交追问，尚未写入 session.jsonl
        if task.status == .running
            && !pendingFollowUpText.isEmpty
            && messages.last?.content != pendingFollowUpText {
            ChatBubble(role: .user, content: pendingFollowUpText, time: nil)
                .id("pending-followup")
            ChatBubble(role: .assistant, content: "", time: nil, isStreaming: true)
        }
    }

    // MARK: - 追问栏

    private func followUpBar(task: CCTask) -> some View {
        HStack(spacing: 10) {
            if task.status == .running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在输入...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("停止", systemImage: "stop.fill") {
                    TaskManager.shared.stop(task: task)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
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

    private func refresh() {
        if let running = taskManager.runningTasks.first(where: { $0.id == taskId }) {
            self.task = running
        } else if let fromDisk = TaskStore.shared.load(id: taskId) {
            self.task = fromDisk
            if fromDisk.status == .completed && !fromDisk.viewed {
                taskManager.markViewed(taskId: taskId)
            }
        }
        // 从 session.jsonl 读取消息
        self.messages = TaskStore.shared.loadMessages(id: taskId)
    }

    private func submitFollowUp() {
        guard let t = task, t.status != .running else { return }
        let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        pendingFollowUpText = text
        TaskManager.shared.followUp(task: t, followUpPrompt: text)
        followUpText = ""
    }
}

// MARK: - 聊天气泡

struct ChatBubble: View {
    let role: ChatRole
    let content: String
    let time: Date?
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if role == .assistant {
                avatarView(role: .assistant)
                    .padding(.top, 12)
            }

            VStack(alignment: role == .user ? .trailing : .leading, spacing: 4) {
                messageContent

                if !isStreaming && !content.isEmpty {
                    MessageToolbar(content: content)
                        .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
                }

                if let time = time, !isStreaming {
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 600, alignment: role == .user ? .trailing : .leading)

            if role == .user {
                avatarView(role: .user)
            }
        }
        .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private var messageContent: some View {
        if isStreaming && content.isEmpty {
            HStack(spacing: 4) {
                TypingIndicator()
                Text("正在输入...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .bubbleBackground(for: role, accent: true)
        } else if isStreaming {
            Markdown(content).markdownTheme(MarkdownTheme.gitHub)
                .overlay(alignment: .bottomLeading) { TypingIndicator() }
                .bubbleBackground(for: role)
        } else if !content.isEmpty {
            if role == .user {
                Text(content)
                    .font(.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .bubbleBackground(for: role, accent: true)
            } else {
                Markdown(content).markdownTheme(MarkdownTheme.gitHub)
                    .textSelection(.enabled)
                    .bubbleBackground(for: role)
            }
        }
    }

    private func avatarView(role: ChatRole) -> some View {
        Circle()
            .fill(role == .user ? Color.accentColor.opacity(0.6) : Color.purple.opacity(0.3))
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: role == .user ? "person.fill" : "bolt.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(role == .user ? .white : .purple)
            }
    }
}

// MARK: - 任务 Toolbar

struct TaskToolbarContent: ToolbarContent {
    let taskId: String
    let selectedTaskId: String?
    let onNewTask: () -> Void

    @ObservationIgnored @Bindable private var taskManager = TaskManager.shared

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            toolbarContent
        }
        ToolbarItem(placement: .primaryAction) {
            Button("新建", systemImage: "square.and.pencil") {
                onNewTask()
            }
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        // 停止按钮
        if let task = currentTask, task.status == .running {
            Button("停止", systemImage: "stop.fill") {
                TaskManager.shared.stop(task: task)
            }
            .help("停止当前任务")
        }

        // 复制按钮 - 从 session.jsonl 读取最后一条 assistant 消息
        if let lastResponse = TaskStore.shared.getLastResponse(id: taskId), !lastResponse.isEmpty {
            Button("复制", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lastResponse, forType: .string)
            }
            .help("复制回复内容")
        }

        // 打开目录按钮
        if let task = currentTask {
            Button("目录", systemImage: "folder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: task.workDir))
            }
            .help("打开工作目录")
        }
    }

    private var currentTask: CCTask? {
        taskManager.runningTasks.first { $0.id == taskId } ?? TaskStore.shared.load(id: taskId)
    }
}

#Preview {
    HistoryView()
}