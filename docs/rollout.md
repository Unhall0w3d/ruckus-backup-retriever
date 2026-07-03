# Rollout Guide

This guide describes a basic deployment using a Windows host as a pull-based backup retriever.

## 1. Create a script folder

```powershell
New-Item -ItemType Directory -Path "C:\Scripts" -Force
```

Copy the script to:

```text
C:\Scripts\Get-RuckusSmartZoneBackup.ps1
```

## 2. Run a limited first test

Open PowerShell as the Windows account that should own the saved credential.

```powershell
cd C:\Scripts
.\Get-RuckusSmartZoneBackup.ps1 -SkipClusterBackups -MaxDownloadPerCategory 1
```

On first run, provide:

- SmartZone/vSZ host or FQDN
- Backup destination root
- SmartZone/vSZ credentials

This establishes saved settings and a DPAPI-protected credential file under the current Windows user profile.

## 3. Validate output

After the test run, confirm that a timestamped folder was created under the selected backup root and that `last-run-status.json` exists at the root.

```powershell
Get-ChildItem "<BackupRoot>" -Directory | Sort-Object Name -Descending | Select-Object -First 5
Get-Content "<BackupRoot>\last-run-status.json" -Raw
```

## 4. Run a normal backup manually

```powershell
.\Get-RuckusSmartZoneBackup.ps1
```

Default behavior:

- System Configuration backups are downloaded with retry handling
- Switch Configuration records are filtered to newest two per device
- Cluster backups are attempted opportunistically, newest one per blade
- Incomplete cluster files are deleted if the cluster transfer fails
- Retention still runs if only optional cluster downloads fail

## 5. Register a scheduled task

A helper example is included:

```powershell
.\examples\Register-SmartZoneBackupTask.ps1
```

By default, it creates a task named `Ruckus SmartZone Backup` that runs Mondays at 9:00 AM using:

```text
C:\Scripts\Get-RuckusSmartZoneBackup.ps1
```

The task should run as the same Windows user that created the saved SmartZone/vSZ credential.

## 6. Useful scheduled-task command

If you prefer to create it manually:

```powershell
$TaskName = "Ruckus SmartZone Backup"
$ScriptPath = "C:\Scripts\Get-RuckusSmartZoneBackup.ps1"

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$Trigger = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek Monday `
    -At 9:00AM

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
```

## 7. Test the scheduled task

```powershell
Start-ScheduledTask -TaskName "Ruckus SmartZone Backup"
Get-ScheduledTaskInfo -TaskName "Ruckus SmartZone Backup"
```

## 8. Retention

Default retention keeps the newest one timestamped backup run folder.

Retention is skipped for actual final required download failures, but still runs when only optional cluster backups fail or when switch records are classified as unavailable from the controller.
