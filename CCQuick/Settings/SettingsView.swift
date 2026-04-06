import SwiftUI

struct SettingsView: View {
    @Bindable private var store = SettingsStore.shared
    @State private var tempApiBase: String = ""
    @State private var tempApiKey: String = ""
    @State private var tempModel: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("API 配置") {
                    LabeledContent("API Base URL") {
                        TextField("https://api.anthropic.com", text: $tempApiBase)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }

                    LabeledContent("API Key") {
                        SecureField("sk-ant-…", text: $tempApiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }

                    LabeledContent("Model") {
                        TextField("claude-sonnet-4-20250514", text: $tempModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button("取消") {
                            SettingsWindowController.shared.hide()
                        }
                        .keyboardShortcut(.escape)
                        Button("保存") {
                            saveSettings()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(tempApiKey.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // 兼容性提示
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("API 必须兼容 Claude Code CLI（支持 ANTHROPIC_BASE_URL、ANTHROPIC_MODEL、ANTHROPIC_AUTH_TOKEN 环境变量）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 520, height: 300)
        .onAppear {
            tempApiBase = store.apiBase
            tempApiKey = store.apiKey
            tempModel = store.model
        }
    }

    private func saveSettings() {
        store.apiBase = tempApiBase
        store.apiKey = tempApiKey
        store.model = tempModel
        store.save()
        SettingsWindowController.shared.hide()
    }
}