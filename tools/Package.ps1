#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root 'dist' }
$files = @('cpudirect.ps1', 'lib/Topology.ps1', 'lib/Settings.ps1', 'lib/Display.ps1',
    'README.md', 'LICENSE', 'CHANGELOG.md', 'VALIDATION.md', 'tests/Run.Tests.ps1', 'tests/Topology.Tests.ps1',
    'tests/Settings.Tests.ps1', 'tests/EntryPoint.Tests.ps1', 'tools/Package.ps1', '.gitignore')
$hashes = foreach ($relative in $files) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "缺少发布文件：$relative" }
    '{0}  {1}' -f (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant(), $relative
}
if (Test-Path -LiteralPath $OutputDirectory) { throw "输出目录已存在，请使用新的目录：$OutputDirectory" }
New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop | Out-Null
$stage = Join-Path $OutputDirectory 'cpu-direct-usb-zh'
New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
foreach ($relative in $files) {
    $destination = Join-Path $stage $relative
    $parent = Split-Path $destination -Parent
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }
    Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $destination -ErrorAction Stop
}
$hashes | Set-Content -LiteralPath (Join-Path $stage 'checksums.txt') -Encoding ASCII -ErrorAction Stop
$archive = Join-Path $OutputDirectory 'cpu-direct-usb-zh.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $archive, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Copy-Item -LiteralPath (Join-Path $stage 'checksums.txt') -Destination (Join-Path $OutputDirectory 'checksums.txt') -ErrorAction Stop
'{0}  cpu-direct-usb-zh.zip' -f (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() |
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'archive-sha256.txt') -Encoding ASCII -ErrorAction Stop
Write-Host "已生成完整中文发布包：$archive"
