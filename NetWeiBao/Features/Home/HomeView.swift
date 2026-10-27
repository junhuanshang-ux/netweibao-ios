import SwiftUI

struct HomeView: View {
    @State private var localInfo = NetworkInterface.activeIPv4()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        localNetworkCard

                        HStack(alignment: .firstTextBaseline) {
                            SectionLabel(title: "工具")
                            Spacer()
                            Text("8 / \(ToolCatalog.items.count) 已上线")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textTertiary)
                        }

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(ToolCatalog.items) { tool in
                                NavigationLink {
                                    destination(for: tool)
                                } label: {
                                    ToolCard(tool: tool)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            localInfo = NetworkInterface.activeIPv4()
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "network")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x04120E))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("网维宝")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("NETWORK FIELD KIT")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            StatusBadge(text: "v0.1", color: AppTheme.blue)
        }
        .padding(.vertical, 2)
    }

    private var localNetworkCard: some View {
        AppCard {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(AppTheme.blue.opacity(0.13))
                    Image(systemName: localInfo == nil ? "wifi.slash" : "wifi")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(localInfo == nil ? AppTheme.amber : AppTheme.blue)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("本机地址")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)

                    Text(localInfo?.address.description ?? "未连接 IPv4")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(localInfo.map { "接口 \($0.name)" } ?? "请检查 Wi-Fi 或局域网")
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("当前网段")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)

                    Text(localInfo?.subnet.description ?? "—")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            StatusDot(color: AppTheme.accent)
            Text("8 个模块全部就绪")
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func destination(for tool: ToolItem) -> some View {
        if tool.id == "ping" {
            PingDashboardView()
        } else if tool.id == "dhcp" {
            DHCPDashboardView()
        } else if tool.id == "loop" {
            AnomalyDashboardView(mode: .loop)
        } else if tool.id == "storm" {
            AnomalyDashboardView(mode: .storm)
        } else if tool.id == "traceroute" {
            TracerouteDashboardView()
        } else if tool.id == "wifi" {
            WiFiDashboardView()
        } else if tool.id == "subnet" {
            SubnetCalculatorView()
        } else if tool.id == "speed" {
            SpeedTestDashboardView()
        } else {
            ToolPlaceholderView(tool: tool)
        }
    }
}

private struct ToolCard: View {
    let tool: ToolItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tool.tint.opacity(0.13))
                    Image(systemName: tool.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tool.tint)
                }
                .frame(width: 38, height: 38)

                Spacer()

                if tool.available {
                    StatusBadge(text: "可用", color: AppTheme.accent)
                } else {
                    Text("规划中")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                }
            }

            Spacer(minLength: 2)

            Text(tool.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            Text(tool.subtitle)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    tool.available ? tool.tint.opacity(0.20) : AppTheme.stroke,
                    lineWidth: 1
                )
        )
    }
}
