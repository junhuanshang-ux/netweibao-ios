import Foundation
import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        missionCard
                        boundaryCard
                        privacyCard
                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "版本 \(short)（\(build)）"
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "network")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x04120E))
            }
            .frame(width: 78, height: 78)

            Text("网维宝")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text(version)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var missionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "定位")

                Text("为现场网络工程师打造的 iPhone 诊断工具箱。把常用的连通性、链路与配置计算能力，收进一个随手可用的 App。")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    StatusBadge(text: "Ping / DHCP 已上线", color: AppTheme.accent)
                    StatusBadge(text: "2 / 8 模块", color: AppTheme.blue)
                }
                .padding(.top, 2)
            }
        }
    }

    private var boundaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "iOS 能力边界")

                boundaryRow(
                    icon: "lock.shield",
                    title: "沙盒与权限",
                    text: "App 不能开启混杂模式抓包，也不能扫描周边 Wi-Fi。需要这些能力的场景，应配合专业探针或端口镜像。"
                )

                Divider().background(AppTheme.stroke)

                boundaryRow(
                    icon: "wifi",
                    title: "Wi-Fi 信息",
                    text: "可以读取当前连接的 SSID、BSSID 与信号强度，但需要定位权限和 Apple 的 WiFi Info entitlement。"
                )

                Divider().background(AppTheme.stroke)

                boundaryRow(
                    icon: "bolt.circle",
                    title: "风暴与环路",
                    text: "将基于路径、延迟、抖动与丢包做启发式判断，不会伪装成交换机级别的抓包结论。"
                )
            }
        }
    }

    private func boundaryRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(text)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(title: "隐私")

                Text("所有探测都由你主动发起。扫描结果只保存在本机内存中，不上传服务器；当前版本不包含第三方统计 SDK。")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Text("SwiftUI · BSD Sockets · Swift Concurrency")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)

            Text("Made for network engineers")
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}
