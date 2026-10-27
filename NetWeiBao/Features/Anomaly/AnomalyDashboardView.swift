import Foundation
import SwiftUI

struct AnomalyDashboardView: View {
    @StateObject private var viewModel: AnomalyViewModel

    init(mode: AnomalyMode) {
        _viewModel = StateObject(wrappedValue: AnomalyViewModel(mode: mode))
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    targetCard
                    actionCard

                    if viewModel.isRunning {
                        progressCard
                    }

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if let report = viewModel.report {
                        reportContent(report)
                    } else if !viewModel.isRunning {
                        stepsCard
                    }

                    InlineInfoNote(text: viewModel.mode.disclaimer)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle(viewModel.mode.rawValue)
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
                    .fill(viewModel.mode.tint.opacity(0.13))
                Image(systemName: viewModel.mode.icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(viewModel.mode.tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.mode.rawValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(viewModel.mode.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 4)

            StatusBadge(text: "主动探测", color: viewModel.mode.tint)
        }
        .padding(.vertical, 4)
    }

    private var targetCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "检测目标")

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
                        .foregroundStyle(viewModel.mode.tint)

                    TextField("网关 IP 或域名", text: $viewModel.target)
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

                Text(
                    viewModel.localInfo.map {
                        "本机 \($0.address.description) · \($0.subnet.description) · 默认取网段第一个地址"
                    } ?? "请先连接 Wi-Fi 或局域网"
                )
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
    }

    private var actionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "检测")

                    Spacer()

                    StatusBadge(text: "最长约 18 秒", color: AppTheme.blue)
                }

                Text(viewModel.mode.explanation)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    viewModel.start()
                } label: {
                    Label(
                        viewModel.isRunning ? "检测中…" : "开始检测",
                        systemImage: viewModel.isRunning ? "hourglass" : "waveform.path.ecg"
                    )
                }
                .buttonStyle(PrimaryButtonStyle(color: viewModel.mode.tint))
                .disabled(viewModel.isRunning)
                .opacity(viewModel.isRunning ? 0.6 : 1)
            }
        }
    }

    private var progressCard: some View {
        AppCard {
            VStack(spacing: 10) {
                HStack {
                    SectionLabel(title: "检测进度")

                    Spacer()

                    Text("\(Int(viewModel.phase.progress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(viewModel.mode.tint)
                        .monospacedDigit()
                }

                ProgressView(value: viewModel.phase.progress)
                    .tint(viewModel.mode.tint)

                HStack {
                    Text(viewModel.phase.label)
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

    private var stepsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "检测步骤")

                ForEach(Array(viewModel.mode.steps.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(item.offset + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(viewModel.mode.tint)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(viewModel.mode.tint.opacity(0.12))
                            )

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

    private func reportContent(_ report: AnomalyReport) -> some View {
        VStack(spacing: 14) {
            riskCard(report)
            evidenceCard(report)
            metricsCard(report)
            broadcastCard(report)
            contextCard(report)
        }
    }

    private func riskCard(_ report: AnomalyReport) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: report.risk.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(report.risk.color)

                    Text(report.headline)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer(minLength: 4)

                    StatusBadge(text: report.risk.rawValue, color: report.risk.color)
                }

                Text(report.summary)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func evidenceCard(_ report: AnomalyReport) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "判断依据")

                ForEach(Array(report.evidence.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(viewModel.mode.tint)
                            .frame(width: 4, height: 4)
                            .padding(.top, 5)

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

    private func metricsCard(_ report: AnomalyReport) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionLabel(title: "采样数据")
                qualitySection(title: "基线", quality: report.baseline)
                Divider().background(AppTheme.stroke)
                qualitySection(title: "复测", quality: report.post)
            }
        }
    }

    private func qualitySection(title: String, quality: LinkQuality) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text("\(quality.received)/\(quality.sent) 响应")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
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
        }
    }

    private func broadcastCard(_ report: AnomalyReport) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(title: "广播探测")

                    Spacer()

                    Text("发送 \(report.broadcast.sent) 个请求")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
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
                        title: "回复",
                        value: "\(report.broadcast.totalReplies)"
                    )
                    StatTile(
                        title: "响应设备",
                        value: "\(report.broadcast.uniqueResponders.count)"
                    )
                    StatTile(
                        title: "重复回复",
                        value: "\(report.broadcast.duplicateReplies)",
                        tint: report.broadcast.duplicateReplies > 0 ? AppTheme.amber : AppTheme.accent
                    )
                }

                Text(
                    "同源同序号重复 \(report.broadcast.duplicatePairs) 组 · 最多 \(report.broadcast.maxRepliesPerPair) 个/组"
                )
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)

                if !report.broadcast.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(report.broadcast.warnings.prefix(3).enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(AppTheme.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func contextCard(_ report: AnomalyReport) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel(title: "检测信息")

                contextRow("目标", report.target)
                contextRow("接口", report.interfaceName ?? "—")
                contextRow("模式", report.mode.rawValue)
            }
        }
    }

    private func contextRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 46, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func metricValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }
}

private extension AnomalyMode {
    var icon: String {
        switch self {
        case .loop:
            return "arrow.triangle.2.circlepath"
        case .storm:
            return "bolt.circle"
        }
    }

    var tint: Color {
        switch self {
        case .loop:
            return AppTheme.amber
        case .storm:
            return AppTheme.danger
        }
    }

    var subtitle: String {
        switch self {
        case .loop:
            return "重复回声 · 链路质量启发式"
        case .storm:
            return "广播负载 · 链路退化代理"
        }
    }

    var explanation: String {
        switch self {
        case .loop:
            return "先对网关做基线采样，再发送低强度广播 Echo，观察是否出现同源同序号重复回复，并复测网关质量。"
        case .storm:
            return "先对网关做基线采样，再发送低强度广播探测，比较探测前后的丢包、延迟与抖动，寻找风暴导致的链路退化。"
        }
    }

    var steps: [String] {
        switch self {
        case .loop:
            return [
                "基线：连续 Ping 网关，记录丢包、平均延迟与抖动。",
                "广播：向 255.255.255.255 发送 8 个低强度 Echo 请求。",
                "复测：再次采样网关，对比广播前后的链路质量。",
                "分析：检查同源同序号重复回复，给出启发式结论。"
            ]
        case .storm:
            return [
                "基线：连续 Ping 网关，建立延迟、丢包和抖动基线。",
                "广播：发送 8 个低强度广播 Echo，观察响应与重复。",
                "复测：再次采样网关，检测广播负载后的质量变化。",
                "分析：结合重复回复与退化幅度，给出风暴征兆判断。"
            ]
        }
    }

    var disclaimer: String {
        switch self {
        case .loop:
            return "iOS 无法读取交换机 MAC 表、STP 状态或开启混杂模式。本检测只基于广播重复回声与链路质量，属于弱信号，不能确认二层环路；真正的环路定位仍需交换机侧命令或端口镜像。"
        case .storm:
            return "iOS 无法抓包或开启混杂模式。本检测只发送低强度广播探测并比较网关链路质量，不能制造或证明广播风暴；结论不能替代端口镜像、抓包或交换机计数器。"
        }
    }
}

private extension AnomalyRisk {
    var color: Color {
        switch self {
        case .none:
            return AppTheme.accent
        case .suspected:
            return AppTheme.amber
        case .unknown:
            return AppTheme.textTertiary
        }
    }

    var icon: String {
        switch self {
        case .none:
            return "checkmark.shield"
        case .suspected:
            return "exclamationmark.triangle"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

private extension AnomalyPhase {
    var progress: Double {
        switch self {
        case .idle:
            return 0
        case .resolving:
            return 0.05
        case .baseline:
            return 0.15
        case .broadcast:
            return 0.45
        case .post:
            return 0.75
        case .analyzing:
            return 0.92
        }
    }

    var label: String {
        switch self {
        case .idle:
            return "等待开始"
        case .resolving:
            return "正在解析目标…"
        case .baseline:
            return "1/3 基线采样（最多约 7 秒）"
        case .broadcast:
            return "2/3 广播回声探测（约 3 秒）"
        case .post:
            return "3/3 复测链路质量（最多约 7 秒）"
        case .analyzing:
            return "正在生成判断…"
        }
    }
}
