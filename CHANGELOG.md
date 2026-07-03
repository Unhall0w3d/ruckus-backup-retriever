# Changelog

## 1.31.7

- Public repository refresh based on tested v1.31.6 behavior.
- Removes environment-specific default backup destination from first-run prompting and help text.
- Updates README, requirements, rollout guide, troubleshooting guide, and examples for v1.31.x behavior.

## 1.31.6

- Fixes PowerShell 5.1 array wrapping in normalized lists and download task batches.
- Fixes download batches receiving wrapped arrays instead of task objects.

## 1.31.5

- Normalizes API list responses that are returned as one object with array-valued properties.
- Fixes controllers that return System Configuration, Cluster, or Switch Configuration records in a vectorized shape.

## 1.31.4

- Adds defensive output path construction and pre-download task logging.

## 1.31.3

- Improves Windows-safe filename handling.
- Improves Switch Configuration grouping for environments with different metadata shapes.

## 1.31.2

- Treats Cluster backups as opportunistic.
- Deletes incomplete Cluster backup files on failure.
- Adds `ClusterRetryCount`, default `0`.
- Adds `ClusterBackupsPerBlade`, default `1`.
- Allows retention to run when only optional Cluster backups fail.

## 1.31.1

- Adds `SwitchConfigsPerDevice`, default `2`.
- Keeps only the newest N Switch Configuration records per device by default.
- Fixes Cluster diagnostics array handling when one endpoint is queued.

## 1.31.0

- Adds Cluster endpoint diagnostics.
- Adds `ClusterDiagnosticsOnly`, `NoClusterHeaderProbe`, and `ClusterProbeTimeoutSeconds`.
- Applies `RequestTimeoutSeconds` to web requests.

## 1.30.x

- Adds retry handling for failed, empty, timed-out, and size-mismatched downloads.
- Adds `UnavailableFromController` classification for Switch Configuration records returning empty content.
- Allows retention when only unavailable Switch Configuration records remain.
