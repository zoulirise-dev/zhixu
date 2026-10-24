# GitHub browser authentication

The app bundles the official arm64 GitHub CLI executable (MIT, see LICENSE and VERSION).
Upstream release: https://github.com/cli/cli/releases/tag/v2.103.0
The downloaded archive was verified against the upstream release checksum before extraction.

Zhixu runs `gh auth login --web --hostname github.com --git-protocol https --skip-ssh-key --insecure-storage` with a private GH_CONFIG_DIR (0700), an isolated Git global config, no inherited GH/GITHUB credentials, and noninteractive stdin. It shows the official device code, opens GitHub's fixed authorization URL, and waits for authorization. This is GitHub CLI's OAuth application, not a separately registered Zhixu OAuth app.

The temporary CLI credential file is used only to transfer the resulting credential to Zhixu's macOS Keychain item. The whole temporary directory is removed on success, failure or cancellation. Existing user gh configuration is not changed. After a successful Git operation, credentials are approved through the configured Git credential helper so other clients using that helper can reuse them. An abrupt process/OS crash may leave the protected temporary directory until macOS removes it; no credential file is saved in the application bundle or project.

GitHub credentials apply to HTTPS remotes. SSH remotes continue to use SSH. Other HTTPS hosting platforms use system Git authentication and an on-demand username/password prompt; they are not advertised as browser sign-in integrations.

The executable is excluded from the source repository. Run `bash scripts/bootstrap-gh.sh` from the repository root to download the pinned archive and verify its checksum.
