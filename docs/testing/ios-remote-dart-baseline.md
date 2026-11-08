# iOS R1 平台无关基础与 Windows 测试基线

本轮接续 `_codex_post_install_next_last.txt`：先获取锁定依赖并运行两个纯
Dart 包和 App 的分析、测试，再完成有界的服务器选择解析基础。基于本地
`main` 的 `4ea522239890e7097841b5e2c436b9c6b6178ea5`；fetch 后
`origin/main` 为 `72357f62be2d247a4372cccd148ff0be1f5d2a6d`。
用户明确授权在 main 正常提交，不推送。日期：2026-11-08。

## 实际实现边界

`packages/dsh_remote/lib/src/server/server_selection.dart` 新增纯 Dart 模型：

- schema v1，明确区分 unconfigured、selfHosted、hosted。
- 已保存选择优先，其次旧安装配置，最后编译默认地址。
- 无默认地址的新安装保持未配置；旧空/缺失地址仅在调用方确认旧安装时
  迁移为需确认的 hosted，无可连接 origin，不静默选择公共服。
- 显式地址按共享规范化函数归一化，但远程专用选择进一步要求 HTTPS；
  拒绝空 authority、路径、userinfo、query、fragment 和损坏记录。
- 无效输入抛出不含原地址的 FormatException，不回落；调用方保留旧值供修正。
- 迁移可序列化且幂等，显式选择不受默认值变动影响。

这是解析/迁移基础，尚未接入 Flutter 的 SharedPreferences、RootGate 或
账号创建。包级 RemoteAccount 的 null 公共服约定及 Android 现有行为未改。
未来调用方必须等待明确 origin，显式传入账号，并保留现有 origin/epoch
所有权检查。没有修改登录、Host pin、撤销、凭据存储或连接协议。
R1 仍限个人使用、加密 Relay；没有声称已完成 Relay-only App 或 iOS 客户端。

## 工具与依赖

Windows x64，`D:/tools/flutter`：Flutter 3.47.7（abaf9c5237），Dart 3.13.5。
每个命令进程内临时设置 PATH、PUB_CACHE=`D:/tools/pub-cache`、
PUB_HOSTED_URL；App 测试另设 DSH_TEST_FONT_DIR=`D:/tools/dsh-test-fonts`。
没有修改用户/系统环境变量，没有运行全局 Flutter 配置命令。

两个 Dart 包使用其锁文件来源 `https://pub.flutter-io.cn`；App 锁文件来源为
`https://pub.dev`。App 首次镜像获取因缺 image_picker_ios 失败（exit 69）。
官方源获取两次因下载流缓慢中止；最后两个包使用官方归档下载，SHA-256
逐项匹配锁文件后以 tarfile 的 data 过滤器解压至 D 盘 Pub 缓存，再执行
`flutter pub get --offline --enforce-lockfile` 成功。没有升级或修改三个锁文件。

官方归档（仅缓存于项目外，不入仓库）：

| 包 | SHA-256 |
| --- | --- |
| riverpod 3.4.3 | 484dfc873ea4c4f4240e5635444fa066f87b07862b7279ebd004a2b71fba4b7a |
| shared_preferences 2.5.6 | 1e85e0dccf5b4a016077fea7dfbb4a7cb39c759ac1596fcf60c06deadb7da91f |

地址为 `https://pub.dev/api/archives/<包名>-<版本>.tar.gz`。

三份测试字体从官方 Noto 仓库 `notofonts/noto-cjk` 的 Sans2.004 标签、
`Sans/OTC/NotoSansCJK-<字重>.ttc` 下载到 D 盘，不安装系统字体。

| 字重 | SHA-256 |
| --- | --- |
| Regular | b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a |
| Bold | faa5f3656a78b2e2d450d27fe8382c778bc2b6bb5ea29c986664a6a435056ceb |
| Light | 872def437cf8b9c41bf1736da891e34a8c25b764c0c4a51418d3745570660f42 |

Material 字体使用 SDK 已有资源，项目字体使用已有 assets。没有伪造字体、
截图或更新 golden；Windows 与 CI Ubuntu/font repack 及 Emoji 加载路径不一致，
截图结果不能充当 CI 截图基线。drawer 的 Emoji helper 固定读取 Linux 路径，
本轮没有修改它或模拟该系统目录。

## 验证

最终计数与失败分类在同目录 `ios-remote-dart-baseline.json`；统计采用 JSON
reporter 的非隐藏 testDone，跳过不算通过。原始日志保留在本地
`_baseline_*.log` / `_baseline_*.jsonl`，不提交日志或测试缓存。

| 范围/命令（在对应目录执行） | 通过 | 失败 | 跳过 | 退出码 |
| --- | ---: | ---: | ---: | ---: |
| dsh_client：dart test --reporter json（原始基线） | 697 | 2 | 31 | 1 |
| dsh_client：心跳/尾空格路径两个文件单独复核 | 11 | 1 | 0 | 1 |
| dsh_remote：dart test --reporter json（修改前） | 460 | 2 | 4 | 1 |
| dsh_remote：新增迁移及相关回归五个测试文件 | 81 | 0 | 0 | 0 |
| dsh_remote：dart test --reporter json（修改后全量） | 474 | 0 | 4 | 0 |
| App：flutter test --no-pub --concurrency=4 --reporter json | 9147 | 1056 | 387 | 1 |

App 的 906 个测试文件全部启动，全量运行约 931 秒。1056 个失败中 982 个
报告了像素差异；其余 74 个未报告像素差异，JSON 中逐项列出。像素差异分类
不排除同一用例同时有其他异常，不代表所有这类失败仅由 Windows 渲染导致。

其他实际执行命令与结果：

- 两个包：`dart pub get --enforce-lockfile`、`dart analyze` 均 exit 0。
  dsh_remote 修改后再次 `dart analyze` 也无问题。
- App：`flutter pub get --offline --enforce-lockfile` exit 0。
- App：`flutter analyze --no-pub` exit 255：analysis server 在 LSP JSON
  读取阶段抛 `FormatException: Unexpected end of input`，未得到分析结论。
  使用同 SDK 的 `dart analyze` 替代检查，exit 0、No issues found；不把原命令
  崩溃写成通过，没有修改 SDK、全局配置或源码来绕过。
- 定向命令：`dart test test/server_selection_test.dart test/ipv6_server_url_test.dart
  test/account_cross_instance_logout_test.dart test/account_refresh_owner_test.dart
  test/qr_login_cancellation_test.dart --reporter json`。包含 12 个新增模型测试及
  69 个既有 URL、刷新、取消、退出/跨 origin 用例，全部通过。
- 客户端复核：`dart test test/dsh_go_heartbeat_test.dart
  test/session_path_whitespace_test.dart --reporter json`。
- `python app/tool/l10n_merge.py --check` exit 0（56 parts、5853 keys）。
- `python app/tool/guide_sync.py --check` exit 1：既有 manifest 过期，未修改。
- `git diff --exit-code -- app/pubspec.lock packages/dsh_client/pubspec.lock
  packages/dsh_remote/pubspec.lock` exit 0；三个锁文件未变化。

失败证据与解释边界：

- 客户端原始基线：心跳 fake WebSocket 的 `StreamSink is closed`，以及 Windows
  尾空格路径无法区分文件；单独复核只保留路径失败。
- Remote 原始基线：两个 activation 用例的 fake Host WebSocket 关闭异常。
  修改后全量未复现；没有修改相关路径，不宣称此时序异常已修复。
- App 非像素失败包含尾空格/路径分隔符、文件占用与超时、4 个会话同步 Timer
  清理断言、文本/换行/字符解码比较、缺少 `sh` 的 10 个 bootstrap 用例、
  生成文件同步以及桥接/平台 fixture 失败。完整 74 项见 JSON；不统一归为字体
  问题，不以本轮基线推断在 Linux/CI 上的结论，没有广泛修改无关代码。
  其中符号链接创建返回 Windows errno 1314（当前会话缺少所需特权），本轮未
  修改系统开发者模式或提权策略；需要相应测试环境才能验收该用例。
- 客户端 31 个、Remote 4 个跳过用例涉及显式 live 环境/下载索引等前置条件；
  未提供真实 Host/账号，不运行这些外部测试，不把跳过当通过。

本轮实际修改的六个路径：

1. `packages/dsh_remote/lib/src/server/server_selection.dart`
2. `packages/dsh_remote/lib/dsh_remote.dart`
3. `packages/dsh_remote/test/server_selection_test.dart`
4. `packages/dsh_remote/README.md`
5. `docs/testing/ios-remote-dart-baseline.md`
6. `docs/testing/ios-remote-dart-baseline.json`

本地汇总 CLI：`python .harness-tmp-baseline/finalize.py -o
docs/testing/ios-remote-dart-baseline.json`，stdout 保存为
`.harness-tmp-baseline/baseline-stdout.json`；与 `-o` 回执逐字节一致
（字节数见本轮回执）。这是本轮汇总脚本的 CLI 回执，不是另起 Codex 进程生成的结果。
原用户未跟踪文件、本轮原始日志、截图差异与 D 盘依赖/字体缓存均保留；
没有创建本轮临时分支或工作树。

## 下一门槛

后续才能把模型接入设置加载/持久化及账号创建，明确旧安装识别与迁移确认，
继续验证 A→B→A、Host/会话缓存与凭据的 origin 归属，防止把未配置的 null
传入仍有公共服默认值的 RemoteAccount。不能仅替换常量后宣称迁移完成。

完整远程入口、零 runtime 调用及原生插件扩面仍受 Mac/Xcode 门槛约束；
HTTPS/WSS Server 与隔离 Host 的无补丁实连、镜像 digest、真实撤销和恢复仍待
后续授权环境。没有使用真实 Host 账号，没有部署服务、开放防火墙端口、签名、
上架、安装 Android SDK/Visual Studio 或重试已知 403 推送。
