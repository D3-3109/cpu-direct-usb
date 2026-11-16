#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $root 'cpudirect.ps1'
$script:systemCalls = 0

# 点源导入不得调用设备、注册表、电源或编译系统适配器。
function Get-PnpDevice { throw '测试禁止访问真实设备' }
function Get-PnpDeviceProperty { throw '测试禁止访问真实设备属性' }
function Get-ItemProperty { throw '测试禁止读取真实注册表' }
function Set-ItemProperty { throw '测试禁止修改真实注册表' }
function New-ItemProperty { throw '测试禁止修改真实注册表' }
function Remove-ItemProperty { throw '测试禁止修改真实注册表' }
function powercfg { throw '测试禁止访问真实电源设置' }
function Add-Type { throw '点源时不应编译系统适配器' }
function Read-Host { throw '点源时不应询问用户' }
. $scriptPath
Write-Host '[通过] 点源只导入定义，无扫描、编译或写入副作用'
$parameterSets = (Get-Command $scriptPath).ParameterSets
foreach ($set in $parameterSets) {
    $modes = @($set.Parameters | Where-Object { $_.Name -in @('Configure', 'Restore', 'Json') })
    if ($modes.Count -gt 1 -or ($set.Name -eq 'Scan' -and $modes.Count -gt 0)) { throw '运行模式未隔离' }
}
if ($parameterSets.Count -ne 4) { throw '缺少运行模式' }
Write-Host '[通过] 扫描、JSON、配置与恢复参数模式互斥'

$script:snapshot = @{
    Nodes = @{
        'PCI\VEN_1022&DEV_15B6\C' = [pscustomobject]@{
            InstanceId = 'PCI\VEN_1022&DEV_15B6\C'; ParentId = ''; CompatibleIds = @('PCI\CC_0C0330')
            Service = 'USBXHCI'; FriendlyName = '中文控制器'; Class = 'USB'; Status = 'OK'
            BusDescription = ''; LocationPaths = @('PCIROOT(0)#PCI(0801)#PCI(0003)'); ReadError = ''
        }
        'USB\ROOT_HUB30\R' = [pscustomobject]@{
            InstanceId = 'USB\ROOT_HUB30\R'; ParentId = 'PCI\VEN_1022&DEV_15B6\C'; CompatibleIds = @('USB\Class_09')
            Service = 'USBHUB3'; FriendlyName = '根集线器'; Class = 'USB'; Status = 'OK'
            BusDescription = ''; LocationPaths = @(); ReadError = ''
        }
        'USB\VID_1234&PID_5678\A' = [pscustomobject]@{
            InstanceId = 'USB\VID_1234&PID_5678\A'; ParentId = 'USB\ROOT_HUB30\R'; CompatibleIds = @('USB\Class_03')
            Service = 'HidUsb'; FriendlyName = '测试鼠标'; Class = 'USB'; Status = 'OK'
            BusDescription = '模拟鼠标'; LocationPaths = @(); ReadError = ''
        }
    }
    Diagnostics = @()
    EnumerationSucceeded = $true
}
function Get-PnpSnapshot { return $script:snapshot }
function Get-SystemUsbSuspend { return @{ SchemeGuid = '00000000-0000-0000-0000-000000000001'; AC = $true; DC = $false; Error = '' } }
function Get-MsiStatus { param($InstanceId); return @{ Enabled = $false; Status = '配置为关闭'; Error = '' } }
function Get-PowerManagement { param($InstanceId); return @{ SelectiveSuspend = $true; Error = '' } }
$data = Get-UsbData
if ($data.Devices.Count -ne 1 -or -not $data.HasCpuController -or $data.DirectInputCount -ne 1) { throw '扫描数据集成失败' }
$jsonText = $data | ConvertTo-Json -Depth 16
$decoded = $jsonText | ConvertFrom-Json
if ($decoded.Devices[0].Name -ne '模拟鼠标' -or $decoded.SystemSuspend.DC -ne $false) { throw 'JSON 输出数据不完整' }
Write-Host '[通过] 模拟扫描集成与中文 JSON 输出'

$options = @(Get-ConfigurationOptions $data)
foreach ($required in @('MSI', 'Suspend', 'SystemSuspend')) {
    if (@($options | Where-Object { $_.Type -eq $required }).Count -ne 1) { throw "配置接口不兼容：$required" }
}
Write-Host '[通过] 扫描数据与设置模块的选项接口匹配'

$script:writeCount = 0
function Test-ConfigurationMenu {
    param($Data)
    function Write-Host { param($Object, $ForegroundColor) }
    return Show-ConfigurationMenu $Data
}
function Apply-Optimization { param($Opt); $script:writeCount++; return @{ Success = $false; Message = '模拟失败'; BackupPath = ''; RollbackSucceeded = $true } }
function Read-Host { param($Prompt); return '' }
$skipped = Test-ConfigurationMenu $data
if (-not $skipped -or $script:writeCount -ne 0) { throw '回车跳过仍调用了修改' }
Write-Host '[通过] 配置菜单回车不修改任何设置'
function Read-Host { param($Prompt); return '99999999999999999999999999999' }
$invalid = Test-ConfigurationMenu $data
if ($invalid -or $script:writeCount -ne 0) { throw '超大序号应被拒绝' }
Write-Host '[通过] 非法序号不会触发修改'
function Read-Host { param($Prompt); return '1' }
$failed = Test-ConfigurationMenu $data
if ($failed -or $script:writeCount -ne 1) { throw '修改失败状态未传回入口' }
Write-Host '[通过] 修改失败返回失败状态，不误报成功'
Write-Host '入口与模块集成测试：7 项通过；全部系统访问均被拦截或模拟。'
