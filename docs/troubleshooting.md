# Troubleshooting

## The script prompts again for host or output root

Saved settings are stored under the current Windows user profile:

```text
%APPDATA%\RuckusBackupApiProbe\settings.json
```

If you run the script as a different Windows user, it will not see the same saved settings.

## The scheduled task cannot decrypt credentials

Credentials are saved with PowerShell `Export-Clixml` using Windows DPAPI. They are normally decryptable only by the same Windows user on the same machine.

Fix:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -UpdateCreds
```

Run that command as the same Windows user that will run the scheduled task.

## Switch Configuration records return empty files

Some SmartZone/Switch Manager environments return historical switch configuration records that no longer produce downloadable content. The script classifies those as:

```text
UnavailableFromController
```

This is not treated the same as a normal download failure. By default, the script keeps only the newest two switch configuration records per device to avoid chasing stale history.

To keep all historical switch records:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -SwitchConfigsPerDevice 0
```

## Switch Configuration selected count looks wrong

Different SmartZone/Switch Manager versions may return slightly different record shapes. The script attempts to group records by device using available metadata and rendered filenames. If grouping looks wrong, run with debug capture and review:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -SkipClusterBackups -DebugCapture
```

Then inspect:

```text
logs\switch-list.json
logs\download-status.json
```

Do not post unredacted logs publicly.

## Cluster backups fail mid-download

Cluster backups can be several GB and may fail across long-lived HTTPS sessions, especially when vSZ is cloud-hosted and the backup host is on-prem.

Common causes include:

- Firewall/NAT idle timeout
- Proxy or SSL inspection timeout
- WAN instability or packet loss
- Cloud/load-balancer response timeout
- Controller-side stream timeout
- Local storage pauses

The tested cluster endpoint did not support HTTP range/resumable downloads. If a cluster download fails, the script deletes the incomplete file and moves on.

Cluster backups are opportunistic by design.

## Cluster diagnostics

To probe cluster download endpoint behavior without downloading multi-GB files:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -ClusterDiagnosticsOnly -SkipSwitchBackups -MaxDownloadPerCategory 1
```

Review:

```text
logs\cluster-download-probes.json
```

Useful indicators:

```text
RangeStatusCode = 206
RangeSupported  = True
```

If the endpoint returns `200` instead of `206`, it is probably ignoring the range request and does not support resumable download in the way this script needs.

## Retention did not remove older folders

Retention skips cleanup when actual final required download failures remain. It still runs when only optional cluster backups fail or when switch records are classified as `UnavailableFromController`.

To run retention only:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -PruneOnly
```

## Certificate validation warning in PowerShell 5.1

Windows PowerShell 5.1 does not support `-SkipCertificateCheck` directly on `Invoke-WebRequest`. The script installs a temporary certificate bypass for the session when certificate checking is skipped. Yes, it is ugly. No, you are not imagining it.

Use `-NoSkipCertificateCheck` if the Windows host trusts the SmartZone/vSZ certificate chain.
