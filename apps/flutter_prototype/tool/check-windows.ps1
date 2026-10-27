$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
function Invoke-Checked {
  param([string]$Exe, [string[]]$Arguments)
  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Exe failed ($LASTEXITCODE)" }
}
Invoke-Checked -Exe flutter -Arguments @('doctor', '-v')
Invoke-Checked -Exe git -Arguments @('--version')
Invoke-Checked -Exe flutter -Arguments @('pub', 'get')
Invoke-Checked -Exe flutter -Arguments @('analyze')
Invoke-Checked -Exe flutter -Arguments @('test')
Invoke-Checked -Exe flutter -Arguments @('build', 'windows', '--release')
Write-Host 'Application built; preparing the Windows installer.'

& (Join-Path $PSScriptRoot "package-windows.ps1")
