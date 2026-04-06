import SwiftUI
import AppKit

// ESC 键处理（兼容 macOS 13）
struct EscapeHandler: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EscapeView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? EscapeView)?.onEscape = onEscape
    }

    class EscapeView: NSView {
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { false }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // ESC
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

struct InputView: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: "bolt.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            // 输入框
            TextField("输入任务，按回车发送...", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focused)
                .onSubmit {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                    text = ""
                }
                .background(EscapeHandler(onEscape: onCancel))

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
        .onAppear {
            focused = true
        }
    }
}