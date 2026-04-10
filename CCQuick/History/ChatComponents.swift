import SwiftUI
import MarkdownUI

// MARK: - Notification Extensions

extension Notification.Name {
    static let openHistoryWindow = Notification.Name("openHistoryWindow")
    static let selectHistoryTask = Notification.Name("selectHistoryTask")
    static let deleteSelectedHistoryTask = Notification.Name("deleteSelectedHistoryTask")
}

// MARK: - Task Group

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

// MARK: - Markdown Utilities

enum MarkdownUtils {
    static func stripMarkdown(_ markdown: String) -> String {
        var result: [String] = []
        var inCodeBlock = false

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("```") { inCodeBlock.toggle(); continue }
            if inCodeBlock { continue }

            var processed = line
            while processed.hasPrefix("#") { processed = String(processed.dropFirst()) }
            processed = processed.trimmingCharacters(in: .whitespaces)

            if processed.hasPrefix("- ") || processed.hasPrefix("* ") || processed.hasPrefix("+ ") {
                processed = String(processed.dropFirst(2))
            } else if let range = processed.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                processed.removeSubrange(range)
            }

            if processed.hasPrefix("> ") { processed = String(processed.dropFirst(2)) }
            let trimmed = processed.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { continue }
            if trimmed.contains("|") && trimmed.contains("-") && !trimmed.contains(where: { !$0.isWhitespace && $0 != "|" && $0 != "-" }) {
                continue
            }
            if processed.contains("|") {
                processed = processed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " | ")
            }

            result.append(processed)
        }

        return result.joined(separator: "\n")
            .replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]+\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "_([^_]+)_", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "~~([^~]+)~~", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }
}

// MARK: - Markdown Theme

enum MarkdownTheme {
    static let gitHub = MarkdownUI.Theme.gitHub.text {
        FontFamily(.system())
        FontSize(NSFont.systemFontSize)
    }
}

// MARK: - Chat Role

enum ChatRole {
    case user
    case assistant
}

// MARK: - Typing Indicator

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

// MARK: - Task Status Label

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

// MARK: - Message Toolbar

struct MessageToolbar: View {
    let content: String

    @State private var isHoveringCopy = false
    @State private var isHoveringMarkdown = false

    var body: some View {
        HStack(spacing: 6) {
            toolbarButton(
                icon: "doc.on.doc",
                tooltip: "复制原文",
                isHovering: isHoveringCopy
            ) {
                isHoveringCopy = true
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(MarkdownUtils.stripMarkdown(content), forType: .string)
            }
            .onHover { isHoveringCopy = $0 }

            if !content.isEmpty {
                toolbarButton(
                    icon: "chevron.left.forwardslash.chevron.right",
                    tooltip: "复制 Markdown",
                    isHovering: isHoveringMarkdown
                ) {
                    isHoveringMarkdown = true
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }
                .onHover { isHoveringMarkdown = $0 }
            }
        }
        .padding(.top, 6)
    }

    private func toolbarButton(icon: String, tooltip: String, isHovering: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovering ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.15))
                )
                .foregroundStyle(isHovering ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - View Helpers

extension View {
    func bubbleBackground(for role: ChatRole, accent: Bool = false) -> some View {
        let bg: Color = accent
            ? (role == .user ? Color.accentColor.opacity(0.8) : Color(NSColor.controlBackgroundColor))
            : Color(NSColor.controlBackgroundColor)
        return self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
