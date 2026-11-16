#requires -Version 5.1
<#
.SYNOPSIS
    USB 连接分析器（简体中文版）
.DESCRIPTION
    扫描 USB 控制器与输入设备，显示连接路径，最后提供可选设置。
    原始项目：MariusHeier/cpu-direct-usb。
#>

# 型号表沿用上游 Linux xhci-pci.c / pci.ids 汇总，未逐条验证主板布线。
# Intel CPU/SoC 控制器（型号参考）
$IntelCpuIntegrated = @{
    '8a13' = @{ Name = "Ice Lake Thunderbolt 3 USB Controller"; Platform = "Ice Lake (10th Gen)"; USB = "USB 3.2/TB3"; Year = "2019" }
    '9a13' = @{ Name = "Tiger Lake-LP Thunderbolt 4 USB Controller"; Platform = "Tiger Lake (11th Gen)"; USB = "USB4/TB4"; Year = "2020" }
    '9a17' = @{ Name = "Tiger Lake-H Thunderbolt 4 USB Controller"; Platform = "Tiger Lake-H (11th Gen)"; USB = "USB4/TB4"; Year = "2021" }
    '461e' = @{ Name = "Alder Lake-P Thunderbolt 4 USB Controller"; Platform = "Alder Lake (12th Gen)"; USB = "USB4/TB4"; Year = "2022" }
    '464e' = @{ Name = "Alder Lake-N Processor USB 3.2 xHCI Controller"; Platform = "Alder Lake-N"; USB = "USB 3.2"; Year = "2023" }
    'a71e' = @{ Name = "Raptor Lake-P Thunderbolt 4 USB Controller"; Platform = "Raptor Lake (13th Gen)"; USB = "USB4/TB4"; Year = "2023" }
    '7ec0' = @{ Name = "Meteor Lake-P Thunderbolt 4 USB Controller"; Platform = "Meteor Lake (Core Ultra)"; USB = "USB4/TB4"; Year = "2024" }
    'a831' = @{ Name = "Lunar Lake-M Thunderbolt 4 USB Controller"; Platform = "Lunar Lake"; USB = "USB4/TB4"; Year = "2024" }
}

# Intel 芯片组控制器（型号参考）
$IntelPch = @{
    '7f6e' = @{ Name = "800 Series PCH USB 3.1 xHCI HC"; Platform = "800 Series PCH"; USB = "USB 3.1"; Year = "2024" }
    '7a60' = @{ Name = "Raptor Lake USB 3.2 Gen 2x2 XHCI Host Controller"; Platform = "700 Series PCH"; USB = "USB 3.2 Gen 2x2 (20Gbps)"; Year = "2023" }
    '7a61' = @{ Name = "Raptor Lake USB 3.2 Gen 1x1 xDCI Device Controller"; Platform = "700 Series PCH"; USB = "USB 3.2 Gen 1"; Year = "2023" }
    '7ae0' = @{ Name = "Alder Lake-S PCH USB 3.2 Gen 2x2 XHCI Controller"; Platform = "600 Series PCH (Desktop)"; USB = "USB 3.2 Gen 2x2 (20Gbps)"; Year = "2021" }
    '51ed' = @{ Name = "Alder Lake PCH USB 3.2 xHCI Host Controller"; Platform = "600 Series PCH"; USB = "USB 3.2"; Year = "2022" }
    '54ed' = @{ Name = "Alder Lake-N PCH USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "Alder Lake-N PCH"; USB = "USB 3.2 Gen 2 (10Gbps)"; Year = "2023" }
    '7e7d' = @{ Name = "Meteor Lake-P USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "Meteor Lake PCH"; USB = "USB 3.2 Gen 2"; Year = "2024" }
    '777d' = @{ Name = "Arrow Lake USB 3.2 xHCI Controller"; Platform = "Arrow Lake"; USB = "USB 3.2"; Year = "2024" }
    'a87d' = @{ Name = "Lunar Lake-M USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "Lunar Lake PCH"; USB = "USB 3.2 Gen 2"; Year = "2024" }
    'a0ed' = @{ Name = "Tiger Lake-LP USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "500 Series PCH"; USB = "USB 3.2 Gen 2 (10Gbps)"; Year = "2020" }
    '43ed' = @{ Name = "Tiger Lake-H USB 3.2 Gen 2x1 xHCI Host Controller"; Platform = "500 Series PCH-H"; USB = "USB 3.2 Gen 2"; Year = "2021" }
    'a3af' = @{ Name = "Comet Lake PCH-V USB Controller"; Platform = "400 Series PCH"; USB = "USB 3.1"; Year = "2020" }
    '02ed' = @{ Name = "Comet Lake PCH-LP USB 3.1 xHCI Host Controller"; Platform = "400 Series PCH-LP"; USB = "USB 3.1"; Year = "2020" }
    '06ed' = @{ Name = "Comet Lake USB 3.1 xHCI Host Controller"; Platform = "400 Series PCH"; USB = "USB 3.1"; Year = "2020" }
    'a36d' = @{ Name = "Cannon Lake PCH USB 3.1 xHCI Host Controller"; Platform = "300 Series PCH"; USB = "USB 3.1"; Year = "2018" }
    '9ded' = @{ Name = "Cannon Point-LP USB 3.1 xHCI Controller"; Platform = "300 Series PCH-LP"; USB = "USB 3.1"; Year = "2018" }
    'a2af' = @{ Name = "200 Series/Z370 Chipset Family USB 3.0 xHCI Controller"; Platform = "200 Series PCH"; USB = "USB 3.0"; Year = "2017" }
    'a12f' = @{ Name = "100 Series/C230 Series Chipset Family USB 3.0 xHCI Controller"; Platform = "100 Series PCH"; USB = "USB 3.0"; Year = "2015" }
    '9d2f' = @{ Name = "Sunrise Point-LP USB 3.0 xHCI Controller"; Platform = "100 Series PCH-LP"; USB = "USB 3.0"; Year = "2015" }
    '8cb1' = @{ Name = "9 Series Chipset Family USB xHCI Controller"; Platform = "9 Series PCH"; USB = "USB 3.0"; Year = "2014" }
    '9cb1' = @{ Name = "Wildcat Point-LP USB xHCI Controller"; Platform = "9 Series PCH-LP"; USB = "USB 3.0"; Year = "2014" }
    '8c31' = @{ Name = "8 Series/C220 Series Chipset Family USB xHCI"; Platform = "8 Series PCH"; USB = "USB 3.0"; Year = "2013" }
    '9c31' = @{ Name = "8 Series USB xHCI HC"; Platform = "8 Series PCH-LP"; USB = "USB 3.0"; Year = "2013" }
    '1e31' = @{ Name = "7 Series/C210 Series Chipset Family USB xHCI Host Controller"; Platform = "7 Series PCH"; USB = "USB 3.0"; Year = "2012" }
    '8d31' = @{ Name = "C610/X99 series chipset USB xHCI Host Controller"; Platform = "X99/C610 (HEDT/Server)"; USB = "USB 3.0"; Year = "2014" }
    'a1af' = @{ Name = "C620 Series Chipset Family USB 3.0 xHCI Controller"; Platform = "C620 (Server)"; USB = "USB 3.0"; Year = "2017" }
}

# Thunderbolt 控制器；型号不能确定 PCIe 上游归属
$IntelThunderbolt = @{
    '5782' = @{ Name = "JHL9580 Thunderbolt 5 USB Controller"; Platform = "Barlow Ridge Host 80G"; USB = "USB4/TB5 (80Gbps)"; Year = "2024" }
    '5785' = @{ Name = "JHL9540 Thunderbolt 4 USB Controller"; Platform = "Barlow Ridge Host 40G"; USB = "USB4/TB4 (40Gbps)"; Year = "2024" }
    '5787' = @{ Name = "JHL9480 Thunderbolt 5 USB Controller"; Platform = "Barlow Ridge Hub 80G"; USB = "USB4/TB5 (80Gbps)"; Year = "2024" }
    '57a5' = @{ Name = "JHL9440 Thunderbolt 4 USB Controller"; Platform = "Barlow Ridge Hub 40G"; USB = "USB4/TB4 (40Gbps)"; Year = "2024" }
    '1138' = @{ Name = "Thunderbolt 4 USB Controller [Maple Ridge 4C]"; Platform = "Maple Ridge 4C"; USB = "USB4/TB4 (40Gbps)"; Year = "2020" }
    '1135' = @{ Name = "Thunderbolt 4 USB Controller [Maple Ridge 2C]"; Platform = "Maple Ridge 2C"; USB = "USB4/TB4 (40Gbps)"; Year = "2020" }
    '0b27' = @{ Name = "Thunderbolt 4 USB Controller [Goshen Ridge]"; Platform = "Goshen Ridge"; USB = "USB4/TB4 (40Gbps)"; Year = "2020" }
    '15e9' = @{ Name = "JHL7540 Thunderbolt 3 USB Controller [Titan Ridge 2C]"; Platform = "Titan Ridge 2C"; USB = "USB 3.1/TB3 (40Gbps)"; Year = "2018" }
    '15ec' = @{ Name = "JHL7540 Thunderbolt 3 USB Controller [Titan Ridge 4C]"; Platform = "Titan Ridge 4C"; USB = "USB 3.1/TB3 (40Gbps)"; Year = "2018" }
    '15f0' = @{ Name = "JHL7440 Thunderbolt 3 USB Controller [Titan Ridge DD]"; Platform = "Titan Ridge DD"; USB = "USB 3.1/TB3 (40Gbps)"; Year = "2018" }
    '15b5' = @{ Name = "DSL6340 USB 3.1 Controller [Alpine Ridge 2C]"; Platform = "Alpine Ridge 2C"; USB = "USB 3.1/TB3 (40Gbps)"; Year = "2015" }
    '15b6' = @{ Name = "DSL6540 USB 3.1 Controller [Alpine Ridge 4C]"; Platform = "Alpine Ridge 4C"; USB = "USB 3.1/TB3 (40Gbps)"; Year = "2015" }
    '15c1' = @{ Name = "JHL6240 Thunderbolt 3 USB 3.1 Controller [Alpine Ridge LP]"; Platform = "Alpine Ridge LP"; USB = "USB 3.1/TB3"; Year = "2016" }
    '15d4' = @{ Name = "JHL6540 Thunderbolt 3 USB Controller [Alpine Ridge 4C]"; Platform = "Alpine Ridge 4C C-step"; USB = "USB 3.1/TB3 (40Gbps)"; Year = "2016" }
    '15db' = @{ Name = "JHL6340 Thunderbolt 3 USB 3.1 Controller [Alpine Ridge 2C]"; Platform = "Alpine Ridge 2C C-step"; USB = "USB 3.1/TB3 (40Gbps)"; Year = "2016" }
}

# AMD CPU/SoC 控制器（型号参考）
$AmdCpuIntegrated = @{
    # Raphael / Granite Ridge (Ryzen 7000/9000)
    '15b6' = @{ Name = "Raphael/Granite Ridge USB 3.1 xHCI"; Platform = "Ryzen 7000/9000 Desktop (AM5)"; USB = "USB 3.1"; Year = "2022" }
    '15b7' = @{ Name = "Raphael/Granite Ridge USB 3.1 xHCI"; Platform = "Ryzen 7000/9000 Desktop (AM5)"; USB = "USB 3.1"; Year = "2022" }
    '15b8' = @{ Name = "Raphael/Granite Ridge USB 2.0 xHCI"; Platform = "Ryzen 7000/9000 Desktop (AM5)"; USB = "USB 2.0"; Year = "2022" }
    # Strix Halo (Zen 5)
    '1587' = @{ Name = "Strix Halo USB 3.1 xHCI"; Platform = "Strix Halo (Zen 5)"; USB = "USB 3.1"; Year = "2024" }
    '1588' = @{ Name = "Strix Halo USB 3.1 xHCI"; Platform = "Strix Halo (Zen 5)"; USB = "USB 3.1"; Year = "2024" }
    '1589' = @{ Name = "Strix Halo USB 3.1 xHCI"; Platform = "Strix Halo (Zen 5)"; USB = "USB 3.1"; Year = "2024" }
    '158b' = @{ Name = "Strix Halo USB 3.1 xHCI"; Platform = "Strix Halo (Zen 5)"; USB = "USB 3.1"; Year = "2024" }
    '158d' = @{ Name = "Strix Halo USB4 Host Router"; Platform = "Strix Halo (Zen 5)"; USB = "USB4"; Year = "2024" }
    '158e' = @{ Name = "Strix Halo USB4 Host Router"; Platform = "Strix Halo (Zen 5)"; USB = "USB4"; Year = "2024" }
    # Rembrandt (Ryzen 6000 Mobile)
    '161a' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4"; Year = "2022" }
    '161b' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4"; Year = "2022" }
    '161c' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4"; Year = "2022" }
    '161d' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4"; Year = "2022" }
    '161e' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4"; Year = "2022" }
    '161f' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4"; Year = "2022" }
    '15d6' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4"; Year = "2022" }
    '15d7' = @{ Name = "Rembrandt USB4 XHCI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4"; Year = "2022" }
    '162e' = @{ Name = "Rembrandt USB4/Thunderbolt NHI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4/TB"; Year = "2022" }
    '162f' = @{ Name = "Rembrandt USB4/Thunderbolt NHI controller"; Platform = "Ryzen 6000 Mobile (Zen 3+)"; USB = "USB4/TB"; Year = "2022" }
    # Phoenix (Ryzen 7040)
    '15c4' = @{ Name = "Phoenix USB4/Thunderbolt NHI controller"; Platform = "Ryzen 7040 Mobile (Zen 4)"; USB = "USB4/TB"; Year = "2023" }
    '15c5' = @{ Name = "Phoenix USB4/Thunderbolt NHI controller"; Platform = "Ryzen 7040 Mobile (Zen 4)"; USB = "USB4/TB"; Year = "2023" }
    '1668' = @{ Name = "Pink Sardine USB4/Thunderbolt NHI controller"; Platform = "Pink Sardine"; USB = "USB4/TB"; Year = "2023" }
    '1669' = @{ Name = "Pink Sardine USB4/Thunderbolt NHI controller"; Platform = "Pink Sardine"; USB = "USB4/TB"; Year = "2023" }
    # Renoir / Cezanne (Ryzen 4000/5000 APU)
    '1639' = @{ Name = "Renoir/Cezanne USB 3.1"; Platform = "Ryzen 4000/5000 APU (Zen 2/3)"; USB = "USB 3.1"; Year = "2020" }
    # Raven Ridge / Picasso (Ryzen 2000/3000 APU)
    '15e0' = @{ Name = "Raven USB 3.1"; Platform = "Ryzen 2000 APU (Zen)"; USB = "USB 3.1"; Year = "2018" }
    '15e1' = @{ Name = "Raven USB 3.1"; Platform = "Ryzen 2000 APU (Zen)"; USB = "USB 3.1"; Year = "2018" }
    '15e5' = @{ Name = "Raven2 USB 3.1"; Platform = "Ryzen 3000 APU (Zen+)"; USB = "USB 3.1"; Year = "2019" }
    # Matisse / Vermeer (Ryzen 3000/5000 Desktop)
    '149c' = @{ Name = "Matisse USB 3.0 Host Controller"; Platform = "Ryzen 3000/5000 Desktop (Zen 2/3)"; USB = "USB 3.0"; Year = "2019" }
    '148c' = @{ Name = "Starship USB 3.0 Host Controller"; Platform = "EPYC Rome / Threadripper 3rd Gen"; USB = "USB 3.0"; Year = "2019" }
    # Zeppelin (Ryzen 1000)
    '145f' = @{ Name = "Zeppelin USB 3.0 xHCI Compliant Host Controller"; Platform = "Ryzen 1000 (Zen)"; USB = "USB 3.0"; Year = "2017" }
    '145c' = @{ Name = "Family 17h USB 3.0 Host Controller"; Platform = "Ryzen 1000 (Zen)"; USB = "USB 3.0"; Year = "2017" }
    # Van Gogh (Steam Deck)
    '162c' = @{ Name = "VanGogh USB2"; Platform = "Steam Deck (Van Gogh)"; USB = "USB 2.0"; Year = "2022" }
    '163a' = @{ Name = "VanGogh USB0"; Platform = "Steam Deck (Van Gogh)"; USB = "USB 3.1"; Year = "2022" }
    '163b' = @{ Name = "VanGogh USB1"; Platform = "Steam Deck (Van Gogh)"; USB = "USB 3.1"; Year = "2022" }
    # Other
    '15d4' = @{ Name = "FireFlight USB 3.1"; Platform = "FireFlight"; USB = "USB 3.1"; Year = "2020" }
    '15d5' = @{ Name = "FireFlight USB 3.1"; Platform = "FireFlight"; USB = "USB 3.1"; Year = "2020" }
    '13ed' = @{ Name = "Ariel USB 3.1 Type C (Gen2 + DP Alt)"; Platform = "Ariel"; USB = "USB 3.1 Gen 2"; Year = "2020" }
    '13ee' = @{ Name = "Ariel USB 3.1 Type A (Gen2 x 2 ports)"; Platform = "Ariel"; USB = "USB 3.1 Gen 2"; Year = "2020" }
    '1557' = @{ Name = "Turin USB 3.1 xHCI"; Platform = "EPYC Turin"; USB = "USB 3.1"; Year = "2024" }
}

# AMD 芯片组控制器（型号参考）
$AmdChipset = @{
    '43fc' = @{ Name = "800 Series Chipset USB 3.x XHCI Controller"; Platform = "X870/B850 (AM5)"; USB = "USB 3.2"; Year = "2024" }
    '43fd' = @{ Name = "800 Series Chipset USB 3.x XHCI Controller"; Platform = "X870/B850 (AM5)"; USB = "USB 3.2"; Year = "2024" }
    '43f7' = @{ Name = "600 Series Chipset USB 3.2 Controller"; Platform = "X670/B650 (AM5)"; USB = "USB 3.2"; Year = "2022" }
    '43ee' = @{ Name = "500 Series Chipset USB 3.1 XHCI Controller"; Platform = "X570/B550 (AM4)"; USB = "USB 3.1"; Year = "2019" }
    '43ec' = @{ Name = "A520 Series Chipset USB 3.1 XHCI Controller"; Platform = "A520 (AM4)"; USB = "USB 3.1"; Year = "2020" }
    '43d5' = @{ Name = "400 Series Chipset USB 3.1 xHCI Compliant Host Controller"; Platform = "X470/B450 (AM4)"; USB = "USB 3.1"; Year = "2018" }
    '43b9' = @{ Name = "X370 Series Chipset USB 3.1 xHCI Controller"; Platform = "X370 (AM4)"; USB = "USB 3.1"; Year = "2017" }
    '43ba' = @{ Name = "X399 Series Chipset USB 3.1 xHCI Controller"; Platform = "X399 (Threadripper)"; USB = "USB 3.1"; Year = "2017" }
    '43bb' = @{ Name = "300 Series Chipset USB 3.1 xHCI Controller"; Platform = "B350 (AM4)"; USB = "USB 3.1"; Year = "2017" }
    '43bc' = @{ Name = "A320 USB 3.1 XHCI Host Controller"; Platform = "A320 (AM4)"; USB = "USB 3.1"; Year = "2017" }
    '7814' = @{ Name = "FCH USB XHCI Controller"; Platform = "Legacy FCH"; USB = "USB 3.0"; Year = "2013" }
    '7812' = @{ Name = "FCH USB XHCI Controller"; Platform = "Legacy FCH"; USB = "USB 3.0"; Year = "2012" }
}

# 第三方控制器；可能板载或外接，上游归属待核实
$ThirdParty = @{
    # ASMedia (VID: 1b21)
    '1b21:1042' = @{ Name = "ASM1042 SuperSpeed USB Host Controller"; Vendor = "ASMedia"; USB = "USB 3.0 (5Gbps)"; Year = "2011" }
    '1b21:1142' = @{ Name = "ASM1042A USB 3.0 Host Controller"; Vendor = "ASMedia"; USB = "USB 3.0 (5Gbps)"; Year = "2013" }
    '1b21:1242' = @{ Name = "ASM1142 USB 3.1 Host Controller"; Vendor = "ASMedia"; USB = "USB 3.1 Gen 2 (10Gbps)"; Year = "2015" }
    '1b21:1343' = @{ Name = "ASM1143 USB 3.1 Host Controller"; Vendor = "ASMedia"; USB = "USB 3.1 Gen 2 (10Gbps)"; Year = "2017" }
    '1b21:2142' = @{ Name = "ASM2142/ASM3142 USB 3.1 Host Controller"; Vendor = "ASMedia"; USB = "USB 3.1 Gen 2 (10Gbps)"; Year = "2016" }
    '1b21:3042' = @{ Name = "ASM3042 USB 3.2 Gen 1 xHCI Controller"; Vendor = "ASMedia"; USB = "USB 3.2 Gen 1 (5Gbps)"; Year = "2019" }
    '1b21:3142' = @{ Name = "ASM3142 USB 3.2 Gen 2x1 xHCI Controller"; Vendor = "ASMedia"; USB = "USB 3.2 Gen 2 (10Gbps)"; Year = "2019" }
    '1b21:3242' = @{ Name = "ASM3242 USB 3.2 Host Controller"; Vendor = "ASMedia"; USB = "USB 3.2 Gen 2x2 (20Gbps)"; Year = "2020" }
    '1b21:2425' = @{ Name = "ASM4242 USB 4 / Thunderbolt 3 Host Router"; Vendor = "ASMedia"; USB = "USB4/TB3 (40Gbps)"; Year = "2022" }
    '1b21:2426' = @{ Name = "ASM4242 USB 3.2 xHCI Controller"; Vendor = "ASMedia"; USB = "USB 3.2"; Year = "2022" }
    # VIA (VID: 1106)
    '1106:3483' = @{ Name = "VL805/806 xHCI USB 3.0 Controller"; Vendor = "VIA"; USB = "USB 3.0 (5Gbps)"; Year = "2014" }
    '1106:3432' = @{ Name = "VL800/801 xHCI USB 3.0 Controller"; Vendor = "VIA"; USB = "USB 3.0 (5Gbps)"; Year = "2012" }
    # Fresco Logic (VID: 1b73)
    '1b73:1000' = @{ Name = "FL1000G USB 3.0 Host Controller"; Vendor = "Fresco Logic"; USB = "USB 3.0 (5Gbps)"; Year = "2010" }
    '1b73:1009' = @{ Name = "FL1009 USB 3.0 Host Controller"; Vendor = "Fresco Logic"; USB = "USB 3.0 (5Gbps)"; Year = "2011" }
    '1b73:1100' = @{ Name = "FL1100 USB 3.0 Host Controller"; Vendor = "Fresco Logic"; USB = "USB 3.0 (5Gbps)"; Year = "2012" }
    '1b73:1400' = @{ Name = "FL1400 USB 3.0 Host Controller"; Vendor = "Fresco Logic"; USB = "USB 3.0 (5Gbps)"; Year = "2014" }
    # Etron (VID: 1b6f)
    '1b6f:7023' = @{ Name = "EJ168 USB 3.0 Host Controller"; Vendor = "Etron"; USB = "USB 3.0 (5Gbps)"; Year = "2011" }
    '1b6f:7052' = @{ Name = "EJ188/EJ198 USB 3.0 Host Controller"; Vendor = "Etron"; USB = "USB 3.0 (5Gbps)"; Year = "2013" }
    # Renesas (VID: 1912)
    '1912:0014' = @{ Name = "uPD720201 USB 3.0 Host Controller"; Vendor = "Renesas"; USB = "USB 3.0 (5Gbps)"; Year = "2011" }
    '1912:0015' = @{ Name = "uPD720202 USB 3.0 Host Controller"; Vendor = "Renesas"; USB = "USB 3.0 (5Gbps)"; Year = "2012" }
}

# 控制器与设备识别
function Get-ControllerInfo {
    param([string]$Vid, [string]$Did)

    $vendorId = $Vid.ToLowerInvariant()
    $deviceId = $Did.ToLowerInvariant()
    $entry = $null
    $kind = 'UNKNOWN'
    if ($vendorId -eq '8086') {
        if ($IntelCpuIntegrated.ContainsKey($deviceId)) { $entry = $IntelCpuIntegrated[$deviceId]; $kind = 'CPU' }
        elseif ($IntelPch.ContainsKey($deviceId)) { $entry = $IntelPch[$deviceId]; $kind = 'CHIPSET' }
        elseif ($IntelThunderbolt.ContainsKey($deviceId)) { $entry = $IntelThunderbolt[$deviceId]; $kind = 'TB' }
    } elseif ($vendorId -eq '1022') {
        if ($AmdCpuIntegrated.ContainsKey($deviceId)) { $entry = $AmdCpuIntegrated[$deviceId]; $kind = 'CPU' }
        elseif ($AmdChipset.ContainsKey($deviceId)) { $entry = $AmdChipset[$deviceId]; $kind = 'CHIPSET' }
    }
    $key = "${vendorId}:${deviceId}"
    if ($ThirdParty.ContainsKey($key)) { $entry = $ThirdParty[$key]; $kind = 'ADDON' }
    return @{
        Type = $kind
        Name = if ($entry) { $entry.Name } else { "未收录的 USB 控制器（${vendorId}:${deviceId}）" }
        Platform = if ($entry -and $entry.Platform) { $entry.Platform } else { '未知' }
        USB = if ($entry) { $entry.USB } else { '未知' }
    }
}

function Get-ControllerLabel {
    param($Info)
    switch ($Info.Type) {
        'CPU' { return 'CPU/SoC 控制器（型号推测）' }
        'CHIPSET' { return '芯片组控制器（型号推测）' }
        'TB' { return 'Thunderbolt 控制器（上游未知）' }
        'ADDON' { return '第三方控制器（上游未知）' }
        default { return '控制器归属未知' }
    }
}

function Test-RootHub {
    param($Node)
    return ($Node.InstanceId -match '^USB\\ROOT_HUB[^\\]*\\')
}

function Test-UsbHub {
    param($Node)
    return ((Test-RootHub $Node) -or $Node.Service -match '^(USBHUB|USBHUB3)$' -or
        @($Node.CompatibleIds -match '^USB\\Class_09(?:&|$)').Count -gt 0)
}

function Test-UsbController {
    param($Node)
    # 排除 xDCI 等设备端接口，不能只凭显示名称判断。
    return ($Node.Service -match '^(USBXHCI|USBEHCI|USBOHCI|USBUHCI)$' -or
        @($Node.CompatibleIds -match '^PCI\\CC_0C03(00|10|20|30|80)(?:&|$)').Count -gt 0)
}

function Test-UsbInputNode {
    param($Node)
    if ($Node.Class -in @('XboxComposite', 'XnaComposite', 'XUSBClass')) { return $true }
    if ($Node.InstanceId -match '^USB\\' -and ($Node.Service -eq 'HidUsb' -or
        @($Node.CompatibleIds -match '^USB\\Class_03(?:&|$)').Count -gt 0)) { return $true }
    return ($Node.InstanceId -match '^HID\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}' -and
        ($Node.ParentId -match '^(USB|HID)\\' -or -not $Node.ParentId))
}

function Get-PnpNodes {
    $nodes = @{}
    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object {
        $_.InstanceId -match '^(USB|HID|PCI)\\' -or $_.Class -in @('USB', 'XboxComposite', 'XnaComposite', 'XUSBClass')
    })
    $keys = @('DEVPKEY_Device_Parent', 'DEVPKEY_Device_Service',
        'DEVPKEY_Device_CompatibleIds', 'DEVPKEY_Device_BusReportedDeviceDesc')
    foreach ($device in $devices) {
        $values = @{}
        # 可选属性可能不存在；缺少父节点时，连接路径会显示为不完整。
        $properties = @(Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName $keys -ErrorAction SilentlyContinue)
        foreach ($property in $properties) { $values[$property.KeyName] = $property.Data }
        $nodes[$device.InstanceId] = @{
            InstanceId = $device.InstanceId
            FriendlyName = $device.FriendlyName
            Class = $device.Class
            Status = $device.Status
            ParentId = [string]$values['DEVPKEY_Device_Parent']
            Service = [string]$values['DEVPKEY_Device_Service']
            CompatibleIds = @($values['DEVPKEY_Device_CompatibleIds'])
            BusDescription = [string]$values['DEVPKEY_Device_BusReportedDeviceDesc']
        }
    }
    return $nodes
}

function Get-DeviceChain {
    param([string]$InstanceId, [hashtable]$Nodes)

    $result = @{
        ControllerInstanceId = ''; ControllerInfo = $null
        PhysicalInstanceId = $InstanceId; HubCount = 0; HubNames = @(); Complete = $false
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
                $result.ControllerInstanceId = $node.ParentId
                $vendorId = ''; $deviceId = ''
                if ($node.ParentId -match 'VEN_([0-9A-F]{4})') { $vendorId = $Matches[1] }
                if ($node.ParentId -match 'DEV_([0-9A-F]{4})') { $deviceId = $Matches[1] }
                $result.ControllerInfo = Get-ControllerInfo -Vid $vendorId -Did $deviceId
                $result.Complete = $classificationKnown
            }
            break
        }
        if (Test-UsbHub $node) {
            $result.HubCount++
            $result.HubNames += $(if ($node.FriendlyName) { $node.FriendlyName } else { 'USB 集线器' })
        } elseif ($currentId -match '^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}') {
            # 取最近的物理 USB 实例，复合接口合并，同型号的不同设备分别保留。
            if (-not $physicalFound -and $currentId -notmatch '^USB\\[^\\]*&MI_[0-9A-F]{2}(?:&|\\)') {
                if ($node.Service -or ($node.CompatibleIds -join '')) { $result.PhysicalInstanceId = $currentId }
                $physicalFound = $true
            }
            if (-not $node.Service -and -not ($node.CompatibleIds -join '')) { $classificationKnown = $false }
        }
        $currentId = $node.ParentId
    }
    return $result
}

function Get-PathLabel {
    param($Chain)
    if (-not $Chain.Complete) { return "路径不完整（已识别 $($Chain.HubCount) 级集线器）" }
    $label = Get-ControllerLabel $Chain.ControllerInfo
    if ($Chain.HubCount -eq 0) { return "$label -> 输入设备（无额外集线器）" }
    return "$label -> $($Chain.HubCount) 级 USB 集线器 -> 输入设备"
}

# 设置读取与修改
$UsbPowerSubgroup = '2a737441-1930-4402-8d77-b2bebba308a3'
$UsbSuspendSetting = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

function Get-RegistryFlag {
    param([string]$Path, [string]$Name)
    try {
        $value = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
        if ($value -is [int] -and $value -in @(0, 1)) { return ($value -eq 1) }
    } catch { }
    return $null
}

function Get-SystemUsbSuspend {
    try {
        $output = & powercfg.exe /query SCHEME_CURRENT $UsbPowerSubgroup $UsbSuspendSetting 2>&1
        if ($LASTEXITCODE -eq 0) {
            # 此布尔设置的查询末尾依次为 AC、DC；只取十六进制值，不依赖中英文标签。
            $indices = [regex]::Matches(($output -join "`n"), '(?im)0x([0-9a-f]{8})\s*$')
            if ($indices.Count -eq 2) {
                $ac = [Convert]::ToInt32($indices[0].Groups[1].Value, 16)
                $dc = [Convert]::ToInt32($indices[1].Groups[1].Value, 16)
                if ($ac -in @(0, 1) -and $dc -in @(0, 1)) { return @{ AC = ($ac -eq 1); DC = ($dc -eq 1) } }
            }
        }
    } catch { }
    return @{ AC = $null; DC = $null }
}

function Invoke-UsbPowerCfg {
    param([string[]]$Arguments)
    $output = & powercfg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg 失败（退出码 $LASTEXITCODE）：$($output -join ' ')" }
}

function Apply-Optimization {
    param($Opt)
    try {
        switch ($Opt.Type) {
            'MSI' {
                $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($Opt.Controller)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
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
            default { throw '未知设置选项。' }
        }
        Write-Host "[成功] $($Opt.Desc) - $($Opt.Name)" -ForegroundColor Green
        if ($Opt.Type -ne 'SystemSuspend') { Write-Host '请重启电脑使设备设置生效。' -ForegroundColor Yellow }
    } catch {
        Write-Host "[失败] $($_.Exception.Message)" -ForegroundColor Red
        if ($Opt.Type -eq 'SystemSuspend') { Write-Host '部分电源设置可能已写入，请重新运行查看当前状态。' -ForegroundColor Yellow }
    }
}

function Get-UsbData {
    $nodes = Get-PnpNodes
    $data = @{
        Controllers = @(); Devices = @(); Optimizations = @()
        HasCpuController = $false; DirectInputCount = 0; SystemSuspend = Get-SystemUsbSuspend
    }
    $controllerIds = @{}
    foreach ($node in $nodes.Values) {
        if (Test-UsbController $node) { $controllerIds[$node.InstanceId] = $true }
        if ((Test-RootHub $node) -and $node.ParentId -and $nodes.ContainsKey($node.ParentId)) {
            $controllerIds[$node.ParentId] = $true
        }
    }
    foreach ($controllerId in @($controllerIds.Keys | Sort-Object)) {
        $node = $nodes[$controllerId]
        $vendorId = ''; $deviceId = ''
        if ($controllerId -match 'VEN_([0-9A-F]{4})') { $vendorId = $Matches[1] }
        if ($controllerId -match 'DEV_([0-9A-F]{4})') { $deviceId = $Matches[1] }
        $info = Get-ControllerInfo -Vid $vendorId -Did $deviceId
        $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$controllerId\Device Parameters"
        $msi = Get-RegistryFlag -Path "$path\Interrupt Management\MessageSignaledInterruptProperties" -Name MSISupported
        $suspend = Get-RegistryFlag -Path $path -Name SelectiveSuspendEnabled
        $data.Controllers += @{
            InstanceId = $controllerId; Info = $info; Status = $node.Status
            Msi = $msi; SelectiveSuspend = $suspend; Devices = @()
        }
        if ($info.Type -eq 'CPU') { $data.HasCpuController = $true }
        if ($node.Status -eq 'OK') {
            if ($controllerId -match '^PCI\\' -and $msi -eq $false) {
                $data.Optimizations += @{ Type = 'MSI'; Controller = $controllerId; Name = $info.Name; Desc = '启用 MSI 中断配置' }
            }
            if ($suspend -eq $true) {
                $data.Optimizations += @{ Type = 'Suspend'; Controller = $controllerId; Name = $info.Name; Desc = '关闭此控制器的选择性挂起' }
            }
        }
    }
    if ($data.SystemSuspend.AC -eq $true -or $data.SystemSuspend.DC -eq $true) {
        $data.Optimizations += @{ Type = 'SystemSuspend'; Name = '当前电源计划（插电和电池）'; Desc = '关闭电源计划的 USB 选择性挂起' }
    }

    $physicalDevices = @{}
    foreach ($node in @($nodes.Values | Where-Object { Test-UsbInputNode $_ } | Sort-Object InstanceId)) {
        $chain = Get-DeviceChain -InstanceId $node.InstanceId -Nodes $nodes
        $identity = $chain.PhysicalInstanceId
        if ($physicalDevices.ContainsKey($identity)) { continue }
        $physical = $nodes[$identity]
        $name = if ($physical.BusDescription) { $physical.BusDescription }
            elseif ($physical.FriendlyName) { $physical.FriendlyName }
            elseif ($node.FriendlyName) { $node.FriendlyName } else { '未命名 USB 输入设备' }
        $physicalDevices[$identity] = @{
            Name = $name; InstanceId = $identity; Chain = $chain; Status = $node.Status
        }
    }
    $data.Devices = @($physicalDevices.Values | Sort-Object InstanceId)
    foreach ($controller in $data.Controllers) {
        $controller.Devices = @($data.Devices | Where-Object { $_.Chain.ControllerInstanceId -eq $controller.InstanceId })
    }
    $data.DirectInputCount = @($data.Devices | Where-Object {
        $_.Chain.Complete -and $_.Chain.ControllerInfo.Type -eq 'CPU' -and $_.Chain.HubCount -eq 0
    }).Count
    return $data
}

# 结果与原有的可选设置菜单
function Format-SettingState {
    param($Value)
    if ($null -eq $Value) { return '未知或未配置' }
    if ($Value) { return '已启用' }
    return '已禁用'
}

function Get-ConnectionSummary {
    param($Data)
    if ($Data.HasCpuController) {
        if ($Data.DirectInputCount -eq 0) { return '识别到疑似 CPU/SoC 控制器，当前未识别到直接连接的输入设备；空闲端口位置请查主板手册。' }
        return "当前有 $($Data.DirectInputCount) 个输入设备连接疑似 CPU/SoC 控制器，且不经过额外集线器。"
    }
    return '本次未识别到 CPU/SoC 控制器，不能据此断定主板没有直连端口。'
}

function Show-Tree {
    param($Data)
    Write-Host "`n$(Get-ConnectionSummary $Data)" -ForegroundColor Yellow
    Write-Host "控制器：$($Data.Controllers.Count) 个  |  输入设备：$($Data.Devices.Count) 个"
    Write-Host "`n控制器与连接的输入设备" -ForegroundColor Cyan
    Write-Host ('-' * 64)
    foreach ($controller in $Data.Controllers) {
        Write-Host "`n$(Get-ControllerLabel $controller.Info)" -ForegroundColor Green
        Write-Host "  $($controller.Info.Name)"
        Write-Host "  $($controller.Info.Platform) | $($controller.Info.USB)"
        Write-Host "  MSI 配置：$(Format-SettingState $controller.Msi) | 选择性挂起：$(Format-SettingState $controller.SelectiveSuspend)"
        if ($controller.Status -ne 'OK') { Write-Host "  设备状态：$($controller.Status)" -ForegroundColor Yellow }
        if ($controller.Devices.Count -eq 0) { Write-Host '  当前未连接已识别的输入设备。' }
        foreach ($device in $controller.Devices) {
            $connection = if (-not $device.Chain.Complete) { '路径不完整' }
                elseif ($device.Chain.HubCount -eq 0) { '无额外集线器' }
                else { "$($device.Chain.HubCount) 级集线器" }
            Write-Host "  |- $($device.Name)（$connection）"
        }
    }
}

function Show-FullAnalysis {
    param($Data)
    Write-Host "`n输入设备详情" -ForegroundColor Cyan
    Write-Host ('-' * 64)
    if ($Data.Devices.Count -eq 0) { Write-Host '当前未识别到 USB 输入设备。' }
    foreach ($device in $Data.Devices) {
        Write-Host "`n$($device.Name)" -ForegroundColor White
        Write-Host "  $(Get-PathLabel $device.Chain)"
        Write-Host "  实例：$($device.InstanceId)"
        if ($device.Chain.HubNames.Count -gt 0) { Write-Host "  集线器（从设备向上）：$($device.Chain.HubNames -join ' -> ')" }
        if ($device.Status -ne 'OK') { Write-Host "  设备状态：$($device.Status)" -ForegroundColor Yellow }
    }
    Write-Host "`n电源计划 USB 选择性挂起：插电 $(Format-SettingState $Data.SystemSuspend.AC)；电池 $(Format-SettingState $Data.SystemSuspend.DC)"
    Write-Host '更换 USB 插孔后，重新运行即可比较连接路径。'
    Write-Host ''
}

function Test-Administrator {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Optimizations {
    param($Data)
    if ($Data.Optimizations.Count -eq 0) { return }
    Write-Host '可选设置' -ForegroundColor Cyan
    Write-Host 'MSI 需硬件和驱动支持；关闭挂起会增加功耗，这些设置不保证降低延迟。'
    for ($index = 0; $index -lt $Data.Optimizations.Count; $index++) {
        $opt = $Data.Optimizations[$index]
        Write-Host "[$($index + 1)] $($opt.Desc) - $($opt.Name)"
    }
    if (-not (Test-Administrator)) {
        Write-Host '修改设置需在管理员 PowerShell 中运行。' -ForegroundColor Yellow
        return
    }
    $choice = Read-Host '输入序号执行一项，直接回车跳过'
    if ([string]::IsNullOrWhiteSpace($choice)) { return }
    $number = 0
    if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $Data.Optimizations.Count) {
        Apply-Optimization -Opt $Data.Optimizations[$number - 1]
    } else { Write-Host '序号无效，未修改设置。' -ForegroundColor Yellow }
}

# 点源仅加载函数，方便离线测试；直接运行或 iex 都执行下面的流程。
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "`nUSB 连接分析器 · 简体中文版" -ForegroundColor Cyan
    Write-Host '控制器归属根据型号推测，集线器层数不代表实测延迟。'
    Write-Host '正在扫描 USB 设备，请稍候……'
    try {
        $data = Get-UsbData
        Show-Tree -Data $data
        Show-FullAnalysis -Data $data
        Show-Optimizations -Data $data
    } catch {
        Write-Host "[失败] 扫描未完成：$($_.Exception.Message)" -ForegroundColor Red
    }
}
