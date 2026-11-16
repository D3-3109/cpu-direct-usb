#requires -Version 5.1
$ErrorActionPreference = 'Stop'
# 提前加载内置 Get-FileHash，避免模块自动加载覆盖后面的模拟函数。
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$root = Split-Path $PSScriptRoot -Parent
$launcherPath = Join-Path $root 'run.ps1'
. $launcherPath
$realStarter = ${function:Start-UsbDownloadedScript}
$script:passed = 0
function Assert-Launcher { param([bool]$Value, [string]$Message); if (-not $Value) { throw $Message } }
function Test-Launcher {
    param([string]$Name, [scriptblock]$Test)
    & $Test
    $script:passed++
    Write-Host "[通过] $Name"
}
$script:created = @()
$script:received = @()
$script:started = @()
$script:mode = ''
function New-Item {
    [CmdletBinding()]param($ItemType, $Path)
    $script:created += $Path
}
function Receive-UsbLauncherFile {
    [CmdletBinding()]param($Uri, $Destination)
    $script:received += [pscustomobject]@{ Uri = $Uri; Destination = $Destination }
    if ($script:mode -eq 'download-failure' -and $script:received.Count -eq 2) { Write-Error '模拟网络失败' }
}
function Get-FileHash {
    [CmdletBinding()]param($LiteralPath, $Algorithm)
    $relative = if ($LiteralPath -match '[\\/]lib[\\/]([^\\/]+)$') { 'lib/' + $Matches[1] } else { 'cpudirect.ps1' }
    $value = (Get-UsbLauncherManifest).Files[$relative]
    if ($script:mode -eq 'hash-failure' -and $relative -eq 'lib/Settings.ps1') { $value = 'invalid' }
    return [pscustomobject]@{ Hash = $value }
}
function Start-UsbDownloadedScript {
    [CmdletBinding()]param($ScriptPath, [switch]$Configure)
    $script:started += [pscustomobject]@{ ScriptPath = $ScriptPath; Configure = $Configure.IsPresent; DownloadCount = $script:received.Count }
    if ($script:mode -eq 'child-failure') { throw '模拟分析程序退出失败' }
}
function Write-Host { param($Object, $ForegroundColor); Microsoft.PowerShell.Utility\Write-Host $Object -ForegroundColor $(if ($ForegroundColor) { $ForegroundColor } else { 'Gray' }) }
function Reset-LauncherMock {
    $script:created = @(); $script:received = @(); $script:started = @(); $script:mode = ''
}

Test-Launcher '启动器引用的固定版本与四个运行文件一致' {
    $manifest = Get-UsbLauncherManifest
    Assert-Launcher ($manifest.Commit -match '^[0-9a-f]{40}$') '不是完整提交 SHA'
    Assert-Launcher ($manifest.Files.Count -eq 4) '运行文件数量错误'
    foreach ($relative in $manifest.Files.Keys) {
        # Git 检出可能把 LF 转为 CRLF；固定版本哈希以仓库原始 LF 字节为准。
        $text = [IO.File]::ReadAllText((Join-Path $root $relative), [Text.Encoding]::UTF8).Replace("`r`n", "`n")
        $bytes = [Text.Encoding]::UTF8.GetPreamble() + [Text.Encoding]::UTF8.GetBytes($text)
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
        finally { $algorithm.Dispose() }
        Assert-Launcher ($hash -eq $manifest.Files[$relative]) "固定版本校验值需更新：$relative"
    }
}
Test-Launcher '全部下载校验后才启动，默认仅扫描且不提权' {
    Reset-LauncherMock
    Invoke-UsbLauncher
    Assert-Launcher ($script:started.Count -eq 1 -and $script:started[0].DownloadCount -eq 4) '未完成全部下载即启动'
    Assert-Launcher (-not $script:started[0].Configure) '默认不得进入配置模式'
    foreach ($file in $script:received) {
        Assert-Launcher ($file.Uri -match '^https://raw\.githubusercontent\.com/D3-3109/cpu-direct-usb/[0-9a-f]{40}/') '下载地址未固定到目标仓库提交'
    }
}
Test-Launcher '下载失败不执行任何下载文件' {
    Reset-LauncherMock; $script:mode = 'download-failure'
    $caught = $false
    try { Invoke-UsbLauncher } catch { $caught = $_.Exception.Message -match '模拟网络失败' }
    Assert-Launcher ($caught -and $script:started.Count -eq 0) '下载失败仍启动或丢失错误'
}
Test-Launcher '哈希不匹配不执行任何下载文件' {
    Reset-LauncherMock; $script:mode = 'hash-failure'
    $caught = $false
    try { Invoke-UsbLauncher } catch { $caught = $_.Exception.Message -match '校验失败' }
    Assert-Launcher ($caught -and $script:started.Count -eq 0) '校验失败仍启动'
}
Test-Launcher '重复运行使用独立目录' {
    Reset-LauncherMock
    Invoke-UsbLauncher
    $first = $script:created[0]
    Invoke-UsbLauncher
    Assert-Launcher ($script:created[2] -ne $first) '目录复用可能混入旧文件'
}
Test-Launcher '仅显式 Configure 时传递配置模式' {
    Reset-LauncherMock
    Invoke-UsbLauncher -Configure
    Assert-Launcher $script:started[0].Configure '未传递显式配置参数'
}
Test-Launcher '失败后恢复调用会话的 TLS 设置' {
    Reset-LauncherMock; $script:mode = 'child-failure'
    $before = [Net.ServicePointManager]::SecurityProtocol
    $caught = $false
    try { Invoke-UsbLauncher } catch { $caught = $_.Exception.Message -match '模拟分析程序退出失败' }
    Assert-Launcher ($caught -and [Net.ServicePointManager]::SecurityProtocol -eq $before) '未传递错误或未恢复TLS设置'
}
Test-Launcher 'README 的管道执行方式能触发启动器且不依赖脚本目录' {
    $source = [IO.File]::ReadAllText($launcherPath, [Text.Encoding]::UTF8)
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
    $entry = $ast.EndBlock.Statements[-1].Extent.Text
    $script:invoked = 0
    function Invoke-UsbLauncher { param([switch]$Configure); $script:invoked++ }
    Invoke-Expression $entry
    Assert-Launcher ($script:invoked -eq 1) 'iex 未执行入口'
    Assert-Launcher ($source -notmatch '\$PSScriptRoot') '远程入口依赖未定义脚本目录'
}
Test-Launcher '子进程仅使用进程级执行策略且检查失败码' {
    $text = $realStarter.ToString()
    Assert-Launcher ($text -match "'-ExecutionPolicy', 'Bypass'" -and $text -match "'-NoProfile'") '子进程参数不完整'
    Assert-Launcher ($text -match '\$LASTEXITCODE' -and $text -match 'throw') '子进程失败未检查'
    Assert-Launcher ($text -notmatch 'RunAs|Set-ExecutionPolicy|Invoke-Expression') '子进程不应提权或更改持久策略'
}
Test-Launcher '远程入口为纯 ASCII，中文提示运行时解码' {
    $bytes = [IO.File]::ReadAllBytes($launcherPath)
    Assert-Launcher (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) '入口包含可能误解码的字节'
    Assert-Launcher ((Get-UsbLauncherText 'Verified') -eq '全部运行文件校验通过。') '中文提示解码错误'
}
Test-Launcher '子进程能处理含空格中文路径及显式配置参数' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('USB 启动测试 ' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($directory)
    $scriptPath = Join-Path $directory '模拟程序.ps1'
    [IO.File]::WriteAllText($scriptPath, 'param([switch]$Configure); if (-not $Configure) { exit 8 }; exit 0', [Text.UTF8Encoding]::new($true))
    try { & $realStarter -ScriptPath $scriptPath -Configure }
    finally { [IO.File]::Delete($scriptPath); [IO.Directory]::Delete($directory) }
}
Test-Launcher '真实子进程非零退出传回失败' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('UsbLauncherTest-' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($directory)
    $scriptPath = Join-Path $directory 'failure.ps1'
    [IO.File]::WriteAllText($scriptPath, 'exit 7', [Text.UTF8Encoding]::new($true))
    $caught = $false
    try { & $realStarter -ScriptPath $scriptPath } catch { $caught = $_.Exception.Message -match '退出码：7' }
    finally { [IO.File]::Delete($scriptPath); [IO.Directory]::Delete($directory) }
    Assert-Launcher $caught '没有处理真实子进程失败'
}
Write-Host "启动器测试：$script:passed 项通过；未联网、未启动真实扫描、未写系统设置。"
