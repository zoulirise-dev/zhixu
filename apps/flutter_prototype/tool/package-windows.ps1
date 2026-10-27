$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$version = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([^+\s]+)').Groups[1].Value
if (!$version) { throw 'Missing app version' }
$release = 'build/windows/x64/runner/Release'
if (!(Test-Path "$release/zhixu.exe")) { throw 'Build the Windows release first' }
$stageRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
$stage = Join-Path $stageRoot "Zhixu-$version-windows-x64"
New-Item -ItemType Directory -Force $stage | Out-Null
try {
  Copy-Item "$release/*" $stage -Recurse
  # Include the app-local Microsoft C++ runtime from the installed VS redistribution set.
  $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
  $vs = & $vswhere -latest -products '*' -property installationPath
  $crt = Get-ChildItem "$vs/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
  if (!$crt) { throw 'Visual C++ redistributable runtime not found' }
  Copy-Item "$($crt.FullName)/*.dll" $stage
  Copy-Item '../../LICENSE' "$stage/LICENSE.txt"
  Copy-Item '../../THIRD_PARTY_NOTICES.md' $stage
  $appProcess = Start-Process -FilePath (Join-Path $stage 'zhixu.exe') -WorkingDirectory $stage -PassThru
  try {
    Start-Sleep -Seconds 5
    if ($appProcess.HasExited) { throw "Application exited during startup: $($appProcess.ExitCode)" }
    & "$PSScriptRoot/check-window-chrome.ps1" -AppProcess $appProcess
  } finally {
    if (!$appProcess.HasExited) { Stop-Process -Id $appProcess.Id; $appProcess.WaitForExit() }
  }
  & "$PSScriptRoot/package-installer.ps1" -StageDir $stage -Version $version
} finally {
  Remove-Item $stageRoot -Recurse -Force -ErrorAction Continue
}
