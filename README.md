# RUCKUS SmartZone/vSZ Backup Downloader

PowerShell backup downloader for RUCKUS SmartZone and virtual SmartZone environments.

The script logs in to the SmartZone/vSZ web interface over HTTPS, lists available backup files, and downloads System Configuration, Switch Configuration, and Cluster backups into timestamped local folders. It is intended for administrators who want a pull-based backup workflow from a Windows machine instead of exposing FTP/SFTP services to the controller.

## Features

- Downloads SmartZone/vSZ System Configuration backups
- Downloads Switch Configuration backups when available
- Downloads Cluster backups when available
- Stores backups in timestamped run folders
- Writes `run-status.json` in each run folder
- Writes `last-run-status.json` at the backup root
- Saves reusable settings under the current Windows user profile
- Saves credentials using Windows DPAPI through PowerShell `Export-Clixml`
- Supports retention for successful backup runs
- Supports a lightweight first test run that skips Cluster backups and limits downloads

## Requirements

- Windows PowerShell 5.1 or later
- Windows machine with HTTPS access to the SmartZone/vSZ web interface
- SmartZone/vSZ account with permission to view and download backups
- Local or mapped storage path for downloaded backups

No third-party PowerShell modules are required.

## Repository contents

```text
.
├── Get-RuckusSmartZoneBackup.ps1
├── README.md
├── docs
│   └── rollout.md
├── examples
│   └── Register-SmartZoneBackupTask.ps1
├── .gitignore
├── LICENSE
└── SECURITY.md
```

## Quick start

Create a local script folder and copy the script into it:

```powershell
New-Item -ItemType Directory -Path "C:\Scripts" -Force
Copy-Item ".\Get-RuckusSmartZoneBackup.ps1" "C:\Scripts\Get-RuckusSmartZoneBackup.ps1" -Force
```

Run a limited first test. This establishes saved settings and credentials while avoiding large Cluster backup downloads:

```powershell
cd C:\Scripts
.\Get-RuckusSmartZoneBackup.ps1 -SkipClusterBackups -MaxDownloadPerCategory 1
```

On first run, the script prompts for:

- SmartZone/vSZ host or FQDN
- Backup destination root
- SmartZone/vSZ web UI credentials

The backup destination root is required. There is no built-in default path. Use a location appropriate for your environment, such as:

```text
D:\SmartZoneBackups
```

After the test run, confirm that `last-run-status.json` exists in the selected backup root and that at least one timestamped backup folder was created.

## Full backup run

After the limited test succeeds, run the script without test limits:

```powershell
.\Get-RuckusSmartZoneBackup.ps1
```

This downloads all available backup types unless switches are provided to skip categories or limit counts.

## Common parameters

```powershell
-BaseHost <host-or-fqdn>
```
SmartZone/vSZ host or FQDN. Prompted and saved on first run if omitted.

```powershell
-OutputRoot <path>
```
Root folder where backup run folders are created. Required on first run if omitted, then saved for future runs.

```powershell
-SkipClusterBackups
```
Skip Cluster backup downloads. Useful for first-run testing because Cluster backups can be large.

```powershell
-SkipSwitchBackups
```
Skip Switch Configuration backup downloads.

```powershell
-MaxDownloadPerCategory <number>
```
Limit how many files are downloaded per backup category. Useful for validation testing.

```powershell
-KeepBackupRuns <number>
```
Keep only the newest successful backup run folders. The default is `1`.

```powershell
-UpdateCreds
```
Replace the saved SmartZone/vSZ credential.

```powershell
-ResetSavedConfig
```
Remove saved host/output/certificate settings and prompt again.

```powershell
-ResetSavedCredential
```
Remove the saved credential and prompt again.

```powershell
-ShowHelp
```
Display built-in help.

## Scheduling

A sample scheduled task script is included at:

```text
examples\Register-SmartZoneBackupTask.ps1
```

Run it from an elevated PowerShell prompt after reviewing the script path and schedule.

By default, the example registers a weekly backup task for Monday at 6:00 AM and runs:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Get-RuckusSmartZoneBackup.ps1"
```

The scheduled task should run as the same Windows user that performed the first successful setup run. Saved credentials are encrypted using Windows DPAPI and are normally only readable by the same Windows user on the same machine.

## Output structure

Each backup run creates a timestamped folder under the selected backup root:

```text
<OutputRoot>
├── last-run-status.json
└── yyyyMMdd-HHmmss
    ├── run-status.json
    ├── logs
    │   ├── run.log
    │   └── errors.log
    └── downloaded backup files
```

`last-run-status.json` provides the latest run result. `run-status.json` provides details for that specific timestamped run.

## Status values

The backup script writes one of these run statuses:

```text
Success
PartialFailure
Failure
```

A successful run means all attempted final downloads completed successfully. A partial failure means one or more files failed while others succeeded. A failure means the script could not complete the backup workflow.

## Credential storage

Credentials are saved using PowerShell `Export-Clixml`, which uses Windows DPAPI on Windows. This means the saved credential is encrypted for the Windows user and machine that created it.

If the script is later run as a different Windows account, use:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -UpdateCreds
```

while logged in as that account.

## Certificate validation

By default, the script skips certificate validation for compatibility with privately issued or self-signed SmartZone/vSZ certificates.

To require valid certificate trust, run:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -NoSkipCertificateCheck
```

## Public repository safety notes

The script does not include hardcoded hostnames, IP addresses, usernames, passwords, cookies, tokens, backup UUIDs, or environment-specific backup paths. Runtime settings and credentials are created locally on the machine where the script runs.

Do not commit generated files such as credentials, settings JSON, downloaded backups, logs, HAR captures, or debug captures in Issues, or Pull requests.

## Disclaimer

This project is community-provided automation and is not affiliated with, endorsed by, or supported by RUCKUS Networks. Test in your own environment before relying on it for production backup workflows.
