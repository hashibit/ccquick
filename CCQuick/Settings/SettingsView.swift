import SwiftUI
import Carbon

struct SettingsView: View {
    @Bindable private var store = SettingsStore.shared
    @StateObject private var checker = AvailabilityChecker()
    @State private var isRecordingHotkey = false
    @State private var allowMentions = true
    @State private var textSize: Double = 0.5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - 执行引擎
                SettingsSection(title: "执行引擎") {
                    VStack(alignment: .leading, spacing: 16) {
                        // 执行账户选择
                        HStack {
                            Text("执行账户")
                                .frame(width: 100, alignment: .trailing)
                            Spacer()
                            Picker("", selection: $store.executionAccount) {
                                ForEach(ExecutionAccount.allCases, id: \.self) { account in
                                    Text(account.displayName).tag(account)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 200)
                        }

                        // CodingPlan 订阅时显示 API Key 输入框
                        if store.executionAccount == .codingPlan {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("API Key")
                                        .frame(width: 100, alignment: .trailing)
                                    Spacer()
                                    SecureField("输入 API Key", text: $store.codingPlanApiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 300)
                                        .onChange(of: store.codingPlanApiKey) { _, _ in
                                            store.save()
                                        }
                                }

                                // 提示信息
                                Text("支持：Kimi、通义千问、DeepSeek、智谱、百炼等")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 100)
                            }
                        } else {
                            // Claude 订阅说明
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text("使用已登录的 Claude CLI 配置")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .padding(.leading, 100)
                        }

                        // 检测可用性按钮
                        HStack {
                            Spacer()
                                .frame(width: 100)
                            Button {
                                if store.executionAccount == .claudeSubscription {
                                    checker.checkClaudeSubscription()
                                } else {
                                    checker.checkCodingPlan(apiKey: store.codingPlanApiKey)
                                }
                            } label: {
                                if checker.isChecking {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                    Text("检测中...")
                                } else {
                                    Text("检测可用性")
                                }
                            }
                            .disabled(checker.isChecking || (store.executionAccount == .codingPlan && store.codingPlanApiKey.isEmpty))

                            // 检测结果
                            if let result = checker.result {
                                HStack(spacing: 4) {
                                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result.success ? .green : .red)
                                    if let provider = result.providerName, result.success {
                                        Text(provider)
                                            .foregroundColor(.secondary)
                                    } else if !result.success {
                                        Text(result.message)
                                            .foregroundColor(.red)
                                            .font(.system(size: 11))
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }

                // MARK: - 快捷键
                SettingsSection(title: "快捷键") {
                    VStack(spacing: 0) {
                        HotkeyRecordingRow(
                            title: "打开输入窗口",
                            currentHotkey: store.hotkeyDisplayString,
                            isRecording: $isRecordingHotkey,
                            onRecord: { modifiers, keyCode in
                                store.hotkeyModifiers = modifiers
                                store.hotkeyKeyCode = keyCode
                                store.save()
                            }
                        )
                        Divider()
                        ShortcutRow(title: "打开历史记录", keys: ["菜单"])
                        Divider()
                        ShortcutRow(title: "打开设置", keys: ["菜单"])
                    }
                }

                // MARK: - 行为
                SettingsSection(title: "行为") {
                    VStack(spacing: 0) {
                        ToggleRow(title: "启用通知", isOn: $allowMentions)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 550, height: 480)
    }
}

// MARK: - 设置分组

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            SectionCard {
                content
            }
        }
    }
}

// MARK: - 卡片容器

struct SectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
    }
}

// MARK: - 快捷键行

struct ShortcutRow: View {
    let title: String
    let keys: [String]

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    if !key.isEmpty {
                        Text(key)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(NSColor.windowBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                                    )
                            )
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Toggle 行

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 快捷键录制行

struct HotkeyRecordingRow: NSViewRepresentable {
    let title: String
    let currentHotkey: String
    @Binding var isRecording: Bool
    let onRecord: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let button = NSButton()
        button.title = currentHotkey
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.buttonClicked)
        context.coordinator.button = button
        container.addSubview(button)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 120),
            container.heightAnchor.constraint(equalToConstant: 32)
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let button = context.coordinator.button {
            button.title = isRecording ? "按下新快捷键..." : currentHotkey
            button.highlight(isRecording)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: HotkeyRecordingRow
        var button: NSButton?
        private var monitor: Any?

        init(_ parent: HotkeyRecordingRow) {
            self.parent = parent
        }

        @objc func buttonClicked() {
            if parent.isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }

        private func startRecording() {
            parent.isRecording = true
            button?.title = "按下新快捷键..."

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                if event.keyCode == 53 {
                    self.stopRecording()
                    return nil
                }

                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                var modifiers: UInt32 = 0
                if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
                if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
                if flags.contains(.option) { modifiers |= UInt32(optionKey) }
                if flags.contains(.control) { modifiers |= UInt32(controlKey) }

                guard modifiers != 0 else {
                    NSSound.beep()
                    return nil
                }

                let keyCode = UInt32(event.keyCode)
                self.parent.onRecord(modifiers, keyCode)
                self.stopRecording()
                return nil
            }
        }

        private func stopRecording() {
            parent.isRecording = false
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
            button?.title = parent.currentHotkey
        }
    }
}

#Preview {
    SettingsView()
}