# macOS 开发

本目录是独立 Swift Package，包含 SwiftUI/AppKit 应用、集成测试、图标和构建脚本。当前支持 macOS 14+ 的 Apple Silicon 设备，Swift 6 工具链以 Swift 5 语言模式编译。

## 构建

在仓库根目录执行：

```sh
bash scripts/bootstrap-gh.sh
bash scripts/build.sh
```

也可以在本目录执行同名脚本。源码编译使用 `swift build`；生成应用使用 `bash scripts/build.sh`。应用输出始终默认位于仓库根目录的 `dist/枝序.app`；缓存和测试日志位于本目录 `.build/`。

GitHub CLI 的可执行文件不纳入源码仓库，下载脚本锁定版本及 SHA-256。纯 Swift 编译不需要下载 CLI，但生成完整应用需要它。更新 CLI 时应同时更新脚本、VERSION、许可证与第三方说明。

默认使用 ad-hoc 临时签名。维护者可通过 `ZHIXU_SIGN_IDENTITY` 指定身份；本机已有的根目录 `.build/signing-identity` 仍可复用。证书、私钥和公证凭据不属于开源构建依赖。`ZHIXU_APP_OUTPUT` 可设置独立的应用输出绝对路径。

## 测试与资源

`Tests/` 为独立 Swift 集成测试，可通过 `scripts/test-*.sh` 运行；不是 Swift Package 的 XCTest target，不能用 `swift test` 代替。参见 [测试说明](../../docs/testing.md)。

`Assets/AppIcon.icns` 为 macOS 图标，`../../assets/brand/AppIcon.png` 为共用品牌图片。重建图标使用 `bash scripts/build-icon.sh`。

平台认证使用 macOS 钥匙串和已有 Git 凭据助手。系统权限、鼠标指针、窗口控件和文本输入法等实现均为 macOS 专用，不能直接复制到 Windows。
