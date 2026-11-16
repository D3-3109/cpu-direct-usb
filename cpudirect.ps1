#requires -Version 5.1
<#
.SYNOPSIS
    USB 连接分析器（简体中文版）
.DESCRIPTION
    默认只读扫描 USB 控制器及输入设备。控制器归属是型号推测，不代表延迟测量。
    -Configure 进入可选设置，-Restore 恢复备份，-Json 输出结构化扫描结果。
    原始项目：MariusHeier/cpu-direct-usb；基于 D3-3109 分支 87489da 修订。
#>
[CmdletBinding(DefaultParameterSetName = "Scan")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Configure")][switch]$Configure,
    [Parameter(Mandatory = $true, ParameterSetName = "Restore")][string]$Restore,
    [Parameter(Mandatory = $true, ParameterSetName = "Json")][switch]$Json
)

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

. (Join-Path $PSScriptRoot 'lib/Topology.ps1')
. (Join-Path $PSScriptRoot 'lib/Settings.ps1')
. (Join-Path $PSScriptRoot 'lib/Display.ps1')

# 点源只加载函数和型号表，便于离线测试，不触发扫描或系统修改。
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($Restore) {
            $result = Restore-UsbBackup -Path $Restore
            Show-ConfigurationResult $result
            if (-not $result.Success) { exit 1 }
        } else {
            if (-not $Json) { Write-Host '正在扫描当前连接的 USB 设备，请稍候……' -ForegroundColor Cyan }
            $data = Get-UsbData
            if ($Json) { $data | ConvertTo-Json -Depth 16 }
            else {
                Show-UsbAnalysis -Data $data
                if ($Configure -and $data.EnumerationSucceeded) {
                    if (-not (Show-ConfigurationMenu -Data $data)) { exit 1 }
                } elseif ($Configure) { Write-Host '设备枚举失败，已跳过配置操作。' -ForegroundColor Yellow }
                else { Write-Host '本次仅扫描。可用 -Configure 进入设置，或用 -Restore 指定备份恢复。' }
            }
            if (-not $data.EnumerationSucceeded) { exit 1 }
        }
    } catch {
        Write-Error "运行失败：$($_.Exception.Message)"
        exit 1
    }
}
