import SwiftUI

/// Developer console: a chronological log of every Claude API request/response.
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
                Text("API requests and responses")
                    .font(.system(size: Theme.fontSize))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(log.entries.count) request\(log.entries.count == 1 ? "" : "s")")
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
            Text("No API requests yet")
                .font(.system(size: Theme.fontSize))
                .foregroundStyle(.secondary)
            Text("Requests appear here as the app talks to Claude.")
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
        .background(statusColor.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: 12) {
            statusBadge
            Text(entry.method)
                .font(.system(size: Theme.fontSize, weight: .semibold, design: .monospaced))
            Text(entry.url)
                .font(.system(size: Theme.fontSize, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            if let durationMS = entry.durationMS {
                Text("\(durationMS) ms")
                    .font(.system(size: Theme.fontSize))
                    .foregroundStyle(.secondary)
            }
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: Theme.fontSize))
                .foregroundStyle(.secondary)
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: Theme.badgeFontSize, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.2))
            .foregroundStyle(statusColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Request Headers", dictionary: entry.requestHeaders)
            if let body = entry.requestBody {
                section("Request Body", text: body)
            }

            if let error = entry.errorMessage {
                section("Error", text: error, tint: .red)
            }
            if let status = entry.statusCode {
                section("Response Status", text: "\(status)")
            }
            if let headers = entry.responseHeaders, !headers.isEmpty {
                section("Response Headers", dictionary: headers)
            }
            if let body = entry.responseBody {
                section("Response Body", text: body)
            }
            if !entry.isComplete {
                Text("Awaiting response…")
                    .font(.system(size: Theme.fontSize))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, text: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: Theme.fontSize, weight: .semibold))
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

    @ViewBuilder
    private func section(_ title: String, dictionary: [String: String]) -> some View {
        let joined = dictionary.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        section(title, text: joined.isEmpty ? "(none)" : joined)
    }

    // MARK: Status styling

    private var statusColor: Color {
        if entry.errorMessage != nil { return .red }
        guard let status = entry.statusCode else { return .orange }
        return entry.isSuccess ? .green : .red
    }

    private var statusText: String {
        if entry.errorMessage != nil { return "FAILED" }
        if let status = entry.statusCode { return "\(status)" }
        return "PENDING"
    }
}
