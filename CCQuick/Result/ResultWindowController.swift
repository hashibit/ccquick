import AppKit
import SwiftUI

class ResultWindowController: NSWindowController {
    convenience init(task: CCTask) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = TaskStore.shared.getShortPrompt(id: task.id)
        window.center()

        let view = ResultView(task: task)
        window.contentView = NSHostingView(rootView: view)
        window.minSize = NSSize(width: 400, height: 300)

        self.init(window: window)
    }
}

struct ResultView: View {
    let task: CCTask

    private var prompt: String {
        TaskStore.shared.getFirstPrompt(id: task.id) ?? L10n.taskFallbackName
    }

    private var response: String {
        TaskStore.shared.getLastResponse(id: task.id) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部信息栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt)
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        statusBadge
                        if let finished = task.finishedAt {
                            Text(finished.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(L10n.taskElapsed(task.elapsedString))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(response, forType: .string)
                } label: {
                    Label(L10n.taskCopy, systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 响应内容
            ScrollView {
                Text(response.isEmpty ? L10n.taskNoOutput : response)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch task.status {
        case .completed:
            Label(L10n.statusCompleted, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Label(L10n.statusFailed, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .running:
            Label(L10n.statusRunning, systemImage: "arrow.clockwise.circle")
                .font(.caption)
                .foregroundStyle(.blue)
        case .stopped:
            Label(L10n.statusStopped, systemImage: "hand.raised.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}