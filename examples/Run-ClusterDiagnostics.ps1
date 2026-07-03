<#
.SYNOPSIS
    Runs cluster endpoint diagnostics without downloading full cluster backup files.
#>

[CmdletBinding()]
param(
    [string]$ScriptPath = "C:\Scripts\Get-RuckusSmartZoneBackup.ps1"
)

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}

& $ScriptPath -ClusterDiagnosticsOnly -SkipSwitchBackups -MaxDownloadPerCategory 1
