# 桌面对齐验证记录

2026-10-26 · macOS / Apple Silicon · Flutter 3.47.2 / Dart 3.13.2。

## 自动验证

- 40 项自动测试通过：首次提交、部分暂存、未勾选已暂存文件、重命名/删除/特殊路径、hook 拒绝、外部修改保护、认证成功后保存、认证失败不清除旧凭据、指定远程、真实本地 HTTP 凭据助手。
- 新增分支跟踪重用、符号 HEAD 过滤、未首次提交的分支处理、手动暂存选中提交、临时备份恢复选择与外部写入保护、删除备份内文件、合并冲突继续、历史/反向提交/撤销、忽略路径转义、历史重命名恢复、二进制和删除冲突保留完整版本、输入法组合状态保护测试。
- 桌面集成测试使用隔离的真实临时 Git 仓库，覆盖变更、编辑、保存、刷新、勾选提交、历史详情、设置及临时备份列表。
- 界面截图输出到忽略目录 `build/prototype-screenshots/`。系统 AppKit 关闭按钮是独立原生控件，不包含在 Flutter 画布截图中。

- 原生标题栏实测：45 点高，关闭按钮左/上边距差小于 1 点；保留系统按钮、窗口拖动和双击缩放。
- 新增暂存/工作区差异隔离、多语言补全/词法规则、500 组随机行差异重建验证。

逐项对照见 [PARITY.md](PARITY.md)。

## 本轮新增验证

- 图片：二进制读取保持原字节、项目外符号链接拒绝、预览缩放与重置、损坏图片友好提示。
- 项目：真实指针拖动重新排序，保持当前选中项目；启动恢复逻辑不再把最近项目移到第一位。
- 语言：新增语言及无扩展名配置文件映射、词法与关键词补全覆盖测试。
- 桌面流程新增从真实临时仓库打开 PNG，并验证图片只读标签。
- 提交说明输入框固定 59 点高（18 点行高 × 2.5 + 上下各 7 点内边距），验证多行文字保留和换行动作。
- 标题栏遮罩通过原生坐标通道检查：普通弹窗遮罩、嵌套弹窗叠加、关闭内层保留外层、全部关闭恢复零透明度。

## 样式与缩略图回归

- 依据原生 App.swift、Explorer.swift、CodeEditor.swift：项目短选中条、路径中间省略、文件类型配色、24 点文件行与目录引导线；编辑字体 13、行高 20、顶部留白 12、行号 11。
- 统一普通编辑/差异缩略图，固定 2.2 点缩略行距，滚动长文件背景；拖动框最低 40 点（受容器实际高度限制）。
- 回归覆盖百万行几何边界、画布外像素必须透明、按下拖动框不跳动、拖到底到达最后一行。
- 桌面截图增加 2500 行长文件的普通编辑和差异视图。

## 变更列表显示回归

- 固定 14 点状态列，短名、长名、嵌套路径右边缘一致；状态以 U/A/M/D/R/! 展示，并保留中文/英文悬停解释。
- 高级暂存模式按所在分组展示状态，不将 AM/MM 等原始双列状态直接显示给用户。
- 勾选框视觉缩至 14 点，保留原点击区域；验证全选/逐行中心对齐、点击图形外侧仍能切换。

## 忽略状态回归

- 修复 `--literal-pathspecs` 与 `check-ignore` 不兼容的问题；只对此查询关闭该参数，其他文件操作保留字面路径保护。
- 非匹配退出码 1 与真正失败区分；错误不再静默当作“没有忽略文件”。
- 实际临时仓库覆盖忽略目录、子文件、嵌套 .gitignore、反向规则、强制跟踪文件、全局忽略、中文和换行文件名、规则更新。
- 文件搜索包含忽略文件，搜索匹配项重新查询忽略状态；刷新批次有过期结果保护，并保留旧装饰直到新结果到达。
- 目录状态按冲突/删除/重命名/修改/新增/未跟踪排序，已跟踪修改不会因忽略规则被隐藏。

## 尚需双端验收

- Windows 编译与运行尚未执行，不能以 Mac 通过代替 Windows 通过。
- 自动化验证 composing 状态，不等于真实拼音候选窗、选词、第三方输入法体验已通过。
- 未使用真实账号向 GitHub/Gitee 推送或验证网页登录后的持久化；测试凭据全部为本地模拟数据。
- 大文件连续输入、Windows 文件占用、CRLF、路径大小写及回收站行为仍需实机验证。
- Flutter 版是独立对齐构建，尚未签名公证公开发行，未生成 DMG。

保留 `apps/macos`，未改动原生版源码、正式包或电脑全局 Git 配置；没有推送代码。

## 1.0.4 · 2026-10-26

- 应用包版本 1.0.4，构建号 104；状态栏去掉 Flutter 后缀。
- 47 项单元/组件测试通过，包含工作区/暂存区/历史图片原始字节读取、图片删除与首次提交，以及中文/英文 × 深色/浅色组合。
- macOS 桌面集成测试通过，截图验证历史图片显示；新增/删除图片的缺失侧独立提示。使用真实有效 PNG，并检查不存在解码失败提示。
- macOS 菜单通过原生通道同步语言；Flutter 内置复制/粘贴等文案使用本地化 delegates。
- 设置输入框恢复主题默认高度；复选框保留较小视觉尺寸与原点击范围。
- 只读弹窗准备不再让整页按钮闪成禁用色；图片支持抓手与拖动光标。
- Release .app 已构建并验证本地签名。未制作 DMG、未公证、未上传；Windows 本轮未实机测试。

### 1.0.4 系统菜单与品牌修正

- 不再使用 Flutter 默认英文的退出/窗口菜单项；显式翻译标题，通过原生通道执行退出、最小化、缩放及全屏，保留快捷键。
- 桌面集成测试直接读取 NSApp.mainMenu，验证中文/英文菜单实际标题，确认没有旧版 Quit Zhixu Prototype。
- 应用包名称统一为“枝序.app”；保持原 Bundle ID，保留现有跨平台测试版配置。原生应用未修改。
- macOS 图标全尺寸复用原生 Z 品牌图标；检查脚本与 Xcode 产品引用同步更名。
- 47 项测试、macOS 桌面集成测试及静态检查通过。

## Windows x64 免安装验证 · 2026-10-26

- GitHub Actions Windows Server 2022 构建机：Flutter 3.47.2、静态检查及 47 项测试通过。
- 修复测试样本的文件名平台差异：Windows 使用带空格文件名，macOS 保留换行文件名覆盖；其他忽略规则检查保留。
- Windows C++ 编译指定 UTF-8；产品名 zhixu.exe，使用 Z 品牌图标。
- Release 构建与打包后启动 5 秒检查通过，附带 app-local Visual C++ runtime、完整 Flutter 资源和双语使用说明。
- 构建记录：https://github.com/zoulirise-dev/zhixu/actions/runs/40292889727
- 产物：dist/windows-1.0.4/zhixu-1.0.4-windows-x64-portable.zip，SHA-256 f873a10e70c59490e0bf1479c34dfb4355c82d3ae34be8ab97b3991530249132。
- 已下载到本机并核对 ZIP CRC、SHA-256、PE 文件头、DLL 和 data 目录。尚待用户在 Windows 10/11 实机测试中文输入、显示和真实远程认证；云端启动检查不代表这些交互已全部验证。
- 仅推送独立构建分支 build/windows-portable-1.0.4，未合并 main、未发布 Release。当前本地工作区和暂存区保持原有状态。

## Path and cursor audit - 2026-10-27

- Canonical Git paths are separated from native disk paths; POSIX literal backslashes are preserved.
- Reviewed explorer/search/tab identity, status matching, historical images, history/stash restoration, ignore patterns and selected commits. Git object paths and checkout-index prefixes now use platform-aware conversion.
- Added nested Chinese/space/bracket path tests and POSIX backslash tests; verified explorer badges in Chinese/English and light/dark themes.
- Local static analysis, 63 tests and macOS desktop integration passed. macOS Release build and local signature validation passed.
- Windows build, tests, native caption hand cursors, hit targets, maximize/restore/minimize passed: https://github.com/zoulirise-dev/zhixu/actions/runs/40459896353
- ZIP: dist/windows-1.0.4-r8; SHA256 and ZIP integrity verified. macOS retains native buttons with pointing-hand cursor regions. Native macOS implementation unchanged; no DMG created. Real desktop DPI/input variations still require user testing.

## Final interaction review - 2026-10-27

- Windows caption controls use the default arrow (supersedes the earlier hand-cursor audit). Application file/folder actions retain pointing-hand cursors; text and resize areas retain their appropriate cursors.
- Fixed empty-baseline line decorations and syntax-language updates after file renames. Removed stale prototype/native-only instructions and updated English translations.
- Local analysis passed with no issues; 65 tests passed, one platform-specific test skipped; macOS desktop integration passed. Release rebuilt and ad-hoc signature verified after refreshing stale nested signatures from the incremental build.
- Remaining acceptance: real Windows IME, varied DPI/multi-monitor behavior and Snap Layout popup. Editor currently supports UTF-8 text up to 2 MB; Windows needs system Git and its test package is unsigned.
- Windows build, tests and native caption arrow/maximize/restore/minimize checks passed: https://github.com/zoulirise-dev/zhixu/actions/runs/40461560524 . ZIP downloaded to dist/windows-1.0.4-r9 and SHA256/CRC verified.

## 1.0.4 installation distribution - 2026-10-27

- Windows Inno Setup 6.7.1: bilingual installer generated, directory reuse/upgrade, running-app mutex protection, launch/uninstall and settings-preservation tests passed on Windows. Build: https://github.com/zoulirise-dev/zhixu/actions/runs/40475558438 . EXE is unsigned.
- macOS arm64: Developer ID hardened runtime signing, actual signed executable launch, application notarization and DMG notarization accepted; both tickets stapled and validated. Mounted DMG app signature and ticket verified; Applications symlink and 660x440 Finder layout checked.
- syspolicy_check distribution passed. spctl returned Notarized Developer ID but also reported the host security-disabled override; Apple acceptance and stapler/signature verification were checked independently.
- Final EXE/DMG/ZIP and individual SHA256 files are in dist/release-1.0.4. Native macOS source and 1.0.3 packages retained. No Release created and no main branch pushed.

## Installer-only distribution revision - 2026-10-27

- Removed bundled usage README and portable ZIP generation. Installer removes the obsolete README during upgrades. Desktop shortcut is selected by default; original license notices are retained.
- Windows validation passed: installed files exclude README; desktop shortcut exists and launches the installed app via ShellExecute; upgrade clears the old README, retains install location/settings; running-app protection and uninstall/shortcut removal passed.
- Build: https://github.com/zoulirise-dev/zhixu/actions/runs/40479348112 . The prior COM shortcut-property inspection returned no target in CI, so the regression check now exercises actual shortcut launch.
- Final release directory contains exactly five files: release notes, DMG/SHA256 and Setup EXE/SHA256. Existing notarized macOS DMG unchanged; old staging app and portable archives moved outside the release directory.
