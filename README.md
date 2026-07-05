# RUCKUS SmartZone/vSZ Backup Retriever

PowerShell backup retriever for RUCKUS SmartZone and virtual SmartZone environments.

This project is intended for administrators who need a **pull-based** backup workflow from a Windows host. Instead of opening inbound FTP/SFTP access so SmartZone can push backups somewhere, the script logs in to the SmartZone/vSZ web interface over HTTPS, lists available backup records, and downloads retrievable files locally.

The original use case was a remote client environment with an on-prem Windows jumpbox/multi-use server. The server could reach SmartZone/vSZ over HTTPS, but opening inbound FTP/SFTP to receive backups was not desirable. So the workflow was inverted: the Windows host pulls the backups.

## Current version

`1.31.7`

Version `1.31.7` is a public-repository refresh based on the tested `1.31.6` behavior, with generic first-run backup destination prompting and no environment-specific default output path.

## What it downloads

- **System Configuration** backups
- **Switch Configuration** backups, when Switch Manager backup records are available
- **Cluster** backups, when available

Cluster backups are treated as **opportunistic**. RUCKUS does not expose cluster backups through the same clean scheduled FTP/SFTP export workflow as System Configuration backups. This script attempts to retrieve the newest cluster backup record per blade by default, keeps the file only if the download completes successfully, deletes incomplete cluster files if the download fails, and does not block retention solely because an optional cluster backup failed.

## Current behavior

- Uses the SmartZone/vSZ HTTPS web/API workflow
- Saves reusable local settings under the current Windows user profile
- Saves credentials using Windows DPAPI via PowerShell `Export-Clixml`
- Creates timestamped backup run folders
- Writes `run-status.json` in each run folder
- Writes `last-run-status.json` at the backup root
- Writes detailed logs under each run folder
- Keeps only the newest backup run folder by default
- Retries failed System and Switch downloads
- Classifies empty Switch Configuration records as `UnavailableFromController`
- Filters Switch Configuration records to the newest two per device by default
- Filters Cluster backup records to the newest one per blade by default
- Treats Cluster downloads as best-effort/opportunistic

## Requirements

See [REQUIREMENTS.md](REQUIREMENTS.md) for the full requirements and assumptions.

Short version:

- Windows host capable of running Windows PowerShell 5.1 or newer
- HTTPS reachability from the Windows host to SmartZone/vSZ, usually TCP 8443
- SmartZone/vSZ account with permission to view and download backups
- Local disk space for downloaded backups

## Quick start

Copy the script to a stable folder such as:

```powershell
C:\Scripts\Get-RuckusSmartZoneBackup.ps1
```

Run PowerShell as the Windows user that should own the saved credential. Then run:

```powershell
cd C:\Scripts
.\Get-RuckusSmartZoneBackup.ps1 -SkipClusterBackups -MaxDownloadPerCategory 1
```

On first run, the script prompts for:

- SmartZone/vSZ host or FQDN
- Backup destination root
- Credentials

The script saves the host/output settings and the credential for future runs. Credentials are encrypted using Windows DPAPI and are normally decryptable only by the same Windows user on the same machine.

After the first run succeeds, run a normal backup:

```powershell
.\Get-RuckusSmartZoneBackup.ps1
```

## Common examples

Run a limited validation test without cluster backups:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -SkipClusterBackups -MaxDownloadPerCategory 1
```

Run a normal backup using saved settings:

```powershell
.\Get-RuckusSmartZoneBackup.ps1
```

Update saved credentials:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -UpdateCreds
```

Reset saved settings and credentials:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -ResetSavedConfig -ResetSavedCredential
```

Skip cluster backups entirely:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -SkipClusterBackups
```

Keep only the newest two switch configuration backups per device, which is the default:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -SwitchConfigsPerDevice 2
```

Keep all historical switch configuration backup records returned by SmartZone/Switch Manager:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -SwitchConfigsPerDevice 0
```

Try only the newest cluster backup per blade, which is the default:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -ClusterBackupsPerBlade 1
```

Disable cluster retries, which is the default:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -ClusterRetryCount 0
```

Run cluster endpoint diagnostics without downloading multi-GB cluster files:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -ClusterDiagnosticsOnly -SkipSwitchBackups -MaxDownloadPerCategory 1
```

## Testing

Run the local contract tests from the repository root:

```powershell
.\tests\Run-Tests.ps1
```

The test runner dot-sources the main script without starting a live backup run, then checks the parsing, selection, retry, and credential-ticket helpers against local fixtures.

## Important parameters

| Parameter | Default | Purpose |
| --- | ---: | --- |
| `-BaseHost` | prompted/saved | SmartZone/vSZ host or FQDN |
| `-Port` | `8443` | HTTPS port |
| `-OutputRoot` | prompted/saved | Root folder where timestamped backup folders are created |
| `-SkipCertificateCheck` | enabled by default | Bypass certificate validation for the session |
| `-NoSkipCertificateCheck` | off | Require normal certificate validation |
| `-MaxDownloadPerCategory` | `999` | Limit downloads per category |
| `-SwitchConfigsPerDevice` | `2` | Keep newest N switch config records per device; `0` keeps all |
| `-ClusterBackupsPerBlade` | `1` | Keep newest N cluster records per blade; `0` keeps all |
| `-RetryCount` | `2` | Retry count for System/Switch downloads |
| `-ClusterRetryCount` | `0` | Retry count for Cluster downloads |
| `-RetryDelaySeconds` | `10` | Delay between retry rounds |
| `-RequestTimeoutSeconds` | `0` | Optional timeout passed to web requests; `0` uses default behavior |
| `-SkipClusterBackups` | off | Skip Cluster listing/download |
| `-SkipSwitchBackups` | off | Skip Switch Configuration listing/download |
| `-ClusterDiagnosticsOnly` | off | Probe cluster endpoint headers/range behavior without downloading cluster files |
| `-PruneOnly` | off | Run retention cleanup without downloading |
| `-KeepBackupRuns` | `1` | Number of timestamped backup folders to retain |

## Output structure

Each run creates a timestamped folder under the selected backup root:

```text
<BackupRoot>\<timestamp>\
├── downloaded backup files
├── run-status.json
└── logs\
    ├── run.log
    ├── config-list.json
    ├── cluster-list.json
    ├── switch-list.json
    ├── cluster-download-probes.json
    ├── download-status.json
    └── errors.log
```

If you use `-NoDownload`, the run folder also includes `download-plan.json`.

The backup root also contains:

```text
last-run-status.json
```

## Switch Configuration behavior

SmartZone/Switch Manager may return historical Switch Configuration records. In tested environments, some older records are listed but return empty content when downloaded. The script now keeps only the newest two records per device by default.

If a Switch Configuration download endpoint returns an empty file without an HTTP error after retries, the record is classified as:

```text
UnavailableFromController
```

That classification is treated differently from a real download failure. It means the controller listed a record but did not return content for it.

## Cluster backup behavior

Cluster backups are large and may fail mid-stream when pulled across long-lived HTTPS sessions, especially between cloud-hosted vSZ and an on-prem Windows host. The cluster endpoint tested did not support HTTP range/resumable downloads, so the script cannot resume a partially downloaded cluster file.

Current cluster behavior:

- Downloads newest one cluster backup per blade by default
- Makes one attempt by default
- Deletes incomplete cluster files on failure
- Does not block retention solely because cluster failed
- Logs cluster failures separately

Cluster backups are therefore **nice-to-have**. System and Switch backups are the primary automated deliverables.

## Retention behavior

By default, the script keeps only the newest timestamped backup run folder.

Retention runs when:

- System and Switch backup handling completed without final required download failures
- Only unavailable Switch Configuration records remain
- Only optional Cluster backups failed

Retention is skipped when:

- No downloads were attempted
- Actual final required download failures remain after retries

## Useful SmartZone/vSZ endpoints

The script uses authenticated HTTPS/UI/API endpoints observed from SmartZone/vSZ workflows. These may vary by version.

```text
GET  /wsg/api/scg/backup/config
GET  /wsg/api/scg/backup/config/download?backupUUID=<key>&timezone=<offset>
GET  /wsg/api/scg/backup/cluster
GET  /wsg/api/scg/backup/cluster/downloadagent?bladeUUID=<bladeUUID>&backupUUID=<backupID>&timezone=<offset>
GET  /wsg/api/scg/session/currentUser?_dc=<epoch-ms>
POST /switchm/api/v13_1/switchconfig?_dc=<epoch-ms>&serviceTicket=<ticket>
GET  /switchm/api/v13_1/switchconfig/download/<id>
```

## Scheduling

See [docs/rollout.md](docs/rollout.md) and [examples/Register-SmartZoneBackupTask.ps1](examples/Register-SmartZoneBackupTask.ps1).

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Security notes

Do not publish generated backup files, `settings.json`, credential XML files, HAR captures, debug captures, cookies, tokens, or logs from production environments.

Credentials saved by this script are protected with Windows DPAPI through PowerShell `Export-Clixml`. They are intended to work only for the same Windows user on the same Windows machine.

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

This project is not affiliated with, endorsed by, or supported by RUCKUS, CommScope, or any related vendor. Test carefully before relying on it in production. SmartZone/vSZ APIs and UI-backed endpoints may differ by version.
