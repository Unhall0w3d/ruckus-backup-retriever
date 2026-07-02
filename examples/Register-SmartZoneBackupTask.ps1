<#
Registers a Windows Scheduled Task for Get-RuckusSmartZoneBackup.ps1.

Run this from an elevated PowerShell prompt after the script has already been run
successfully once by the same Windows user that will run the task.
#>

[CmdletBinding()]
param(
    [string]$TaskName = "Ruckus SmartZone Backup",
    [string]$ScriptPath = "C:\Scripts\Get-RuckusSmartZoneBackup.ps1",
    [ValidateSet("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday")]
    [string]$DayOfWeek = "Monday",
    [datetime]$At = "06:00"
)

if (-not (Test-Path $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$trigger = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek $DayOfWeek `
    -At $At

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 12) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Downloads RUCKUS SmartZone/vSZ backups to the configured backup root." `
    -User "$env:USERDOMAIN\$env:USERNAME" `
    -RunLevel Highest
