<#
.SYNOPSIS
    Runs a limited SmartZone/vSZ backup test.

.DESCRIPTION
    Useful for first setup. Skips Cluster backups and limits enabled categories
    to one download each so settings and credentials can be validated before a
    full production run.
#>
[CmdletBinding()]
param(
    [string]$ScriptPath = "C:\Scripts\Get-RuckusSmartZoneBackup.ps1",
    [int]$MaxDownloadPerCategory = 1
)

if (-not (Test-Path $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}

& $ScriptPath -SkipClusterBackups -MaxDownloadPerCategory $MaxDownloadPerCategory
