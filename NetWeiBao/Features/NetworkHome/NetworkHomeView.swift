import Network
import SwiftUI

struct NetworkHomeView: View {
    @StateObject private var viewModel = NetworkHomeViewModel()
    @EnvironmentObject private var permissions: PermissionCoordinator

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    pathCard
                    interfaceSwitcher
                    if let selected = viewModel.selectedInterface {
                        selectedInterfaceCard(selected)
                    }
                    networkServicesCard
                    allInterfacesCard
                    permissionsCard
                    InlineInfoNote(
                        text: "“诊断网卡”会用于 Ping、DHCP、路由追踪、环路/风暴，以及内外网测速。iPhone 不能由 App 直接切换 Wi-Fi/蜂窝，实际联网切换请到系统设置。"
                    )
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "network")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x04120E))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("首页")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("本机网络全貌 · 动态刷新")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            Button {
                viewModel.refresh()
                viewModel.detectGateway()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AppTheme.accent.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var pathCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatusDot(color: viewModel.pathStatus == .satisfied ? AppTheme.accent : AppTheme.amber)
                    Text(viewModel.pathText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    StatusBadge(
                        text: viewModel.pathStatus == .satisfied ? "在线" : "离线",
                        color: viewModel.pathStatus == .satisfied ? AppTheme.accent : AppTheme.amber
                    )
                }

                HStack(spacing: 14) {
                    labeledValue("主机名", viewModel.hostName)
                    labeledValue("系统", "\(viewModel.systemName) \(viewModel.systemVersion)")
                }

                Text(viewModel.pathDetail)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)

                if viewModel.pathStatus == .satisfied {
                    HStack(spacing: 6) {
                        pathBadge(viewModel.usesWiFi, "Wi-Fi")
                        pathBadge(viewModel.usesCellular, "蜂窝")
                        pathBadge(viewModel.usesWired, "有线")
                    }
                }
            }
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func pathBadge(_ active: Bool, _ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(active ? AppTheme.accent : AppTheme.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(active ? AppTheme.accent.opacity(0.12) : Color.white.opacity(0.04))
            )
    }

    private var interfaceSwitcher: some View {
        AppCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((viewModel.selectedInterface?.type.tint ?? AppTheme.blue).opacity(0.12))
                    Image(systemName: viewModel.selectedInterface?.type.icon ?? "network")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(viewModel.selectedInterface?.type.tint ?? AppTheme.blue)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("诊断网卡")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(viewModel.selectedInterface?.displayName ?? "系统默认路由")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                Menu {
                    Button {
                        viewModel.useSystemDefault()
                    } label: {
                        Label("系统默认路由", systemImage: "arrow.triangle.branch")
                    }

                    ForEach(
                        viewModel.interfaces.filter {
                            !$0.ipv4Addresses.isEmpty && $0.type != .loopback
                        }
                    ) { interface in
                        Button {
                            viewModel.select(interface)
                        } label: {
                            Label(
                                "\(interface.displayName) · \(interface.primaryIPv4 ?? "")",
                                systemImage: interface.type.icon
                            )
                        }
                    }
                } label: {
                    Label("切换网卡", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(AppTheme.accent.opacity(0.11)))
                }
            }
        }
    }

    private func selectedInterfaceCard(_ interface: NetworkInterfaceSnapshot) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "接口详情")

                    Spacer()

                    StatusBadge(
                        text: interface.isUp ? "UP" : "DOWN",
                        color: interface.isUp ? AppTheme.accent : AppTheme.textTertiary
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: interface.type.icon)
                        .foregroundStyle(interface.type.tint)
                    Text(interface.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    if interface.isRunning {
                        Text("RUNNING")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                if interface.addresses.isEmpty {
                    Text("接口没有可用地址")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                } else {
                    ForEach(interface.addresses) { address in
                        addressRow(address)
                    }
                }
            }
        }
    }

    private func addressRow(_ address: InterfaceAddress) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(address.family.rawValue)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(address.family == .ipv4 ? AppTheme.blue : Color(hex: 0x9B8CFF))
                .frame(width: 28, alignment: .leading)

            Text(address.address)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            if let prefix = address.prefixLength {
                Text("/\(prefix)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if let netmask = address.netmask {
                Text(netmask)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var networkServicesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "网络服务")

                HStack {
                    Text("推测网关")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer()
                    Text(viewModel.gateway?.description ?? "—")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Divider().background(AppTheme.stroke)

                VStack(alignment: .leading, spacing: 5) {
                    Text("DNS")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)

                    if viewModel.dnsServers.isEmpty {
                        Text("系统未公开或不可读")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                    } else {
                        ForEach(viewModel.dnsServers, id: \.self) { server in
                            Text(server)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var allInterfacesCard: some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(title: "全部接口")
                    Spacer()
                    Text("\(viewModel.interfaces.count) 个")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(AppTheme.stroke)

                LazyVStack(spacing: 0) {
                    ForEach(viewModel.interfaces) { interface in
                        Button {
                            viewModel.select(interface)
                        } label: {
                            interfaceRow(interface)
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            interface.ipv4Addresses.isEmpty
                                || interface.type == .loopback
                        )

                        Divider()
                            .background(AppTheme.stroke)
                            .padding(.leading, 50)
                    }
                }
            }
        }
    }

    private func interfaceRow(_ interface: NetworkInterfaceSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: interface.type.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(interface.type.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(interface.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(interface.primaryIPv4 ?? "无 IPv4 地址")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            if viewModel.selectedName == interface.name {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            } else if !interface.isUp {
                Text("DOWN")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var permissionsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "权限")
                    Spacer()
                    Button("系统设置") {
                        permissions.openSettings()
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
                    .buttonStyle(.plain)
                }

                permissionRow(
                    title: "定位（WiFi 详情）",
                    status: permissions.locationText,
                    active: permissions.isLocationAuthorized,
                    actionTitle: locationActionTitle,
                    action: locationAction
                )

                Divider().background(AppTheme.stroke)

                permissionRow(
                    title: "本地网络",
                    status: permissions.localNetworkText,
                    active: permissions.localNetworkStatus == .authorized,
                    actionTitle: "重新检测",
                    action: permissions.requestLocalNetwork
                )

                Text("首次打开会自动请求定位权限，并通过 Bonjour 触发本地网络授权；WiFi 详情还需要精确位置。")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var locationActionTitle: String {
        if permissions.locationStatus == .notDetermined { return "授权" }
        if permissions.locationStatus == .denied { return "去设置" }
        if permissions.locationStatus == .authorizedWhenInUse
            || permissions.locationStatus == .authorizedAlways {
            return permissions.accuracyAuthorization == .reducedAccuracy ? "精确位置" : "刷新"
        }
        return "授权"
    }

    private func locationAction() {
        if permissions.locationStatus == .denied {
            permissions.openSettings()
        } else {
            permissions.requestLocation()
        }
    }

    private func permissionRow(
        title: String,
        status: String,
        active: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            StatusDot(color: active ? AppTheme.accent : AppTheme.amber)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(status)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer()
            Button(actionTitle, action: action)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .buttonStyle(.plain)
        }
    }
}

private extension InterfaceType {
    var icon: String {
        switch self {
        case .wifi:
            return "wifi"
        case .ethernet:
            return "cable.connector"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .vpn:
            return "lock.shield"
        case .bridge:
            return "point.3.connected.trianglepath.dotted"
        case .peer:
            return "arrow.triangle.2.circlepath"
        case .loopback:
            return "arrow.uturn.backward"
        case .other:
            return "network"
        }
    }

    var tint: Color {
        switch self {
        case .wifi:
            return AppTheme.blue
        case .ethernet:
            return AppTheme.accent
        case .cellular:
            return AppTheme.blue
        case .vpn:
            return Color(hex: 0x9B8CFF)
        case .bridge:
            return AppTheme.amber
        case .peer:
            return AppTheme.textSecondary
        case .loopback:
            return AppTheme.textTertiary
        case .other:
            return AppTheme.textSecondary
        }
    }
}
