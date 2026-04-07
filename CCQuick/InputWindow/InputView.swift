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
                onEscape: onCancel
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

    func makeNSView(context: Context) -> NSTextField {
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

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
        (nsView as? FocusableNSTextField)?.onSubmit = onSubmit
        (nsView as? FocusableNSTextField)?.onEscape = onEscape
        // 每次更新时尝试获得焦点
        DispatchQueue.main.async {
            if let window = nsView.window, window.isKeyWindow {
                window.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: FocusableTextField

        init(_ parent: FocusableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}

class FocusableNSTextField: NSTextField {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return/Enter
            onSubmit?()
        } else if event.keyCode == 53 { // ESC
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}