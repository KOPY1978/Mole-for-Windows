Describe 'Mole for Windows safety kernel' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\src\Mole.Windows\Mole.Windows.psd1'
        Import-Module (Resolve-Path $modulePath) -Force
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    BeforeEach {
        $allowed = Join-Path $TestDrive 'allowed'
        $protected = Join-Path $TestDrive 'protected'
        New-Item -ItemType Directory -Path $allowed -Force | Out-Null
        New-Item -ItemType Directory -Path $protected -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $allowed 'candidate.tmp') -Value 'fixture'
        Set-Content -LiteralPath (Join-Path $protected 'important.txt') -Value 'fixture'
    }

    It 'creates a delete plan only inside the allowlist' {
        $candidate = Join-Path $allowed 'candidate.tmp'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $allowed -ProtectedRoots $protected

        Assert-MoleEqual $plan.Action 'Delete'
        Assert-MoleTrue $plan.Exists
    }

    It 'skips paths outside the allowlist' {
        $candidate = Join-Path $protected 'important.txt'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $allowed -ProtectedRoots $protected

        Assert-MoleEqual $plan.Action 'Skip'
        Assert-MoleEqual $plan.Reason 'OutsideAllowList'
    }

    It 'skips protected paths even when allowlisted' {
        $candidate = Join-Path $protected 'important.txt'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $protected -ProtectedRoots $protected

        Assert-MoleEqual $plan.Action 'Skip'
        Assert-MoleEqual $plan.Reason 'ProtectedPath'
    }

    It 'never treats the allowlisted root itself as a deletion target' {
        $plan = New-MoleCleanupPlan -CandidatePaths $allowed -AllowedRoots $allowed -ProtectedRoots $protected

        Assert-MoleEqual $plan.Action 'Skip'
        Assert-MoleEqual $plan.Reason 'AllowRoot'
    }

    It 'does not delete during dry-run execution' {
        $candidate = Join-Path $allowed 'candidate.tmp'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $allowed -ProtectedRoots $protected

        Invoke-MoleCleanupPlan -Plan $plan | Out-Null
        Assert-MoleTrue (Test-Path -LiteralPath $candidate)
    }

    It 'refuses destructive execution before backup support exists' {
        $candidate = Join-Path $allowed 'candidate.tmp'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $allowed -ProtectedRoots $protected

        Assert-MoleThrows { Invoke-MoleCleanupPlan -Plan $plan -Execute }
    }

    It 'backs up a file and restores it with hash verification' {
        $candidate = Join-Path $allowed 'candidate.tmp'
        $backupRoot = Join-Path $TestDrive 'backups'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $allowed -ProtectedRoots $protected

        $backup = Invoke-MoleBackup -Plan $plan -BackupRoot $backupRoot
        Assert-MoleTrue (Test-Path -LiteralPath $backup.ManifestPath)

        Remove-Item -LiteralPath $candidate -Force
        Assert-MoleFalse (Test-Path -LiteralPath $candidate)

        $restore = Restore-MoleBackup -ManifestPath $backup.ManifestPath
        Assert-MoleEqual $restore.Action 'Restored'
        Assert-MoleTrue (Test-Path -LiteralPath $candidate)
        Assert-MoleEqual (Get-Content -LiteralPath $candidate -Raw).Trim() 'fixture'
    }

    It 'rejects a backup root that overlaps a cleanup target' {
        $candidate = Join-Path $allowed 'candidate.tmp'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $allowed -ProtectedRoots $protected

        Assert-MoleThrows { Invoke-MoleBackup -Plan $plan -BackupRoot $allowed }
    }

    It 'backs up and deletes only after explicit execution' {
        $candidate = Join-Path $allowed 'candidate.tmp'
        $backupRoot = Join-Path $TestDrive 'execution-backups'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $allowed -ProtectedRoots $protected

        $preview = Invoke-MoleCleanupWithBackup `
            -Plan $plan `
            -BackupRoot $backupRoot `
            -AllowedRoots $allowed `
            -ProtectedRoots $protected

        Assert-MoleFalse $preview.Executed
        Assert-MoleTrue (Test-Path -LiteralPath $candidate)
        Assert-MoleNullOrEmpty $preview.ManifestPath

        $result = Invoke-MoleCleanupWithBackup `
            -Plan $plan `
            -BackupRoot (Join-Path $TestDrive 'execution-backups-2') `
            -AllowedRoots $allowed `
            -ProtectedRoots $protected `
            -Execute `
            -Confirm:$false

        Assert-MoleTrue $result.Executed
        Assert-MoleFalse (Test-Path -LiteralPath $candidate)
        Assert-MoleTrue (Test-Path -LiteralPath $result.ManifestPath)
    }

    It 'exposes the user-temp provider in the catalog' {
        $catalog = @(Get-MoleProviderCatalog)

        Assert-MoleEqual (@($catalog | Where-Object { $_.Id -eq 'user-temp' })).Count 1
    }

    It 'exposes the developer-cache provider in the catalog' {
        $catalog = @(Get-MoleProviderCatalog)

        Assert-MoleEqual (@($catalog | Where-Object { $_.Id -eq 'dev-cache' })).Count 1
        Assert-MoleEqual ($catalog | Where-Object Id -eq 'dev-cache').DefaultMinimumAgeDays 14
    }

    It 'exposes the browser-cache provider in the catalog' {
        $catalog = @(Get-MoleProviderCatalog)

        Assert-MoleEqual (@($catalog | Where-Object { $_.Id -eq 'browser-cache' })).Count 1
        Assert-MoleEqual ($catalog | Where-Object Id -eq 'browser-cache').DefaultMinimumAgeDays 14
    }

    It 'finds stale developer cache files but skips lock files' {
        $cacheRoot = Join-Path $TestDrive 'dev-cache'
        New-Item -ItemType Directory -Path (Join-Path $cacheRoot 'nested') -Force | Out-Null

        $stale = Join-Path $cacheRoot 'nested\old-package.tgz'
        $lock = Join-Path $cacheRoot 'nested\old-package.lock'
        Set-Content -LiteralPath $stale -Value 'cache'
        Set-Content -LiteralPath $lock -Value 'lock'

        $old = (Get-Date).AddDays(-30)
        (Get-Item -LiteralPath $stale).LastWriteTime = $old
        (Get-Item -LiteralPath $lock).LastWriteTime = $old

        $roots = @([pscustomobject]@{
                Id    = 'fixture'
                Title = 'Fixture cache'
                Root  = $cacheRoot
            })
        $candidates = @(Get-MoleCacheCandidates -Roots $roots -MinimumAgeDays 14)

        Assert-MoleEqual (@($candidates | Where-Object { $_.Path -eq (Get-MoleCanonicalPath -Path $stale) })).Count 1
        Assert-MoleEqual (@($candidates | Where-Object { $_.Path -eq (Get-MoleCanonicalPath -Path $lock) })).Count 0
    }

    It 'does not return recent developer cache files' {
        $cacheRoot = Join-Path $TestDrive 'recent-cache'
        New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null

        $recent = Join-Path $cacheRoot 'recent-package.tgz'
        Set-Content -LiteralPath $recent -Value 'cache'

        $roots = @([pscustomobject]@{
                Id    = 'fixture'
                Title = 'Fixture cache'
                Root  = $cacheRoot
            })
        $candidates = @(Get-MoleCacheCandidates -Roots $roots -MinimumAgeDays 14)

        Assert-MoleEqual (@($candidates | Where-Object { $_.Path -eq (Get-MoleCanonicalPath -Path $recent) })).Count 0
    }

    It 'discovers only known browser cache roots and not profile data' {
        $localAppData = Join-Path $TestDrive 'browser-local-app-data'
        $chromeProfile = Join-Path $localAppData 'Google\Chrome\User Data\Default'
        $chromeSecondProfile = Join-Path $localAppData 'Google\Chrome\User Data\Profile 1'
        $chromeSystemProfile = Join-Path $localAppData 'Google\Chrome\User Data\System Profile'
        $edgeProfile = Join-Path $localAppData 'Microsoft\Edge\User Data\Default'
        $firefoxProfile = Join-Path $localAppData 'Mozilla\Firefox\Profiles\abc.default-release'

        $fixturePaths = @(
            (Join-Path $chromeProfile 'Cache\Cache_Data'),
            (Join-Path $chromeSecondProfile 'Cache\Cache_Data'),
            (Join-Path $chromeSystemProfile 'Cache\Cache_Data'),
            (Join-Path $edgeProfile 'Cache\Cache_Data'),
            (Join-Path $firefoxProfile 'cache2\entries'),
            (Join-Path $chromeProfile 'Network'),
            (Join-Path $chromeProfile 'Service Worker\CacheStorage'),
            (Join-Path $firefoxProfile 'storage\default')
        )
        foreach ($path in $fixturePaths) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }

        Set-Content -LiteralPath (Join-Path $chromeProfile 'Cookies') -Value 'profile-data'
        Set-Content -LiteralPath (Join-Path $firefoxProfile 'logins.json') -Value 'profile-data'

        $roots = @(Get-MoleBrowserCacheRoots -LocalAppData $localAppData)

        Assert-MoleEqual $roots.Count 4
        Assert-MoleEqual (@($roots | Where-Object { $_.BrowserId -eq 'chrome' })).Count 2
        Assert-MoleEqual (@($roots | Where-Object { $_.BrowserId -eq 'edge' })).Count 1
        Assert-MoleEqual (@($roots | Where-Object { $_.BrowserId -eq 'firefox' })).Count 1
        Assert-MoleEqual (@($roots | Where-Object { (Split-Path -Leaf $_.Root) -notin @('Cache', 'cache2') })).Count 0
        Assert-MoleEqual (@($roots | Where-Object { $_.Root -match 'Cookies|logins\.json|Network|storage' })).Count 0
    }

    It 'plans stale browser cache files only and annotates the responsible browser' {
        $localAppData = Join-Path $TestDrive 'browser-plan-local-app-data'
        $chromeCache = Join-Path $localAppData 'Google\Chrome\User Data\Default\Cache\Cache_Data'
        $chromeProfile = Split-Path -Parent (Split-Path -Parent $chromeCache)
        New-Item -ItemType Directory -Path $chromeCache -Force | Out-Null

        $staleCacheFile = Join-Path $chromeCache 'entry-001'
        Set-Content -LiteralPath $staleCacheFile -Value 'cache'
        (Get-Item -LiteralPath $staleCacheFile).LastWriteTime = (Get-Date).AddDays(-30)
        Set-Content -LiteralPath (Join-Path $chromeProfile 'Cookies') -Value 'private-data'

        $plan = @(New-MoleProviderPlan `
                -Provider 'browser-cache' `
                -LocalAppData $localAppData `
                -RunningBrowserNames @() `
                -ProtectedRoots @())

        Assert-MoleEqual $plan.Count 1
        Assert-MoleEqual $plan[0].Path (Get-MoleCanonicalPath -Path $staleCacheFile)
        Assert-MoleEqual $plan[0].ProviderId 'browser-cache'
        Assert-MoleEqual $plan[0].BrowserId 'chrome'
        Assert-MoleEqual $plan[0].SizeBytes (Get-Item -LiteralPath $staleCacheFile).Length
    }

    It 'refuses to plan a browser cache while that browser is running' {
        $localAppData = Join-Path $TestDrive 'active-browser-local-app-data'
        $chromeCache = Join-Path $localAppData 'Google\Chrome\User Data\Default\Cache'
        New-Item -ItemType Directory -Path $chromeCache -Force | Out-Null

        Assert-MoleThrows {
            New-MoleProviderPlan `
                -Provider 'browser-cache' `
                -LocalAppData $localAppData `
                -RunningBrowserNames @('chrome') `
                -ProtectedRoots @()
        }
    }

    It 'writes dry-run and execution events to the requested audit log' {
        $candidate = Join-Path $allowed 'candidate.tmp'
        $auditPath = Join-Path $TestDrive 'audit\operations.jsonl'
        $backupRoot = Join-Path $TestDrive 'audit-backups'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $allowed -ProtectedRoots $protected

        $preview = Invoke-MoleCleanupWithBackup `
            -Plan $plan `
            -BackupRoot $backupRoot `
            -AllowedRoots $allowed `
            -ProtectedRoots $protected `
            -AuditPath $auditPath

        Assert-MoleFalse $preview.Executed
        Assert-MoleTrue (Test-Path -LiteralPath $candidate)
        Assert-MoleTrue (Test-Path -LiteralPath $auditPath)
        $previewEvents = @(Get-Content -LiteralPath $auditPath | ForEach-Object { ConvertFrom-Json $_ })
        Assert-MoleEqual $previewEvents[0].Event 'plan-created'
        Assert-MoleEqual $previewEvents[0].EstimatedBytes (Get-Item -LiteralPath $candidate).Length

        $result = Invoke-MoleCleanupWithBackup `
            -Plan $plan `
            -BackupRoot (Join-Path $TestDrive 'audit-execution-backups') `
            -AllowedRoots $allowed `
            -ProtectedRoots $protected `
            -AuditPath $auditPath `
            -Execute `
            -Confirm:$false

        $events = @(Get-Content -LiteralPath $auditPath | ForEach-Object { ConvertFrom-Json $_ })
        Assert-MoleEqual (@($events | Where-Object { $_.Event -eq 'execution-started' })).Count 1
        Assert-MoleEqual (@($events | Where-Object { $_.Event -eq 'target-deleted' })).Count 1
        Assert-MoleEqual (@($events | Where-Object { $_.Event -eq 'execution-completed' })).Count 1
        Assert-MoleEqual (@($events | Where-Object { $_.ManifestPath -eq $result.ManifestPath })).Count 3
    }

    It 'rejects an audit log path inside a cleanup target' {
        $candidate = Join-Path $allowed 'candidate.tmp'
        $plan = New-MoleCleanupPlan -CandidatePaths $candidate -AllowedRoots $allowed -ProtectedRoots $protected
        $auditPath = Join-Path $candidate 'operations.jsonl'

        Assert-MoleThrows {
            Invoke-MoleCleanupWithBackup `
                -Plan $plan `
                -BackupRoot (Join-Path $TestDrive 'overlap-backups') `
                -AllowedRoots $allowed `
                -ProtectedRoots $protected `
                -AuditPath $auditPath
        }

        Assert-MoleTrue (Test-Path -LiteralPath $candidate)
    }

    It 'summarizes eligible and skipped targets with total estimated bytes' {
        $plan = @(
            [pscustomobject]@{ Path = 'C:\fixture\a.tmp'; Action = 'Delete'; SizeBytes = 1024; ProviderId = 'user-temp' },
            [pscustomobject]@{ Path = 'C:\fixture\b.tmp'; Action = 'Delete'; SizeBytes = 2048; ProviderId = 'dev-cache' },
            [pscustomobject]@{ Path = 'C:\fixture\important.txt'; Action = 'Skip'; SizeBytes = 4096; ProviderId = 'user-temp' }
        )

        $summary = Get-MoleCleanupSummary -Plan $plan

        Assert-MoleEqual $summary.TargetCount 2
        Assert-MoleEqual $summary.SkippedCount 1
        Assert-MoleEqual $summary.EstimatedBytes 3072
        Assert-MoleEqual $summary.EstimatedMegabytes ([math]::Round(3072 / 1MB, 2))
    }

    It 'analyze prints a summary and audits a dry-run without changing targets' {
        $candidate = Join-Path $allowed 'candidate.tmp'
        $auditPath = Join-Path $TestDrive 'analysis-audit\operations.jsonl'
        $scriptPath = Join-Path $PSScriptRoot '..\scripts\mole.ps1'

        $output = @(& (Resolve-Path $scriptPath).Path analyze -Path $candidate -AllowedRoot $allowed -AuditPath $auditPath)
        $summaryLine = $output | Where-Object { $_ -is [string] -and $_ -like 'Analysis:*' } | Select-Object -First 1
        $expectedBytes = (Get-Item -LiteralPath $candidate).Length

        Assert-MoleEqual $summaryLine ("Analysis: 1 eligible, 0 skipped; estimated reclaimable space 0 MB ({0} bytes)." -f $expectedBytes)
        Assert-MoleTrue (Test-Path -LiteralPath $candidate)
        Assert-MoleTrue (Test-Path -LiteralPath $auditPath)
        $events = @(Get-Content -LiteralPath $auditPath | ForEach-Object { ConvertFrom-Json $_ })
        Assert-MoleEqual $events[0].Event 'plan-created'
    }
}
