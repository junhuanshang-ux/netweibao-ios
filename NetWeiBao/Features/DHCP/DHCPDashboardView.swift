import SwiftUI

struct DHCPDashboardView: View {
    @StateObject private var viewModel = DHCPViewModel()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    networkCard
                    actionCard

                    if viewModel.isScanning {
                        scanningCard
                    }

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if let result = viewModel.result {
                        resultContent(result)
                    }

                    InlineInfoNote(
                        text: "DHCP 检测依赖 UDP 67/68 与广播。如果网络启用了客户端隔离、DHCP snooping，或 iOS 拒绝绑定 68 端口，可能检测不到。检测只发送 DISCOVER，不会请求租约或占用地址。"
                    )
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("DHCP 检测")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            viewModel.refreshInterface()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(AppTheme.blue.opacity(0.13))
                Image(systemName: "server.rack")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppTheme.blue)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("DHCP 服务器检测")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("只读 DISCOVER · 不占用地址")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 4)

            StatusBadge(text: "UDP 67/68", color: AppTheme.blue)
        }
        .padding(.vertical, 4)
    }

    private var networkCard: some View {
        AppCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.blue.opacity(0.12))
                    Image(systemName: "wifi")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.blue)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text("本机网络")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)

                    Text(viewModel.localInfo?.address.description ?? "未识别 IPv4")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(
                        viewModel.localInfo.map {
                            "\($0.name) · \($0.subnet.description)"
                        } ?? "请检查 Wi-Fi 或局域网"
                    )
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("广播目标")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)

                    Text(viewModel.broadcastPreview)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("端口 67")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
    }

    private var actionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "发现")

                    Spacer()

                    StatusBadge(text: "只读", color: AppTheme.accent)
                    StatusBadge(text: "最多 4 秒", color: AppTheme.blue)
                }

                Text("发送 DHCPDISCOVER 广播，收集局域网内 DHCP 服务器返回的 OFFER。")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    viewModel.start()
                } label: {
                    Label(
                        viewModel.isScanning ? "检测中…" : "开始检测",
                        systemImage: viewModel.isScanning ? "hourglass" : "dot.radiowaves.left.and.right"
                    )
                }
                .buttonStyle(PrimaryButtonStyle(color: AppTheme.blue))
                .disabled(viewModel.isScanning)
                .opacity(viewModel.isScanning ? 0.6 : 1)
            }
        }
    }

    private var scanningCard: some View {
        AppCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(AppTheme.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("正在等待 DHCP OFFER")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("同时监听多台服务器的响应，最多等待 4 秒。")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func resultContent(_ result: DHCPDiscoveryResult) -> some View {
        summaryCard(result)

        if !result.warnings.isEmpty {
            warningsCard(result)
        }

        if result.offers.isEmpty {
            emptyCard(result)
        } else {
            ForEach(result.offers) { offer in
                DHCPOfferCard(offer: offer)
            }
        }
    }

    private func summaryCard(_ result: DHCPDiscoveryResult) -> some View {
        AppCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("发现 \(result.offers.count) 台 DHCP 服务器")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(
                        "耗时 \(DHCPFormatter.elapsed(result.duration)) · 客户端端口 \(boundPortText(result))"
                    )
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer(minLength: 8)

                StatusBadge(
                    text: result.boundClientPort ? "UDP 68" : "临时端口",
                    color: result.boundClientPort ? AppTheme.accent : AppTheme.amber
                )
            }
        }
    }

    private func warningsCard(_ result: DHCPDiscoveryResult) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "检测提示")

                ForEach(Array(result.warnings.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.amber)
                            .padding(.top, 1)

                        Text(item.element)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func emptyCard(_ result: DHCPDiscoveryResult) -> some View {
        AppCard {
            EmptyStateView(
                icon: "server.rack",
                title: "未发现 DHCP 服务器",
                message: emptyMessage(result)
            )
        }
    }

    private func emptyMessage(_ result: DHCPDiscoveryResult) -> String {
        if let error = result.errorMessage {
            return error
        }
        if !result.boundClientPort {
            return "没有收到 OFFER，且当前只能使用临时端口。DHCP 服务器通常固定向 UDP 68 回复，因此该结果不能证明网络中没有 DHCP。"
        }
        return "没有收到 DHCP OFFER。可能原因：网络屏蔽广播、DHCP 服务未启用、当前使用静态 IP，或客户端隔离。"
    }

    private func boundPortText(_ result: DHCPDiscoveryResult) -> String {
        result.boundPort.map { String($0) } ?? "—"
    }
}

private struct DHCPOfferCard: View {
    let offer: DHCPOffer

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(AppTheme.blue.opacity(0.13))
                        Image(systemName: "server.rack")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.blue)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("DHCP 服务器")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)

                        Text(offer.serverIdentifier?.description ?? "未提供 Option 54")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 4)

                    StatusBadge(text: "OFFER", color: AppTheme.accent)
                }

                Divider().background(AppTheme.stroke)

                LazyVGrid(columns: columns, spacing: 8) {
                    DHCPInfoCell(
                        label: "分配地址",
                        value: offer.offeredAddress?.description ?? "—"
                    )
                    DHCPInfoCell(
                        label: "子网掩码",
                        value: offer.subnetMask?.description ?? "—"
                    )
                    DHCPInfoCell(
                        label: "租期",
                        value: DHCPFormatter.duration(offer.leaseTime)
                    )
                    DHCPInfoCell(
                        label: "来源",
                        value: offer.sourceAddress?.description ?? "—"
                    )
                }

                if !offer.routers.isEmpty {
                    DHCPInfoRow(
                        label: "网关",
                        value: DHCPFormatter.addresses(offer.routers)
                    )
                }

                if !offer.dnsServers.isEmpty {
                    DHCPInfoRow(
                        label: "DNS",
                        value: DHCPFormatter.addresses(offer.dnsServers)
                    )
                }

                if let domainName = offer.domainName {
                    DHCPInfoRow(label: "域名", value: domainName)
                }

                if let broadcastAddress = offer.broadcastAddress {
                    DHCPInfoRow(label: "广播地址", value: broadcastAddress.description)
                }

                if let nextServer = offer.nextServer {
                    DHCPInfoRow(label: "下一跳", value: nextServer.description)
                }

                if let renewalTime = offer.renewalTime {
                    DHCPInfoRow(label: "续租 T1", value: DHCPFormatter.duration(renewalTime))
                }

                if let rebindingTime = offer.rebindingTime {
                    DHCPInfoRow(label: "重绑 T2", value: DHCPFormatter.duration(rebindingTime))
                }

                if let serverName = offer.serverName {
                    DHCPInfoRow(label: "服务器名", value: serverName)
                }

                if let bootFileName = offer.bootFileName {
                    DHCPInfoRow(label: "启动文件", value: bootFileName)
                }

                if let vendorClass = offer.vendorClass {
                    DHCPInfoRow(label: "厂商类", value: vendorClass)
                }

                if let vendorSpecific = offer.vendorSpecific {
                    DHCPInfoRow(
                        label: "厂商选项",
                        value: vendorSpecific,
                        lineLimit: 3
                    )
                }
            }
        }
    }
}

private struct DHCPInfoCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfaceRaised)
        )
    }
}

private struct DHCPInfoRow: View {
    let label: String
    let value: String
    var lineLimit: Int = 2

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 62, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
