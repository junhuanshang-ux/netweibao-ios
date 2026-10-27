import Foundation
import UIKit

enum ReportPDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842)

    static func render(_ snapshot: ReportSnapshot) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "网维宝网络巡检报告",
            kCGPDFContextCreator as String: "NetWeiBao"
        ]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize),
            format: format
        )

        return renderer.pdfData { context in
            let canvas = Canvas(context: context, snapshot: snapshot)
            canvas.beginPage(withHeader: false)
            canvas.drawCover()
            canvas.newPage()
            canvas.drawOverview()
            canvas.drawEnvironment()

            for result in snapshot.results {
                canvas.draw(result: result)
            }

            canvas.drawNotes()
        }
    }

    static func filename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "NetWeiBao-Report-\(formatter.string(from: date)).pdf"
    }
}

private final class Canvas {
    private let context: UIGraphicsPDFRendererContext
    private let snapshot: ReportSnapshot
    private let margin: CGFloat = 42
    private let pageRect: CGRect
    private let contentWidth: CGFloat
    private let bottomLimit: CGFloat
    private var y: CGFloat = 0
    private var pageNumber = 0

    private let ink = UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)
    private let secondary = UIColor(red: 0.36, green: 0.40, blue: 0.44, alpha: 1)
    private let tertiary = UIColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1)
    private let accent = UIColor(red: 0.20, green: 0.72, blue: 0.50, alpha: 1)
    private let blue = UIColor(red: 0.22, green: 0.56, blue: 0.92, alpha: 1)
    private let amber = UIColor(red: 0.92, green: 0.58, blue: 0.16, alpha: 1)
    private let red = UIColor(red: 0.86, green: 0.26, blue: 0.26, alpha: 1)

    init(context: UIGraphicsPDFRendererContext, snapshot: ReportSnapshot) {
        self.context = context
        self.snapshot = snapshot
        self.pageRect = CGRect(origin: .zero, size: ReportPDFRenderer.pageSize)
        self.contentWidth = pageRect.width - margin * 2
        self.bottomLimit = pageRect.height - 48
    }

    func beginPage(withHeader: Bool = true) {
        context.beginPage()
        pageNumber += 1
        y = margin

        if withHeader {
            drawHeader()
            y = 62
        }
    }

    func newPage() {
        beginPage()
    }

    func drawCover() {
        UIColor.white.setFill()
        context.cgContext.fill(pageRect)

        let bar = CGRect(x: margin, y: 62, width: 54, height: 5)
        accent.setFill()
        UIBezierPath(roundedRect: bar, cornerRadius: 2.5).fill()

        y = 88
        text("网维宝 · NetWeiBao", font: .systemFont(ofSize: 11, weight: .semibold), color: tertiary, spacing: 12)
        text("网络巡检报告", font: .systemFont(ofSize: 32, weight: .bold), color: ink, spacing: 8)
        text(dateText(snapshot.generatedAt), font: .systemFont(ofSize: 11), color: secondary, spacing: 28)

        let scoreColor = statusColor(snapshot.overall)
        text("\(snapshot.score)", font: .systemFont(ofSize: 60, weight: .bold), color: scoreColor, spacing: 0)
        text("综合评分 / 100", font: .systemFont(ofSize: 11, weight: .medium), color: tertiary, spacing: 8)
        text(snapshot.overall.label, font: .systemFont(ofSize: 18, weight: .bold), color: scoreColor, spacing: 4)
        text(snapshot.summaryLine, font: .systemFont(ofSize: 11), color: secondary, spacing: 28)

        divider()
        sectionTitle("设备与网络")
        metricRow("主机名", snapshot.hostName)
        metricRow("系统", snapshot.system)
        metricRow("App 版本", snapshot.appVersion)
        metricRow("接口", snapshot.interfaceName ?? "—")
        metricRow("本机地址", snapshot.localAddress ?? "—")
        metricRow("子网", snapshot.subnet ?? "—")
        metricRow("推测网关", snapshot.gateway ?? "—")
        metricRow("诊断网卡", snapshot.diagnosticInterface ?? "系统默认")
        if let wifi = snapshot.wifi {
            metricRow("WiFi", "\(wifi.ssid) · \(percent(wifi.signalStrength))")
        }
    }

    func drawOverview() {
        sectionTitle("检测总览")
        text(
            "本报告由“一键检测”生成，按顺序执行全部 8 个网络工具。部分结果受 iOS 权限、ICMP 可见性和公共节点影响。",
            font: .systemFont(ofSize: 10),
            color: secondary,
            spacing: 12
        )

        for result in snapshot.results {
            let titleFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
            let statusFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let headlineFont = UIFont.systemFont(ofSize: 10)
            let rowHeight = max(
                measure(result.kind.title, font: titleFont, width: 150),
                max(
                    measure(result.status.label, font: statusFont, width: 54),
                    measure(result.headline, font: headlineFont, width: contentWidth - 222)
                )
            )
            ensure(rowHeight + 6)

            let status = statusColor(result.status)
            status.setFill()
            UIBezierPath(ovalIn: CGRect(x: margin, y: y + 4, width: 7, height: 7)).fill()

            drawString(
                result.kind.title,
                font: titleFont,
                color: ink,
                x: margin + 14,
                y: y,
                width: 150
            )
            drawString(
                result.status.label,
                font: statusFont,
                color: status,
                x: margin + 166,
                y: y,
                width: 54
            )
            drawString(
                result.headline,
                font: headlineFont,
                color: secondary,
                x: margin + 222,
                y: y,
                width: contentWidth - 222
            )
            y += rowHeight + 6
        }
    }

    func drawEnvironment() {
        sectionTitle("网络摘要")

        if let result = snapshot.results.first(where: { $0.kind == .subnet }) {
            for metric in result.metrics {
                metricRow(metric.label, metric.value)
            }
        }

        if let result = snapshot.results.first(where: { $0.kind == .dhcp }),
           let server = result.metrics.first(where: { $0.label == "服务器" }) {
            metricRow("DHCP 服务器", server.value)
        }
        if let result = snapshot.results.first(where: { $0.kind == .speed }) {
            for metric in result.metrics where ["下载", "上传", "节点"].contains(metric.label) {
                metricRow(metric.label, metric.value)
            }
        }
    }

    func draw(result: ReportTestResult) {
        ensure(72)
        divider()

        let status = statusColor(result.status)
        text(
            result.kind.title,
            font: .systemFont(ofSize: 16, weight: .bold),
            color: ink,
            spacing: 3
        )
        text(
            "\(result.status.label) · \(result.headline)",
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: status,
            spacing: 8
        )

        for metric in result.metrics {
            metricRow(metric.label, metric.value)
        }

        for detail in result.details {
            bullet(detail)
        }

        text(
            "耗时 \(String(format: "%.1f", result.duration)) s",
            font: .systemFont(ofSize: 9),
            color: tertiary,
            spacing: 8
        )
    }

    func drawNotes() {
        ensure(90)
        divider()
        sectionTitle("说明")
        bullet("Ping 超时不等于设备离线，目标可能主动丢弃 ICMP。")
        bullet("路由追踪与环路/风暴结果受 iOS 非特权 socket 限制，不能替代交换机侧抓包或端口镜像。")
        bullet("WiFi 的 SSID/BSSID 需要精确位置权限和 WiFi Info entitlement。")
        bullet("报告中的测速为快速模式（10 MB 下载 / 5 MB 上传），详细测速请到“内外网测速”。")
    }

    // MARK: - Drawing helpers

    private func drawHeader() {
        drawString(
            "网维宝 · 网络巡检报告",
            font: .systemFont(ofSize: 8, weight: .medium),
            color: tertiary,
            x: margin,
            y: 24,
            width: contentWidth - 60
        )
        drawString(
            "第 \(pageNumber) 页",
            font: .systemFont(ofSize: 8),
            color: tertiary,
            x: pageRect.width - margin - 54,
            y: 24,
            width: 54
        )
        y = 42
        line()
        y = 54
    }

    private func sectionTitle(_ title: String) {
        ensure(30)
        text(title, font: .systemFont(ofSize: 15, weight: .bold), color: ink, spacing: 8)
    }

    private func metricRow(_ label: String, _ value: String) {
        let labelWidth: CGFloat = 112
        let valueWidth = contentWidth - labelWidth
        let labelFont = UIFont.systemFont(ofSize: 10)
        let valueFont = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let height = max(
            measure(label, font: labelFont, width: labelWidth),
            measure(value, font: valueFont, width: valueWidth)
        )
        ensure(height + 4)

        drawString(
            label,
            font: labelFont,
            color: tertiary,
            x: margin,
            y: y,
            width: labelWidth
        )
        drawString(
            value,
            font: valueFont,
            color: secondary,
            x: margin + labelWidth,
            y: y,
            width: valueWidth
        )
        y += height + 3
    }

    private func bullet(_ value: String) {
        ensure(measure("• " + value, font: .systemFont(ofSize: 9.5), width: contentWidth) + 2)
        text(
            "• \(value)",
            font: .systemFont(ofSize: 9.5),
            color: secondary,
            spacing: 2
        )
    }

    private func divider() {
        ensure(14)
        line()
        y += 10
    }

    private func line() {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
        path.lineWidth = 0.5
        UIColor(red: 0.85, green: 0.87, blue: 0.89, alpha: 1).setStroke()
        path.stroke()
    }

    private func text(
        _ value: String,
        font: UIFont,
        color: UIColor,
        spacing: CGFloat,
        x: CGFloat? = nil,
        width: CGFloat? = nil
    ) {
        let drawX = x ?? margin
        let drawWidth = width ?? contentWidth
        let height = measure(value, font: font, width: drawWidth)
        ensure(height)
        drawString(
            value,
            font: font,
            color: color,
            x: drawX,
            y: y,
            width: drawWidth
        )
        y += height + spacing
    }

    private func drawString(
        _ value: String,
        font: UIFont,
        color: UIColor,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let height = measure(value, font: font, width: width)
        (value as NSString).draw(
            in: CGRect(x: x, y: y, width: width, height: height),
            withAttributes: attributes
        )
    }

    private func measure(_ value: String, font: UIFont, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let rect = (value as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return max(12, ceil(rect.height) + 1)
    }

    private func ensure(_ height: CGFloat) {
        if y + height > bottomLimit {
            newPage()
        }
    }

    private func statusColor(_ status: ReportStatus) -> UIColor {
        switch status {
        case .pass: return accent
        case .warning: return amber
        case .fail: return red
        case .skipped: return tertiary
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
