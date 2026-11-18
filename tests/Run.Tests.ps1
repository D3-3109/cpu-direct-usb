#requires -Version 5.1
# 独立离线运行：powershell.exe -NoProfile -NonInteractive -File .\tests\Run.Tests.ps1
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility, Microsoft.PowerShell.Management -ErrorAction Stop
$PSModuleAutoLoadingPreference = 'None'

$mainPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'cpudirect.ps1'
$source = [IO.File]::ReadAllText($mainPath, [Text.Encoding]::UTF8)
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
if ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.ExitStatementAst] }, $true).Count) {
    throw '主脚本包含 exit，会影响调用方。'
}
foreach ($path in @($PSCommandPath, $mainPath)) {
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) {
        throw "缺少 UTF-8 BOM：$path"
    }
}

$cpu = 'PCI\VEN_1022&DEV_15B6\CPU'; $rootHub = 'USB\ROOT_HUB30\CPU'
$mouse = 'USB\VID_1234&PID_5678\A'; $other = 'USB\VID_1234&PID_5678\B'
$script:passed = 0; $script:failed = 0

function Assert { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message } }
function Node {
    param($Id, $Parent = '', $Compatible = @(), $Service = '', $Name = '中文设备', $Class = 'USB', $Hardware = @(), $Bus = '')
    [pscustomobject]@{
        InstanceId = $Id; ParentId = $Parent; CompatibleIds = $Compatible; HardwareIds = $Hardware
        Service = $Service; FriendlyName = $Name; Class = $Class; Status = 'OK'; BusDescription = $Bus
    }
}
function Reset-Mock {
    $global:UsbTest = @{
        Nodes = @{}; Lines = [Collections.Generic.List[string]]::new()
        Scans = 0; Properties = 0; RegistryReads = 0; RegistryWrites = 0; RegistryKeysCreated = 0
        PowerWrites = 0; Queries = 0; RegistryFail = $false; PowerFailure = ''; QueryExit = 0
        Prompts = 0; Choice = ''; TestPathResult = $true
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

function Get-PnpDevice {
    [CmdletBinding()]param([switch]$PresentOnly)
    Assert $PresentOnly.IsPresent '扫描必须限定当前设备'
    $global:UsbTest.Scans++
    $global:UsbTest.Nodes.Values
}
function Get-PnpDeviceProperty {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipelineByPropertyName = $true)][string[]]$InstanceId,
        [string[]]$KeyName,
        [int]$ThrottleLimit
    )
    process {
        foreach ($id in $InstanceId) {
            Assert ($global:UsbTest.Nodes.ContainsKey($id)) '属性查询必须属于模拟设备'
            $global:UsbTest.Properties++
            $node = $global:UsbTest.Nodes[$id]
            $propMap = @{
                Parent                = 'ParentId'
                Service               = 'Service'
                CompatibleIds         = 'CompatibleIds'
                HardwareIds           = 'HardwareIds'
                BusReportedDeviceDesc = 'BusDescription'
            }
            foreach ($pair in $propMap.GetEnumerator()) {
                $key = 'DEVPKEY_Device_' + $pair.Key
                if ($KeyName -contains $key) {
                    [pscustomobject]@{ InstanceId = $id; KeyName = $key; Data = $node.($pair.Value) }
                }
            }
        }
    }
}
function Get-ItemProperty {
    [CmdletBinding()]param($LiteralPath, $Name)
    $global:UsbTest.RegistryReads++
    [pscustomobject]@{ MSISupported = [int]0; SelectiveSuspendEnabled = [int]1 }
}
function Test-Path {
    [CmdletBinding()]param($LiteralPath, $Path)
    return $global:UsbTest.TestPathResult
}
function New-Item {
    [CmdletBinding()]param($Path, [switch]$Force)
    $global:UsbTest.RegistryKeysCreated++
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

Test-Case '过滤主板灯控等纯厂商 HID，保留带厂商接口的真实键鼠与手柄' {
    $auraUsb = 'USB\VID_0B05&PID_1BED\9876543210'
    $auraMi  = 'USB\VID_0B05&PID_1BED&MI_02\9&1C90B44B&0&0002'
    $auraHid = 'HID\VID_0B05&PID_1BED&MI_02\A&B152954&0&0000'
    $global:UsbTest.Nodes[$auraUsb] = Node $auraUsb $rootHub @('USB\COMPOSITE') 'usbccgp' 'USB Composite Device' 'USB' @() 'AURA LED Controller'
    $global:UsbTest.Nodes[$auraMi]  = Node $auraMi $auraUsb @('USB\Class_03') 'HidUsb' 'USB 输入设备' 'HIDClass'
    $global:UsbTest.Nodes[$auraHid] = Node $auraHid $auraMi @() '' '符合 HID 标准的供应商定义设备' 'HIDClass' @('HID_DEVICE_UP:FF72_U:00A1', 'HID_DEVICE_UPR:FF00-FFFF', 'HID_DEVICE')

    $padUsb = 'USB\VID_054C&PID_0CE6\PAD1'
    $padHid = 'HID\VID_054C&PID_0CE6\PADHID1'
    $global:UsbTest.Nodes[$padUsb] = Node $padUsb $rootHub @('USB\Class_03') 'HidUsb' 'USB 输入设备' 'HIDClass' @() 'Wireless Controller'
    $global:UsbTest.Nodes[$padHid] = Node $padHid $padUsb @() '' 'HID-compliant game controller' 'HIDClass' @('HID_DEVICE_SYSTEM_GAME', 'HID_DEVICE_UP:0001_U:0005')

    $data = Get-UsbData
    $names = $data.Devices.Name -join '|'
    Assert ($data.Devices.Count -eq 2 -and $names -match '模拟鼠标' -and $names -match 'Wireless Controller') '真实输入设备丢失'
    Assert ($names -notmatch 'AURA') '主板 RGB 灯控不应作为输入设备展示'
}

Test-Case 'CPU 后接 Hub 保留 CPU 归属，展示芯片型号，根 Hub 不计层数' {
    $hub = 'USB\VID_174C&PID_2074\H'
    $global:UsbTest.Nodes[$hub] = Node $hub $rootHub @('USB\Class_09') 'USBHUB3' '通用 USB 集线器' 'USB' @() 'ASM107x'
    $global:UsbTest.Nodes[$other] = Node $other $hub @('USB\Class_03') '' '中文键盘'
    $data = Get-UsbData
    $direct = ($data.Devices | Where-Object { $_.InstanceId -eq $mouse }).Chain
    $viaHub = ($data.Devices | Where-Object { $_.InstanceId -eq $other }).Chain
    Assert ($direct.HubCount -eq 0 -and $direct.ChipCount -eq 0) '直连设备 ChipCount 错误'
    Assert ($viaHub.HubCount -eq 1 -and $viaHub.ChipCount -eq 1 -and $data.DirectInputCount -eq 1) 'Hub 层数或直连计数错误'
    Assert ($viaHub.ControllerInfo.Type -eq 'CPU' -and $viaHub.HubNames[0] -eq 'ASM107x (通用 USB 集线器)') 'Hub 归属或芯片名称展示错误'
}

Test-Case '空闲 CPU 控制器无根 Hub、无输入设备时仍识别' {
    $global:UsbTest.Nodes.Remove($rootHub)
    $pch = 'PCI\VEN_1022&DEV_43F7\PCH'; $pchRoot = 'USB\ROOT_HUB30\PCH'
    $global:UsbTest.Nodes[$pch] = Node $pch '' @('PCI\CC_0C0330') '' '芯片组控制器'
    $global:UsbTest.Nodes[$pchRoot] = Node $pchRoot $pch @('USB\Class_09') 'USBHUB3'
    $global:UsbTest.Nodes[$mouse].ParentId = $pchRoot
    $data = Get-UsbData
    Assert ($data.HasCpuController -and $data.Controllers.Count -eq 2 -and $data.DirectInputCount -eq 0) '空闲 CPU 控制器被漏掉'
    Assert ($data.Devices[0].Chain.ChipCount -eq 1) '芯片组设备 ChipCount 应为 1'
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
        $global:UsbTest.Nodes.Remove($id)
    }
}

Test-Case '断链设备保留并显示路径不完整与异常状态' {
    $global:UsbTest.Nodes[$mouse].ParentId = 'USB\missing'; $global:UsbTest.Nodes[$mouse].Status = 'Error'
    $data = Get-UsbData
    Assert ($data.Devices.Count -eq 1 -and -not $data.Devices[0].Chain.Complete -and $null -eq $data.Devices[0].Chain.ChipCount) '断链设备丢失或误判'
    Show-FullAnalysis $data; $text = $global:UsbTest.Lines -join "`n"
    Assert ($text -match '模拟鼠标' -and $text -match '路径不完整' -and $text -match 'Error') '断链设备未完整展示'
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

Test-Case 'MSI 注册表路径不存在时自动创建并写入' {
    $global:UsbTest.TestPathResult = $false
    $ok = Apply-Optimization @{ Type = 'MSI'; Controller = $cpu; Name = '模拟控制器'; Desc = '启用 MSI 中断' }
    Assert ($ok -and $global:UsbTest.RegistryKeysCreated -eq 1 -and $global:UsbTest.RegistryWrites -eq 1) '未创建缺失的 MSI 注册表项'
}

foreach ($type in @('MSI', 'Suspend')) {
    Test-Case "$type 注册表非终止写错误不显示成功" {
        $ErrorActionPreference = 'Continue'
        $global:UsbTest.RegistryFail = $true
        $ok = Apply-Optimization @{ Type = $type; Controller = $cpu; Name = '模拟控制器'; Desc = '模拟设置' } 2>$null
        $text = $global:UsbTest.Lines -join "`n"
        Assert (-not $ok -and $global:UsbTest.RegistryWrites -eq 1) '没有执行模拟注册表写入'
        Assert ($text -match '\[失败\].*模拟注册表非终止写入错误' -and $text -notmatch '\[成功\]') '注册表失败被报告为成功'
    }
}

foreach ($command in @('/setacvalueindex', '/setdcvalueindex', '/setactive')) {
    Test-Case "powercfg $command 非零退出不显示成功" {
        $global:UsbTest.PowerFailure = $command
        $ok = Apply-Optimization @{ Type = 'SystemSuspend'; Name = '模拟电源计划'; Desc = '关闭挂起' }
        $text = $global:UsbTest.Lines -join "`n"
        Assert (-not $ok -and $global:UsbTest.Commands[-1] -eq $command) '失败后不应继续其他电源写入'
        Assert ($text -match '\[失败\].*退出码 5' -and $text -notmatch '\[成功\]') 'powercfg 失败被报告为成功'
    }
}

Test-Case '管理员菜单回车跳过，零写入' {
    function Test-Administrator { return $true }
    $res = Show-Optimizations (Get-UsbData)
    Assert ($res -eq 'EXIT' -and $global:UsbTest.Prompts -eq 1) '回车应退出'
    Assert-NoWrites
}

Test-Case '非管理员拒绝序号修改（零写入），但支持按 R 重新扫描' {
    function Test-Administrator { return $false }
    $data = Get-UsbData
    $global:UsbTest.Choice = '1'
    $res1 = Show-Optimizations $data
    Assert ($res1 -eq 'DONE' -and ($global:UsbTest.Lines -join ' ') -match '管理员') '非管理员不应执行优化'
    Assert-NoWrites

    $global:UsbTest.Choice = 'R'
    $res2 = Show-Optimizations $data
    Assert ($res2 -eq 'RESCAN') '非管理员应支持按 R 重新扫描端口'
    Assert-NoWrites
}

Test-Case '管理员选择一项只执行该项模拟写入' {
    function Test-Administrator { return $true }
    $global:UsbTest.Choice = '1'
    $res = Show-Optimizations (Get-UsbData)
    Assert ($res -eq 'APPLIED' -and $global:UsbTest.RegistryWrites -eq 1 -and $global:UsbTest.PowerWrites -eq 0) '选择一项却修改了其他设置'
    Assert ($global:UsbTest.LastWrite.Name -eq 'MSISupported' -and $global:UsbTest.LastWrite.Value -eq 1 -and $global:UsbTest.LastWrite.Type -eq 'DWord') 'MSI 写入值或类型错误'
    Assert (($global:UsbTest.Lines -join ' ') -match '\[成功\]') '模拟写入成功未反馈'
}

Test-Case '管理员选择 A 一键应用所有可用优化' {
    function Test-Administrator { return $true }
    $global:UsbTest.Choice = 'A'
    $res = Show-Optimizations (Get-UsbData)
    Assert ($res -eq 'APPLIED' -and $global:UsbTest.RegistryWrites -eq 2 -and $global:UsbTest.PowerWrites -eq 3) '未应用全部可用优化'
}

foreach ($entry in @('本地 &', '文本 iex')) {
    Test-Case "$entry 默认扫描、显示、可选菜单并返回调用方" {
        if ($entry -eq '本地 &') { & $mainPath } else { $source | Invoke-Expression }
        $text = $global:UsbTest.Lines -join "`n"
        Assert ($global:UsbTest.Scans -eq 1 -and $global:UsbTest.Properties -eq $global:UsbTest.Nodes.Count) '默认入口没有执行完整模拟扫描'
        Assert ($text -match '0 芯片' -and $text -match 'USB 控制器' -and $text -match '输入设备详情' -and $text -match '模拟鼠标') '默认入口缺少展示'
        Assert ($text -notmatch '\[失败\]' -and $global:UsbTest.Queries -eq 1) '默认入口失败或漏读电源状态'
        Assert-NoWrites
    }
}

Microsoft.PowerShell.Utility\Write-Host "回归结果：$script:passed 项通过，$script:failed 项失败；PnP、注册表和 powercfg 全部使用模拟。"
if ($script:failed -gt 0) { throw "$script:failed 项回归测试失败。" }
