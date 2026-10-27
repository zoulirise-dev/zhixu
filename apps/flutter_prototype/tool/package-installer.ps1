param([Parameter(Mandatory=$true)][string]$StageDir, [Parameter(Mandatory=$true)][string]$Version)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class InstallerPath {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  private static extern uint GetLongPathName(string path, StringBuilder output, uint length);
  public static string Canonical(string path) {
    var output = new StringBuilder(32768);
    var n = GetLongPathName(System.IO.Path.GetFullPath(path), output, (uint)output.Capacity);
    if (n == 0 || n >= output.Capacity) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    return output.ToString();
  }
}
'@
$compiler = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
if (!(Test-Path $compiler)) { throw 'Inno Setup 6 is required' }
$out = (New-Item -ItemType Directory -Force 'build/installer').FullName
& $compiler "/DAppVersion=$Version" "/DStageDir=$StageDir" "/DOutputDir=$out" "$PSScriptRoot/installer/zhixu.iss"
if ($LASTEXITCODE) { throw 'Installer compilation failed' }
$setup = Join-Path $out "Zhixu-$Version-Windows-x64-Setup.exe"
$testDir = Join-Path $env:TEMP ('Zhixu-install-' + [guid]::NewGuid().ToString())
$marker = Join-Path $env:APPDATA ('ZhixuFlutter/installer-probe-' + [guid]::NewGuid().ToString() + '.txt')
$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\app.zhixu.desktop.windows_is1'
function Run-Setup([string]$extra) {
  $proc = Start-Process $setup -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- $extra" -Wait -PassThru
  return $proc.ExitCode
}
try {
  if (Test-Path $registry) { throw 'Installer test requires an isolated user profile' }
  if ((Run-Setup "/DIR=`"$testDir`" /LANG=chinesesimplified") -ne 0) { throw 'First install failed' }
  if (!(Test-Path "$testDir/zhixu.exe")) { throw 'Installed executable missing' }
  if (Test-Path "$testDir/使用说明-README.txt") { throw 'Removed readme is still included' }
  $shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) '枝序.lnk'
  if (!(Test-Path $shortcut)) { throw 'Desktop shortcut was not created by default' }
  # Simulate the obsolete readme from the previous installer before upgrading.
  'old readme' | Set-Content "$testDir/使用说明-README.txt"
  New-Item -ItemType Directory -Force (Split-Path $marker) | Out-Null
  'keep settings' | Set-Content $marker
  $before = (Get-ItemProperty $registry).InstallLocation
  # No /DIR on the upgrade: the registered location must be reused.
  if ((Run-Setup '/LANG=english') -ne 0) { throw 'Upgrade failed' }
  if ((Get-ItemProperty $registry).InstallLocation -ne $before) { throw 'Install location changed' }
  if ((Get-Content $marker) -ne 'keep settings') { throw 'Upgrade removed user data' }
  if (Test-Path "$testDir/使用说明-README.txt") { throw 'Upgrade did not remove obsolete readme' }
  # Exercise the actual desktop link using Windows ShellExecute.
  Start-Process -FilePath $shortcut
  Start-Sleep -Seconds 5
  $app = Get-Process zhixu -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and [InstallerPath]::Canonical($_.Path) -eq [InstallerPath]::Canonical("$testDir/zhixu.exe")
  } | Select-Object -First 1
  if (!$app) { throw 'Desktop shortcut did not launch the installed application' }
  try {
    if ($app.HasExited) { throw 'Installed app failed to start' }
    if ((Run-Setup '') -eq 0) { throw 'Installer overwrote a running app' }
  } finally {
    if (!$app.HasExited) { Stop-Process -Id $app.Id; $app.WaitForExit() }
  }
  $uninstall = Start-Process "$testDir/unins000.exe" -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
  if ($uninstall.ExitCode -ne 0) { throw 'Uninstall failed' }
  if (Test-Path "$testDir/zhixu.exe") { throw 'Uninstall left executable behind' }
  if ((Get-Content $marker) -ne 'keep settings') { throw 'Uninstall removed user data' }
  if (Test-Path $shortcut) { throw 'Uninstall left the desktop shortcut' }
  Write-Host 'PASS installer: default desktop shortcut, removed readme,  initial install, directory reuse, upgrade, running-app protection, launch, uninstall and settings preservation'
} finally {
  Remove-Item $marker -Force -ErrorAction SilentlyContinue
}
"$((Get-FileHash $setup -Algorithm SHA256).Hash.ToLower())  $(Split-Path $setup -Leaf)" | Set-Content "$setup.sha256" -Encoding ascii
