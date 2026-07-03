# Changelog

## 1.30.5

- Public repository refresh based on v1.30.4 behavior.
- Removes environment-specific default backup path from first-run prompt/help text.
- Keeps retry handling for failed, empty, timed-out, and size-mismatched downloads.
- Keeps `UnavailableFromController` classification for Switch Configuration records that return empty content after retries.
- Keeps retention behavior that still runs when only unavailable Switch Configuration records remain.
- Updates README, rollout guide, troubleshooting guide, and scheduled task example.

## 1.30.4

- Allows retention cleanup to run when only `UnavailableFromController` Switch Configuration records remain.
- Retention remains skipped when actual final download failures remain after retries.

## 1.30.3

- Separates empty Switch Configuration download responses into `UnavailableFromController`.
- Adds unavailable counts to download/status summaries.

## 1.30.2

- Fixes retry array handling for Windows PowerShell 5.1.
- Updates runtime banner/version logging.

## 1.30.1

- Fixes PowerShell 5.1 parser issue in retry round logging.

## 1.30.0

- Adds retry handling for failed, empty, timed-out, and size-mismatched downloads.
- Adds `RetryCount`, `RetryDelaySeconds`, and `RequestTimeoutSeconds` parameters.
- Adds clearer download failure metadata.
