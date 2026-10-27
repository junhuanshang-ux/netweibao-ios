import Foundation
import SwiftUI

struct BatchPingView: View {
    @ObservedObject var viewModel: BatchPingViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            inputCard

            if viewModel.isRunning || viewModel.total > 0 {
                progressCard
            }

            if let notice = viewModel.noticeMessage {
                WarningBanner(message: notice)
            }

            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }

            if !viewModel.rows.isEmpty {
                resultsCard
            }

            InlineInfoNote(
                text: "批量模式会解析域名并按顺序探测。CIDR 写法会自动展开为可用地址；单次最多 128 个目标，以免产生过量网络请求。"
            )
            .padding(.horizontal, 2)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    inputFocused = false
                }
            }
        }
    }

    private var recognizedTargets: Int {
        BatchPingViewModel.parseTargets(viewModel.input).targets.count
    }

    private var inputCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    SectionLabel(title: "目标列表")

                    Spacer()

                    Text("已识别 \(recognizedTargets) 个")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.input)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 112, maxHeight: 150)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.24))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.075), lineWidth: 1)
                        )
                        .focused($inputFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(viewModel.isRunning)
                        .opacity(viewModel.isRunning ? 0.55 : 1)

                    if viewModel.input.isEmpty {
                        Text("223.5.5.5\nwww.baidu.com\n192.168.1.0/24")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary.opacity(0.75))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }

                Text("支持 IP、域名、CIDR；换行、空格或逗号分隔。")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)

                HStack {
                    Text("每个目标探测")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()

                    Stepper(value: $viewModel.attempts, in: 1...5) {
                        Text("\(viewModel.attempts) 次")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .monospacedDigit()
                    }
                    .fixedSize()
                    .disabled(viewModel.isRunning)
                }

                ParameterSlider(
                    title: "单次超时",
                    value: $viewModel.timeout,
                    range: 0.2...5,
                    step: 0.2,
                    format: "%.1f s"
                )
                .disabled(viewModel.isRunning)
                .opacity(viewModel.isRunning ? 0.55 : 1)

                Button {
                    inputFocused = false
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                } label: {
                    Label(
                        viewModel.isRunning ? "停止批量探测" : "开始批量探测",
                        systemImage: viewModel.isRunning ? "stop.fill" : "square.stack.3d.up"
                    )
                }
                .buttonStyle(
                    PrimaryButtonStyle(
                        color: viewModel.isRunning ? AppTheme.danger : AppTheme.accent
                    )
                )
                .disabled(!viewModel.isRunning && recognizedTargets == 0)
                .opacity(!viewModel.isRunning && recognizedTargets == 0 ? 0.45 : 1)
            }
        }
    }

    private var progressCard: some View {
        AppCard {
            VStack(spacing: 10) {
                HStack {
                    SectionLabel(title: "探测进度")

                    Spacer()

                    Text("\(viewModel.completed)/\(viewModel.total)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.accent)
                        .monospacedDigit()
                }

                ProgressView(value: viewModel.progress)
                    .tint(AppTheme.accent)

                HStack(spacing: 8) {
                    StatusBadge(
                        text: "在线 \(onlineCount)",
                        color: AppTheme.accent
                    )
                    StatusBadge(
                        text: "失败 \(failedCount)",
                        color: AppTheme.danger
                    )
                    Spacer()
                    Text(
                        viewModel.isRunning
                            ? "正在探测"
                            : (viewModel.completed < viewModel.total ? "已停止" : "已完成")
                    )
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
    }

    private var onlineCount: Int {
        viewModel.rows.filter { $0.status == .online }.count
    }

    private var failedCount: Int {
        viewModel.rows.filter { $0.status == .failed || $0.status == .unreachable }.count
    }

    private var resultsCard: some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(title: "批量结果")

                    Spacer()

                    Text("\(viewModel.rows.count) 个目标")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Divider().background(AppTheme.stroke)

                LazyVStack(spacing: 0) {
                    ForEach(viewModel.rows) { row in
                        BatchTargetRowView(row: row)
                        Divider()
                            .background(AppTheme.stroke)
                            .padding(.leading, 36)
                    }
                }
            }
        }
    }
}

private struct BatchTargetRowView: View {
    let row: BatchTargetRow

    private var color: Color {
        PingPalette.color(for: row.status)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusDot(color: color)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.target)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if let address = row.address, address != row.target {
                    Text(address)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                if let message = row.message {
                    Text(message)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.danger.opacity(0.9))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if row.status == .pending {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(row.status.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(color)
                }

                if row.sent > 0 {
                    Text("\(row.received)/\(row.sent) 收/发")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                if let latency = row.averageLatency {
                    Text(LatencyFormatter.milliseconds(latency))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
