import SwiftUI
import UniformTypeIdentifiers

struct ReportDashboardView: View {
    @StateObject private var viewModel = ReportViewModel()

    private let tint = Color(hex: 0x9B8CFF)

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    actionCard

                    if viewModel.isRunning {
                        progressCard
                    }

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if let snapshot = viewModel.snapshot {
                        summaryCard(snapshot)
                        pdfCard(snapshot)
                        resultsCard(snapshot)
                        environmentCard(snapshot)
                    } else if !viewModel.isRunning {
                        emptyCard
                    }

                    InlineInfoNote(
                        text: "一键检测会依次执行 Ping、DHCP、路由追踪、环路、风暴、WiFi、子网计算和快速测速。报告测速使用 10 MB 下载 / 5 MB 上传，避免巡检消耗过多流量。"
                    )
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileExporter(
            isPresented: $viewModel.showExporter,
            document: viewModel.exportDocument,
            contentType: .pdf,
            defaultFilename: viewModel.pdfFilename
        ) { result in
            if case .failure(let error) = result {
                viewModel.errorMessage = "保存 PDF 失败：\(error.localizedDescription)"
            }
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
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("报告")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("一键巡检 · PDF 导出")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 4)

            StatusBadge(text: "8 项", color: tint)
        }
        .padding(.vertical, 4)
    }

    private var actionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "一键检测")
                    Spacer()
                    Text("约 30–90 秒")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Text("依次运行全部 8 个工具，汇总连通性、DHCP、路径、环路/风暴、WiFi、子网和测速结果，并生成 PDF。")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if viewModel.isRunning {
                        viewModel.cancel()
                    } else {
                        viewModel.start()
                    }
                } label: {
                    Label(
                        viewModel.isRunning ? "停止检测" : "一键检测",
                        systemImage: viewModel.isRunning ? "stop.fill" : "wand.and.stars"
                    )
                }
                .buttonStyle(
                    PrimaryButtonStyle(color: viewModel.isRunning ? AppTheme.danger : tint)
                )

                Text("检测会使用当前“诊断网卡”；测速仍走系统路由。")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var progressCard: some View {
        AppCard {
            VStack(spacing: 10) {
                HStack {
                    SectionLabel(title: "检测进度")
                    Spacer()
                    Text("\(Int(viewModel.progressValue * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                ProgressView(value: viewModel.progressValue)
                    .tint(tint)

                HStack {
                    Text(viewModel.progressText)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)

                    Spacer()

                    Button("停止") {
                        viewModel.cancel()
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.danger)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func summaryCard(_ snapshot: ReportSnapshot) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("综合评分")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)
                        Text("\(snapshot.score)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(snapshot.overall.tint)
                            .monospacedDigit()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        StatusBadge(
                            text: snapshot.overall.label,
                            color: snapshot.overall.tint
                        )
                        Text(formatDate(snapshot.generatedAt))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                Text(snapshot.summaryLine)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pdfCard(_ snapshot: ReportSnapshot) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    SectionLabel(title: "PDF 报告")
                    Spacer()
                    StatusBadge(text: "已生成", color: AppTheme.accent)
                }

                Text("\(viewModel.pdfFilename).pdf")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Button {
                        viewModel.showExporter = true
                    } label: {
                        Label("下载", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GhostButtonStyle())

                    if let url = viewModel.pdfURL {
                        ShareLink(item: url) {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }

                Button("重新生成 PDF") {
                    viewModel.regeneratePDF()
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .buttonStyle(.plain)
            }
        }
    }

    private func resultsCard(_ snapshot: ReportSnapshot) -> some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(title: "检测结果")
                    Spacer()
                    Text("\(snapshot.results.count) 项")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(AppTheme.stroke)

                ForEach(snapshot.results) { result in
                    resultRow(result)
                    Divider()
                        .background(AppTheme.stroke)
                        .padding(.leading, 54)
                }
            }
        }
    }

    private func resultRow(_ result: ReportTestResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(result.status.tint.opacity(0.12))
                Image(systemName: result.kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(result.status.tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.kind.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(result.status.label)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(result.status.tint)
                }

                Text(result.headline)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)

                if !result.metrics.isEmpty {
                    Text(result.metrics.prefix(3).map { "\($0.label) \($0.value)" }.joined(separator: " · "))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func environmentCard(_ snapshot: ReportSnapshot) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title: "检测环境")

                metric("主机名", snapshot.hostName)
                metric("系统", snapshot.system)
                metric("接口", snapshot.interfaceName ?? "—")
                metric("本机地址", snapshot.localAddress ?? "—")
                metric("子网", snapshot.subnet ?? "—")
                metric("推测网关", snapshot.gateway ?? "—")
                metric("诊断网卡", snapshot.diagnosticInterface ?? "系统默认")
                if let wifi = snapshot.wifi {
                    metric("WiFi", "\(wifi.ssid) · \(Int(wifi.signalStrength * 100))%")
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    private var emptyCard: some View {
        AppCard {
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: "还没有巡检报告",
                message: "点击“一键检测”，完成后会自动生成 PDF。"
            )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

private extension ReportStatus {
    var tint: Color {
        switch self {
        case .pass: return AppTheme.accent
        case .warning: return AppTheme.amber
        case .fail: return AppTheme.danger
        case .skipped: return AppTheme.textTertiary
        }
    }
}
