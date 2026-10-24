# 测试说明

在 Apple Silicon macOS 上准备 Swift 6 工具链和 Git，从仓库根目录运行脚本。每个脚本编译独立测试入口，日志与二进制位于 apps/macos/.build。根目录 scripts 是兼容入口，不存放平台实现。

## 常用验证

```sh
bash scripts/test.sh
bash scripts/test-open-folder.sh
bash scripts/test-selected-commit.sh
bash scripts/test-remote-checkout.sh
bash scripts/test-git-workflow.sh
bash scripts/test-stash-restore.sh
bash scripts/test-stash-list.sh
bash scripts/test-editor.sh
bash scripts/test-completion.sh
bash scripts/test-split-comparison.sh
bash scripts/test-responsiveness.sh
bash scripts/test-settings-remote.sh
```

其他脚本分别验证分支管理、丢弃修改、文件操作、本地历史、远程错误、多远程选择、滚动条、对话框和本地化。运行相关脚本即可，不需要为每次文档修改重复全部测试。

## 环境与隔离

Git 测试使用临时仓库；不能替换为真实业务路径。部分 AppKit 测试需要桌面会话，会打开测试窗口。认证测试 test-auth-reliability.sh 使用模拟传输、临时凭据助手和专用测试钥匙串条目；完成后清理。没有钥匙串访问权限的沙盒中不能完整验证这组测试。

测试不使用真实远程密码，也不能代替服务端实际 OAuth 授权、企业认证策略或其他电脑首次安装验证。性能数字只代表测试设备与数据规模；主线程心跳间隔不是界面帧率。

## 公开前检查

```sh
python3 scripts/check-public-files.py
```

检查脚本按根目录 .gitignore 计算待公开文件，使用临时 Git 索引验证忽略效果，不初始化当前项目。它仅输出可疑项的文件名、行号和类别，不输出疑似秘密原文。规则扫描不等同于完整安全审计；提交或发布前仍需检查 diff 和历史。
