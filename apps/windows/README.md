# Windows 版本状态

1.0.4 已提供 Flutter x64 EXE 安装版，工程位于 `apps/flutter_prototype/windows`，共用代码见 [Flutter 桌面版](../flutter_prototype/README.md)。

需要 Windows 10/11 x64 和 Git for Windows。运行 EXE 安装程序，安装后启动枝序，无需安装 Flutter 或 Visual Studio。Windows 包未签名；GitHub 网页登录需要 GitHub CLI，也可使用电脑现有 Git 认证或 HTTPS 凭据。

静态检查、自动测试、Release 编译、启动和原生窗口操作检查已通过。输入法、不同 DPI、多屏贴靠和真实远程认证仍需实机验收。现有 macOS 原生版继续保留。

详见 [1.0.4 说明](../../docs/releases/v1.0.4.md) 和 [提交与发布准备](../../docs/releases/publish-1.0.4.md)。

EXE 安装版默认按当前用户安装，复用上次目录，升级前要求退出应用；升级及卸载保留用户偏好。
