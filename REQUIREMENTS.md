# Requirements

## Operating system

- Windows Server or Windows desktop capable of running Windows PowerShell 5.1 or newer.
- The script is written for Windows PowerShell 5.1 compatibility because many operational jumpboxes still live there, heroically refusing to modernize.

## PowerShell

- Windows PowerShell 5.1 or newer.
- No third-party PowerShell modules are required.
- The script uses built-in web request/session handling and DPAPI-backed credential export/import.

## Network access

The Windows host running the script must be able to reach SmartZone/vSZ over HTTPS, normally:

```text
TCP 8443
```

The workflow is pull-based. The SmartZone/vSZ controller does not need inbound FTP/SFTP access to the Windows host.

## SmartZone/vSZ access

You need a SmartZone/vSZ account with permissions to:

- Authenticate to the web interface
- View backup records
- Download System Configuration backups
- Download Cluster backups, when available
- View/download Switch Configuration records, when Switch Manager is present

## Disk space

Provide enough local disk space for:

- System Configuration backup files
- Switch Configuration backup text files
- Optional Cluster backup files, which may be several GB each
- One or more timestamped backup run folders depending on retention settings

By default, retention keeps the newest one timestamped backup run folder.

## Certificates

`-SkipCertificateCheck` is enabled by default for operational convenience in environments using private/self-signed certificates. Use `-NoSkipCertificateCheck` if the Windows host trusts the SmartZone/vSZ certificate chain and you want normal certificate validation.

## Credential storage

Credentials are saved with PowerShell `Export-Clixml`. On Windows, this uses DPAPI and is normally decryptable only by the same Windows user on the same machine.

If you run the script as a scheduled task, run the task as the same Windows user that created the saved credential, or rerun the script with `-UpdateCreds` as the scheduled-task user.
