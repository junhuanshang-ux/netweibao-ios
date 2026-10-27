import SwiftUI

enum PingMode: String, CaseIterable, Identifiable, Hashable {
    case single = "单机"
    case subnet = "网段"
    case batch = "批量"

    var id: String { rawValue }
}

struct PingDashboardView: View {
    @StateObject private var single = SinglePingViewModel()
    @StateObject private var subnet = SubnetPingViewModel()
    @StateObject private var batch = BatchPingViewModel()

    @State private var mode: PingMode = .single
    @State private var localAddress = NetworkInterface.activeIPv4()?.address.description

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    modePicker
                    modeContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Ping")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: mode) { newMode in
            if newMode != .single { single.stop() }
            if newMode != .subnet { subnet.stop() }
            if newMode != .batch { batch.stop() }
        }
        .onDisappear {
            single.stop()
            subnet.stop()
            batch.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("连通性诊断")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("ICMP Echo · 单机 / 网段 / 批量")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 4)

            StatusBadge(
                text: localAddress ?? "无 IPv4",
                color: localAddress == nil ? AppTheme.amber : AppTheme.accent
            )
        }
        .padding(.vertical, 4)
    }

    private var modePicker: some View {
        Picker("Ping 模式", selection: $mode) {
            ForEach(PingMode.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .single:
            SinglePingView(viewModel: single)
        case .subnet:
            SubnetPingView(viewModel: subnet)
        case .batch:
            BatchPingView(viewModel: batch)
        }
    }
}
