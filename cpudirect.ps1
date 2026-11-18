#requires -Version 5.1
<#
.SYNOPSIS
    CPU Direct USB - USB 直连与拓扑分析工具（简体中文版）
.DESCRIPTION
    扫描 USB 控制器与输入设备，直观展示设备到 CPU 之间经过的芯片层级（0 芯片直连 / 1 芯片 / 2+ 芯片），
    并提供 MSI 中断与 USB 选择性挂起的快捷优化。
    原项目：MariusHeier/cpu-direct-usb
#>

# =============================================================================
# 规范常量与控制器型号表（源自 Linux xhci-pci.c / pci.ids）
# =============================================================================

$VendorIntel = '8086'
$VendorAmd   = '1022'

$UsbPowerSubgroup  = '2a737441-1930-4402-8d77-b2bebba308a3'
$UsbSuspendSetting = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$UnrankedChipOrder = 99

$IntelCpuIntegrated = @{
    '8a13' = @{ Name = "Ice Lake Thunderbolt 3 USB Controller"; Platform = "Ice Lake (10th Gen)"; USB = "USB 3.2/TB3" }
    '9a13' = @{ Name = "Tiger Lake-LP Thunderbolt 4 USB Controller"; Platform = "Tiger Lake (11th Gen)"; USB = "USB4/TB4" }
    '9a17' = @{ Name = "Tiger Lake-H Thunderbolt 4 USB Controller"; Platform = "Tiger Lake-H (11th Gen)"; USB = "USB4/TB4" }
    '461e' = @{ Name = "Alder Lake-P Thunderbolt 4 USB Controller"; Platform = "Alder Lake (12th Gen)"; USB = "USB4/TB4" }
    '464e' = @{ Name = "Alder Lake-N Processor USB 3.2 xHCI Controller"; Platform = "Alder Lake-N"; USB = "USB 3.2" }
    'a71e' = @{ Name = "Raptor Lake-P Thunderbolt 4 USB Controller"; Platform = "Raptor Lake (13th Gen)"; USB = "USB4/TB4" }
    '7ec0' = @{ Name = "Meteor Lake-P Thunderbolt 4 USB Controller"; Platform = "Meteor Lake (Core Ultra)"; USB = "USB4/TB4" }
    'a831' = @{ Name = "Lunar Lake-M Thunderbolt 4 USB Controller"; Platform = "Lunar Lake"; USB = "USB4/TB4" }
}

$IntelPch = @{
    '7f6e' = @{ Name = "800 Series PCH USB 3.1 xHCI HC"; Platform = "800 Series PCH"; USB = "USB 3.1" }
    '7a60' = @{ Name = "Raptor Lake USB 3.2 Gen 2x2 XHCI Host Controller"; Platform = "700 Series PCH"; USB = "USB 3.2 Gen 2x2 (20Gbps)" }
    '7a61' = @{ Name = "Raptor Lake USB 3.2 Gen 1x1 xDCI Device Controller"; Platform = "700 Series PCH"; USB = "USB 3.2 Gen 1" }
    '7ae0' = @{ Name = "Alder Lake-S PCH USB 3.2 Gen 2x2 XHCI Controller"; Platform = "600 Series PCH (Desktop)"; USB = "USB 3.2 Gen 2x2 (20Gbps)" }
    '51ed' = @{ Name = "Alder Lake PCH USB 3.2 xHCI Host Controller"; Platform = "600 Series PCH"; USB = "USB 3.2" }
    '54ed' = @{ Name = "Alder Lake-N PCH USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "Alder Lake-N PCH"; USB = "USB 3.2 Gen 2 (10Gbps)" }
    '7e7d' = @{ Name = "Meteor Lake-P USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "Meteor Lake PCH"; USB = "USB 3.2 Gen 2" }
    '777d' = @{ Name = "Arrow Lake USB 3.2 xHCI Controller"; Platform = "Arrow Lake"; USB = "USB 3.2" }
    'a87d' = @{ Name = "Lunar Lake-M USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "Lunar Lake PCH"; USB = "USB 3.2 Gen 2" }
    'a0ed' = @{ Name = "Tiger Lake-LP USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "500 Series PCH"; USB = "USB 3.2 Gen 2 (10Gbps)" }
    '43ed' = @{ Name = "Tiger Lake-H USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "500 Series PCH-H"; USB = "USB 3.2 Gen 2" }
    'a3af' = @{ Name = "Comet Lake PCH-V USB Controller"; Platform = "400 Series PCH"; USB = "USB 3.1" }
    '02ed' = @{ Name = "Comet Lake PCH-LP USB 3.1 xHCI Host Controller"; Platform = "400 Series PCH-LP"; USB = "USB 3.1" }
    '06ed' = @{ Name = "Comet Lake USB 3.1 xHCI Host Controller"; Platform = "400 Series PCH"; USB = "USB 3.1" }
    'a36d' = @{ Name = "Cannon Lake PCH USB 3.1 xHCI Host Controller"; Platform = "300 Series PCH"; USB = "USB 3.1" }
    '9ded' = @{ Name = "Cannon Point-LP USB 3.1 xHCI Controller"; Platform = "300 Series PCH-LP"; USB = "USB 3.1" }
    'a2af' = @{ Name = "200 Series/Z370 Chipset Family USB 3.0 xHCI Controller"; Platform = "200 Series PCH"; USB = "USB 3.0" }
    'a12f' = @{ Name = "100 Series/C230 Series Chipset Family USB 3.0 xHCI Controller"; Platform = "100 Series PCH"; USB = "USB 3.0" }
    '9d2f' = @{ Name = "Sunrise Point-LP USB 3.0 xHCI Controller"; Platform = "100 Series PCH-LP"; USB = "USB 3.0" }
    '8cb1' = @{ Name = "9 Series Chipset Family USB xHCI Controller"; Platform = "9 Series PCH"; USB = "USB 3.0" }
    '9cb1' = @{ Name = "Wildcat Point-LP USB xHCI Controller"; Platform = "9 Series PCH-LP"; USB = "USB 3.0" }
    '8c31' = @{ Name = "8 Series/C220 Series Chipset Family USB xHCI"; Platform = "8 Series PCH"; USB = "USB 3.0" }
    '9c31' = @{ Name = "8 Series USB xHCI HC"; Platform = "8 Series PCH-LP"; USB = "USB 3.0" }
    '1e31' = @{ Name = "7 Series/C210 Series Chipset Family USB xHCI Host Controller"; Platform = "7 Series PCH"; USB = "USB 3.0" }
    '8d31' = @{ Name = "C610/X99 series chipset USB xHCI Host Controller"; Platform = "X99/C610 (HEDT/Server)"; USB = "USB 3.0" }
    'a1af' = @{ Name = "C620 Series Chipset Family USB 3.0 xHCI Controller"; Platform = "C620 (Server)"; USB = "USB 3.0" }
}

$IntelThunderbolt = @{
    '5782' = @{ Name = "JHL9580 Thunderbolt 5 USB Controller"; Platform = "Barlow Ridge Host 80G"; USB = "USB4/TB5 (80Gbps)" }
    '5785' = @{ Name = "JHL9540 Thunderbolt 4 USB Controller"; Platform = "Barlow Ridge Host 40G"; USB = "USB4/TB4 (40Gbps)" }
    '5787' = @{ Name = "JHL9480 Thunderbolt 5 USB Controller"; Platform = "Barlow Ridge Hub 80G"; USB = "USB4/TB5 (80Gbps)" }
    '57a5' = @{ Name = "JHL9440 Thunderbolt 4 USB Controller"; Platform = "Barlow Ridge Hub 40G"; USB = "USB4/TB4 (40Gbps)" }
    '1138' = @{ Name = "Thunderbolt 4 USB Controller [Maple Ridge 4C]"; Platform = "Maple Ridge 4C"; USB = "USB4/TB4 (40Gbps)" }
    '1135' = @{ Name = "Thunderbolt 4 USB Controller [Maple Ridge 2C]"; Platform = "Maple Ridge 2C"; USB = "USB4/TB4 (40Gbps)" }
    '0b27' = @{ Name = "Thunderbolt 4 USB Controller [Goshen Ridge]"; Platform = "Goshen Ridge"; USB = "USB4/TB4 (40Gbps)" }
    '15e9' = @{ Name = "JHL7540 Thunderbolt 3 USB Controller [Titan Ridge 2C]"; Platform = "Titan Ridge 2C"; USB = "USB 3.1/TB3 (40Gbps)" }
    '15ec' = @{ Name = "JHL7540 Thunderbolt 3 USB Controller [Titan Ridge 4C]"; Platform = "Titan Ridge 4C"; USB = "USB 3.1/TB3 (40Gbps)" }
    '15f0' = @{ Name = "JHL7440 Thunderbolt 3 USB Controller [Titan Ridge DD]"; Platform = "Titan Ridge DD"; USB = "USB 3.1/TB3 (40Gbps)" }
    '15b5' = @{ Name = "DSL6340 USB 3.1 Controller [Alpine Ridge 2C]"; Platform = "Alpine Ridge 2C"; USB = "USB 3.1/TB3 (40Gbps)" }
    '15b6' = @{ Name = "DSL6540 USB 3.1 Controller [Alpine Ridge 4C]"; Platform = "Alpine Ridge 4C"; USB = "USB 3.1/TB3 (40Gbps)" }
    '15c1' = @{ Name = "JHL6240 Thunderbolt 3 USB 3.1 Controller [Alpine Ridge LP]"; Platform = "Alpine Ridge LP"; USB = "USB 3.1/TB3" }
    '15d4' = @{ Name = "JHL6540 Thunderbolt 3 USB Controller [Alpine Ridge 4C]"; Platform = "Alpine Ridge 4C C-step"; USB = "USB 3.1/TB3 (40Gbps)" }
    '15db' = @{ Name = "JHL6340 Thunderbolt 3 USB 3.1 Controller [Alpine Ridge 2C]"; Platform = "Alpine Ridge 2C C-step"; USB = "USB 3.1/TB3 (40Gbps)" }
}

$AmdCpuIntegrated = @{
    '15b6' = @{ Name = "Raphael/Granite Ridge USB 3.1 xHCI"; Platform = "Ryzen 7000/9000 Desktop (AM5)"; USB = "USB 3.1" }
    '15b7' = @{ Name = "Raphael/Granite Ridge USB 3.1 xHCI"; Platform = "Ryzen 7000/9000 Desktop (AM5)"; USB = "USB 3.1" }
    '15b8' = @{ Name = "Raphael/Granite Ridge USB 2.0 xHCI"; Platform = "Ryzen 7000/9000 Desktop (AM5)"; USB = "USB 2.0" }
    '1587' = @{ Name = "Strix Halo USB 3.1 xHCI"; Platform = "Strix Halo (Zen 5)"; USB = "USB 3.1" }
    '1588' = @{ Name = "Strix Halo USB 3.1 xHCI"; Platform = "Strix Halo (Zen 5)"; USB = "USB 3.1" }
    '1589' = @{ Name = "Strix Halo USB 3.1 xHCI"; Platform = "Strix Halo (Zen 5)"; USB = "USB 3.1" }
    '158b' = @{ Name = "Strix Halo USB 3.1 xHCI"; Platform = "Strix Halo (Zen 5)"; USB = "USB 3.1" }
    '158d' = @{ Name = "Strix Halo USB4 Host Router"; Platform = "Strix Halo (Zen 5)"; USB = "USB4" }
    '158e' = @{ Name = "Strix Halo USB4 Host Router"; Platform = "Strix Halo (Zen 5)"; USB = "USB4" }
    '161a' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4" }
    '161b' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4" }
    '161c' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4" }
    '161d' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4" }
    '161e' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4" }
    '161f' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4" }
    '15d6' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4" }
    '15d7' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4" }
    '162e' = @{ Name = "Rembrandt USB4/Thunderbolt NHI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4/TB" }
    '162f' = @{ Name = "Rembrandt USB4/Thunderbolt NHI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4/TB" }
    '15c4' = @{ Name = "Phoenix USB4/Thunderbolt NHI controller"; Platform = "Ryzen 7040 Mobile (Zen 4)"; USB = "USB4/TB" }
    '15c5' = @{ Name = "Phoenix USB4/Thunderbolt NHI controller"; Platform = "Ryzen 7040 Mobile (Zen 4)"; USB = "USB4/TB" }
    '1668' = @{ Name = "Pink Sardine USB4/Thunderbolt NHI controller"; Platform = "Pink Sardine"; USB = "USB4/TB" }
    '1669' = @{ Name = "Pink Sardine USB4/Thunderbolt NHI controller"; Platform = "Pink Sardine"; USB = "USB4/TB" }
    '1639' = @{ Name = "Renoir/Cezanne USB 3.1"; Platform = "Ryzen 4000/5000 APU (Zen 2/3)"; USB = "USB 3.1" }
    '15e0' = @{ Name = "Raven USB 3.1"; Platform = "Ryzen 2000 APU (Zen)"; USB = "USB 3.1" }
    '15e1' = @{ Name = "Raven USB 3.1"; Platform = "Ryzen 2000 APU (Zen)"; USB = "USB 3.1" }
    '15e5' = @{ Name = "Raven2 USB 3.1"; Platform = "Ryzen 3000 APU (Zen+)"; USB = "USB 3.1" }
    '149c' = @{ Name = "Matisse USB 3.0 Host Controller"; Platform = "Ryzen 3000/5000 Desktop (Zen 2/3)"; USB = "USB 3.0" }
    '148c' = @{ Name = "Starship USB 3.0 Host Controller"; Platform = "EPYC Rome / Threadripper 3rd Gen"; USB = "USB 3.0" }
    '145f' = @{ Name = "Zeppelin USB 3.0 xHCI Compliant Host Controller"; Platform = "Ryzen 1000 (Zen)"; USB = "USB 3.0" }
    '145c' = @{ Name = "Family 17h USB 3.0 Host Controller"; Platform = "Ryzen 1000 (Zen)"; USB = "USB 3.0" }
    '162c' = @{ Name = "VanGogh USB2"; Platform = "Steam Deck (Van Gogh)"; USB = "USB 2.0" }
    '163a' = @{ Name = "VanGogh USB0"; Platform = "Steam Deck (Van Gogh)"; USB = "USB 3.1" }
    '163b' = @{ Name = "VanGogh USB1"; Platform = "Steam Deck (Van Gogh)"; USB = "USB 3.1" }
    '15d4' = @{ Name = "FireFlight USB 3.1"; Platform = "FireFlight"; USB = "USB 3.1" }
    '15d5' = @{ Name = "FireFlight USB 3.1"; Platform = "FireFlight"; USB = "USB 3.1" }
    '13ed' = @{ Name = "Ariel USB 3.1 Type C (Gen2 + DP Alt)"; Platform = "Ariel"; USB = "USB 3.1 Gen 2" }
    '13ee' = @{ Name = "Ariel USB 3.1 Type A (Gen2 x 2 ports)"; Platform = "Ariel"; USB = "USB 3.1 Gen 2" }
    '1557' = @{ Name = "Turin USB 3.1 xHCI"; Platform = "EPYC Turin"; USB = "USB 3.1" }
}

$AmdChipset = @{
    '43fc' = @{ Name = "800 Series Chipset USB 3.x XHCI Controller"; Platform = "X870/B850 (AM5)"; USB = "USB 3.2" }
    '43fd' = @{ Name = "800 Series Chipset USB 3.x XHCI Controller"; Platform = "X870/B850 (AM5)"; USB = "USB 3.2" }
    '43f7' = @{ Name = "600 Series Chipset USB 3.2 Controller"; Platform = "X670/B650 (AM5)"; USB = "USB 3.2" }
    '43ee' = @{ Name = "500 Series Chipset USB 3.1 XHCI Controller"; Platform = "X570/B550 (AM4)"; USB = "USB 3.1" }
    '43ec' = @{ Name = "A520 Series Chipset USB 3.1 XHCI Controller"; Platform = "A520 (AM4)"; USB = "USB 3.1" }
    '43d5' = @{ Name = "400 Series Chipset USB 3.1 xHCI Compliant Host Controller"; Platform = "X470/B450 (AM4)"; USB = "USB 3.1" }
    '43b9' = @{ Name = "X370 Series Chipset USB 3.1 xHCI Controller"; Platform = "X370 (AM4)"; USB = "USB 3.1" }
    '43ba' = @{ Name = "X399 Series Chipset USB 3.1 xHCI Controller"; Platform = "X399 (Threadripper)"; USB = "USB 3.1" }
    '43bb' = @{ Name = "300 Series Chipset USB 3.1 xHCI Controller"; Platform = "B350 (AM4)"; USB = "USB 3.1" }
    '43bc' = @{ Name = "A320 USB 3.1 XHCI Host Controller"; Platform = "A320 (AM4)"; USB = "USB 3.1" }
    '7814' = @{ Name = "FCH USB XHCI Controller"; Platform = "Legacy FCH"; USB = "USB 3.0" }
    '7812' = @{ Name = "FCH USB XHCI Controller"; Platform = "Legacy FCH"; USB = "USB 3.0" }
}

$ThirdParty = @{
    '1b21:1042' = @{ Name = "ASM1042 SuperSpeed USB Host Controller"; Platform = "ASMedia"; USB = "USB 3.0 (5Gbps)" }
    '1b21:1142' = @{ Name = "ASM1042A USB 3.0 Host Controller"; Platform = "ASMedia"; USB = "USB 3.0 (5Gbps)" }
    '1b21:1242' = @{ Name = "ASM1142 USB 3.1 Host Controller"; Platform = "ASMedia"; USB = "USB 3.1 Gen 2 (10Gbps)" }
    '1b21:1343' = @{ Name = "ASM1143 USB 3.1 Host Controller"; Platform = "ASMedia"; USB = "USB 3.1 Gen 2 (10Gbps)" }
    '1b21:2142' = @{ Name = "ASM2142/ASM3142 USB 3.1 Host Controller"; Platform = "ASMedia"; USB = "USB 3.1 Gen 2 (10Gbps)" }
    '1b21:3042' = @{ Name = "ASM3042 USB 3.2 Gen 1 xHCI Controller"; Platform = "ASMedia"; USB = "USB 3.2 Gen 1 (5Gbps)" }
    '1b21:3142' = @{ Name = "ASM3142 USB 3.2 Gen 2x1 xHCI Controller"; Platform = "ASMedia"; USB = "USB 3.2 Gen 2 (10Gbps)" }
    '1b21:3242' = @{ Name = "ASM3242 USB 3.2 Host Controller"; Platform = "ASMedia"; USB = "USB 3.2 Gen 2x2 (20Gbps)" }
    '1b21:2425' = @{ Name = "ASM4242 USB 4 / Thunderbolt 3 Host Router"; Platform = "ASMedia"; USB = "USB4/TB3 (40Gbps)" }
    '1b21:2426' = @{ Name = "ASM4242 USB 3.2 xHCI Controller"; Platform = "ASMedia"; USB = "USB 3.2" }
    '1106:3483' = @{ Name = "VL805/806 xHCI USB 3.0 Controller"; Platform = "VIA"; USB = "USB 3.0 (5Gbps)" }
    '1106:3432' = @{ Name = "VL800/801 xHCI USB 3.0 Controller"; Platform = "VIA"; USB = "USB 3.0 (5Gbps)" }
    '1b73:1000' = @{ Name = "FL1000G USB 3.0 Host Controller"; Platform = "Fresco Logic"; USB = "USB 3.0 (5Gbps)" }
    '1b73:1009' = @{ Name = "FL1009 USB 3.0 Host Controller"; Platform = "Fresco Logic"; USB = "USB 3.0 (5Gbps)" }
    '1b73:1100' = @{ Name = "FL1100 USB 3.0 Host Controller"; Platform = "Fresco Logic"; USB = "USB 3.0 (5Gbps)" }
    '1b73:1400' = @{ Name = "FL1400 USB 3.0 Host Controller"; Platform = "Fresco Logic"; USB = "USB 3.0 (5Gbps)" }
    '1b6f:7023' = @{ Name = "EJ168 USB 3.0 Host Controller"; Platform = "Etron"; USB = "USB 3.0 (5Gbps)" }
    '1b6f:7052' = @{ Name = "EJ188/EJ198 USB 3.0 Host Controller"; Platform = "Etron"; USB = "USB 3.0 (5Gbps)" }
    '1912:0014' = @{ Name = "uPD720201 USB 3.0 Host Controller"; Platform = "Renesas"; USB = "USB 3.0 (5Gbps)" }
    '1912:0015' = @{ Name = "uPD720202 USB 3.0 Host Controller"; Platform = "Renesas"; USB = "USB 3.0 (5Gbps)" }
}

# =============================================================================
# 拓扑识别与 PnP 采集层
# =============================================================================

function Get-ControllerInfo {
    param([string]$Vid, [string]$Did)

    $vendorId = $Vid.ToLowerInvariant()
    $deviceId = $Did.ToLowerInvariant()
    $entry = $null
    $kind = 'UNKNOWN'

    if ($vendorId -eq $VendorIntel) {
        if ($IntelCpuIntegrated.ContainsKey($deviceId)) { $entry = $IntelCpuIntegrated[$deviceId]; $kind = 'CPU' }
        elseif ($IntelPch.ContainsKey($deviceId)) { $entry = $IntelPch[$deviceId]; $kind = 'CHIPSET' }
        elseif ($IntelThunderbolt.ContainsKey($deviceId)) { $entry = $IntelThunderbolt[$deviceId]; $kind = 'TB' }
    } elseif ($vendorId -eq $VendorAmd) {
        if ($AmdCpuIntegrated.ContainsKey($deviceId)) { $entry = $AmdCpuIntegrated[$deviceId]; $kind = 'CPU' }
        elseif ($AmdChipset.ContainsKey($deviceId)) { $entry = $AmdChipset[$deviceId]; $kind = 'CHIPSET' }
    }

    $key = "${vendorId}:${deviceId}"
    if ($ThirdParty.ContainsKey($key)) {
        $entry = $ThirdParty[$key]
        $kind = 'ADDON'
    }

    $idSuffix = if ($vendorId -or $deviceId) { " ($vendorId`:$deviceId)" } else { '' }
    return @{
        Type     = $kind
        Name     = if ($entry) { $entry.Name } else { "未知 USB 控制器$idSuffix" }
        Platform = if ($entry -and $entry.Platform) { $entry.Platform } else { '未知平台' }
        USB      = if ($entry) { $entry.USB } else { '未知规格' }
    }
}

function Test-RootHub {
    param($Node)
    return ($Node.InstanceId -match '^USB\\ROOT_HUB[^\\]*\\')
}

function Test-UsbHub {
    param($Node)
    $isHubService = $Node.Service -match '^(USBHUB|USBHUB3)$'
    $hasHubClass  = @($Node.CompatibleIds -match '^USB\\Class_09(?:&|$)').Count -gt 0
    return ((Test-RootHub $Node) -or $isHubService -or $hasHubClass)
}

function Test-UsbController {
    param($Node)
    $isHostService = $Node.Service -match '^(USBXHCI|USBEHCI|USBOHCI|USBUHCI)$'
    $hasHostClass  = @($Node.CompatibleIds -match '^PCI\\CC_0C03(00|10|20|30|80)(?:&|$)').Count -gt 0
    return ($isHostService -or $hasHostClass)
}

function Test-HidInputCollection {
    param($Node)

    if ($Node.Class -in @('Mouse', 'Keyboard')) { return $true }
    if ($Node.Service -in @('mouhid', 'kbdhid')) { return $true }

    $hwIds = @($Node.HardwareIds | Where-Object { $_ })
    if ($hwIds.Count -eq 0) { return $true }

    # 匹配鼠标/键盘/手柄摇杆/模拟控制器(方向盘踏板)/触控数位板，排除主板 RGB 灯控等纯厂商自定义 HID (FF00-FFFF)
    $realInputPattern = '^(HID_DEVICE_SYSTEM_(MOUSE|KEYBOARD|GAME)|HID_DEVICE_UP:0001_U:000[1245678]|HID_DEVICE_UP:0002_|HID_DEVICE_UP:000D_)'
    return (@($hwIds -match $realInputPattern).Count -gt 0)
}

function Test-UsbInputNode {
    param($Node, [hashtable]$HidChildrenByParent = @{})

    $isXboxDevice = $Node.Class -in @('XboxComposite', 'XnaComposite', 'XUSBClass')
    if ($isXboxDevice) { return $true }

    $isUsbNode = $Node.InstanceId -match '^USB\\'
    if ($isUsbNode) {
        if ($HidChildrenByParent.ContainsKey($Node.InstanceId)) { return $false }

        $hasHidClass = @($Node.CompatibleIds -match '^USB\\Class_03(?:&|$)').Count -gt 0
        return ($Node.Service -eq 'HidUsb' -or $hasHidClass)
    }

    $isUsbHidNode   = $Node.InstanceId -match '^HID\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}'
    $hasValidParent = (-not $Node.ParentId) -or ($Node.ParentId -match '^(USB|HID)\\')
    if ($isUsbHidNode -and $hasValidParent) {
        return (Test-HidInputCollection $Node)
    }

    return $false
}

function Get-PnpNodes {
    $ProgressPreference = 'SilentlyContinue'
    $nodes = @{}

    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object {
        $_.InstanceId -match '^(USB|HID|PCI)\\' -or $_.Class -in @('USB', 'XboxComposite', 'XnaComposite', 'XUSBClass')
    })
    if ($devices.Count -eq 0) { return $nodes }

    $keys = @(
        'DEVPKEY_Device_Parent'
        'DEVPKEY_Device_Service'
        'DEVPKEY_Device_CompatibleIds'
        'DEVPKEY_Device_HardwareIds'
        'DEVPKEY_Device_BusReportedDeviceDesc'
    )

    # ThrottleLimit 1 避免多会话 CIM 并发丢失属性，单次批量查询约 0.4s
    $propsById = @{}
    $allProps = @(Get-PnpDeviceProperty -InstanceId @($devices.InstanceId) -KeyName $keys -ThrottleLimit 1 -ErrorAction SilentlyContinue)
    foreach ($prop in $allProps) {
        if (-not $propsById.ContainsKey($prop.InstanceId)) { $propsById[$prop.InstanceId] = @{} }
        $propsById[$prop.InstanceId][$prop.KeyName] = $prop.Data
    }

    foreach ($device in $devices) {
        $values = if ($propsById.ContainsKey($device.InstanceId)) { $propsById[$device.InstanceId] } else { @{} }
        $nodes[$device.InstanceId] = @{
            InstanceId     = $device.InstanceId
            FriendlyName   = [string]$device.FriendlyName
            Class          = [string]$device.Class
            Status         = [string]$device.Status
            ParentId       = [string]$values['DEVPKEY_Device_Parent']
            Service        = [string]$values['DEVPKEY_Device_Service']
            CompatibleIds  = @($values['DEVPKEY_Device_CompatibleIds'])
            HardwareIds    = @($values['DEVPKEY_Device_HardwareIds'])
            BusDescription = [string]$values['DEVPKEY_Device_BusReportedDeviceDesc']
        }
    }

    return $nodes
}

function Format-HubName {
    param($Node)

    $friendly = ([string]$Node.FriendlyName).Trim()
    $busDesc  = ([string]$Node.BusDescription).Trim()

    if ($busDesc -and $friendly -and $busDesc -ne $friendly) {
        return "$busDesc ($friendly)"
    }
    if ($busDesc) { return $busDesc }
    if ($friendly) { return $friendly }
    return 'USB 集线器'
}

function Get-DeviceChain {
    param([string]$InstanceId, [hashtable]$Nodes)

    $result = @{
        ControllerInstanceId = ''
        ControllerInfo       = $null
        PhysicalInstanceId   = $InstanceId
        HubCount             = 0
        HubNames             = @()
        Complete             = $false
        ChipCount            = $null
    }

    $visited = @{}
    $physicalFound = $false
    $classificationKnown = $true
    $currentId = $InstanceId

    while ($currentId -and $Nodes.ContainsKey($currentId) -and -not $visited.ContainsKey($currentId)) {
        $visited[$currentId] = $true
        $node = $Nodes[$currentId]

        if (Test-RootHub $node) {
            if ($node.ParentId -and $Nodes.ContainsKey($node.ParentId)) {
                $ctrlNode = $Nodes[$node.ParentId]
                $result.ControllerInstanceId = $ctrlNode.InstanceId
                $vid = if ($ctrlNode.InstanceId -match 'VEN_([0-9A-F]{4})') { $Matches[1] } else { '' }
                $did = if ($ctrlNode.InstanceId -match 'DEV_([0-9A-F]{4})') { $Matches[1] } else { '' }
                $result.ControllerInfo = Get-ControllerInfo -Vid $vid -Did $did
                $result.Complete = $classificationKnown
            }
            break
        }

        $isKnownNode     = [bool]($node.Service -or ($node.CompatibleIds -join ''))
        $isUsbDeviceNode = $node.InstanceId -match '^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}'
        $isInterfaceNode = $node.InstanceId -match '^USB\\[^\\]*&MI_[0-9A-F]{2}(?:&|\\)'

        if (Test-UsbHub $node) {
            $result.HubCount++
            $result.HubNames += (Format-HubName $node)
        } elseif ($isUsbDeviceNode) {
            if (-not $isKnownNode) { $classificationKnown = $false }
            # 复合接口合并到所属物理 USB 设备，同型号多台物理设备按各自实例保留
            if (-not $physicalFound -and -not $isInterfaceNode) {
                if ($isKnownNode) { $result.PhysicalInstanceId = $node.InstanceId }
                $physicalFound = $true
            }
        }

        $currentId = $node.ParentId
    }

    if ($result.Complete -and $result.ControllerInfo) {
        if ($result.ControllerInfo.Type -eq 'CPU') {
            $result.ChipCount = $result.HubCount
        } elseif ($result.ControllerInfo.Type -in @('CHIPSET', 'TB', 'ADDON')) {
            $result.ChipCount = 1 + $result.HubCount
        }
    }

    return $result
}

# =============================================================================
# 系统设置读取与优化层
# =============================================================================

function Get-RegistryFlag {
    param([string]$Path, [string]$Name)

    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }

    $value = $item.$Name
    if ($value -is [int] -and $value -in @(0, 1)) { return ($value -eq 1) }
    return $null
}

function Get-SystemUsbSuspend {
    $output = & powercfg.exe /query SCHEME_CURRENT $UsbPowerSubgroup $UsbSuspendSetting 2>&1
    if ($LASTEXITCODE -ne 0) { return @{ AC = $null; DC = $null } }

    $indices = [regex]::Matches(($output -join "`n"), '(?im)0x([0-9a-f]{8})\s*$')
    if ($indices.Count -ne 2) { return @{ AC = $null; DC = $null } }

    $ac = [Convert]::ToInt32($indices[0].Groups[1].Value, 16)
    $dc = [Convert]::ToInt32($indices[1].Groups[1].Value, 16)
    if ($ac -in @(0, 1) -and $dc -in @(0, 1)) {
        return @{ AC = ($ac -eq 1); DC = ($dc -eq 1) }
    }

    return @{ AC = $null; DC = $null }
}

function Invoke-UsbPowerCfg {
    param([string[]]$Arguments)

    $output = & powercfg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg 失败（退出码 $LASTEXITCODE）：$($output -join ' ')"
    }
}

function Apply-Optimization {
    param($Opt)

    try {
        switch ($Opt.Type) {
            'MSI' {
                $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($Opt.Controller)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                if (-not (Test-Path -LiteralPath $path)) {
                    New-Item -Path $path -Force -ErrorAction Stop | Out-Null
                }
                Set-ItemProperty -LiteralPath $path -Name MSISupported -Value 1 -Type DWord -Force -ErrorAction Stop
            }
            'Suspend' {
                $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($Opt.Controller)\Device Parameters"
                Set-ItemProperty -LiteralPath $path -Name SelectiveSuspendEnabled -Value 0 -Type DWord -Force -ErrorAction Stop
            }
            'SystemSuspend' {
                Invoke-UsbPowerCfg -Arguments @('/setacvalueindex', 'SCHEME_CURRENT', $UsbPowerSubgroup, $UsbSuspendSetting, '0')
                Invoke-UsbPowerCfg -Arguments @('/setdcvalueindex', 'SCHEME_CURRENT', $UsbPowerSubgroup, $UsbSuspendSetting, '0')
                Invoke-UsbPowerCfg -Arguments @('/setactive', 'SCHEME_CURRENT')
            }
            default { throw "未知优化类型：$($Opt.Type)" }
        }

        Write-Host "  [成功] $($Opt.Desc) - $($Opt.Name)" -ForegroundColor Green
        if ($Opt.Type -ne 'SystemSuspend') {
            Write-Host '  ! 请重启电脑使控制器设置生效。' -ForegroundColor Yellow
        }
        return $true
    } catch {
        Write-Host "  [失败] $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-UsbData {
    $nodes = Get-PnpNodes
    $data = @{
        Controllers      = @()
        Devices          = @()
        Optimizations    = @()
        HasCpuController = $false
        DirectInputCount = 0
        SystemSuspend    = Get-SystemUsbSuspend
    }

    $controllerIds = @{}
    foreach ($node in $nodes.Values) {
        if (Test-UsbController $node) {
            $controllerIds[$node.InstanceId] = $true
        }
        if ((Test-RootHub $node) -and $node.ParentId -and $nodes.ContainsKey($node.ParentId)) {
            $controllerIds[$nodes[$node.ParentId].InstanceId] = $true
        }
    }

    $typeOrder = @{ 'CPU' = 0; 'CHIPSET' = 1; 'TB' = 2; 'ADDON' = 3; 'UNKNOWN' = 4 }
    $controllers = @()
    foreach ($controllerId in @($controllerIds.Keys | Sort-Object)) {
        $node = $nodes[$controllerId]
        $vid  = if ($controllerId -match 'VEN_([0-9A-F]{4})') { $Matches[1] } else { '' }
        $did  = if ($controllerId -match 'DEV_([0-9A-F]{4})') { $Matches[1] } else { '' }
        $info = Get-ControllerInfo -Vid $vid -Did $did

        $basePath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$controllerId\Device Parameters"
        $msi      = Get-RegistryFlag -Path "$basePath\Interrupt Management\MessageSignaledInterruptProperties" -Name MSISupported
        $suspend  = Get-RegistryFlag -Path $basePath -Name SelectiveSuspendEnabled

        $controllers += @{
            InstanceId       = $controllerId
            Vid              = $vid
            Did              = $did
            Info             = $info
            Status           = $node.Status
            Msi              = $msi
            SelectiveSuspend = $suspend
            Devices          = @()
            SortOrder        = $typeOrder[$info.Type]
        }

        if ($info.Type -eq 'CPU') { $data.HasCpuController = $true }
        if ($node.Status -eq 'OK') {
            if ($controllerId -match '^PCI\\' -and $msi -eq $false) {
                $data.Optimizations += @{ Type = 'MSI'; Controller = $controllerId; Name = $info.Name; Desc = '启用 MSI 中断' }
            }
            if ($suspend -eq $true) {
                $data.Optimizations += @{ Type = 'Suspend'; Controller = $controllerId; Name = $info.Name; Desc = '关闭控制器选择性挂起' }
            }
        }
    }
    $data.Controllers = @($controllers | Sort-Object { $_.SortOrder }, { $_.InstanceId })

    $acEnabled = ($data.SystemSuspend.AC -eq $true)
    $dcEnabled = ($data.SystemSuspend.DC -eq $true)
    if ($acEnabled -or $dcEnabled) {
        $scopeLabel = if ($acEnabled -and $dcEnabled) { '当前电源计划（插电与电池）' }
            elseif ($acEnabled) { '当前电源计划（插电模式）' }
            else { '当前电源计划（仅电池模式未关，台式机可忽略）' }
        $data.Optimizations += @{ Type = 'SystemSuspend'; Name = $scopeLabel; Desc = '关闭电源计划 USB 选择性挂起' }
    }

    $hidChildrenByParent = @{}
    foreach ($node in $nodes.Values) {
        if ($node.InstanceId -match '^HID\\' -and $node.ParentId) {
            if (-not $hidChildrenByParent.ContainsKey($node.ParentId)) {
                $hidChildrenByParent[$node.ParentId] = @()
            }
            $hidChildrenByParent[$node.ParentId] += $node
        }
    }

    $physicalDevices = @{}
    $inputNodes = @($nodes.Values | Where-Object { Test-UsbInputNode $_ $hidChildrenByParent } | Sort-Object { $_.InstanceId })
    foreach ($node in $inputNodes) {
        $chain = Get-DeviceChain -InstanceId $node.InstanceId -Nodes $nodes
        $identity = $chain.PhysicalInstanceId
        if ($physicalDevices.ContainsKey($identity)) { continue }

        $physical = $nodes[$identity]
        $busDesc  = if ($physical) { $physical.BusDescription.Trim() } else { '' }
        $physName = if ($physical) { $physical.FriendlyName.Trim() } else { '' }
        $nodeName = $node.FriendlyName.Trim()

        $name = if ($busDesc) { $busDesc }
            elseif ($physName) { $physName }
            elseif ($nodeName) { $nodeName }
            else { '未命名 USB 输入设备' }

        $vid = ''; $pidVal = ''
        if ($identity -match 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
            $vid = $Matches[1]; $pidVal = $Matches[2]
        }

        $status = if ($node.Status -ne 'OK') { $node.Status }
            elseif ($physical -and $physical.Status) { $physical.Status }
            else { 'OK' }

        $physicalDevices[$identity] = @{
            Name       = $name
            InstanceId = $identity
            Vid        = $vid
            Pid        = $pidVal
            Chain      = $chain
            Status     = $status
        }
    }

    $data.Devices = @($physicalDevices.Values | Sort-Object {
        if ($null -eq $_.Chain.ChipCount) { $UnrankedChipOrder } else { [int]$_.Chain.ChipCount }
    }, { $_.Name })

    foreach ($controller in $data.Controllers) {
        $controller.Devices = @($data.Devices | Where-Object { $_.Chain.ControllerInstanceId -eq $controller.InstanceId })
    }
    $data.DirectInputCount = @($data.Devices | Where-Object { $_.Chain.ChipCount -eq 0 }).Count

    return $data
}

# =============================================================================
# 终端展示与交互层
# =============================================================================

function Get-Palette {
    $useAnsi = $Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected
    if (-not $useAnsi) {
        return @{ Mint = ''; Orange = ''; Coral = ''; Sky = ''; Dim = ''; Border = ''; White = ''; Bold = ''; Reset = '' }
    }

    $e = [char]27
    return @{
        Mint   = "$e[38;2;0;255;135m"
        Orange = "$e[38;2;255;179;71m"
        Coral  = "$e[38;2;255;107;107m"
        Sky    = "$e[38;2;135;206;235m"
        Dim    = "$e[38;2;120;120;120m"
        Border = "$e[38;2;74;74;74m"
        White  = "$e[97m"
        Bold   = "$e[1m"
        Reset  = "$e[0m"
    }
}

function Format-SettingState {
    param($Value)
    if ($null -eq $Value) { return '未读取' }
    if ($Value) { return '已启用' }
    return '已禁用'
}

function Get-DeviceHopTag {
    param($Chain)

    if (-not $Chain.Complete) { return '路径不完整' }

    if ($Chain.HubCount -eq 0) {
        switch ($Chain.ControllerInfo.Type) {
            'CPU'     { return 'CPU 直连' }
            'CHIPSET' { return '经主板芯片组' }
            'TB'      { return '经雷电控制器' }
            'ADDON'   { return '经第三方控制器' }
            default   { return '未知控制器' }
        }
    }

    $ctrlLabel = switch ($Chain.ControllerInfo.Type) {
        'CPU'     { 'CPU 控制器' }
        'CHIPSET' { '主板芯片组' }
        'TB'      { '雷电控制器' }
        'ADDON'   { '第三方控制器' }
        default   { '未知控制器' }
    }
    return "$ctrlLabel + $($Chain.HubCount) 级集线器"
}

function Show-Tree {
    param($Data)
    $c = Get-Palette

    Write-Host ''
    Write-Host "  $($c.Dim)设备到 CPU 之间经过的芯片越少，传输链路越短：$($c.Reset)"
    Write-Host ''
    Write-Host "  $($c.Mint)$($c.Bold)0 芯片$($c.Reset)  设备 $($c.Mint)---$($c.Reset) [CPU]                    $($c.Dim)(CPU 直连，最佳)$($c.Reset)"
    Write-Host "  $($c.Orange)$($c.Bold)1 芯片$($c.Reset)  设备 -$($c.Orange)[芯片组/集线器]$($c.Reset)- [CPU]       $($c.Dim)(经主板芯片组或 1 级集线器)$($c.Reset)"
    Write-Host "  $($c.Coral)$($c.Bold)2+芯片$($c.Reset)  设备 -$($c.Coral)[集线器]$($c.Reset)-$($c.Coral)[芯片组]$($c.Reset)- [CPU]     $($c.Dim)(经多级集线器/扩展坞)$($c.Reset)"
    Write-Host ''
    Write-Host "  $($c.Border)=====================================================================$($c.Reset)"
    Write-Host ''

    if ($Data.Devices.Count -eq 0) {
        Write-Host "  $($c.Dim)未检测到 USB 输入设备（鼠标 / 键盘 / 手柄）$($c.Reset)"
        Write-Host ''
        return
    }

    $chip0   = @($Data.Devices | Where-Object { $_.Chain.ChipCount -eq 0 })
    $chip1   = @($Data.Devices | Where-Object { $_.Chain.ChipCount -eq 1 })
    $chip2   = @($Data.Devices | Where-Object { $null -ne $_.Chain.ChipCount -and $_.Chain.ChipCount -ge 2 })
    $unknown = @($Data.Devices | Where-Object { $null -eq $_.Chain.ChipCount })

    if ($chip0.Count -eq 0) {
        if ($Data.HasCpuController) {
            Write-Host "  $($c.Orange)! 检测到 CPU 控制器，但当前没有输入设备处于 0 芯片直连状态$($c.Reset)"
            Write-Host "  $($c.Dim)  提示：部分主板接口会经过板载集线器或芯片组；可换插背板其他 USB 口后按 R 重扫对比$($c.Reset)"
        } else {
            Write-Host "  $($c.Orange)! 当前平台无独立识别的 CPU 直连控制器，1 芯片即为最佳端口$($c.Reset)"
        }
        Write-Host ''
    }

    $groups = @(
        @{ List = $chip0;   Color = $c.Mint;   Title = '0 芯片 - 直连 CPU' }
        @{ List = $chip1;   Color = $c.Orange; Title = '1 芯片 - 经芯片组 / 单级集线器' }
        @{ List = $chip2;   Color = $c.Coral;  Title = '2+ 芯片 - 经多级芯片 / 集线器' }
        @{ List = $unknown; Color = $c.Dim;    Title = '未知控制器或路径不完整' }
    )

    foreach ($group in $groups) {
        if ($group.List.Count -eq 0) { continue }
        Write-Host "  $($group.Color)$($group.Title)$($c.Reset)"
        for ($i = 0; $i -lt $group.List.Count; $i++) {
            $dev = $group.List[$i]
            $branch = if ($i -eq $group.List.Count - 1) { "'-" } else { '|-' }
            $tag = Get-DeviceHopTag $dev.Chain
            $statusWarn = if ($dev.Status -ne 'OK') { " $($c.Coral)[异常: $($dev.Status)]$($c.Reset)" } else { '' }
            Write-Host "    $($c.Dim)$branch$($c.Reset) $($group.Color)$($dev.Name)$($c.Reset) $($c.Dim)($tag)$($c.Reset)$statusWarn"
        }
        Write-Host ''
    }
}

function Show-FullAnalysis {
    param($Data)
    $c = Get-Palette

    Write-Host "  $($c.White)$($c.Bold)USB 控制器 ($($Data.Controllers.Count))$($c.Reset)"
    Write-Host "  $($c.Border)---------------------------------------------------------------------$($c.Reset)"

    foreach ($ctrl in $Data.Controllers) {
        $badgeColor = switch ($ctrl.Info.Type) {
            'CPU'     { $c.Mint }
            'CHIPSET' { $c.Orange }
            'TB'      { $c.Sky }
            'ADDON'   { $c.Sky }
            default   { $c.Dim }
        }
        $badgeText = switch ($ctrl.Info.Type) {
            'CPU'     { 'CPU 控制器' }
            'CHIPSET' { '主板芯片组' }
            'TB'      { '雷电控制器' }
            'ADDON'   { '第三方控制器' }
            default   { '未知控制器' }
        }

        Write-Host ''
        Write-Host "  $badgeColor[$badgeText]$($c.Reset) $($c.White)$($ctrl.Info.Name)$($c.Reset)"
        Write-Host "      $($c.Dim)VID:$($ctrl.Vid) DID:$($ctrl.Did) | $($ctrl.Info.Platform) | $($ctrl.Info.USB)$($c.Reset)"

        $flags = @()
        if ($null -ne $ctrl.Msi) {
            $flags += if ($ctrl.Msi) { "中断: $($c.Mint)MSI$($c.Reset)" } else { "中断: $($c.Coral)传统线中断 (可优化)$($c.Reset)" }
        }
        if ($null -ne $ctrl.SelectiveSuspend) {
            $flags += if ($ctrl.SelectiveSuspend) { "挂起: $($c.Orange)已启用 (可优化)$($c.Reset)" } else { "挂起: $($c.Mint)已禁用$($c.Reset)" }
        }
        if ($flags.Count -gt 0) {
            Write-Host "      $($flags -join '  |  ')"
        }
        if ($ctrl.Status -ne 'OK') {
            Write-Host "      $($c.Coral)! 控制器状态异常: $($ctrl.Status)$($c.Reset)"
        }

        if ($ctrl.Devices.Count -gt 0) {
            for ($i = 0; $i -lt $ctrl.Devices.Count; $i++) {
                $dev = $ctrl.Devices[$i]
                $branch = if ($i -eq $ctrl.Devices.Count - 1) { "'-" } else { '|-' }
                $hubInfo = if ($dev.Chain.HubCount -gt 0) { " $($c.Orange)(+$($dev.Chain.HubCount) 级集线器)$($c.Reset)" } else { '' }
                Write-Host "      $($c.Dim)$branch$($c.Reset) $($dev.Name)$hubInfo"
            }
        } else {
            Write-Host "      $($c.Dim)(无输入设备连接)$($c.Reset)"
        }
    }

    Write-Host ''
    Write-Host "  $($c.White)$($c.Bold)输入设备详情 ($($Data.Devices.Count))$($c.Reset)"
    Write-Host "  $($c.Border)---------------------------------------------------------------------$($c.Reset)"

    if ($Data.Devices.Count -eq 0) {
        Write-Host ''
        Write-Host "  $($c.Dim)未检测到 USB 输入设备$($c.Reset)"
    } else {
        foreach ($dev in $Data.Devices) {
            $hopColor = switch ($dev.Chain.ChipCount) {
                0 { $c.Mint }
                1 { $c.Orange }
                default { if ($null -eq $dev.Chain.ChipCount) { $c.Dim } else { $c.Coral } }
            }
            $hopPrefix = if ($null -eq $dev.Chain.ChipCount) { '' } else { "$($dev.Chain.ChipCount) 芯片 · " }
            $idLabel = if ($dev.Vid) { "VID:$($dev.Vid) PID:$($dev.Pid)" } else { $dev.InstanceId }

            Write-Host ''
            Write-Host "  $($c.White)$($dev.Name)$($c.Reset) $($c.Dim)($idLabel)$($c.Reset)"
            Write-Host "      $hopColor$hopPrefix$(Get-DeviceHopTag $dev.Chain)$($c.Reset)"
            if ($dev.Chain.ControllerInfo) {
                Write-Host "      $($c.Dim)控制器: $($dev.Chain.ControllerInfo.Name)$($c.Reset)"
            }
            if ($dev.Chain.HubNames.Count -gt 0) {
                Write-Host "      $($c.Dim)集线器: $($dev.Chain.HubNames -join ' -> ')$($c.Reset)"
            }
            if ($dev.Status -ne 'OK') {
                Write-Host "      $($c.Coral)! 设备状态: $($dev.Status)$($c.Reset)"
            }
        }
    }

    Write-Host ''
    Write-Host "  $($c.Border)---------------------------------------------------------------------$($c.Reset)"
    $acText = Format-SettingState $Data.SystemSuspend.AC
    $dcText = Format-SettingState $Data.SystemSuspend.DC
    Write-Host "  $($c.Dim)电源计划 USB 选择性挂起:$($c.Reset) 插电 [$acText] | 电池 [$dcText]"
    Write-Host ''
}

function Test-Administrator {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-UserChoice {
    param([string]$Prompt)
    try {
        return [string](Read-Host $Prompt)
    } catch [Management.Automation.PSInvalidOperationException] {
        # 非交互宿主（如 -NonInteractive）不支持 Read-Host，视同回车退出
        return ''
    }
}

function Show-Optimizations {
    param($Data)
    $c = Get-Palette
    $isAdmin = Test-Administrator
    $hasOpts = ($Data.Optimizations.Count -gt 0)

    if ($hasOpts) {
        Write-Host "  $($c.White)$($c.Bold)可用优化项$($c.Reset)"
        Write-Host "  $($c.Border)---------------------------------------------------------------------$($c.Reset)"
        Write-Host ''
        for ($i = 0; $i -lt $Data.Optimizations.Count; $i++) {
            $opt = $Data.Optimizations[$i]
            $prefix = if ($isAdmin) { "$($c.Sky)[$($i + 1)]$($c.Reset)" } else { "$($c.Dim)-$($c.Reset)" }
            Write-Host "  $prefix $($opt.Desc) $($c.Dim)- $($opt.Name)$($c.Reset)"
        }
        if ($isAdmin -and $Data.Optimizations.Count -gt 1) {
            Write-Host "  $($c.Sky)[A]$($c.Reset) 一键应用以上全部优化"
        }
        if (-not $isAdmin) {
            Write-Host ''
            Write-Host "  $($c.Orange)! 修改系统设置需管理员权限（右键以管理员身份运行 PowerShell）$($c.Reset)"
        }
        Write-Host ''
    } else {
        Write-Host "  $($c.Mint)[OK] 所有可检测的控制器 MSI 与电源挂起设置均已就绪$($c.Reset)"
        Write-Host ''
    }

    $prompt = if ($hasOpts -and $isAdmin) {
        '  输入序号执行优化，[R] 重新扫描，直接回车退出'
    } else {
        '  输入 [R] 重新扫描（换插接口后对比），直接回车退出'
    }

    $choice = (Read-UserChoice $prompt).Trim()
    if (-not $choice) { return 'EXIT' }
    if ($choice -match '^[Rr]$') { return 'RESCAN' }

    if ($hasOpts -and $isAdmin) {
        if ($choice -match '^[Aa]$') {
            foreach ($opt in $Data.Optimizations) { Apply-Optimization -Opt $opt | Out-Null }
            return 'APPLIED'
        }
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $Data.Optimizations.Count) {
            Apply-Optimization -Opt $Data.Optimizations[$number - 1] | Out-Null
            return 'APPLIED'
        }
    }

    if ($hasOpts -and -not $isAdmin) {
        Write-Host "  $($c.Orange)当前非管理员权限，未修改设置。$($c.Reset)"
    } else {
        Write-Host "  $($c.Orange)无效输入，未修改设置。$($c.Reset)"
    }
    return 'DONE'
}

function Invoke-Analyzer {
    $c = Get-Palette
    $useAnsi = ($c.Reset -ne '')

    do {
        Write-Host ''
        Write-Host "  $($c.Sky)$($c.Bold)CPU DIRECT USB · USB 拓扑与直连分析$($c.Reset)"
        Write-Host "  $($c.Border)=====================================================================$($c.Reset)"
        if ($useAnsi) {
            Write-Host "  $($c.Dim)正在扫描 USB 控制器与输入设备...$($c.Reset)" -NoNewline
        }

        $action = 'EXIT'
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $data = Get-UsbData
            $sw.Stop()
            $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 2)

            if ($useAnsi) {
                Write-Host "`r  $($c.Mint)[OK]$($c.Reset) $($c.Dim)扫描完成 (${elapsed}s)                    $($c.Reset)"
            } else {
                Write-Host "  [OK] 扫描完成 (${elapsed}s)"
            }

            Show-Tree -Data $data
            Show-FullAnalysis -Data $data
            $action = Show-Optimizations -Data $data

            if ($action -eq 'APPLIED') {
                $again = (Read-UserChoice '  输入 [R] 重新扫描验证，直接回车退出').Trim()
                if ($again -match '^[Rr]$') { $action = 'RESCAN' }
            }
        } catch {
            Write-Host ''
            Write-Host "  $($c.Coral)[失败] 扫描未完成：$($_.Exception.Message)$($c.Reset)"
            $action = 'EXIT'
        }
    } while ($action -eq 'RESCAN')
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Analyzer
}
