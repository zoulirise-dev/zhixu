# 1.0.4 提交与发布准备

## 当前结论

双端 1.0.4 安装文件集中在 `dist/release-1.0.4/`。macOS DMG 已完成签名公证；Windows EXE 支持安装升级但尚未代码签名。原生 macOS 1.0.3 保留在历史发行版。

## 提交同一份源码到两个平台

1. 在枝序打开本项目，刷新变更列表，检查本项目提交署名。
2. 勾选本次源码与文档修改，包括 `.github/workflows` 和 `apps/flutter_prototype`。不勾选证书、测试报告、构建目录和安装包。
3. 提交说明建议：`feat: add Flutter desktop 1.0.4 for macOS and Windows`。只提交一次。
4. 推送到 GitHub 的 `main`，再选择 Gitee，推送同一个本地 `main`。无需为 Gitee 再提交一次，也不更换署名。
5. 如果某端已有其他更新，先获取并检查差异；不要使用强制推送覆盖。
6. 分别打开两个仓库确认最新提交相同，README 图片和文档能正常打开。

独立的 `build/windows-portable-1.0.4` 仅用于云端验证，本地源码已包含相应改动；不要为了发布而盲目合并构建分支，也不要改写既有提交历史。

## 创建发行版

- 标签：`v1.0.4`，目标选择包含本次源码的提交；两个平台使用相同提交与标签。
- 标题：`枝序 v1.0.4 · macOS / Windows`。
- 两个平台使用相同发布标题和说明；如希望先小范围试用，可在 GitHub 勾选 Pre-release。
- 正文：复制同目录 `v1.0.4.md`；富文本编辑器可粘贴其渲染后的正文。
- 附件：上传 `dist/release-1.0.4/` 中的 DMG、EXE 及各自的 `.sha256` 文件，共四个附件；发布说明 `发布说明.md` 用作发行版正文。两个平台使用相同附件。
- 不上传 `枝序.app` 目录、证书或私钥；源码提交不包含 `dist/`。
- 上传后使用未登录浏览器分别测试附件下载，再删掉 README 中“维护者发布并上传附件后直链生效”的说明。

Windows 对应构建记录：https://github.com/zoulirise-dev/zhixu/actions/runs/40479348112 。后续如修改应用源码，必须重新构建，不能继续使用旧附件。macOS 本机发布脚本为 `apps/flutter_prototype/tool/package-macos.sh`，通过环境变量读取签名身份和公证钥匙串配置。

## 发布前检查

- `python3 scripts/check-public-files.py`：检查当前可发布文件中的常见敏感信息模式及忽略规则；不等同于完整 Git 历史或所有未知密钥审计。
- 确认 `pubspec.lock` 提交，`build/`、`.dart_tool/`、`dist/`、证书资料和本机凭据被忽略。
- 回归记录见 `apps/flutter_prototype/VALIDATION.md`。
- 建议最后在 Windows 实机检查中文输入、文件保存、窗口缩放、克隆与推送；先使用测试仓库。
- 本次整理未自动提交、推送 main、创建标签或创建 Release。
