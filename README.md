# RUCKUS SmartZone/vSZ Backup Retriever

PowerShell backup retriever for RUCKUS SmartZone and virtual SmartZone environments.

This project is intended for administrators who need a **pull-based** backup workflow from a Windows host. Instead of opening inbound FTP/SFTP access so SmartZone can push backups somewhere, the script logs in to the SmartZone/vSZ web interface over HTTPS, lists available backups, and downloads them locally.

## What it downloads

- System Configuration backups
- Switch Configuration backups, when Switch Manager backup records are available
- Cluster backups, when available

## Current behavior

- Uses the SmartZone/vSZ HTTPS web/API workflow
- Saves reusable local settings under the current Windows user profile
- Saves credentials using Windows DPAPI via PowerShell `Export-Clixml`
- Creates timestamped backup run folders
- Writes `run-status.json` in each run folder
- Writes `last-run-status.json` at the backup root
- Retries failed, empty, timed-out, and size-mismatched downloads
- Classifies empty Switch Configuration records as `UnavailableFromController` after retries
- Performs retention when downloads succeeded, even if some Switch Configuration records were unavailable from the controller
- Skips retention when actual final download failures remain, to preserve older backup runs

## Requirements

- Windows PowerShell 5.1 or later
- Windows host with HTTPS access to the SmartZone/vSZ web interface
- SmartZone/vSZ account with permission to view and download backups
- Local or mapped storage location for downloaded backups

No third-party PowerShell modules are required.

## Repository contents

```text
.
├── Get-RuckusSmartZoneBackup.ps1
├── README.md
├── docs
│   ├── rollout.md
│   └── troubleshooting.md
├── examples
│   ├── Register-SmartZoneBackupTask.ps1
│   └── Run-LimitedTest.ps1
├── .gitignore
├── CHANGELOG.md
├── LICENSE
└── SECURITY.md
```

## Quick start

Create a stable local script folder and copy the script into it:

```powershell
New-Item -ItemType Directory -Path "C:\Scripts" -Force
Copy-Item ".\Get-RuckusSmartZoneBackup.ps1" "C:\Scripts\Get-RuckusSmartZoneBackup.ps1" -Force
```

Run a limited first test:

```powershell
cd C:\Scripts
.\Get-RuckusSmartZoneBackup.ps1 -SkipClusterBackups -MaxDownloadPerCategory 1
```

On first run, the script prompts for:

- SmartZone/vSZ host or FQDN
- Backup destination root
- SmartZone/vSZ credentials

There is **no built-in default backup destination**. Choose a path appropriate for your environment, for example:

```text
D:\SmartZoneBackups
```

The limited test establishes saved settings and credentials while avoiding large Cluster backup downloads.

## Full backup run

After the limited test succeeds, run the script without test limits:

```powershell
cd C:\Scripts
.\Get-RuckusSmartZoneBackup.ps1
```

This downloads all discovered backup categories unless parameters are used to skip or limit them.

## Common parameters

### Connection and storage

```powershell
-BaseHost <host-or-fqdn>
```

SmartZone/vSZ host or FQDN. Prompted and saved on first run if omitted.

```powershell
-OutputRoot <path>
```

Root folder where timestamped backup run folders are created. Prompted and saved on first run if omitted.

```powershell
-Port <number>
```

HTTPS port for this run. Default is `8443`. The port is not prompted for and is not saved.

### Backup selection

```powershell
-SkipClusterBackups
```

Skips Cluster backup listing and download. Useful for first-run testing.

```powershell
-SkipSwitchBackups
```

Skips Switch Configuration backup listing and download.

```powershell
-MaxDownloadPerCategory <number>
```

Limits how many files are downloaded per category. Useful for validation testing.

### Retry behavior

```powershell
-RetryCount <number>
```

Number of retry rounds for failed or incomplete downloads. Default: `2`.

```powershell
-RetryDelaySeconds <number>
```

Delay between retry rounds. Default: `10`.

```powershell
-RequestTimeoutSeconds <number>
```

Optional per-request timeout. Default: `0`, which leaves the PowerShell/web request default behavior in place. This can be useful for large Cluster backup downloads.

Example:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -RetryCount 2 -RetryDelaySeconds 15 -RequestTimeoutSeconds 14400
```

### Retention

```powershell
-KeepBackupRuns <number>
```

Keeps only the newest timestamped backup run folders after successful/recoverable runs. Default: `1`.

Retention still runs when Switch Configuration records are classified as `UnavailableFromController`. Retention is skipped when actual final download failures remain after retries.

### Saved settings and credentials

```powershell
-UpdateCreds
```

Replaces the saved SmartZone/vSZ credential.

```powershell
-ResetSavedConfig
```

Removes saved host/output/certificate settings and prompts again.

```powershell
-ResetSavedCredential
```

Removes the saved credential and prompts again.

```powershell
-ShowHelp
```

Displays built-in help.

## Scheduling

A sample scheduled task helper is included:

```text
examples\Register-SmartZoneBackupTask.ps1
```

Example:

```powershell
cd .\examples
.\Register-SmartZoneBackupTask.ps1 -DayOfWeek Monday -At "09:00"
```

By default, the example registers a weekly backup task that runs:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Get-RuckusSmartZoneBackup.ps1"
```

The scheduled task should run as the same Windows user that performed the first successful setup run. Saved credentials are encrypted using Windows DPAPI and are normally readable only by the same Windows user on the same machine.

## Output structure

Each run creates a timestamped folder under the selected backup root:

```text
<OutputRoot>
├── last-run-status.json
└── yyyyMMdd-HHmmss
    ├── run-status.json
    ├── logs
    │   ├── run.log
    │   ├── download-status.json
    │   ├── config-list.json
    │   ├── switch-list.json
    │   ├── cluster-list.json
    │   └── errors.log
    └── downloaded backup files
```

Some list/log files are only created when that category is retrieved or when errors occur.

## Status values

The backup script writes one of these run statuses:

```text
Success
PartialFailure
Failure
```

`Success` means the workflow completed and all final required downloads succeeded.

`PartialFailure` means the workflow completed but one or more listed files did not produce a usable download. This can include Switch Configuration records classified as `UnavailableFromController`.

`Failure` means the script could not complete the backup workflow.

## Switch Configuration unavailable records

Some SmartZone/Switch Manager environments may return Switch Configuration records that produce empty content when downloaded. After retries, these are classified as:

```text
UnavailableFromController
```

These are tracked separately from true download failures. This avoids treating stale or non-retrievable controller records the same as a timeout, partial file, or request failure.

## Useful API/UI endpoints

The script follows SmartZone/vSZ web and API behavior observed from the UI workflow. Useful endpoints involved include:

```text
GET  /wsg/api/scg/backup/config
GET  /wsg/api/scg/backup/config/download?backupUUID=<backupUUID>&timezone=<offset>
GET  /wsg/api/scg/backup/cluster
GET  /wsg/api/scg/backup/cluster/downloadagent?bladeUUID=<bladeUUID>&backupUUID=<backupUUID>&timezone=<offset>
GET  /wsg/api/scg/session/currentUser
POST /switchm/api/v13_1/switchconfig
GET  /switchm/api/v13_1/switchconfig/download/<id>
```

These endpoints may vary by SmartZone/vSZ version. Test before relying on this in production.

## Credential storage

Credentials are saved using PowerShell `Export-Clixml`, which uses Windows DPAPI on Windows. The saved credential is encrypted for the Windows user and machine that created it.

If the script is later run as a different Windows account, run:

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

The script does not include hardcoded customer hostnames, IP addresses, usernames, passwords, cookies, tokens, backup UUIDs, or environment-specific backup paths. Runtime settings and credentials are created locally on the machine where the script runs.

Do not commit generated files such as credentials, settings JSON, downloaded backups, logs, HAR captures, debug captures, or customer-specific output.

## Disclaimer

This project is community-provided automation and is not affiliated with, endorsed by, or supported by RUCKUS Networks. Test in your own environment before relying on it for production backup workflows.
