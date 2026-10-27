# 枝序 Flutter 桌面版（1.0.4）

在同一套 Flutter 代码中实现 macOS / Windows 桌面工作台，对照 `apps/macos` 原生版移植交互与样式。原生 1.0.3 及现有安装包保留。此工程是当前双端实现，应用名为 `枝序`，Bundle ID 为 `app.zhixu.flutterprototype`。

逐项对照与剩余验收项见 [PARITY.md](PARITY.md)。

## 已实现

- 220 宽项目侧栏、紧凑工具栏、可拖动文件面板、圆角选中态与主色短横线、主题右键菜单、细滚动条、操作按钮手型与悬停反馈。
- 项目打开、初始化、创建、克隆、持久项目列表；主题目录选择窗口；设置的语言、浅色/深色模式、本项目提交署名、远程仓库管理和关于信息。
- 默认勾选提交、Shift 连选、全选、单文件/全部撤销，手动暂存高级模式；勾选提交通过独立索引隔离未勾选内容。
- 文件目录懒加载、搜索、刷新、忽略项灰显，创建文件/文件夹、剪切/复制/粘贴、同目录副本、重命名、移到废纸篓、在系统文件管理器打开；支持多选与 Cmd/Ctrl 快捷键。
- 普通文件和差异分开打开，文件标签、脏状态提示、保存保护、语法着色、行号和修改标记、minimap、基础补全、括号配对、自动缩进、Markdown 预览。
- 本地/远程分支列表、创建、切换、重命名、删除、合并与对比；远程已存在本地跟踪分支时直接切回。覆盖修改时可收起、携带或确认放弃。
- 历史分页与刷新、提交详情、单文件历史、恢复旧版本、撤销最新未推送提交、修改其说明、生成反向提交。
- 临时备份的分支/时间列表，备份—文件—差异三栏；选择任意备份恢复、当前/备份同步滚动对比、同内容跳过、逐文件选择、删除备份或备份内文件前确认。
- 文本冲突的当前/传入/结果三栏、逐块选择与编辑；二进制、删除或符号链接冲突可选择完整版本，标记解决后继续/中止 Git 操作。
- 多远程获取/推送/拉取选择、待推送/待拉取数量、分叉提示；操作按钮加载反馈及状态栏进度。
- 默认复用系统 Git 认证；HTTPS 失败时输入凭据，成功后交给已配置的 Git helper；GitHub 通过 GitHub CLI 网页设备授权。

## 新增编辑与项目管理

- 文件目录打开 PNG、JPEG、GIF、WebP、BMP、WBMP、ICO 时显示图片，支持透明网格、缩放/拖动和适应窗口；图片只读，不走文本保存。SVG 保留源码编辑。单张文件上限 32 MB，预览解码宽度最多 4096 像素。
- 增加 Dart、Kotlin、C#、C++、Ruby、Lua、R、PowerShell、GraphQL、Dockerfile、Makefile、CMake 的识别、高亮与关键词补全；配置文件和更多扩展名也可识别。此功能不包含语言服务器、编译或类型诊断。
- 左侧项目可按住拖动排序，排序保存在偏好中；启动时恢复上次项目，但不改变排列。

## 运行与构建

工具链：Flutter 3.47.2 / Dart 3.13.2，以及系统 Git。macOS 需要 Xcode；Windows 需要 Visual Studio C++ 桌面工具链和 Git for Windows。

```sh
cd apps/flutter_prototype
flutter pub get
flutter run -d macos
# 在 Windows 电脑上：
flutter run -d windows
```

可传入测试仓库路径，或使用“打开项目”。所有提交、恢复、推送均为真实操作，请先使用测试仓库。

```sh
flutter analyze
flutter test
flutter test integration_test/desktop_test.dart -d macos
# Windows 实机：
flutter test integration_test/desktop_test.dart -d windows
```

`tool/check-macos.sh` / `tool/check-windows.ps1` 执行检查并构建。macOS 脚本会在现有 GitHub CLI 可用时随包复制 helper、许可证与版本信息；Windows 网页登录需要 `gh` 位于 PATH。macOS 输出为 `build/macos/Build/Products/Release/枝序.app`。

## 认证与数据

不建立应用账号库，不把密码写入配置文件或命令行参数。临时 HTTPS 凭据仅通过限定目标 URL 的单次进程环境传入；成功后交给电脑已有 Git helper。macOS 未配置 helper 时，仅当前命令使用系统 osxkeychain（若可用）；不修改全局配置。其他环境没有 helper 时提示未记住。其他客户端是否共用取决于是否使用相同 helper。SSH 仍使用系统密钥和配置。

项目列表、主题和语言保存在独立的 `ZhixuFlutter/preferences.json` 应用数据目录，不读取或覆盖原生版偏好。编辑器使用 Flutter TextField 的组合输入链路，组合输入期间不会自动替换文字。

## 验证边界

详见 [VALIDATION.md](VALIDATION.md)。目前不能宣称与原生版完全等价：Windows 已通过云端编译、自动测试及窗口交互检查，仍需真实桌面输入法、多屏与文件占用验证；真实 GitHub/Gitee 登录仍需测试账号验收；大文件性能尚未做基准测试。普通本地构建不等于签名公证分发包；发布请使用 `tool/package-macos.sh` 或 Windows 云端安装包流程。

## 1.0.4

应用包与界面版本统一为 1.0.4。支持历史提交、分支对比、变更和临时备份中的图片对照；语言切换同步 macOS 菜单，并补充中英文提示与深浅色适配。原生 macOS 版保持不变。

## Windows 安装包

GitHub Actions 的 `Windows installer` 工作流在 Windows 上执行静态检查、测试、Release 构建并打包。构建产物 `zhixu-windows-installer` 内包含 EXE 安装程序与 SHA-256 校验文件。默认勾选创建桌面快捷方式，也可自行取消。

要求 Windows 10/11 x64 和 Git for Windows。包内带 Flutter 依赖与 Visual C++ 运行库，无需安装 Flutter 或 Visual Studio。GitHub 网页授权需要电脑安装 GitHub CLI；HTTPS 账号密码/令牌与已有 Git 认证不受影响。Windows 安装包暂未做代码签名。

本机已有 Windows 构建工具时可运行 `tool/check-windows.ps1`，生成 `build/installer/Zhixu-1.0.4-Windows-x64-Setup.exe`。

## 制作分发包

- Windows：云端工作流只生成 EXE 安装程序及校验文件。`tool/package-installer.ps1` 使用 Inno Setup 6，验证目录复用、覆盖升级、运行保护和卸载；应用通过命名互斥量阻止安装期间覆盖运行中的代码。
- macOS：在本机设置 `ZHIXU_SIGN_IDENTITY` 和 `ZHIXU_NOTARY_PROFILE`，运行 `bash tool/package-macos.sh`。需要已安装的 Flutter、GitHub CLI helper、Developer ID 证书与已验证的公证钥匙串配置。脚本保留原生应用，输出到根目录 `dist/release-版本/`，公证回执存于已忽略的证书资料目录。
- macOS 分发包当前仅包含 arm64，要求 macOS 14+。升级原生版需重新添加项目；不会自动迁移原生版偏好。
