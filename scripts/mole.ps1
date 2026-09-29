[CmdletBinding()]
param(
    [ValidateSet('analyze', 'status', 'clean', 'backup', 'restore', 'providers')]
    [string] $Command = 'analyze',

    [string[]] $Path,

    [string[]] $AllowedRoot,

    [ValidateSet('user-temp', 'dev-cache', 'browser-cache')]
    [string] $Provider = 'user-temp',

    [ValidateRange(-1, 3650)]
    [int] $MinimumAgeDays = -1,

    [string] $BackupRoot,

    [string] $AuditPath,

    [string] $ManifestPath,

    [switch] $Execute
)

$modulePath = Join-Path $PSScriptRoot '..\src\Mole.Windows\Mole.Windows.psd1'
Import-Module (Resolve-Path $modulePath) -Force

switch ($Command) {
    'analyze' {
        if ($Path) {
            if (-not $AllowedRoot) {
                throw 'AllowedRoot is required when analyzing explicit paths.'
            }

            $analysisPlan = @(New-MoleCleanupPlan -CandidatePaths $Path -AllowedRoots $AllowedRoot)
        }
        else {
            $analysisPlan = @(New-MoleProviderPlan -Provider $Provider -MinimumAgeDays $MinimumAgeDays)
        }

        $summary = Get-MoleCleanupSummary -Plan $analysisPlan
        $effectiveAuditPath = $AuditPath
        if (-not $effectiveAuditPath -and $env:LOCALAPPDATA) {
            $effectiveAuditPath = Join-Path $env:LOCALAPPDATA 'Mole\audit\operations.jsonl'
        }
        if (-not $effectiveAuditPath -and $summary.TargetCount -gt 0) {
            throw 'LOCALAPPDATA is unavailable; specify AuditPath to persist the analysis audit event.'
        }

        if ($summary.TargetCount -gt 0) {
            $analysisAllowedRoots = if ($AllowedRoot) {
                $AllowedRoot
            }
            else {
                @($analysisPlan | Where-Object { $_.Action -eq 'Delete' } | ForEach-Object { Split-Path -Parent $_.Path } | Select-Object -Unique)
            }

            if (-not $BackupRoot) {
                if ($env:LOCALAPPDATA) {
                    $BackupRoot = Join-Path $env:LOCALAPPDATA 'Mole\backups'
                }
                else {
                    $BackupRoot = Join-Path (Split-Path -Parent $effectiveAuditPath) '.unused-backups'
                }
            }

            Invoke-MoleCleanupWithBackup `
                -Plan $analysisPlan `
                -BackupRoot $BackupRoot `
                -AllowedRoots $analysisAllowedRoots `
                -AuditPath $effectiveAuditPath | Out-Null
        }

        $summary.Plan | Format-Table ProviderId, BrowserId, Path, Exists, Action, Reason, SizeBytes -AutoSize
        Write-Output ("Analysis: {0} eligible, {1} skipped; estimated reclaimable space {2} MB ({3} bytes)." -f `
                $summary.TargetCount, $summary.SkippedCount, $summary.EstimatedMegabytes, $summary.EstimatedBytes)
        if ($effectiveAuditPath) {
            Write-Output "Audit log: $effectiveAuditPath"
        }
    }
    'status' {
        Write-Output 'Phase 2 status: safety kernel, backup/restore, cleanup providers, and provider-based analysis are available; default mode is dry-run with audit logging.'
    }
    'providers' {
        Get-MoleProviderCatalog | Format-Table -AutoSize
    }
    'backup' {
        if (-not $Path -or -not $AllowedRoot -or -not $BackupRoot) {
            throw 'Backup requires Path, AllowedRoot, and BackupRoot.'
        }

        $plan = New-MoleCleanupPlan -CandidatePaths $Path -AllowedRoots $AllowedRoot
        Invoke-MoleBackup -Plan $plan -BackupRoot $BackupRoot | Format-List
    }
    'restore' {
        if (-not $ManifestPath) {
            throw 'Restore requires ManifestPath.'
        }

        Restore-MoleBackup -ManifestPath $ManifestPath -Force:$Execute | Format-Table -AutoSize
    }
    'clean' {
        $providerPlan = New-MoleProviderPlan -Provider $Provider -MinimumAgeDays $MinimumAgeDays
        if (-not $providerPlan) {
            Write-Output "No eligible targets found for provider '$Provider'."
            break
        }

        if ($Execute -and -not $BackupRoot) {
            throw 'Execute requires an explicit BackupRoot so every target can be restored.'
        }

        if (-not $env:LOCALAPPDATA -and (-not $AuditPath -or (-not $BackupRoot -and $Execute))) {
            throw 'LOCALAPPDATA is unavailable; specify AuditPath and, for execution, BackupRoot.'
        }

        if (-not $AuditPath) {
            $AuditPath = Join-Path $env:LOCALAPPDATA 'Mole\audit\operations.jsonl'
        }
        if (-not $BackupRoot) {
            if ($env:LOCALAPPDATA) {
                $BackupRoot = Join-Path $env:LOCALAPPDATA 'Mole\backups'
            }
            else {
                $BackupRoot = Join-Path (Split-Path -Parent $AuditPath) '.unused-backups'
            }
        }

        $cleanArguments = @{
            Plan         = $providerPlan
            BackupRoot   = $BackupRoot
            AllowedRoots = @($providerPlan | ForEach-Object { Split-Path -Parent $_.Path } | Select-Object -Unique)
            AuditPath    = $AuditPath
        }
        if ($Execute) {
            $cleanArguments.Execute = $true
            $cleanArguments.Confirm = $false
        }

        $result = Invoke-MoleCleanupWithBackup @cleanArguments
        if ($Execute -and $result.Executed) {
            $result | Format-List
        }
        else {
            $result.Results | Format-Table ProviderId, BrowserId, Path, Exists, Action, Reason, SizeBytes -AutoSize
            $megabytes = [math]::Round(($result.EstimatedBytes / 1MB), 2)
            Write-Output ("Estimated reclaimable space: {0} MB ({1} bytes). No files were changed." -f $megabytes, $result.EstimatedBytes)
            Write-Output "Audit log: $AuditPath"
        }
    }
}
