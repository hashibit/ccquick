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
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.secondary)
                .font(.title3)

            TextField("输入任务，按回车发送…", text: $text)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                    text = ""
                }
                .background(EscapeHandler(onEscape: onCancel))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 620, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        )
        .onAppear {
            focused = true
        }
    }
}
