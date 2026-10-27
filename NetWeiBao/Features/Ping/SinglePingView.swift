import Foundation
import SwiftUI

struct SinglePingView: View {
    @ObservedObject var viewModel: SinglePingViewModel
    @FocusState private var inputFocused: Bool

    private let quickTargets = [
        "192.168.1.1",
        "223.5.5.5",
        "1.1.1.1",
        "www.baidu.com"
    ]

    var body: some View {
        VStack(spacing: 14) {
            inputCard

            if viewModel.statistics.sent > 0 {
                statisticsCard
            }

            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }

            if !viewModel.samples.isEmpty {
                resultsCard
            } else if !viewModel.isRunning {
                AppCard {
                    EmptyStateView(
                        icon: "waveform.path.ecg",
                        title: "等待发起探测",
                        message: "输入 IP 或域名，向目标发送 ICMP Echo 请求。"
                    )
                }
            }

            InlineInfoNote(
                text: "首次访问局域网时，iOS 会请求“本地网络”权限；如已拒绝，可在 设置 > 隐私与安全性 > 本地网络 中重新开启。目标超时不等于设备离线，部分设备会主动丢弃 ICMP。"
            )
            .padding(.horizontal, 2)
        }
    }

    private var canStart: Bool {
        !viewModel.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var averageLatencyText: String {
        guard let average = viewModel.statistics.averageLatency else { return "—" }
        return String(format: "%.1f", average)
    }

    private var inputCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    SectionLabel(title: "目标地址")

                    Spacer()

                    if let resolved = viewModel.resolvedAddress {
                        Text(resolved)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "scope")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.accent)

                    TextField("IP 地址或域名", text: $viewModel.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .focused($inputFocused)
                        .disabled(viewModel.isRunning)
                        .onSubmit {
                            inputFocused = false
                            viewModel.start()
                        }

                    if !viewModel.host.isEmpty {
                        Button {
                            viewModel.host = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isRunning)
                    }
                }
                .terminalField()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(quickTargets, id: \.self) { target in
                            quickTargetButton(target)
                        }
                    }
                }
                .disabled(viewModel.isRunning)

                Toggle(isOn: $viewModel.continuous) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("持续 Ping")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("关闭后只发送一个 ICMP Echo")
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                .disabled(viewModel.isRunning)

                ParameterSlider(
                    title: "单次超时",
                    value: $viewModel.timeout,
                    range: 0.2...5,
                    step: 0.2,
                    format: "%.1f s"
                )
                .disabled(viewModel.isRunning)

                if viewModel.continuous {
                    ParameterSlider(
                        title: "发送间隔",
                        value: $viewModel.interval,
                        range: 0.2...5,
                        step: 0.2,
                        format: "%.1f s"
                    )
                    .disabled(viewModel.isRunning)
                }

                Button {
                    inputFocused = false
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                } label: {
                    Label(
                        viewModel.isRunning ? "停止 Ping" : "开始 Ping",
                        systemImage: viewModel.isRunning ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(
                    PrimaryButtonStyle(
                        color: viewModel.isRunning ? AppTheme.danger : AppTheme.accent
                    )
                )
                .disabled(!viewModel.isRunning && !canStart)
                .opacity(!viewModel.isRunning && !canStart ? 0.45 : 1)
            }
        }
    }

    private func quickTargetButton(_ target: String) -> some View {
        let selected = viewModel.host == target

        return Button {
            viewModel.host = target
        } label: {
            Text(target)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selected ? AppTheme.accent.opacity(0.12) : Color.white.opacity(0.045))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            selected ? AppTheme.accent.opacity(0.35) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var statisticsCard: some View {
        AppCard {
            VStack(spacing: 12) {
                HStack {
                    SectionLabel(title: "实时统计")

                    Spacer()

                    if viewModel.isRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("运行中")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    StatTile(
                        title: "已发送",
                        value: "\(viewModel.statistics.sent)"
                    )
                    StatTile(
                        title: "已接收",
                        value: "\(viewModel.statistics.received)",
                        tint: AppTheme.accent
                    )
                    StatTile(
                        title: "丢包率",
                        value: LatencyFormatter.percent(viewModel.statistics.packetLoss),
                        tint: viewModel.statistics.packetLoss > 0 ? AppTheme.amber : AppTheme.accent
                    )
                    StatTile(
                        title: "平均延迟",
                        value: averageLatencyText,
                        unit: viewModel.statistics.averageLatency == nil ? nil : "ms"
                    )
                }

                HStack(spacing: 0) {
                    summaryMetric(
                        title: "最小",
                        value: LatencyFormatter.milliseconds(viewModel.statistics.minLatency)
                    )

                    divider

                    summaryMetric(
                        title: "最大",
                        value: LatencyFormatter.milliseconds(viewModel.statistics.maxLatency)
                    )

                    divider

                    summaryMetric(
                        title: "抖动",
                        value: LatencyFormatter.milliseconds(viewModel.statistics.jitter)
                    )
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.stroke)
            .frame(width: 1, height: 24)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var resultsCard: some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(title: "响应记录")

                    Spacer()

                    Text("最近 \(viewModel.samples.count) 条")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)

                    if !viewModel.isRunning {
                        Button {
                            viewModel.reset()
                        } label: {
                            Text("清空")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Divider().background(AppTheme.stroke)

                ForEach(Array(viewModel.samples.reversed()), id: \.id) { reply in
                    PingReplyRow(reply: reply)
                    Divider()
                        .background(AppTheme.stroke)
                        .padding(.leading, 36)
                }
            }
        }
    }
}
