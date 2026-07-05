<#
.SYNOPSIS
    Runs contract-style tests for the RUCKUS SmartZone/vSZ backup script.

.DESCRIPTION
    This runner dot-sources the main script so helper functions are available
    without starting a live backup run, then exercises parsing and selection
    helpers against local fixtures.
#>

[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot '..\Get-RuckusSmartZoneBackup.ps1')
)

$resolvedScriptPath = Resolve-Path -LiteralPath $ScriptPath -ErrorAction Stop
. $resolvedScriptPath.Path

$failures = New-Object System.Collections.Generic.List[string]
$passCount = 0

function Add-Failure {
    param([string]$Message)
    [void]$script:failures.Add($Message)
    Write-Host "FAIL: $Message"
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { Add-Failure $Message; return }
    $script:passCount++
    Write-Host "PASS: $Message"
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    Assert-True -Condition (-not $Condition) -Message $Message
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    $same = $false
    try {
        if ($null -eq $Expected -and $null -eq $Actual) { $same = $true }
        elseif ($Expected -is [System.Collections.IEnumerable] -and -not ($Expected -is [string]) -and $Actual -is [System.Collections.IEnumerable] -and -not ($Actual -is [string])) {
            $expectedArray = @($Expected)
            $actualArray = @($Actual)
            if ($expectedArray.Count -eq $actualArray.Count) {
                $same = $true
                for ($i = 0; $i -lt $expectedArray.Count; $i++) {
                    if ($expectedArray[$i] -ne $actualArray[$i]) { $same = $false; break }
                }
            }
        }
        else {
            $same = ($Expected -eq $Actual)
        }
    }
    catch {
        $same = $false
    }

    if (-not $same) {
        Add-Failure ("{0} (expected: {1}; actual: {2})" -f $Message, ($Expected | Out-String).Trim(), ($Actual | Out-String).Trim())
        return
    }

    $script:passCount++
    Write-Host "PASS: $Message"
}

$fixtures = Join-Path $PSScriptRoot 'fixtures'

Write-Host "Running helper contract tests from $resolvedScriptPath"

$listWrapper = Get-Content -LiteralPath (Join-Path $fixtures 'list-wrapper.json') -Raw | ConvertFrom-Json
$items = @(Get-ListItems -Json $listWrapper)
Assert-Equal 2 $items.Count 'Get-ListItems unwraps nested data.list payloads'
Assert-Equal 'cfg-1' ([string](Get-BackupId -Item $items[0])) 'Get-BackupId reads keys from list items'

$vectorized = Get-Content -LiteralPath (Join-Path $fixtures 'vectorized-record.json') -Raw | ConvertFrom-Json
$records = @(ConvertTo-RecordList -Items $vectorized)
Assert-Equal 2 $records.Count 'ConvertTo-RecordList splits vectorized backup payloads'
Assert-Equal 'switch-a' ([string](Get-FirstProp -Object $records[0] -Names @('switchName'))) 'Split records preserve first vector entry'
Assert-Equal 'switch-b' ([string](Get-FirstProp -Object $records[1] -Names @('switchName'))) 'Split records preserve second vector entry'

$switchItems = @(
    [pscustomobject]@{ id = 'a1'; switchName = 'edge-01'; backupStartTime = '2024-01-01T00:00:00Z' },
    [pscustomobject]@{ id = 'a2'; switchName = 'edge-01'; backupStartTime = '2024-01-02T00:00:00Z' },
    [pscustomobject]@{ id = 'a3'; switchName = 'edge-01'; backupStartTime = '2024-01-03T00:00:00Z' },
    [pscustomobject]@{ id = 'b1'; switchName = 'edge-02'; backupStartTime = '2024-01-01T00:00:00Z' },
    [pscustomobject]@{ id = 'b2'; switchName = 'edge-02'; backupStartTime = '2024-01-04T00:00:00Z' }
)
$selectedSwitch = @(Select-NewestSwitchConfigItemsPerDevice -Items $switchItems -PerDevice 2)
Assert-Equal 4 $selectedSwitch.Count 'Select-NewestSwitchConfigItemsPerDevice keeps newest N per device'
Assert-Equal 'b2' ([string](Get-BackupId -Item $selectedSwitch[0])) 'Switch selection returns newest items first'

$clusterItems = @(
    [pscustomobject]@{ id = 'c1'; backupStartTime = '2024-01-01T00:00:00Z'; blades = @([pscustomobject]@{ bladeUUID = 'blade-1' }) },
    [pscustomobject]@{ id = 'c2'; backupStartTime = '2024-01-02T00:00:00Z'; blades = @([pscustomobject]@{ bladeUUID = 'blade-1' }) },
    [pscustomobject]@{ id = 'c3'; backupStartTime = '2024-01-03T00:00:00Z'; blades = @([pscustomobject]@{ bladeUUID = 'blade-2' }) },
    [pscustomobject]@{ id = 'c4'; backupStartTime = '2024-01-04T00:00:00Z'; blades = @([pscustomobject]@{ bladeUUID = 'blade-2' }) }
)
$selectedCluster = @(Select-NewestClusterBackupItemsPerBlade -Items $clusterItems -PerBlade 1)
Assert-Equal 2 $selectedCluster.Count 'Select-NewestClusterBackupItemsPerBlade keeps newest item per blade'
Assert-Equal 'c4' ([string](Get-BackupId -Item $selectedCluster[0])) 'Cluster selection returns newest records first'

$safeName = ConvertTo-SafeFileName -Name 'CON:<bad>|name?.bak' -DefaultName 'fallback.bak'
Assert-Equal '_CON__bad__name_.bak' $safeName 'ConvertTo-SafeFileName strips invalid Windows filename characters'

$currentUser = Get-Content -LiteralPath (Join-Path $fixtures 'current-user.json') -Raw | ConvertFrom-Json
Assert-Equal 'svc-12345' (Get-ServiceTicketFromCurrentUser -Json $currentUser) 'Get-ServiceTicketFromCurrentUser reads nested tickets'

Assert-False (Test-RetryableDownloadFailure -Category 'switch-config' -Outcome 'RequestFailure' -StatusCode 404 -ErrorMessage '404 not found') '404 switch failures are treated as permanent'
Assert-True (Test-RetryableDownloadFailure -Category 'system-config' -Outcome 'EmptyResponse' -StatusCode $null -ErrorMessage '') 'Empty responses remain retryable'
Assert-True (Test-RetryableDownloadFailure -Category 'cluster' -Outcome 'RequestFailure' -StatusCode 503 -ErrorMessage 'Service unavailable') '503 cluster failures remain retryable'

$pendingStatus = New-Object 'System.Collections.Generic.List[object]'
[void]$pendingStatus.Add([pscustomobject]@{ Category = 'system-config'; Id = 'a1'; Success = $false; Retryable = $false })
[void]$pendingStatus.Add([pscustomobject]@{ Category = 'system-config'; Id = 'a2'; Success = $false; Retryable = $true })
[void]$pendingStatus.Add([pscustomobject]@{ Category = 'system-config'; Id = 'a3'; Success = $true; Retryable = $true })
$pendingTasks = @(
    [pscustomobject]@{ Category = 'system-config'; Id = 'a1' },
    [pscustomobject]@{ Category = 'system-config'; Id = 'a2' },
    [pscustomobject]@{ Category = 'system-config'; Id = 'a3' }
)
$pending = @(Get-PendingDownloadTasks -Tasks $pendingTasks -StatusList $pendingStatus)
Assert-Equal 1 $pending.Count 'Get-PendingDownloadTasks skips non-retryable failures'
Assert-Equal 'a2' ([string]$pending[0].Id) 'Get-PendingDownloadTasks keeps retryable failures'

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host ("{0} test(s) failed, {1} passed." -f $failures.Count, $passCount)
    exit 1
}

Write-Host ("All tests passed: {0}" -f $passCount)
exit 0
