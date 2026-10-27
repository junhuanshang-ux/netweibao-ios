import Foundation
import SwiftUI

struct TracerouteDashboardView: View {
    @StateObject private var viewModel = TracerouteViewModel()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    targetCard

                    if viewModel.isRunning {
                        progressCard
                    }

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if let warning = viewModel.warning {
                        WarningBanner(message: warning)
                    }

                    if !viewModel.hops.isEmpty {
                        summaryCard
                        hopsCard
                    } else if !viewModel.isRunning {
                        AppCard {
                            EmptyStateView(
                                icon: "arrow.triangle.branch",
                                title: "等待开始追踪",
                                message: "逐跳增加 TTL，观察 ICMP Time Exceeded 与目标响应。"
                            )
                        }
                    }

                    InlineInfoNote(
                        text: "iOS 不提供 raw socket。若系统不向非特权 ICMP socket 回传 Time Exceeded，中间跳会显示为 *；这不是目标不可达，而是路径不可见。"
                    )
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("路由追踪")
        .navigationBarTitleDisplayMode(.inline)
        .scrollIndicators(.hidden)
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
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppTheme.blue)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("路由追踪")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("逐跳 TTL · ICMP 路径可见性")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 4)

            StatusBadge(text: "IPv4", color: AppTheme.blue)
        }
        .padding(.vertical, 4)
    }

    private var targetCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "目标")

                    Spacer()

                    Button("使用推测网关") {
                        viewModel.useSuggestedTarget()
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRunning || viewModel.suggestedTarget.isEmpty)
                }

                HStack(spacing: 10) {
                    Image(systemName: "scope")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.blue)

                    TextField("IP 或域名", text: $viewModel.target)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .disabled(viewModel.isRunning)
                        .onSubmit {
                            viewModel.start()
                        }
                }
                .terminalField()

                if let localInfo = viewModel.localInfo {
                    Text("本机 \(localInfo.address.description) · \(localInfo.subnet.description)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                HStack {
                    Text("最大跳数")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()

                    Stepper(value: $viewModel.maxHops, in: 4...30) {
                        Text("\(viewModel.maxHops) 跳")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .monospacedDigit()
                    }
                    .fixedSize()
                    .disabled(viewModel.isRunning)
                }

                ParameterSlider(
                    title: "每跳超时",
                    value: $viewModel.timeout,
                    range: 0.3...2.0,
                    step: 0.1,
                    format: "%.1f s"
                )
                .disabled(viewModel.isRunning)
                .opacity(viewModel.isRunning ? 0.55 : 1)

                Button {
                    viewModel.start()
                } label: {
                    Label(
                        viewModel.isRunning ? "追踪中…" : "开始追踪",
                        systemImage: viewModel.isRunning ? "hourglass" : "location.north.line"
                    )
                }
                .buttonStyle(PrimaryButtonStyle(color: AppTheme.blue))
                .disabled(viewModel.isRunning)
                .opacity(viewModel.isRunning ? 0.6 : 1)
            }
        }
    }

    private var progressCard: some View {
        AppCard {
            VStack(spacing: 10) {
                HStack {
                    SectionLabel(title: "追踪进度")

                    Spacer()

                    Text("第 \(viewModel.hops.count) / \(viewModel.maxHops) 跳")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                ProgressView(value: viewModel.progress)
                    .tint(AppTheme.blue)

                HStack {
                    Text("每跳 1 次探测，超时 \(String(format: "%.1f", viewModel.timeout)) 秒")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)

                    Spacer()

                    Button("停止") {
                        viewModel.cancel()
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.danger)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryCard: some View {
        AppCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.reached ? "已到达目标" : "未到达目标")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.reached ? AppTheme.accent : AppTheme.amber)

                    Text("共 \(viewModel.hops.count) 跳 · 目标 \(viewModel.target)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 8)

                StatusBadge(
                    text: viewModel.reached ? "完成" : "部分路径",
                    color: viewModel.reached ? AppTheme.accent : AppTheme.amber
                )
            }
        }
    }

    private var hopsCard: some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(title: "路径")

                    Spacer()

                    Text("\(viewModel.hops.count) 跳")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(AppTheme.stroke)

                LazyVStack(spacing: 0) {
                    ForEach(viewModel.hops) { hop in
                        TracerouteHopRow(hop: hop)
                        Divider()
                            .background(AppTheme.stroke)
                            .padding(.leading, 42)
                    }
                }
            }
        }
    }
}

private struct TracerouteHopRow: View {
    let hop: TracerouteHop

    private var color: Color {
        switch hop.status {
        case .target:
            return AppTheme.accent
        case .hop:
            return AppTheme.blue
        case .timeout:
            return AppTheme.textTertiary
        case .unreachable:
            return AppTheme.danger
        }
    }

    private var statusText: String {
        switch hop.status {
        case .target:
            return "目标"
        case .hop:
            return "跳点"
        case .timeout:
            return "超时"
        case .unreachable:
            return "不可达"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("#\(hop.ttl)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 30, alignment: .leading)

            StatusDot(color: color, size: 7)

            Text(hop.address?.description ?? "*")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(hop.address == nil ? AppTheme.textTertiary : AppTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let latency = hop.latency {
                Text(LatencyFormatter.milliseconds(latency))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
                    .monospacedDigit()
            }

            Text(statusText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
