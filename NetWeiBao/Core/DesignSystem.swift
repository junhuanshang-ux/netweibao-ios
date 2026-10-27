import SwiftUI

enum AppTheme {
    static let background = Color(hex: 0x05080F)
    static let backgroundLifted = Color(hex: 0x08111C)
    static let surface = Color(hex: 0x0D1624)
    static let surfaceRaised = Color(hex: 0x122033)
    static let stroke = Color.white.opacity(0.07)
    static let accent = Color(hex: 0x35E0B2)
    static let blue = Color(hex: 0x5B93FF)
    static let amber = Color(hex: 0xFFB84D)
    static let danger = Color(hex: 0xFF6675)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.36)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            AppTheme.background
            LinearGradient(
                colors: [
                    Color(hex: 0x07131D),
                    AppTheme.background,
                    Color(hex: 0x060A12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(AppTheme.accent.opacity(0.10))
                .frame(width: 330, height: 330)
                .blur(radius: 110)
                .offset(x: 160, y: -300)
            Circle()
                .fill(AppTheme.blue.opacity(0.07))
                .frame(width: 280, height: 280)
                .blur(radius: 120)
                .offset(x: -170, y: 340)
        }
        .ignoresSafeArea()
    }
}

struct AppCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppTheme.stroke, lineWidth: 1)
            )
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.textTertiary)
            .tracking(1.1)
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.65), radius: 5)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var tint: Color = AppTheme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let unit {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surfaceRaised)
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = AppTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hex: 0x04120E))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.055))
            )
    }
}

struct TerminalFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .medium, design: .monospaced))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.24))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.075), lineWidth: 1)
            )
    }
}

extension View {
    func terminalField() -> some View {
        modifier(TerminalFieldModifier())
    }

    func appScreen() -> some View {
        background(AppBackground())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(AppTheme.textTertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
            Text(message)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}
