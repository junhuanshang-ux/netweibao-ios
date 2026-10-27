import CoreLocation
import Foundation
import SwiftUI

struct WiFiDashboardView: View {
    @StateObject private var viewModel = WiFiViewModel()

    private let tint = Color(hex: 0x4DD0E1)

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    permissionCard

                    if viewModel.isLoading {
                        loadingCard
                    }

                    if let network = viewModel.network {
                        networkCard(network)
                    }

                    if let quality = viewModel.quality {
                        qualityCard(quality)
                    }

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if !viewModel.isLoading,
                       viewModel.network == nil,
                       viewModel.errorMessage == nil {
                        AppCard {
                            EmptyStateView(
                                icon: "wifi",
                                title: "未读取到当前 WiFi",
                                message: "请确认已连接 WiFi，并允许定位权限。"
                            )
                        }
                    }

                    InlineInfoNote(
                        text: "iOS 只允许读取当前连接的 WiFi，不能扫描周边 AP。SSID/BSSID 需要定位权限和 WiFi Info entitlement；模拟器通常无法返回。"
                    )
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("WiFi 分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            viewModel.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tint.opacity(0.13))
                Image(systemName: "wifi")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("WiFi 分析")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("当前连接 · 信号与网关质量")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 4)

            StatusBadge(
                text: viewModel.authorizationText,
                color: viewModel.isAuthorized ? AppTheme.accent : AppTheme.amber
            )
        }
        .padding(.vertical, 4)
    }

    private var permissionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "location.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(viewModel.isAuthorized ? AppTheme.accent : AppTheme.amber)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("定位权限")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(viewModel.authorizationText)
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    Spacer()

                    if viewModel.authorizationStatus == .notDetermined {
                        Button("允许") {
                            viewModel.requestAuthorization()
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .buttonStyle(.plain)
                    } else if viewModel.authorizationStatus == .denied {
                        Button("去设置") {
                            viewModel.openSettings()
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.amber)
                        .buttonStyle(.plain)
                    } else {
                        Button("刷新") {
                            viewModel.refresh()
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .buttonStyle(.plain)
                    }
                }

                Text("iOS 要求定位权限才能向 App 暴露当前 WiFi 的 SSID/BSSID。")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var loadingCard: some View {
        AppCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(tint)
                Text("正在读取当前 WiFi 并采样网关质量…")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func networkCard(_ network: WiFiNetworkInfo) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前 WiFi")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)

                        Text(network.ssid.isEmpty ? "未命名 WiFi" : network.ssid)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    Spacer(minLength: 8)

                    StatusBadge(
                        text: network.isSecure ? "加密" : "开放",
                        color: network.isSecure ? AppTheme.accent : AppTheme.danger
                    )
                }

                HStack(spacing: 6) {
                    Text("BSSID")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)

                    Text(network.bssid.isEmpty ? "—" : network.bssid)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    if network.autoJoined {
                        StatusBadge(text: "自动加入", color: AppTheme.blue)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("信号强度")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)

                        Spacer()

                        Text("\(Int(network.signalStrength * 100))% · \(signalLabel(network.signalStrength))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(signalColor(network.signalStrength))
                            .monospacedDigit()
                    }

                    ProgressView(value: network.signalStrength)
                        .tint(signalColor(network.signalStrength))
                }
            }
        }
    }

    private func qualityCard(_ quality: LinkQuality) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "网关质量")

                    Spacer()

                    if let gateway = viewModel.gateway {
                        Text(gateway.description)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    StatTile(
                        title: "平均",
                        value: metricValue(quality.average),
                        unit: quality.average == nil ? nil : "ms"
                    )
                    StatTile(
                        title: "丢包",
                        value: LatencyFormatter.percent(quality.loss),
                        tint: quality.loss > 0 ? AppTheme.amber : AppTheme.accent
                    )
                    StatTile(
                        title: "抖动",
                        value: metricValue(quality.jitter),
                        unit: quality.jitter == nil ? nil : "ms"
                    )
                }

                Text("\(quality.received)/\(quality.sent) 响应 · 6 次采样")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private func metricValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    private func signalLabel(_ strength: Double) -> String {
        if strength >= 0.66 { return "强" }
        if strength >= 0.33 { return "中" }
        return "弱"
    }

    private func signalColor(_ strength: Double) -> Color {
        if strength >= 0.66 { return AppTheme.accent }
        if strength >= 0.33 { return AppTheme.amber }
        return AppTheme.danger
    }
}
