Set-StrictMode -Version Latest

$privateFiles = @(
    (Join-Path $PSScriptRoot 'Mole.Backup.ps1'),
    (Join-Path $PSScriptRoot 'Mole.Providers.ps1')
)

foreach ($privateFile in $privateFiles) {
    . $privateFile
}

function ConvertTo-MoleComparablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) {
        $full = $full.TrimEnd([char[]]@('\', '/'))
    }

    if ($full.Length -gt 3) {
        $full = $full.TrimEnd([char]0x5c, [char]0x2f)
    }

    return $full.ToLowerInvariant()
}

function Get-MoleCanonicalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Path must not be empty.'
    }

    try {
        if (Test-Path -LiteralPath $Path) {
            $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
            return $resolved.ProviderPath
        }

        return [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        throw "Unable to canonicalize path '$Path': $($_.Exception.Message)"
    }
}

function Test-MolePathWithin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    $pathValue = ConvertTo-MoleComparablePath -Path $Path
    $rootValue = ConvertTo-MoleComparablePath -Path $Root

    if ($pathValue.Equals($rootValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if ($rootValue.EndsWith('\', [System.StringComparison]::Ordinal)) {
        return $pathValue.StartsWith($rootValue, [System.StringComparison]::OrdinalIgnoreCase)
    }

    return $pathValue.StartsWith($rootValue + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-MoleDefaultProtectedRoots {
    [CmdletBinding()]
    param()

    $roots = @(
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Pictures'),
        (Join-Path $env:USERPROFILE 'Videos'),
        (Join-Path $env:USERPROFILE 'Music'),
        (Join-Path $env:USERPROFILE '.ssh'),
        (Join-Path $env:USERPROFILE '.gnupg')
    )

    return @($roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-MolePathProtected {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [string[]] $ProtectedRoots = (Get-MoleDefaultProtectedRoots)
    )

    $canonical = Get-MoleCanonicalPath -Path $Path
    $driveRoot = [System.IO.Path]::GetPathRoot($canonical)

    if ($canonical.Equals($driveRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    foreach ($root in @($ProtectedRoots)) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        if (Test-MolePathWithin -Path $canonical -Root $root) {
            return $true
        }
    }

    $probePath = $canonical
    $cursor = $null
    while (-not $cursor -and $probePath) {
        $cursor = Get-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        if ($cursor) {
            break
        }

        $parent = Split-Path -Parent $probePath
        if (-not $parent -or $parent -eq $probePath) {
            break
        }
        $probePath = $parent
    }

    while ($null -ne $cursor) {
        if ($cursor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            return $true
        }

        $nextPath = Split-Path -Parent $cursor.FullName
        if (-not $nextPath -or $nextPath -eq $cursor.FullName) {
            break
        }
        $cursor = Get-Item -LiteralPath $nextPath -Force -ErrorAction SilentlyContinue
    }

    return $false
}

function New-MoleCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $CandidatePaths,

        [Parameter(Mandatory = $true)]
        [string[]] $AllowedRoots,

        [string[]] $ProtectedRoots = (Get-MoleDefaultProtectedRoots)
    )

    if ($AllowedRoots.Count -eq 0) {
        throw 'At least one allowlisted root is required.'
    }

    foreach ($candidate in $CandidatePaths) {
        $canonical = Get-MoleCanonicalPath -Path $candidate
        $exists = Test-Path -LiteralPath $canonical
        $reason = $null
        $action = 'Delete'
        $inAllowList = $false

        foreach ($allowedRoot in $AllowedRoots) {
            if (Test-MolePathWithin -Path $canonical -Root $allowedRoot) {
                $inAllowList = $true
                break
            }
        }

        if (-not $inAllowList) {
            $action = 'Skip'
            $reason = 'OutsideAllowList'
        }
        elseif (@($AllowedRoots | Where-Object {
                    (ConvertTo-MoleComparablePath -Path $_) -eq (ConvertTo-MoleComparablePath -Path $canonical)
                }).Count -gt 0) {
            $action = 'Skip'
            $reason = 'AllowRoot'
        }
        elseif (Test-MolePathProtected -Path $canonical -ProtectedRoots $ProtectedRoots) {
            $action = 'Skip'
            $reason = 'ProtectedPath'
        }
        elseif (-not $exists) {
            $action = 'Skip'
            $reason = 'Missing'
        }

        [pscustomobject]@{
            Path   = $canonical
            Exists = $exists
            Action = $action
            Reason = $reason
        }
    }
}

function Invoke-MoleCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Plan,

        [switch] $Execute
    )

    if (-not $Execute) {
        return @($Plan)
    }

    if (-not $Plan) {
        return @()
    }

    throw 'Destructive execution is intentionally disabled until a caller supplies an explicit backup manifest and audited execution path.'
}

function Assert-MoleProviderInactive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Entries
    )

    $browserEntries = @(
        $Entries |
            Where-Object {
                $_.PSObject.Properties['ProviderId'] -and
                $_.PSObject.Properties['BrowserId'] -and
                $_.PSObject.Properties['ProviderId'].Value -eq 'browser-cache' -and
                $_.PSObject.Properties['BrowserId'].Value
            }
    )
    if ($browserEntries.Count -eq 0) {
        return
    }

    $runningNames = @(Get-MoleRunningBrowserNames)
    foreach ($entry in $browserEntries) {
        $requiredProcess = Get-MoleBrowserProcessName -BrowserId $entry.BrowserId
        if ($runningNames -contains $requiredProcess) {
            $browserTitle = switch ($entry.BrowserId) {
                'chrome' { 'Google Chrome' }
                'edge' { 'Microsoft Edge' }
                'firefox' { 'Mozilla Firefox' }
            }
            throw "$browserTitle is running. Close it before cleaning its cache."
        }
    }
}

function Get-MolePlanEstimatedBytes {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)]
        [object[]] $Entries
    )

    [long] $total = 0
    foreach ($entry in $Entries) {
        $sizeProperty = $entry.PSObject.Properties['SizeBytes']
        if ($sizeProperty -and $null -ne $sizeProperty.Value) {
            $total += [long] $sizeProperty.Value
            continue
        }

        $item = Get-Item -LiteralPath $entry.Path -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            continue
        }

        if ($item.PSIsContainer) {
            foreach ($file in @(Get-ChildItem -LiteralPath $item.FullName -File -Force -Recurse -ErrorAction SilentlyContinue)) {
                if (-not (Test-MolePathProtected -Path $file.FullName)) {
                    $total += [long] $file.Length
                }
            }
        }
        else {
            $total += [long] $item.Length
        }
    }

    return $total
}

function Get-MoleCleanupSummary {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]] $Plan = @()
    )

    $entries = @($Plan)
    $targets = @($entries | Where-Object { $_.Action -eq 'Delete' })
    $skipped = @($entries | Where-Object { $_.Action -eq 'Skip' })
    $estimatedBytes = [long] (Get-MolePlanEstimatedBytes -Entries $targets)
    $providerIds = @(
        $entries |
            Where-Object { $_.PSObject.Properties['ProviderId'] } |
            ForEach-Object { $_.ProviderId } |
            Select-Object -Unique
    )

    return [pscustomobject]@{
        TargetCount       = $targets.Count
        SkippedCount      = $skipped.Count
        EstimatedBytes    = $estimatedBytes
        EstimatedMegabytes = [math]::Round(($estimatedBytes / 1MB), 2)
        ProviderIds       = $providerIds
        Plan              = $entries
    }
}

function Test-MoleAuditPathSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $AuditPath,

        [Parameter(Mandatory = $true)]
        [object[]] $Entries
    )

    $canonicalAuditPath = Get-MoleCanonicalPath -Path $AuditPath
    if (Test-MolePathProtected -Path $canonicalAuditPath) {
        throw "Audit path is protected: $canonicalAuditPath"
    }

    foreach ($entry in $Entries) {
        $target = Get-MoleCanonicalPath -Path $entry.Path
        if ((Test-MolePathWithin -Path $canonicalAuditPath -Root $target) -or
            (Test-MolePathWithin -Path $target -Root $canonicalAuditPath)) {
            throw "Audit path overlaps a cleanup target: $canonicalAuditPath"
        }
    }

    return $canonicalAuditPath
}

function Write-MoleAuditEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $AuditPath,

        [Parameter(Mandatory = $true)]
        [string] $Event,

        [Parameter(Mandatory = $true)]
        [object[]] $Entries,

        [long] $EstimatedBytes = 0,

        [string] $ManifestPath,

        [string] $TargetPath,

        [string] $Message
    )

    $parent = Split-Path -Parent $AuditPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }

    $providerIds = @(
        $Entries |
            Where-Object { $_.PSObject.Properties['ProviderId'] } |
            ForEach-Object { $_.ProviderId } |
            Select-Object -Unique
    )
    $browserIds = @(
        $Entries |
            Where-Object { $_.PSObject.Properties['BrowserId'] } |
            ForEach-Object { $_.BrowserId } |
            Select-Object -Unique
    )

    $record = [pscustomobject]@{
        TimestampUtc   = (Get-Date).ToUniversalTime().ToString('o')
        Event          = $Event
        User           = $env:USERNAME
        Computer       = $env:COMPUTERNAME
        ProviderIds    = $providerIds
        BrowserIds     = $browserIds
        TargetCount    = $Entries.Count
        EstimatedBytes = $EstimatedBytes
        ManifestPath   = $ManifestPath
        TargetPath     = $TargetPath
        Message        = $Message
    }

    $json = $record | ConvertTo-Json -Depth 6 -Compress
    Add-Content -LiteralPath $AuditPath -Value $json -Encoding UTF8 -ErrorAction Stop
}

function Invoke-MoleCleanupWithBackup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Plan,

        [Parameter(Mandatory = $true)]
        [string] $BackupRoot,

        [Parameter(Mandatory = $true)]
        [string[]] $AllowedRoots,

        [string[]] $ProtectedRoots = (Get-MoleDefaultProtectedRoots),

        [string] $AuditPath,

        [switch] $Execute
    )

    $deleteEntries = @($Plan | Where-Object { $_.Action -eq 'Delete' })
    if ($deleteEntries.Count -eq 0) {
        return [pscustomobject]@{
            Executed     = $false
            ItemCount    = 0
            ManifestPath = $null
            Results      = @()
        }
    }

    # Re-validate every target immediately before creating a backup or deleting anything.
    $validatedPlan = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $deleteEntries) {
        $canonical = Get-MoleCanonicalPath -Path $entry.Path
        $insideAllowList = $false
        foreach ($root in $AllowedRoots) {
            if (Test-MolePathWithin -Path $canonical -Root $root) {
                $insideAllowList = $true
                break
            }
        }

        if (-not $insideAllowList) {
            throw "Cleanup target is outside the allowlist: $canonical"
        }
        foreach ($root in $AllowedRoots) {
            if ((ConvertTo-MoleComparablePath -Path $canonical) -eq (ConvertTo-MoleComparablePath -Path $root)) {
                throw "Cleanup target is an allowlisted root: $canonical"
            }
        }
        if (Test-MolePathProtected -Path $canonical -ProtectedRoots $ProtectedRoots) {
            throw "Cleanup target is protected: $canonical"
        }
        if (-not (Test-Path -LiteralPath $canonical)) {
            continue
        }

        $validatedEntry = [pscustomobject]@{
                Path   = $canonical
                Exists = $true
                Action = 'Delete'
                Reason = $null
            }
        foreach ($metadataName in @('ProviderId', 'BrowserId', 'SizeBytes')) {
            $metadata = $entry.PSObject.Properties[$metadataName]
            if ($metadata) {
                Add-Member -InputObject $validatedEntry -NotePropertyName $metadataName -NotePropertyValue $metadata.Value -Force
            }
        }
        $validatedPlan.Add($validatedEntry)
    }

    if ($validatedPlan.Count -eq 0) {
        return [pscustomobject]@{
            Executed     = $false
            ItemCount    = 0
            ManifestPath = $null
            Results      = @()
        }
    }

    $validatedArray = $validatedPlan.ToArray()
    $estimatedBytes = Get-MolePlanEstimatedBytes -Entries $validatedArray
    if ($AuditPath) {
        $AuditPath = Test-MoleAuditPathSafe -AuditPath $AuditPath -Entries $validatedArray
    }

    if (-not $Execute) {
        if ($AuditPath) {
            Write-MoleAuditEvent -AuditPath $AuditPath -Event 'plan-created' -Entries $validatedArray -EstimatedBytes $estimatedBytes
        }

        return [pscustomobject]@{
            Executed     = $false
            ItemCount    = $validatedPlan.Count
            EstimatedBytes = $estimatedBytes
            ManifestPath = $null
            Results      = @($validatedArray)
        }
    }

    Assert-MoleProviderInactive -Entries $validatedArray
    if (-not $PSCmdlet.ShouldProcess("$($validatedArray.Count) cleanup target(s)", 'Back up and delete')) {
        if ($AuditPath) {
            Write-MoleAuditEvent -AuditPath $AuditPath -Event 'whatif-preview' -Entries $validatedArray -EstimatedBytes $estimatedBytes
        }

        return [pscustomobject]@{
            Executed       = $false
            ItemCount      = $validatedArray.Count
            EstimatedBytes = $estimatedBytes
            ManifestPath   = $null
            Results        = @($validatedArray)
        }
    }

    if ($AuditPath) {
        Write-MoleAuditEvent -AuditPath $AuditPath -Event 'execution-started' -Entries $validatedArray -EstimatedBytes $estimatedBytes
    }

    try {
        $backup = Invoke-MoleBackup -Plan $validatedArray -BackupRoot $BackupRoot
    }
    catch {
        if ($AuditPath) {
            Write-MoleAuditEvent -AuditPath $AuditPath -Event 'backup-failed' -Entries $validatedArray -EstimatedBytes $estimatedBytes -Message $_.Exception.Message
        }
        throw
    }

    if ($AuditPath) {
        Write-MoleAuditEvent -AuditPath $AuditPath -Event 'backup-created' -Entries $validatedArray -EstimatedBytes $estimatedBytes -ManifestPath $backup.ManifestPath
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $validatedArray) {
        try {
            Assert-MoleProviderInactive -Entries @($entry)
        }
        catch {
            $message = '{0} Backup manifest: {1}. Restore any entries already removed from this run.' -f $_.Exception.Message, $backup.ManifestPath
            if ($AuditPath) {
                Write-MoleAuditEvent -AuditPath $AuditPath -Event 'execution-interrupted' -Entries $validatedArray -EstimatedBytes $estimatedBytes -ManifestPath $backup.ManifestPath -Message $message
            }
            throw $message
        }

        try {
            Remove-Item -LiteralPath $entry.Path -Force -ErrorAction Stop
            $results.Add([pscustomobject]@{
                    Path   = $entry.Path
                    Action = 'Deleted'
            })

            if ($AuditPath) {
                $targetEstimatedBytes = Get-MolePlanEstimatedBytes -Entries @($entry)
                Write-MoleAuditEvent -AuditPath $AuditPath -Event 'target-deleted' -Entries @($entry) -EstimatedBytes $targetEstimatedBytes -ManifestPath $backup.ManifestPath -TargetPath $entry.Path
            }
        }
        catch {
            $message = '{0} Backup manifest: {1}.' -f $_.Exception.Message, $backup.ManifestPath
            if ($AuditPath) {
                Write-MoleAuditEvent -AuditPath $AuditPath -Event 'execution-failed' -Entries $validatedArray -EstimatedBytes $estimatedBytes -ManifestPath $backup.ManifestPath -TargetPath $entry.Path -Message $message
            }
            throw $message
        }
    }

    if ($AuditPath) {
        Write-MoleAuditEvent -AuditPath $AuditPath -Event 'execution-completed' -Entries $validatedArray -EstimatedBytes $estimatedBytes -ManifestPath $backup.ManifestPath
    }

    return [pscustomobject]@{
        Executed     = $true
        ItemCount    = $results.Count
        EstimatedBytes = $estimatedBytes
        ManifestPath = $backup.ManifestPath
        Results      = @($results.ToArray())
    }
}

Export-ModuleMember -Function @(
    'Get-MoleCanonicalPath',
    'Test-MolePathWithin',
    'Get-MoleDefaultProtectedRoots',
    'Test-MolePathProtected',
    'New-MoleCleanupPlan',
    'Invoke-MoleCleanupPlan',
    'Invoke-MoleCleanupWithBackup',
    'Get-MoleCleanupSummary',
    'Get-MoleBackupRoot',
    'Test-MoleBackupRootSafe',
    'Invoke-MoleBackup',
    'Restore-MoleBackup',
    'Get-MoleProviderCatalog',
    'Get-MoleTempCandidates',
    'Get-MoleDeveloperCacheRoots',
    'Get-MoleCacheCandidates',
    'Get-MoleBrowserCacheRoots',
    'Get-MoleRunningBrowserNames',
    'New-MoleProviderPlan'
)
