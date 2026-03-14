import SwiftUI

struct RequestLogRow: View {
    let entry: RequestLogEntry

    var body: some View {
        HStack(spacing: 0) {
            Text(entry.timeString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(entry.method)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(methodColor)
                .frame(width: 60, alignment: .leading)

            Text(entry.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.isWebhook {
                HStack(spacing: 2) {
                    if entry.statusCode > 0 {
                        Text("\(entry.statusCode)")
                    } else {
                        Text("ERR")
                    }
                    if let attempts = entry.webhookAttempts, attempts > 1 {
                        Text("(\(attempts)x)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(webhookStatusColor)
                .frame(width: 80, alignment: .center)
            } else {
                Text("\(entry.statusCode)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .frame(width: 50, alignment: .center)
            }

            if entry.isWebhook {
                if entry.webhookError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(entry.webhookError ?? "")
                        .frame(width: 70, alignment: .trailing)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 70, alignment: .trailing)
                }
            } else {
                Text(entry.durationString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, DesignSystem.Padding.md)
        .padding(.vertical, DesignSystem.Padding.xs)
        .background(entry.isWebhook ? Color.purple.opacity(0.05) : Color.clear)
    }

    private var methodColor: Color {
        if entry.isWebhook { return .purple }
        return switch entry.method {
        case "GET": .blue
        case "POST": .green
        case "DELETE": .red
        case "PUT", "PATCH": .orange
        default: .primary
        }
    }

    private var statusColor: Color {
        switch entry.statusCategory {
        case .success: .green
        case .clientError: .orange
        case .serverError: .red
        case .other: .secondary
        }
    }

    private var webhookStatusColor: Color {
        entry.webhookError != nil ? .orange : .green
    }
}
