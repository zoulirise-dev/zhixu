# 枝序 · 让 Git 简单一点

枝序（Zhixu）是面向日常开发的 Git 桌面工具，将项目、分支、提交、文件编辑和冲突处理集中在一个工作台。默认勾选文件直接提交，需要时再使用手动暂存。

![枝序工作台概览：项目、文件目录与代码编辑集中在一个窗口](assets/screenshots/editor.png)

## 下载

**当前版本 · v1.0.4**。选择系统，再选择访问方便的下载源。维护者发布 `v1.0.4` 并上传附件后，以下直链生效。

| 系统 | Gitee 下载 | GitHub 下载 |
| --- | --- | --- |
| **macOS · M 系列芯片** | [DMG 安装包](https://gitee.com/zoulirise/zhixu/releases/download/v1.0.4/Zhixu-1.0.4-macOS-arm64.dmg) | [DMG 安装包](https://github.com/zoulirise-dev/zhixu/releases/download/v1.0.4/Zhixu-1.0.4-macOS-arm64.dmg) |
| **Windows · x64（推荐安装版）** | [EXE 安装程序](https://gitee.com/zoulirise/zhixu/releases/download/v1.0.4/Zhixu-1.0.4-Windows-x64-Setup.exe) | [EXE 安装程序](https://github.com/zoulirise-dev/zhixu/releases/download/v1.0.4/Zhixu-1.0.4-Windows-x64-Setup.exe) |

- **macOS**：macOS 14+、Apple Silicon（M 系列）。打开 DMG，将枝序拖入 Applications。应用与 DMG 均已使用 Developer ID 签名并通过 Apple 公证；暂不提供 Intel 安装包。
- **Windows**：Windows 10/11 x64，需安装 Git for Windows。EXE 支持记住安装位置、覆盖升级与卸载。无需安装 Flutter 或 Visual Studio。Windows 包暂未做代码签名，可能显示发布者未知。
- **认证**：优先使用电脑已有 Git 认证；Windows 的 GitHub 网页登录需要 GitHub CLI。
- **升级**：升级前保存编辑并退出枝序。1.0.4 使用新的 Flutter 实现，从原生 macOS 1.0.3 升级后需重新添加项目；仓库内容和系统 Git 配置不会被清除。

更新说明：[v1.0.4](docs/releases/v1.0.4.md)。历史版本：[Gitee 发行版](https://gitee.com/zoulirise/zhixu/releases) · [GitHub 发行版](https://github.com/zoulirise-dev/zhixu/releases)。原生 macOS 1.0.3 仍可从历史版本下载。

## 少记命令，把注意力放在代码上

### 改了很多文件，这次只想提交其中几个？

勾选需要提交的文件，直接查看差异并提交；未勾选的修改留在工作区。默认不用先理解暂存区，需要时再开启手动暂存。

![勾选文件提交，并逐行查看本次修改](assets/screenshots/changes.png)

### 改到一半要切换分支，担心覆盖当前修改？

检测到切换会覆盖修改时，明确选择“临时收起修改并切换”“携带修改切换”或“放弃修改并切换”。临时收起的修改之后可从备份列表选择恢复。

![切换分支前选择如何处理尚未提交的修改](assets/screenshots/branch-protection.png)

### 同一套代码放在 GitHub 和 Gitee，不想来回配置？

在项目设置里管理多个远程地址，推送或拉取时选择目标。“本项目提交署名”独立设置，默认读取电脑 Git 配置；同一条提交推送到不同平台时保持相同署名。登录认证优先复用电脑现有配置。



以上均为演示项目的真实界面截图。

## 平台状态

| 平台 | 当前实现 | 安装形式 |
| --- | --- | --- |
| macOS Apple Silicon | Flutter 1.0.4 | 签名公证 DMG |
| Windows x64 | Flutter 1.0.4 | EXE 安装版 |
| macOS 原生版 | SwiftUI/AppKit 1.0.3，保留源码与历史发行版 | 历史 DMG |

macOS / Windows 1.0.4 共用 Flutter 工程，不依赖 Node 或 Electron。跨平台源码位于 `apps/flutter_prototype`，目录名暂保留以避免打断现有构建路径。

## 功能

- 创建、打开和克隆项目；优先使用电脑已有 Git 认证。
- 仅提交勾选文件；支持高级手动暂存模式、提交并推送。
- 分支创建、切换、重命名、删除、合并和对比。
- 切换覆盖修改时，选择临时收起、携带或放弃修改。
- 管理多个远程仓库，独立设置本项目提交署名；选择推送/拉取目标；显示待推送、待拉取和分叉状态。
- 临时备份列表、差异查看、指定恢复、单文件或整条备份删除。
- 提交详情、单文件历史、恢复旧版本和反向提交。
- 冲突分块处理、标记解决、继续或中止操作。
- 文件管理、忽略规则、文本编辑、语法高亮、基础补全与 Markdown 预览。
- 中文/英文、浅色/深色与跟随系统主题。

文本编辑支持 UTF-8 文件（上限 2 MB）；补全包含括号、缩进、关键词、文件内单词和基础片段，不包含语言服务器或 AI 补全。二进制文件可参与 Git 操作，不提供文本编辑。

## Flutter 双端版本（1.0.4）

[Flutter 桌面版](apps/flutter_prototype/README.md) 统一实现双端工作台、分支/历史/备份/冲突、编辑器与系统 Git 认证，详见[对照记录](apps/flutter_prototype/PARITY.md)。双端构建和自动检查已通过；不同输入法、多屏环境与认证配置的体验欢迎反馈。

## 从源码构建

当前 1.0.4 请按 [Flutter 构建说明](apps/flutter_prototype/README.md) 操作；Windows 安装脚本、macOS 签名公证脚本均在该工程 `tool/` 下，签名凭据不包含在源码中。

### 保留的原生 macOS 1.0.3

需要 Apple Silicon Mac、Xcode 或兼容的 Swift 6 工具链，以及 Git。使用终端在仓库根目录运行：

```sh
# 获取固定版本的 GitHub CLI，并验证归档校验和
bash scripts/bootstrap-gh.sh
# 构建本地应用；不执行公证，也不生成 DMG
bash scripts/build.sh
```

输出：`dist/枝序.app`。未配置签名身份时使用本地临时签名，不需要维护者的证书。仅编译 Swift 源码可运行 `swift build --package-path apps/macos`。

详细说明：[macOS 开发](apps/macos/README.md)、[使用指南](docs/usage.md)、[贡献指南](CONTRIBUTING.md)。

## 仓库结构

```text
apps/macos/     macOS 源码、测试、平台资源和脚本
apps/flutter_prototype/  Flutter 双端原型、测试与平台工程
apps/windows/   Windows 状态与验证入口
assets/brand/  共用品牌图片
docs/          使用、架构和发布说明
scripts/       根目录构建和测试入口
```

两端按目录划分，采用同一主分支维护。[GitHub](https://github.com/zoulirise-dev/zhixu) 是主仓库，[Gitee](https://gitee.com/zoulirise/zhixu) 同步提供源码与发行版。平台进度和版本可以独立推进，详见 [架构与平台规划](docs/architecture.md)。

## 测试

```sh
bash scripts/test.sh
bash scripts/test-selected-commit.sh
bash scripts/test-remote-checkout.sh
bash scripts/test-completion.sh
bash scripts/test-responsiveness.sh
```

测试使用临时仓库。部分 AppKit 测试会短暂打开测试窗口；认证测试涉及临时钥匙串条目，运行前请阅读 [测试说明](docs/testing.md)。

## 许可与联系

源码采用 [MIT License](LICENSE)，作者 **zoulirise**，联系邮箱 **zoulirise@gmail.com**。第三方组件遵守各自许可证，见 [第三方说明](THIRD_PARTY_NOTICES.md)。安全问题请参考 [安全报告说明](SECURITY.md)。
