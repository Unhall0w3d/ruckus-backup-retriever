<#
.SYNOPSIS
    Registers a Windows Scheduled Task for Get-RuckusSmartZoneBackup.ps1.

.DESCRIPTION
    Run from an elevated PowerShell prompt after the backup script has already
    completed one successful setup/test run as the same Windows user that will
    run the task.

    Saved SmartZone/vSZ credentials are protected with Windows DPAPI and are
    normally readable only by the same Windows user on the same machine.
#>
[CmdletBinding()]
param(
    [string]$TaskName = "Ruckus SmartZone Backup",
    [string]$ScriptPath = "C:\Scripts\Get-RuckusSmartZoneBackup.ps1",
    [ValidateSet("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday")]
    [string]$DayOfWeek = "Monday",
    [datetime]$At = "09:00",
    [int]$ExecutionTimeLimitHours = 12,
    [int]$RequestTimeoutSeconds = 14400,
    [int]$RetryCount = 2,
    [int]$RetryDelaySeconds = 15,
    [switch]$Force
)

if (-not (Test-Path $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}

$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -RetryCount $RetryCount -RetryDelaySeconds $RetryDelaySeconds -RequestTimeoutSeconds $RequestTimeoutSeconds"

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument $argument

$trigger = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek $DayOfWeek `
    -At $At

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours $ExecutionTimeLimitHours) `
    -MultipleInstances IgnoreNew

if ($Force -and (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Downloads RUCKUS SmartZone/vSZ backups to the configured backup root." `
    -User "$env:USERDOMAIN\$env:USERNAME" `
    -RunLevel Highest
