#requires -Version 5.1
# 点源仅定义函数。MSI 仅表示注册表配置，不代表实际 IRQ 或运行中的中断模式。
# 恢复会删除原先不存在的值；为避免误删其他内容，可能新建的空注册表键会保留。
# 电源操作只保存具体方案的设置，不激活方案；重新应用该方案后由系统/驱动决定生效。

function Stop-UsbSettings {
    param([string]$Message)
    $exception = New-Object System.InvalidOperationException($Message)
    $exception.Data['UsbSettingsMessage'] = $Message
    throw $exception
}

function Get-UsbFailureText {
    param($Failure)
    $exception = $Failure.Exception
    while ($null -ne $exception) {
        if ($exception.Data.Contains('UsbSettingsMessage')) { return [string]$exception.Data['UsbSettingsMessage'] }
        $exception = $exception.InnerException
    }
    return ('系统访问失败，请检查权限、设备状态和本地备份目录。系统原始错误：' + $Failure.Exception.Message)
}

function New-UsbSettingsResult {
    param([bool]$Success, [string]$Message, [string]$BackupPath = '', $RollbackSucceeded = $null)
    [pscustomobject]@{ Success = $Success; Message = $Message; BackupPath = $BackupPath; RollbackSucceeded = $RollbackSucceeded }
}

function Get-UsbField {
    param($Record, [string]$Name)
    if ($null -eq $Record) { return $null }
    if ($Record -is [System.Collections.IDictionary]) { return $Record[$Name] }
    $property = $Record.PSObject.Properties[$Name]
    if ($null -ne $property -and $property.MemberType -eq 'NoteProperty') { return $property.Value }
    return $null
}

function Assert-UsbFields {
    param($Record, [string[]]$Names)
    if ($Record -is [System.Collections.IDictionary]) { $keys = @($Record.Keys) }
    elseif ($Record -is [pscustomobject]) {
        $keys = @($Record.PSObject.Properties | ForEach-Object {
            if ($_.MemberType -ne 'NoteProperty') { Stop-UsbSettings '备份包含不支持的属性。' }
            $_.Name
        })
    }
    else { Stop-UsbSettings '备份结构无效。' }
    if ($keys.Count -ne $Names.Count) { Stop-UsbSettings '备份字段不完整或包含额外字段。' }
    foreach ($key in $keys) {
        if ($key -isnot [string] -or $Names -cnotcontains $key) { Stop-UsbSettings '备份包含不允许的字段。' }
    }
}

function Test-UsbInteger {
    param($Value, [long]$Maximum = 4294967295)
    return (($Value -is [int] -or $Value -is [long] -or $Value -is [uint32] -or $Value -is [byte]) -and $Value -ge 0 -and $Value -le $Maximum)
}

function ConvertTo-UsbSchemeGuid {
    param($Value)
    $guid = [guid]::Empty
    if ($Value -isnot [string] -or -not [guid]::TryParseExact($Value, 'D', [ref]$guid) -or $guid -eq [guid]::Empty) {
        Stop-UsbSettings '电源计划标识必须是具体的有效 GUID。'
    }
    return $guid.ToString('D')
}

function Get-UsbRegistryTarget {
    param([string]$Type, [string]$InstanceId)
    if ($InstanceId -notmatch '\A(?:PCI|USB)\\[A-Za-z0-9_&{}+.-]{1,200}\\[A-Za-z0-9_&{}+.-]{1,200}\z' -or
        @($InstanceId.Split('\') | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
        Stop-UsbSettings '设备标识不在允许的 PCI/USB 控制器范围内。'
    }
    if ($Type -ceq 'MSI' -and $InstanceId -notmatch '\APCI\\') { Stop-UsbSettings 'MSI 注册表配置仅适用于 PCI 控制器。' }
    $root = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\$InstanceId"
    switch -CaseSensitive ($Type) {
        'MSI' { return @{ Root = $root; Path = "$root\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"; Name = 'MSISupported' } }
        'Suspend' { return @{ Root = $root; Path = "$root\Device Parameters"; Name = 'SelectiveSuspendEnabled' } }
        default { Stop-UsbSettings '不支持的控制器设置类型。' }
    }
}

# 以下系统访问函数可被测试覆盖；所有注册表路径均由固定规则生成。
function Test-UsbAdministrator {
    [CmdletBinding()]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    finally { $identity.Dispose() }
}

function Get-UsbMachineBinding {
    [CmdletBinding()]
    param()
    $base = $null; $key = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
        $key = $base.OpenSubKey('SOFTWARE\Microsoft\Cryptography', $false)
        if ($null -eq $key) { Stop-UsbSettings '无法读取本机标识，已取消操作。' }
        $value = $key.GetValue('MachineGuid', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return @{ Kind = 'MachineGuid'; Value = (ConvertTo-UsbSchemeGuid $value) }
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        if ($null -ne $base) { $base.Dispose() }
    }
}

function Get-UsbControllerClass {
    [CmdletBinding()]
    param([string]$InstanceId)
    $target = Get-UsbRegistryTarget -Type Suspend -InstanceId $InstanceId
    $key = Get-Item -LiteralPath $target.Root -ErrorAction Stop
    try { return $key.GetValue('ClassGUID', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    finally { $key.Dispose() }
}

function Assert-UsbController {
    param([string]$InstanceId)
    $null = Get-UsbRegistryTarget -Type Suspend -InstanceId $InstanceId
    if ((Get-UsbControllerClass -InstanceId $InstanceId -ErrorAction Stop) -ne '{36fc9e60-c465-11cf-8056-444553540000}') {
        Stop-UsbSettings '目标设备不属于允许的 USB 控制器设备类。'
    }
}

function Read-UsbRegistryValue {
    [CmdletBinding()]
    param([string]$Type, [string]$InstanceId)
    $target = Get-UsbRegistryTarget -Type $Type -InstanceId $InstanceId
    $absent = @{ Exists = $false; Kind = $null; Value = $null }
    if (-not (Test-Path -LiteralPath $target.Path -ErrorAction Stop)) { return $absent }
    $key = Get-Item -LiteralPath $target.Path -ErrorAction Stop
    try {
        if ($key.GetValueNames() -notcontains $target.Name) { return $absent }
        $kind = $key.GetValueKind($target.Name).ToString()
        $value = $key.GetValue($target.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        switch ($kind) {
            'DWord' { $value = [long][BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$value), 0) }
            'QWord' { $value = ([long]$value).ToString([Globalization.CultureInfo]::InvariantCulture) }
            { $_ -eq 'Binary' -or $_ -eq 'None' } { $value = [Convert]::ToBase64String([byte[]]$value) }
            'MultiString' { $value = [string[]]$value }
        }
        return @{ Exists = $true; Kind = $kind; Value = $value }
    }
    finally { $key.Dispose() }
}

function Write-UsbRegistryValue {
    [CmdletBinding()]
    param([string]$Type, [string]$InstanceId, $State)
    $target = Get-UsbRegistryTarget -Type $Type -InstanceId $InstanceId
    Assert-UsbRegistryState $State
    Assert-UsbController $InstanceId
    if (-not $State.Exists) {
        # 仅删除目标值，绝不递归删除注册表键。
        if ((Read-UsbRegistryValue -Type $Type -InstanceId $InstanceId -ErrorAction Stop).Exists) {
            Remove-ItemProperty -LiteralPath $target.Path -Name $target.Name -ErrorAction Stop
        }
        return
    }
    $value = $State.Value
    switch ($State.Kind) {
        'DWord' { $value = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$value), 0) }
        'QWord' { $value = [long]::Parse($value, [Globalization.CultureInfo]::InvariantCulture) }
        { $_ -eq 'Binary' -or $_ -eq 'None' } { $value = [Convert]::FromBase64String($value) }
        'MultiString' { $value = [string[]]$value }
    }
    if (-not (Test-Path -LiteralPath $target.Path -ErrorAction Stop)) {
        $null = New-Item -Path $target.Path -Force -ErrorAction Stop
    }
    # 新值使用 DWord；恢复按原始 RegistryValueKind 创建/替换，不丢失类型。
    $null = New-ItemProperty -LiteralPath $target.Path -Name $target.Name -PropertyType $State.Kind -Value $value -Force -ErrorAction Stop
}

function Initialize-UsbPowerNative {
    [CmdletBinding()]
    param()
    if ($null -eq ('CpuDirectUsb.SettingsPowerNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CpuDirectUsb {
    public static class SettingsPowerNative {
        [DllImport("PowrProf.dll", ExactSpelling = true)]
        public static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
        [DllImport("PowrProf.dll", ExactSpelling = true)]
        public static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);
        [DllImport("PowrProf.dll", ExactSpelling = true)]
        public static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);
        [DllImport("Kernel32.dll", ExactSpelling = true)]
        public static extern IntPtr LocalFree(IntPtr memory);
    }
}
'@ -ErrorAction Stop
    }
}

function Get-UsbActiveScheme {
    [CmdletBinding()]
    param()
    Initialize-UsbPowerNative -ErrorAction Stop
    $pointer = [IntPtr]::Zero
    try {
        $code = [CpuDirectUsb.SettingsPowerNative]::PowerGetActiveScheme([IntPtr]::Zero, [ref]$pointer)
        if ($code -ne 0 -or $pointer -eq [IntPtr]::Zero) { Stop-UsbSettings "读取活动电源计划失败，系统错误码：$code。" }
        $guid = [Runtime.InteropServices.Marshal]::PtrToStructure($pointer, [type][guid])
        return ConvertTo-UsbSchemeGuid ($guid.ToString('D'))
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) {
            if ([CpuDirectUsb.SettingsPowerNative]::LocalFree($pointer) -ne [IntPtr]::Zero) { Stop-UsbSettings '释放电源计划读取缓冲区失败。' }
        }
    }
}

function Read-UsbPowerIndex {
    [CmdletBinding()]
    param([string]$SchemeGuid, [ValidateSet('AC', 'DC')][string]$Mode)
    $scheme = [guid](ConvertTo-UsbSchemeGuid $SchemeGuid)
    $subgroup = [guid]'2a737441-1930-4402-8d77-b2bebba308a3'
    $setting = [guid]'48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    Initialize-UsbPowerNative -ErrorAction Stop
    [uint32]$value = 0
    if ($Mode -eq 'AC') {
        $code = [CpuDirectUsb.SettingsPowerNative]::PowerReadACValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$subgroup, [ref]$setting, [ref]$value)
    }
    else {
        $code = [CpuDirectUsb.SettingsPowerNative]::PowerReadDCValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$subgroup, [ref]$setting, [ref]$value)
    }
    if ($code -ne 0) { Stop-UsbSettings "读取 USB 电源设置失败，系统错误码：$code。" }
    return [long]$value
}

function Invoke-UsbPowerCfgCommand {
    [CmdletBinding()]
    param([string[]]$Arguments)
    # 外部命令包装本身也限制命令及参数，不接收备份中的任意命令。
    if ($Arguments.Count -ne 5 -or $Arguments[0] -cnotin @('/setacvalueindex', '/setdcvalueindex') -or
        $Arguments[2] -cne '2a737441-1930-4402-8d77-b2bebba308a3' -or
        $Arguments[3] -cne '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' -or $Arguments[4] -cnotin @('0', '1')) {
        Stop-UsbSettings '拒绝不在白名单内的电源命令。'
    }
    $null = ConvertTo-UsbSchemeGuid $Arguments[1]
    $executable = Join-Path ([Environment]::GetFolderPath('System')) 'powercfg.exe'
    $ErrorActionPreference = 'Stop'
    & $executable @Arguments 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE
    return [int]$exitCode
}

function Set-UsbPowerIndex {
    param([string]$SchemeGuid, [string]$Mode, $Value)
    $scheme = ConvertTo-UsbSchemeGuid $SchemeGuid
    if ($Mode -cnotin @('AC', 'DC') -or -not (Test-UsbInteger $Value 1)) { Stop-UsbSettings 'USB 电源设置值无效。' }
    $verb = if ($Mode -eq 'AC') { '/setacvalueindex' } else { '/setdcvalueindex' }
    $exitCode = Invoke-UsbPowerCfgCommand -Arguments @($verb, $scheme, '2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', [string]$Value) -ErrorAction Stop
    if (-not (Test-UsbInteger $exitCode 2147483647) -or $exitCode -ne 0) { Stop-UsbSettings "写入 USB 电源设置失败，命令退出码：$exitCode。" }
}

function Resolve-UsbLocalPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { Stop-UsbSettings '本地文件路径不能为空。' }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '\A[A-Za-z]:\\') { Stop-UsbSettings '备份必须位于本地磁盘，不能使用网络或设备路径。' }
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -notin @('Fixed', 'Removable', 'Ram')) { Stop-UsbSettings '备份必须位于本地磁盘。' }
    # 不跟随目录联接/符号链接到其他位置。
    $probe = $full
    while (-not [string]::IsNullOrEmpty($probe)) {
        if (([IO.File]::Exists($probe) -or [IO.Directory]::Exists($probe)) -and
            (([IO.File]::GetAttributes($probe) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            Stop-UsbSettings '备份路径不能经过目录联接或符号链接。'
        }
        $probe = [IO.Path]::GetDirectoryName($probe)
    }
    return $full
}

function Write-UsbBackupFile {
    [CmdletBinding()]
    param([string]$Directory, [string]$Json)
    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $Directory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CpuDirectUsb\Backups'
    }
    $directoryPath = Resolve-UsbLocalPath $Directory
    $null = [IO.Directory]::CreateDirectory($directoryPath)
    $path = Join-Path $directoryPath (([guid]::NewGuid().ToString('D')) + '.json')
    $stream = $null; $writer = $null
    try {
        $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $writer = New-Object IO.StreamWriter($stream, (New-Object Text.UTF8Encoding($true)))
        $writer.Write($Json)
        $writer.Flush()
        $stream.Flush($true)
    }
    finally {
        if ($null -ne $writer) { $writer.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
    return $path
}

function Read-UsbBackupFile {
    [CmdletBinding()]
    param([string]$Path)
    $full = Resolve-UsbLocalPath $Path
    if ([IO.Path]::GetExtension($full) -ine '.json') { Stop-UsbSettings '恢复只接受本地 JSON 备份文件。' }
    $file = Get-Item -LiteralPath $full -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 65536) { Stop-UsbSettings '备份文件类型或大小无效。' }
    return Get-Content -LiteralPath $full -Raw -Encoding UTF8 -ErrorAction Stop
}

function Assert-UsbRegistryState {
    param($State)
    Assert-UsbFields $State @('Exists', 'Kind', 'Value')
    if ($State.Exists -isnot [bool]) { Stop-UsbSettings '注册表值存在性记录无效。' }
    if (-not $State.Exists) {
        if ($null -ne $State.Kind -or $null -ne $State.Value) { Stop-UsbSettings '不存在的注册表值不能附带类型或内容。' }
        return
    }
    if ($State.Kind -isnot [string]) { Stop-UsbSettings '注册表值类型无效。' }
    $valid = $false
    switch -CaseSensitive ($State.Kind) {
        'DWord' { $valid = Test-UsbInteger $State.Value }
        'QWord' {
            [long]$number = 0
            $valid = $State.Value -is [string] -and $State.Value -cmatch '\A-?(0|[1-9][0-9]*)\z' -and [long]::TryParse($State.Value, [ref]$number)
        }
        { $_ -ceq 'String' -or $_ -ceq 'ExpandString' } { $valid = $State.Value -is [string] -and $State.Value.IndexOf([char]0) -lt 0 }
        'MultiString' {
            $valid = $State.Value -is [array]
            foreach ($entry in $State.Value) { if ($entry -isnot [string] -or $entry.IndexOf([char]0) -ge 0) { $valid = $false } }
        }
        { $_ -ceq 'Binary' -or $_ -ceq 'None' } {
            if ($State.Value -is [string]) {
                try { $null = [Convert]::FromBase64String($State.Value); $valid = $true } catch { $valid = $false }
            }
        }
    }
    if (-not $valid) { Stop-UsbSettings '注册表原值或类型无效，无法安全恢复。' }
}

function Assert-UsbTarget {
    param($Target)
    Assert-UsbFields $Target @('Type', 'InstanceId', 'SchemeGuid')
    if ($Target.Type -ceq 'SystemSuspend') {
        if ($null -ne $Target.InstanceId) { Stop-UsbSettings '系统电源目标不能包含设备标识。' }
        $null = ConvertTo-UsbSchemeGuid $Target.SchemeGuid
    }
    elseif ($Target.Type -cin @('MSI', 'Suspend')) {
        if ($Target.InstanceId -isnot [string] -or $null -ne $Target.SchemeGuid) { Stop-UsbSettings '控制器目标记录无效。' }
        $null = Get-UsbRegistryTarget -Type $Target.Type -InstanceId $Target.InstanceId
    }
    else { Stop-UsbSettings '备份目标不在允许范围内。' }
}

function Assert-UsbState {
    param($Target, $State)
    if ($Target.Type -ceq 'SystemSuspend') {
        Assert-UsbFields $State @('AC', 'DC')
        if (-not (Test-UsbInteger $State.AC 1) -or -not (Test-UsbInteger $State.DC 1)) { Stop-UsbSettings '备份中的 USB 电源值必须为 0 或 1。' }
    }
    else { Assert-UsbRegistryState $State }
}

function Assert-UsbBackupDocument {
    param($Document)
    Assert-UsbFields $Document @('Version', 'CreatedUtc', 'Machine', 'Target', 'State')
    if (-not (Test-UsbInteger $Document.Version 1) -or $Document.Version -ne 1) { Stop-UsbSettings '不支持的备份版本。' }
    [datetime]$created = [datetime]::MinValue
    if ($Document.CreatedUtc -isnot [string] -or -not [datetime]::TryParseExact($Document.CreatedUtc, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$created)) {
        Stop-UsbSettings '备份时间记录无效。'
    }
    Assert-UsbFields $Document.Machine @('Kind', 'Value')
    if ($Document.Machine.Kind -cne 'MachineGuid') { Stop-UsbSettings '备份机器标识类型无效。' }
    $null = ConvertTo-UsbSchemeGuid $Document.Machine.Value
    Assert-UsbTarget $Document.Target
    Assert-UsbState $Document.Target $Document.State
}

function Save-UsbBackup {
    param($Target, $State, $Machine, [string]$Directory)
    $document = [ordered]@{ Version = 1; CreatedUtc = [datetime]::UtcNow.ToString('o'); Machine = $Machine; Target = $Target; State = $State }
    Assert-UsbBackupDocument $document
    $json = ConvertTo-Json -InputObject $document -Depth 8 -ErrorAction Stop
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 65533) { Stop-UsbSettings '备份内容过大，已取消设置修改。' }
    $path = Write-UsbBackupFile -Directory $Directory -Json $json -ErrorAction Stop
    if ($path -isnot [string] -or [string]::IsNullOrWhiteSpace($path)) { Stop-UsbSettings '未获得有效的备份文件路径。' }
    # 落盘后再读回，备份不可读或内容不完整时绝不修改设置。
    $saved = ConvertFrom-Json -InputObject (Read-UsbBackupFile -Path $path -ErrorAction Stop) -ErrorAction Stop
    Assert-UsbBackupDocument $saved
    $expected = ConvertFrom-Json -InputObject $json -ErrorAction Stop
    if ((ConvertTo-Json $saved -Depth 8 -Compress -ErrorAction Stop) -cne (ConvertTo-Json $expected -Depth 8 -Compress -ErrorAction Stop)) {
        Stop-UsbSettings '备份读回核对失败，已取消设置修改。'
    }
    return $path
}

function Read-UsbTargetState {
    param($Target)
    if ($Target.Type -eq 'SystemSuspend') {
        $state = @{ AC = (Read-UsbPowerIndex -SchemeGuid $Target.SchemeGuid -Mode AC -ErrorAction Stop); DC = (Read-UsbPowerIndex -SchemeGuid $Target.SchemeGuid -Mode DC -ErrorAction Stop) }
    }
    else { $state = Read-UsbRegistryValue -Type $Target.Type -InstanceId $Target.InstanceId -ErrorAction Stop }
    Assert-UsbState $Target $state
    return $state
}

function Test-UsbStateEqual {
    param($Target, $Left, $Right)
    if ($Target.Type -eq 'SystemSuspend') { return ($Left.AC -eq $Right.AC -and $Left.DC -eq $Right.DC) }
    return ($Left.Exists -eq $Right.Exists -and $Left.Kind -ceq $Right.Kind -and
        (ConvertTo-Json -InputObject $Left.Value -Compress -Depth 4 -ErrorAction Stop) -ceq (ConvertTo-Json -InputObject $Right.Value -Compress -Depth 4 -ErrorAction Stop))
}

function Set-UsbTargetState {
    param($Target, $State, [switch]$AttemptAll)
    Assert-UsbTarget $Target
    Assert-UsbState $Target $State
    $writeFailure = $null
    if ($Target.Type -eq 'SystemSuspend') {
        foreach ($mode in @('AC', 'DC')) {
            try { Set-UsbPowerIndex -SchemeGuid $Target.SchemeGuid -Mode $mode -Value $State.$mode }
            catch { if (-not $AttemptAll) { throw }; $writeFailure = $_ }
        }
    }
    else { Write-UsbRegistryValue -Type $Target.Type -InstanceId $Target.InstanceId -State $State -ErrorAction Stop }
    $actual = Read-UsbTargetState $Target
    if (-not (Test-UsbStateEqual $Target $State $actual)) { Stop-UsbSettings '设置写入后读回不一致。' }
    if ($null -ne $writeFailure) { throw $writeFailure }
}

function Invoke-UsbSettingsChange {
    param($Target, $State, $Original, [string]$BackupPath, [string]$SuccessMessage)
    try {
        Set-UsbTargetState -Target $Target -State $State
        return New-UsbSettingsResult $true $SuccessMessage $BackupPath
    }
    catch {
        $message = Get-UsbFailureText $_
        try {
            Set-UsbTargetState -Target $Target -State $Original -AttemptAll
            return New-UsbSettingsResult $false ("操作失败：$message 已自动回滚并核对操作前状态；备份已保留。") $BackupPath $true
        }
        catch {
            $rollbackMessage = Get-UsbFailureText $_
            return New-UsbSettingsResult $false ("操作失败：$message 自动回滚失败：$rollbackMessage 请保留备份并检查当前配置。") $BackupPath $false
        }
    }
}

function Get-MsiStatus {
    [CmdletBinding()]
    param([string]$InstanceId)
    $ErrorActionPreference = 'Stop'
    $result = @{ Enabled = $null; Status = '未知（仅注册表配置，未检测实际中断模式）'; Error = '' }
    try {
        if ($InstanceId -notmatch '\APCI\\') { Stop-UsbSettings 'MSI 注册表配置仅适用于 PCI 控制器。' }
        Assert-UsbController $InstanceId
        $state = Read-UsbRegistryValue -Type MSI -InstanceId $InstanceId -ErrorAction Stop
        Assert-UsbRegistryState $state
        if (-not $state.Exists) { $result.Status = '未配置（仅注册表配置，未检测实际中断模式）' }
        elseif ($state.Kind -ceq 'DWord' -and (Test-UsbInteger $state.Value 1)) {
            $result.Enabled = ($state.Value -eq 1)
            $result.Status = if ($result.Enabled) { '已启用（仅注册表配置，未检测实际中断模式）' } else { '未启用（仅注册表配置，未检测实际中断模式）' }
        }
        else { $result.Error = 'MSI 注册表值不是有效的双字 0 或 1，无法判断配置。' }
    }
    catch { $result.Error = Get-UsbFailureText $_ }
    return $result
}

function Get-PowerManagement {
    [CmdletBinding()]
    param([string]$InstanceId)
    $ErrorActionPreference = 'Stop'
    $result = @{ SelectiveSuspend = $null; Error = '' }
    try {
        Assert-UsbController $InstanceId
        $state = Read-UsbRegistryValue -Type Suspend -InstanceId $InstanceId -ErrorAction Stop
        Assert-UsbRegistryState $state
        if ($state.Exists) {
            if ($state.Kind -ceq 'DWord' -and (Test-UsbInteger $state.Value 1)) { $result.SelectiveSuspend = ($state.Value -eq 1) }
            else { $result.Error = '选择性挂起注册表值不是有效的双字 0 或 1，无法判断配置。' }
        }
    }
    catch { $result.Error = Get-UsbFailureText $_ }
    return $result
}

function Get-SystemUsbSuspend {
    [CmdletBinding()]
    param()
    $ErrorActionPreference = 'Stop'
    $result = @{ SchemeGuid = $null; AC = $null; DC = $null; Error = '' }
    try { $result.SchemeGuid = ConvertTo-UsbSchemeGuid (Get-UsbActiveScheme -ErrorAction Stop) }
    catch { $result.Error = Get-UsbFailureText $_; return $result }
    $errors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($mode in @('AC', 'DC')) {
        try {
            $value = Read-UsbPowerIndex -SchemeGuid $result.SchemeGuid -Mode $mode -ErrorAction Stop
            if (-not (Test-UsbInteger $value 1)) { Stop-UsbSettings 'USB 选择性挂起值不是有效的 0 或 1。' }
            $result[$mode] = ($value -eq 1)
        }
        catch { $errors.Add((Get-UsbFailureText $_)) }
    }
    $result.Error = $errors -join '；'
    return $result
}

function Get-ConfigurationOptions {
    [CmdletBinding()]
    param($Data)
    foreach ($controller in @(Get-UsbField $Data 'Controllers')) {
        if ($null -eq $controller) { continue }
        $status = Get-UsbField $controller 'Status'
        if ($null -ne $status -and $status -ine 'OK') { continue }
        $id = Get-UsbField $controller 'InstanceId'
        try { $null = Get-UsbRegistryTarget -Type Suspend -InstanceId $id } catch { continue }
        $name = Get-UsbField (Get-UsbField $controller 'Info') 'Name'
        if ([string]::IsNullOrWhiteSpace($name)) { $name = 'USB 控制器' }
        $msi = Get-UsbField $controller 'Msi'
        $enabled = Get-UsbField $msi 'Enabled'
        if ($id -match '\APCI\\' -and $enabled -is [bool] -and -not $enabled -and -not (Get-UsbField $msi 'Error')) {
            @{ Type = 'MSI'; Controller = $id; Name = "启用 MSI 注册表配置（$name）"; Desc = '将 MSI 支持注册表值从 0 改为 1；驱动兼容性未验证，可能需要重新启动。这不代表已确认实际中断模式。'; Impact = '仅此控制器；驱动及其连接设备可能受影响。' }
        }
        $power = Get-UsbField $controller 'Power'
        $suspend = Get-UsbField $power 'SelectiveSuspend'
        if ($suspend -is [bool] -and $suspend -and -not (Get-UsbField $power 'Error')) {
            @{ Type = 'Suspend'; Controller = $id; Name = "关闭控制器选择性挂起（$name）"; Desc = '将此控制器的选择性挂起注册表值从 1 改为 0；驱动可能忽略该设置，可能需要重新启动。'; Impact = '此控制器及其连接设备；可能增加耗电，不保证降低延迟。' }
        }
    }
    $system = Get-UsbField $Data 'SystemSuspend'
    $ac = Get-UsbField $system 'AC'; $dc = Get-UsbField $system 'DC'
    if (($ac -is [bool] -and $ac) -or ($dc -is [bool] -and $dc)) {
        @{ Type = 'SystemSuspend'; Controller = $null; Name = '关闭电源计划的 USB 选择性挂起'; Desc = '关闭执行时活动电源计划在插电和电池供电时的 USB 选择性挂起；执行时固定方案，不切换活动方案，需手动重新应用该方案。'; Impact = '该电源计划下的所有 USB 设备；可能增加耗电并缩短续航，不保证降低延迟。' }
    }
}

function Apply-Optimization {
    [CmdletBinding()]
    param($Opt, [string]$BackupDirectory)
    $ErrorActionPreference = 'Stop'
    $backupPath = ''
    try {
        if ((Test-UsbAdministrator -ErrorAction Stop) -ne $true) { Stop-UsbSettings '需要管理员权限才能修改设置。' }
        $type = Get-UsbField $Opt 'Type'; $id = Get-UsbField $Opt 'Controller'
        if ($type -ceq 'SystemSuspend') {
            if ($null -ne $id) { Stop-UsbSettings '系统电源选项不能包含设备标识。' }
            $target = @{ Type = $type; InstanceId = $null; SchemeGuid = (ConvertTo-UsbSchemeGuid (Get-UsbActiveScheme -ErrorAction Stop)) }
            $desired = @{ AC = 0; DC = 0 }
            $message = 'USB 电源配置已保存并读回核对。未切换活动方案；请手动重新应用该方案后使用。'
        }
        elseif ($type -cin @('MSI', 'Suspend')) {
            $target = @{ Type = $type; InstanceId = $id; SchemeGuid = $null }
            Assert-UsbTarget $target
            Assert-UsbController $id
            $desired = @{ Exists = $true; Kind = 'DWord'; Value = $(if ($type -ceq 'MSI') { 1 } else { 0 }) }
            $message = if ($type -ceq 'MSI') { 'MSI 注册表配置已保存并读回核对。驱动兼容性未验证；未检测实际中断模式，可能需要重新启动。' } else { '控制器选择性挂起注册表配置已保存并读回核对。驱动可能忽略该设置，可能需要重新启动。' }
        }
        else { Stop-UsbSettings '不支持的设置选项。' }
        $machine = Get-UsbMachineBinding -ErrorAction Stop
        $original = Read-UsbTargetState $target
        if ($type -ceq 'SystemSuspend') {
            if ($original.AC -eq 0 -and $original.DC -eq 0) { return New-UsbSettingsResult $true '该方案的 USB 选择性挂起已关闭，无需修改。' }
        }
        else {
            $required = if ($type -ceq 'MSI') { 0 } else { 1 }
            if (-not $original.Exists -or $original.Kind -cne 'DWord' -or $original.Value -ne $required) {
                Stop-UsbSettings '当前注册表配置已变化或不符合操作条件，未修改设置；请重新扫描。'
            }
        }
        $backupPath = Save-UsbBackup -Target $target -State $original -Machine $machine -Directory $BackupDirectory
        return Invoke-UsbSettingsChange -Target $target -State $desired -Original $original -BackupPath $backupPath -SuccessMessage $message
    }
    catch { return New-UsbSettingsResult $false (Get-UsbFailureText $_) $backupPath }
}

function Restore-UsbBackup {
    [CmdletBinding()]
    param([string]$Path)
    $ErrorActionPreference = 'Stop'
    $backupPath = ''
    try {
        if ((Test-UsbAdministrator -ErrorAction Stop) -ne $true) { Stop-UsbSettings '需要管理员权限才能恢复设置。' }
        # 只反序列化 JSON 数据；不导入脚本对象，不执行备份中的路径或命令。
        $document = ConvertFrom-Json -InputObject (Read-UsbBackupFile -Path $Path -ErrorAction Stop) -ErrorAction Stop
        Assert-UsbBackupDocument $document
        $machine = Get-UsbMachineBinding -ErrorAction Stop
        if ($machine.Kind -cne $document.Machine.Kind -or $machine.Value -ine $document.Machine.Value) { Stop-UsbSettings '备份来自其他机器，已拒绝恢复。' }
        $target = $document.Target
        if ($target.Type -cne 'SystemSuspend') { Assert-UsbController $target.InstanceId }
        $original = Read-UsbTargetState $target
        $backupPath = Save-UsbBackup -Target $target -State $original -Machine $machine
        $message = if ($target.Type -ceq 'SystemSuspend') { '备份中的 USB 电源配置已恢复并读回核对。未切换活动方案；请手动重新应用目标方案后使用。' } else { '备份中的注册表配置已恢复并读回核对；原先不存在的值已删除，可能新建的空键会保留。可能需要重新启动。' }
        return Invoke-UsbSettingsChange -Target $target -State $document.State -Original $original -BackupPath $backupPath -SuccessMessage $message
    }
    catch { return New-UsbSettingsResult $false (Get-UsbFailureText $_) $backupPath }
}
