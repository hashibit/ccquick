import SwiftUI
import Carbon

struct SettingsView: View {
    @Bindable private var store = SettingsStore.shared
    @State private var tempApiBase: String = ""
    @State private var tempApiKey: String = ""
    @State private var tempModel: String = ""
    @State private var selectedAccount = "API"
    @State private var allowMentions = true
    @State private var alwaysReturnToLast = false
    @State private var textSize: Double = 0.5
    @State private var isRecordingHotkey = false

    let accounts = ["API", "Claude Code CLI"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - 账户配置
                SettingsSection(title: "账户配置") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("默认账户")
                                .frame(width: 120, alignment: .trailing)
                            Spacer()
                            Picker("", selection: $selectedAccount) {
                                ForEach(accounts, id: \.self) { account in
                                    Text(account).tag(account)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 200)
                        }

                        if selectedAccount == "API" {
                            SettingRow(title: "API Base URL", value: $tempApiBase, placeholder: "https://api.anthropic.com")
                            SettingRow(title: "API Key", value: $tempApiKey, isSecure: true, placeholder: "sk-ant-...")
                            SettingRow(title: "Model", value: $tempModel, placeholder: "claude-sonnet-4-20250514")
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.secondary)
                                Text("使用 Claude Code CLI 默认配置")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // MARK: - 快捷键
                SettingsSection(title: "快捷键") {
                    VStack(spacing: 0) {
                        // 主快捷键（可录制）
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
                        ShortcutRow(title: "打开历史记录", keys: ["⌘", "H"])
                        Divider()
                        ShortcutRow(title: "打开设置", keys: ["⌘", ","])
                    }
                }

                // MARK: - 行为
                SettingsSection(title: "行为") {
                    VStack(spacing: 0) {
                        ToggleRow(title: "启用通知", isOn: $allowMentions)
                        Divider()
                        ToggleRow(title: "任务完成后自动标记为已查看", isOn: $alwaysReturnToLast)
                    }
                }

                // MARK: - 外观
                SettingsSection(title: "外观") {
                    HStack {
                        Text("默认文本大小")
                            .frame(width: 120)
                        Spacer()
                        Slider(value: $textSize, in: 0...1)
                            .frame(width: 200)
                        Text("中")
                            .foregroundColor(.secondary)
                            .frame(width: 30)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(24)
        }
        .frame(width: 550, height: 520)
        .onAppear {
            tempApiBase = store.apiBase
            tempApiKey = store.apiKey
            tempModel = store.model
        }
        .onChange(of: tempApiBase) { _, newValue in
            store.apiBase = newValue
            store.save()
        }
        .onChange(of: tempApiKey) { _, newValue in
            store.apiKey = newValue
            store.save()
        }
        .onChange(of: tempModel) { _, newValue in
            store.model = newValue
            store.save()
        }
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

// MARK: - 设置行

struct SettingRow: View {
    let title: String
    @Binding var value: String
    var isSecure: Bool = false
    let placeholder: String

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 120, alignment: .trailing)
            Spacer()
            if isSecure {
                SecureField(placeholder, text: $value)
                    .frame(width: 250)
            } else {
                TextField(placeholder, text: $value)
                    .frame(width: 250)
            }
        }
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

                // ESC 取消录制
                if event.keyCode == 53 {
                    self.stopRecording()
                    return nil
                }

                // 获取修饰键
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                var modifiers: UInt32 = 0
                if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
                if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
                if flags.contains(.option) { modifiers |= UInt32(optionKey) }
                if flags.contains(.control) { modifiers |= UInt32(controlKey) }

                // 必须至少有一个修饰键
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
