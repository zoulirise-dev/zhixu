# 第三方组件

| 组件 | 用途 | 版本与许可 | 位置 |
| --- | --- | --- | --- |
| GitHub CLI | GitHub 网页授权 | 2.103.0，MIT | apps/macos/Vendor/GitHubCLI/LICENSE |
| Git | 仓库操作 | 使用用户电脑安装的版本；当前不随应用分发 | 系统环境 |

GitHub CLI 上游：https://github.com/cli/cli/releases/tag/v2.103.0 。下载脚本校验固定归档 SHA-256；可执行文件不提交到源码仓库。生成 macOS 应用时会把 CLI 的许可证及版本信息一起复制到应用资源目录。

枝序的 MIT 许可证不替代第三方许可证。新增依赖或更换打包方式时，应更新本文件及随包许可材料。
