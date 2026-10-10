# DSH Mobile 原生 iPhone 客户端

这是面向现有 DSH Desktop 0.2.0-rc.2 与 `dsh-tether-ios` Mac 插件的独立 SwiftUI 客户端。Bundle ID 为 `com.hoya.dsh.mobile`，不会覆盖既有 Tauri 手机端。最低 iOS 17.5。

## 已接入

- 通过官方 iroh Swift 绑定连接现有 `dsh-tether/0` Mac sidecar；首次粘贴 Mac 插件显示的完整 DSH Mobile 配对串（电脑 ID 和六位码都必需）。自建中继模式的配对串还包含中继地址，客户端用它建立连接并保存在本机配对列表，供以后重连。再次粘贴已保存电脑的配对串时，客户端改用已配对身份重连并更新中继地址。
- iroh 身份私钥保存在 iOS Keychain，已配对电脑名称与 ID 保存在 App 沙盒。Mac 的 DSH 浏览器认证值仅由 sidecar 在受控代理内注入，不进入 iPhone。
- 通过 iroh 代理流调用同版 DSH Gateway：真实会话列表、新建与命名、工作模式、消息发送、停止、会话实时跟随；工具批准经原有 tether 控制流单次允许或拒绝。
- 设置页读取 Mac 插件的当前中继模式。中继切换仍由电脑端插件控制；手机端不伪装成已切换。
- 设置页通过 DSH `pluginInventory/list` 显示电脑插件的实时启用与运行状态；通过已安装的 `dsh-cost-meter` 只读统计接口显示近 91 天的真实 Token 活动热力图。电脑缺少对应接口时明确显示不可用。

## 当前边界

- 插件列表目前只读，安装、停用与配置仍在电脑端操作；附件和图片发送尚未接入。界面不显示假数据。
- tether 现有审批控制消息不包含 Session ID，因此批准卡在当前会话和会话列表都可见，不能声称它已与某一个会话准确绑定。
- 连接由 iOS 前台进程保持；App 进入后台后不承诺持续接收批准或推送。
- 新 Bundle ID 不继承旧 Tauri App 的配对身份，首次须重新配对。清除本机配对会删除本 App 的 Keychain 身份及沙盒主机簿；Mac 端白名单需要在电脑插件中单独撤销。卸载 iOS App 不保证系统自动清除 Keychain 项。
- Mac 切换公共/自建中继后，手机需粘贴新配对串更新保存的中继路径；只更新配对信息，不会改变 Mac 的中继选择。

## 构建

GitHub Actions 的 `build-native-ios` 使用固定版本 XcodeGen 和固定提交的 [iroh-ffi Swift 包](https://github.com/n0-computer/iroh-ffi/tree/5e451092dba0c1a09ee83ff6e5be37b1152a5c58)，构建 unsigned iPhone arm64 IPA 并上传该次运行的 Artifacts；不会发布 Release 或持有签名凭据。Hoya 可对候选 IPA 自行签名安装。

本地有完整 Xcode 时，在仓库内运行：

```sh
swift test --package-path ios-native/ProtocolKit --scratch-path ios-native/ProtocolKit/.build
xcodegen generate --spec ios-native/project.yml --project ios-native
xcodebuild -project ios-native/DSHMobile.xcodeproj -scheme DSHMobile \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios-native/.derivedData \
  -clonedSourcePackagesDirPath ios-native/.packages CODE_SIGNING_ALLOWED=NO build
```

CI 编译和可签名 IPA 不能代替与家中 Mac 的真机配对、Wi-Fi/蜂窝和审批闭环验收；未取得这些证据前，产物标记为候选版。
