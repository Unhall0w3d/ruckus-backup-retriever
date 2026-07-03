# Rollout Guide

This guide describes how to deploy `Get-RuckusSmartZoneBackup.ps1` on a Windows host and schedule it to run weekly.

## 1. Choose the Windows host

Use a Windows server, workstation, management VM, or jumpbox that has HTTPS access to the SmartZone/vSZ web interface.

The host should have enough local or mapped storage for the expected backup size. Cluster backups can be large, so confirm storage before scheduling a full run. Yes, finding this out during the first production backup is technically a learning experience, but not a good one.

## 2. Copy the script

Create a stable script directory:

```powershell
New-Item -ItemType Directory -Path "C:\Scripts" -Force
```

Copy the script:

```powershell
Copy-Item ".\Get-RuckusSmartZoneBackup.ps1" "C:\Scripts\Get-RuckusSmartZoneBackup.ps1" -Force
```

## 3. Run the first limited test

Open PowerShell as the Windows account that will run the scheduled task.

Run:

```powershell
cd C:\Scripts
.\Get-RuckusSmartZoneBackup.ps1 -SkipClusterBackups -MaxDownloadPerCategory 1
```

This does three things:

1. Prompts for the SmartZone/vSZ host or FQDN.
2. Prompts for the backup destination root.
3. Prompts for SmartZone/vSZ credentials and saves them encrypted for the current Windows user.

There is no built-in default backup destination. Example:

```text
D:\SmartZoneBackups
```

The `-SkipClusterBackups` switch avoids downloading large Cluster backups during the first test. The `-MaxDownloadPerCategory 1` switch downloads at most one item from each enabled category.

## 4. Validate the test result

Check that the backup root contains a timestamped folder and status file:

```powershell
Get-ChildItem "D:\SmartZoneBackups"
Get-Content "D:\SmartZoneBackups\last-run-status.json" -Raw
```

Replace `D:\SmartZoneBackups` with the backup destination root selected during setup.

## 5. Run a full manual backup

After the limited test succeeds, run the full backup manually once:

```powershell
cd C:\Scripts
.\Get-RuckusSmartZoneBackup.ps1 -RetryCount 2 -RetryDelaySeconds 15 -RequestTimeoutSeconds 14400
```

This verifies the full production workflow, including Cluster backups if available.

## 6. Register the scheduled task

A sample helper script is provided:

```text
examples\Register-SmartZoneBackupTask.ps1
```

Review it before running.

From an elevated PowerShell prompt:

```powershell
cd C:\Path\To\Repo\examples
.\Register-SmartZoneBackupTask.ps1 -DayOfWeek Monday -At "09:00"
```

The task should run as the same Windows user that completed the first successful setup run. Saved credentials are encrypted using Windows DPAPI for that user and machine.

## 7. Test the scheduled task

Start it manually:

```powershell
Start-ScheduledTask -TaskName "Ruckus SmartZone Backup"
```

Check the task result:

```powershell
Get-ScheduledTaskInfo -TaskName "Ruckus SmartZone Backup"
```

Check the backup root for an updated timestamped folder and updated `last-run-status.json`.

## 8. Updating saved settings

Change saved credentials:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -UpdateCreds
```

Reset saved host/output/certificate settings:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -ResetSavedConfig
```

Reset saved credentials:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -ResetSavedCredential
```

## 9. Operational notes

- Keep the script in a stable location, such as `C:\Scripts`.
- Do not schedule the first-run limited test command for production.
- The production scheduled task should normally run the script without `-SkipClusterBackups` or `-MaxDownloadPerCategory`.
- For large Cluster backups, consider using `-RequestTimeoutSeconds 14400`.
- Monitor `last-run-status.json`, Windows Task Scheduler history, and the run logs under each timestamped folder.
- `UnavailableFromController` Switch Configuration records are tracked separately from true download failures.
- Retention runs when only unavailable Switch Configuration records remain, but skips when actual final download failures remain.
