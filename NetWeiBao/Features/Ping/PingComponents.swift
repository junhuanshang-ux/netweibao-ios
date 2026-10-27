import Foundation
import SwiftUI

enum PingPalette {
    static func color(for outcome: PingOutcome) -> Color {
        switch outcome {
        case .reply:
            return AppTheme.accent
        case .timeout:
            return AppTheme.textTertiary
        case .unreachable:
            return AppTheme.amber
        case .failure:
            return AppTheme.danger
        }
    }

    static func color(for status: HostScanStatus) -> Color {
        switch status {
        case .online:
            return AppTheme.accent
        case .pending:
            return AppTheme.textTertiary
        case .timeout:
            return AppTheme.textTertiary
        case .unreachable:
            return AppTheme.amber
        case .failed:
            return AppTheme.danger
        }
    }
}

struct PingReplyRow: View {
    let reply: PingReply

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(color: PingPalette.color(for: reply.outcome))

            Text("#\(reply.sequence)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 38, alignment: .leading)

            Text(reply.statusText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PingPalette.color(for: reply.outcome))

            Spacer(minLength: 8)

            if let latency = reply.latencyMs {
                Text(LatencyFormatter.milliseconds(latency))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
            }

            Text(reply.timestamp, style: .time)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

struct HostScanRow: View {
    let result: HostScanResult

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(color: PingPalette.color(for: result.status))

            VStack(alignment: .leading, spacing: 3) {
                Text(result.address.description)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)

                if let message = result.message {
                    Text(message)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.danger.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let latency = result.latencyMs {
                Text(LatencyFormatter.milliseconds(latency))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
                    .monospacedDigit()
            }

            Text(result.status.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PingPalette.color(for: result.status))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.accent)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .tint(AppTheme.accent)
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.danger)
                .padding(.top, 2)

            Text(message)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.danger.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.danger.opacity(0.18), lineWidth: 1)
        )
    }
}

struct WarningBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.amber)
                .padding(.top, 2)

            Text(message)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.amber.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.amber.opacity(0.18), lineWidth: 1)
        )
    }
}

struct InlineInfoNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
