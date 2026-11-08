# iOS R1：A 预检执行记录

2026-11-08；工作基线 `72357f62be2d247a4372cccd148ff0be1f5d2a6d`。本记录是公开发布产物与源码预检，未证明实际远程兼容。主应用 AGPL、第三方 MIT、ASSETS 品牌边界保持不变，未移植第三方代码或素材。上轮方案修改及所有未跟踪回执保留。

用户决定：R1 远程专用、仅加密 Relay、个人使用、无多用户系统。拟腾讯云，域名/默认地址未定；未配置不得自动访问公共服。本批不部署、不访问现用 Host、不读写真实 secret、不签名或发布，不扩展完整远程 UI、恢复或 iOS 原生集成。

## 公开发布包实测

执行 `python tooling/ios_remote_preflight.py -o .harness-tmp-ios-preflight/receipt.json`，通过 HTTPS 从 npm registry 下载精确包和从 GitHub 下载固定提交归档；没有 npm install、生命周期脚本或 Host 启动。输出同时进入 stdout 和 `-o` JSON。回执的 markers 是静态位置索引，不是能力运行结果。记录日期、完整 SRI、URL、gitHead、SHA-256 和位置见 [机器回执](ios-remote-preflight.json)。

| 输入 | 本次实测结果 | 边界 |
| --- | --- | --- |
| `ds-harness-remote@0.6.3` | npm SRI SHA-512 与下载字节一致；包内名称/版本一致；MIT；gitHead `bd0eadeb98b47b74b7b56924091a5a7429762d41` | 与候选 Server commit 不同；只验证 registry 声明与字节一致，未验证 npm 签名/发布者 provenance |
| `@deepseek-ai/dsh@0.2.2-rc.1` | npm SRI SHA-512 与字节一致；包内名称/版本一致；MIT；Node `>=24.9.0` | CLI 包未带 gitHead；依赖未安装，完整引擎依赖树未冻结，不能视为已安装 Host |
| Server `8f905b53d195a2c1ae29913d90eaacd40addeda9` | 固定源码归档 SHA-256 `0832aad10e439ad6c8a77a24860b614ac583fb5ba67062e2857ef753b5c431ce`；server package version `0.5.21` | 归档 hash 是本次下载固定值；不是 Git commit 签名验证或镜像 digest |
| GHCR | 按钉住 CI 的 SHA 标签规则只读查询 `server:sha-8f905b5`，HTTP 404 | 未获得与候选提交对应的公共镜像，未拉取镜像；不推断整个 GHCR 仓库不可用，不改查 latest 充当通过 |

包 SHA-256：插件 `eca4ded731d15488c9992cdfb1e0f3ffa0ca392cb2f08da894187481bd6db3ad`；DSH CLI `ad21968aed0337a326b853507a23b30eacbbec4d67ab07f3b6fde69b75b19cd6`。

来源：[插件 npm 元数据](https://registry.npmjs.org/ds-harness-remote/0.6.3)、[DSH npm 元数据](https://registry.npmjs.org/@deepseek-ai/dsh/0.2.2-rc.1)、[固定 Server 源码](https://github.com/liguobao/ds-harness-remote/tree/8f905b53d195a2c1ae29913d90eaacd40addeda9/apps/server)。Web 读取失败后使用 Python HTTPS 下载核验，未用搜索摘要代替包内容。

## 安装入口与能力结论

发布插件 `package/README.md:61` 给出 `dsh plugin --profile web add -w ds-harness-remote@0.6.3`；精确 DSH CLI 的 `lib/plugin-DscIHF4k.js` 确有 profile 参数和插件管理转发。它会修改选定 profile，安装依赖可能执行脚本，因此本次只静态核验入口，未运行。未来须使用独立测试 OS 账号或已核验的数据目录隔离；`npm --prefix` 只隔离依赖，不能隔离 DSH profile。npm CLI 拒绝 desktop profile，不能盲用插件 README 的 desktop 示例。

发布包 `dist/client/settings.js:278` 的密码入口发送 serverUrl/email/password；`dist/server-api.js` 使用既有 `/api/v1/auth/login`。候选 `apps/server/src/server.ts:237` 有对应路由，故无需另造登录协议。插件空地址仍回落公共服，未来测试必须显式设置 origin，不能沿用空值。

发布插件 `dist/harness-version.js:18` 将 `0.2.2-rc.1` 判为 V3；`dist/service.js:383` 仅在 `localGateway.supportsCarrier` 时宣告 `harness.remote.v3`；`dist/rpc-router.js:139` 返回 transport.describe。**版本判定只满足必要条件**：未安装真实依赖、未验证 carrier 和安全通道的能力响应，V3 门禁仍未通过。DSH CLI 包本身不含 V3 字符串并不代表引擎不支持，能力来自其运行依赖和插件。

发布插件 `dist/server-connection.js:174` 在无 RTC factory 或 forceRelay 时仍提供 Relay；候选 `apps/server/src/gateway.ts:44` 只宣告 lan/p2p/turn/relay，未含 relay.attach。本候选应验证 Control WebSocket 内 Relay；独立 data socket/attach 不作为既有服务能力。Noise IK、首次 pin 提示、变更拒绝、实际会话/流/审批、刷新和撤销正反例均未运行，不能因登录路由和字符串存在而宣布互操作通过。源归档与包完整性通过不关闭 B 门禁。

## 本机启动副作用与状态边界清单

以下是实际源码调用链检查；本批没有改动它们，也没有测得“本机调用为零”。

| 入口/位置 | 当前副作用或状态 | 后续必须满足的边界 |
| --- | --- | --- |
| `main.dart:28` → `LaunchController.begin`；`launch_state.dart:130,268` | 首帧前尝试 `dsh/launch.begin`，成功会注册 handler；异常 fallback 不等于没有调用 | 能力判断须早于 Android launch 调用；区分系统 UI 通道与本机引擎通道 |
| `app.dart:150`、`appearance_state.dart:125` | 刷新率服务与动态色可能进入平台通道 | C 核对平台守卫和 fallback，不以隐藏 RootGate 替代 |
| `ui/shell/root_gate.dart:283` → `runtime/runtime_state.dart:60` | watch runtime 导致订阅 events 和 getStatus；刷新异常仍 loaded | 远程分支装配前决定能力；不得把未知状态当未安装进入引导 |
| `root_gate.dart:249,303,310,312,317` | 自动 start、setup 监听、技能安装、guestFs 失效、诊断发布 | 不装配本机监听或写入；远程连接不触发本机技能/文件系统操作 |
| `state/connection_state.dart:61,76` | local connection 监听网络并读取 runtime、运行后连本机 endpoint | 无 Host 状态不得读取 local provider；无本机兜底 |
| `state/hosts_state.dart:49,306,316,353` | decode/初始 Host/forget 均可落 local；active_host 没有 origin/account | 新远程选择显式为空；选择与缓存归属须含 origin/account/host，未知账号不得展示历史 |
| `hosts_state.dart:392,418,433` | 切服 forget 远程 Host，operation epoch 防晚到登录；null 仍指公共服 | 保留 Android 旧约定；iOS 未来独立版本化选择，关闭旧连接并失效列表/会话/审批，不用 null 偷换默认 |
| `remote_account.dart:283,346` | 规范 origin 的 SHA-256 前 24 位隔离 identity/credentials/pins；同 store + scope 共享写入队列/epoch | 复用现有库；切服保留旧 origin 凭据，切换不等于撤销，离线退出不能宣称服务端撤销 |
| 手机操控/voice/runtime、WebView、安装更新/图标/权限入口 | 仍有 Android 专属入口和通道 | C/D 按实际调用装配过滤；完整远程 UI 不在本批范围 |

下一批配置需复用 `normalizeServerUrl`，R1 额外坚持 HTTPS；显式保存 origin 优先编译默认，空默认停未配置。旧 null/缺失无法区分使用过公共服或全新安装，应保留兼容意图且要求确认，不自动登录；非法旧值保留并要求重选。版本迁移幂等，不删除旧凭据。必须测大小写/端口/尾斜杠/非法 origin、A→B→A 晚到响应、同 hostId 跨 origin、退出与 pin 隔离。现有库隔离不代表 App 全部缓存已隔离。

## 工具链、验证与下一门槛

Windows；Node `v24.20.0`，满足候选 CLI Node 要求；Python 3.14 可用。PATH 无 Flutter/Dart，进一步按 flutter.bat/dart.exe/dart.bat 文件名检查 `D:/tools`、`D:/Infra Tools`、`D:/AIInfra/tools`、`D:/Ai Infra Tools`、`D:/MovedFromC/.cache`、本用户 Local/Programs/Downloads/agent-tools 和 `D:/download`、`D:/projects` 等常见位置未发现。WSL 列表命令仅返回帮助，未获得可用发行版证据。未搜索或读取现用 DSH 用户数据与凭据；这不保证全盘绝无 SDK，用户若已有非标准位置可直接提供路径。

| 实际命令 | 结果 |
| --- | --- |
| `python tooling/ios_remote_preflight.py -o .harness-tmp-ios-preflight/receipt.json` | 通过：公开下载、两包完整性和身份、源码归档 hash、静态索引；stdout 另存临时文件 |
| `python tooling/ios_remote_preflight.py --offline -o .harness-tmp-ios-preflight/offline-receipt.json` | 通过：缓存字节复核，无网络 |
| `python -m unittest discover -s tooling -p test_ios_remote_preflight.py -v` | 4/4 通过：篡改拒绝、只读归档、缺失缓存失败、静态位置索引 |
| `python app/tool/l10n_merge.py --check` | 通过：56 parts、5853 keys |
| `python app/tool/guide_sync.py --check` | 失败：现有 `app/assets/skills/dsh-go-guide/manifest.json` 过期；相关指南、生成器和生成物均无本轮 diff，未擅自再生成夹带修复 |
| Flutter/Dart analyze/test、iOS 构建、模拟器/真机、真实 Server/Host 实连 | 未运行：未找到 Dart/Flutter；无 Mac/隔离服务端及 Host 环境；本批禁止访问现用 Host |

本批代码仅新增预检工具和其测试；**未修改 Dart 产品代码，也无“代码已改但未测”的产品补丁**。服务器选择、配置迁移和 App 状态隔离待有可运行 Dart 工具链后实施；不安装 SDK、不改全局环境。预检工具只用标准库，下载走批准的公开 HTTPS，不引入项目依赖。

A 尚有镜像/完整 Host 依赖组合和互操作证据缺口；后续 B 需另外授权的隔离部署环境及测试 profile，先冻结精确依赖和镜像/本地 image ID，再测登录/刷新/撤销、pin、V3、Control Relay 和流审批。C 需提供 Mac 后生成并审查工程，验证全依赖模拟器启动和 iphoneos 无签名链接；失败先停扩面。当前未生成 ios/，未声明任何 iOS 构建或真机验收通过。
