#requires -Version 5.1

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

    $evidence = '型号未收录，无法判断 CPU 或芯片组归属。'
    if ($kind -in @('CPU', 'CHIPSET')) { $evidence = '根据上游 PCI 型号表推测，未验证本机主板布线。' }
    if ($kind -in @('TB', 'ADDON')) { $evidence = '仅识别控制器型号，PCIe 上游归属待核实。' }
    return [pscustomobject]@{
        Type = $kind
        Name = if ($entry) { $entry.Name } else { "未收录的 USB 控制器（${vendorId}:${deviceId}）" }
        Platform = if ($entry -and $entry.Platform) { $entry.Platform } else { '待核实' }
        USB = if ($entry) { $entry.USB } else { '未知' }
        Confidence = if ($kind -in @('CPU', 'CHIPSET')) { 'ModelHint' } else { 'Unknown' }
        Evidence = $evidence
    }
}

function Get-ControllerLabel {
    param($Info)
    if (-not $Info) { return '控制器归属未知' }
    switch ($Info.Type) {
        'CPU' { return 'CPU/SoC 控制器（型号推测）' }
        'CHIPSET' { return '芯片组控制器（型号推测）' }
        'TB' { return 'Thunderbolt 控制器（上游待核实）' }
        'ADDON' { return '第三方控制器（上游待核实）' }
        default { return '控制器归属未知' }
    }
}

function Test-RootHub {
    param($Node)
    return ($Node.InstanceId -match '^USB\\ROOT_HUB[^\\]*\\')
}

function Test-UsbHub {
    param($Node)
    if (Test-RootHub $Node) { return $true }
    return (@($Node.CompatibleIds | Where-Object { $_ -match '^USB\\Class_09(?:&|$)' }).Count -gt 0 -or
        $Node.Service -match '^(USBHUB|USBHUB3)$')
}

function Test-UsbController {
    param($Node)
    # 使用 USB 主机控制器的编程接口代码，排除 xDCI 等设备端控制器。
    return (@($Node.CompatibleIds | Where-Object { $_ -match '^PCI\\CC_0C03(00|10|20|30|80)(?:&|$)' }).Count -gt 0 -or
        $Node.Service -match '^(USBXHCI|USBEHCI|USBOHCI|USBUHCI)$')
}

function Test-UsbInputNode {
    param($Node)
    if ($Node.Class -in @('XboxComposite', 'XnaComposite', 'XUSBClass')) { return $true }
    if ($Node.InstanceId -match '^USB\\' -and
        (@($Node.CompatibleIds | Where-Object { $_ -match '^USB\\Class_03(?:&|$)' }).Count -gt 0 -or
        $Node.Service -eq 'HidUsb')) { return $true }
    return ($Node.InstanceId -match '^HID\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}' -and
        ($Node.ParentId -match '^(USB|HID)\\' -or -not $Node.ParentId))
}

function Get-PnpSnapshot {
    $nodes = @{}
    $diagnostics = @()
    try {
        $devices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
    } catch {
        return @{ Nodes = $nodes; Diagnostics = @("设备枚举失败：$($_.Exception.Message)"); EnumerationSucceeded = $false }
    }

    $keys = @('DEVPKEY_Device_Parent', 'DEVPKEY_Device_Service', 'DEVPKEY_Device_CompatibleIds',
        'DEVPKEY_Device_BusReportedDeviceDesc', 'DEVPKEY_Device_LocationPaths')
    foreach ($device in $devices) {
        $node = [pscustomobject]@{
            InstanceId = [string]$device.InstanceId
            FriendlyName = [string]$device.FriendlyName
            Class = [string]$device.Class
            Status = [string]$device.Status
            ParentId = ''
            Service = ''
            CompatibleIds = @()
            BusDescription = ''
            LocationPaths = @()
            ReadError = ''
        }
        if ($node.InstanceId -match '^(USB|HID|PCI)\\' -or $node.Class -in @('USB', 'XboxComposite', 'XnaComposite', 'XUSBClass')) {
            $propertyErrors = @()
            try {
                # 部分设备不提供可选属性；保留已成功读取的字段，父链缺失另行诊断。
                $properties = @(Get-PnpDeviceProperty -InstanceId $node.InstanceId -KeyName $keys -ErrorAction SilentlyContinue -ErrorVariable propertyErrors)
                foreach ($property in $properties) {
                    switch ($property.KeyName) {
                        'DEVPKEY_Device_Parent' { $node.ParentId = [string]$property.Data }
                        'DEVPKEY_Device_Service' { $node.Service = [string]$property.Data }
                        'DEVPKEY_Device_CompatibleIds' { $node.CompatibleIds = @($property.Data) }
                        'DEVPKEY_Device_BusReportedDeviceDesc' { $node.BusDescription = [string]$property.Data }
                        'DEVPKEY_Device_LocationPaths' { $node.LocationPaths = @($property.Data) }
                    }
                }
                if ($properties.Count -eq 0 -and $propertyErrors.Count -gt 0) {
                    $node.ReadError = [string]$propertyErrors[0]
                }
            } catch { $node.ReadError = $_.Exception.Message }
            if ($propertyErrors.Count -gt 0) {
                $details = @($propertyErrors | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '；'
                $diagnostics += "部分属性未读取 [$($node.InstanceId)]（可能包含设备不提供的可选属性）：$details"
            }
            if ($node.ReadError) { $diagnostics += "属性读取失败 [$($node.InstanceId)]：$($node.ReadError)" }
            if ($node.InstanceId -match '^USB\\' -and -not (Test-RootHub $node) -and
                $node.CompatibleIds.Count -eq 0 -and -not $node.Service) {
                $diagnostics += "设备分类信息缺失 [$($node.InstanceId)]，可能无法识别输入设备或集线器。"
            }
        }
        $nodes[$node.InstanceId] = $node
    }
    return @{ Nodes = $nodes; Diagnostics = $diagnostics; EnumerationSucceeded = $true }
}

function Get-DeviceChain {
    param([string]$InstanceId, [hashtable]$Nodes, [int]$MaxDepth = 64)

    $result = [pscustomobject]@{
        ControllerInstanceId = ''
        ControllerInfo = $null
        PhysicalInstanceId = ''
        HubCount = 0
        HubNames = @()
        NodeIds = @()
        Complete = $false
        Diagnostics = @()
    }
    $visited = @{}
    $physicalCandidate = ''
    $currentId = $InstanceId
    for ($depth = 0; $depth -lt $MaxDepth; $depth++) {
        if (-not $currentId) { $result.Diagnostics += '父设备信息缺失，连接路径不完整。'; break }
        if ($visited.ContainsKey($currentId)) { $result.Diagnostics += "父设备链出现循环：$currentId"; break }
        $visited[$currentId] = $true
        $result.NodeIds += $currentId
        if (-not $Nodes.ContainsKey($currentId)) { $result.Diagnostics += "父设备不在扫描快照中：$currentId"; break }
        $node = $Nodes[$currentId]
        if ($node.ReadError) { $result.Diagnostics += "属性读取失败 [$currentId]：$($node.ReadError)" }

        if (Test-RootHub $node) {
            if ($physicalCandidate -and $result.Diagnostics.Count -eq 0) { $result.PhysicalInstanceId = $physicalCandidate }
            if (-not $node.ParentId -or -not $Nodes.ContainsKey($node.ParentId)) {
                $result.Diagnostics += '根集线器的控制器信息缺失。'
                break
            }
            $result.ControllerInstanceId = $node.ParentId
            $controller = $Nodes[$node.ParentId]
            $vendorId = ''; $deviceId = ''
            if ($controller.InstanceId -match 'VEN_([0-9A-F]{4})') { $vendorId = $Matches[1] }
            if ($controller.InstanceId -match 'DEV_([0-9A-F]{4})') { $deviceId = $Matches[1] }
            $result.ControllerInfo = Get-ControllerInfo -Vid $vendorId -Did $deviceId
            $result.Complete = ($result.Diagnostics.Count -eq 0)
            return $result
        }
        if (Test-UsbHub $node) {
            if ($physicalCandidate -and -not $result.PhysicalInstanceId -and $result.Diagnostics.Count -eq 0) {
                $result.PhysicalInstanceId = $physicalCandidate
            }
            $physicalCandidate = ''
            $result.HubCount++
            $result.HubNames += $(if ($node.FriendlyName) { $node.FriendlyName } else { $node.InstanceId })
        } elseif ($node.InstanceId -match '^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}[^\\]*\\') {
            # 只有直接位于已识别集线器之下的物理 USB 实例才能用来合并接口。
            if ($node.InstanceId -notmatch '^USB\\[^\\]*&MI_[0-9A-F]{2}(?:&|\\)' -and -not $result.PhysicalInstanceId) {
                if ($physicalCandidate) {
                    $result.Diagnostics += "发现多个未经过已识别集线器的物理 USB 节点：$currentId"
                }
                $physicalCandidate = $node.InstanceId
            }
            if ($node.CompatibleIds.Count -eq 0 -and -not $node.Service) {
                $result.Diagnostics += "缺少 USB 节点分类信息：$currentId"
            }
        }
        $currentId = $node.ParentId
    }
    if ($result.NodeIds.Count -ge $MaxDepth) { $result.Diagnostics += "父设备链超过 $MaxDepth 层，已停止追踪。" }
    return $result
}

function Get-PathLabel {
    param($Chain)
    $controllerLabel = Get-ControllerLabel $Chain.ControllerInfo
    if (-not $Chain.Complete) { return "路径不完整；已识别 $($Chain.HubCount) 级集线器；$controllerLabel" }
    if ($Chain.HubCount -eq 0) { return "$controllerLabel → 输入设备（未经过额外 USB 集线器）" }
    return "$controllerLabel → $($Chain.HubCount) 级 USB 集线器 → 输入设备"
}

function ConvertTo-UsbData {
    param($Snapshot)

    $nodes = $Snapshot.Nodes
    $data = [pscustomobject]@{
        Controllers = @()
        Devices = @()
        Diagnostics = @($Snapshot.Diagnostics)
        EnumerationSucceeded = $Snapshot.EnumerationSucceeded
        HasCpuController = $false
        DirectInputCount = 0
        SystemSuspend = $null
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
        $data.Controllers += [pscustomobject]@{
            InstanceId = $controllerId
            FriendlyName = $node.FriendlyName
            Info = $info
            Vid = $vendorId
            Did = $deviceId
            Status = $node.Status
            ParentId = $node.ParentId
            LocationPaths = @($node.LocationPaths)
            Msi = $null
            Power = $null
            Devices = @()
        }
        if ($info.Type -eq 'CPU') { $data.HasCpuController = $true }
        if ($node.Status -and $node.Status -ne 'OK') { $data.Diagnostics += "控制器状态为 $($node.Status)：$controllerId" }
    }

    $physicalDevices = @{}
    foreach ($node in @($nodes.Values | Where-Object { Test-UsbInputNode $_ } | Sort-Object InstanceId)) {
        $chain = Get-DeviceChain -InstanceId $node.InstanceId -Nodes $nodes
        $identity = if ($chain.PhysicalInstanceId) { $chain.PhysicalInstanceId } else { $node.InstanceId }
        $data.Diagnostics += @($chain.Diagnostics | ForEach-Object { "[$($node.InstanceId)] $_" })
        if ($node.Status -and $node.Status -ne 'OK') { $data.Diagnostics += "输入设备状态为 $($node.Status)：$($node.InstanceId)" }
        if ($physicalDevices.ContainsKey($identity)) {
            $existing = $physicalDevices[$identity]
            $existing.InterfaceIds = @(@($existing.InterfaceIds) + $node.InstanceId | Sort-Object -Unique)
            if ($chain.Complete -and -not $existing.Chain.Complete) { $existing.Chain = $chain }
            continue
        }
        $physical = if ($nodes.ContainsKey($identity)) { $nodes[$identity] } else { $node }
        $name = if ($physical.BusDescription) { $physical.BusDescription.Trim() }
            elseif ($physical.FriendlyName) { $physical.FriendlyName }
            elseif ($node.FriendlyName) { $node.FriendlyName } else { '未命名 USB 输入设备' }
        $vendorId = '????'; $productId = '????'
        if ($identity -match 'VID_([0-9A-F]{4})') { $vendorId = $Matches[1] }
        if ($identity -match 'PID_([0-9A-F]{4})') { $productId = $Matches[1] }
        $physicalDevices[$identity] = [pscustomobject]@{
            Name = $name
            Vid = $vendorId
            Pid = $productId
            InstanceId = $identity
            InterfaceIds = @($node.InstanceId)
            Chain = $chain
        }
    }
    $data.Devices = @($physicalDevices.Values | Sort-Object InstanceId)
    foreach ($controller in $data.Controllers) {
        $controller.Devices = @($data.Devices | Where-Object { $_.Chain.ControllerInstanceId -eq $controller.InstanceId })
    }
    $data.DirectInputCount = @($data.Devices | Where-Object {
        $_.Chain.Complete -and $_.Chain.ControllerInfo.Type -eq 'CPU' -and $_.Chain.HubCount -eq 0
    }).Count
    $data.Diagnostics = @($data.Diagnostics | Sort-Object -Unique)
    return $data
}

function Get-UsbData {
    $data = ConvertTo-UsbData -Snapshot (Get-PnpSnapshot)
    $data.SystemSuspend = Get-SystemUsbSuspend
    if ($data.SystemSuspend.Error) { $data.Diagnostics += "电源计划读取失败：$($data.SystemSuspend.Error)" }
    foreach ($controller in $data.Controllers) {
        $controller.Msi = Get-MsiStatus -InstanceId $controller.InstanceId
        $controller.Power = Get-PowerManagement -InstanceId $controller.InstanceId
        if ($controller.Msi.Error) { $data.Diagnostics += "MSI 配置读取失败 [$($controller.InstanceId)]：$($controller.Msi.Error)" }
        if ($controller.Power.Error) { $data.Diagnostics += "设备电源配置读取失败 [$($controller.InstanceId)]：$($controller.Power.Error)" }
    }
    return $data
}

function Get-ConnectionSummary {
    param($Data)
    if (-not $Data.EnumerationSucceeded) { return '设备扫描未完成，无法判断本机连接情况。' }
    if ($Data.HasCpuController) {
        if ($Data.DirectInputCount -eq 0) {
            return '识别到疑似 CPU/SoC 控制器，但当前未发现不经过额外集线器的输入设备；空闲端口需结合主板资料确认。'
        }
        return "识别到 $($Data.DirectInputCount) 个接在疑似 CPU/SoC 控制器下且未经过额外集线器的输入设备。"
    }
    return '本次未识别到 CPU/SoC 控制器；这不代表主板没有直连端口，请结合型号和主板资料核实。'
}
