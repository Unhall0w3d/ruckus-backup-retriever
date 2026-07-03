<#
.SYNOPSIS
    Registers a Windows scheduled task for the RUCKUS SmartZone/vSZ Backup Retriever.

.DESCRIPTION
    Creates or replaces a scheduled task that runs Get-RuckusSmartZoneBackup.ps1.
    The task should run as the same Windows user that created the saved DPAPI credential.
#>

[CmdletBinding()]
param(
    [string]$TaskName = "Ruckus SmartZone Backup",
    [string]$ScriptPath = "C:\Scripts\Get-RuckusSmartZoneBackup.ps1",
    [string]$DaysOfWeek = "Monday",
    [string]$At = "9:00AM",
    [switch]$Force
)

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing -and -not $Force) {
    throw "Scheduled task '$TaskName' already exists. Re-run with -Force to replace it."
}

if ($existing -and $Force) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$Trigger = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek $DaysOfWeek `
    -At $At

$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 12) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description "Downloads RUCKUS SmartZone/vSZ backups to local backup storage." `
    -User "$env:USERDOMAIN\$env:USERNAME" `
    -RunLevel Highest

Write-Host "Scheduled task registered: $TaskName"
Write-Host "Script: $ScriptPath"
Write-Host "Schedule: $DaysOfWeek at $At"
Write-Host "Reminder: run the task as the same Windows user that created the saved SmartZone/vSZ credential."
