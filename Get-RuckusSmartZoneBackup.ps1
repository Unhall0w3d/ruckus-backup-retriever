<#
.SYNOPSIS
    RUCKUS SmartZone/vSZ Backup API Downloader

.DESCRIPTION
    Authenticates to the RUCKUS SmartZone/vSZ web/CAS interface, lists available
    System Configuration, Switch Configuration, and Cluster backups using the UI/API endpoints discovered
    during testing, and automatically downloads discovered files.

    First run prompts for BaseHost, BackupRoot, and credentials, then saves:
      - BaseHost / BackupRoot / SkipCertificateCheck in %APPDATA%\RuckusBackupApiProbe\settings.json
      - HTTPS port defaults to 8443 and is not prompted/stored
      - Credentials encrypted with Windows DPAPI via Export-Clixml

    Later runs reuse saved settings and credentials. Use -UpdateCreds to replace the saved credential.

    This version intentionally reduces debug capture. It writes:
      - logs\run.log
      - logs\config-list.json, if retrieved
      - logs\switch-list.json, if retrieved
      - logs\cluster-list.json, if retrieved
      - logs\download-status.json
      - logs\errors.log, if errors occur
      - backup files directly under the timestamped run folder

    Use -DebugCapture to also save raw request/response metadata and bodies.

    Version: 1.30.5
    Changes in v1.30.5:
      - Public repo refresh: removes environment-specific default backup root from first-run prompts/help
      - Preserves v1.30.4 retry, unavailable switch record, and retention behavior

    Changes in v1.30.1:
      - Fixes PowerShell 5.1 parser issue in retry round log message when a variable was followed by a colon
    1.30.2
      - Fixes retry array handling so retry tasks are not wrapped as nested arrays in Windows PowerShell 5.1
      - Updates runtime banner/version logging to match script version

    Changes in v1.30:
      - Adds retry handling for failed, empty, timed-out, and size-mismatched downloads
      - Adds retry attempt metadata to download-status.json
      - Adds clearer failure reasons when Invoke-WebRequest returns no useful error
      - Adds optional RequestTimeoutSeconds, RetryCount, and RetryDelaySeconds parameters
      - Keeps final status based on the last attempt per backup item

.NOTES
    Windows PowerShell 5.1 compatible, because apparently we still live here.

    Default backup destination:
      <OutputRoot>\<yyyyMMdd-HHmmss>\

    Retention default:
      Keep only the newest timestamped backup folder and remove older folders.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BaseHost,

    [Parameter(Mandatory = $false)]
    [int]$Port = 8443,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCertificateCheck,

    [Parameter(Mandatory = $false)]
    [switch]$NoSkipCertificateCheck,

    [Parameter(Mandatory = $false)]
    [int]$TimezoneOffset = 240,

    [Parameter(Mandatory = $false)]
    [int]$MaxDownloadPerCategory = 999,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 10)]
    [int]$RetryCount = 2,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$RetryDelaySeconds = 10,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 86400)]
    [int]$RequestTimeoutSeconds = 0,

    [Parameter(Mandatory = $false)]
    [switch]$NoDownload,

    [Parameter(Mandatory = $false)]
    [switch]$SkipClusterBackups,

    [Parameter(Mandatory = $false)]
    [switch]$SkipSwitchBackups,

    [Parameter(Mandatory = $false)]
    [switch]$DebugCapture,

    [Parameter(Mandatory = $false)]
    [switch]$ResetSavedConfig,

    [Parameter(Mandatory = $false)]
    [switch]$ResetSavedCredential,

    [Parameter(Mandatory = $false)]
    [switch]$UpdateCreds,

    [Parameter(Mandatory = $false)]
    [int]$KeepBackupRuns = 1,

    [Parameter(Mandatory = $false)]
    [switch]$PruneOnly,

    [Parameter(Mandatory = $false)]
    [Alias("h", "help")]
    [switch]$ShowHelp,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$CredentialPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:ScriptVersion = "1.30.5"
$script:FinalExitCode = 1
$script:RequestTimeoutSeconds = 0


function Show-RuckusBackupHelp {
    Write-Host ""
    Write-Host "RUCKUS SmartZone/vSZ Backup API Downloader"
    Write-Host ""
    Write-Host "Purpose:"
    Write-Host "  Logs into the local SmartZone/vSZ web interface, lists System Configuration, Switch Configuration, and Cluster backups,"
    Write-Host "  downloads discovered backup files, and keeps only the newest backup run folders."
    Write-Host ""
    Write-Host "Default first-run behavior:"
    Write-Host "  If saved settings do not exist, prompts for BaseHost, BackupRoot, and credentials."
    Write-Host "  Saves BaseHost/BackupRoot/SkipCertificateCheck to %APPDATA%\RuckusBackupApiProbe\settings.json."
    Write-Host "  Saves credentials encrypted with Windows DPAPI to %APPDATA%\RuckusBackupApiProbe\Credentials\."
    Write-Host "  HTTPS port defaults to 8443 and is not prompted or stored."
    Write-Host "  SkipCertificateCheck defaults to enabled."
    Write-Host ""
    Write-Host "Backup destination:"
    Write-Host "  No built-in default path is used. First run prompts for OutputRoot if it is not supplied or saved."
    Write-Host "  Example: D:\SmartZoneBackups\<yyyyMMdd-HHmmss>\"
    Write-Host ""
    Write-Host "Common usage:"
    Write-Host "  .\Get-RuckusSmartZoneBackup.ps1"
    Write-Host "  .\Get-RuckusSmartZoneBackup.ps1 -UpdateCreds"
    Write-Host "  .\Get-RuckusSmartZoneBackup.ps1 -NoDownload"
    Write-Host "  .\Get-RuckusSmartZoneBackup.ps1 -SkipClusterBackups"
    Write-Host "  .\Get-RuckusSmartZoneBackup.ps1 -SkipSwitchBackups"
    Write-Host "  .\Get-RuckusSmartZoneBackup.ps1 -MaxDownloadPerCategory 1"
    Write-Host "  .\Get-RuckusSmartZoneBackup.ps1 -BaseHost smartzone.example.com -OutputRoot D:\SmartZoneBackups"
    Write-Host "  .\Get-RuckusSmartZoneBackup.ps1 -OutputRoot D:\SmartZoneBackups -KeepBackupRuns 1"
    Write-Host "  .\Get-RuckusSmartZoneBackup.ps1 -PruneOnly"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -BaseHost                 SmartZone/vSZ host or FQDN. Prompted/saved on first run if omitted."
    Write-Host "  -OutputRoot               Root backup folder. Prompted/saved on first run if omitted."
    Write-Host "  -Port                     HTTPS port for this run only. Default: 8443. Not prompted or stored."
    Write-Host "  -UpdateCreds              Replace the saved username/password."
    Write-Host "  -ResetSavedConfig         Remove saved BaseHost/OutputRoot/SkipCertificateCheck and prompt again."
    Write-Host "  -ResetSavedCredential     Remove the saved credential and prompt again."
    Write-Host "  -NoDownload               List backups only; do not download."
    Write-Host "  -SkipClusterBackups       Skip Cluster backup listing/download. Useful for testing without huge files."
    Write-Host "  -SkipSwitchBackups        Skip Switch config listing/download."
    Write-Host "  -MaxDownloadPerCategory   Limit downloads per category. Default: 999."
    Write-Host "  -KeepBackupRuns           Keep newest N timestamped backup folders. Default: 1."
    Write-Host "  -PruneOnly                Run retention cleanup only, then exit. Useful for cleaning old test folders."
    Write-Host "  -DebugCapture             Write extra request/response debug files. Use only for troubleshooting."
    Write-Host "  -NoSkipCertificateCheck   Disable certificate bypass if the certificate is trusted."
    Write-Host "  -ShowHelp                 Show this help text."
    Write-Host ""
}

if ($ShowHelp) {
    Show-RuckusBackupHelp
    return
}


if ($PSVersionTable.PSVersion.Major -lt 6) {
    try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch {}
}

function Write-SafeJson {
    param([string]$Path, $Object, [int]$Depth = 20)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Object | ConvertTo-Json -Depth $Depth | Out-File -FilePath $Path -Encoding UTF8
}

function Write-SafeText {
    param([string]$Path, [AllowNull()][string]$Text)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($null -eq $Text) { $Text = "" }
    $Text | Out-File -FilePath $Path -Encoding UTF8
}

function Add-RunLog {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $Message
    if ($script:RunLogPath) { Add-Content -Path $script:RunLogPath -Value $line -Encoding UTF8 }
}

function Add-ErrorLog {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    Write-Warning $Message
    if ($script:ErrorLogPath) { Add-Content -Path $script:ErrorLogPath -Value $line -Encoding UTF8 }
}


function Get-PreviousLastRunStatus {
    param([string]$Root)

    $path = Join-Path $Root "last-run-status.json"
    if (-not (Test-Path $path)) { return $null }

    try { return (Get-Content -Path $path -Raw -ErrorAction Stop | ConvertFrom-Json) }
    catch { return $null }
}

function Get-PreviousLastSuccessfulRun {
    param([string]$Root)

    $previous = Get-PreviousLastRunStatus -Root $Root
    if ($null -eq $previous) { return $null }

    $prop = $previous.PSObject.Properties["LastSuccessfulRun"]
    if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) { return [string]$prop.Value }

    $statusProp = $previous.PSObject.Properties["Status"]
    $endProp = $previous.PSObject.Properties["LastRunEnd"]
    if ($null -ne $statusProp -and $statusProp.Value -eq "Success" -and $null -ne $endProp) { return [string]$endProp.Value }

    return $null
}

function Write-RuckusBackupEvent {
    param(
        [ValidateSet("Success","PartialFailure","Failure")]
        [string]$Status,
        [string]$Message,
        [int]$EventId
    )

    try {
        $source = "RuckusSmartZoneBackup"
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName Application -Source $source -ErrorAction Stop
        }

        $entryType = "Information"
        if ($Status -eq "PartialFailure") { $entryType = "Warning" }
        elseif ($Status -eq "Failure") { $entryType = "Error" }

        Write-EventLog -LogName Application -Source $source -EventId $EventId -EntryType $entryType -Message $Message -ErrorAction Stop
    }
    catch {
        Add-ErrorLog "Event Log write skipped/failed: $($_.Exception.Message)"
    }
}


function ConvertTo-StatusBoolean {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $false }

    if ($Value -is [bool]) { return [bool]$Value }

    if ($Value -is [System.Management.Automation.SwitchParameter]) {
        return [bool]$Value.IsPresent
    }

    try {
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $false }
        if ($text -match '^(?i:true|1|yes|y)$') { return $true }
        if ($text -match '^(?i:false|0|no|n)$') { return $false }
        return [System.Convert]::ToBoolean($text)
    }
    catch {
        return $false
    }
}

function Write-BackupRunStatus {
    param(
        [string]$Root,
        [string]$RunFolder,
        [ValidateSet("Success","PartialFailure","Failure")]
        [string]$Status,
        [int]$ExitCode,
        [datetime]$Started,
        [datetime]$Completed,
        [string]$BaseHost,
        [int]$Port,
        [object]$NoDownload,
        [object]$SkippedClusterBackups,
        [object]$SkippedSwitchBackups,
        [int]$SystemConfigFound,
        [int]$SystemConfigDownloaded,
        [int]$SwitchConfigFound,
        [int]$SwitchConfigDownloaded,
        [int]$ClusterFound,
        [int]$ClusterDownloaded,
        [int]$RawAttempts,
        [int]$RawSuccess,
        [int]$RawFailed,
        [int]$RawUnavailable,
        [int]$FinalFiles,
        [int]$FinalSuccess,
        [int]$FinalUnavailable,
        [int]$FinalFailed,
        [object[]]$UnavailableItems,
        [object[]]$FailedItems,
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Root)) { return }
    if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }

    $noDownloadStatus = ConvertTo-StatusBoolean -Value $NoDownload
    $skippedClusterStatus = ConvertTo-StatusBoolean -Value $SkippedClusterBackups
    $skippedSwitchStatus = ConvertTo-StatusBoolean -Value $SkippedSwitchBackups

    $previousLastSuccessful = Get-PreviousLastSuccessfulRun -Root $Root
    $completedText = $Completed.ToString("o")
    $lastSuccessful = $previousLastSuccessful
    if ($Status -eq "Success") { $lastSuccessful = $completedText }

    $obj = [ordered]@{
        ScriptName              = "Get-RuckusSmartZoneBackup.ps1"
        ScriptVersion           = $script:ScriptVersion
        Status                  = $Status
        ExitCode                = $ExitCode
        LastRunStart            = $Started.ToString("o")
        LastRunEnd              = $completedText
        LastSuccessfulRun       = $lastSuccessful
        BaseHost                = $BaseHost
        Port                    = $Port
        OutputFolder            = $RunFolder
        NoDownload              = $noDownloadStatus
        SkippedClusterBackups   = $skippedClusterStatus
        SkippedSwitchBackups    = $skippedSwitchStatus
        SystemConfigFound       = $SystemConfigFound
        SystemConfigDownloaded  = $SystemConfigDownloaded
        SwitchConfigFound       = $SwitchConfigFound
        SwitchConfigDownloaded  = $SwitchConfigDownloaded
        ClusterFound            = $ClusterFound
        ClusterDownloaded       = $ClusterDownloaded
        RawAttempts             = $RawAttempts
        RawSuccess              = $RawSuccess
        RawFailed               = $RawFailed
        RawUnavailable          = $RawUnavailable
        FinalFiles              = $FinalFiles
        FinalSuccess            = $FinalSuccess
        FinalUnavailable        = $FinalUnavailable
        FinalFailed             = $FinalFailed
        UnavailableItems        = @($UnavailableItems)
        FailedItems             = @($FailedItems)
        Message                 = $Message
    }

    if (-not [string]::IsNullOrWhiteSpace($RunFolder)) {
        Write-SafeJson -Path (Join-Path $RunFolder "run-status.json") -Object $obj
    }

    Write-SafeJson -Path (Join-Path $Root "last-run-status.json") -Object $obj
    Add-RunLog "Status written: $(Join-Path $Root 'last-run-status.json')"

    $eventId = 1000
    if ($Status -eq "PartialFailure") { $eventId = 1001 }
    elseif ($Status -eq "Failure") { $eventId = 1002 }
    Write-RuckusBackupEvent -Status $Status -EventId $eventId -Message $Message
}

function Redact-String {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $r = $Text
    $r = $r -replace '(?i)(password=)[^&\s]+', '$1<REDACTED>'
    $r = $r -replace '(?i)("password"\s*:\s*")[^"]+', '$1<REDACTED>'
    $r = $r -replace '(?i)(JSESSIONID=)[^;\s]+', '$1<REDACTED>'
    $r = $r -replace '(?i)(CASTGC=)[^;\s]+', '$1<REDACTED>'
    $r = $r -replace '(?i)(XSRF-TOKEN=)[^;\s]+', '$1<REDACTED>'
    $r = $r -replace '(?i)(LPSID-[^=]+=)[^;\s]+', '$1<REDACTED>'
    $r = $r -replace '(?i)(LPVID=)[^;\s]+', '$1<REDACTED>'
    return $r
}

function Get-DefaultConfigPath {
    $base = Join-Path $env:APPDATA "RuckusBackupApiProbe"
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
    return (Join-Path $base "settings.json")
}

function Get-DefaultCredentialPath {
    param([string]$HostName, [int]$PortNumber)
    $base = Join-Path $env:APPDATA "RuckusBackupApiProbe\Credentials"
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
    $safeHost = $HostName -replace '[^a-zA-Z0-9\.-]', '_'
    return (Join-Path $base "$safeHost-$PortNumber.credential.xml")
}

function Resolve-Settings {
    param(
        [string]$InputBaseHost,
        [string]$InputOutputRoot,
        [int]$InputPort,
        [switch]$InputSkipCertificateCheck,
        [switch]$InputNoSkipCertificateCheck,
        [string]$InputConfigPath,
        [switch]$InputResetSavedConfig
    )

    $path = if ([string]::IsNullOrWhiteSpace($InputConfigPath)) { Get-DefaultConfigPath } else { $InputConfigPath }

    if ($InputResetSavedConfig -and (Test-Path $path)) {
        Remove-Item $path -Force
        Write-Host "Removed saved config: $path"
    }

    $saved = $null
    if (Test-Path $path) {
        try { $saved = Get-Content $path -Raw | ConvertFrom-Json } catch { $saved = $null }
    }

    $resolvedHost = $InputBaseHost
    $resolvedOutputRoot = $InputOutputRoot
    $resolvedPort = if ($InputPort -gt 0) { [int]$InputPort } else { 8443 }
    $resolvedSkip = $true

    if ($saved) {
        if ([string]::IsNullOrWhiteSpace($resolvedHost) -and (Test-HasProperty -Object $saved -Name "BaseHost") -and $saved.BaseHost) {
            $resolvedHost = [string]$saved.BaseHost
        }
        if ([string]::IsNullOrWhiteSpace($resolvedOutputRoot) -and (Test-HasProperty -Object $saved -Name "OutputRoot") -and $saved.OutputRoot) {
            $resolvedOutputRoot = [string]$saved.OutputRoot
        }
        if ((Test-HasProperty -Object $saved -Name "SkipCertificateCheck") -and ($null -ne $saved.SkipCertificateCheck)) {
            $resolvedSkip = [bool]$saved.SkipCertificateCheck
        }
    }

    if ($InputSkipCertificateCheck.IsPresent) { $resolvedSkip = $true }
    if ($InputNoSkipCertificateCheck.IsPresent) { $resolvedSkip = $false }

    if ([string]::IsNullOrWhiteSpace($resolvedHost)) {
        $resolvedHost = Read-Host "Enter RUCKUS SmartZone/vSZ host or FQDN"
    }

    if ([string]::IsNullOrWhiteSpace($resolvedOutputRoot)) {
        do {
            $rootInput = Read-Host "Enter backup destination root (required; example: D:\SmartZoneBackups)"
        } while ([string]::IsNullOrWhiteSpace($rootInput))
        $resolvedOutputRoot = $rootInput
    }

    # Intentionally do not prompt for or store Port. Default is 8443 unless -Port is supplied for this run.
    $settings = [pscustomobject]@{
        BaseHost             = $resolvedHost
        OutputRoot           = $resolvedOutputRoot
        SkipCertificateCheck = $resolvedSkip
        UpdatedAt            = (Get-Date).ToString("o")
    }
    Write-SafeJson -Path $path -Object $settings

    return [pscustomobject]@{
        BaseHost             = $resolvedHost
        Port                 = $resolvedPort
        OutputRoot           = $resolvedOutputRoot
        SkipCertificateCheck = $resolvedSkip
        ConfigPath           = $path
    }
}

function Get-SavedOrPromptCredential {
    param([string]$HostName, [int]$PortNumber, [string]$InputCredentialPath, [switch]$InputResetSavedCredential)

    $path = if ([string]::IsNullOrWhiteSpace($InputCredentialPath)) { Get-DefaultCredentialPath -HostName $HostName -PortNumber $PortNumber } else { $InputCredentialPath }

    if ($InputResetSavedCredential -and (Test-Path $path)) {
        Remove-Item $path -Force
        Write-Host "Removed saved credential: $path"
    }

    if (Test-Path $path) {
        try {
            $cred = Import-Clixml -Path $path
            return [pscustomobject]@{ Credential = $cred; Path = $path; Loaded = $true }
        }
        catch {
            Add-ErrorLog "Saved credential could not be loaded from $path. Prompting again. $($_.Exception.Message)"
        }
    }

    $cred = Get-Credential -Message "Enter RUCKUS SmartZone/vSZ web UI credentials"
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $cred | Export-Clixml -Path $path
    return [pscustomobject]@{ Credential = $cred; Path = $path; Loaded = $false }
}

function Enable-CertBypassIfNeeded {
    param([bool]$Enable)
    if (-not $Enable) { return }

    if ($PSVersionTable.PSVersion.Major -ge 6) { return }

    Write-Warning "PowerShell 5.1 does not support -SkipCertificateCheck directly. Installing temporary cert bypass for this session. Still a museum exhibit."

    # PowerShell 5.1 keeps Add-Type classes loaded for the lifetime of the console.
    # Use a script-specific class name and test with -as [type], which reliably finds
    # classes already added in the current session. Avoids TYPE_ALREADY_EXISTS on rerun.
    $certPolicyTypeName = "RuckusTrustAllCertsPolicyV112"
    $certPolicyType = ($certPolicyTypeName -as [type])

    if (-not $certPolicyType) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class RuckusTrustAllCertsPolicyV112 : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) { return true; }
}
"@
        $certPolicyType = ($certPolicyTypeName -as [type])
    }

    [System.Net.ServicePointManager]::CertificatePolicy = New-Object $certPolicyTypeName
}

function New-TimestampedOutputFolder {
    param([string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) { throw "OutputRoot cannot be empty." }
    if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $path = Join-Path $Root $timestamp
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    foreach ($sub in @("logs")) { New-Item -ItemType Directory -Path (Join-Path $path $sub) -Force | Out-Null }
    return $path
}

function Invoke-BackupRunRetention {
    param([string]$Root, [int]$Keep)

    if ($Keep -lt 1) { $Keep = 1 }
    if (-not (Test-Path $Root)) {
        Add-RunLog "Retention: output root does not exist, nothing to prune: $Root"
        return
    }

    try {
        $folders = @(Get-ChildItem -Path $Root -Directory -ErrorAction Stop | Where-Object { $_.Name -match '^\d{8}-\d{6}$' } | Sort-Object Name -Descending)
        Add-RunLog "Retention: found $($folders.Count) timestamped backup run folder(s); keeping newest $Keep."
        if ($folders.Count -le $Keep) {
            Add-RunLog "Retention: no old backup run folders to remove."
            return
        }
        $remove = @($folders | Select-Object -Skip $Keep)
        foreach ($folder in $remove) {
            Add-RunLog "Retention: removing old backup run folder $($folder.FullName)"
            Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
        }
    }
    catch {
        Add-ErrorLog "Retention cleanup failed: $($_.Exception.Message)"
    }
}

function New-RunLock {
    param([string]$Root)

    if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
    $lockPath = Join-Path $Root ".ruckus-smartzone-backup.lock"
    try {
        $stream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.WriteLine("PID=$PID")
        $writer.WriteLine("Started=$(Get-Date -Format o)")
        $writer.Flush()
        return [pscustomobject]@{ Path = $lockPath; Stream = $stream; Writer = $writer }
    }
    catch {
        throw "Another backup run appears to be active, or the lock file is unavailable: $lockPath :: $($_.Exception.Message)"
    }
}

function Remove-RunLock {
    param($Lock)
    if ($null -eq $Lock) { return }
    try { if ($Lock.Writer) { $Lock.Writer.Dispose() } } catch {}
    try { if ($Lock.Stream) { $Lock.Stream.Dispose() } } catch {}
    try { if ($Lock.Path -and (Test-Path $Lock.Path)) { Remove-Item $Lock.Path -Force -ErrorAction SilentlyContinue } } catch {}
}


function Get-HtmlAttributeValue {
    param([string]$Tag, [string]$AttributeName)
    if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }
    $pattern = '(?i)\b' + [regex]::Escape($AttributeName) + '\s*=\s*(?:"(?<v>[^"]*)"|''(?<v>[^'']*)''|(?<v>[^\s>]+))'
    $m = [regex]::Match($Tag, $pattern)
    if ($m.Success) { return [System.Net.WebUtility]::HtmlDecode($m.Groups['v'].Value) }
    return $null
}

function Get-HtmlFormFields {
    param([string]$Html)
    $fields = [ordered]@{}
    if ([string]::IsNullOrWhiteSpace($Html)) { return $fields }
    $inputMatches = [regex]::Matches($Html, '<input\b[^>]*>', 'IgnoreCase')
    foreach ($match in $inputMatches) {
        $tag = $match.Value
        $name = Get-HtmlAttributeValue -Tag $tag -AttributeName 'name'
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $value = Get-HtmlAttributeValue -Tag $tag -AttributeName 'value'
        if ($null -eq $value) { $value = '' }
        if (-not $fields.Contains($name)) { $fields[$name] = $value }
    }
    return $fields
}

function Convert-HeadersToHash {
    param($Headers)
    $h = [ordered]@{}
    if ($null -eq $Headers) { return $h }
    try {
        foreach ($key in $Headers.Keys) { $h[$key] = Redact-String (($Headers[$key]) -join "; ") }
    } catch {}
    return $h
}

function Test-HasProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) -or $Object.ContainsKey($Name) }
    try { return (($Object.PSObject.Properties.Name) -contains $Name) } catch { return $false }
}

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        return $null
    }
    try {
        $p = $Object.PSObject.Properties[$Name]
        if ($p) { return $p.Value }
    } catch {}
    return $null
}

function Get-FirstProp {
    param($Object, [string[]]$Names)
    foreach ($name in $Names) {
        $v = Get-Prop -Object $Object -Name $name
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) { return $v }
    }
    return $null
}

function Invoke-RuckusRequest {
    param(
        [string]$Name,
        [string]$Method = "GET",
        [string]$Uri,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        $Body = $null,
        [string]$ContentType = $null,
        [hashtable]$Headers = @{},
        [string]$OutFile = $null,
        [string]$OutputPath,
        [bool]$CaptureDebug = $false
    )

    $safeName = $Name -replace '[^a-zA-Z0-9\._-]', '_'
    $params = @{
        Method             = $Method
        Uri                = $Uri
        WebSession         = $Session
        MaximumRedirection = 10
        Headers            = $Headers
        UseBasicParsing    = $true
        ErrorAction        = "Stop"
    }
    if ($null -ne $Body) { $params.Body = $Body }
    if ($ContentType) { $params.ContentType = $ContentType }
    if ($OutFile) { $params.OutFile = $OutFile }
    if ($script:RequestTimeoutSeconds -gt 0) { $params.TimeoutSec = [int]$script:RequestTimeoutSeconds }
    if ($script:EffectiveSkipCertificateCheck -and ($PSVersionTable.PSVersion.Major -ge 6)) { $params.SkipCertificateCheck = $true }

    if ($CaptureDebug) {
        $debugBody = $null
        if ($null -ne $Body) { $debugBody = Redact-String ($Body | Out-String) }
        Write-SafeJson -Path (Join-Path $OutputPath "debug\$safeName.request.json") -Object ([ordered]@{
            Name=$Name; Method=$Method; Uri=$Uri; Headers=$Headers; OutFile=$OutFile; Body=$debugBody
        })
    }

    try {
        $resp = Invoke-WebRequest @params
        $status = $null
        $statusDesc = $null
        $content = $null
        $headersOut = [ordered]@{}

        try { if (Test-HasProperty -Object $resp -Name "StatusCode") { $status = [int](Get-Prop -Object $resp -Name "StatusCode") } } catch {}
        try { if (Test-HasProperty -Object $resp -Name "StatusDescription") { $statusDesc = [string](Get-Prop -Object $resp -Name "StatusDescription") } } catch {}
        try { if (Test-HasProperty -Object $resp -Name "Headers") { $headersOut = Convert-HeadersToHash (Get-Prop -Object $resp -Name "Headers") } } catch {}
        if (-not $OutFile) {
            try { if (Test-HasProperty -Object $resp -Name "Content") { $content = [string](Get-Prop -Object $resp -Name "Content") } } catch {}
        }

        if ($CaptureDebug) {
            Write-SafeJson -Path (Join-Path $OutputPath "debug\$safeName.response.json") -Object ([ordered]@{
                Name=$Name; Success=$true; StatusCode=$status; StatusDescription=$statusDesc; Headers=$headersOut; OutFile=$OutFile
            })
            if (-not $OutFile) { Write-SafeText -Path (Join-Path $OutputPath "debug\$safeName.body.txt") -Text (Redact-String $content) }
        }

        return [pscustomobject]@{
            Success           = $true
            Name              = $Name
            Method            = $Method
            Uri               = $Uri
            StatusCode        = $status
            StatusDescription = $statusDesc
            Headers           = $headersOut
            Content           = $content
            OutFile           = $OutFile
            ErrorMessage      = $null
        }
    }
    catch {
        $ex = $_.Exception
        $status = $null
        $headersOut = [ordered]@{}
        $bodyText = $null

        try {
            if (Test-HasProperty -Object $ex -Name "Response") {
                $exResp = Get-Prop -Object $ex -Name "Response"
                if ($exResp) {
                    try { $status = [int]$exResp.StatusCode } catch {}
                    try { $headersOut = Convert-HeadersToHash $exResp.Headers } catch {}
                    try {
                        $stream = $exResp.GetResponseStream()
                        if ($stream) {
                            $reader = New-Object System.IO.StreamReader($stream)
                            $bodyText = Redact-String $reader.ReadToEnd()
                        }
                    } catch {}
                }
            }
        } catch {}

        $msg = "$Name [$Method] $Uri :: $($ex.Message)"
        Add-ErrorLog $msg
        Write-SafeJson -Path (Join-Path $OutputPath "logs\$safeName.error.json") -Object ([ordered]@{
            Name=$Name; Success=$false; StatusCode=$status; Message=$ex.Message; Headers=$headersOut; Uri=$Uri
        })
        if ($bodyText) { Write-SafeText -Path (Join-Path $OutputPath "logs\$safeName.error-body.txt") -Text $bodyText }

        return [pscustomobject]@{
            Success           = $false
            Name              = $Name
            Method            = $Method
            Uri               = $Uri
            StatusCode        = $status
            StatusDescription = $null
            Headers           = $headersOut
            Content           = $bodyText
            OutFile           = $OutFile
            ErrorMessage      = $ex.Message
        }
    }
}

function Convert-ResponseJson {
    param($Response)
    if ($null -eq $Response -or -not $Response.Success -or [string]::IsNullOrWhiteSpace($Response.Content)) { return $null }
    try { return $Response.Content | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

function Get-CsrfTokenFromResponse {
    param($Response)

    if ($null -eq $Response) { return $null }

    # SmartZone exposes this both as a response header and as:
    # <meta name="X-CSRF-Token" content="...">
    try {
        $headers = Get-Prop -Object $Response -Name "Headers"
        if ($headers) {
            foreach ($candidate in @("X-CSRF-Token", "x-csrf-token")) {
                try {
                    $v = Get-Prop -Object $headers -Name $candidate
                    if ($v -and -not [string]::IsNullOrWhiteSpace([string]$v)) { return [string]$v }
                } catch {}
            }
        }
    } catch {}

    try {
        $content = Get-Prop -Object $Response -Name "Content"
        if (-not [string]::IsNullOrWhiteSpace([string]$content)) {
            $m = [regex]::Match([string]$content, '<meta\s+name=["'']X-CSRF-Token["'']\s+content=["''](?<token>[^"'']+)["'']', 'IgnoreCase')
            if ($m.Success) { return $m.Groups['token'].Value }
        }
    } catch {}

    return $null
}

function New-RuckusAjaxHeaders {
    param([string]$Accept = "application/json")

    $h = @{
        "Accept"           = $Accept
        "X-Requested-With" = "XMLHttpRequest"
        "Referer"          = "$script:BaseUri/wsg/"
    }

    if ($script:CsrfToken -and -not [string]::IsNullOrWhiteSpace([string]$script:CsrfToken)) {
        $h["X-CSRF-Token"] = [string]$script:CsrfToken
    }

    return $h
}

function Get-ListItems {
    param($Json)
    if ($null -eq $Json) { return @() }

    if (($Json -is [System.Collections.IEnumerable]) -and -not ($Json -is [string]) -and -not (Test-HasProperty -Object $Json -Name "PSObject")) {
        return @($Json)
    }

    foreach ($prop in @("list", "data", "items", "results", "result")) {
        $v = Get-Prop -Object $Json -Name $prop
        if ($null -eq $v) { continue }

        if (($v -is [System.Array]) -or (($v -is [System.Collections.IEnumerable]) -and -not ($v -is [string]) -and -not (Test-HasProperty -Object $v -Name "PSObject"))) {
            return @($v)
        }

        foreach ($nested in @("list", "items", "results")) {
            $nv = Get-Prop -Object $v -Name $nested
            if ($null -ne $nv) { return @($nv) }
        }

        if (Test-HasProperty -Object $v -Name "filename" -or Test-HasProperty -Object $v -Name "backupID" -or Test-HasProperty -Object $v -Name "key") {
            return @($v)
        }
    }

    if (Test-HasProperty -Object $Json -Name "filename" -or Test-HasProperty -Object $Json -Name "backupID" -or Test-HasProperty -Object $Json -Name "key") {
        return @($Json)
    }

    return @()
}

function Get-BackupId {
    param($Item)
    $v = Get-FirstProp -Object $Item -Names @("key", "backupUUID", "backupUuid", "uuid", "id", "backupID", "backupId", "configId", "configID")
    if ($null -eq $v) { return $null }
    return [string]$v
}

function Get-BackupName {
    param($Item, [string]$Prefix, [string]$Id, [string]$DefaultExtension = ".bak")
    $v = Get-FirstProp -Object $Item -Names @("filename", "fileName", "name", "backupName", "configName")
    if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) { $v = "$Prefix-$Id$DefaultExtension" }
    $safe = [string]$v
    $safe = $safe -replace '[\\/:*?"<>|]', '_'
    return $safe
}

function Add-FileNameSuffix {
    param([string]$FileName, [string]$Suffix)
    if ([string]::IsNullOrWhiteSpace($Suffix)) { return $FileName }
    $dir = [System.IO.Path]::GetDirectoryName($FileName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [System.IO.Path]::GetExtension($FileName)
    $newName = "$base$Suffix$ext"
    if ([string]::IsNullOrWhiteSpace($dir)) { return $newName }
    return (Join-Path $dir $newName)
}

function Get-BackupSize {
    param($Item)
    $v = Get-FirstProp -Object $Item -Names @("filesize", "fileSize", "size", "sizeBytes", "bytes", "file_size")
    if ($null -eq $v) { return $null }
    try { return [int64]$v } catch { return $null }
}

function Get-ClusterBladeUuids {
    param($Item)
    $list = New-Object System.Collections.Generic.List[string]
    $blades = Get-Prop -Object $Item -Name "blades"
    if ($null -ne $blades) {
        foreach ($b in @($blades)) {
            if ($null -eq $b) { continue }
            if ($b -is [string]) { if (-not [string]::IsNullOrWhiteSpace($b)) { [void]$list.Add($b) } }
            else {
                $v = Get-FirstProp -Object $b -Names @("bladeUUID", "bladeUuid", "uuid", "id")
                if ($v) { [void]$list.Add([string]$v) }
            }
        }
    }
    foreach ($prop in @("bladeUUID", "bladeUuid", "bladeId", "nodeUUID", "nodeUuid")) {
        $v = Get-Prop -Object $Item -Name $prop
        if ($v) { [void]$list.Add([string]$v) }
    }
    return @($list | Sort-Object -Unique)
}

function Invoke-BackupDownload {
    param(
        [string]$Category,
        [string]$Id,
        [string]$DisplayName,
        [string]$Uri,
        [string]$OutFile,
        [object]$ExpectedSize,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$OutputPath,
        [System.Collections.Generic.List[object]]$StatusList,
        [bool]$CaptureDebug,
        [int]$AttemptNumber = 1,
        [string]$AttemptType = "Initial"
    )

    $dir = Split-Path $OutFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if (Test-Path $OutFile) {
        Remove-Item $OutFile -Force
    }

    $expectedText = if ($null -ne $ExpectedSize) { " expected $ExpectedSize bytes" } else { "" }
    $attemptText = if ($AttemptNumber -gt 1) { " retry attempt $($AttemptNumber - 1)" } else { "" }
    Add-RunLog "Downloading [$Category] $DisplayName$expectedText$attemptText..."

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $headers = New-RuckusAjaxHeaders -Accept "*/*"
    $result = Invoke-RuckusRequest -Name ("download-$Category-$Id-attempt-$AttemptNumber" -replace '[^a-zA-Z0-9\._-]', '_') -Method GET -Uri $Uri -Session $Session -Headers $headers -OutFile $OutFile -OutputPath $OutputPath -CaptureDebug:$CaptureDebug
    $timer.Stop()

    $exists = Test-Path $OutFile
    $bytes = 0L
    if ($exists) {
        try { $bytes = [int64](Get-Item $OutFile).Length } catch { $bytes = 0L }
    }

    $sizeMatches = $null
    if ($null -ne $ExpectedSize) { $sizeMatches = ($bytes -eq [int64]$ExpectedSize) }

    # Invoke-WebRequest -OutFile on Windows PowerShell 5.1 may not return StatusCode in a normal object.
    # Treat no exception + non-zero file as success, then separately validate size when SmartZone provided one.
    $ok = ($result.Success -and $exists -and $bytes -gt 0)
    $failureReason = $null
    $outcome = "Success"

    if (-not $result.Success) {
        $failureReason = $result.ErrorMessage
        $outcome = "RequestFailure"
    }
    elseif (-not $exists) {
        $failureReason = "Invoke-WebRequest completed without throwing, but no output file was created."
        $outcome = "MissingOutputFile"
    }
    elseif ($bytes -le 0) {
        $failureReason = "Invoke-WebRequest completed without throwing, but the output file was empty."
        $outcome = "EmptyResponse"
    }

    if ($ok -and ($false -eq $sizeMatches)) {
        $ok = $false
        $failureReason = "Downloaded file size ($bytes bytes) does not match expected size ($ExpectedSize bytes)."
        $outcome = "SizeMismatch"
    }

    if ([string]::IsNullOrWhiteSpace([string]$failureReason)) {
        if (-not $ok) {
            $failureReason = "Download did not complete successfully; no detailed error was returned by Invoke-WebRequest."
            if ([string]::IsNullOrWhiteSpace([string]$outcome) -or $outcome -eq "Success") { $outcome = "UnknownFailure" }
        }
        else { $failureReason = $null }
    }

    if (-not $ok -and [string]::IsNullOrWhiteSpace([string]$result.ErrorMessage)) {
        $result.ErrorMessage = $failureReason
    }

    $retryable = $false
    if (-not $ok) {
        $retryable = $true
    }

    if ($ok) {
        $msg = "Downloaded [$Category] $DisplayName -> $OutFile ($bytes bytes)"
        if ($false -eq $sizeMatches) { $msg += " [size differs from list value]" }
        Add-RunLog $msg
    }
    else {
        Add-ErrorLog "Download failed for [$Category] $DisplayName. Attempt=$AttemptNumber Retryable=$retryable Error: $failureReason"
    }

    [void]$StatusList.Add([pscustomobject]@{
        Timestamp       = (Get-Date).ToString("o")
        Category        = $Category
        Id              = $Id
        DisplayName     = $DisplayName
        Uri             = $Uri
        OutFile         = $OutFile
        Success         = $ok
        BytesWritten    = $bytes
        ExpectedSize    = $ExpectedSize
        SizeMatches     = $sizeMatches
        HttpStatus      = $result.StatusCode
        DurationSeconds = [math]::Round($timer.Elapsed.TotalSeconds, 2)
        AttemptNumber   = $AttemptNumber
        AttemptType     = $AttemptType
        Retryable       = $retryable
        Outcome         = $outcome
        ErrorMessage    = $failureReason
    })
}


function Get-CookieHeaderFromSession {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string[]]$Uris
    )

    # CookieContainer.GetCookies() is path-aware. A cookie scoped to /wsg/ may not be
    # returned when asking for https://host:8443/. Same for the Switch Manager SESSION
    # cookie under /switchm/. So gather cookies from the actual task URI plus the known
    # app roots and de-duplicate by name/domain/path. Because naturally one appliance
    # needs two cookie personalities.
    $cookieMap = @{}

    foreach ($uriText in $Uris) {
        if ([string]::IsNullOrWhiteSpace($uriText)) { continue }
        try {
            $cookieUri = [System.Uri]$uriText
            $cookies = $Session.Cookies.GetCookies($cookieUri)
            foreach ($cookie in $cookies) {
                if ($cookie -and -not [string]::IsNullOrWhiteSpace($cookie.Name)) {
                    $key = ('{0}|{1}|{2}' -f $cookie.Name, $cookie.Domain, $cookie.Path)
                    $cookieMap[$key] = ('{0}={1}' -f $cookie.Name, $cookie.Value)
                }
            }
        }
        catch {}
    }

    if ($cookieMap.Count -lt 1) { return '' }
    return (($cookieMap.Values | Sort-Object) -join '; ')
}

function New-DownloadTask {
    param([string]$Category,[string]$Id,[string]$DisplayName,[string]$Uri,[string]$OutFile,[object]$ExpectedSize)
    return [pscustomobject]@{ Category=$Category; Id=$Id; DisplayName=$DisplayName; Uri=$Uri; OutFile=$OutFile; ExpectedSize=$ExpectedSize }
}

function Invoke-DownloadTaskSequential {
    param(
        $Task,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$OutputPath,
        [System.Collections.Generic.List[object]]$StatusList,
        [bool]$CaptureDebug,
        [int]$AttemptNumber = 1,
        [string]$AttemptType = "Initial"
    )
    Invoke-BackupDownload -Category $Task.Category -Id $Task.Id -DisplayName $Task.DisplayName -Uri $Task.Uri -OutFile $Task.OutFile -ExpectedSize $Task.ExpectedSize -Session $Session -OutputPath $OutputPath -StatusList $StatusList -CaptureDebug:$CaptureDebug -AttemptNumber $AttemptNumber -AttemptType $AttemptType
}

function Get-DownloadTaskKey {
    param($Task)
    return ('{0}|{1}' -f ([string]$Task.Category), ([string]$Task.Id))
}

function Get-PendingDownloadTasks {
    param(
        [object[]]$Tasks,
        [System.Collections.Generic.List[object]]$StatusList
    )

    $lastByTask = @{}
    foreach ($entry in $StatusList) {
        if ($null -eq $entry) { continue }
        $cat = ""
        $id = ""
        try { $cat = [string]$entry.Category } catch {}
        try { $id = [string]$entry.Id } catch {}
        if ([string]::IsNullOrWhiteSpace($cat) -or [string]::IsNullOrWhiteSpace($id)) { continue }
        $lastByTask[('{0}|{1}' -f $cat, $id)] = $entry
    }

    $pending = New-Object System.Collections.Generic.List[object]
    foreach ($task in $Tasks) {
        $key = Get-DownloadTaskKey -Task $task
        if (-not $lastByTask.ContainsKey($key)) {
            [void]$pending.Add($task)
            continue
        }
        $entry = $lastByTask[$key]
        $success = $false
        try {
            $successProperty = $entry.PSObject.Properties["Success"]
            if ($null -ne $successProperty -and $successProperty.Value -eq $true) { $success = $true }
        } catch {}
        if (-not $success) { [void]$pending.Add($task) }
    }

    $arr = New-Object 'object[]' $pending.Count
    for ($i = 0; $i -lt $pending.Count; $i++) { $arr[$i] = $pending[$i] }
    return $arr
}


function ConvertTo-PlainObjectArray {
    param([object]$InputObject)

    $list = New-Object System.Collections.Generic.List[object]

    if ($null -eq $InputObject) {
        return @()
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        foreach ($item in $InputObject) {
            if ($null -ne $item) { [void]$list.Add($item) }
        }
    }
    else {
        [void]$list.Add($InputObject)
    }

    $arr = New-Object 'object[]' $list.Count
    for ($i = 0; $i -lt $list.Count; $i++) {
        $arr[$i] = $list[$i]
    }
    return $arr
}

function Invoke-DownloadTaskBatch {
    param(
        [string]$Category,
        [object]$Tasks,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$OutputPath,
        [System.Collections.Generic.List[object]]$StatusList,
        [bool]$CaptureDebug,
        [int]$RetryCount = 2,
        [int]$RetryDelaySeconds = 10
    )

    $Tasks = ConvertTo-PlainObjectArray -InputObject $Tasks
    if ($null -eq $Tasks -or $Tasks.Count -lt 1) {
        Add-RunLog "No [$Category] downloads queued."
        return
    }

    Add-RunLog "Starting [$Category] download batch: $($Tasks.Count) file(s). Sequential=True RetryCount=$RetryCount"

    foreach ($task in $Tasks) {
        Invoke-DownloadTaskSequential -Task $task -Session $Session -OutputPath $OutputPath -StatusList $StatusList -CaptureDebug:$CaptureDebug -AttemptNumber 1 -AttemptType "Initial"
    }

    for ($retryRound = 1; $retryRound -le $RetryCount; $retryRound++) {
        $pending = @(Get-PendingDownloadTasks -Tasks $Tasks -StatusList $StatusList)
        if ($pending.Count -lt 1) {
            if ($retryRound -eq 1) { Add-RunLog "No [$Category] retry downloads needed." }
            break
        }

        Add-RunLog "Starting [$Category] retry round $retryRound of ${RetryCount}: $($pending.Count) file(s)."
        if ($RetryDelaySeconds -gt 0) { Start-Sleep -Seconds $RetryDelaySeconds }

        foreach ($task in $pending) {
            Invoke-DownloadTaskSequential -Task $task -Session $Session -OutputPath $OutputPath -StatusList $StatusList -CaptureDebug:$CaptureDebug -AttemptNumber ($retryRound + 1) -AttemptType "Retry"
        }
    }

    $remaining = @(Get-PendingDownloadTasks -Tasks $Tasks -StatusList $StatusList)
    if ($remaining.Count -gt 0) {
        Add-ErrorLog "[$Category] downloads still failing after retry handling: $($remaining.Count) file(s)."
    }
    else {
        Add-RunLog "[$Category] downloads completed successfully after retry handling."
    }
}


function New-SwitchConfigQueryBody {
    param([int]$Limit = 30000)

    # Browser HAR from the Switch Backup tab shows this exact body shape.
    # RUCKUS expects Content-Type text/plain;charset=UTF-8 here. Yes, JSON as text/plain.
    # Standards had a good run, briefly.
    return ([ordered]@{
        fullTextSearch = [ordered]@{ type = 'OR'; value = '' }
        attributes     = @('*')
        sortInfo       = [ordered]@{ sortColumn = 'backupStartTime'; dir = 'DESC' }
        page           = 1
        limit          = $Limit
    } | ConvertTo-Json -Depth 20 -Compress)
}

function Get-ServiceTicketFromCurrentUser {
    param($Json)

    if ($null -eq $Json) { return $null }

    $data = Get-Prop -Object $Json -Name 'data'
    if ($null -ne $data) {
        $sessionUser = Get-Prop -Object $data -Name 'sessionUser'
        if ($null -ne $sessionUser) {
            $ticket = Get-Prop -Object $sessionUser -Name 'serviceTicketId'
            if (-not [string]::IsNullOrWhiteSpace([string]$ticket)) { return [string]$ticket }
        }
    }

    $ticket2 = Get-Prop -Object $Json -Name 'serviceTicketId'
    if (-not [string]::IsNullOrWhiteSpace([string]$ticket2)) { return [string]$ticket2 }

    return $null
}

function Get-SwitchConfigId {
    param($Item)
    $v = Get-FirstProp -Object $Item -Names @('id','configBackupId','configId','backupId','uuid')
    if ($null -eq $v) { return $null }
    return [string]$v
}

function Get-SwitchConfigName {
    param($Item,[string]$Id)
    $name = Get-FirstProp -Object $Item -Names @('name','filename','fileName','backupName')
    if ([string]::IsNullOrWhiteSpace([string]$name)) { $name = "switch-config-$Id" }
    $switchName = Get-FirstProp -Object $Item -Names @('switchName','switchId')
    if (-not [string]::IsNullOrWhiteSpace([string]$switchName) -and ([string]$name -notlike "*$switchName*")) { $name = "$switchName-$name" }
    $safe = ([string]$name) -replace '[\\/:*?"<>|]', '_'
    if ($safe -notmatch '\.(txt|cfg|config)$') { $safe = "$safe.txt" }
    return $safe
}

# Main
$effectiveResetCred = ($ResetSavedCredential -or $UpdateCreds)
$settings = Resolve-Settings -InputBaseHost $BaseHost -InputOutputRoot $OutputRoot -InputPort $Port -InputSkipCertificateCheck:$SkipCertificateCheck -InputNoSkipCertificateCheck:$NoSkipCertificateCheck -InputConfigPath $ConfigPath -InputResetSavedConfig:$ResetSavedConfig
$script:EffectiveSkipCertificateCheck = [bool]$settings.SkipCertificateCheck
Enable-CertBypassIfNeeded -Enable $script:EffectiveSkipCertificateCheck

$script:BaseUri = "https://$($settings.BaseHost):$($settings.Port)"
$runLock = $null

if ($PruneOnly) {
    $pruneLogRoot = $settings.OutputRoot
    if (-not (Test-Path $pruneLogRoot)) { New-Item -ItemType Directory -Path $pruneLogRoot -Force | Out-Null }
    $script:RunLogPath = Join-Path $pruneLogRoot "retention-prune.log"
    $script:ErrorLogPath = Join-Path $pruneLogRoot "retention-prune-errors.log"
    Add-RunLog "RUCKUS Backup API Downloader v1.30.4 - PruneOnly"
    Add-RunLog "Output root: $($settings.OutputRoot)"
    Add-RunLog "Retention: keep newest $KeepBackupRuns backup run folder(s)"
    Add-RunLog "Download retry handling: RetryCount=$RetryCount RetryDelaySeconds=$RetryDelaySeconds RequestTimeoutSeconds=$RequestTimeoutSeconds"
    Invoke-BackupRunRetention -Root $settings.OutputRoot -Keep $KeepBackupRuns
    Add-RunLog "PruneOnly complete."
    return
}

$outPath = New-TimestampedOutputFolder -Root $settings.OutputRoot
$runStarted = Get-Date
$script:FinalExitCode = 1
$runLock = New-RunLock -Root $settings.OutputRoot
if ($DebugCapture) { New-Item -ItemType Directory -Path (Join-Path $outPath "debug") -Force | Out-Null }

$script:RunLogPath = Join-Path $outPath "logs\run.log"
$script:ErrorLogPath = Join-Path $outPath "logs\errors.log"
$configItems = @()
$clusterItems = @()
$switchItems = @()
$downloadStatusArray = @()

try {
    Add-RunLog "RUCKUS Backup API Downloader v1.30.4"
    Add-RunLog "Target: $script:BaseUri"
    Add-RunLog "Output: $outPath"
    Add-RunLog "Output root: $($settings.OutputRoot)"
    Add-RunLog "Retention: keep newest $KeepBackupRuns backup run folder(s)"
    Add-RunLog "Saved config: $($settings.ConfigPath)"
    Add-RunLog "SkipCertificateCheck: $($settings.SkipCertificateCheck)"

    $credResult = Get-SavedOrPromptCredential -HostName $settings.BaseHost -PortNumber $settings.Port -InputCredentialPath $CredentialPath -InputResetSavedCredential:$effectiveResetCred
    if ($credResult.Loaded) { Add-RunLog "Using saved credential from: $($credResult.Path)" } else { Add-RunLog "Saved credential using Windows DPAPI for this Windows user: $($credResult.Path)" }
    $credential = $credResult.Credential

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $loginUri = "$script:BaseUri/cas/login?service=%2Fwsg%2Flogin%2Fcas"

    Add-RunLog "Fetching CAS login form..."
    $loginGet = Invoke-RuckusRequest -Name "cas-login-get" -Method GET -Uri $loginUri -Session $session -OutputPath $outPath -CaptureDebug:$DebugCapture
    if (-not $loginGet.Success) { throw "CAS login form fetch failed: $($loginGet.ErrorMessage)" }

    $fields = Get-HtmlFormFields -Html $loginGet.Content
    if ($fields.Count -eq 0) { throw "No CAS login form fields detected. SSO/MFA/JavaScript login may be blocking scripted login." }

    if (-not $fields.Contains("username")) { $fields["username"] = "" }
    if (-not $fields.Contains("password")) { $fields["password"] = "" }
    if (-not $fields.Contains("_eventId")) { $fields["_eventId"] = "submit" }

    $fields["username"] = $credential.UserName
    $fields["password"] = $credential.GetNetworkCredential().Password

    Add-RunLog "Submitting CAS login..."
    $loginPost = Invoke-RuckusRequest -Name "cas-login-post" -Method POST -Uri $loginUri -Session $session -Body $fields -ContentType "application/x-www-form-urlencoded" -OutputPath $outPath -CaptureDebug:$DebugCapture
    if (-not $loginPost.Success) { throw "CAS login POST failed: $($loginPost.ErrorMessage)" }

    Add-RunLog "Validating authenticated /wsg/ session..."
    $wsg = Invoke-RuckusRequest -Name "wsg-shell" -Method GET -Uri "$script:BaseUri/wsg/" -Session $session -OutputPath $outPath -CaptureDebug:$DebugCapture
    if (-not $wsg.Success) { throw "Authenticated /wsg/ validation failed: $($wsg.ErrorMessage)" }

    $script:CsrfToken = Get-CsrfTokenFromResponse -Response $wsg
    if (-not $script:CsrfToken) { $script:CsrfToken = Get-CsrfTokenFromResponse -Response $loginPost }
    if ($script:CsrfToken) { Add-RunLog "CSRF token detected from authenticated session." } else { Add-RunLog "No CSRF token detected. Continuing with cookie session only." }

    Add-RunLog "Listing System Configuration backups..."
    $configResp = Invoke-RuckusRequest -Name "config-list" -Method GET -Uri "$script:BaseUri/wsg/api/scg/backup/config" -Session $session -Headers (New-RuckusAjaxHeaders) -OutputPath $outPath -CaptureDebug:$DebugCapture
    $configJson = Convert-ResponseJson -Response $configResp
    if ($configJson) { Write-SafeJson -Path (Join-Path $outPath "logs\config-list.json") -Object $configJson }
    $configItems = @(Get-ListItems -Json $configJson)
    Add-RunLog "System Configuration backups found: $($configItems.Count)"

    $clusterItems = @()
    if ($SkipClusterBackups) {
        Add-RunLog "SkipClusterBackups selected. Skipping Cluster backup listing and download."
    }
    else {
        Add-RunLog "Listing Cluster backups..."
        $clusterResp = Invoke-RuckusRequest -Name "cluster-list" -Method GET -Uri "$script:BaseUri/wsg/api/scg/backup/cluster" -Session $session -Headers (New-RuckusAjaxHeaders) -OutputPath $outPath -CaptureDebug:$DebugCapture
        $clusterJson = Convert-ResponseJson -Response $clusterResp
        if ($clusterJson) { Write-SafeJson -Path (Join-Path $outPath "logs\cluster-list.json") -Object $clusterJson }
        $clusterItems = @(Get-ListItems -Json $clusterJson)
        Add-RunLog "Cluster backups found: $($clusterItems.Count)"
    }

    $switchItems = @()
    $switchConfigBaseUri = $null
    if ($SkipSwitchBackups) {
        Add-RunLog "SkipSwitchBackups selected. Skipping Switch config listing and download."
    }
    else {
        Add-RunLog "Preparing Switch Manager session..."
        try {
            $dc = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
            $validationUri1 = "$script:BaseUri/wsg/api/scg/session/validation?_dc=$dc&scgVersion=7.1.1.0.872&keepMeAlive=true"
            [void](Invoke-RuckusRequest -Name "switch-session-validation-keepalive-true" -Method GET -Uri $validationUri1 -Session $session -Headers (New-RuckusAjaxHeaders -Accept "*/*") -OutputPath $outPath -CaptureDebug:$DebugCapture)
            $dc2 = $dc + 1
            $validationUri2 = "$script:BaseUri/wsg/api/scg/session/validation?_dc=$dc2&scgVersion=7.1.1.0.872&keepMeAlive=false"
            [void](Invoke-RuckusRequest -Name "switch-session-validation-keepalive-false" -Method GET -Uri $validationUri2 -Session $session -Headers (New-RuckusAjaxHeaders -Accept "*/*") -OutputPath $outPath -CaptureDebug:$DebugCapture)
        }
        catch {
            Add-ErrorLog "Switch session validation call failed, continuing anyway: $($_.Exception.Message)"
        }

        Add-RunLog "Requesting current user/session details for Switch Manager service ticket..."
        $switchServiceTicket = $null
        try {
            $dcUser = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
            $currentUserResp = Invoke-RuckusRequest -Name "switch-current-user" -Method GET -Uri "$script:BaseUri/wsg/api/scg/session/currentUser?_dc=$dcUser" -Session $session -Headers (New-RuckusAjaxHeaders -Accept "*/*") -OutputPath $outPath -CaptureDebug:$DebugCapture
            $currentUserJson = Convert-ResponseJson -Response $currentUserResp
            if ($currentUserJson) {
                if ($DebugCapture) { Write-SafeJson -Path (Join-Path $outPath "logs\current-user.json") -Object $currentUserJson }
                $switchServiceTicket = Get-ServiceTicketFromCurrentUser -Json $currentUserJson
            }
        }
        catch {
            Add-ErrorLog "Switch currentUser/serviceTicket lookup failed: $($_.Exception.Message)"
        }

        if ([string]::IsNullOrWhiteSpace($switchServiceTicket)) {
            Add-ErrorLog "Switch Manager serviceTicketId was not found. Switch config listing will likely fail."
        }
        else {
            Add-RunLog "Switch Manager service ticket detected."
        }

        Add-RunLog "Listing Switch configuration backups..."
        $switchQueryBody = New-SwitchConfigQueryBody -Limit 30000
        # HAR capture from the Switch Backup tab confirmed the list call:
        #   POST /switchm/api/v13_1/switchconfig?_dc=<epochms>&serviceTicket=<serviceTicketId>
        # with Content-Type: text/plain;charset=UTF-8 and a JSON body.
        $dcList = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        $switchListCandidates = @()
        if (-not [string]::IsNullOrWhiteSpace($switchServiceTicket)) {
            $encodedTicket = [System.Uri]::EscapeDataString($switchServiceTicket)
            $switchListCandidates += "$script:BaseUri/switchm/api/v13_1/switchconfig?_dc=$dcList&serviceTicket=$encodedTicket"
        }
        # Fallbacks retained for controller variance, but the serviceTicket URL above should be the real one.
        $switchListCandidates += @(
            "$script:BaseUri/switchm/api/v13_1/switchconfig",
            "$script:BaseUri/switchm/api/v11_1/switchconfig"
        )
        foreach ($candidate in $switchListCandidates) {
            $switchResp = Invoke-RuckusRequest -Name ("switch-list-" + ($candidate -replace '[^a-zA-Z0-9]', '_')) -Method POST -Uri $candidate -Session $session -Headers (New-RuckusAjaxHeaders -Accept "*/*") -Body $switchQueryBody -ContentType "text/plain;charset=UTF-8" -OutputPath $outPath -CaptureDebug:$DebugCapture
            if ($switchResp.Success) {
                $switchJson = Convert-ResponseJson -Response $switchResp
                if ($switchJson) {
                    Write-SafeJson -Path (Join-Path $outPath "logs\switch-list.json") -Object $switchJson
                    $switchItems = @(Get-ListItems -Json $switchJson)
                    $switchConfigBaseUri = "$script:BaseUri/switchm/api/v13_1/switchconfig"
                    break
                }
            }
        }
        if ($switchConfigBaseUri) {
            Add-RunLog "Switch configuration backups found: $($switchItems.Count)"
            Add-RunLog "Switch configuration API base: $switchConfigBaseUri"
        }
        else {
            Add-ErrorLog "Switch configuration backup list endpoint was not found using known candidates. If the UI tab works, capture its Network request for the Switch tab list/download and we can wire it in."
        }
    }

    $downloadStatus = New-Object System.Collections.Generic.List[object]

    if (-not $NoDownload) {
        Add-RunLog "Auto-download enabled. Attempting downloads for discovered backup files."

        $configTasks = New-Object System.Collections.Generic.List[object]
        $count = 0
        foreach ($item in $configItems) {
            if ($count -ge $MaxDownloadPerCategory) { break }
            $id = Get-BackupId -Item $item
            if ([string]::IsNullOrWhiteSpace($id)) { Add-ErrorLog "Skipping config item with no backup ID/key."; continue }
            $name = Get-BackupName -Item $item -Prefix "system-config" -Id $id -DefaultExtension ".bak"
            $size = Get-BackupSize -Item $item
            $outFile = Join-Path $outPath $name
            $downloadUri = "$script:BaseUri/wsg/api/scg/backup/config/download?backupUUID=$([System.Uri]::EscapeDataString($id))&timezone=$TimezoneOffset"
            [void]$configTasks.Add((New-DownloadTask -Category "system-config" -Id $id -DisplayName $name -Uri $downloadUri -OutFile $outFile -ExpectedSize $size))
            $count++
        }
        Invoke-DownloadTaskBatch -Category "system-config" -Tasks $configTasks -Session $session -OutputPath $outPath -StatusList $downloadStatus -CaptureDebug:$DebugCapture -RetryCount $RetryCount -RetryDelaySeconds $RetryDelaySeconds

        $switchTasks = New-Object System.Collections.Generic.List[object]
        if ($switchConfigBaseUri) {
            $count = 0
            foreach ($item in $switchItems) {
                if ($count -ge $MaxDownloadPerCategory) { break }
                $id = Get-SwitchConfigId -Item $item
                if ([string]::IsNullOrWhiteSpace($id)) { Add-ErrorLog "Skipping switch config item with no config ID."; continue }
                $name = Get-SwitchConfigName -Item $item -Id $id
                $outFile = Join-Path $outPath $name
                $downloadUri = "$switchConfigBaseUri/download/$([System.Uri]::EscapeDataString($id))"
                [void]$switchTasks.Add((New-DownloadTask -Category "switch-config" -Id $id -DisplayName $name -Uri $downloadUri -OutFile $outFile -ExpectedSize $null))
                $count++
            }
        }
        Invoke-DownloadTaskBatch -Category "switch-config" -Tasks $switchTasks -Session $session -OutputPath $outPath -StatusList $downloadStatus -CaptureDebug:$DebugCapture -RetryCount $RetryCount -RetryDelaySeconds $RetryDelaySeconds

        $clusterTasks = New-Object System.Collections.Generic.List[object]
        $count = 0
        foreach ($item in $clusterItems) {
            if ($count -ge $MaxDownloadPerCategory) { break }
            $id = Get-BackupId -Item $item
            if ([string]::IsNullOrWhiteSpace($id)) { Add-ErrorLog "Skipping cluster item with no backup ID."; continue }
            $bladeUuids = @(Get-ClusterBladeUuids -Item $item)
            if ($bladeUuids.Count -lt 1) { Add-ErrorLog "Cluster backup '$id' did not include blade UUIDs. Skipping."; continue }
            $name = Get-BackupName -Item $item -Prefix "cluster" -Id $id -DefaultExtension ".bak"
            $size = Get-BackupSize -Item $item
            $bladeIndex = 0
            foreach ($bladeUuid in $bladeUuids) {
                if ([string]::IsNullOrWhiteSpace($bladeUuid)) { continue }
                $suffix = if ($bladeUuids.Count -gt 1) { "-" + (($bladeUuid -replace '[\\/:*?"<>|]', '_')) } else { "" }
                $clusterFileName = Add-FileNameSuffix -FileName $name -Suffix $suffix
                $outFile = Join-Path $outPath $clusterFileName
                $downloadUri = "$script:BaseUri/wsg/api/scg/backup/cluster/downloadagent?bladeUUID=$([System.Uri]::EscapeDataString($bladeUuid))&backupUUID=$([System.Uri]::EscapeDataString($id))&timezone=$TimezoneOffset"
                [void]$clusterTasks.Add((New-DownloadTask -Category "cluster" -Id "$id-$bladeIndex" -DisplayName "$name blade $bladeUuid" -Uri $downloadUri -OutFile $outFile -ExpectedSize $size))
                $bladeIndex++
            }
            $count++
        }
        Invoke-DownloadTaskBatch -Category "cluster" -Tasks $clusterTasks -Session $session -OutputPath $outPath -StatusList $downloadStatus -CaptureDebug:$DebugCapture -RetryCount $RetryCount -RetryDelaySeconds $RetryDelaySeconds
    }
    else {
        Add-RunLog "NoDownload selected. Listing completed without downloading files."
    }

    $downloadStatusArray = @()
    foreach ($entry in $downloadStatus) {
        $downloadStatusArray += $entry
    }

    Write-SafeJson -Path (Join-Path $outPath "logs\download-status.json") -Object $downloadStatusArray

    $attempts = 0
    $rawOkCount = 0
    $rawFailCount = 0
    $rawUnavailableCount = 0
    $finalByTask = @{}

    foreach ($entry in $downloadStatusArray) {
        if ($null -eq $entry) { continue }
        $attempts++

        $entrySuccess = $false
        $successProperty = $entry.PSObject.Properties["Success"]
        if ($null -ne $successProperty -and $successProperty.Value -eq $true) { $entrySuccess = $true }

        $entryOutcome = ""
        try {
            $outcomeProperty = $entry.PSObject.Properties["Outcome"]
            if ($null -ne $outcomeProperty) { $entryOutcome = [string]$outcomeProperty.Value }
        } catch {}

        if ($entrySuccess) { $rawOkCount++ }
        elseif ($entry.Category -eq "switch-config" -and ($entryOutcome -eq "EmptyResponse" -or $entryOutcome -eq "MissingOutputFile")) { $rawUnavailableCount++ }
        else { $rawFailCount++ }

        $cat = ""
        $id = ""
        try { $cat = [string]$entry.Category } catch {}
        try { $id = [string]$entry.Id } catch {}
        if ([string]::IsNullOrWhiteSpace($cat)) { $cat = "unknown" }
        if ([string]::IsNullOrWhiteSpace($id)) { $id = [string]$attempts }
        $finalByTask[('{0}|{1}' -f $cat, $id)] = $entry
    }

    $finalTotal = 0
    $finalOkCount = 0
    $finalUnavailableCount = 0
    $finalFailCount = 0
    $failedItems = @()
    $unavailableItems = @()
    $systemDownloaded = 0
    $switchDownloaded = 0
    $clusterDownloaded = 0

    foreach ($key in $finalByTask.Keys) {
        $finalTotal++
        $entry = $finalByTask[$key]
        $entrySuccess = $false
        if ($null -ne $entry) {
            $successProperty = $entry.PSObject.Properties["Success"]
            if ($null -ne $successProperty -and $successProperty.Value -eq $true) { $entrySuccess = $true }
        }
        if ($entrySuccess) {
            $finalOkCount++
            try {
                if ($entry.Category -eq "system-config") { $systemDownloaded++ }
                elseif ($entry.Category -eq "switch-config") { $switchDownloaded++ }
                elseif ($entry.Category -eq "cluster") { $clusterDownloaded++ }
            } catch {}
        }
        else {
            $failedCategory = "unknown"
            $failedId = ""
            $failedDisplayName = ""
            $failedOutFile = ""
            $failedError = ""
            $failedOutcome = ""
            try { $failedCategory = [string]$entry.Category } catch {}
            try { $failedId = [string]$entry.Id } catch {}
            try { $failedDisplayName = [string]$entry.DisplayName } catch {}
            try { $failedOutFile = [string]$entry.OutFile } catch {}
            try { $failedError = [string]$entry.ErrorMessage } catch {}
            try {
                $outcomeProperty = $entry.PSObject.Properties["Outcome"]
                if ($null -ne $outcomeProperty) { $failedOutcome = [string]$outcomeProperty.Value }
            } catch {}

            if ($failedCategory -eq "switch-config" -and ($failedOutcome -eq "EmptyResponse" -or $failedOutcome -eq "MissingOutputFile")) {
                $finalUnavailableCount++
                $unavailableItems += [pscustomobject]@{
                    Category    = $failedCategory
                    Id          = $failedId
                    DisplayName = $failedDisplayName
                    OutFile     = $failedOutFile
                    Outcome     = "UnavailableFromController"
                    Error       = $failedError
                }
            }
            else {
                $finalFailCount++
                $failedItems += [pscustomobject]@{
                    Category    = $failedCategory
                    Id          = $failedId
                    DisplayName = $failedDisplayName
                    OutFile     = $failedOutFile
                    Outcome     = $failedOutcome
                    Error       = $failedError
                }
            }
        }
    }

    $recoveredByRetry = 0
    foreach ($key in $finalByTask.Keys) {
        $entry = $finalByTask[$key]
        $success = $false
        $attemptNumber = 1
        try {
            $successProperty = $entry.PSObject.Properties["Success"]
            if ($null -ne $successProperty -and $successProperty.Value -eq $true) { $success = $true }
            $attemptProperty = $entry.PSObject.Properties["AttemptNumber"]
            if ($null -ne $attemptProperty) { $attemptNumber = [int]$attemptProperty.Value }
        } catch {}
        if ($success -and $attemptNumber -gt 1) { $recoveredByRetry++ }
    }

    Add-RunLog "Download summary: RawAttempts=$attempts RawSuccess=$rawOkCount RawFailed=$rawFailCount RawUnavailable=$rawUnavailableCount RecoveredByRetry=$recoveredByRetry FinalFiles=$finalTotal FinalSuccess=$finalOkCount FinalUnavailable=$finalUnavailableCount FinalFailed=$finalFailCount"
    Add-RunLog "Details: $outPath\logs\download-status.json"

    $runStatus = "Failure"
    $exitCode = 1
    $statusMessage = "SmartZone backup failed."

    if ($NoDownload) {
        $runStatus = "Success"
        $exitCode = 0
        $statusMessage = "SmartZone backup listing completed. NoDownload was selected."
        Add-RunLog "NoDownload selected. Retention cleanup skipped."
    }
    elseif ($attempts -eq 0) {
        $runStatus = "Failure"
        $exitCode = 1
        $statusMessage = "SmartZone backup failed. No download attempts were made."
        Add-RunLog "No download attempts were made. Retention cleanup skipped."
    }
    elseif ($finalFailCount -gt 0) {
        $runStatus = "PartialFailure"
        $exitCode = 2
        $statusMessage = "SmartZone backup partially failed. One or more files failed to download."
        Add-RunLog "One or more final file downloads failed after recovery attempts. Retention cleanup skipped to preserve older backup runs."
    }
    elseif ($finalUnavailableCount -gt 0) {
        $runStatus = "PartialFailure"
        $exitCode = 2
        $statusMessage = "SmartZone backup partially completed. One or more switch configuration records returned empty content after retries and were classified as unavailable from the controller."
        Add-RunLog "One or more switch configuration records returned empty content after retries and were classified as unavailable from the controller. Retention cleanup will still run because downloaded backup files completed successfully."
        Invoke-BackupRunRetention -Root $settings.OutputRoot -Keep $KeepBackupRuns
    }
    else {
        $runStatus = "Success"
        $exitCode = 0
        $statusMessage = "All SmartZone backup files downloaded successfully."
        Invoke-BackupRunRetention -Root $settings.OutputRoot -Keep $KeepBackupRuns
    }

    Write-BackupRunStatus -Root $settings.OutputRoot -RunFolder $outPath -Status $runStatus -ExitCode $exitCode -Started $runStarted -Completed (Get-Date) -BaseHost $settings.BaseHost -Port $settings.Port -NoDownload ([bool]$NoDownload) -SkippedClusterBackups ([bool]$SkipClusterBackups) -SkippedSwitchBackups ([bool]$SkipSwitchBackups) -SystemConfigFound $configItems.Count -SystemConfigDownloaded $systemDownloaded -SwitchConfigFound $switchItems.Count -SwitchConfigDownloaded $switchDownloaded -ClusterFound $clusterItems.Count -ClusterDownloaded $clusterDownloaded -RawAttempts $attempts -RawSuccess $rawOkCount -RawFailed $rawFailCount -RawUnavailable $rawUnavailableCount -FinalFiles $finalTotal -FinalSuccess $finalOkCount -FinalUnavailable $finalUnavailableCount -FinalFailed $finalFailCount -UnavailableItems $unavailableItems -FailedItems $failedItems -Message $statusMessage
    $script:FinalExitCode = $exitCode

    Add-RunLog "Complete. Output folder: $outPath"
}
catch {
    $msg = "Fatal error: $($_.Exception.Message)"
    Add-ErrorLog $msg
    try {
        Write-BackupRunStatus -Root $settings.OutputRoot -RunFolder $outPath -Status "Failure" -ExitCode 1 -Started $runStarted -Completed (Get-Date) -BaseHost $settings.BaseHost -Port $settings.Port -NoDownload ([bool]$NoDownload) -SkippedClusterBackups ([bool]$SkipClusterBackups) -SkippedSwitchBackups ([bool]$SkipSwitchBackups) -SystemConfigFound $configItems.Count -SystemConfigDownloaded 0 -SwitchConfigFound $switchItems.Count -SwitchConfigDownloaded 0 -ClusterFound $clusterItems.Count -ClusterDownloaded 0 -RawAttempts 0 -RawSuccess 0 -RawFailed 0 -RawUnavailable 0 -FinalFiles 0 -FinalSuccess 0 -FinalUnavailable 0 -FinalFailed 1 -UnavailableItems @() -FailedItems @([pscustomobject]@{ Category="fatal"; Id=""; DisplayName="Fatal script error"; OutFile=""; Outcome="Fatal"; Error=$_.Exception.Message }) -Message $msg
    }
    catch {
        Add-ErrorLog "Unable to write failure run status: $($_.Exception.Message)"
    }
    $script:FinalExitCode = 1
}
finally {
    Remove-RunLock -Lock $runLock
}

exit $script:FinalExitCode
