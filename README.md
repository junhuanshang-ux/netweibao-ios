# 网维宝 · NetWeiBao

<p align="center">
  <img src="NetWeiBao/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" alt="网维宝 App Icon">
</p>

<p align="center">
  <img src="https://github.com/junhuanshang-ux/netweibao-ios/actions/workflows/build-ipa.yml/badge.svg" alt="Build unsigned IPA">
</p>

面向现场网络工程师的 iPhone 诊断工具箱。8 个模块已全部上线：Ping、DHCP、路由追踪、环路、风暴、WiFi 分析、子网计算、内外网测速。

> 工程是原生 SwiftUI，最低 iOS 16.0。所有网络探测均使用 Apple 公开 API，不包含私有 API、越狱依赖或第三方统计 SDK。

---

## 下载与安装（GitHub Actions）

- 仓库：[junhuanshang-ux/netweibao-ios](https://github.com/junhuanshang-ux/netweibao-ios)
- 最新 Release：[github.com/junhuanshang-ux/netweibao-ios/releases/latest](https://github.com/junhuanshang-ux/netweibao-ios/releases/latest)
- 直接下载：[NetWeiBao-unsigned.ipa](https://github.com/junhuanshang-ux/netweibao-ios/releases/latest/download/NetWeiBao-unsigned.ipa)
- 本地工作区文件：`dist/NetWeiBao-unsigned.ipa`（已加入 `.gitignore`）
- SHA-256：`06c018e68f21f7eea34ea27040f2b43128095352e3a8c02bbcf5fe40bb7f79e1`

构建由 GitHub Actions 的 macOS runner 完成，工作流是 [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)。手动触发 `Build unsigned IPA` 后，会：

1. 用 `xcodebuild` 编译 Release 版；
2. 打包成 `NetWeiBao-unsigned.ipa`；
3. 上传 artifact；
4. 创建带 IPA 和 SHA-256 的 GitHub Release。

> **这是未签名（ad-hoc）IPA，不能直接双击安装。** 需要用 Sideloadly / AltStore / TrollStore（视 iOS 版本）重签安装；免费 Apple ID 签名通常 7 天有效，过期需重签。也可以在 Mac 上打开 Xcode 工程直接 Run。

Windows 本地不需要安装 Xcode；构建在 GitHub 的 macOS runner 上完成。

### 构建耗时优化

之前的等待主要来自 `macos-latest` 排队和完整 Release 构建。现在已改为：

- 固定 `runs-on: macos-15`，避免 latest 镜像调度波动；
- `actions/cache` 缓存 DerivedData，增量编译；
- `xcodebuild -quiet`，关闭 dSYM 和 index store；
- 只保留一个 workflow，`concurrency` 自动取消旧构建。

本次构建 job 约 **61 秒**；包含 GitHub 排队后约 **2 分钟**。之前那种十分钟级等待基本消除，但托管 runner 的排队仍可能受平台负载影响。

---

## 当前进度

| # | 模块 | 状态 |
|---|------|------|
| 1 | Ping（单机 / 网段 / 批量） | ✅ 已完成 |
| 2 | DHCP 服务器检测 | ✅ 已完成（待真机验证 UDP 68） |
| 3 | 路由追踪 | ✅ 已完成（受 ICMP 可见性限制） |
| 4 | 环路检测 | ✅ 已完成（启发式，受 iOS 限制） |
| 5 | 网络风暴检测 | ✅ 已完成（链路质量代理，受 iOS 限制） |
| 6 | WiFi 分析 | ✅ 已完成（仅当前连接） |
| 7 | 子网计算 | ✅ 已完成 |
| 8 | 内外网测速 | ✅ 已完成 |

### 工作台

- 顶部品牌/本机网络卡已移除，只保留“工具”网格，减少重复信息。
- 完整网络信息统一放在“首页”。

### 底部导航

**首页 / 工具 / 报告 / 关于**，不再单独放 Ping；Ping 仍可从工具网格进入。

### 报告已实现

- **一键检测**：依次执行 Ping、DHCP、路由追踪、环路、风暴、WiFi、子网计算和快速测速，共 8 项。
- 自动汇总为统计报告：综合评分、正常/需关注/失败/跳过数量、逐项指标与结论。
- **PDF**：自动生成 A4 中文报告，支持下载到文件、系统分享。
- 报告测速使用 **10 MB 下载 / 5 MB 上传**，避免巡检消耗 150 MB。
- 全局隐藏滚动条，不再显示右侧滚动指示器。

### 网络首页已实现

- 底部新增 **首页** Tab，作为 App 默认页。
- 动态显示网络路径状态（Wi-Fi / 蜂窝 / 有线 / 离线、计费网络、低数据模式）、主机名、系统版本。
- 列出全部接口：Wi-Fi、蜂窝、VPN、热点桥接、点对点、回环、其他。
- 每个接口显示 IPv4 / IPv6、前缀、点分掩码、UP/RUNNING 状态。
- 显示推测网关与 DNS（DNS 读取失败时明确标注“系统未公开”）。
- **切换网卡**：选择诊断出口接口；Ping、DHCP、路由追踪、环路/风暴通过 `IP_BOUND_IF` 绑定，测速通过 `NWConnection` 绑定同一接口类型。
- iPhone 不允许 App 直接切换 Wi-Fi/蜂窝，真正的联网切换需到系统设置；首页提供“系统设置”入口。

### 首次启动权限

首次打开会自动请求：

1. **定位（建议精确）**：WiFi 分析读取 SSID/BSSID、信号强度需要。
2. **本地网络**：通过短时 Bonjour 浏览触发 iOS 本地网络授权，用于 Ping、DHCP、路由追踪和局域网扫描。

不请求通知、相机、麦克风、照片或通讯录。权限状态和“去设置 / 精确位置 / 重新检测”入口都放在首页。

### Ping 已实现

- **单机 Ping**：IP / 域名解析、持续探测、超时与间隔可调、发送/接收/丢包/最小/平均/最大/抖动统计、最近 120 条响应。
- **网段 Ping**：CIDR 解析、自动带出本机网段、并发数 8/16/32、最多 4096 个地址、实时进度、在线/离线筛选。
- **批量 Ping**：IP / 域名 / CIDR 混输、自动展开 /24 及更小网段、最多 128 个目标、每目标 1–5 次探测、在线/失败统计。
- **工程能力**：IPv4 / CIDR 计算、本机 IPv4 与掩码识别、域名解析、可取消的并发扫描、统一的暗色设计系统、8 个模块的工作台与能力边界提示。

### DHCP 已实现

- 发送只读 **DHCPDISCOVER** 广播，收集并解析 **DHCPOFFER**，不请求租约、不占用地址。
- 展示服务器标识、分配地址、子网掩码、网关、DNS、租期、T1/T2、域名、广播地址、下一跳、启动文件与厂商信息。
- 同时发现多台 DHCP 服务器；按服务器标识去重。
- 优先绑定 UDP 68；失败时回退临时端口，并在界面明确提示“结果可能不完整”。
- 支持本网段广播与 `255.255.255.255` 双目标发送。

### 环路 / 风暴已实现

- **环路检测**：网关基线 → 10 个单播重复回声 → 8 个广播回声 → 网关复测；检测同源同序号重复 Echo Reply，并结合丢包、延迟、抖动给出“未发现 / 疑似 / 无法判断”。
- **风暴检测**：比较单播/广播探测前后的网关丢包、延迟、抖动，并统计重复回复，识别疑似广播风暴或链路拥塞。
- **目标自动探测**：默认目标不再死用 `.1`，开始检测时会同时探测网段第一个和最后一个地址（常见 `.1` / `.254`），优先使用有响应的候选。
- **广播无响应不再直接判“无法判断”**：广播 ICMP 被过滤时，结论主要依据单播重复回声与链路质量，并在结果页明确提示“广播级证据缺失”。
- 每次检测会给出“下一步建议”，例如确认网关、检查 STP/MAC 表、排查 Wi-Fi 重传、使用端口镜像等。
- 两个模块都明确标注为**启发式 / 代理指标**，不会输出“确认环路”或“确认风暴”的虚假结论。
- 受 iOS 限制，无法读取交换机 MAC/STP，也无法抓包；真正的二层定位仍需交换机命令、端口镜像或探针。

### 为什么之前两个都显示“无法判断”？

旧版本只依赖 `255.255.255.255` 的广播 Echo Reply，而很多网络/终端会直接过滤广播 ICMP；旧逻辑把“没有广播回复”当成了无法判断。另一个原因是默认目标只是网段第一个地址，未必是真实网关。

现在已改为：

1. 自动尝试 `.1` / `.254` 两个常见网关候选；
2. 增加目标单播重复回声检测，不再依赖广播回复；
3. 广播无响应只降低置信度，不再直接返回“无法判断”；
4. 结果页显示具体原因和下一步建议。

### 路由追踪已实现

- IPv4 逐跳 TTL 探测，1–30 跳、每跳超时 0.3–2.5 秒可调。
- 解析 ICMP Time Exceeded、Echo Reply、Destination Unreachable。
- 展示 TTL、跳点地址、RTT、目标/跳点/超时/不可达状态；支持中途停止。
- 如果 iOS 不向非特权 socket 暴露 Time Exceeded，会显示 `*` 和“路径不可见”警告，不伪造跳点。

### 子网计算已实现

- 支持 CIDR、`IP + 点分掩码`、单个 IP（按 /32）。
- 展示网络地址、广播地址、掩码、反掩码、首/末主机、可用主机数、总地址数、前缀与 32 位二进制。
- 支持一键使用本机网段；纯本地计算，不发起网络请求。

### WiFi 分析已实现

- 读取当前 SSID、BSSID、是否加密、是否自动加入、信号强度。
- 对网关做 6 次采样，展示平均延迟、丢包与抖动。
- 需要“精确”定位权限；SSID/BSSID 还需要 **Access WiFi Information** entitlement（已加入工程）。
- **SSID 读取失败时不再整页不可用**：仍显示 `en0` 接口、本机 IP、网段、推测网关和网关质量。
- 提供“允许 / 精确位置 / 去设置 / 刷新”操作入口。
- iOS 不允许扫描周边 AP；模拟器通常无法返回 SSID。

### 内外网测速已实现

- 外网默认节点：**洛杉矶 Sharktech LibreSpeed**（`https://laxspeed.sharktech.net/backend`），已验证 100 MB 下载和 50 MB 上传。
- **支持中国内节点**：把外网后端地址改成国内 LibreSpeed 的 `.../backend` 即可；国内公共测速站多有限网/反爬，所以没有内置固定地址。
- `www.speedtest.cn` 不是 LibreSpeed 后端，不能直接填入；它需要官方 SDK/授权 API。当前支持的是 LibreSpeed 兼容后端。
- 内网：填写自建 LibreSpeed 后端的 `.../backend` 地址，支持 NAS / 路由器 / 电脑。
- 测试流程：5 次延迟采样 → 默认 100 MB 下载 → 默认 50 MB 上传；下载（10–500 MB）和上传（5–200 MB）可在测速页手动调节。
- **测速也绑定“诊断网卡”**：使用 `NWConnection` 的 `requiredInterfaceType` 强制指定 Wi-Fi / 蜂窝 / 有线接口类型；未选择时走系统默认路由，绑定失败直接报错，不回退。
- 展示下载/上传 Mbps、平均延迟、抖动、丢包、传输字节与耗时；内网/外网都有结果时显示对比卡。
- 公共节点可能限速，结果不能直接等同运营商带宽。

---

## 在 Mac 上运行

环境要求：macOS + Xcode 15 或更新版本 + iOS 16 及以上的真机（ICMP 与局域网权限建议真机验证）。

1. 打开 `NetWeiBao.xcodeproj`。
2. 选中 `NetWeiBao` target → **Signing & Capabilities** → 选择你的 Apple Developer Team。
3. 如 Bundle Identifier 冲突，改成你自己的，例如 `com.yourname.netweibao`。
4. 连接 iPhone，选择设备后 Run。
5. 首次扫描局域网时，允许 **本地网络** 权限。

如果工程文件损坏或需要重建：

```bash
python3 scripts/generate_xcodeproj.py
```

也可以使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
xcodegen generate
```

### 命令行构建（可选）

```bash
xcodebuild \
  -project NetWeiBao.xcodeproj \
  -scheme NetWeiBao \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

在 macOS 上直接打未签名 IPA：

```bash
bash scripts/build-ipa.sh
```

产物：`dist/NetWeiBao-unsigned.ipa`。

---

## 目录结构

```text
NetWeiBao/
├── App/                     # App 入口、根 TabView、Info.plist
├── Core/                    # 设计系统、IPv4、CIDR、本机网络、DNS
├── Features/
│   ├── NetworkHome/         # 首页：接口、网关、DNS、网卡切换
│   ├── Home/                # 工具网格
│   ├── Report/              # 一键巡检、PDF 生成与分享
│   ├── Ping/                # Ping 引擎与三个模式
│   ├── SpeedTest/           # 内外网测速
│   ├── WiFi/                # WiFi 分析
│   └── About/               # 关于与 iOS 能力边界
└── Assets.xcassets/         # AppIcon、AccentColor、LaunchBackground

.github/workflows/
└── build-ipa.yml            # GitHub Actions 未签名 IPA 构建 + Release

scripts/
├── build-ipa.sh             # macOS 本地构建 IPA
├── generate_xcodeproj.py    # 无 Xcode 环境下生成 .xcodeproj
├── generate_app_icon.py     # 生成 1024×1024 图标
└── validate_project.py      # 工程 / 资源 / 配置静态检查

builder.json                 # iBuilder / 仓库构建元数据
dist/                        # 本地下载的 IPA（不提交到 git）

docs/
└── FEASIBILITY.md           # 八个模块的 iOS 可行性、限制与建议
```

### Ping 的实现方式

- 使用 `SOCK_DGRAM` + `IPPROTO_ICMP` 的非特权 ICMP Echo，不依赖 root 或 raw socket。
- 每次探测构造 ICMP Echo Request（含校验和与随机 identifier / 递增 sequence），用 `poll` 等待 Echo Reply。
- 通过 `OperationQueue` 限制同时阻塞的探测数量，避免网段扫描耗尽文件描述符。
- 网段/批量扫描使用 Swift `TaskGroup` 控制窗口并发，支持取消；旧任务用 run token 隔离，避免结果串台。
- 域名解析走 `getaddrinfo`，在后台队列执行，支持 `.local` / mDNS 主机名。

---

## 真机验证清单

- [ ] 单机 Ping `127.0.0.1`、网关、`223.5.5.5`、域名。
- [ ] 关闭“持续 Ping”后只发送一次。
- [ ] 运行中切换 Tab / 返回，探测停止且 UI 状态正确。
- [ ] `/30`、`/24` 网段扫描；扫描中停止后不再追加结果。
- [ ] 批量输入 IP、域名、`192.168.1.0/24`，确认 CIDR 展开与数量上限提示。
- [ ] 拒绝“本地网络”权限后，错误提示可读，不崩溃。
- [ ] 飞行模式下单机 / 网段 / 批量均有明确失败态。
- [ ] 大网段（如 `/20`）滚动流畅度与内存占用。

---

## 已知限制

- 目标可能主动丢弃 ICMP，**超时不等于设备离线**。
- iOS 会在首次访问局域网时弹“本地网络”权限；拒绝后探测会失败。
- 当前探测只支持 IPv4；首页会展示 IPv6 地址，但 Ping / DHCP / 路由追踪仍为 IPv4。
- 路由追踪依赖 iOS 是否向非特权 ICMP socket 暴露 `Time Exceeded`；不暴露时只能显示 `*`，不能伪造跳点。
- “切换网卡”会绑定 BSD socket 诊断模块和 `NWConnection` 测速；系统 DNS 和实际联网路由仍由 iOS 决定。iPhone 上不能由 App 直接切换 Wi-Fi/蜂窝。
- DNS 通过 `/etc/resolv.conf` 尽力读取；iOS 沙盒可能隐藏，界面会标注“系统未公开”。
- WiFi 只读取当前连接，不能扫描周边 AP；需要“精确”定位权限和 Access WiFi Information entitlement。
- Sideloadly / AltStore 重签时，所用 provisioning profile 也需要支持 `com.apple.developer.networking.wifi-info`；否则 WiFi 详情可能为空或签名失败。
- 外网测速默认使用第三方 LibreSpeed 公共节点，可能被限速或临时不可用；内网测速必须在局域网自建 LibreSpeed 后端。
- 测速会消耗流量（默认下载 100 MB + 上传 50 MB），且结果受节点、WiFi、运营商和当前负载影响；可在测速页调小。
- 报告中的测速固定为快速模式（10 MB 下载 / 5 MB 上传），详细带宽请到“内外网测速”单独测试。
- PDF 分享/下载依赖系统文件界面；报告数据仅保存在本机临时目录，App 退出后不保留。
- 扫描/测速结果仅保存在内存，退出 App 后不保留。
- App 进入后台后系统可能挂起探测，长时间扫描请保持前台。
- 这是网络诊断工具，不替代交换机侧抓包、端口镜像或厂商网管系统。

更完整的模块可行性、系统限制和替代方案见 [docs/FEASIBILITY.md](docs/FEASIBILITY.md)。

---

## 下一步

8 个模块已全部完成。后续可以继续做：结果导出/分享、历史记录、IPv6、更多测速节点自动选择，以及探针联动（环路/风暴/周边 AP 的真实抓包能力）。
