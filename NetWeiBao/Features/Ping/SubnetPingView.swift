import Foundation
import SwiftUI

struct SubnetPingView: View {
    @ObservedObject var viewModel: SubnetPingViewModel
    @FocusState private var inputFocused: Bool

    private let concurrencyOptions = [8, 16, 32]

    var body: some View {
        VStack(spacing: 14) {
            inputCard

            if viewModel.isRunning || viewModel.total > 0 {
                progressCard
            }

            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }

            if viewModel.total > 0 {
                resultsCard
            }

            InlineInfoNote(
                text: "并发扫描会快速产生大量 ICMP 请求，请保持 App 在前台。若没有结果，请检查 设置 > 隐私与安全性 > 本地网络 权限。超时只代表没有收到 ICMP 响应。"
            )
            .padding(.horizontal, 2)
        }
    }

    private var subnet: IPv4Subnet? {
        IPv4Subnet(cidr: viewModel.cidr)
    }

    private var rangeSummary: String {
        guard let subnet else { return "CIDR 格式无效，示例：192.168.1.0/24" }
        return "可用 \(subnet.usableHostCount) 个地址 · 掩码 \(subnet.netmask.description)"
    }

    private var inputCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    SectionLabel(title: "扫描范围")

                    Spacer()

                    Button {
                        viewModel.useLocalSubnet()
                    } label: {
                        Text("使用本机网段")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRunning)
                }

                HStack(spacing: 10) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.blue)

                    TextField("192.168.1.0/24", text: $viewModel.cidr)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.go)
                        .focused($inputFocused)
                        .onSubmit {
                            inputFocused = false
                            viewModel.start()
                        }
                        .disabled(viewModel.isRunning)
                }
                .terminalField()
                .opacity(viewModel.isRunning ? 0.55 : 1)

                Text(rangeSummary)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                ParameterSlider(
                    title: "单次超时",
                    value: $viewModel.timeout,
                    range: 0.2...5,
                    step: 0.2,
                    format: "%.1f s"
                )
                .disabled(viewModel.isRunning)
                .opacity(viewModel.isRunning ? 0.55 : 1)

                HStack {
                    Text("并发数")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()

                    Picker("并发数", selection: $viewModel.concurrency) {
                        ForEach(concurrencyOptions, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 198)
                    .disabled(viewModel.isRunning)
                    .opacity(viewModel.isRunning ? 0.55 : 1)
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
                        viewModel.isRunning ? "停止扫描" : "开始扫描",
                        systemImage: viewModel.isRunning ? "stop.fill" : "antenna.radiowaves.left.and.right"
                    )
                }
                .buttonStyle(
                    PrimaryButtonStyle(
                        color: viewModel.isRunning ? AppTheme.danger : AppTheme.accent
                    )
                )
            }
        }
    }

    private var progressCard: some View {
        AppCard {
            VStack(spacing: 10) {
                HStack {
                    SectionLabel(title: "扫描进度")

                    Spacer()

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.accent)
                        .monospacedDigit()
                }

                ProgressView(value: viewModel.progress)
                    .tint(AppTheme.accent)

                HStack(spacing: 8) {
                    StatusBadge(
                        text: "在线 \(viewModel.onlineCount)",
                        color: AppTheme.accent
                    )

                    StatusBadge(
                        text: "已扫描 \(viewModel.completed)",
                        color: AppTheme.blue
                    )

                    Spacer(minLength: 4)

                    Text(viewModel.summaryText)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var resultsCard: some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(title: "扫描结果")

                    Spacer()

                    Text("\(viewModel.displayedResults.count) 条")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 10)

                Picker("筛选", selection: $viewModel.filter) {
                    ForEach(HostFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                Divider().background(AppTheme.stroke)

                if viewModel.displayedResults.isEmpty {
                    EmptyStateView(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "没有符合条件的设备",
                        message: viewModel.isRunning
                            ? "扫描仍在进行，请稍候。"
                            : "尝试切换到“全部”查看超时目标。"
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.displayedResults) { result in
                            HostScanRow(result: result)
                            Divider()
                                .background(AppTheme.stroke)
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }
}
