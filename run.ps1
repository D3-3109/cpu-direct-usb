#requires -Version 5.1
<#
.SYNOPSIS
    Download and launch the Chinese CPU Direct USB edition in read-only mode.
.DESCRIPTION
    Pin all runtime files to one commit and verify SHA256 before launching.
    Only the child process uses ExecutionPolicy Bypass; no elevation is requested.
#>
[CmdletBinding()]
param([switch]$Configure)

function Get-UsbLauncherText {
    param([string]$Key)
    # Keep this bootstrap ASCII: Windows PowerShell 5.1 may misdecode web text.
    $messages = @{
        MissingEngine = '\u627e\u4e0d\u5230 Windows PowerShell\uff0c\u8bf7\u5728 Windows 10/11 \u4e0a\u8fd0\u884c\u3002'
        ChildFailed = '\u5206\u6790\u7a0b\u5e8f\u672a\u6b63\u5e38\u5b8c\u6210\uff0c\u9000\u51fa\u7801\uff1a{0}\u3002'
        WindowsOnly = '\u8bf7\u5728 Windows 10/11 \u7684 PowerShell \u4e2d\u8fd0\u884c\u3002'
        Downloading = '\u6b63\u5728\u4e0b\u8f7d\u5e76\u6821\u9a8c USB \u8fde\u63a5\u5206\u6790\u5668\u2026\u2026'
        Directory = '\u6587\u4ef6\u4fdd\u5b58\u4f4d\u7f6e\uff1a{0}'
        HashFailed = '\u6587\u4ef6\u6821\u9a8c\u5931\u8d25\uff0c\u5df2\u505c\u6b62\u8fd0\u884c\uff1a{0}'
        Verified = '\u5168\u90e8\u8fd0\u884c\u6587\u4ef6\u6821\u9a8c\u901a\u8fc7\u3002'
        Failed = '\u4e00\u952e\u542f\u52a8\u5931\u8d25\uff1a{0}'
    }
    return [regex]::Unescape($messages[$Key])
}

function Get-UsbLauncherManifest {
    # Update the commit and all hashes together when runtime files change.
    return @{
        Commit = 'adefb050eca3abf6d8fb64e69c7313fde16cab1b'
        Files = [ordered]@{
            'cpudirect.ps1' = '9a6f139bb3fed5cf9d2d9bb123b64643718659dba6556082448eaa76b514776f'
            'lib/Topology.ps1' = 'e0d2fb73c59a27b8e25fe44776f9d170ae8f774ec15ee79a55ab9ef89c99fb06'
            'lib/Settings.ps1' = '9069f4acaec99775f44947ed21229d5bec2ff6effb511202c86fcb4cda3b25bb'
            'lib/Display.ps1' = 'b030ebd97605161b997526cec38bc094bf3098d7874a3f735e158858a8a0bc2a'
        }
    }
}

function Receive-UsbLauncherFile {
    [CmdletBinding()]
    param([string]$Uri, [string]$Destination)
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
}

function Start-UsbDownloadedScript {
    [CmdletBinding()]
    param([string]$ScriptPath, [switch]$Configure)
    $engine = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw (Get-UsbLauncherText 'MissingEngine') }
    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    if ($Configure) { $arguments += '-Configure' }
    & $engine @arguments | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw ((Get-UsbLauncherText 'ChildFailed') -f $exitCode) }
}

function Invoke-UsbLauncher {
    [CmdletBinding()]
    param([switch]$Configure)
    $ErrorActionPreference = 'Stop'
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        if ($env:OS -ne 'Windows_NT') { throw (Get-UsbLauncherText 'WindowsOnly') }
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
        $manifest = Get-UsbLauncherManifest
        $directory = Join-Path ([IO.Path]::GetTempPath()) ('CpuDirectUsb-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $directory -ErrorAction Stop
        $null = New-Item -ItemType Directory -Path (Join-Path $directory 'lib') -ErrorAction Stop
        Write-Host (Get-UsbLauncherText 'Downloading') -ForegroundColor Cyan
        Write-Host ((Get-UsbLauncherText 'Directory') -f $directory)
        foreach ($relative in $manifest.Files.Keys) {
            $destination = Join-Path $directory $relative
            $uri = 'https://raw.githubusercontent.com/D3-3109/cpu-direct-usb/{0}/{1}' -f $manifest.Commit, $relative
            Receive-UsbLauncherFile -Uri $uri -Destination $destination -ErrorAction Stop
            $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($actual -ine $manifest.Files[$relative]) { throw ((Get-UsbLauncherText 'HashFailed') -f $relative) }
        }
        Write-Host (Get-UsbLauncherText 'Verified') -ForegroundColor Green
        $scriptPath = Join-Path $directory 'cpudirect.ps1'
        Start-UsbDownloadedScript -ScriptPath $scriptPath -Configure:$Configure -ErrorAction Stop
    } catch {
        throw ((Get-UsbLauncherText 'Failed') -f $_.Exception.Message)
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
}

# Support local execution and irm | iex. Dot-sourcing only loads definitions.
if ($MyInvocation.InvocationName -ne '.') { Invoke-UsbLauncher -Configure:$Configure }
