import SwiftUI

struct SettingsView: View {
    @Bindable private var store = SettingsStore.shared
    @State private var tempApiBase: String = ""
    @State private var tempApiKey: String = ""
    @State private var tempModel: String = ""

    @State private var selectedAccount = "API"
    @State private var sortBy = "editDate"
    @State private var groupByDate = true
    @State private var alwaysReturnToLast = false
    @State private var autoSortChecked = false
    @State private var allowMentions = true
    @State private var enableMacAccount = false
    @State private var textSize: Double = 0.4

    let accounts = ["API", "Claude Code CLI"]
    let sortOptions = ["编辑日期", "创建日期", "标题"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // MARK: - API 配置
                Section {
                    Picker("默认账户", selection: $selectedAccount) {
                        ForEach(accounts, id: \.self) { account in
                            Text(account).tag(account)
                        }
                    }
                    .pickerStyle(.menu)

                    if selectedAccount == "API" {
                        HStack {
                            Text("API Base URL")
                                .frame(width: 120, alignment: .trailing)
                            TextField("https://api.anthropic.com", text: $tempApiBase)
                                .textFieldStyle(.plain)
                                .frame(maxWidth: .infinity)
                        }

                        HStack {
                            Text("API Key")
                                .frame(width: 120, alignment: .trailing)
                            SecureField("sk-ant-…", text: $tempApiKey)
                                .textFieldStyle(.plain)
                                .frame(maxWidth: .infinity)
                        }

                        HStack {
                            Text("Model")
                                .frame(width: 120, alignment: .trailing)
                            TextField("claude-sonnet-4-20250514", text: $tempModel)
                                .textFieldStyle(.plain)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.secondary)
                            Text("使用 Claude Code CLI 默认配置")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                } header: {
                    Label("账户配置", systemImage: "person.circle")
                }

                // MARK: - 快捷键
                Section {
                    HStack {
                        Text("打开输入窗口")
                            .frame(width: 120, alignment: .trailing)
                        HStack(spacing: 4) {
                            ShortcutKey("⌘")
                            ShortcutKey("⇧")
                            ShortcutKey("Space")
                        }
                        Spacer()
                    }

                    HStack {
                        Text("打开历史记录")
                            .frame(width: 120, alignment: .trailing)
                        HStack(spacing: 4) {
                            ShortcutKey("⌘")
                            ShortcutKey("H")
                        }
                        Spacer()
                    }

                    HStack {
                        Text("打开设置")
                            .frame(width: 120, alignment: .trailing)
                        HStack(spacing: 4) {
                            ShortcutKey("⌘")
                            ShortcutKey(",")
                        }
                        Spacer()
                    }
                } header: {
                    Label("快捷键", systemImage: "keyboard")
                }

                // MARK: - 行为
                Section {
                    Toggle("启用通知", isOn: $allowMentions)

                    Toggle("任务完成后自动标记为已查看", isOn: $alwaysReturnToLast)
                } header: {
                    Label("行为", systemImage: "gearshape")
                }

                // MARK: - 文本大小
                Section {
                    HStack {
                        Text("默认文本大小")
                            .frame(width: 120, alignment: .trailing)
                        Slider(value: $textSize, in: 0...1)
                            .labelsHidden()
                            .frame(width: 200)
                        HStack {
                            Text("小")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("大")
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 60)
                    }
                } header: {
                    Label("外观", systemImage: "textformat.size")
                }
            }
            .formStyle(.grouped)

            // MARK: - 底部说明
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                Text("API 必须兼容 Claude Code CLI（支持 ANTHROPIC_BASE_URL、ANTHROPIC_MODEL、ANTHROPIC_AUTH_TOKEN 环境变量）")
                    .font(.caption)
                Spacer()
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 540, height: 480)
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

// MARK: - 快捷键徽章
struct ShortcutKey: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor).opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 0.5, x: 0, y: 1)
            )
    }
}

#Preview {
    SettingsView()
}
