#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$syntaxErrors = @()
$scriptFiles = @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/]dist[\\/]' })
foreach ($file in $scriptFiles) {
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($errorRecord in $errors) { $syntaxErrors += "$($file.Name):$($errorRecord.Extent.StartLineNumber) $($errorRecord.Message)" }
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        $syntaxErrors += "$($file.Name)：中文 PowerShell 脚本必须使用 UTF-8 BOM，兼容 Windows PowerShell 5.1。"
    }
}
if ($syntaxErrors.Count -gt 0) { throw ($syntaxErrors -join "`n") }
Write-Host "[通过] $($scriptFiles.Count) 个 PowerShell 文件的语法与中文编码检查"

$engine = (Get-Process -Id $PID).Path
foreach ($name in @('Topology.Tests.ps1', 'Settings.Tests.ps1', 'EntryPoint.Tests.ps1')) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "缺少测试：$name" }
    & $engine -NoProfile -NonInteractive -File $path
    if ($LASTEXITCODE -ne 0) { throw "$name 失败，退出码：$LASTEXITCODE" }
}
Write-Host '全部离线测试通过；未枚举真实设备，未修改本机注册表或电源设置。'
