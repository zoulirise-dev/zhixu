# 原生版逐项对照记录

2026-10-26。基准是 `../macos/Sources/Zhixu` 当前源码，不是最初四项原型需求。
“已实现”表示有对应路径，不表示所有平台、所有数据与像素均已验收。

| 原生模块 | 对照项目 | Flutter 对应与本轮结果 |
|---|---|---|
| WindowChrome.swift | 主窗口标题、系统按钮、拖动、双击缩放、边距 | Runner/MainFlutterWindow.swift；45 点原生标题区域，系统按钮保留，左/上边距自动按按钮高度计算；桌面测试验证 |
| AppDialogs.swift | 40 点标题、原生红色关闭按钮、固定头尾、中间滚动、渐隐边界 | ui/theme.dart、ui/native_close.dart；原生按钮经 MethodChannel 定位，独立滚动区域 |
| Theme.swift / ScrollStyle.swift | 明暗主题、按钮描边、悬停按下、手型、细滚动条 | ui/theme.dart；统一组件，字体与原生紧凑尺寸对齐 |
| App.swift | 三栏布局、紧凑搜索、分割线拖动与光标、底部版本 | main.dart；独立面板、圆角选项卡与主色短线；弹窗阻断底层鼠标 |
| App.swift | 空项目、项目列表、最近项目、打开/新建/克隆 | main.dart、workspace/dialogs.dart；欢迎页与最近项目持久化 |
| App.swift | macOS 菜单及编辑快捷键 | PlatformMenuBar；文件、编辑、Git、窗口菜单；弹窗打开时阻断工作台菜单操作 |
| Model.swift | 只刷新列表、保留勾选与编辑器状态 | refreshChangesOnly；独立刷新状态，无整页灰闪 |
| Model.swift / Git.swift | 勾选提交、仅提交所选、手动暂存、撤销 | main.dart、core/git_service.dart、core/workflows.dart；真实 Git 测试覆盖独立索引和未勾选暂存内容 |
| FileTree.swift / Explorer.swift | 隐藏/忽略文件、目录懒加载、搜索、刷新 | workspace/explorer.dart；忽略灰显；不递归阻塞展开 |
| Explorer.swift | 创建、剪切、复制、粘贴、副本、重命名、删除、访达、忽略 | workspace/explorer.dart；含多选快捷键及确认；危险路径/符号链接限制 |
| BranchPicker.swift | 本地/远程、远程 HEAD 排除、加载更多、右键菜单 | workspace/dialogs.dart；菜单定位、复用已有跟踪分支、当前分支禁删 |
| Model.swift | 新建/重命名未首次提交分支、覆盖修改提示 | core/workflows.dart；收起/携带/放弃选择与确认 |
| GitToolsUI.swift | 合并分支、分支对比、冲突继续/中止 | workspace/dialogs.dart；当前/传入/结果，逐块选择，完整二进制与删除版本选择 |
| App.swift / Git.swift | 历史分页、刷新、待推送、提交详情、撤销、反向提交 | main.dart、workspace/dialogs.dart；80 条分页，按上游判断待推送，后续页不会误认最新提交 |
| GitToolsUI.swift | 单文件历史、重命名前历史、恢复版本 | core/workflows.dart；真实仓库测试覆盖 |
| EditorDocument.swift | 普通/差异标签、临时预览、固定标签、脏状态、保存确认 | main.dart；单击预览替换、双击固定、编辑自动固定、保存前外部修改保护 |
| CodeEditor.swift | 行号、变更标记、缩略图、滚动与差异 | ui/code_editor.dart、ui/diff_view.dart；差异双行号、minimap 点击拖动、标签滚动位置保留 |
| Syntax.swift / Completion.swift | 多语言词法、片段、当前文档词、缩进、括号、中文组合输入 | core/syntax.dart、core/completion.dart；移植语言表与规则，补 HTML 内 JS/CSS/PHP；组合输入期间不替换文本 |
| MarkdownPreview.swift | Markdown 渲染、图片、外部与本地文件链接 | workspace/dialogs.dart；本地图片/文件限制在项目内；补文内锚点导航 |
| StashBrowser.swift | 任意备份、分支时间、备份/文件/编辑器、刷新、删除确认 | workspace/dialogs.dart；整条与单文件删除；删除不会改真实索引 |
| RestoreConflictDialog.swift / RestoreSplitEditor.swift | 内容相同跳过、不同选择、左右对照、同步滚动 | core/workflows.dart、ui/diff_view.dart；按行差异对齐，500 组随机重建测试；恢复前再次检查内容 |
| PushTargetDialog.swift / PullTargetDialog.swift | 单远程直连、多远程选择、地址和目标分支 | main.dart；提交并推送先选目标，取消不会产生提交；分叉提示引导合并 |
| RemoteFailureDialog.swift / BrowserLogin.swift | 系统认证、HTTPS 登录、GitHub 网页、错误分类、重试 | core/git_service.dart、workspace/dialogs.dart；模拟 helper/HTTP 验证；真实平台授权待验收 |
| SettingsView.swift | 系统默认语言、主题、Git 信息、项目署名、远程卡片、关于 | workspace/dialogs.dart；补自动补全开关、Git 执行/工具路径；地址与管理动作在所属卡片 |
| Localization.swift | 中英文与系统初始语言 | ui/localization.dart；macOS 读取系统首选语言，配置独立保存 |

## 验证证据

- `test/`：40 项自动测试，包含真实临时 Git 仓库、认证模拟、工作流、补全/差异。
- `integration_test/desktop_test.dart`：macOS 实际应用编辑、刷新、勾选提交、历史详情、设置、备份、目录选择与标题栏坐标。
- `build/prototype-screenshots/`：集成测试生成的界面图。Flutter 画布不包含 AppKit 叠加的真实标题/关闭按钮；不能据此判断系统按钮缺失。
- `VALIDATION.md`：平台、认证、输入法等验收边界。

## 尚不能标为完全一致

- Windows 实机编译与系统菜单/回收站/认证/中文输入尚未验收；不会以 macOS 结果代替。
- 真实 GitHub/Gitee 授权、系统拼音候选窗及第三方输入法、大文件性能仍需要实机验证。
- 当前语法高亮是词法规则，Flutter 与 AppKit 文本排版存在差异；没有宣称逐像素一致。

原生 macOS 工程保持不动。本构建不生成 DMG、不推送代码，不覆盖正式版偏好和安装包。
