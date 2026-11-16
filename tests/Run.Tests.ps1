#requires -Version 5.1
# 独立离线运行：powershell.exe -NoProfile -NonInteractive -File .\tests\Run.Tests.ps1
$ErrorActionPreference = 'Stop'
# 先加载内置模块，避免懒加载覆盖下面的同名 mock；不加载 PnP 模块。
Import-Module Microsoft.PowerShell.Utility, Microsoft.PowerShell.Management -ErrorAction Stop
$PSModuleAutoLoadingPreference = 'None'
$mainPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'cpudirect.ps1'
$source = [IO.File]::ReadAllText($mainPath, [Text.Encoding]::UTF8)
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
# iex 中的 exit 会结束测试调用方，运行前先拒绝它。
if ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.ExitStatementAst] }, $true).Count) {
    throw '主脚本包含 exit，会影响调用方。'
}
foreach ($path in @($PSCommandPath, $mainPath)) {
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw "缺少 UTF-8 BOM：$path" }
}

$cpu = 'PCI\VEN_1022&DEV_15B6\CPU'; $rootHub = 'USB\ROOT_HUB30\CPU'
$mouse = 'USB\VID_1234&PID_5678\A'; $other = 'USB\VID_1234&PID_5678\B'
$script:passed = 0; $script:failed = 0
function Assert { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message } }
function Node {
    param($Id, $Parent = '', $Compatible = @(), $Service = '', $Name = '中文设备', $Class = 'USB')
    [pscustomobject]@{ InstanceId = $Id; ParentId = $Parent; CompatibleIds = $Compatible; Service = $Service
        FriendlyName = $Name; Class = $Class; Status = 'OK'; BusDescription = '' }
}
function Reset-Mock {
    # global 仅供同进程的本地脚本与 iex 共用；所有系统调用均在下面拦截。
    $global:UsbTest = @{
        Nodes = @{}; Lines = [Collections.Generic.List[string]]::new()
        Scans = 0; Properties = 0; RegistryReads = 0; RegistryWrites = 0; PowerWrites = 0; Queries = 0
        RegistryFail = $false; PowerFailure = ''; QueryExit = 0; Prompts = 0; Choice = ''
        Commands = [Collections.Generic.List[string]]::new(); LastWrite = $null
        Query = "Possible Setting Index: 000`nPossible Setting Index: 001`nCurrent AC Power Setting Index: 0x00000000`nCurrent DC Power Setting Index: 0x00000001"
    }
    $global:UsbTest.Nodes[$cpu] = Node $cpu '' @('PCI\CC_0C0330') '' '中文主控制器'
    $global:UsbTest.Nodes[$rootHub] = Node $rootHub $cpu @('USB\Class_09') 'USBHUB3' '根集线器'
    $global:UsbTest.Nodes[$mouse] = Node $mouse $rootHub @('USB\Class_03') 'HidUsb' '模拟鼠标'
}
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:passed++; Microsoft.PowerShell.Utility\Write-Host "[通过] $Name" }
    catch { $script:failed++; Microsoft.PowerShell.Utility\Write-Host "[失败] $Name：$($_.Exception.Message)`n$($_.ScriptStackTrace)" }
    finally { Reset-Mock }
}
function Assert-NoWrites {
    Assert (($global:UsbTest.RegistryWrites + $global:UsbTest.PowerWrites) -eq 0) '不应修改注册表或电源设置'
}

# 保留生产 Get-PnpNodes，模拟最底层命令，确保 & 和 iex 也不会扫描本机。
function Get-PnpDevice {
    [CmdletBinding()]param([switch]$PresentOnly)
    Assert $PresentOnly.IsPresent '扫描必须限定当前设备'
    $global:UsbTest.Scans++
    $global:UsbTest.Nodes.Values
}
function Get-PnpDeviceProperty {
    [CmdletBinding()]param($InstanceId, $KeyName)
    Assert ($global:UsbTest.Nodes.ContainsKey($InstanceId)) '属性查询必须属于模拟设备'
    $global:UsbTest.Properties++
    $node = $global:UsbTest.Nodes[$InstanceId]
    foreach ($pair in @{ Parent = 'ParentId'; Service = 'Service'; CompatibleIds = 'CompatibleIds'; BusReportedDeviceDesc = 'BusDescription' }.GetEnumerator()) {
        $key = 'DEVPKEY_Device_' + $pair.Key
        if ($KeyName -contains $key) { [pscustomobject]@{ KeyName = $key; Data = $node.($pair.Value) } }
    }
}
function Get-ItemProperty {
    [CmdletBinding()]param($LiteralPath, $Name)
    $global:UsbTest.RegistryReads++
    [pscustomobject]@{ MSISupported = [int]0; SelectiveSuspendEnabled = [int]1 }
}
function Set-ItemProperty {
    [CmdletBinding()]param($LiteralPath, $Name, $Value, $Type, [switch]$Force)
    $global:UsbTest.RegistryWrites++
    $global:UsbTest.LastWrite = @{ Path = $LiteralPath; Name = $Name; Value = $Value; Type = $Type }
    if ($global:UsbTest.RegistryFail) { Write-Error '模拟注册表非终止写入错误' }
}
function powercfg.exe {
    $command = [string]$args[0]
    if ($command -eq '/query') {
        $global:UsbTest.Queries++; $global:LASTEXITCODE = $global:UsbTest.QueryExit
        return $global:UsbTest.Query
    }
    Assert ($command -in @('/setacvalueindex', '/setdcvalueindex', '/setactive')) '意外的电源命令'
    $global:UsbTest.PowerWrites++; $global:UsbTest.Commands.Add($command)
    $global:LASTEXITCODE = 0
    if ($command -eq $global:UsbTest.PowerFailure) { $global:LASTEXITCODE = 5; '模拟 powercfg 失败' }
}
function powercfg { powercfg.exe @args }
function Get-CimInstance { throw '禁止真实设备扫描' }
function Get-WmiObject { throw '禁止真实设备扫描' }
function New-Item { throw '禁止真实注册表写入' }
function New-ItemProperty { throw '禁止真实注册表写入' }
function Remove-ItemProperty { throw '禁止真实注册表写入' }
function Write-Host { param($Object, $ForegroundColor, [switch]$NoNewline); $global:UsbTest.Lines.Add([string]$Object) }
function Read-Host { param($Prompt); $global:UsbTest.Prompts++; return $global:UsbTest.Choice }

Reset-Mock
. $mainPath
Test-Case '点源只加载定义；语法、BOM 与无 exit 检查通过' {
    Assert (($global:UsbTest.Scans + $global:UsbTest.Properties + $global:UsbTest.RegistryReads + $global:UsbTest.Queries + $global:UsbTest.Prompts) -eq 0) '点源产生了系统访问或交互'
    Assert ($global:UsbTest.Lines.Count -eq 0) '点源不应运行主界面'
    Assert-NoWrites
}
Test-Case '同 VID/PID 两台物理设备保留，各自 MI 接口合并' {
    foreach ($id in @($mouse, $other)) {
        $global:UsbTest.Nodes[$id] = Node $id $rootHub @('USB\COMPOSITE') 'usbccgp' '复合键盘'
        foreach ($mi in @('00', '01')) {
            $interface = $id.Replace('PID_5678', "PID_5678&MI_$mi") + $mi
            $global:UsbTest.Nodes[$interface] = Node $interface $id @('USB\Class_03') 'HidUsb' '键盘接口'
        }
    }
    $data = Get-UsbData
    Assert ($data.Devices.Count -eq 2 -and $data.DirectInputCount -eq 2) '物理设备丢失或接口未合并'
    Assert (($data.Devices.InstanceId -join '|') -eq "$mouse|$other") '物理实例身份不正确'
}
Test-Case 'CPU 后接 Hub 保留 CPU 标签，根 Hub 不计层数' {
    $hub = 'USB\VID_4321&PID_0009\H'
    $global:UsbTest.Nodes[$hub] = Node $hub $rootHub @('USB\Class_09') '' '中文集线器'
    $global:UsbTest.Nodes[$other] = Node $other $hub @('USB\Class_03') '' '中文键盘'
    $data = Get-UsbData; $direct = $data.Devices[0].Chain; $viaHub = $data.Devices[1].Chain
    Assert ($direct.HubCount -eq 0 -and $viaHub.HubCount -eq 1 -and $data.DirectInputCount -eq 1) 'Hub 层数或直连计数错误'
    Assert ($viaHub.ControllerInfo.Type -eq 'CPU') 'Hub 不应改变控制器归属'
    $label = Get-PathLabel $viaHub
    Assert ($label -match 'CPU/SoC.*1 级 USB 集线器' -and $label -notmatch '芯片组') 'CPU + Hub 标签错误'
}
Test-Case '空闲 CPU 控制器无根 Hub、无输入设备时仍识别' {
    $global:UsbTest.Nodes.Remove($rootHub)
    $pch = 'PCI\VEN_1022&DEV_43F7\PCH'; $pchRoot = 'USB\ROOT_HUB30\PCH'
    $global:UsbTest.Nodes[$pch] = Node $pch '' @('PCI\CC_0C0330') '' '芯片组控制器'
    $global:UsbTest.Nodes[$pchRoot] = Node $pchRoot $pch @('USB\Class_09') 'USBHUB3'
    $global:UsbTest.Nodes[$mouse].ParentId = $pchRoot
    $data = Get-UsbData; $summary = Get-ConnectionSummary $data
    Assert ($data.HasCpuController -and $data.Controllers.Count -eq 2 -and $data.DirectInputCount -eq 0) '空闲 CPU 控制器被漏掉'
    Assert ($summary -match '识别到疑似 CPU/SoC' -and $summary -match '输入设备.*空闲端口' -and $summary -notmatch '没有直连端口') '空闲状态提示错误'
}
Test-Case '中文名称通过兼容 ID 或 service 独立识别' {
    foreach ($useService in @($false, $true)) {
        $controller = Node $cpu '' @('PCI\CC_0C0330') '' '中文主控制器'
        $hub = Node 'USB\VID_4321&PID_0009\H' '' @('USB\Class_09') '' '中文集线器'
        $input = Node $mouse '' @('USB\Class_03') '' '中文输入设备'
        if ($useService) {
            $controller.CompatibleIds = @(); $controller.Service = 'USBXHCI'
            $hub.CompatibleIds = @(); $hub.Service = 'USBHUB3'; $input.CompatibleIds = @(); $input.Service = 'HidUsb'
        }
        Assert ((Test-UsbController $controller) -and (Test-UsbHub $hub) -and (Test-UsbInputNode $input)) '分类依赖了英文名称'
    }
}
Test-Case '未知 Intel/AMD ID 和独立 Thunderbolt 不判为 CPU' {
    foreach ($id in @('PCI\VEN_8086&DEV_FFFF\X', 'PCI\VEN_1022&DEV_FFFF\X', 'PCI\VEN_8086&DEV_1138\X')) {
        $global:UsbTest.Nodes.Remove($cpu)
        $global:UsbTest.Nodes[$id] = Node $id '' @('PCI\CC_0C0330') '' '中文控制器'
        $global:UsbTest.Nodes[$rootHub].ParentId = $id
        $data = Get-UsbData
        Assert (-not $data.HasCpuController -and $data.DirectInputCount -eq 0) '未知型号或 Thunderbolt 被强判为 CPU'
        Assert ((Get-PathLabel $data.Devices[0].Chain) -match '未知') '界面未保留未知归属'
        $global:UsbTest.Nodes.Remove($id)
    }
}
Test-Case '断链设备保留并显示路径不完整与异常状态' {
    $global:UsbTest.Nodes[$mouse].ParentId = 'USB\missing'; $global:UsbTest.Nodes[$mouse].Status = 'Error'
    $data = Get-UsbData
    Assert ($data.Devices.Count -eq 1 -and -not $data.Devices[0].Chain.Complete -and $data.DirectInputCount -eq 0) '断链设备丢失或误判直连'
    Show-FullAnalysis $data; $text = $global:UsbTest.Lines -join "`n"
    Assert ($text -match '模拟鼠标' -and $text -match '路径不完整' -and $text -match '设备状态：Error') '断链设备未完整展示'
}
Test-Case '缺分类的共同 USB 祖先不能合并两台 HID 设备' {
    $global:UsbTest.Nodes[$mouse] = Node $mouse $rootHub @() '' '未知共同祖先'
    foreach ($suffix in @('A', 'B')) {
        $id = "HID\VID_1234&PID_5678\$suffix"
        $global:UsbTest.Nodes[$id] = Node $id $mouse @() '' '中文 HID 设备' 'HIDClass'
    }
    $data = Get-UsbData
    Assert ($data.Devices.Count -eq 2 -and $data.DirectInputCount -eq 0) '未知共同祖先导致错误合并或直连'
    Assert (@($data.Devices | Where-Object { $_.Chain.Complete }).Count -eq 0) '未知分类应显示不完整'
}
Test-Case 'powercfg 英文和中文 query 分别读取 AC/DC' {
    $state = Get-SystemUsbSuspend
    Assert ($state.AC -eq $false -and $state.DC -eq $true) '英文 AC/DC 读取错误'
    $global:UsbTest.Query = "可能的设置索引: 000`n可能的设置索引: 001`n当前交流电源设置索引: 0x00000001`n当前直流电源设置索引: 0x00000000"
    $state = Get-SystemUsbSuspend
    Assert ($state.AC -eq $true -and $state.DC -eq $false) '中文 AC/DC 读取错误'
    $global:UsbTest.QueryExit = 5; $state = Get-SystemUsbSuspend
    Assert ($null -eq $state.AC -and $null -eq $state.DC) 'query 失败不能伪造电源状态'
    Assert-NoWrites
}
foreach ($type in @('MSI', 'Suspend')) {
    Test-Case "$type 注册表非终止写错误不显示成功" {
        $ErrorActionPreference = 'Continue' # 不能靠测试全局 Stop 掩盖生产错误处理缺失。
        $global:UsbTest.RegistryFail = $true
        Apply-Optimization @{ Type = $type; Controller = $cpu; Name = '模拟控制器'; Desc = '模拟设置' } 2>$null
        $text = $global:UsbTest.Lines -join "`n"
        Assert ($global:UsbTest.RegistryWrites -eq 1) '没有执行模拟注册表写入'
        Assert ($text -match '\[失败\].*模拟注册表非终止写入错误' -and $text -notmatch '\[成功\]') '注册表失败被报告为成功'
    }
}
foreach ($command in @('/setacvalueindex', '/setdcvalueindex', '/setactive')) {
    Test-Case "powercfg $command 非零退出不显示成功" {
        $global:UsbTest.PowerFailure = $command
        Apply-Optimization @{ Type = 'SystemSuspend'; Name = '模拟电源计划'; Desc = '关闭挂起' }
        $text = $global:UsbTest.Lines -join "`n"
        Assert ($global:UsbTest.Commands[-1] -eq $command) '失败后不应继续其他电源写入'
        Assert ($text -match '\[失败\].*退出码 5' -and $text -notmatch '\[成功\]') 'powercfg 失败被报告为成功'
    }
}
Test-Case '管理员菜单回车跳过，零写入' {
    function Test-Administrator { return $true }
    Show-Optimizations (Get-UsbData)
    Assert ($global:UsbTest.Prompts -eq 1 -and ($global:UsbTest.Lines -join ' ') -match '可选设置') '没有提供可选菜单'
    Assert-NoWrites
}
Test-Case '非管理员菜单不接受修改，零写入' {
    function Test-Administrator { return $false }
    $global:UsbTest.Choice = '1'
    Show-Optimizations (Get-UsbData)
    Assert ($global:UsbTest.Prompts -eq 0 -and ($global:UsbTest.Lines -join ' ') -match '管理员') '非管理员仍可选择修改'
    Assert-NoWrites
}
Test-Case '管理员选择一项只执行该项模拟写入' {
    function Test-Administrator { return $true }
    $global:UsbTest.Choice = '1'
    Show-Optimizations (Get-UsbData)
    Assert ($global:UsbTest.RegistryWrites -eq 1 -and $global:UsbTest.PowerWrites -eq 0) '选择一项却修改了其他设置'
    Assert ($global:UsbTest.LastWrite.Name -eq 'MSISupported' -and $global:UsbTest.LastWrite.Value -eq 1 -and $global:UsbTest.LastWrite.Type -eq 'DWord') 'MSI 写入值或类型错误'
    Assert (($global:UsbTest.Lines -join ' ') -match '\[成功\]') '模拟写入成功未反馈'
}
foreach ($entry in @('本地 &', '文本 iex')) {
    Test-Case "$entry 默认扫描、显示、可选菜单并返回调用方" {
        if ($entry -eq '本地 &') { & $mainPath } else { $source | Invoke-Expression }
        $text = $global:UsbTest.Lines -join "`n"
        Assert ($global:UsbTest.Scans -eq 1 -and $global:UsbTest.Properties -eq $global:UsbTest.Nodes.Count) '默认入口没有执行完整模拟扫描'
        Assert ($text -match '(?s)正在扫描.*控制器与连接的输入设备.*输入设备详情.*可选设置' -and $text -match '模拟鼠标') '默认入口缺少展示或菜单'
        Assert ($text -notmatch '\[失败\]' -and $global:UsbTest.Queries -eq 1) '默认入口失败或漏读电源状态'
        Assert-NoWrites
    }
}
Microsoft.PowerShell.Utility\Write-Host "回归结果：$script:passed 项通过，$script:failed 项失败；PnP、注册表和 powercfg 全部使用模拟。"
if ($script:failed -gt 0) { throw "$script:failed 项回归测试失败。" }
