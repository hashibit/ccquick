import SwiftUI
import MarkdownUI

extension Notification.Name {
    static let selectHistoryTask = Notification.Name("selectHistoryTask")
    static let deleteSelectedHistoryTask = Notification.Name("deleteSelectedHistoryTask")
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
        .ignoresSafeArea()
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
    }

    /// 双击打开任务详情独立窗口
    private func openTaskDetailWindow(taskId: String) {
        let controller = TaskDetailWindowController(taskId: taskId)
        controller.show()
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
        .onChange(of: taskManager.runningTasks) { refresh() }
        .onChange(of: taskManager.unviewedTasks) { refresh() }
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
            .onChange(of: task.response) { _, newValue in
                if let lastFollowUp = extractFollowUps(from: newValue).last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastFollowUp.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - 聊天气泡列表

    @ViewBuilder
    private func chatBubbles(task: CCTask) -> some View {
        // 用户原始问题
        ChatBubble(role: .user, content: task.prompt, time: task.startedAt)

        // AI 第一轮回复
        let firstResponse = extractFirstResponse(from: task.response)
        if !firstResponse.isEmpty {
            ChatBubble(
                role: .assistant,
                content: firstResponse,
                time: task.finishedAt,
                isStreaming: task.status == .running && !hasFollowUps(from: task.response)
            )
        }

        // 追问轮次
        let followUps = extractFollowUps(from: task.response)
        ForEach(followUps, id: \.id) { followUp in
            ChatBubble(role: .user, content: followUp.question, time: nil)
            if !followUp.answer.isEmpty {
                ChatBubble(
                    role: .assistant,
                    content: followUp.answer,
                    time: nil,
                    isStreaming: task.status == .running && followUp.isLast
                )
            }
        }

        // 正在运行但还没有回复
        if task.status == .running && task.response.isEmpty {
            ChatBubble(role: .assistant, content: "", time: nil, isStreaming: true)
        }
    }

    // MARK: - 解析 response

    /// 提取第一轮 AI 回复（追问分隔符之前的内容）
    private func extractFirstResponse(from response: String) -> String {
        if let separatorRange = response.range(of: "\n\n---\n\n### 追问：") {
            return String(response[..<separatorRange.lowerBound])
        }
        return response
    }

    /// 检查是否有追问
    private func hasFollowUps(from response: String) -> Bool {
        response.contains("\n\n---\n\n### 追问：")
    }

    /// 提取追问轮次
    private func extractFollowUps(from response: String) -> [FollowUpRound] {
        var rounds: [FollowUpRound] = []
        let separator = "\n\n---\n\n### 追问："

        var remaining = response
        var isFirst = true

        while let sepRange = remaining.range(of: separator) {
            if isFirst {
                // 第一轮分隔符之后的内容开始解析
                isFirst = false
            }

            // 获取分隔符之后的内容
            let afterSeparator = String(remaining[sepRange.upperBound...])

            // 找到问题结束的位置（下一个换行之后）
            if let questionEndRange = afterSeparator.range(of: "\n\n") {
                let question = String(afterSeparator[..<questionEndRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

                // 获取回答部分（下一个分隔符之前，或到结尾）
                let answerStart = questionEndRange.upperBound
                let answerPart = String(afterSeparator[answerStart...])

                let nextSepRange = answerPart.range(of: separator)
                let answer = nextSepRange != nil
                    ? String(answerPart[..<nextSepRange!.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    : answerPart.trimmingCharacters(in: .whitespacesAndNewlines)

                rounds.append(FollowUpRound(
                    id: "followup-\(rounds.count)",
                    question: question,
                    answer: answer,
                    isLast: nextSepRange == nil && task?.status == .running
                ))

                // 继续处理剩余部分
                remaining = nextSepRange != nil ? answerPart : ""
            } else {
                // 问题后面没有回答（正在生成）
                let question = afterSeparator.trimmingCharacters(in: .whitespacesAndNewlines)
                rounds.append(FollowUpRound(
                    id: "followup-\(rounds.count)",
                    question: question,
                    answer: "",
                    isLast: task?.status == .running
                ))
                break
            }
        }

        return rounds
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
    }

    private func submitFollowUp() {
        guard let t = task, t.status != .running else { return }
        let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 使用 followUp 方法在当前任务会话中继续对话，不创建新历史
        TaskManager.shared.followUp(task: t, followUpPrompt: text)
        followUpText = ""
    }
}

// MARK: - 追问轮次数据

struct FollowUpRound: Identifiable {
    let id: String
    let question: String
    let answer: String
    let isLast: Bool
}

// MARK: - 聊天气泡

enum ChatRole {
    case user
    case assistant
}

struct ChatBubble: View {
    let role: ChatRole
    let content: String
    let time: Date?
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if role == .assistant {
                // AI 头像
                avatarView(role: .assistant)
            }

            VStack(alignment: role == .user ? .trailing : .leading, spacing: 4) {
                // 消息内容
                messageContent

                // 时间戳
                if let time = time, !isStreaming {
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 600, alignment: role == .user ? .trailing : .leading)

            if role == .user {
                // 用户头像
                avatarView(role: .user)
            }
        }
        .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private var messageContent: some View {
        if isStreaming && content.isEmpty {
            // 正在输入状态
            HStack(spacing: 4) {
                TypingIndicator()
                Text("正在输入...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(role == .user ? Color.accentColor.opacity(0.8) : Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if isStreaming {
            // 流式输出中
            VStack(alignment: .leading, spacing: 4) {
                Markdown(content)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)

                HStack(spacing: 4) {
                    TypingIndicator()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if !content.isEmpty {
            // 完整消息
            if role == .user {
                Text(content)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.accentColor.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Markdown(content)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        if let task = currentTask {
            HStack(spacing: 8) {
                // 状态标签
                TaskStatusLabel(task: task)

                // 复制按钮
                if !task.response.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(task.response, forType: .string)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // 打开目录按钮
                Button {
                    let workDirURL = URL(fileURLWithPath: task.workDir)
                    NSWorkspace.shared.open(workDirURL)
                } label: {
                    Label("目录", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var currentTask: CCTask? {
        taskManager.runningTasks.first { $0.id == taskId } ?? TaskStore.shared.load(id: taskId)
    }
}

struct TaskStatusLabel: View {
    let task: CCTask

    var body: some View {
        let config = statusConfig()
        Label(config.text, systemImage: config.icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(config.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(config.color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func statusConfig() -> (text: String, icon: String, color: Color) {
        switch task.status {
        case .completed: return ("已完成", "checkmark.circle.fill", .green)
        case .failed: return ("失败", "xmark.circle.fill", .red)
        case .running: return ("运行中", "arrow.clockwise", .blue)
        }
    }
}

// MARK: - 打字动画指示器

struct TypingIndicator: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                    .opacity(animationPhase == index ? 1 : 0.5)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    animationPhase = (animationPhase + 1) % 3
                }
            }
        }
    }
}

#Preview {
    HistoryView()
}
