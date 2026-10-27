import Foundation
import SwiftUI

struct SubnetCalculatorView: View {
    @State private var input: String

    init() {
        _input = State(
            initialValue: NetworkInterface.activeIPv4()?.subnet.cidr ?? "192.168.1.0/24"
        )
    }

    private var parsed: SubnetParseResult? {
        parse(input)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    inputCard

                    if let parsed {
                        resultContent(parsed)
                    } else if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ErrorBanner(message: "无法解析。支持 CIDR、IP + 点分掩码，或单个 IP。")
                    }

                    InlineInfoNote(
                        text: "纯本地计算，不发起网络请求。输入可以是 192.168.1.0/24、192.168.1.10 255.255.255.0，或单个 IP（按 /32 处理）。"
                    )
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("子网计算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color(hex: 0x9CCC65).opacity(0.13))
                Image(systemName: "number.square")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x9CCC65))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("子网计算")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("CIDR · 掩码 · 主机范围")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 4)

            StatusBadge(text: "纯本地", color: AppTheme.accent)
        }
        .padding(.vertical, 4)
    }

    private var inputCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "输入")

                    Spacer()

                    Button("使用本机网段") {
                        if let local = NetworkInterface.activeIPv4() {
                            input = local.subnet.cidr
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0x9CCC65))

                    TextField("192.168.1.0/24", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                }
                .terminalField()

                if let local = NetworkInterface.activeIPv4() {
                    Text("本机 \(local.address.description) · \(local.subnet.description)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func resultContent(_ parsed: SubnetParseResult) -> some View {
        let subnet = parsed.subnet

        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(title: "网络")
                    Spacer()
                    StatusBadge(text: "/\(subnet.prefixLength)", color: AppTheme.blue)
                }

                Text(subnet.cidr)
                    .font(.system(size: 27, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let inputAddress = parsed.inputAddress,
                   inputAddress != subnet.network {
                    Text("输入地址 \(inputAddress.description) 已归一化为网络地址")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }

        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "地址结构")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    SubnetValueTile(title: "网络地址", value: subnet.network.description)
                    SubnetValueTile(title: "广播地址", value: subnet.broadcast.description)
                    SubnetValueTile(title: "子网掩码", value: subnet.netmask.description)
                    SubnetValueTile(
                        title: "反掩码",
                        value: IPv4Address(value: ~subnet.netmask.value).description
                    )
                    SubnetValueTile(title: "第一个主机", value: subnet.firstHost.description)
                    SubnetValueTile(title: "最后一个主机", value: subnet.lastHost.description)
                }

                Divider().background(AppTheme.stroke)

                HStack(spacing: 0) {
                    SubnetMetric(
                        title: "可用主机",
                        value: "\(subnet.usableHostCount)"
                    )
                    SubnetDivider()
                    SubnetMetric(
                        title: "总地址",
                        value: "\(subnet.totalAddressCount)"
                    )
                    SubnetDivider()
                    SubnetMetric(
                        title: "前缀",
                        value: "/\(subnet.prefixLength)"
                    )
                }
            }
        }

        AppCard {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(title: "二进制")
                binaryRow("网络", value: subnet.network.value)
                binaryRow("掩码", value: subnet.netmask.value)
            }
        }
    }

    private func binaryRow(_ label: String, value: UInt32) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 28, alignment: .leading)

            Text(binary(value))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private func binary(_ value: UInt32) -> String {
        let raw = String(value, radix: 2)
        let padded = String(repeating: "0", count: max(0, 32 - raw.count)) + raw
        return stride(from: 0, to: 32, by: 8)
            .map { offset in
                let start = padded.index(padded.startIndex, offsetBy: offset)
                let end = padded.index(start, offsetBy: 8)
                return String(padded[start..<end])
            }
            .joined(separator: ".")
    }

    private func parse(_ raw: String) -> SubnetParseResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("/") {
            guard let subnet = IPv4Subnet(cidr: trimmed) else { return nil }
            let addressPart = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init)
            return SubnetParseResult(
                subnet: subnet,
                inputAddress: addressPart.flatMap(IPv4Address.init)
            )
        }

        let parts = trimmed
            .components(separatedBy: CharacterSet(charactersIn: " ,\t"))
            .filter { !$0.isEmpty }

        guard let first = parts.first.flatMap(IPv4Address.init) else { return nil }

        if parts.count == 1 {
            return SubnetParseResult(
                subnet: IPv4Subnet(address: first, prefixLength: 32),
                inputAddress: first
            )
        }

        guard parts.count == 2, let mask = IPv4Address(parts[1]) else {
            return nil
        }
        let prefix = NetworkInterface.prefixLength(for: mask)
        guard IPv4Subnet.mask(for: prefix) == mask.value else {
            return nil
        }
        return SubnetParseResult(
            subnet: IPv4Subnet(address: first, prefixLength: prefix),
            inputAddress: first
        )
    }
}

private struct SubnetParseResult {
    let subnet: IPv4Subnet
    let inputAddress: IPv4Address?
}

private struct SubnetValueTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfaceRaised)
        )
    }
}

private struct SubnetMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SubnetDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.stroke)
            .frame(width: 1, height: 24)
    }
}
