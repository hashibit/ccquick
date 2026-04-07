import SwiftUI
import AppKit

struct InputView: View {
    @State private var text = ""

    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: "bolt.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            // 输入框 - 使用 FocusableTextField 确保 NSPanel 中能获得焦点
            FocusableTextField(
                placeholder: "输入任务，按回车发送...",
                text: $text,
                onSubmit: {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                    text = ""
                },
                onEscape: onCancel,
                onClear: { text = "" }
            )

            // 发送按钮
            Button {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSubmit(trimmed)
                text = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .opacity(text.isEmpty ? 0.4 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 600, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

// 使用 NSTextField 确保在 borderless NSPanel 中能正确获得焦点和处理 ESC
struct FocusableTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onClear: () -> Void

    func makeNSView(context: Context) -> FocusableNSTextField {
        let textField = FocusableNSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.onSubmit = onSubmit
        textField.onEscape = onEscape
        return textField
    }

    func updateNSView(_ nsView: FocusableNSTextField, context: Context) {
        // 只在文本真正不同时才更新（避免输入时光标跳转/全选）
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.onSubmit = onSubmit
        nsView.onEscape = onEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: FocusableTextField
        private var isEditing = false

        init(_ parent: FocusableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            isEditing = true
            parent.text = textField.stringValue
            isEditing = false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            if !isEditing {
                parent.text = textField.stringValue
            }
        }

        // 提交后清空文本
        func handleSubmit() {
            parent.onSubmit()
        }
    }
}

class FocusableNSTextField: NSTextField {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        logDebug("keyDown: keyCode=\(event.keyCode)", category: "Input")
        if event.keyCode == 36 { // Return/Enter
            logInfo("Enter 按下，触发 onSubmit", category: "Input")
            onSubmit?()
        } else if event.keyCode == 53 { // ESC
            logInfo("ESC 按下", category: "Input")
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }

    // 确保获得焦点
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            logDebug("TextField 获得焦点", category: "Input")
            // 将光标移到末尾
            if let editor = currentEditor() {
                editor.selectedRange = NSRange(location: stringValue.count, length: 0)
            }
        }
        return result
    }
}