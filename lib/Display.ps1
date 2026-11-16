#requires -Version 5.1

function Format-SettingState {
    param($Value)
    if ($null -eq $Value) { return '未知或未显式配置' }
    if ($Value) { return '已启用' }
    return '已禁用'
}

function Show-UsbAnalysis {
    param($Data)

    Write-Host ''
    Write-Host 'USB 连接分析器 · 简体中文版' -ForegroundColor Cyan
    Write-Host '控制器归属为型号推测；集线器层数单独显示，不测量或承诺延迟收益。'
    Write-Host ''
    Write-Host (Get-ConnectionSummary $Data) -ForegroundColor Yellow
    Write-Host "控制器：$($Data.Controllers.Count) 个  |  输入设备：$($Data.Devices.Count) 个"
    Write-Host ''
    Write-Host '控制器与连接的输入设备' -ForegroundColor Cyan
    Write-Host ('-' * 64)
    foreach ($controller in $Data.Controllers) {
        Write-Host ''
        Write-Host (Get-ControllerLabel $controller.Info) -ForegroundColor Green
        Write-Host "  $($controller.Info.Name)"
        Write-Host "  厂商/设备 ID：$($controller.Vid):$($controller.Did)"
        Write-Host "  平台：$($controller.Info.Platform)  |  规格：$($controller.Info.USB)"
        Write-Host "  判断依据：$($controller.Info.Evidence)"
        Write-Host "  实例：$($controller.InstanceId)"
        if ($controller.LocationPaths.Count -gt 0) { Write-Host "  系统位置路径：$($controller.LocationPaths -join '；')" }
        if ($controller.Msi) { Write-Host "  MSI 注册表配置：$($controller.Msi.Status)" }
        if ($controller.Power) { Write-Host "  控制器选择性挂起配置：$(Format-SettingState $controller.Power.SelectiveSuspend)" }
        if ($controller.Devices.Count -eq 0) {
            Write-Host '  当前未识别到该控制器下的输入设备；不代表没有可用端口。'
        } else {
            foreach ($device in $controller.Devices) {
                Write-Host "  |- $($device.Name)"
                Write-Host "     $(Get-PathLabel $device.Chain)"
            }
        }
    }
    if ($Data.Controllers.Count -eq 0) { Write-Host '未识别到 USB 主控制器，请查看扫描提示。' }

    Write-Host ''
    Write-Host '输入设备详情' -ForegroundColor Cyan
    Write-Host ('-' * 64)
    foreach ($device in $Data.Devices) {
        Write-Host ''
        Write-Host $device.Name -ForegroundColor White
        Write-Host "  厂商/产品 ID：$($device.Vid):$($device.Pid)"
        Write-Host "  $(Get-PathLabel $device.Chain)"
        Write-Host "  物理实例或保留的接口实例：$($device.InstanceId)"
        Write-Host "  合并的输入接口：$($device.InterfaceIds.Count) 个"
        if ($device.Chain.HubNames.Count -gt 0) { Write-Host "  集线器（从设备向上）：$($device.Chain.HubNames -join ' → ')" }
    }
    if ($Data.Devices.Count -eq 0) { Write-Host '当前未识别到 USB 输入设备。' }

    Write-Host ''
    Write-Host '当前电源计划' -ForegroundColor Cyan
    Write-Host "  插电时 USB 选择性挂起：$(Format-SettingState $Data.SystemSuspend.AC)"
    Write-Host "  电池时 USB 选择性挂起：$(Format-SettingState $Data.SystemSuspend.DC)"
    if ($Data.SystemSuspend.SchemeGuid) { Write-Host "  计划标识：$($Data.SystemSuspend.SchemeGuid)" }
    if ($Data.Diagnostics.Count -gt 0) {
        Write-Host ''
        Write-Host "扫描完成，但有 $($Data.Diagnostics.Count) 条提示：" -ForegroundColor Yellow
        foreach ($diagnostic in $Data.Diagnostics) { Write-Host "  - $diagnostic" -ForegroundColor Yellow }
    } else { Write-Host "`n扫描完成。" -ForegroundColor Green }
    Write-Host '更换插孔后重新运行可比较连接路径；空闲插孔的位置请查主板手册。'
    Write-Host ''
}

function Show-ConfigurationResult {
    param($Result)
    $color = if ($Result.Success) { 'Green' } else { 'Red' }
    Write-Host $Result.Message -ForegroundColor $color
    if ($Result.BackupPath) {
        Write-Host "备份文件：$($Result.BackupPath)"
        Write-Host "恢复命令：.\cpudirect.ps1 -Restore '$($Result.BackupPath.Replace("'", "''"))'"
    }
}

function Show-ConfigurationMenu {
    param($Data)
    $options = @(Get-ConfigurationOptions -Data $Data)
    if ($options.Count -eq 0) {
        Write-Host '没有可修改的已知设置；未知状态不会自动修改。'
        return $true
    }
    Write-Host '可选设置（不保证降低输入延迟）' -ForegroundColor Cyan
    Write-Host '这些设置需要管理员权限。选择后先备份，再修改并验证；失败时尝试恢复原值。'
    Write-Host '关闭选择性挂起可能增加功耗、影响续航；MSI 需硬件与驱动支持。'
    for ($index = 0; $index -lt $options.Count; $index++) {
        $option = $options[$index]
        Write-Host "`n[$($index + 1)] $($option.Desc)"
        Write-Host "    对象：$($option.Name)"
        Write-Host "    影响：$($option.Impact)" -ForegroundColor Yellow
    }
    Write-Host ''
    $choice = Read-Host '输入序号执行该项，直接回车退出'
    if ([string]::IsNullOrWhiteSpace($choice)) { return $true }
    $number = 0
    if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $options.Count) {
        Write-Host '序号无效，未修改任何设置。' -ForegroundColor Yellow
        return $false
    }
    $result = Apply-Optimization -Opt $options[$number - 1]
    Show-ConfigurationResult $result
    return $result.Success
}
