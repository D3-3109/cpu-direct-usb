#requires -Version 5.1
# 独立运行：powershell.exe -NoProfile -File .\tests\Settings.Tests.ps1
# 不依赖 Pester。设备、注册表、权限、机器标识、备份存储与电源命令全部使用内存模拟。
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\Settings.ps1'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw '设置模块语法检查失败。' }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -isnot [Management.Automation.Language.FunctionDefinitionAst]) { throw '模块顶层出现函数定义以外的操作。' }
}
. $modulePath
$realRegistryWriter = ${function:Write-UsbRegistryValue}

function Assert-SettingsTest {
    param([bool]$Condition, [string]$Message = '断言失败。')
    if (-not $Condition) { throw $Message }
}

function Copy-SettingsTestValue {
    param($Value)
    return ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 10 -Compress)
}

function Reset-SettingsMock {
    $script:controllerId = 'PCI\VEN_1234&DEV_5678\1&ABC&0&00'
    $script:schemeA = '11111111-1111-4111-8111-111111111111'
    $script:schemeB = '22222222-2222-4222-8222-222222222222'
    $script:mock = @{
        Admin = $true; AdminCalls = 0; Class = '{36fc9e60-c465-11cf-8056-444553540000}'
        Machine = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; Active = $script:schemeA; ActiveCalls = 0
        Registry = @{}; Power = @{}; Files = @{}; Backups = 0; RegistryWrites = 0; PowerWrites = 0
        Commands = (New-Object 'System.Collections.Generic.List[object]'); Events = (New-Object 'System.Collections.Generic.List[string]')
        RegistryReadError = $false; ClassError = $false; MachineError = $false; ActiveError = $false; PowerReadError = ''
        RegistryFailAt = @(); RegistryNonTermAt = @(); RegistryIgnoreAt = @()
        PowerExitAt = @{}; PowerNonTermAt = @(); PowerIgnoreAt = @()
        BackupFail = $false; BackupNonTerm = $false; BackupReadFail = $false; BackupCorrupt = $false; SwitchOnBackup = ''
    }
    $script:mock.Registry["MSI|$script:controllerId"] = @{ Exists = $true; Kind = 'DWord'; Value = 0 }
    $script:mock.Registry["Suspend|$script:controllerId"] = @{ Exists = $true; Kind = 'DWord'; Value = 1 }
    $script:mock.Power[$script:schemeA] = @{ AC = 1; DC = 1 }
    $script:mock.Power[$script:schemeB] = @{ AC = 1; DC = 0 }
}

# 所有系统边界在调用任何公开接口前即被覆盖。
function Test-UsbAdministrator { [CmdletBinding()]param(); $script:mock.AdminCalls++; return $script:mock.Admin }
function Get-UsbMachineBinding {
    [CmdletBinding()]param()
    if ($script:mock.MachineError) { Write-Error '模拟机器标识读取失败。'; return }
    return @{ Kind = 'MachineGuid'; Value = $script:mock.Machine }
}
function Get-UsbControllerClass {
    [CmdletBinding()]param([string]$InstanceId)
    if ($script:mock.ClassError) { Write-Error '模拟设备类读取失败。'; return }
    return $script:mock.Class
}
function Read-UsbRegistryValue {
    [CmdletBinding()]param([string]$Type, [string]$InstanceId)
    if ($script:mock.RegistryReadError) { Write-Error '模拟注册表非终止读取错误。'; return }
    $key = "$Type|$InstanceId"
    if ($script:mock.Registry.ContainsKey($key)) { return Copy-SettingsTestValue $script:mock.Registry[$key] }
    return @{ Exists = $false; Kind = $null; Value = $null }
}
function Write-UsbRegistryValue {
    [CmdletBinding()]param([string]$Type, [string]$InstanceId, $State)
    Assert-SettingsTest ($script:mock.Files.Count -gt 0) '未备份就写注册表。'
    $script:mock.RegistryWrites++
    $count = $script:mock.RegistryWrites
    $script:mock.Events.Add('注册表写入')
    if ($script:mock.RegistryIgnoreAt -notcontains $count) {
        if ($State.Exists) { $script:mock.Registry["$Type|$InstanceId"] = Copy-SettingsTestValue $State }
        else { $script:mock.Registry.Remove("$Type|$InstanceId") }
    }
    # 在产生部分效果后报错，验证调用方不能假设抛错意味着零写入。
    if ($script:mock.RegistryNonTermAt -contains $count) { Write-Error '模拟注册表非终止写入错误。' }
    if ($script:mock.RegistryFailAt -contains $count) { throw '模拟注册表写入失败。' }
}
function Get-UsbActiveScheme {
    [CmdletBinding()]param()
    $script:mock.ActiveCalls++
    if ($script:mock.ActiveError) { Write-Error '模拟活动方案读取失败。'; return }
    return $script:mock.Active
}
function Read-UsbPowerIndex {
    [CmdletBinding()]param([string]$SchemeGuid, [string]$Mode)
    Assert-SettingsTest ($SchemeGuid -in @($script:schemeA, $script:schemeB)) '读取必须使用具体方案。'
    if ($script:mock.PowerReadError -eq $Mode) { Write-Error '模拟电源值读取失败。'; return }
    return [long]$script:mock.Power[$SchemeGuid][$Mode]
}
function Invoke-UsbPowerCfgCommand {
    [CmdletBinding()]param([string[]]$Arguments)
    Assert-SettingsTest ($script:mock.Files.Count -gt 0) '未备份就写电源配置。'
    Assert-SettingsTest ($Arguments.Count -eq 5) '电源命令参数数量错误。'
    Assert-SettingsTest ($Arguments[0] -in @('/setacvalueindex', '/setdcvalueindex')) '禁止激活或执行其他电源命令。'
    Assert-SettingsTest ($Arguments[1] -in @($script:schemeA, $script:schemeB)) '禁止使用动态方案别名。'
    Assert-SettingsTest ($Arguments[2] -eq '2a737441-1930-4402-8d77-b2bebba308a3') 'USB 子组 GUID 错误。'
    Assert-SettingsTest ($Arguments[3] -eq '48e6b7a6-50f5-4782-a5d4-53bb8f07e226') 'USB 设置 GUID 错误。'
    Assert-SettingsTest ($Arguments[4] -in @('0', '1')) '电源设置值错误。'
    $script:mock.PowerWrites++
    $count = $script:mock.PowerWrites
    $script:mock.Commands.Add($Arguments.Clone())
    $script:mock.Events.Add('电源写入')
    $mode = if ($Arguments[0] -eq '/setacvalueindex') { 'AC' } else { 'DC' }
    if ($script:mock.PowerIgnoreAt -notcontains $count) { $script:mock.Power[$Arguments[1]][$mode] = [int]$Arguments[4] }
    if ($script:mock.PowerNonTermAt -contains $count) { Write-Error '模拟外部命令非终止错误。' }
    if ($script:mock.PowerExitAt.ContainsKey($count)) { return $script:mock.PowerExitAt[$count] }
    return 0
}
function Write-UsbBackupFile {
    [CmdletBinding()]param([string]$Directory, [string]$Json)
    $script:mock.Events.Add('备份写入')
    if ($script:mock.BackupNonTerm) { Write-Error '模拟备份非终止错误。'; return }
    if ($script:mock.BackupFail) { throw '模拟备份失败。' }
    $script:mock.Backups++
    $path = 'C:\模拟备份\' + [guid]::NewGuid().ToString('D') + '.json'
    Assert-SettingsTest (-not $script:mock.Files.ContainsKey($path)) '覆盖了已有备份。'
    $script:mock.Files[$path] = if ($script:mock.BackupCorrupt) { '{无效的备份}' } else { $Json }
    if ($script:mock.SwitchOnBackup) { $script:mock.Active = $script:mock.SwitchOnBackup }
    return $path
}
function Read-UsbBackupFile {
    [CmdletBinding()]param([string]$Path)
    $script:mock.Events.Add('备份读回')
    if ($script:mock.BackupReadFail) { Write-Error '模拟备份读回失败。'; return }
    if (-not $script:mock.Files.ContainsKey($Path)) { throw '模拟备份文件不存在。' }
    return $script:mock.Files[$Path]
}

# 防止未来修改测试时意外落入真实的设备/注册表命令。
function Get-PnpDevice { throw '测试禁止访问真实设备。' }
function Get-CimInstance { throw '测试禁止访问真实设备。' }
function Get-WmiObject { throw '测试禁止访问真实设备。' }
function Get-Item { throw '测试禁止访问真实注册表或备份。' }
function Get-ItemProperty { throw '测试禁止读取真实注册表。' }
function New-Item { throw '测试禁止创建真实注册表键或目录。' }
function New-ItemProperty { throw '测试禁止写入真实注册表。' }
function Set-ItemProperty { throw '测试禁止写入真实注册表。' }
function Remove-ItemProperty { throw '测试禁止删除真实注册表值。' }
function Get-Content { throw '测试禁止读取真实备份。' }
function Set-Content { throw '测试禁止写入真实备份。' }
function powercfg { throw '测试禁止调用真实电源命令。' }

function Get-TestOption { param([string]$Type = 'MSI'); return @{ Type = $Type; Controller = $(if ($Type -eq 'SystemSuspend') { $null } else { $script:controllerId }) } }
function Assert-NoSettingsWrites {
    Assert-SettingsTest (($script:mock.RegistryWrites + $script:mock.PowerWrites) -eq 0) '失败前发生了设置写入。'
}
function Invoke-SettingsTest {
    param([string]$Name, [scriptblock]$Body)
    Reset-SettingsMock
    try { & $Body; $script:passed++; Write-Output "通过：$Name" }
    catch { $script:failed++; Write-Output ("失败：{0}；{1}；位置：{2}" -f $Name, $_.Exception.Message, $_.ScriptStackTrace) }
}
$script:passed = 0; $script:failed = 0

Invoke-SettingsTest '点源只定义函数，原生接口可单独编译而不调用' {
    Initialize-UsbPowerNative
    Assert-SettingsTest ($null -ne ('CpuDirectUsb.SettingsPowerNative' -as [type]))
    Assert-NoSettingsWrites
    Assert-SettingsTest ($script:mock.AdminCalls -eq 0 -and $script:mock.ActiveCalls -eq 0)
}
Invoke-SettingsTest 'MSI 明确区分 0、1、缺值与无效配置' {
    $key = "MSI|$script:controllerId"
    $result = Get-MsiStatus $script:controllerId
    Assert-SettingsTest ($result.Enabled -eq $false -and $result.Status -match '仅注册表配置' -and $result.Status -match '未检测实际')
    $script:mock.Registry[$key].Value = 1
    Assert-SettingsTest ((Get-MsiStatus $script:controllerId).Enabled -eq $true)
    $script:mock.Registry[$key].Value = 2
    $result = Get-MsiStatus $script:controllerId
    Assert-SettingsTest ($null -eq $result.Enabled -and $result.Error.Length -gt 0)
    $script:mock.Registry.Remove($key)
    Assert-SettingsTest ($null -eq (Get-MsiStatus $script:controllerId).Enabled)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '字符串零不会冒充有效 MSI 双字配置' {
    $script:mock.Registry["MSI|$script:controllerId"] = @{ Exists = $true; Kind = 'String'; Value = '0' }
    Assert-SettingsTest ($null -eq (Get-MsiStatus $script:controllerId).Enabled)
}
Invoke-SettingsTest '控制器挂起区分启用、关闭和缺值' {
    Assert-SettingsTest ((Get-PowerManagement $script:controllerId).SelectiveSuspend -eq $true)
    $script:mock.Registry["Suspend|$script:controllerId"].Value = 0
    Assert-SettingsTest ((Get-PowerManagement $script:controllerId).SelectiveSuspend -eq $false)
    $script:mock.Registry.Remove("Suspend|$script:controllerId")
    Assert-SettingsTest ($null -eq (Get-PowerManagement $script:controllerId).SelectiveSuspend)
}
Invoke-SettingsTest '非终止读取错误返回未知及中文错误' {
    $script:mock.RegistryReadError = $true
    foreach ($result in @((Get-MsiStatus $script:controllerId), (Get-PowerManagement $script:controllerId))) {
        Assert-SettingsTest ($result.Error -match '系统访问失败')
    }
    Assert-SettingsTest ($null -eq (Get-MsiStatus $script:controllerId).Enabled)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '系统挂起结构化读取同一具体方案' {
    $result = Get-SystemUsbSuspend
    Assert-SettingsTest ($result.SchemeGuid -eq $script:schemeA -and $result.AC -eq $true -and $result.DC -eq $true -and $result.Error -eq '')
    Assert-SettingsTest ($script:mock.ActiveCalls -eq 1)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '系统单侧读取失败保留另一侧状态' {
    $script:mock.PowerReadError = 'AC'
    $result = Get-SystemUsbSuspend
    Assert-SettingsTest ($null -eq $result.AC -and $result.DC -eq $true -and $result.Error.Length -gt 0)
}
Invoke-SettingsTest '活动方案读取失败不伪造状态' {
    $script:mock.ActiveError = $true
    $result = Get-SystemUsbSuspend
    Assert-SettingsTest ($null -eq $result.SchemeGuid -and $null -eq $result.AC -and $null -eq $result.DC -and $result.Error.Length -gt 0)
}
Invoke-SettingsTest '配置选项严格使用布尔状态并兼容缺少设备状态字段' {
    $controller = @{ InstanceId = $script:controllerId; Info = @{ Name = '测试控制器' }; Msi = @{ Enabled = $false }; Power = @{ SelectiveSuspend = $true } }
    $data = @{ Controllers = @($controller); SystemSuspend = @{ AC = $false; DC = $true } }
    $options = @(Get-ConfigurationOptions $data)
    Assert-SettingsTest ($options.Count -eq 3 -and $options[0].Desc -match '驱动兼容性未验证')
    Assert-SettingsTest ($null -eq $options[2].Controller -and $options[0].Name -match '测试控制器')
    $controller.Status = 'Error'
    Assert-SettingsTest (@(Get-ConfigurationOptions $data).Count -eq 1)
    $controller.Status = 'OK'; $controller.Msi.Enabled = $null; $controller.Power.SelectiveSuspend = '1'
    $data.SystemSuspend = @{ AC = $null; DC = $false }
    Assert-SettingsTest (@(Get-ConfigurationOptions $data).Count -eq 0)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '配置选项接受纯数据对象并跳过无效设备标识' {
    $data = Copy-SettingsTestValue @{ Controllers = @(@{ InstanceId = $script:controllerId; Status = 'OK'; Info = @{ Name = '测试控制器' }; Msi = @{ Enabled = $false }; Power = @{ SelectiveSuspend = $false } }) }
    Assert-SettingsTest (@(Get-ConfigurationOptions $data).Count -eq 1)
    $data.Controllers[0].InstanceId = 'PCI\..\逃逸'
    Assert-SettingsTest (@(Get-ConfigurationOptions $data).Count -eq 0)
}
Invoke-SettingsTest '每次应用与恢复都检查管理员权限' {
    $script:mock.Admin = $false
    $a = Apply-Optimization (Get-TestOption)
    $b = Restore-UsbBackup 'C:\模拟备份\不存在.json'
    Assert-SettingsTest (-not $a.Success -and -not $b.Success -and $script:mock.AdminCalls -eq 2 -and $script:mock.Backups -eq 0)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '非 USB 设备类禁止修改' {
    $script:mock.Class = '{00000000-0000-0000-0000-000000000000}'
    $result = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest (-not $result.Success -and $script:mock.Backups -eq 0)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '设备目标拒绝路径遍历及任意注册表路径' {
    foreach ($id in @('PCI\..\A', 'USB\A\..', 'PCI\A\B\额外路径', 'HKLM:\SOFTWARE\A', 'PCI\A\*')) {
        $result = Apply-Optimization @{ Type = 'MSI'; Controller = $id }
        Assert-SettingsTest (-not $result.Success)
    }
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '机器标识不可用时零写入' {
    $script:mock.MachineError = $true
    $result = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest (-not $result.Success)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest 'MSI 成功返回单个结果且先备份再写入' {
    $output = @(Apply-Optimization (Get-TestOption))
    Assert-SettingsTest ($output.Count -eq 1 -and $output[0].Success -and $null -eq $output[0].RollbackSucceeded)
    Assert-SettingsTest ($script:mock.Registry["MSI|$script:controllerId"].Value -eq 1)
    Assert-SettingsTest ($script:mock.Events[0] -eq '备份写入' -and $script:mock.Events[1] -eq '备份读回' -and $script:mock.Events[2] -eq '注册表写入')
    $document = ConvertFrom-Json $script:mock.Files[$output[0].BackupPath]
    Assert-SettingsTest ($document.Version -eq 1 -and $document.State.Value -eq 0 -and $document.State.Kind -eq 'DWord' -and $document.State.Exists)
    Assert-SettingsTest ($document.Machine.Value -eq $script:mock.Machine)
}
Invoke-SettingsTest '控制器挂起成功写入双字零' {
    $result = Apply-Optimization (Get-TestOption Suspend)
    Assert-SettingsTest ($result.Success -and $script:mock.Registry["Suspend|$script:controllerId"].Value -eq 0)
}
Invoke-SettingsTest '备份失败保持零写入' {
    $script:mock.BackupFail = $true
    $result = Apply-Optimization (Get-TestOption SystemSuspend)
    Assert-SettingsTest (-not $result.Success -and $null -eq $result.RollbackSucceeded)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '备份非终止错误保持零写入' {
    $script:mock.BackupNonTerm = $true
    $result = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest (-not $result.Success)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '备份读回失败保持零写入' {
    $script:mock.BackupReadFail = $true
    $result = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest (-not $result.Success)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '备份内容损坏保持零写入' {
    $script:mock.BackupCorrupt = $true
    $result = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest (-not $result.Success)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '注册表写入非终止错误会回滚' {
    $script:mock.RegistryNonTermAt = @(1)
    $result = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest (-not $result.Success -and $result.RollbackSucceeded -eq $true -and $script:mock.Registry["MSI|$script:controllerId"].Value -eq 0)
    Assert-SettingsTest ($script:mock.Files.ContainsKey($result.BackupPath))
}
Invoke-SettingsTest '注册表读回不一致会回滚' {
    $script:mock.RegistryIgnoreAt = @(1)
    $result = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest (-not $result.Success -and $result.RollbackSucceeded -eq $true -and $result.Message -match '读回不一致')
}
Invoke-SettingsTest '回滚失败与普通失败明确区分并保留备份' {
    $script:mock.RegistryFailAt = @(1, 2)
    $result = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest (-not $result.Success -and $result.RollbackSucceeded -eq $false -and $result.Message -match '自动回滚失败' -and $script:mock.Files.ContainsKey($result.BackupPath))
}
Invoke-SettingsTest '电源配置写入成功并提示手动重新应用方案' {
    $result = Apply-Optimization (Get-TestOption SystemSuspend)
    Assert-SettingsTest ($result.Success -and $script:mock.PowerWrites -eq 2 -and $result.Message -match '手动重新应用')
    Assert-SettingsTest ($script:mock.Power[$script:schemeA].AC -eq 0 -and $script:mock.Power[$script:schemeA].DC -eq 0)
}
Invoke-SettingsTest '首条电源命令非零退出即停止继续修改并回滚' {
    $script:mock.PowerExitAt[1] = 5
    $result = Apply-Optimization (Get-TestOption SystemSuspend)
    Assert-SettingsTest (-not $result.Success -and $result.RollbackSucceeded -eq $true -and $script:mock.PowerWrites -eq 3)
    Assert-SettingsTest ($script:mock.Commands[1][0] -eq '/setacvalueindex' -and $script:mock.Commands[1][4] -eq '1')
}
Invoke-SettingsTest '第二条电源命令失败回滚两侧部分写入' {
    $script:mock.PowerExitAt[2] = 5
    $result = Apply-Optimization (Get-TestOption SystemSuspend)
    Assert-SettingsTest (-not $result.Success -and $result.RollbackSucceeded -eq $true -and $script:mock.PowerWrites -eq 4)
    Assert-SettingsTest ($script:mock.Power[$script:schemeA].AC -eq 1 -and $script:mock.Power[$script:schemeA].DC -eq 1)
}
Invoke-SettingsTest '外部命令非终止错误也触发回滚' {
    $script:mock.PowerNonTermAt = @(2)
    $result = Apply-Optimization (Get-TestOption SystemSuspend)
    Assert-SettingsTest (-not $result.Success -and $result.RollbackSucceeded -eq $true)
}
Invoke-SettingsTest '电源读回不一致不能报告成功' {
    $script:mock.PowerIgnoreAt = @(2)
    $result = Apply-Optimization (Get-TestOption SystemSuspend)
    Assert-SettingsTest (-not $result.Success -and $result.RollbackSucceeded -eq $true -and $result.Message -match '读回不一致')
}
Invoke-SettingsTest '电源回滚一侧失败仍尝试另一侧' {
    $script:mock.PowerExitAt[2] = 5; $script:mock.PowerExitAt[3] = 5
    $result = Apply-Optimization (Get-TestOption SystemSuspend)
    Assert-SettingsTest (-not $result.Success -and $result.RollbackSucceeded -eq $false -and $script:mock.PowerWrites -eq 4)
    Assert-SettingsTest ($script:mock.Commands[3][0] -eq '/setdcvalueindex')
}
Invoke-SettingsTest '用户中途切换电源计划不改变已固定目标' {
    $script:mock.SwitchOnBackup = $script:schemeB
    $result = Apply-Optimization (Get-TestOption SystemSuspend)
    Assert-SettingsTest ($result.Success -and $script:mock.Active -eq $script:schemeB -and $script:mock.ActiveCalls -eq 1)
    Assert-SettingsTest ($script:mock.Power[$script:schemeB].AC -eq 1 -and $script:mock.Power[$script:schemeB].DC -eq 0)
    foreach ($command in $script:mock.Commands) { Assert-SettingsTest ($command[1] -eq $script:schemeA) }
}
Invoke-SettingsTest '重复应用不会覆盖先前备份' {
    $a = Apply-Optimization (Get-TestOption)
    $script:mock.Registry["MSI|$script:controllerId"].Value = 0
    $b = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest ($a.Success -and $b.Success -and $a.BackupPath -ne $b.BackupPath -and $script:mock.Files.Count -eq 2)
}
Invoke-SettingsTest '恢复成功前先备份恢复前状态' {
    $applied = Apply-Optimization (Get-TestOption)
    $restored = Restore-UsbBackup $applied.BackupPath
    Assert-SettingsTest ($restored.Success -and $restored.BackupPath -ne $applied.BackupPath -and $script:mock.Registry["MSI|$script:controllerId"].Value -eq 0)
    $snapshot = ConvertFrom-Json $script:mock.Files[$restored.BackupPath]
    Assert-SettingsTest ($snapshot.State.Value -eq 1 -and $script:mock.Files.Count -eq 2)
}
Invoke-SettingsTest '恢复原先缺失的值会删除新增值' {
    $applied = Apply-Optimization (Get-TestOption)
    Assert-SettingsTest ($applied.Success)
    $document = ConvertFrom-Json $script:mock.Files[$applied.BackupPath]
    $document.State = @{ Exists = $false; Kind = $null; Value = $null }
    $script:mock.Files[$applied.BackupPath] = ConvertTo-Json $document -Depth 8
    $restored = Restore-UsbBackup $applied.BackupPath
    Assert-SettingsTest ($restored.Success -and -not $script:mock.Registry.ContainsKey("MSI|$script:controllerId") -and $restored.Message -match '空键会保留')
}
Invoke-SettingsTest '原始注册表类型和值可往返恢复' {
    foreach ($state in @(
        @{ Exists = $true; Kind = 'String'; Value = '原始中文值' },
        @{ Exists = $true; Kind = 'ExpandString'; Value = '%SystemRoot%\测试' },
        @{ Exists = $true; Kind = 'MultiString'; Value = @('中文', '第二项') },
        @{ Exists = $true; Kind = 'MultiString'; Value = @() },
        @{ Exists = $true; Kind = 'Binary'; Value = 'AAH/' },
        @{ Exists = $true; Kind = 'None'; Value = '' },
        @{ Exists = $true; Kind = 'QWord'; Value = '-9223372036854775808' },
        @{ Exists = $true; Kind = 'DWord'; Value = [long]4294967295 }
    )) {
        $script:mock.Registry["MSI|$script:controllerId"] = @{ Exists = $true; Kind = 'DWord'; Value = 0 }
        $applied = Apply-Optimization (Get-TestOption)
        Assert-SettingsTest $applied.Success
        $document = ConvertFrom-Json $script:mock.Files[$applied.BackupPath]
        $document.State = $state
        $script:mock.Files[$applied.BackupPath] = ConvertTo-Json $document -Depth 8
        $restored = Restore-UsbBackup $applied.BackupPath
        Assert-SettingsTest $restored.Success ('无法恢复类型：' + $state.Kind + '；' + $restored.Message)
        Assert-SettingsTest (Test-UsbStateEqual @{ Type = 'MSI' } $state $script:mock.Registry["MSI|$script:controllerId"])
    }
}
Invoke-SettingsTest '跨机器备份拒绝恢复且不写设置' {
    $applied = Apply-Optimization (Get-TestOption)
    $script:mock.Machine = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'; $script:mock.RegistryWrites = 0
    $restored = Restore-UsbBackup $applied.BackupPath
    Assert-SettingsTest (-not $restored.Success -and $restored.Message -match '其他机器' -and $script:mock.Backups -eq 1)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '恢复其他电源计划不会读取或切换活动方案' {
    $applied = Apply-Optimization (Get-TestOption SystemSuspend)
    $script:mock.Active = $script:schemeB; $script:mock.ActiveCalls = 0
    $restored = Restore-UsbBackup $applied.BackupPath
    Assert-SettingsTest ($restored.Success -and $script:mock.ActiveCalls -eq 0 -and $script:mock.Active -eq $script:schemeB)
    Assert-SettingsTest ($script:mock.Power[$script:schemeA].AC -eq 1 -and $script:mock.Power[$script:schemeB].DC -eq 0)
}
Invoke-SettingsTest '恢复前备份失败不写设置' {
    $applied = Apply-Optimization (Get-TestOption)
    $script:mock.RegistryWrites = 0; $script:mock.BackupFail = $true
    $restored = Restore-UsbBackup $applied.BackupPath
    Assert-SettingsTest (-not $restored.Success -and $null -eq $restored.RollbackSucceeded)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '恢复部分失败回滚到恢复前状态' {
    $applied = Apply-Optimization (Get-TestOption SystemSuspend)
    $script:mock.PowerWrites = 0; $script:mock.PowerExitAt[2] = 5
    $restored = Restore-UsbBackup $applied.BackupPath
    Assert-SettingsTest (-not $restored.Success -and $restored.RollbackSucceeded -eq $true -and $script:mock.Files.Count -eq 2)
    Assert-SettingsTest ($script:mock.Power[$script:schemeA].AC -eq 0 -and $script:mock.Power[$script:schemeA].DC -eq 0)
}
Invoke-SettingsTest '恢复及其回滚都失败时明确报告' {
    $applied = Apply-Optimization (Get-TestOption)
    $script:mock.RegistryWrites = 0; $script:mock.RegistryFailAt = @(1, 2)
    $restored = Restore-UsbBackup $applied.BackupPath
    Assert-SettingsTest (-not $restored.Success -and $restored.RollbackSucceeded -eq $false -and $restored.Message -match '自动回滚失败')
}
Invoke-SettingsTest '拒绝未知版本、额外路径、脚本字段及无效原值' {
    $applied = Apply-Optimization (Get-TestOption)
    $json = $script:mock.Files[$applied.BackupPath]
    $script:mock.RegistryWrites = 0
    foreach ($variant in 1..7) {
        $document = ConvertFrom-Json $json
        switch ($variant) {
            1 { $document.Version = 2 }
            2 { $document.Target | Add-Member Path 'HKLM:\SOFTWARE\任意位置' }
            3 { $document | Add-Member Command '任意命令' }
            4 { $document.Target.InstanceId = 'PCI\..\任意位置' }
            5 { $document.Target.Type = '任意类型' }
            6 { $document.State.Value = '0' }
            7 { $document.State.Exists = 'false' }
        }
        $script:mock.Files[$applied.BackupPath] = ConvertTo-Json $document -Depth 8
        $result = Restore-UsbBackup $applied.BackupPath
        Assert-SettingsTest (-not $result.Success)
    }
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '电源备份拒绝动态方案别名和非布尔索引' {
    $applied = Apply-Optimization (Get-TestOption SystemSuspend)
    $document = ConvertFrom-Json $script:mock.Files[$applied.BackupPath]
    $document.Target.SchemeGuid = 'SCHEME_CURRENT'
    $script:mock.Files[$applied.BackupPath] = ConvertTo-Json $document -Depth 8
    $script:mock.PowerWrites = 0
    Assert-SettingsTest (-not (Restore-UsbBackup $applied.BackupPath).Success)
    $document.Target.SchemeGuid = $script:schemeA; $document.State.AC = 2
    $script:mock.Files[$applied.BackupPath] = ConvertTo-Json $document -Depth 8
    Assert-SettingsTest (-not (Restore-UsbBackup $applied.BackupPath).Success)
    Assert-NoSettingsWrites
}
Invoke-SettingsTest '底层注册表写入显式设置类型并提升非终止错误' {
    # 运行真实包装函数，但它调用的所有注册表命令均在此作用域覆盖。
    function Test-Path { [CmdletBinding()]param($LiteralPath); return $true }
    function New-ItemProperty {
        [CmdletBinding()]param($LiteralPath, $Name, $PropertyType, $Value, [switch]$Force)
        Assert-SettingsTest ($PropertyType -eq 'DWord' -and $Force -and $Name -eq 'MSISupported' -and $Value -eq 1)
        Write-Error '模拟底层非终止错误。'
    }
    $caught = $false
    try { & $realRegistryWriter -Type MSI -InstanceId $script:controllerId -State @{ Exists = $true; Kind = 'DWord'; Value = 1 } }
    catch { $caught = $true }
    Assert-SettingsTest $caught
    Assert-NoSettingsWrites
}

Invoke-SettingsTest '应用时重新检查原值，缺值和异常类型不修改' {
    foreach ($state in @(@{ Exists = $false; Kind = $null; Value = $null }, @{ Exists = $true; Kind = 'String'; Value = '0' }, @{ Exists = $true; Kind = 'DWord'; Value = 1 })) {
        $script:mock.Registry["MSI|$script:controllerId"] = $state
        Assert-SettingsTest (-not (Apply-Optimization (Get-TestOption)).Success)
    }
    Assert-NoSettingsWrites
    Assert-SettingsTest ($script:mock.Backups -eq 0)
}
Invoke-SettingsTest 'USB 目标允许挂起设置但拒绝 MSI' {
    $script:controllerId = 'USB\VID_1234&PID_5678\ABC'
    $script:mock.Registry["Suspend|$script:controllerId"] = @{ Exists = $true; Kind = 'DWord'; Value = 1 }
    Assert-SettingsTest ($null -eq (Get-MsiStatus $script:controllerId).Enabled)
    Assert-SettingsTest (-not (Apply-Optimization (Get-TestOption)).Success)
    Assert-NoSettingsWrites
    Assert-SettingsTest ((Apply-Optimization (Get-TestOption Suspend)).Success)
}
Invoke-SettingsTest '系统两侧已关闭无需备份或写入' {
    $script:mock.Power[$script:schemeA] = @{ AC = 0; DC = 0 }
    $result = Apply-Optimization (Get-TestOption SystemSuspend)
    Assert-SettingsTest ($result.Success -and $result.Message -match '无需修改' -and $script:mock.Backups -eq 0)
    Assert-NoSettingsWrites
}

Write-Output ("设置模块测试结果：{0} 项通过，{1} 项失败；所有系统访问均为模拟，原生接口仅编译定义。" -f $script:passed, $script:failed)
if ($script:failed -ne 0) { exit 1 }
