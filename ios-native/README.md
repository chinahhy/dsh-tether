# DSH Mobile 原生界面试用版

这是独立的 SwiftUI iPhone 界面试用工程，基于现有 DSH Tether `ios-only` 分支的配套设计。它与现有 Tauri 客户端并行，使用独立 Bundle ID `com.hoya.dsh.mobile.preview`，不会覆盖已在使用的手机 App。

## 目前可以试什么

- 会话列表、搜索、工作模式筛选，以及带标准/PTC/极简/创造模式选择的新建任务页。
- 原生聊天排版、输入和任务内的批准卡片；所有操作只改变内存中的演示状态。
- 设置页的设备、中继选择、插件入口和按来源切换的 13 周 Token 活动热力图。
- `ProtocolKit` 对既有 `dsh-tether/0` JSON-lines Wire 消息和 DSH 0.2.0-rc.2 普通 RPC envelope 的编码、边界及 `rpcId` 校验。

屏幕始终标明“演示数据 · 尚未连接电脑”。目前**不能**配对、读取真实会话、执行插件、发送消息或批准真实工具调用；中继控件不会切换网络，热力图也不是账户账单。`ProtocolKit` 只做纯数据编解码，尚未接入 iroh Swift 传输、`/api/remote.mux`、真实会话 API 或现有 Mac sidecar。

## 构建与验证

本项目使用 [XcodeGen 2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0) 从 `project.yml` 生成 Xcode 工程。CI 的 `build-native-ios-preview` 在 macOS runner 上先运行 Swift package 测试，再构建 iPhone arm64 unsigned `.app`，打包为 `dsh-mobile-preview-unsigned.ipa` 上传到该次 Actions 运行的 Artifacts。它不会发布 Release、提交签名证书或修改现有 Tauri IPA。

本地有 Xcode 时，可在仓库内运行：

```sh
swift test --package-path ios-native/ProtocolKit --scratch-path ios-native/ProtocolKit/.build
xcodegen generate --spec ios-native/project.yml --project ios-native
xcodebuild -project ios-native/DSHMobilePreview.xcodeproj -scheme DSHMobilePreview \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios-native/.derivedData CODE_SIGNING_ALLOWED=NO build
```

只有 Command Line Tools、缺少完整 Xcode/XCTest 的 Mac，可以运行 `sh ios-native/scripts/test-protocol-local.sh` 做协议烟测。所有主动生成的工程、缓存与产物都留在 `ios-native/` 内，并被 Git 忽略。未签名 IPA 需要 Hoya 自行签名后才能安装；构建成功不等于配对或蜂窝网络实机验收。

## 下一阶段接入条件

1. 固定并验证官方 iroh Swift 绑定与 host 的 ALPN `dsh-tether/0`、Pair/Hello、Proxy 流互通；私钥只存 iOS Keychain，已配对设备保存在 App 沙盒。新 Bundle ID 不自动继承旧客户端身份。
2. 经当前受控 Mac 代理调用 DSH 0.2.0-rc.2 的 `/api/<namespace>/<method>` 和 `/api/remote.mux`，完成列表、历史、发送、取消、工作模式及一次性审批闭环。
3. 以真实接口来源核准 Token 用量口径，才替换演示热力图；第三方插件页面需要独立适配。

删除此试用 App 时，iOS 沙盒会被系统清理；若后续版本写入 Keychain，卸载不保证清除 Keychain 项，须提供 App 内解除配对。此版本未建立身份、配对记录或本机服务，因此没有新增 Mac DSH 残留。
