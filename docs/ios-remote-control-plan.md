# DSH-Go iOS 远程遥控方案（工作量 + 自建中转）

> 基于 fork：https://github.com/hzopc1031/DSH-Go  
> 上游主仓：https://github.com/ccch1mneyyy/dsh-Go  
> 遥控协议来源：https://github.com/liguobao/ds-harness-remote（MIT）  
> 撰写日期：2026-11-08（Asia/Shanghai）  
> 范围：先做「手机遥控电脑上的 DSH」，本机引擎（手机内跑 Linux/DSH）列为后续；不包含 App Store 上架与证书采购决策。

---

## 1. 目标与非目标

### 目标（MVP）
- iOS App（Flutter）可登录 **自建 Remote Server**，列出在线 Host（台式/笔记本上的 DSH + `ds-harness-remote` 插件）。
- 连接后用与 Android 版相同的聊天/审批能力遥控电脑上的会话（经端到端加密隧道）。
- 连接路径按官方语义：`LAN → P2P → TURN → Relay`；失败自动回落。
- 默认不再依赖公共中转 `https://dsh.r2049.cn`，改为 Liu 自己的域名/服务器。
- 客户端 **可配置** `serverUrl`（设置页 + 可选编译期默认）。

### 非目标（首期不做）
- 手机本机安装 Ubuntu/DSH 引擎（Android 的 PRoot 运行时，iOS 不可直接复用）。
- 手机操控（无障碍/屏幕点击）——属本机引擎能力。
- 冒充官方品牌/Deepy/鲸娘素材二次分发（见 `ASSETS.md`）；较大改造发布前仍应按上游要求联系作者。
- 未经 Liu 确认的花钱、开 Apple 开发者账号、上架、开放额外公网端口。

---

## 2. 现状快照（来自仓库与文档）

| 项 | 事实 |
| --- | --- |
| 客户端形态 | Flutter；`app/` 目前只有 `android/`，**没有 `ios/` 工程目录** |
| 远程能力 | 已有 `packages/dsh_remote`（纯 Dart）+ `dartssh2`（SSH）+ `flutter_webrtc` |
| 默认 Remote 服务器 | `https://dsh.r2049.cn`（李国宝项目托管；`RemoteAccount.serverUrl` 可改） |
| Host 侧 | 电脑装 DSH，再装插件 `ds-harness-remote`；Host **只出站连接**，一般不需公网入站端口 |
| iOS 先例 | ds-harness-remote 官方有 TestFlight 测试，**未公开发布**；DSH Go 上游 README 写明计划适配 iOS |
| 本机环境 | 台式可跑 Codex；Windows 上 PATH 暂无 Flutter；**Mac 尚未接入**，真机构建需 Mac + Xcode |

---

## 3. 遥控架构（「中转服务器」到底是什么）

遥控不是单一 frp 端口转发，而是 **账号控制面 + 可选数据面中转**：

```
iOS / Android 客户端
        │  HTTPS REST（登录、列 Host、发 TURN 临时凭证）
        │  WebSocket Control（/ws/v1/connect：握手、信令、心跳）
        ▼
┌─────────────────────────────────────────────┐
│  Remote Server（控制面，必须自建/替换的核心） │
│  - 账号与设备凭证                             │
│  - Host 在线发现                              │
│  - WebRTC 信令转发（offer/answer/ICE）       │
│  - 短时 STUN/TURN 凭证下发                   │
│  - 内置加密 Relay（WebSocket 转发密文）       │
└─────────────────────────────────────────────┘
        │                         │
        │ 信令                    │ 回落：密文 Relay
        ▼                         ▼
   WebRTC DataChannel        Relay 数据通道
   LAN / P2P / TURN
        │
        ▼
电脑 Host：DSH + ds-harness-remote 插件
（会话明文只在 Client↔Host 两端解密；Noise_IK E2EE）
```

### 3.1 三类「服务器」角色（别混）

| 角色 | 类型 | 干什么 | 是否必须自建 |
| --- | --- | --- | --- |
| **Remote Server（控制面）** | Node 单进程服务（官方开源 `apps/server`，可 Docker） | 登录、设备、Host 列表、Control WS、可选签发 TURN 凭证、内置 Relay | **是**（要把公共 `dsh.r2049.cn` 换成自己的） |
| **TURN（coturn）** | 独立 UDP/TCP 中继（coturn） | NAT 打洞失败时转发 WebRTC 包；仍是密文隧道外的网络层中继 | 推荐，非绝对必须；不配则更多走 Server Relay |
| **Relay 节点** | Server 内置 / 可扩展数据 WS | P2P/TURN 都失败时，用 WebSocket 转发 **Noise 密文** | 开源自建 Server 已带 Relay；公网质量取决于机器带宽与地域 |

> 业务会话（提示词、工具输出等）经 Noise 端到端加密；中转看到的是密文与必要的控制元数据（账号、在线、连接 ID 等），按上游安全说明：**不能读会话正文**。首次信任 Host 指纹仍依赖 Server 下发的描述符，自建后信任边界在你自己的 Server。

### 3.2 App 要配几个地址？

- **对 App 通常只配一个**：自建 Remote Server 的 HTTPS origin（`serverUrl`）。
- TURN/coturn 地址写在 **Server 环境变量**；客户端通过 `GET /api/v1/turn/credentials` 取临时凭证，**不必**在 App 再填第二个服务地址。

### 3.3 两条客户端遥控路径（可并存）

1. **DSH Remote（推荐跨网）** — 可配置 `serverUrl`；自建 Server 用账号密码登录；Host 插件指向同一 Server。  
2. **SSH** — 适合同一内网/已有 SSH；不依赖 Remote Server。MVP 建议先做 DSH Remote。

---

## 4. 换成自己的中转：落地步骤

### 4.1 最小可用（Relay 为主）
1. 在有公网 IP/域名的机器部署：`ghcr.io/liguobao/ds-harness-remote/server:latest` 或源码 `apps/server` Docker Compose。  
2. 配置 `.env`：`DSH_SERVER_ACCOUNT` / `DSH_SERVER_PASSWORD`（≥12 位）/ `DSH_SERVER_PUBLIC_URL=https://remote.你的域名`。  
3. 前面加 **HTTPS 反代**（Nginx/Caddy），并支持 WebSocket：`/ws/v1/connect`，空闲超时 **>75s**。  
4. 电脑 DSH 安装 `ds-harness-remote`，登录指向同一 URL。  
5. 客户端 `RemoteAccount(serverUrl: 'https://remote.你的域名')`。  

不配 STUN/TURN 时：主要为 **Relay**，仍可用，延迟与带宽吃 Server。

### 4.2 完整路径（LAN/P2P/TURN/Relay）
1. 另部署 **coturn**，开放 3478 UDP/TCP + relay 端口段。  
2. Server 配置 `DSH_SERVER_STUN_URLS`、`DSH_SERVER_TURN_URLS`、`DSH_SERVER_TURN_SECRET`（与 coturn `static-auth-secret` 一致）。  
3. 客户端会走 `GET /api/v1/turn/credentials` 取短时凭证。  

### 4.3 App / Host 要改什么
- **配置项**：默认 `https://dsh.r2049.cn` → 可配置的自建 origin（设置页 + 编译期默认）。  
- **登录**：自建用密码登录；保留「可切换 Server」便于调试。  
- Host 插件与 Client **必须同一 Server**。

---

## 5. iOS 客户端实施方案（远程优先）

### 阶段 A — 工程与协议对齐（可无 Mac 部分完成）
- 同步 fork；盘点 `dsh_remote` API、`serverUrl`、登录与 `connectHost`。  
- 设置中增加「Remote Server URL」与密码登录。  
- 文档化与 Host 插件版本矩阵（建议 Host：`ds-harness-remote@0.6.x` + DSH 0.2.x）。

### 阶段 B — 自建 Server 验证（台式/云主机即可）
- 部署 Server + HTTPS。  
- 用现有 Android 或官方 Web/插件先打通「自建 Server ↔ Host」。  
- 再开 iOS，避免问题耦合。

### 阶段 C — iOS 工程骨架（需要 Mac）
- `flutter create --platforms=ios` 补齐 `app/ios`。  
- 权限：网络、相册/拍照、Keychain、WebRTC 相关描述。  
- 先跑通：**密码登录 → 列 Host → Relay 连接 → 发一条 prompt**（可暂关 WebRTC）。

### 阶段 D — 直连路径与体验
- 验证 `flutter_webrtc` 在 iOS 的 DataChannel。  
- 连接诊断 UI（路径 lan/p2p/turn/relay、失败回落原因）。

### 阶段 E — 分发（单独决策）
- 开发者账号、描述文件、TestFlight：需明确授权后再做。  
- 品牌与关于页：标注主仓与作者；自有名称/图标。

---

## 6. 工作量估算（1 名熟悉 Flutter 的开发者）

| 工作包 | 人日（约） | 前置条件 |
| --- | --- | --- |
| A. 协议/配置改造设计与文档 | 1–2 | 无 |
| B. 自建 Server + HTTPS 反代打通 | 1–3 | 云主机/域名；可花钱项需确认 |
| B2. coturn TURN（可选） | 1–2 | 防火墙/端口策略 |
| C. iOS 工程 + Relay-only MVP | 5–10 | **Mac + Xcode + 真机/模拟器** |
| D. WebRTC/TURN 与诊断打磨 | 3–7 | C 完成；建议真机双网环境 |
| E. TestFlight/证书流程 | 2–4 | Apple 账号与付费决策 |
| **合计 MVP（远程-only，含自建 Server，不含上架）** | **约 11–24 人日** | 有 Mac 时日历约 **2–4 周** |
| 无 Mac 时 | 仅 A+B（+B2） | **约 3–7 人日** |

风险缓冲：仓库体积大、插件版本不一致、国内网络对 WebRTC/UDP 限制、iOS 后台保活——建议预留 **+30%**。

---

## 7. 已定推进口径（2026-11-08）

1. **先支持自建 `serverUrl`**（客户端可配置，不再绑死公共服）。  
2. **iOS 暂时仅支持遥控功能**（不做本机引擎）。  
3. 建议顺序：先自建 Remote Server → 用 Android/Host 验收 → 再开 iOS MVP（可先 Relay-only）→ 稳定后再加 TURN/P2P。  
4. coturn 为可选增强，不阻塞首期遥控。

### 仍需拍板的事项
- [ ] 自建 Server 部署目标（腾讯云 / 其他）与域名  
- [ ] 第一期是否上 coturn，还是只 Relay  
- [ ] Mac 何时可构建 / 是否本机手动构建  
- [ ] 是否授权 Apple 开发者相关（涉及花钱则另问）

---

## 8. 许可证与协作提醒

- 主应用 AGPL-3.0；`packages/dsh_remote` 协议移植自 ds-harness-remote（MIT）。  
- 自建 Server 使用上游开源 `apps/server`；完整官方站点体验上游不承诺开源。  
- fork 发布请标注主仓与作者；品牌素材见 `ASSETS.md`。  
- 较大改造/二次发布前按上游 README 联系原作者。

---

## 9. 参考链接

- 引擎与远程主机说明：`docs/guide/zh/03-engine-hosts.md`  
- Dart 客户端：`packages/dsh_remote/README.md`（默认 `serverUrl: https://dsh.r2049.cn`）  
- 自建 Server：https://github.com/liguobao/ds-harness-remote/blob/main/apps/server/README.md  
- 网络与传输：上游 `docs/network.md`  
