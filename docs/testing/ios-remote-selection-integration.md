# R1 服务器选择接入与隔离验收（2026-11-08）

基线：`19c67f153caf20c4d87408428f90e4e4fd0d9e26`，本地 main。首次正常
`git push origin main` 返回 403：`Permission to hzopc1031/DSH-Go.git denied to lurnagao-dahua`。
remote 保持 `https://github.com/hzopc1031/DSH-Go.git`，停止后续推送，无账号、凭据或历史变更。

## 本轮边界

- `app/lib/remote/server_selection_store.dart`：将已有纯 Dart 模型接到 SharedPreferences，
  仅存版本化 origin/选择。新安装无默认地址保持未配置；升级缺少旧地址时记录 hosted 待确认；
  旧自建地址迁移幂等，版本化选择优先。不删除旧配置、凭据或用户 Host；非法记录保留并报错，
  不回落公共服。写失败报错并重新加载持久化值，避免内存缓存伪装成已保存。
- 安装历史由未来调用方显式提供 `hasLegacySettings`；本轮没有凭空推断历史，
  没有读取 Keychain/Keystore 真实凭据。确定可靠的安装历史证据仍是启动接入的必要条件。
- `DshRemoteRelayBackend.fromSelection`：显式 origin 才可构造账号，复用已有邮箱密码协议、
  origin 安全存储和 Noise Relay 路径；无 peer connector，不启用直连；设备名称/platform 显式传入。
  每个 backend 保有独立 Host 目录和首次信任审批缓存。
- 新增 App 持久化/工厂测试和纯 Dart 双服务器隔离测试。后者使用进程内 loopback fixture，
  同 Host id、不同 identity，覆盖 A→B→A 身份恢复、凭据/pin 作用域、服务端成功撤销 B 不影响 A。
  fixture 的 HTTP 地址仅供测试，产品选择仍仅接受 HTTPS origin。

本轮只接入 App 存储适配器和 backend 工厂；**尚未接入设置页面、App 启动、自动持久化登录、
activeHost/currentSession 或业务恢复**。现有 Android provider 和公共默认约定保持原行为。
工厂与存储由测试直接调用，不代表全局启动已经使用新选择。
顺序 A→B→A 配置保存已覆盖；当前 Android 表单并发登录用原有竞态测试验证，
不将其等同于未来远程专用启动的并发切换验收。

## 环境与命令

Flutter 3.47.7 / Dart 3.13.5，`D:/tools/flutter`；命令进程内设置 PATH、
PUB_CACHE=`D:/tools/pub-cache`；Dart 包 PUB_HOSTED_URL=`https://pub.flutter-io.cn`，
App 为 `https://pub.dev`，DSH_TEST_FONT_DIR=`D:/tools/dsh-test-fonts`。
使用现有锁定依赖和缓存，本轮没有重新解析或升级依赖，三个锁文件差异为空。

App 工作目录：

```powershell
flutter test --no-pub test/remote/server_selection_store_test.dart test/remote/relay_backend_test.dart test/remote/relay_login_origin_test.dart test/remote/relay_login_publish_test.dart test/remote/relay_login_lifecycle_test.dart test/remote/relay_login_submit_test.dart test/remote/remote_startup_test.dart --reporter json
dart analyze
flutter analyze --no-pub
```

最终 App 上述测试 **63 通过、0 失败、0 跳过**（新增配置测试 12 个）。dart analyze 通过；
flutter analyze 仍因 LSP JSON 解析崩溃退出 255，与旧基线一致。
App 全量本轮未重跑；旧 9147/1056/387（其中 982 像素差异）只作历史基线，不能计作本轮结果。
dsh_client 本轮未改、未重跑，历史 697/2/31 未被修复或改报通过。

dsh_remote 工作目录：

```powershell
dart test --reporter json
dart analyze
$testFiles = @(rg --files test -g '*_test.dart' | Where-Object { $_ -ne 'test\origin_isolation_test.dart' })
dart test @testFiles --reporter json
dart test test/origin_isolation_test.dart test/server_selection_test.dart test/compact_history_test.dart test/remote_client_test.dart test/stream_transfer_test.dart --reporter json
dart test test/origin_isolation_test.dart test/server_selection_test.dart test/account_restore_test.dart test/account_cross_instance_logout_test.dart test/account_refresh_owner_test.dart --reporter json
```

本轮首次全量 **471 通过、4 失败、4 跳过**；静态分析通过。相对旧 474/0/4，新增隔离用例通过，
4 个失败均为 `Bad state: StreamSink is closed`，位于未改动的 fake_remote.dart WebSocket 关闭路径。
旧测试集合（排除新增文件，包产品源码与测试替身均与基线相同）对照为 **472/2/4**，
证明相同错误在旧集合也存在；失败用例随时序波动，不能说逐一证明所有失败均与新用例无关。
相关文件加新增测试复核 **72/1/0**，仍在旧 remote_client activation 用例关闭时报错。
没有改替身、关闭安全用例、更新 golden 或修复无关代码。
新增隔离、迁移、账号恢复、跨实例撤销和刷新所有权五文件的针对性安全测试最终 **28/0/0**，exit 0。

根目录 `python app/tool/l10n_merge.py --check` 通过；
`python app/tool/guide_sync.py --check` 因既有 manifest.json 过期失败（exit 1）；
`git diff --check` 通过。
原始 `_r1_*.jsonl`、分析日志及用户原回执均保留，机器统计见同名 JSON。
最初新增隔离测试曾因误用参数名无法编译，改为实际 API `confirmNewHost` 后重测；
该开发过程日志 `_r1_origin_test.jsonl` 保留，不当成最终结果。

## 未通过的门槛

1. 现有 `RemoteAccount.logout()` 捕获远端撤销错误并本地退出，不能据此确认服务端已撤销。
   这是检查发现的既有行为，本轮未扩改；账号 UI 接入前须完成失败反馈契约和针对性测试，
   不得将本轮“成功撤销隔离”用例解释为撤销失败安全验收完成。
2. activeHost、会话、审批、读取缓存等全局状态尚未按 origin 完成迁移与清理。
   本轮只验收账号原有作用域及新 backend 实例缓存，不能宣称整个 App origin 隔离已完成。
3. 无 Mac/Xcode 原生预检，无未打测试补丁的 Server/Host 实连，无 iPhone Keychain、
   Relay、后台/切网验收；iOS 尚不可称可交付。未生成完整 iOS 壳、部署、操作真实 Host、签名、上架或新增本机引擎。

后续先解决账号撤销失败反馈和安装历史识别，再在 Mac 原生门槛与隔离实连允许的范围接设置、
启动与全局状态清理。域名未定继续保持未配置，不静默选择公共服务器。
