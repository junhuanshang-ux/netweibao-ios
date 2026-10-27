# 网维宝 · NetWeiBao

<p align="center">
  <img src="NetWeiBao/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" alt="网维宝 App Icon">
</p>

<p align="center">
  <img src="https://github.com/junhuanshang-ux/netweibao-ios/actions/workflows/build-ipa.yml/badge.svg" alt="Build unsigned IPA">
</p>

面向现场网络工程师的 iPhone 诊断工具箱。当前版本聚焦第 1 个模块：**Ping（单机 / 网段 / 批量）**，其余模块按顺序接入。

> 工程是原生 SwiftUI，最低 iOS 16.0。所有网络探测均使用 Apple 公开 API，不包含私有 API、越狱依赖或第三方统计 SDK。

---

## 下载与安装（GitHub Actions）

- 仓库：[junhuanshang-ux/netweibao-ios](https://github.com/junhuanshang-ux/netweibao-ios)
- 最新 Release：[github.com/junhuanshang-ux/netweibao-ios/releases/latest](https://github.com/junhuanshang-ux/netweibao-ios/releases/latest)
- 直接下载：[NetWeiBao-unsigned.ipa](https://github.com/junhuanshang-ux/netweibao-ios/releases/latest/download/NetWeiBao-unsigned.ipa)
- 本地工作区文件：`dist/NetWeiBao-unsigned.ipa`（已加入 `.gitignore`）
- SHA-256：`6378be2fc8394af8059c4834f4ad8b20bd657af905a741a5a9d142e7740cf650`

构建由 GitHub Actions 的 macOS runner 完成，工作流是 [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)。手动触发 `Build unsigned IPA` 后，会：

1. 用 `xcodebuild` 编译 Release 版；
2. 打包成 `NetWeiBao-unsigned.ipa`；
3. 上传 artifact；
4. 创建带 IPA 和 SHA-256 的 GitHub Release。

> **这是未签名（ad-hoc）IPA，不能直接双击安装。** 需要用 Sideloadly / AltStore / TrollStore（视 iOS 版本）重签安装；免费 Apple ID 签名通常 7 天有效，过期需重签。也可以在 Mac 上打开 Xcode 工程直接 Run。

Windows 本地不需要安装 Xcode；构建在 GitHub 的 macOS runner 上完成。

---

## 当前进度

| # | 模块 | 状态 |
|---|------|------|
| 1 | Ping（单机 / 网段 / 批量） | ✅ 已完成 |
| 2 | DHCP 服务器检测 | ⏳ 待开发 |
| 3 | 路由追踪 | ⏳ 待开发 |
| 4 | 环路检测 | ⏳ 待开发 |
| 5 | 网络风暴检测 | ⏳ 待开发（受 iOS 抓包权限限制） |
| 6 | WiFi 分析 | ⏳ 待开发（仅当前连接） |
| 7 | 子网计算 | ⏳ 待开发（核心算法已就绪） |
| 8 | 内外网测速 | ⏳ 待开发 |

### Ping 已实现

- **单机 Ping**：IP / 域名解析、持续探测、超时与间隔可调、发送/接收/丢包/最小/平均/最大/抖动统计、最近 120 条响应。
- **网段 Ping**：CIDR 解析、自动带出本机网段、并发数 8/16/32、最多 4096 个地址、实时进度、在线/离线筛选。
- **批量 Ping**：IP / 域名 / CIDR 混输、自动展开 /24 及更小网段、最多 128 个目标、每目标 1–5 次探测、在线/失败统计。
- **工程能力**：IPv4 / CIDR 计算、本机 IPv4 与掩码识别、域名解析、可取消的并发扫描、统一的暗色设计系统、8 个模块的工作台与能力边界提示。

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
│   ├── Home/                # 工作台、工具目录、占位页
│   ├── Ping/                # Ping 引擎、模型、三个模式的 UI
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
- 当前只支持 IPv4；IPv6、TTL / 路由跳数尚未接入。
- 扫描结果仅保存在内存，退出 App 后不保留。
- App 进入后台后系统可能挂起探测，长时间扫描请保持前台。
- 这是网络诊断工具，不替代交换机侧抓包、端口镜像或厂商网管系统。

更完整的模块可行性、系统限制和替代方案见 [docs/FEASIBILITY.md](docs/FEASIBILITY.md)。

---

## 下一步

按顺序实现 **DHCP 服务器检测**：DHCP DISCOVER / OFFER 报文、服务器标识、租期、网关与 DNS 解析，并在真机上验证 UDP 67/68 与广播行为。
