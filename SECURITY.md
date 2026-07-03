# Security Policy

Do not publish or attach generated backup files, credential XML files, settings files, HAR captures, debug captures, cookies, tokens, or logs that may contain environment-specific information.

The script stores credentials using PowerShell `Export-Clixml`. On Windows, this uses DPAPI and is normally decryptable only by the same Windows user on the same machine.

Do not post live SmartZone/vSZ hostnames, usernames, passwords, cookies, CSRF tokens, session IDs, backup UUIDs, switch names, customer data, or downloaded backup files in public issues.

If you believe the script exposes sensitive runtime data, open an issue with redacted examples only.
