# 第三方与现有资源

- App 图标复制自本仓库 `app/src-tauri/app-icon.png`，属于既有 DSH Tether 资源；项目根目录 `LICENSE` 为 MIT，保留原版权声明。
- XcodeGen 2.46.0（MIT）只在构建时生成 Xcode 工程，不进入 App 安装包：[项目及许可证](https://github.com/yonaskolb/XcodeGen/tree/2.46.0)。
- [iroh-ffi v1.1.0](https://github.com/n0-computer/iroh-ffi/tree/5e451092dba0c1a09ee83ff6e5be37b1152a5c58) 及其 iroh Rust 网络库用于 iPhone 到 Mac 的端到端连接，按该项目的 MIT 或 Apache-2.0 双许可证使用；许可证文本见 `licenses/iroh-ffi/`。Swift 包固定到该提交及其 manifest 中 SHA-256 固定的 XCFramework。
- SwiftUI、Foundation、Security、CryptoKit 均为 Apple 平台框架。没有复制 HAPI 或 OpenCode 的代码。
