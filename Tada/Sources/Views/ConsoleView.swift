import AppKit
import SwiftUI

/// Developer console: a chronological log of every on-device Foundation Models call.
struct ConsoleView: View {
    @State private var log = APILog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if log.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(log.entries) { entry in
                            APILogEntryRow(entry: entry)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Console")
                    .font(.system(size: 20, weight: .semibold))
                Text("On-device model calls")
                    .font(.system(size: Theme.fontSize))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(log.entries.count) call\(log.entries.count == 1 ? "" : "s")")
                .font(.system(size: Theme.fontSize))
                .foregroundStyle(.secondary)
            Button("Clear") { log.clear() }
                .disabled(log.entries.isEmpty)
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No model calls yet")
                .font(.system(size: Theme.fontSize))
                .foregroundStyle(.secondary)
            Text("Calls appear here as the app's agents run on the on-device model.")
                .font(.system(size: Theme.fontSize))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Entry Row

private struct APILogEntryRow: View {
    let entry: APILogEntry
    @State private var expanded = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary

            if expanded {
                Divider().padding(.vertical, 12)
                details
            }
        }
        .padding(16)
        .background(phaseColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(phaseColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
    }

    // MARK: Summary

    /// Fixed column widths keep the role and task badges flush down the list,
    /// regardless of how wide any individual badge's text is.
    private static let roleColumnWidth: CGFloat = 150
    private static let taskColumnWidth: CGFloat = 360

    private var summary: some View {
        HStack(spacing: 12) {
            roleBadge(entry.role)
                .frame(width: Self.roleColumnWidth, alignment: .leading)

            Group {
                if let taskTitle = entry.taskTitle {
                    taskTitleBadge(taskTitle)
                }
            }
            .frame(width: Self.taskColumnWidth, alignment: .leading)
            .clipped()

            Text(entry.operation)
                .font(.system(size: Theme.fontSize))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if let durationText {
                Text(durationText)
                    .font(.system(size: Theme.fontSize))
                    .foregroundStyle(.secondary)
            }
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: Theme.fontSize))
                .foregroundStyle(.secondary)
            statusBadge
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    /// Human-readable elapsed time: seconds once a call runs past 1s,
    /// milliseconds below that. `nil` until the call completes.
    private var durationText: String? {
        guard let ms = entry.durationMS else { return nil }
        return ms >= 1000 ? String(format: "%.1fs", Double(ms) / 1000) : "\(ms) ms"
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: Theme.badgeFontSize, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.2))
            .foregroundStyle(statusColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .modifier(PendingPulse(active: isPending))
    }

    /// True while a call is in flight — no output and no error yet.
    private var isPending: Bool {
        !entry.isComplete
    }

    private func roleBadge(_ role: AIRole) -> some View {
        Text(role.displayName)
            .font(.system(size: Theme.badgeFontSize, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(phaseColor.opacity(0.2))
            .foregroundStyle(phaseColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// The task or sub-task this call serves. Hugs its text; the enclosing
    /// fixed-width column keeps it from crowding out the operation.
    private func taskTitleBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: Theme.badgeFontSize, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.08))
            .foregroundStyle(.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Colour for the task phase this call serves; tints the whole entry to
    /// match the app's phase palette — discovery (orange), execution (blue),
    /// knowledge work on completed tasks (emerald). Grey when phase is unknown.
    private var phaseColor: Color {
        switch entry.phase {
        case .discovery: Color(lightHex: 0xC8762A, darkHex: 0xE8A04F)
        case .execution: Color(lightHex: 0x2F6FCE, darkHex: 0x5E9BF2)
        case .knowledge: Color(lightHex: 0x1F9D78, darkHex: 0x3FC9A3)
        case nil: .gray
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let temperature = entry.temperature {
                section("Temperature", text: String(format: "%.2f", temperature))
            }
            if let outputType = entry.outputType {
                section("Output Type", text: outputType)
            }
            section("Instructions", text: entry.instructions, tokens: entry.instructionsTokens)
            section("Prompt", text: entry.prompt, tokens: entry.promptTokens)

            if let error = entry.errorMessage {
                section("Error", text: error, tint: .red)
            }
            if let output = entry.output {
                section("Output", text: output, tokens: entry.outputTokens)
            }
            if !entry.isComplete {
                Text("Awaiting response…")
                    .font(.system(size: Theme.fontSize))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, text: String, tokens: Int? = nil, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: Theme.fontSize, weight: .semibold))
                if let tokens {
                    Text("≈\(tokens) tokens")
                        .font(.system(size: Theme.badgeFontSize))
                        .foregroundStyle(.secondary)
                        .help("Approximate token count (~4 chars/token); exact counts need Xcode 26.4+")
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Copy \(title.lowercased())")
            }
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Status styling

    private var statusColor: Color {
        if entry.errorMessage != nil { return .red }
        return entry.isComplete ? .green : .orange
    }

    private var statusText: String {
        if entry.errorMessage != nil { return "FAILED" }
        return entry.isComplete ? "OK" : "RUNNING"
    }
}

// MARK: - Pending pulse

/// Gently pulses the opacity of a view while `active`, so an in-flight call is
/// easy to spot in the console list. Settles back to fully opaque once the call
/// resolves.
private struct PendingPulse: ViewModifier {
    let active: Bool
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dimmed ? 0.35 : 1.0)
            .animation(
                active
                    ? .easeInOut(duration: 0.75).repeatForever(autoreverses: true)
                    : .default,
                value: dimmed
            )
            .onAppear { dimmed = active }
            .onChange(of: active) { _, isActive in dimmed = isActive }
    }
}

// MARK: - Appearance-adaptive colour

private extension Color {
    /// Builds a colour from two `0xRRGGBB` hex values, picking light or dark to
    /// match the current appearance.
    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? darkHex : lightHex
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
