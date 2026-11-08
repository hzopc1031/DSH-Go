# DSH-Go iOS 远程遥控实施方案

> 2026-11-08 深化版；评审输入：`_codex_review_last.txt`，静态基线 `72357f62be2d247a4372cccd148ff0be1f5d2a6d`。本次 fetch 后 HEAD 与 origin/main 均为此提交。
> fork：[hzopc1031/DSH-Go](https://github.com/hzopc1031/DSH-Go)；主仓及原作者：[ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go)、ccch1mneyyy；遥控来源：[李国宝 ds-harness-remote](https://github.com/liguobao/ds-harness-remote)（MIT）。
> 本轮仅修订方案。没有实现、部署、建仓、签名、修改全局配置、接触实际密钥、付费、提交或推送。文中的命令全部是后续操作模板，未执行。

## 1. 交付范围与证据等级

首版 **R1：Relay MVP** 是远程专用 iOS 客户端：可配置 self-hosted `serverUrl`，邮箱密码登录、发现并信任电脑 Host、经加密 Relay 使用 DSH 会话、流式聊天与审批，以及断线后安全恢复。手机不安装或运行 Linux、PRoot、Node 或 DSH，不收集本机引擎 API key，不显示本机安装、启动、重置或手机操控入口。电脑 Host 负责引擎、模型账号、工作区和执行权限。

**R2：四路径版** 在 R1 验收后独立交付 `LAN → P2P → TURN → Relay` 的能力协商、选路、回落及诊断。coturn 属于 R2，不阻塞 R1。SSH 虽已存在，但首版不列入 iOS 支持与验收承诺；后续单独核验。TestFlight/App Store、证书、品牌替换与发布是另一阶段，不包含在 R1/R2 开发工期内。iOS 本机引擎不在本方案后续阶段内。

本文区分三种结论：**源码已核验**（能力存在或存在缺口）、**拟定契约/候选组合**（未来要实现）、**待实测**（未通过运行证据）。静态方案闭环不等于实现完成。当前是 Windows 环境，PATH 未发现 Flutter/Dart，未接入 Mac；没有 iOS 工程、模拟器、真机或未经测试补丁的本轮 Server/Host 实连证据。需要 Mac 时再由 Liu 提供，本次不索取设备。

## 2. 架构与真实模块映射

```text
远程专用 RootGate（拟增平台能力分支）
  └─ server 选择 → 已有密码登录 → Host 列表/指纹确认
       └─ 现有 connection_state / DshClient / 原生 Flutter 聊天与审批
            └─ dsh_remote：设备身份、token、Host pin、Noise IK、RPC/流
                 ├─ R1：加密 WebSocket Relay
                 └─ R2：WebRTC DataChannel（LAN / P2P / coturn）→ Relay

iOS Client ── HTTPS REST + WSS Control ── HTTPS 可信反代 ── Remote Server
电脑 Host  ── HTTPS REST + WSS Control ───────────────────────┘
iOS Client ══ Noise 密文（Relay 或 WebRTC）════════ 电脑 Host 插件 → DSH
```

Remote Server 是账号、设备发现和信令控制面，也能转发 Relay 密文；coturn 是独立的 WebRTC 网络中继。Host 和 Client 主动出站，不要求给电脑做公网端口映射。Relay 可能经 Control socket 或协商后的独立 data socket；反代必须覆盖实际部署产生的地址与 Upgrade 路径。不能只配置一个路径后声称所有 Relay 拓扑可用。[上游网络说明](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/docs/network.md)

Noise 保护会话正文，TLS/WSS 保护传输与账号控制面；Server 仍能观察账号、在线状态和连接元数据。首次 Host 身份来自 Server 描述符，必须由用户在电脑核对指纹后确认；自建并不消除首次信任风险。已有 pin 变更必须拒绝连接，不自动接受新 key。

| 实际目录/文件 | 已有能力 | 拟复用与新增边界 |
| --- | --- | --- |
| `app/lib/main.dart`、`app.dart`、`ui/shell/root_gate.dart` | App 初始化、RootGate、runtime 引导与自动启动 | 增 iOS 远程启动分支；连同 launch、全局 provider 副作用核查，不能只隐藏引导页 |
| `app/lib/state/hosts_state.dart` | HostRef、active_host、remote_relay_server、账号/服务器切换竞态保护 | 复用操作 epoch；增无 Host 状态、带 origin 的远程选择和迁移；不改变 Android 默认本机契约 |
| `app/lib/ui/remote/relay_login_sheet.dart` | **已有**服务器地址、邮箱、密码表单 | 提升为首启入口、预填有效默认地址、调整“恢复默认”语义；不重写登录协议 |
| `app/lib/remote/relay/dsh_remote_backend.dart`、`relay_backend.dart` | RemoteAccount 适配、Host 信任、mux、direct 开关 | R1 显式 `direct=false`；设备名/platform 改为 iOS（现为 Android 字面值）；维持 Android 行为 |
| `packages/dsh_remote/lib/src/account/remote_account.dart` | origin 隔离身份/凭据/pin、刷新/退出、握手、能力探测 | 优先原样复用；本方案不复制一套 iOS 协议库 |
| `packages/dsh_remote/lib/src/server/server_api.dart` | origin 规范化、登录/注册设备/刷新/撤销、Host 与 TURN API | 复用校验；UI 与配置解析采用同一规范化函数 |
| `app/lib/remote/secret_store.dart` | flutter_secure_storage 包装，凭据不放 SharedPreferences | 验证 iOS Keychain、锁屏可访问性、重装和退出清理；不以 Android 注释当作 iOS 证明 |
| `app/lib/state/connection_state.dart`、`packages/dsh_client/` | 本机/SSH/Relay 连接、共享会话与流；本机连接会读 runtime | 无 Host 时不创建本机连接；沿用远程 DshClient，不新增本机 HTTP 兜底 |
| `app/lib/remote/network_watch.dart` | 网络变化与 AppLifecycleListener.onResume | 复用事件入口，补 iOS 恢复/取消/并发验收，事件到达不代表已经恢复 |
| `app/lib/remote/relay/webrtc_peer.dart`、`network_route.dart` | flutter_webrtc DataChannel、候选与网络策略 | R1 不启用直连，但插件仍参与原生构建；R2 再验证路径 |
| `app/lib/ui/chat/`、`ui/sessions/`、`ui/remote/` | 聊天、会话、远程 UI | 复用会话归属和审批模型，增未知发送结果、恢复状态及入口能力过滤 |
| `app/lib/runtime/`、`ui/onboarding/`、`ui/engine/`、`ui/phone/` | Android runtime 通道、本机安装、引擎和手机操控 | iOS 不装配本机副作用，不进入这些操作；远程 Host 支持的引擎设置可按 Host 能力独立开放 |
| `app/lib/l10n/parts/` | 中英 ARB 输入与生成链 | 未来实现同步两种语言并运行 l10n_merge；本次不改任何 ARB |
| `app/ios/` | **不存在** | 后续生成与审核工程、Pod/依赖锁、entitlements、权限和 deployment target |
| `runtime/bridge/dsh-go-bridge/`、`runtime/patches/` | Android 打包引擎的桥与版本补丁 | 不移植到手机，不默认要求外部电脑 Host 套用 Android 补丁；兼容性以真实 Host 探测为准 |

## 3. 远程专用启动、退出与恢复契约（闭环 1）

现状：RootGate.build 无条件 watch `localRuntimeProvider`，还监听安装、技能同步、guest FS 和本机诊断；初始 HostRef 和 forget 后的落点均为 `local`。缺少 `dsh/runtime` 的 iOS 首次读取失败会走未安装状态，再进入安装引导。只生成 ios/ 或捕获 MissingPluginException 不满足远程专用目标。

拟定最小设计：在根入口、任何 runtime provider 读取之前决定平台能力，例如 `supportsLocalRuntime=false`；远程分支只等待设置、服务器选择、账号恢复及远程 Host 选择加载完成。Android 继续走已有分支。不要伪造“已安装/运行”的 runtime 状态。能力判断也用于路由、设置索引、抽屉、搜索、快捷入口与深链，调用侧再次拒绝不支持的本机操作。

| 场景 | iOS 应到达状态与动作 | 必须禁止 |
| --- | --- | --- |
| 全新安装 | 远程欢迎 → 选择/输入服务器 → 邮箱密码登录 → Host 列表 → 核对指纹 → 连接 | runtime 查询、安装/解压、模型 API key 引导 |
| 还未选择服务器或用户取消登录 | 保留可编辑服务器配置的登录页 | 自动连公共服或本机 |
| 已登录但没有 Host/全部离线 | 空列表/离线页，显示电脑端授权说明，可刷新、切服务器、退出 | 自动新建本机会话或永远停在 splash |
| 已存 Host 且允许自动连接 | 加载同 origin/账号的选择后才连接；恢复会话前重新验权与 pin 校验 | 闪现“本机”、使用另一服务器同 ID Host |
| 关闭自动连接/旧配置为 local、SSH 或损坏 | 进入远程 Host 选择；保留原配置可供其他平台使用 | HostRef.decode 的 local 缺省变成实际本机连接 |
| 网络断开/Host 重启 | 保留目标 Host 归属，显示离线/重连；有界退避，手动重试 | 回落本机、重发不明结果的写请求 |
| 退出/失效凭据 | 断开会话、清远程视图，回该 origin 登录页；撤销结果另行说明 | forget 后 select(local)、展示旧账号审批 |
| App 被杀后重启 | 先恢复 origin → Keychain/账号 → Host 选择；重新握手再恢复订阅/历史 | 把磁盘缓存当在线状态或自动批准待办 |

拟在 App 层为 iOS 表示“没有选中 Host”（可空选择或显式状态，实施时择最小改动），不将 `HostRef.local` 当占位。记录选择/缓存以 `(origin, account, hostId)` 为边界，账号未确认前不展示历史。取消、切 Host、切服务器、退出均取消在途连接与重连任务；晚到响应不得覆盖新状态。

能力隔离清单：本机安装/启停/重置/卸载、PRoot 文件系统与技能写入、本机诊断发布、本机 DeepSeek 登录桥、Android 无障碍/屏幕操控/前台服务、自动启动、本机 WebView URL、Android 安装更新/图标及权限专属入口。检查 `main.dart`/`app.dart`/launch 和全局 watch 的 MethodChannel；先验平台支持再调用。隐藏 UI 之外还要验证启动到连接期间本机通道调用次数为零。远程 settings 只在 Host 返回能力后开放，不能因名称含“引擎”一概禁止，也不能把本机设置误写入 Host。

## 4. 服务器选择、默认值与迁移（闭环 2）

已核验：表单已支持自建登录；hosts_state 做持久化、origin 规范化和 A→B→A 登录竞态保护；RemoteAccount 用规范化 origin 的 SHA-256 前 24 位命名空间隔离 identity、credentials 和 pins。现有 `relayServerProvider == null`、`useDefault()` 和包级缺省都指向公共 `https://dsh.r2049.cn`。**不能把 null 改为 Liu 的域名，也不能仅改一处常量。**

拟定配置优先级与迁移：

1. 新 iOS 配置用有版本的明确选择（如 `unconfigured / selfHosted(origin) / hosted`），持久化只放 origin/选择，不放密码和 token。给 RemoteAccount 始终传解析后的显式 origin，保留包级 null 公共服约定，避免影响 Android。
2. 有效的显式保存地址优先于编译期 `DSH_REMOTE_DEFAULT_SERVER_URL`（拟增、仅非敏感 origin）；编译期未设置则保持未配置，提示输入，不静默使用公共服。Liu 域名尚未确定，`https://remote.example.com` 仅为示例，不能发布成默认值。
3. 旧 `remote_relay_server` 非空时规范化后迁移，失败则保留原值并提示重新选择，不做猜测修复。旧 null/键缺失原本都代表公共默认：升级记录为 hosted 兼容选择并提示确认；历史格式不能区分“明确用过公共服”和“从未配置”，迁移不得自动登录公共服。全新 iOS 安装采用第 2 条。迁移应幂等并有 schema 标记，不删除旧 origin 的凭据。
4. “恢复默认服务器”恢复构建中有效的 self-hosted origin；没有默认则回未配置。“切换公共服务器”若后续保留，必须是另一项明确动作，不以 null/空输入暗中触发；首版默认不主动展示公共登录。
5. 继续复用 `normalizeServerUrl`：修剪输入、补 HTTPS、去尾斜杠，拒绝 userinfo/path/query/fragment，公网须 HTTPS；库允许私网/回环 HTTP，但 iOS R1 产品契约只支持 HTTPS，开发特例需单独配置 ATS，不能全局放开。端口属于 origin；等价地址必须落同一作用域。
6. 以解析后的 origin 和登录类型决定表单/账号 backend，不再以 `selection == null` 推导认证方式。密码表单预填有效 origin。默认值变动不覆盖既有显式选择。
7. 切服务器前关闭旧 socket/流/连接、失效读列表及会话缓存，取消旧登录；保留旧 origin 安全存储以便切回，界面说明“切换不等于撤销”。登录操作完成前再次核对 origin/epoch；不同 origin 的 Host、pin、token 和审批不可串用。

迁移验收包含大小写主机名、默认/非默认端口、尾斜杠、非法路径、无配置、旧公共配置、旧自建配置、编译默认改变、A→B→A 并发，以及切回 A 后只恢复 A 的身份。当前缓存不全是 origin 命名空间，隔离是待实现工作，不能因 token 已隔离便宣布整体完成。

## 5. 邮箱密码、设备和电脑 Host 授权

### 5.1 账号从哪里来，能否注册

上游小型 self-hosted Server 是**环境变量初始化的单账号服务**。部署者在私有运行环境设置 `DSH_SERVER_ACCOUNT`（为兼容客户端用邮箱格式）与 `DSH_SERVER_PASSWORD`（至少 12 字符），并设置 `DSH_SERVER_PUBLIC_URL` 为外部 HTTPS origin。首次启动 Store 创建设备/token 状态文件；账号名和密码不是用户在手机上自行注册出来的。

此实现没有开放注册、邮箱验证、找回密码、邀请用户或多租户账号体系；邮箱是登录标识，不意味着发邮件或关联公共站点账号。手机不提供“注册”按钮。忘记密码由部署者修改服务配置并重建容器；不能承诺 App 内找回。更改账号清空设备归属与 token，更改密码清空 token，设备需重新授权。相同 origin 不支持多个互相隔离的个人账号；需要多人隔离时应另行部署独立实例/origin，不能把一套账号分享给不互信的人。[账号与 Store 源码](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server/src/store.ts)

### 5.2 手机登录与凭据生命周期

| 步骤/凭据 | 已核验的请求与行为 | 计划验收 |
| --- | --- | --- |
| 密码登录 | `POST /api/v1/auth/login`，JSON `{email,password}`；返回 account、token、expiresAt，并设置 Web cookie | 密码只在输入与 HTTPS 请求内存中使用；不写日志/配置/URL，不保存邮箱密码组合 |
| 账号 token | 该提交账号 session 为 8 小时，内存保存；Web 使用 HttpOnly/SameSite=Strict，HTTPS 时 Secure cookie | 原生 Dart 用返回的 Bearer，不依赖 WebView cookie；该 token 仅用于设备注册后丢弃，Server 重启需重新账号登录 |
| 设备注册 | `POST /api/v1/devices/register`，账号 Bearer + `{device: descriptor}`；含 deviceId、client 角色、identity 公钥、platform、版本 | 本地创建身份私钥，私钥不上传；iOS 描述符不能继续写 Android；被撤销/身份冲突后的再授权按现有库新建身份 |
| 设备 access/refresh | Server 返回 accessToken/refreshToken 与各自 expiresAt；候选源码 access 1 小时、refresh 自签发起 30 天，轮换不延长该 refresh 家族截止时间 | origin 隔离后放安全存储；以响应 expiresAt 为准，不能把时长写死为跨 Server 保证 |
| 刷新 | `POST /api/v1/auth/refresh`，`{deviceId,refreshToken}`；Dart accessToken 路径会提前刷新并合并并发刷新 | 401/过期/撤销按稳定错误退出，不陷入重试风暴；刷新写入不能被旧退出删除 |
| Host 发现/身份 | access Bearer 调 `/api/v1/devices`、`/api/v1/devices/{id}`，后者包含授权后的 identity | 不能以在线列表代替 pin/归属检查 |
| Control/连接 | `/ws/v1/connect` 设备认证、同账号连接授权 → 选路 → Noise → Harness 能力探测 | 新连接重新验证；token 不放 URL、信令或诊断 |
| 本机退出 | Dart `logout(revokeDevice:true)` 关闭连接、尽力 `DELETE /api/v1/devices/self`、清本地 token/被撤销 identity，保留 Host pins | 在线验证旧设备凭据失效；离线只承诺本地清除，不能显示“服务端已撤销” |

候选 Server 对“刷新成功但响应丢失”有持久化恢复：在后继 refresh 尚未再次轮换/撤销/过期前，重试前一 token 返回同一后继；更旧 token 被拒绝，升级前没有恢复元数据的已消费 token 也不能恢复。Dart 部分注释仍描述旧 token 重用撤销家族，不能据注释推导所有 Server 行为；本方案以所钉 Server 的实际实现和测试为准，也不借此增加自动重试业务 mutation。[Server refresh 实现](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server/src/store.ts)

Keychain 需在锁屏、重启后首次解锁、重装及清除账号后实测；读取失败应提示解锁/重新登录，不能误报已撤销。首版不为了后台保活放宽 Keychain 可访问性。卸载 App 不能视为 Server 撤销证据。网络异常时离线退出的 Server 撤销是未确认状态；现有库会删除本地凭据，不能假设还能后台补撤销。由部署者按该版本实际支持的管理能力处理，或明确以改密码使所有设备重新授权；不虚构远程管理撤销 API。`POST /api/v1/auth/logout` 只结束账号 Web session，不等同撤销设备，也不等于退出电脑 Host。

### 5.3 与电脑 Host 的绑定有何不同

电脑安装 DSH 与 `ds-harness-remote` 插件，在插件设置指定同一 HTTPS origin 并以同一部署账号授权 Host。Host 有自己独立的 deviceId、identity 私钥和设备 token，使用 host 角色出站上线；手机登录不会自动安装插件、启动电脑 DSH 或把手机凭据复制给电脑。首次连接还需在手机确认电脑指纹，权限审批最终由电脑 DSH 当前待办与策略判定。

上游完整协议还有一次性 Host 匹配码、owned-role 授权与 OAuth，插件也含这些入口；但本次核验的小 Server 路由只有账号注册和 `register-owned-role`，不据协议宣称它支持全部匹配码/OAuth流程。R1 采用电脑端邮箱密码授权路径；若候选插件入口实际不能完成该路径，则阻塞兼容性门禁，先核验对应插件实现，不能借公共站点流程绕过。

退出手机只撤销该 client，不撤销 Host 或其他手机；退出 Host 由电脑端独立完成。切服务器要在手机和电脑分别配置并重新授权，不能搬运旧 token、pin 或登录态。Host 重装导致 key 变更必须在电脑核验后由用户显式忘记旧 pin 再信任，不能因“账号相同”自动放行。[插件凭据作用域](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/packages/plugin/src/server-credentials.ts)

### 5.4 coturn 凭据单独管理

coturn 凭据与登录邮箱密码、设备 token、Noise identity 都不同。R1 不部署 coturn，也不填写 TURN secret。R2 推荐 coturn `use-auth-secret`，`static-auth-secret` 与 Server 的 `DSH_SERVER_TURN_SECRET` 使用同一部署侧私密值，只存在于这两处私有配置；App 不保存或内置共享 secret。

Server 配置 `DSH_SERVER_STUN_URLS`、`DSH_SERVER_TURN_URLS`，已建立连接授权的双方调用 `GET /api/v1/turn/credentials?connection_id=...`，获得有时限的 TURN username/credential。候选默认 TTL 300 秒，可配 60–3600 秒，生成方式为 expiry/deviceId 用户名与 HMAC-SHA1；需验过期拒绝和重新连接取新凭据。上游另支持 `DSH_SERVER_TURN_USERNAME` + `DSH_SERVER_TURN_PASSWORD` 静态模式，与 secret 模式互斥，所有连接会共享静态对，首选不用。TURN 端口/relay 范围、带宽和时钟同步要独立验收；HTTPS 反代不会代转 TURN UDP。[ICE 实现](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server/src/ice.ts)

## 6. 可复现版本与能力门禁（闭环 3）

禁止用 `latest`、`0.6.x`、`0.2.x` 作为发布验收组合。以下是**精确候选与证据账本，不是已通过组合**：

| 组成 | 精确候选/事实 | 证据与未验证项 |
| --- | --- | --- |
| App/Dart 客户端 | 当前基线 `72357f62be2d247a4372cccd148ff0be1f5d2a6d`，未来实现另记实际 SHA | 本文修改不代表 iOS 实现 |
| Server 源码 | `8f905b53d195a2c1ae29913d90eaacd40addeda9`（2026-11-08 查询上游 main） | 已核对 server.ts/store.ts/gateway 目录与部署文件；未经本轮构建实连 |
| Server 镜像 | 优先由上述提交按上游 Dockerfile 构建；公共 GHCR digest **待查验后填写** | `server:latest` 不得用于通过门禁；源码提交不等于公共镜像具有同一能力，需记录 RepoDigest/OCI revision、架构与 image ID |
| Host 插件 | `ds-harness-remote@0.6.3`，该提交 package.json 的精确版本 | npm/tarball 的来源、完整性和安装后实际版本待核验，不用源码版本号替代包证据 |
| 电脑 DSH | `@deepseek-ai/dsh@0.2.2-rc.1` 候选 | 与本仓 runtime/build-runtime.sh 默认一致仅作选择依据；不是电脑兼容性证明，不自动施加 runtime/patches；记录电脑 OS、Node、DSH 实际版本与任何补丁 hash |
| 旧实连记录 | Host `0.6.0` / Harness `0.2.1-rc.5` | docs/testing/remote-auto-network.md 明示信令/Relay fixture 测试补丁，不是公开镜像或 iOS 的能力证明 |

实施 A/B 阶段将候选变成冻结清单：Server commit + digest/image ID、插件包版本/完整性、DSH exact version、Host OS/Node、App SHA 与 Flutter/Pod 锁、连接能力返回。缺一项标“待验证”，不得包装成稳定兼容组合；若候选不满足，明确换组合后重新验证，不现场无记录补丁。

| 能力/协议 | R1 门禁 | R2 增量门禁 |
| --- | --- | --- |
| 账号/设备 REST、Control v1、同账号与角色校验 | 必须通过登录、注册、刷新、Host 查询/密钥、连接、撤销正反用例 | 沿用 |
| Noise IK + pin + Relay 数据通路 | 必须不靠测试补丁通过；记录实际 Control relay 或 `transport.relay.attach`，不能假定双方都支持 attach | 同样适用于四条路径；attach 扩展需双方及 Server 实际协商 |
| `harness.transport.describe` → `harness.remote.v3` | 安全通道后首 RPC；缺失报 `HARNESS_VERSION_INCOMPATIBLE`，同时宣告 v1/v3 或非法能力列表报 `INVALID_MESSAGE` | 不因 WebRTC 成功跳过 |
| Harness V3 聊天/会话/原生流/权限 | 必须完成实际流与审批，不能仅看登录在线或版本字符串 | 各数据路径重复关键业务验收 |
| `remote.history.compact.v1` | 可选；按实际协商，缺失降级既有历史方式；模式冲突按现有 `HISTORY_MODE_CHANGED` 处理 | 沿用 |
| WebRTC offer/answer/ICE、transport.selected、短期 TURN | R1 不承诺、不启用 | 记录 Host/Client/Server 能力及真实候选对；禁止只按 UI 标签认定路径 |

公开上游当前源码比旧 fixture 更新，文档声称支持四路径，只能作为候选依据；仍须用未经测试补丁的构建完成互操作。已核对候选 gateway.ts 的 SUPPORTED_TRANSPORTS 仅列 transport.lan/p2p/turn/relay，没有协商 transport.relay.attach，因此本候选优先验收 Control WebSocket 内置 Relay，不把独立 Relay 节点/attach fixture 当作必要条件或已有能力。[Gateway 实现](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server/src/gateway.ts)。协议文档也提醒“存在 schema 不等于符合实现”。

## 7. iOS 原生依赖与构建门槛（闭环 4）

R1 计划先**保留并构建 flutter_webrtc**，运行时禁用直连。现有 app/pubspec.yaml 直接依赖、hosts_state 始终装配 flutterPeerConnector，故 `direct=false` 不会从 Pod 链移除 WebRTC。只有原生预检失败且无法小修时，才另评是否拆依赖/条件装配；此时应重新估时，不能一边保留依赖一边宣称“纯 Dart 无原生问题”。

拟采用以下首轮预检组合，全部 **待 Mac 验证**：

| 项 | 组合与验收要求 |
| --- | --- |
| Flutter / Dart | `3.47.7`（仓库 CI）/ 随该 SDK 的 Dart，须满足 pubspec `^3.13.5`；记录 flutter --version 的实际 Dart/engine SHA，不猜配版本 |
| Xcode / macOS | 候选 Xcode `26.1.1`、iOS SDK `26.1`，Apple 表列 macOS `15.6` 起；未来设备 OS 超出其支持时选兼容 Xcode 并重跑门禁。实际 Xcode build number、macOS patch 待填 |
| deployment target | 候选 iOS `15.0`；Flutter 3.47 支持下限为 15，不按 WebRTC 单插件的 13.0 下限宣称整 App 支持 iOS 13 |
| WebRTC | pubspec.lock `flutter_webrtc 1.6.3`；对应 podspec 钉 `WebRTC-SDK 150.7871.04`，iOS target 13.0；验 arm64 simulator 与 iphoneos arm64 slice、链接与启动 |
| 存储及其他插件 | flutter_secure_storage `11.2.0`；逐个审 pubspec.lock 的 iOS 原生插件、Pod/SPM 解析与许可证，尤其 connectivity、媒体、通知、webview、文件路径；Android-only 实现不得在首启调用 |
| 依赖锁 | 首轮按生成工程选一套依赖管理，优先验证 CocoaPods；记录 pod --version、Podfile.lock 和实际插件约束，不能同时无依据引入 SPM；若有更高下限先回写方案 |

构建门槛按序推进：① 在现有 Flutter 源中生成 ios/，逐项审 diff，确认无 Android 与生成物无关变动；② 原生依赖解析成功，模拟器 debug 无签名构建并启动；③ iphoneos release `--no-codesign` 编译链接成功，**此产物不能安装，也不代表真机通过**；④ Liu 后续提供设备与独立签名授权后，真机安装、Keychain 登录恢复、WSS/Noise/流/审批、锁屏切网全套通过。Mac 未提供前，②–④均未运行；模拟器不能替代④。

仅 DataChannel 不需要麦克风/摄像头授权，不为“WebRTC 相关”泛增权限。R1 用受信 HTTPS，无全局 ATS 豁免；相册/拍照/通知等若不在首版范围则无入口和授权弹窗，若保留需独立权限验收。R2 LAN 访问再核查本地网络用途说明/发现方式，只有实际使用 Bonjour 才声明相应服务。Keychain entitlements 与可访问性按实际插件和 App ID 配置验证，不提前生成或索取证书。

依据：[Flutter iOS 环境](https://docs.flutter.dev/platform-integration/ios/setup)、[Flutter 支持平台](https://docs.flutter.dev/reference/supported-platforms)、[Apple Xcode 支持表](https://developer.apple.com/support/xcode/)、[WebRTC 1.6.3 podspec](https://github.com/flutter-webrtc/flutter-webrtc/blob/v1.6.3/ios/flutter_webrtc.podspec)、[安全存储 11.2.0](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0)。这些是工具/插件要求，不是本项目构建成功证据。

## 8. 自建 Server 运维边界（闭环 6）

R1 最小拓扑是一台已有授权环境的单进程 Server + HTTPS 反代 + 持久数据卷，手机和电脑填同一 HTTPS origin。没有 STUN/TURN 不保证库绝不尝试 host candidate，**Relay-only 必须在客户端显式禁用直连并以所选路径证据验收**。R1 不开放 TURN 端口，不引入外置 Relay 集群。

- Compose 的 `server-data:/data` 与 Dockerfile 的 `DSH_SERVER_DATA_FILE=/data/state.json` 一起构成设备/token 持久化。源码裸跑默认 `data/state.json` 相对工作目录。记录真实卷名、挂载与属主可写权限，不复制容器短暂可写层当备份。禁止把 `docker compose down -v` 写入常规更新命令。
- 更新/重建保持同一卷、同一账号密码和数据文件路径；Web 账号 session 在内存，重启后需要重登，与设备 refresh 可恢复是两回事。验证重建后原手机与 Host 凭据可刷新/重连、pin 不变、在线状态重新上线而非从磁盘伪造。
- 备份包含状态文件与恢复所需的私有部署配置，备份有访问控制且不进入仓库/诊断附件；本次不读取或创建实际 secret。先停单进程获得一致副本，在隔离环境恢复原版本和卷验证。不可多副本共同写同一 JSON 文件；跨账号切换或密码变化导致失效须视为预期再授权。备份回滚可能回退撤销/轮换状态，恢复后按风险强制重新授权，不能承诺旧 token 全部安全保留。
- 反代需 HTTPS、正确 PUBLIC_URL origin、原样保留 Origin、支持 WebSocket Upgrade，空闲超时高于 75 秒并覆盖部署调大的心跳阈值（例 120 秒）。只把 Node listener 绑定 loopback/受控网络，不能公网绕过反代。校验实际 Control 与 Relay endpoint 均可访问。
- `DSH_SERVER_TRUSTED_PROXY_IPS` 仅填 Server 看到的可信反代 peer IP（裸 IPv4/IPv6，非 CIDR/域名）。代理必须**覆盖** X-Forwarded-For 为一个真实客户端 IP，不追加、不透传客户端值。多级代理先确定最后一跳规则，不能直接套用 `$proxy_add_x_forwarded_for`。
- 默认忽略 XFF，所有请求按 socket peer 限流；反代下可能所有人共用 API 240/min、登录 20/min。验伪造头不能绕过、可信 peer 缺失/重复/列表头返回 `400 INVALID_MESSAGE`、独立 IP 分开计数，同公网 NAT 仍共享额度；控制连接升级也需验限流。环境变量变更须 recreate，单纯 restart 不会加载新配置。
- 单账号表示个人/互信设备边界，无多租户、成员管理、高可用或公网 SLA 承诺。部署者能管理账号和元数据，不因此获得会话明文；诊断不得记录 token、identity 私钥、prompt 或审批内容。带宽与费用需要另行决策，本轮无采购部署。

R2 才加入独立 coturn，先明确 3478 UDP/TCP 或实际 TLS 端口、relay 端口范围、NAT/external-ip 和防火墙策略，再验证蜂窝/严格 NAT 下候选对与失效凭据。以上均不能从 Android 模拟器 fixture 推导。

## 9. 完整验收清单（闭环 5）

R1 的安全恢复策略是重新认证/校验 Host pin、重建 transport + Noise、重开订阅并读取 history baseline；不承诺 iOS 后台持续运行或锁屏实时收流。电脑继续执行与手机后台保活是两件事。首版无后台音频/VoIP 变通；恢复后显示期间发生的变化。连接建立时降级与已连接后迁移分开验收。

| 编号/场景 | 操作与通过标准 | 证据/环境 |
| --- | --- | --- |
| T1 首启/无 Host/退出/冷恢复 | 覆盖第 3 节所有状态，含 Keychain 残留、禁止自动连接和旧 local 配置；零本机通道调用、无无限 splash | widget/provider 覆盖 + 模拟器 + 真机 |
| T2 地址/登录/切服务器 | 合法/非法 origin、错误密码、429、TLS 错误、A→B→A，历史与凭据/pin/审批不串用，晚到登录不能改变新 origin | 单测与自建隔离账号实连 |
| T3 流式聊天 | 新建/切换会话，多段增量、工具输出、完成/取消；手机与电脑历史一致，无重复气泡/截断，长回复跨帧 | 真机 R1 Relay、记录事件顺序与最终状态，不记录正文 |
| T4 审批 | allow_once/deny 由当前 Host pending request 确认；重复点击/过期/已处理/断连均有稳定结果；无本地伪造“批准成功” | 电脑待办与副作用次数核对；超时不自动放行 |
| T5 锁屏/后台/杀进程 | 流式回复或待审批时后台/锁屏 1 分钟及 5 分钟、再杀 App 重开；恢复历史与当前 pending，不重复 prompt/审批，无后台持续收流承诺 | 真实 iPhone（模拟器不关闭此项） |
| T6 切网/离线 | Wi-Fi↔蜂窝、飞行模式后恢复，撤销/切 Host/退出时取消在途重连；重连有退避，读历史重建不串流 | 真机双网；新 connection/Noise 证据 |
| T7 Host/Server 重启 | Host 停止/重启，Server 重建保卷；不回落本机，重新上线并验权，历史恢复；无旧连接写请求回放 | 实际 Host + 同版本无测试补丁 Server |
| T8 凭据失效 | access 到期刷新、refresh 到期/撤销、改密码、刷新成功响应丢失、Keychain 读失败；登录状态与稳定错误吻合，无无限重试 | 可控时钟/故障注入与真实刷新路径 |
| T9 Host 密钥变化 | 保留 hostId 改 key、列表/详情竞态、跨服务器同 hostId；已 pin 的身份不匹配停止自动恢复，明确显示需核对 | `PEER_IDENTITY_MISMATCH`；绝不自动改 pin |
| T10 响应丢失防重复 | 分别在 prompt/审批已送达 Host、响应未到手机时断网；重连只读历史/待办确认，Host 执行次数仍为 1 | 故障注入 + Host 副作用计数，不以 UI 显示一次代替 |
| T11 安全/运维 | 跨角色/跨账号拒绝、伪造 XFF、限流、持久卷重建/隔离恢复、无敏感日志、旧设备撤销后不能续接 | 第 8 节逐项记录 |
| T12 R2 四路径 | LAN、跨网 P2P、强制直连失败走 TURN、禁 UDP/直连后 Relay，各自带流与审批；建立后切网按重建策略恢复 | 候选对/selected mode/Server 计数交叉证明，含 IPv4/IPv6，不能只阻断 UDP 宣称直连全失败 |

未知结果契约：断线/超时之后，prompt、审批、删除及其他 mutation 均不得自动重放。UI 标“结果待确认”，禁重复提交；优先读取 Host 历史/运行状态/当前权限请求。只有所钉 Host 明确提供并验证了相应请求 ID 幂等语义，才可设计同 ID 重试；未确认时不编造幂等保证。无法判断原 prompt 是否执行时，保留草稿与人工确认路径，不自动发送新 ID。审批以 Host 当前 pending ID 为准，已处理或 `PERMISSION_NOT_PENDING` 不能自动改为另一个审批。错误显示稳定码与可操作提示，日志只含白名单诊断字段。

每次验收填写 App/Server/插件/DSH 精确版本、无补丁声明或补丁 hash、iPhone 型号与 iOS、网络、实际路径、步骤、通过/失败/跳过和脱敏证据。桌面纯 Dart 测试不代表 iOS native 成功，模拟器也不替代蜂窝/锁屏。R1 T1–T11 全过才交付；T12 是 R2 门槛。

## 10. 阶段、人日、依赖与退出门槛（闭环 7）

估算假设：1 名熟悉 Flutter/Riverpod 与 Remote 协议的开发者，复用现有 UI/客户端；已有可授权的 Server/域名环境与可用电脑 Host；Mac 和 iPhone 在对应阶段可用；不新增账号体系、SSH、附件/语音/手机操控、后台常驻、品牌重做或上架。人日是有效工作量，不包含等待硬件、账号、审核、DNS/网络或付费采购的时间。候选依赖若不兼容需重估。

| 阶段 | 工作项 | 人日 | 依赖与退出门槛 |
| --- | --- | --- | --- |
| A 静态与协议预检 | 固定版本/能力清单，配置迁移及首启状态设计，确认电脑密码授权路径与无测试补丁可用性 | 2–3 | 可先无 Mac；以可复现候选与明确失败项退出，不以登录成功代替 v3 |
| B 自建隔离验证 | 经另行授权部署 HTTPS/持久卷/可信反代，Android或现有兼容客户端↔Host 验登录、V3、Relay、重建/撤销 | 2–4 | 依赖 A 与部署环境；T2/T7/T8/T11 的服务端部分通过，否则不进入完整 iOS 开发 |
| C 原生预检 | 生成 ios/，全依赖构建、平台调用清单、Keychain 预检，记录 Flutter/Xcode/Pod 锁 | 2–4 | Mac 后执行；模拟器启动和 iphoneos 无签名链接均过，失败先停开发扩面 |
| D iOS 远程壳/迁移 | RootGate/无 Host/退出/恢复、本机入口隔离、默认服务器解析与已有表单复用，iOS 设备标识与 direct=false | 4–6 | A+C；T1/T2，Android 本机与公共/自建远程行为回归通过 |
| E 聊天审批与恢复 | 完整流/审批、未知结果处理、锁屏/切网/Host 重启、凭据与 pin 错误、取消竞态 | 4–7 | B+D；T3–T10 真机通过，不以一条 prompt 冒烟退出 |
| F R1 收口 | 全表复测、无补丁组合冻结、脱敏诊断与已知限制、双语界面/未来指南同步 | 2–3 | A–E；T1–T11 全过，原生与服务版本证据齐全 |
| **R1 Relay MVP 合计** | **A+B+C+D+E+F** | **16–27** | **不包含 coturn、直连与分发；加 30% 风险预留约 21–36 人日** |
| G R2 直连与 TURN | coturn/凭据/端口、WebRTC DataChannel 与四路径诊断，候选对、IPv6、严格 NAT、R1 回归 | **另加 6–11** | R1 通过 + 网络/端口授权；T12 与 R1 核心回归全过 |
| **R2 累计** | **R1+G** | **22–38** | **同口径加 30% 约 29–50 人日；不与 R1 混称 MVP** |
| H 分发 | App ID/签名与真机分发渠道、品牌许可/署名、TestFlight 等 | 另估 2–4 起 | 单独授权与 Apple 条件、发布材料齐全；不含审核等待，可能重选 SDK |

B 与 C 可在 A 之后并行准备，单人总人日不会因此减少；日历工期以可用资源排期，不再承诺 2–4 周。无 Mac 可完成 A，并在另有部署授权后推进 B，约 4–7 人日；本轮只有方案，不执行 A/B 的部署与代码工作。真机验收需要可运行的签名安装，当前禁止签名，因此未来授权未落实前 R1 交付门禁不能关闭。

## 11. 后续可复制命令模板（本轮未执行）

所有块都要求未来明确授权、隔离工作目录和相应工具已由用户准备好；不要在本轮执行。占位值不是凭据；不把密码/token 写进命令或仓库。不提供安装 Xcode、sudo 改全局、签名、花钱或发布命令。

### 11.1 Mac 上的工程与无签名构建

在未来隔离工作分支、`app/` 目录且尚无 ios/ 时运行；`flutter create` 可能修改 pubspec/metadata，逐项审核，仅保留与 iOS 必需的变动，不能覆盖用户改动。生成后先按第 7 节审 deployment target、插件与 project 配置；拟增 define 只有配置解析实现后才生效。

```bash
flutter --version
xcodebuild -version
xcodebuild -showsdks
pod --version
flutter doctor -v
flutter create --platforms=ios --project-name dsh_app .
flutter pub get
flutter analyze
flutter test
flutter build ios --simulator --debug \
  --dart-define=DSH_REMOTE_DEFAULT_SERVER_URL=https://remote.example.com
flutter build ios --release --no-codesign \
  --dart-define=DSH_REMOTE_DEFAULT_SERVER_URL=https://remote.example.com
flutter devices
# 仅在已启动的模拟器中运行，SIMULATOR_ID 是模拟器 ID，不是物理设备。
flutter run -d "$SIMULATOR_ID" \
  --dart-define=DSH_REMOTE_DEFAULT_SERVER_URL=https://remote.example.com
```

如选择 CocoaPods，在生成并审核的 ios/ 工程按项目要求解析 Pod，保存实际锁与版本；不要擅自全局升级 pod 或执行不必要的 pod update。真机安装、签名、Team、证书与 TestFlight 命令本轮不提供；无签名构建不能完成 T5/T6。

### 11.2 从钉死源码构建自建 Server

在**已有、隔离且授权使用的上游源码工作副本**运行（不在本仓库建服务、不建新仓库）；先确认该副本无用户未保存改动。使用固定提交，避免 floating main。命令中的 private .env 由未来部署者自行配置，既不打印也不纳入版本控制。

```bash
git status --short
git switch --detach 8f905b53d195a2c1ae29913d90eaacd40addeda9
cd apps/server
# 仅首次、且确认不存在 .env 时复制示例；随后在私有编辑器配置账号/密码/public URL。
test -e .env || cp .env.example .env
docker compose build server
# 执行前确认卷名/挂载、反代与绑定地址；不要输出 compose config（可能展开密码）。
docker compose up -d --no-build server
docker compose ps
# 记录本地构建的不可变 image ID；不要整份 inspect 环境变量。
docker image inspect "$(docker compose images -q server)" --format '{{.Id}}'
# 配置变更或同版本重建：保持同一项目名与 server-data 卷。
docker compose up -d --no-build --force-recreate server
# 停止但保留卷：
docker compose down
```

上游 compose 默认绑定 `127.0.0.1:8080`，适用于同机反代；若反代在容器内，要按隔离网络调整可达地址并记录 Server 看到的 peer IP，不能直接改为任意公网暴露。源码构建记 commit+image ID；若用公共镜像，先由发布记录核验同一源码 revision 并把 compose 的 image 固定到真实 `ghcr.io/liguobao/ds-harness-remote/server@sha256:...`，实际 digest 未核验前该路径不可复制执行，也不得拿上述源码测试成绩代替镜像测试。

Nginx 已有 TLS server 块内的配置**示意**如下；证书、域名、listener 与可信 peer 按未来环境确定，不能原样替换生产文件。覆盖 `/` 为了包含实际 REST、Control 及该 origin Relay 路由；外部 Relay endpoint 另行配置与验证。

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header Origin $http_origin;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_read_timeout 120s;
    proxy_send_timeout 120s;
}
```

部署者配置 DSH_SERVER_TRUSTED_PROXY_IPS 后再验伪造头/真实 IP/限流。配置文件、状态数据、反代日志不外发；诊断人工检查，自动打码不能当保证。备份/恢复需在知道真实卷名与路径后写具体 runbook，本方案不提供会删除卷的命令。

### 11.3 电脑 Host 与后续仓库验证

电脑先在未来授权的测试账号/工作区固定安装，不影响用户正在使用的 Host。npm --prefix 只隔离依赖目录，不隔离 DSH 用户数据；运行还须使用独立 OS 测试账号，或先核实该精确引擎支持的数据目录隔离方式，不能直接读取现有账号配置。插件从 DSH 实际支持的插件管理入口安装**精确 `ds-harness-remote@0.6.3`**并核验包完整性，在设置中填写同一 serverUrl、邮箱与密码完成电脑授权；不猜测一个尚未核验的插件安装 CLI。检查 Host 在线并核对手机首次连接的指纹。

```bash
# 仅未来隔离电脑测试环境；不在本轮或用户生产全局 Node 环境执行。
npm install --prefix ./ios-remote-host-lab --save-exact @deepseek-ai/dsh@0.2.2-rc.1
./ios-remote-host-lab/node_modules/.bin/dsh --version
./ios-remote-host-lab/node_modules/.bin/dsh web --host 127.0.0.1 --port 3080 --no-open
```

启动引擎可能打印本地访问 token；后续操作者不得把完整输出贴入报告，配置模型账号与执行 prompt 还可能产生模型费用，需要另行授权。该命令仅演示固定引擎入口，不证明插件已装好或可兼容。

未来实现按实际改动执行以下仓库契约（根目录，非本轮检查）：

```bash
(cd app && flutter pub get && flutter analyze && flutter test)
(cd packages/dsh_remote && dart pub get && dart analyze && dart test)
(cd packages/dsh_client && dart pub get && dart analyze && dart test)
python3 app/tool/l10n_merge.py --check
python3 app/tool/guide_sync.py --check
```

改文案应先同步中英 ARB 并运行生成器；改指南同步 docs/guide 中英并运行 guide_sync。未经涉及不要求修改 bridge/runtime，若确需改动再执行对应 Node 测试及两端契约检查。本轮不为文档修订运行行为测试。

## 12. 风险、待决策与未验证台账

| 项 | 当前状态 | 处理/阻塞点 |
| --- | --- | --- |
| 远程首启与无 Host 状态 | 设计已补，代码未实现 | 阻塞 R1；D 阶段验证零 runtime 调用与 Android 回归 |
| 默认地址与迁移 | 契约已拟定，无实际 Liu 域名 | Liu 决定部署 origin、是否保留明确的公共服入口；未确定时保持未配置 |
| 单账号产品边界 | 上游事实已核验 | Liu 确认仅个人/互信设备使用；多人独立账号超范围，另估 |
| 可复现 Server/Host 组合 | commit/候选版本精确，镜像 digest、包完整性、实连待验证 | B 门禁；旧 fixture 不能关闭，若失败先换候选并记录 |
| iOS 原生链 | 无 ios/、无 Mac 证据 | C 门禁；Liu 后续提供 Mac/真机，当前不索取、不假定可用 |
| 锁屏/切网/Keychain | 仅已有监听入口 | E 真机门禁，不承诺后台常驻或无缝迁移 |
| 防重复写请求 | 明确禁止未知结果重放 | 实现需检查 mux/连接恢复是否隐式重试；T10 未过不能发布聊天审批 |
| 持久卷/可信代理/恢复 | 已写运维契约，未部署测试 | B 门禁；私有配置与备份位置由后续环境确定 |
| 四路径/coturn | 独立 R2 | Liu 决定是否启动 R2、端口和带宽预算；不阻塞 R1 |
| 签名与分发 | 本轮禁止 | 后续需独立决定开发安装方式和授权；不购买账号/不建证书；TestFlight 另议 |

本轮文档更新没有技术阻塞；缺 Mac、部署授权/目标、签名安装条件和未实测版本组合是**后续实现/交付门禁**，不能写成已完成。默认建议按 R1 → R2 顺序，待 Liu 决定服务器/域名与账号边界、是否保留公共入口，之后再安排设备与分发，不因这份方案自动获得部署或付费授权。

## 13. 许可证、品牌与上游协作

保留主应用 [AGPL-3.0](../LICENSE)，sdk/examples 的 MIT，以及 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) 和各上游版权/许可/修改声明；遥控 MIT 来源不能替代整体 App 的 AGPL 义务。发布修改版须按适用许可证提供对应源码等必要材料，并保留引用来源。这里仅记录仓库契约，不对分发作法律结论。

[ASSETS.md](../ASSETS.md) 将 DSH Go 名称、品牌标识、Deepy、鲸娘与相关展示素材排除在 AGPL 授权之外。内部构建测试许可不等于修改版再发布许可；发布需换自有名称/素材或取得对应授权，不能冒充 DeepSeek、DSH Go 或原作者官方产品。App 图标、启动图、关于页、许可页与发布页均需复查，不能仅修改仓库名称。

按 [README 授权范围与再发布](../README.md#授权范围与再发布)，fork/发布在仓库说明、App 关于页与发布页面标注主仓及原作者 ccch1mneyyy，保留李国宝 Remote 等第三方署名。改造/衍生发布前联系作者是上游协作请求，并非向 AGPL 代码追加许可限制；品牌条款独立遵守。联系作者也需 Liu 后续授权，本轮未发送消息、开 issue/PR 或建仓。

## 14. 核验来源、评审闭环与本轮检查

本地已读：评审全文、原方案、CONTRIBUTING.md、docs/architecture.md、README.md 发布约定、ASSETS.md、相关依赖/CI 与第 2 节映射源码。静态定位均相对 `72357f62`；上游查询日期 2026-11-08，Remote main 固定到 `8f905b53d195a2c1ae29913d90eaacd40addeda9`。

| 评审必闭环项 | 本文落点 | 实现验收去向 |
| --- | --- | --- |
| 1 RootGate/runtime 与无 Host | 第 2–3 节 | D/E、T1/T5/T7 |
| 2 已有登录/配置/凭据复用与 null 迁移 | 第 2、4–5 节 | D、T2/T8/T9 |
| 3 精确版本、v3 与旧补丁证据边界 | 第 6 节 | A/B、冻结版本账本 |
| 4 Relay-only 原生依赖与 Mac 门槛 | 第 7、11.1 节 | C、模拟器与真机构建分开 |
| 5 流/审批/恢复/防重复 | 第 9 节 | E/F、T3–T10 |
| 6 持久卷/重建/可信代理/单账号 | 第 5、8、11.2 节 | B、T7/T8/T11 |
| 7 Relay 与四路径范围/估时/依赖 | 第 1、10、12 节 | R1 与 R2 各自退出门槛 |

上游固定来源（正文各处链接直接支撑相应结论）：

- [Server 部署说明](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server/README.md)、[compose.yaml](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server/compose.yaml)、[Dockerfile](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server/Dockerfile)：持久卷、运行用户、环境与代理边界。
- [server.ts](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server/src/server.ts)、[store.ts](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server/src/store.ts)：登录请求、8h/1h/30d、注册/刷新/撤销、账号/密码变更行为，无开放注册路由。
- [协议](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/docs/protocol.md)、[网络](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/docs/network.md)、[插件 package.json](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/packages/plugin/package.json)、[插件设置](https://github.com/liguobao/ds-harness-remote/blob/8f905b53d195a2c1ae29913d90eaacd40addeda9/packages/plugin/src/client/settings.ts)：能力与版本、现有登录入口；规范不等于运行证明。
- [本仓旧网络验证](testing/remote-auto-network.md)：明确带测试补丁与设备/网络边界；第 7 节列出 Flutter、Apple、插件原始文档，均不能替代本项目 Mac 实测。

本轮实际检查是 git status/branch/upstream、fetch origin main 与 SHA 对照、源码/文档静态交叉核验及修订后的差异/路径/空白检查。没有运行 Flutter/Dart 测试、iOS 构建、Server 部署/恢复、真实账号登录、网络故障注入或任何真机验收；原因是仅文档授权且缺相应设备/工具/环境。所有候选与验收结果保持“未验证”，不计入通过项。

## 15. ?????? A ?????2026-11-08?

???????? R1 ???????? Relay????????????????????????????????? origin ??????????????????????????????????????????Host ?????????????????R2 ???????

????????????????V3/Relay ????????????????? Python ?????????????????????????? [A ??????](testing/ios-remote-preflight.md)????????? [JSON](testing/ios-remote-preflight.json)?

Flutter/Dart ?? PATH ????? SDK/??/????????????? SDK ?????????????????????????? Dart ?????????????????/???origin ????????????? Python ??????????? RemoteAccount ? origin ???????????Android ? null ????????????

A ??????????????????????????????????? Server/Host ?????? B??????/??????????? Host??? secret???????????C ?? Mac????? iphoneos ????????C ??????????? UI?????? iOS ??????????? ios/?
