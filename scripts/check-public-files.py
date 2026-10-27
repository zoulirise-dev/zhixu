#!/usr/bin/env python3
"""Read-only check of publishable files; never print matched secret values."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    "private key": rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----",
    "GitHub token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})\b",
    "GitLab token": rb"\bglpat-[A-Za-z0-9_-]{15,}\b",
    "AWS access key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "credential in URL": rb"https?://[^\s/@:]+:[^\s/@]+@",
    "personal absolute path": rb"(?:/Users/|/home/)[A-Za-z0-9_.-]+/",
    "Apple account/team record": rb"(?:APPLE_ID|TEAM_ID|NOTARY_PROFILE)\s*=\s*[^\s]+",
}
# Deliberate credential rejection fixtures; no live credentials.
URL_FIXTURE_FILES = {
    "apps/macos/Tests/AuthReliabilityIntegration.swift",
    "apps/macos/Tests/RemoteFailureIntegration.swift",
}
ALLOWED_URL_FIXTURES = {b"https" + b"://user:secret@gitee.com/a", b"https" + b"://user:secret@git.company.invalid/a"}


def main():
    findings = []
    with tempfile.TemporaryDirectory(prefix="zhixu-public-check-") as directory:
        subprocess.run(["git", "init", "-q", directory], check=True)
        command = ["git", "--git-dir=" + directory + "/.git", "--work-tree=" + str(ROOT)]
        env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        paths = subprocess.check_output(command + ["ls-files", "--others", "--exclude-standard", "-z"], cwd=ROOT, env=env).split(b"\0")
        # Verify important exclusions, even when these files do not exist locally.
        excluded = ["证书资料/release.env", "测试报告/report.txt", ".build/log", "dist/枝序.app/Contents/Info.plist", "apps/macos/.build/test", "apps/macos/.swiftpm/config", "apps/macos/Vendor/GitHubCLI/gh", "apps/windows/bin/app.dll", "apps/windows/obj/build.cache", ".env", "keys/signing.p12", "keys/private.pem", "apps/flutter_prototype/build/windows/app.exe", "apps/flutter_prototype/.dart_tool/package_config.json", "apps/flutter_prototype/windows/flutter/ephemeral/generated_config.cmake", "apps/flutter_prototype/macos/Flutter/ephemeral/Flutter-Generated.xcconfig"]
        for path in excluded:
            result = subprocess.run(command + ["check-ignore", "-q", "--", path], cwd=ROOT, env=env)
            if result.returncode != 0:
                findings.append((path, 0, "missing ignore rule"))
        files = [ROOT / os.fsdecode(path) for path in paths if path]
        for path in files:
            relative = path.relative_to(ROOT).as_posix()
            if path.is_symlink():
                findings.append((relative, 0, "review symlink before publication"))
                continue
            data = path.read_bytes()
            if b"\0" in data[:8192]:
                continue
            for kind, pattern in PATTERNS.items():
                for match in re.finditer(pattern, data):
                    line_start = data.rfind(b"\n", 0, match.start()) + 1
                    line_end = data.find(b"\n", match.end())
                    line = data[line_start:line_end if line_end >= 0 else len(data)]
                    if kind == "credential in URL" and relative in URL_FIXTURE_FILES and any(data[match.start():].startswith(fixture) and match.group() == fixture.split(b"@")[0] + b"@" for fixture in ALLOWED_URL_FIXTURES):
                        continue
                    findings.append((relative, data.count(b"\n", 0, match.start()) + 1, kind))
        print(f"Checked {len(files)} publishable files; {len(excluded)} exclusion checks.")
        for path, line, kind in findings:
            print(f"REVIEW {path}:{line} [{kind}]")
        if findings:
            raise SystemExit(1)
        print("PASS: no matches for configured sensitive-data patterns.")
        print("Scope: current publishable files only; no Git history audit or entropy guarantee.")


if __name__ == "__main__":
    main()
