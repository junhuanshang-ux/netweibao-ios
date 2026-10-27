import SwiftUI

struct ToolItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let available: Bool
    let details: String
    let capabilities: [String]
    let feasibility: String
}

enum ToolCatalog {
    static let items: [ToolItem] = [
        ToolItem(
            id: "ping",
            title: "Ping",
            subtitle: "单机 / 网段 / 批量",
            icon: "dot.radiowaves.left.and.right",
            tint: AppTheme.accent,
            available: true,
            details: "向目标发送 ICMP Echo 请求，测量可达性、往返延迟、丢包与抖动。",
            capabilities: [
                "单机持续 Ping 与统计",
                "CIDR 网段并发扫描",
                "批量 IP / 域名 / CIDR 探测"
            ],
            feasibility: "基于 iOS 公开的 BSD Socket 能力实现，无需私有 API。"
        ),
        ToolItem(
            id: "dhcp",
            title: "DHCP 检测",
            subtitle: "发现与租约识别",
            icon: "server.rack",
            tint: AppTheme.blue,
            available: true,
            details: "发现局域网中的 DHCP 服务器，读取 OFFER 中的服务器标识、租期、网关与 DNS。",
            capabilities: [
                "广播 DHCP DISCOVER",
                "解析 OFFER 与服务器指纹",
                "展示网关、DNS 与租期"
            ],
            feasibility: "需要绑定 UDP 68 并收发广播包，真机权限和不同网络策略需要在设备上验证。"
        ),
        ToolItem(
            id: "traceroute",
            title: "路由追踪",
            subtitle: "逐跳路径与延迟",
            icon: "arrow.triangle.branch",
            tint: Color(hex: 0x9B8CFF),
            available: false,
            details: "逐步增加 TTL，观察数据包经过的网关与路径延迟，定位跨网段故障点。",
            capabilities: [
                "IPv4 逐跳追踪",
                "每跳延迟与超时统计",
                "路径异常标记"
            ],
            feasibility: "iOS 不提供 raw socket。计划使用 UDP/TCP 递增 TTL 并解析 ICMP 错误，部分网络只能得到有限跳数。"
        ),
        ToolItem(
            id: "loop",
            title: "环路检测",
            subtitle: "路径回环启发式分析",
            icon: "arrow.triangle.2.circlepath",
            tint: AppTheme.amber,
            available: true,
            details: "通过基线采样、广播重复回声与链路质量变化，识别疑似二层环路。",
            capabilities: [
                "网关基线采样",
                "广播重复回声检测",
                "广播前后链路对比"
            ],
            feasibility: "无法读取交换机 MAC 表或 STP 状态，只能做基于重复回声与链路质量的启发式判断，不能确认环路。"
        ),
        ToolItem(
            id: "storm",
            title: "风暴检测",
            subtitle: "链路质量代理指标",
            icon: "bolt.circle",
            tint: AppTheme.danger,
            available: true,
            details: "通过低强度广播探测前后的网关质量变化，识别疑似广播风暴或链路拥塞。",
            capabilities: [
                "低强度广播探测",
                "广播前后质量对比",
                "重复回复统计"
            ],
            feasibility: "公开 API 无法抓包或开启混杂模式。只提供链路质量代理指标，无法替代端口镜像抓包分析。"
        ),
        ToolItem(
            id: "wifi",
            title: "WiFi 分析",
            subtitle: "当前连接质量",
            icon: "wifi",
            tint: Color(hex: 0x4DD0E1),
            available: false,
            details: "查看当前 SSID、BSSID、信号强度与安全类型，并结合网关延迟评估无线链路。",
            capabilities: [
                "当前网络身份与信号强度",
                "网关延迟与抖动",
                "无线链路质量评分"
            ],
            feasibility: "iOS 不允许扫描周边 AP，仅能读取当前网络。需要定位权限和 WiFi Info entitlement。"
        ),
        ToolItem(
            id: "subnet",
            title: "子网计算",
            subtitle: "CIDR / 掩码换算",
            icon: "number.square",
            tint: Color(hex: 0x9CCC65),
            available: false,
            details: "在 CIDR、掩码、网络地址、广播地址与可用主机范围之间快速换算。",
            capabilities: [
                "CIDR 与点分掩码互转",
                "网络/广播/主机范围",
                "可用地址数量"
            ],
            feasibility: "纯本地计算，无网络权限要求。"
        ),
        ToolItem(
            id: "speed",
            title: "内外网测速",
            subtitle: "吞吐 / 延迟 / 抖动",
            icon: "speedometer",
            tint: Color(hex: 0xFF8A65),
            available: false,
            details: "对内网网关或公网测速端点执行下载、上传与延迟测试，区分内网和外网瓶颈。",
            capabilities: [
                "下载与上传吞吐",
                "延迟与抖动",
                "内网 / 公网目标对比"
            ],
            feasibility: "使用 URLSession 对自建或授权测速端点传输。公共测速服务通常需要 API 授权。"
        )
    ]
}
