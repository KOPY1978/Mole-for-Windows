function Get-MoleProviderCatalog {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{
            Id                  = 'user-temp'
            Title               = 'User temporary files'
            Risk                = 'low'
            RequiresElevation   = $false
            DefaultMinimumAgeDays = 3
            Scope               = 'Current user TEMP directory; files only'
        },
        [pscustomobject]@{
            Id                  = 'dev-cache'
            Title               = 'Developer tool caches'
            Risk                = 'medium'
            RequiresElevation   = $false
            DefaultMinimumAgeDays = 14
            Scope               = 'Known per-user package/build caches; lock files excluded'
        },
        [pscustomobject]@{
            Id                  = 'browser-cache'
            Title               = 'Browser disk caches'
            Risk                = 'medium'
            RequiresElevation   = $false
            DefaultMinimumAgeDays = 14
            Scope               = 'Default Chrome, Edge and Firefox disk-cache folders only; browser must be closed'
        }
    )
}

function Get-MoleTempRoots {
    [CmdletBinding()]
    param()

    $roots = @($env:TEMP, $env:TMP) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Get-MoleCanonicalPath -Path $_ }

    return @($roots | Select-Object -Unique)
}

function Get-MoleTempCandidates {
    [CmdletBinding()]
    param(
        [ValidateRange(0, 3650)]
        [int] $MinimumAgeDays = 3
    )

    $cutoff = (Get-Date).AddDays(-1 * $MinimumAgeDays)
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($root in Get-MoleTempRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -File -ErrorAction SilentlyContinue)) {
            if ($item.LastWriteTime -ge $cutoff) {
                continue
            }

            $results.Add([pscustomobject]@{
                    ProviderId = 'user-temp'
                    AllowedRoot = $root
                    Path        = $item.FullName
                    LastWriteTime = $item.LastWriteTime
                    Length      = $item.Length
                })
        }
    }

    return @($results.ToArray())
}

function Get-MoleDeveloperCacheRoots {
    [CmdletBinding()]
    param()

    $roots = New-Object System.Collections.Generic.List[object]

    function Add-CacheRoot {
        param(
            [string] $Id,
            [string] $Title,
            [string] $Path
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return
        }

        $roots.Add([pscustomobject]@{
                Id    = $Id
                Title = $Title
                Root  = $Path
            })
    }

    $localAppData = $env:LOCALAPPDATA
    $userProfile = $env:USERPROFILE

    if ($localAppData) {
        Add-CacheRoot -Id 'npm' -Title 'npm cache' -Path (Join-Path $localAppData 'npm-cache')
        Add-CacheRoot -Id 'yarn' -Title 'Yarn cache' -Path (Join-Path $localAppData 'Yarn\Cache')
        Add-CacheRoot -Id 'pnpm' -Title 'pnpm store' -Path (Join-Path $localAppData 'pnpm\store')
        Add-CacheRoot -Id 'pip' -Title 'pip cache' -Path (Join-Path $localAppData 'pip\Cache')
        Add-CacheRoot -Id 'nuget' -Title 'NuGet HTTP cache' -Path (Join-Path $localAppData 'NuGet\v3-cache')
        Add-CacheRoot -Id 'go-build' -Title 'Go build cache' -Path (Join-Path $localAppData 'go-build')
    }

    if ($userProfile) {
        Add-CacheRoot -Id 'cargo' -Title 'Cargo registry artifact cache' -Path (Join-Path $userProfile '.cargo\registry\cache')
    }

    return @($roots.ToArray() | Sort-Object -Property Root -Unique)
}

function Test-MoleCacheFileSkippable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File
    )

    $name = $File.Name.ToLowerInvariant()
    $extension = $File.Extension.ToLowerInvariant()

    if ($extension -in @('.lock', '.lck', '.pid', '.tmp.lock')) {
        return $true
    }

    if ($name -match '(^|[._-])(lock|active|inuse)([._-]|$)') {
        return $true
    }

    return $false
}

function Get-MoleCacheCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Roots,

        [ValidateRange(0, 3650)]
        [int] $MinimumAgeDays = 14
    )

    $cutoff = (Get-Date).AddDays(-1 * $MinimumAgeDays)
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($rootInfo in @($Roots)) {
        $root = Get-MoleCanonicalPath -Path ([string] $rootInfo.Root)
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($item.LastWriteTime -ge $cutoff) {
                continue
            }

            if (Test-MoleCacheFileSkippable -File $item) {
                continue
            }

            if (Test-MolePathProtected -Path $item.FullName) {
                continue
            }

            $cacheId = $null
            $cacheTitle = $null
            $browserId = $null
            if ($rootInfo.PSObject.Properties['Id']) {
                $cacheId = $rootInfo.Id
            }
            if ($rootInfo.PSObject.Properties['Title']) {
                $cacheTitle = $rootInfo.Title
            }
            if ($rootInfo.PSObject.Properties['BrowserId']) {
                $browserId = $rootInfo.BrowserId
                $cacheId = $browserId
            }
            if ($rootInfo.PSObject.Properties['BrowserTitle']) {
                $cacheTitle = $rootInfo.BrowserTitle
            }

            $results.Add([pscustomobject]@{
                    ProviderId    = if ($browserId) { 'browser-cache' } else { 'dev-cache' }
                    CacheId       = $cacheId
                    CacheTitle    = $cacheTitle
                    BrowserId     = $browserId
                    AllowedRoot  = $root
                    Path          = $item.FullName
                    LastWriteTime = $item.LastWriteTime
                    Length        = $item.Length
                })
        }
    }

    return @($results.ToArray())
}

function Get-MoleBrowserCacheRoots {
    [CmdletBinding()]
    param(
        [string] $LocalAppData = $env:LOCALAPPDATA
    )

    if ([string]::IsNullOrWhiteSpace($LocalAppData) -or -not (Test-Path -LiteralPath $LocalAppData)) {
        return @()
    }

    $localRoot = Get-MoleCanonicalPath -Path $LocalAppData
    $userDataRoots = @(
        [pscustomobject]@{
            BrowserId    = 'chrome'
            BrowserTitle = 'Google Chrome'
            UserDataRoot = Join-Path $localRoot 'Google\Chrome\User Data'
        },
        [pscustomobject]@{
            BrowserId    = 'edge'
            BrowserTitle = 'Microsoft Edge'
            UserDataRoot = Join-Path $localRoot 'Microsoft\Edge\User Data'
        }
    )

    $roots = New-Object System.Collections.Generic.List[object]
    $profilePattern = '^(Default|Profile\s+\d+|Guest Profile)$'

    foreach ($browser in $userDataRoots) {
        if (-not (Test-Path -LiteralPath $browser.UserDataRoot)) {
            continue
        }

        foreach ($profile in @(Get-ChildItem -LiteralPath $browser.UserDataRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($profile.Name -notmatch $profilePattern) {
                continue
            }

            $cacheRoot = Join-Path $profile.FullName 'Cache'
            if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
                continue
            }

            $canonicalCache = Get-MoleCanonicalPath -Path $cacheRoot
            if (Test-MolePathProtected -Path $canonicalCache) {
                continue
            }

            $roots.Add([pscustomobject]@{
                    BrowserId    = $browser.BrowserId
                    BrowserTitle = $browser.BrowserTitle
                    ProfileName  = $profile.Name
                    Root         = $canonicalCache
                })
        }
    }

    $firefoxProfiles = Join-Path $localRoot 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $firefoxProfiles -PathType Container) {
        foreach ($profile in @(Get-ChildItem -LiteralPath $firefoxProfiles -Directory -Force -ErrorAction SilentlyContinue)) {
            $cacheRoot = Join-Path $profile.FullName 'cache2'
            if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
                continue
            }

            $canonicalCache = Get-MoleCanonicalPath -Path $cacheRoot
            if (Test-MolePathProtected -Path $canonicalCache) {
                continue
            }

            $roots.Add([pscustomobject]@{
                    BrowserId    = 'firefox'
                    BrowserTitle = 'Mozilla Firefox'
                    ProfileName  = $profile.Name
                    Root         = $canonicalCache
                })
        }
    }

    return @($roots.ToArray() | Sort-Object -Property Root -Unique)
}

function Get-MoleRunningBrowserNames {
    [CmdletBinding()]
    param()

    $browserNames = @('chrome', 'msedge', 'firefox')
    $processes = @(Get-Process -Name $browserNames -ErrorAction SilentlyContinue)
    return @($processes | Select-Object -ExpandProperty ProcessName -Unique)
}

function Get-MoleBrowserProcessName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('chrome', 'edge', 'firefox')]
        [string] $BrowserId
    )

    switch ($BrowserId) {
        'chrome' { return 'chrome' }
        'edge' { return 'msedge' }
        'firefox' { return 'firefox' }
    }
}

function Add-MoleProviderPlanMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Plan,

        [Parameter(Mandatory = $true)]
        [object[]] $Candidates,

        [Parameter(Mandatory = $true)]
        [string] $ProviderId
    )

    foreach ($entry in $Plan) {
        $entryPath = ConvertTo-MoleComparablePath -Path $entry.Path
        $candidate = $Candidates |
            Where-Object { (ConvertTo-MoleComparablePath -Path $_.Path) -eq $entryPath } |
            Select-Object -First 1

        Add-Member -InputObject $entry -NotePropertyName ProviderId -NotePropertyValue $ProviderId -Force
        if ($candidate) {
            Add-Member -InputObject $entry -NotePropertyName SizeBytes -NotePropertyValue ([long] $candidate.Length) -Force
            if ($candidate.BrowserId) {
                Add-Member -InputObject $entry -NotePropertyName BrowserId -NotePropertyValue $candidate.BrowserId -Force
            }
        }
    }

    return @($Plan)
}

function New-MoleProviderPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('user-temp', 'dev-cache', 'browser-cache')]
        [string] $Provider,

        [ValidateRange(-1, 3650)]
        [int] $MinimumAgeDays = -1,

        [string[]] $ProtectedRoots = (Get-MoleDefaultProtectedRoots),

        [string] $LocalAppData,

        [string[]] $RunningBrowserNames
    )

    switch ($Provider) {
        'user-temp' {
            if ($MinimumAgeDays -lt 0) {
                $MinimumAgeDays = 3
            }

            $candidates = @(Get-MoleTempCandidates -MinimumAgeDays $MinimumAgeDays)
            if ($candidates.Count -eq 0) {
                return @()
            }

            $allowed = @($candidates.AllowedRoot | Select-Object -Unique)
            $plan = @(New-MoleCleanupPlan -CandidatePaths $candidates.Path -AllowedRoots $allowed -ProtectedRoots $ProtectedRoots)
            return Add-MoleProviderPlanMetadata -Plan $plan -Candidates $candidates -ProviderId 'user-temp'
        }

        'dev-cache' {
            if ($MinimumAgeDays -lt 0) {
                $MinimumAgeDays = 14
            }

            $roots = @(Get-MoleDeveloperCacheRoots)
            $candidates = @(Get-MoleCacheCandidates -Roots $roots -MinimumAgeDays $MinimumAgeDays)
            if ($candidates.Count -eq 0) {
                return @()
            }

            $allowed = @($candidates.AllowedRoot | Select-Object -Unique)
            $plan = @(New-MoleCleanupPlan -CandidatePaths $candidates.Path -AllowedRoots $allowed -ProtectedRoots $ProtectedRoots)
            return Add-MoleProviderPlanMetadata -Plan $plan -Candidates $candidates -ProviderId 'dev-cache'
        }

        'browser-cache' {
            if ($MinimumAgeDays -lt 0) {
                $MinimumAgeDays = 14
            }

            if (-not $PSBoundParameters.ContainsKey('RunningBrowserNames')) {
                $RunningBrowserNames = @(Get-MoleRunningBrowserNames)
            }

            $roots = if ($LocalAppData) {
                @(Get-MoleBrowserCacheRoots -LocalAppData $LocalAppData)
            }
            else {
                @(Get-MoleBrowserCacheRoots)
            }

            $activeBrowsers = @(
                $roots |
                    Where-Object {
                        $requiredProcess = Get-MoleBrowserProcessName -BrowserId $_.BrowserId
                        $RunningBrowserNames -contains $requiredProcess
                    } |
                    Select-Object -ExpandProperty BrowserTitle -Unique
            )
            if ($activeBrowsers.Count -gt 0) {
                throw ('Close these browsers before planning cache cleanup: {0}' -f ($activeBrowsers -join ', '))
            }

            $candidates = @(Get-MoleCacheCandidates -Roots $roots -MinimumAgeDays $MinimumAgeDays)
            if ($candidates.Count -eq 0) {
                return @()
            }

            $allowed = @($candidates.AllowedRoot | Select-Object -Unique)
            $plan = @(New-MoleCleanupPlan -CandidatePaths $candidates.Path -AllowedRoots $allowed -ProtectedRoots $ProtectedRoots)
            return Add-MoleProviderPlanMetadata -Plan $plan -Candidates $candidates -ProviderId 'browser-cache'
        }
    }
}
