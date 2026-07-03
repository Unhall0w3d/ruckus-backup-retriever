# Troubleshooting

## The script prompts for a backup root every run

Confirm the script can write to the current user's application data folder:

```powershell
$env:APPDATA
```

Saved settings are stored under:

```text
%APPDATA%\RuckusBackupApiProbe\settings.json
```

Use `-ResetSavedConfig` if the saved file is corrupt or should be replaced.

## Scheduled task cannot decrypt credentials

Saved credentials are encrypted with Windows DPAPI for the Windows user and machine that created them.

Run the first setup/test as the same Windows user that will run the scheduled task. If the task must run as a different user, log in or run PowerShell as that user and run:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -UpdateCreds
```

## Cluster backup times out

Large Cluster backups may need a longer request timeout:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -RequestTimeoutSeconds 14400
```

`14400` seconds is four hours. Adjust based on environment and backup size.

## Downloaded file size does not match expected size

The script retries size mismatches automatically. If retries still fail, check:

- Available disk space
- Network stability between the Windows host and SmartZone/vSZ
- Proxy/security software that may interrupt long HTTPS downloads
- SmartZone/vSZ controller health

## Switch Configuration records return empty files

Some Switch Manager records may be listed but return empty content from the download endpoint. After retries, the script classifies these as:

```text
UnavailableFromController
```

These records are tracked separately from true download failures. They may indicate stale or non-retrievable records in SmartZone/Switch Manager rather than a local transfer failure.

## Retention did not run

Retention is skipped when actual final download failures remain after retries. This preserves older backup runs instead of deleting the last known better data.

Retention still runs when only `UnavailableFromController` Switch Configuration records remain.

## Certificate warnings on PowerShell 5.1

Windows PowerShell 5.1 does not support `-SkipCertificateCheck` directly for `Invoke-WebRequest`. The script installs a temporary certificate bypass in the current PowerShell session when skip validation is enabled.

To require valid certificate trust, use:

```powershell
.\Get-RuckusSmartZoneBackup.ps1 -NoSkipCertificateCheck
```
