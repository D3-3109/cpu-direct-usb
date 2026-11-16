#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent

# 用 AST 只加载主脚本的型号字典；不运行主流程或触碰本机设备。
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot 'cpudirect.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors -join "`n") }
foreach ($name in @('IntelCpuIntegrated', 'IntelPch', 'IntelThunderbolt', 'AmdCpuIntegrated', 'AmdChipset', 'ThirdParty')) {
    $assignment = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq ('$' + $name)
    }, $false)
    if (-not $assignment) { throw "缺少型号表：$name" }
    . ([scriptblock]::Create($assignment.Extent.Text))
}
. (Join-Path $projectRoot 'lib/Topology.ps1')
. (Join-Path $projectRoot 'lib/Display.ps1')

$script:passed = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "断言失败：$Message" }
}
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    & $Body
    $script:passed++
    Write-Host "[通过] $Name"
}
function New-Node {
    param([string]$Id, [string]$Parent = '', [string[]]$Compatible = @(), [string]$Service = '', [string]$Name = '', [string]$Class = 'USB')
    return [pscustomobject]@{
        InstanceId = $Id; ParentId = $Parent; CompatibleIds = $Compatible; Service = $Service
        FriendlyName = $Name; Class = $Class; Status = 'OK'; BusDescription = ''; LocationPaths = @(); ReadError = ''
    }
}
function New-Fixture {
    $nodes = @{}
    $script:cpuId = 'PCI\VEN_1022&DEV_15B6\CPU'
    $script:pchId = 'PCI\VEN_1022&DEV_43F7\PCH'
    $script:rootId = 'USB\ROOT_HUB30\CPU'
    $script:pchRoot = 'USB\ROOT_HUB30\PCH'
    $nodes[$cpuId] = New-Node $cpuId '' @('PCI\CC_0C0330') '' '中文主控制器'
    $nodes[$pchId] = New-Node $pchId '' @('PCI\CC_0C0330') '' '芯片组主控制器'
    $nodes[$rootId] = New-Node $rootId $cpuId @('USB\Class_09') 'USBHUB3' '根集线器'
    $nodes[$pchRoot] = New-Node $pchRoot $pchId @('USB\Class_09') 'USBHUB3' '根集线器'
    return $nodes
}
function Convert-Fixture {
    param([hashtable]$Nodes)
    return ConvertTo-UsbData @{ Nodes = $Nodes; Diagnostics = @(); EnumerationSucceeded = $true }
}

Test-Case '空闲 CPU 控制器不会被误报为不存在' {
    $nodes = New-Fixture
    $id = 'USB\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id $pchRoot @('USB\Class_03') 'HidUsb' '键盘'
    $data = Convert-Fixture $nodes
    Assert-True $data.HasCpuController '应保留空闲 CPU 控制器'
    Assert-True ($data.DirectInputCount -eq 0) '当前没有直连设备'
    Assert-True ((Get-ConnectionSummary $data) -match '识别到疑似 CPU/SoC') '不能宣称没有 CPU USB'
}
Test-Case '根集线器不计入额外 Hub' {
    $nodes = New-Fixture
    $id = 'USB\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id $rootId @('USB\Class_03') 'HidUsb' '鼠标'
    $data = Convert-Fixture $nodes
    Assert-True ($data.DirectInputCount -eq 1) '应有一个推测直连设备'
    Assert-True ($data.Devices[0].Chain.HubCount -eq 0) '根集线器不增加层数'
}
Test-Case 'CPU 后接中文名称 Hub 保留 CPU 归属' {
    $nodes = New-Fixture
    $hubId = 'USB\VID_4321&PID_0009\H'
    $nodes[$hubId] = New-Node $hubId $rootId @('USB\Class_09&SubClass_00') '' '通用集线器'
    $id = 'USB\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id $hubId @('USB\Class_03') 'HidUsb' '鼠标'
    $data = Convert-Fixture $nodes
    $chain = $data.Devices[0].Chain
    Assert-True ($chain.HubCount -eq 1) '中文 Hub 应计数'
    Assert-True ($chain.ControllerInfo.Type -eq 'CPU') '不能标为芯片组'
    Assert-True ((Get-PathLabel $chain) -notmatch '芯片组') '展示也不能标为芯片组'
    Assert-True ($data.DirectInputCount -eq 0) '经 Hub 不视作无 Hub 直连'
}
Test-Case '多级 Hub 与芯片组独立表示' {
    $nodes = New-Fixture
    $first = 'USB\VID_4321&PID_0009\H1'; $second = 'USB\VID_4321&PID_0009\H2'
    $nodes[$first] = New-Node $first $pchRoot @('USB\Class_09') '' '一级集线器'
    $nodes[$second] = New-Node $second $first @() 'USBHUB3' '二级集线器'
    $id = 'USB\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id $second @('USB\Class_03') 'HidUsb' '鼠标'
    $chain = (Convert-Fixture $nodes).Devices[0].Chain
    Assert-True ($chain.HubCount -eq 2 -and $chain.ControllerInfo.Type -eq 'CHIPSET') '芯片组与两级 Hub 分开存储'
}
Test-Case '相同 VID/PID 的两个物理设备均保留' {
    $nodes = New-Fixture
    foreach ($suffix in @('A', 'B')) {
        $id = "USB\VID_1234&PID_5678\$suffix"
        $parent = if ($suffix -eq 'A') { $rootId } else { $pchRoot }
        $nodes[$id] = New-Node $id $parent @('USB\Class_03') 'HidUsb' '同型号手柄'
    }
    $data = Convert-Fixture $nodes
    Assert-True ($data.Devices.Count -eq 2) '不能按型号去重'
    Assert-True ($data.DirectInputCount -eq 1) '分别保留各自连接路径'
}
Test-Case '复合设备多个接口合并到物理 USB 父实例' {
    $nodes = New-Fixture
    $physical = 'USB\VID_1234&PID_5678\A'
    $nodes[$physical] = New-Node $physical $rootId @('USB\COMPOSITE') 'usbccgp' '复合键盘'
    foreach ($suffix in @('00', '01')) {
        $id = "USB\VID_1234&PID_5678&MI_$suffix\A$suffix"
        $nodes[$id] = New-Node $id $physical @('USB\Class_03') 'HidUsb' '键盘接口'
    }
    $data = Convert-Fixture $nodes
    Assert-True ($data.Devices.Count -eq 1) '应合并两个接口'
    Assert-True ($data.Devices[0].InterfaceIds.Count -eq 2) '保留两个接口标识'
    Assert-True ($data.Devices[0].InstanceId -eq $physical) '以物理实例为键'
}
Test-Case '不同复合设备的接口不会互相合并' {
    $nodes = New-Fixture
    foreach ($serial in @('A', 'B')) {
        $physical = "USB\VID_1234&PID_5678\$serial"
        $nodes[$physical] = New-Node $physical $rootId @('USB\COMPOSITE') 'usbccgp' '复合设备'
        foreach ($suffix in @('00', '01')) {
            $id = "USB\VID_1234&PID_5678&MI_$suffix\$serial$suffix"
            $nodes[$id] = New-Node $id $physical @('USB\Class_03') 'HidUsb' '接口'
        }
    }
    $data = Convert-Fixture $nodes
    Assert-True ($data.Devices.Count -eq 2) '两个物理实例应保留'
}
Test-Case '分类不依赖英文名称' {
    $node = New-Node 'USB\VID_1234&PID_5678\A' '' @('USB\Class_03') 'HidUsb' 'Hub Controller Root'
    Assert-True (-not (Test-UsbHub $node)) '名字含 Hub 的鼠标不是 Hub'
    Assert-True (-not (Test-UsbController $node)) '名字含 Controller 不是控制器'
    $controller = New-Node 'PCI\VEN_1234&DEV_5678\C' '' @('PCI\CC_0C0330') '' ''
    Assert-True (Test-UsbController $controller) '空名称控制器仍可按类代码识别'
}
Test-Case '仅服务字段可用的 USB HID 仍保留' {
    $node = New-Node 'USB\VID_1234&PID_5678\A' '' @() 'HidUsb' '中文设备'
    Assert-True (Test-UsbInputNode $node) 'HidUsb 是独立分类依据'
}
Test-Case '未知 Intel AMD 以及 Thunderbolt 不强判归属' {
    foreach ($vendor in @('8086', '1022')) {
        Assert-True ((Get-ControllerInfo $vendor 'ffff').Type -eq 'UNKNOWN') '未收录型号应未知'
    }
    $tb = Get-ControllerInfo '8086' '1138'
    Assert-True ($tb.Type -eq 'TB' -and $tb.Confidence -eq 'Unknown') 'Thunderbolt 上游未知'
    Assert-True ((Get-ControllerLabel $tb) -notmatch 'CPU') '不能显示位于 CPU 内'
    Assert-True ((Get-ControllerInfo '1b21' '3242').Type -eq 'ADDON') '第三方保留独立类别'
}
Test-Case '父链缺失保留设备及诊断' {
    $nodes = New-Fixture
    $id = 'USB\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id 'USB\missing' @('USB\Class_03') 'HidUsb' '断链设备'
    $data = Convert-Fixture $nodes
    Assert-True ($data.Devices.Count -eq 1) '不能丢弃断链设备'
    Assert-True (-not $data.Devices[0].Chain.Complete) '路径应不完整'
    Assert-True ($data.Diagnostics.Count -gt 0 -and $data.DirectInputCount -eq 0) '未知不能当直连'
}
Test-Case '读取异常和父链循环可诊断' {
    $nodes = New-Fixture
    $id = 'USB\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id $id @('USB\Class_03') 'HidUsb' '循环设备'
    $nodes[$id].ReadError = '访问被拒绝'
    $chain = Get-DeviceChain $id $nodes
    Assert-True (-not $chain.Complete) '异常不完整'
    Assert-True (($chain.Diagnostics -join ' ') -match '循环') '保留循环诊断'
    Assert-True (($chain.Diagnostics -join ' ') -match '访问被拒绝') '保留读取失败原因'
}
Test-Case '超出父链深度上限时保留未知' {
    $nodes = New-Fixture
    $id = 'USB\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id $rootId @('USB\Class_03') 'HidUsb' '鼠标'
    $chain = Get-DeviceChain $id $nodes -MaxDepth 1
    Assert-True (-not $chain.Complete -and ($chain.Diagnostics -join ' ') -match '超过') '达到上限必须报告'
}
Test-Case '没有分类信息的中间节点不当作零级 Hub' {
    $nodes = New-Fixture
    $middle = 'USB\VID_1111&PID_2222\M'
    $nodes[$middle] = New-Node $middle $rootId @() '' '未知中间节点'
    $id = 'USB\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id $middle @('USB\Class_03') 'HidUsb' '鼠标'
    $chain = Get-DeviceChain $id $nodes
    Assert-True (-not $chain.Complete) '未知节点应使直连判断不确定'
}
Test-Case '设备端 xDCI 不当作 USB 主机控制器' {
    $node = New-Node 'PCI\VEN_8086&DEV_7A61\XDCI' '' @('PCI\CC_0C03FE', 'PCI\CC_0C03') '' '设备端控制器'
    Assert-True (-not (Test-UsbController $node)) '排除设备端编程接口'
}
Test-Case '未识别的共同中间节点不能合并两台设备' {
    $nodes = New-Fixture
    $middle = 'USB\VID_1111&PID_2222\M'
    $nodes[$middle] = New-Node $middle $rootId @() '' '未知节点'
    foreach ($suffix in @('A', 'B')) {
        $id = "USB\VID_1234&PID_5678\$suffix"
        $nodes[$id] = New-Node $id $middle @('USB\Class_03') 'HidUsb' '鼠标'
    }
    $data = Convert-Fixture $nodes
    Assert-True ($data.Devices.Count -eq 2) '不能把共同未知节点当物理身份'
    Assert-True ($data.DirectInputCount -eq 0) '未知节点不能判为直连'
}
Test-Case '空枚举与枚举失败区分' {
    $empty = ConvertTo-UsbData @{ Nodes = @{}; Diagnostics = @(); EnumerationSucceeded = $true }
    $failed = ConvertTo-UsbData @{ Nodes = @{}; Diagnostics = @('设备枚举失败'); EnumerationSucceeded = $false }
    Assert-True ((Get-ConnectionSummary $empty) -ne (Get-ConnectionSummary $failed)) '不能把失败当空设备'
}
Test-Case 'Windows 枚举异常转为扫描诊断' {
    function Get-PnpDevice { [CmdletBinding()]param([switch]$PresentOnly); throw '模拟设备服务失败' }
    $snapshot = Get-PnpSnapshot
    Assert-True (-not $snapshot.EnumerationSucceeded) '枚举失败状态'
    Assert-True (($snapshot.Diagnostics -join ' ') -match '模拟设备服务失败') '保留异常'
}
Test-Case '枚举限定当前设备且保留状态异常设备' {
    $script:presentWasRequested = $false
    function Get-PnpDevice {
        [CmdletBinding()]param([switch]$PresentOnly)
        $script:presentWasRequested = $PresentOnly.IsPresent
        return [pscustomobject]@{ InstanceId = 'USB\VID_1234&PID_5678\A'; FriendlyName = '异常键盘'; Class = 'USB'; Status = 'Error' }
    }
    function Get-PnpDeviceProperty {
        [CmdletBinding()]param($InstanceId, $KeyName)
        return @([pscustomobject]@{ KeyName = 'DEVPKEY_Device_CompatibleIds'; Data = @('USB\Class_03') },
            [pscustomobject]@{ KeyName = 'DEVPKEY_Device_Parent'; Data = 'USB\missing' })
    }
    $snapshot = Get-PnpSnapshot
    Assert-True $script:presentWasRequested '必须 PresentOnly'
    $data = ConvertTo-UsbData $snapshot
    Assert-True ($data.Devices.Count -eq 1) '异常设备也保留'
    Assert-True (($data.Diagnostics -join ' ') -match '状态为 Error') '状态异常可见'
}
Test-Case '父属性缺失的 HID 节点保留为未完成设备' {
    $nodes = New-Fixture
    $id = 'HID\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id '' @() '' '未知父设备的 HID' 'HIDClass'
    $data = Convert-Fixture $nodes
    Assert-True ($data.Devices.Count -eq 1) '缺失父属性不能提前过滤 HID'
    Assert-True (-not $data.Devices[0].Chain.Complete -and $data.Diagnostics.Count -gt 0) '断链诊断保留'
}
Test-Case '部分属性成功时仍保留其他属性的读取错误' {
    function Get-PnpDevice {
        [CmdletBinding()]param([switch]$PresentOnly)
        return [pscustomobject]@{ InstanceId = 'USB\VID_1234&PID_5678\A'; FriendlyName = '鼠标'; Class = 'USB'; Status = 'OK' }
    }
    function Get-PnpDeviceProperty {
        [CmdletBinding()]param($InstanceId, $KeyName)
        [pscustomobject]@{ KeyName = 'DEVPKEY_Device_CompatibleIds'; Data = @('USB\Class_03') }
        Write-Error '模拟父属性访问失败'
    }
    $snapshot = Get-PnpSnapshot
    Assert-True (($snapshot.Diagnostics -join ' ') -match '模拟父属性访问失败') '部分成功也记录错误'
    $data = ConvertTo-UsbData $snapshot
    Assert-True ($data.Devices.Count -eq 1 -and -not $data.Devices[0].Chain.Complete) '已识别设备应带断链保留'
}
Test-Case '中文输出包含完整路径且不宣称延迟收益' {
    $nodes = New-Fixture
    $id = 'USB\VID_1234&PID_5678\A'
    $nodes[$id] = New-Node $id $rootId @('USB\Class_03') 'HidUsb' '鼠标'
    $data = Convert-Fixture $nodes
    $data.SystemSuspend = @{ AC = $true; DC = $false; SchemeGuid = 'mock' }
    $script:lines = [System.Collections.Generic.List[string]]::new()
    function Write-Host { param($Object, $ForegroundColor); $script:lines.Add([string]$Object) }
    Show-UsbAnalysis $data
    $text = $script:lines -join "`n"
    Assert-True ($text -match '简体中文版' -and $text -match '电池时 USB 选择性挂起：已禁用') '中文主界面和 AC/DC 分别显示'
    Assert-True ($text -notmatch 'CHIP [012]|lowest latency|低延迟中断') '不保留旧的确定性性能标签'
}
Write-Host "拓扑与界面测试：$script:passed 项通过；未访问真实设备或设置。"
