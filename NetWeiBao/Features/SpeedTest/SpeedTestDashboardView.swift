import Foundation
import SwiftUI

struct SpeedTestDashboardView: View {
    @StateObject private var viewModel = SpeedTestViewModel()

    private let tint = Color(hex: 0xFF8A65)

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    modePicker
                    nodeCard
                    actionCard

                    if viewModel.isRunning {
                        progressCard
                    }

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if let result = viewModel.currentResult {
                        resultCard(result)
                    } else if !viewModel.isRunning {
                        AppCard {
                            EmptyStateView(
                                icon: "speedometer",
                                title: "等待开始测速",
                                message: "默认下载 100 MB、上传 50 MB，并采样 5 次延迟。"
                            )
                        }
                    }

                    if let external = viewModel.externalResult,
                       let internalResult = viewModel.internalResult {
                        comparisonCard(external: external, internalResult: internalResult)
                    }

                    InlineInfoNote(
                        text: "外网默认使用第三方 LibreSpeed 洛杉矶 Sharktech 节点，已验证 100 MB 下载与 50 MB 上传；公共节点可能限速。内网需自建 LibreSpeed。测速会消耗较多流量。"
                    )
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("内外网测速")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: viewModel.mode) { _ in
            viewModel.modeChanged()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tint.opacity(0.13))
                Image(systemName: "speedometer")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("内外网测速")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("下载 / 上传 / 延迟 / 抖动")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 4)

            StatusBadge(text: "LibreSpeed", color: tint)
        }
        .padding(.vertical, 4)
    }

    private var modePicker: some View {
        Picker("测速范围", selection: $viewModel.mode) {
            ForEach(SpeedTestMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(viewModel.isRunning)
        .opacity(viewModel.isRunning ? 0.55 : 1)
    }

    private var nodeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    SectionLabel(title: "测速节点")

                    Spacer()

                    StatusBadge(
                        text: viewModel.mode == .external ? "外网" : "内网",
                        color: viewModel.mode == .external ? AppTheme.blue : AppTheme.accent
                    )
                }

                if viewModel.mode == .external {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("默认")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)
                        Text("洛杉矶 · Sharktech (LibreSpeed)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    TextField("LibreSpeed 后端地址", text: $viewModel.externalURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(viewModel.isRunning)
                        .terminalField()

                    Text("支持国内 LibreSpeed 节点：把地址替换成国内后端的 .../backend 即可。国内公共测速站多有反爬或限网，因此没有内置默认值。")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    TextField(
                        "http://192.168.1.10:8080/backend",
                        text: $viewModel.internalURL
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(viewModel.isRunning)
                    .terminalField()

                    Text("在 NAS / 路由器 / 电脑部署 LibreSpeed 后，填写其 backend 地址。")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().background(AppTheme.stroke)

                HStack(spacing: 14) {
                    sizePicker(
                        title: "下载",
                        value: $viewModel.downloadMegabytes,
                        options: [10, 25, 50, 100, 200, 500]
                    )

                    sizePicker(
                        title: "上传",
                        value: $viewModel.uploadMegabytes,
                        options: [5, 10, 25, 50, 100, 200]
                    )

                    Spacer(minLength: 0)
                }
                .disabled(viewModel.isRunning)

                Text(viewModel.sizeSummary)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private func sizePicker(
        title: String,
        value: Binding<Int>,
        options: [Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button("\(option) MB") {
                        value.wrappedValue = option
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(value.wrappedValue) MB")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            }
        }
    }

    private var actionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    viewModel.mode == .external
                        ? "通过 LibreSpeed 兼容后端测试公网下载/上传吞吐与延迟。默认节点为第三方公共节点。"
                        : "测试局域网内测速后端的吞吐，用于对比内网和公网链路。"
                )
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

                Text("本次将传输：\(viewModel.sizeSummary)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)

                Text("测速会绑定首页所选“诊断网卡”；未选择时走系统默认路由。绑定失败会直接报错，不会偷偷回退。")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if viewModel.isRunning {
                        viewModel.cancel()
                    } else {
                        viewModel.start()
                    }
                } label: {
                    Label(
                        viewModel.isRunning ? "停止测速" : "开始测速",
                        systemImage: viewModel.isRunning ? "stop.fill" : "speedometer"
                    )
                }
                .buttonStyle(
                    PrimaryButtonStyle(color: viewModel.isRunning ? AppTheme.danger : tint)
                )
                .disabled(!viewModel.isRunning && !viewModel.canStart)
                .opacity(!viewModel.isRunning && !viewModel.canStart ? 0.45 : 1)
            }
        }
    }

    private var progressCard: some View {
        AppCard {
            VStack(spacing: 10) {
                HStack {
                    SectionLabel(title: "测速进度")

                    Spacer()

                    Text(viewModel.phaseText)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                ProgressView(value: viewModel.phase.progress)
                    .tint(tint)

                HStack {
                    Text("节点：\(viewModel.nodeName)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)

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

    private func resultCard(_ result: SpeedTestResult) -> some View {
        VStack(spacing: 14) {
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel(title: "测速结果")

                        Spacer()

                        Text(result.nodeName)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 0) {
                        speedMetric(
                            title: "下载",
                            mbps: result.download.mbps,
                            color: AppTheme.accent
                        )

                        Rectangle()
                            .fill(AppTheme.stroke)
                            .frame(width: 1, height: 64)

                        speedMetric(
                            title: "上传",
                            mbps: result.upload.mbps,
                            color: AppTheme.blue
                        )
                    }

                    Divider().background(AppTheme.stroke)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        StatTile(
                            title: "延迟",
                            value: metricValue(result.latency.average),
                            unit: result.latency.average == nil ? nil : "ms"
                        )
                        StatTile(
                            title: "抖动",
                            value: metricValue(result.latency.jitter),
                            unit: result.latency.jitter == nil ? nil : "ms"
                        )
                        StatTile(
                            title: "丢包",
                            value: LatencyFormatter.percent(result.latency.loss),
                            tint: result.latency.loss > 0 ? AppTheme.amber : AppTheme.accent
                        )
                    }

                    Text(
                        "下载 \(bytes(result.download.bytes)) / \(seconds(result.download.duration)) · 上传 \(bytes(result.upload.bytes)) / \(seconds(result.upload.duration))"
                    )
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("节点 \(result.baseURL)")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private func speedMetric(title: String, mbps: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", mbps))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text("Mbps")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func comparisonCard(
        external: SpeedTestResult,
        internalResult: SpeedTestResult
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "内外网对比")

                comparisonRow("外网", result: external)
                Divider().background(AppTheme.stroke)
                comparisonRow("内网", result: internalResult)
            }
        }
    }

    private func comparisonRow(_ label: String, result: SpeedTestResult) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 34, alignment: .leading)

            Text("↓ \(String(format: "%.1f", result.download.mbps))")
                .foregroundStyle(AppTheme.accent)
            Text("↑ \(String(format: "%.1f", result.upload.mbps))")
                .foregroundStyle(AppTheme.blue)
            Text("RTT \(metricValue(result.latency.average))")
                .foregroundStyle(AppTheme.textTertiary)

            Spacer(minLength: 0)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func metricValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    private func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1f s", value)
    }
}

private extension SpeedTestPhase {
    var progress: Double {
        switch self {
        case .idle:
            return 0
        case .latency:
            return 0.15
        case .download:
            return 0.40
        case .upload:
            return 0.75
        case .analyzing:
            return 0.95
        }
    }

}
