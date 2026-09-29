function Get-MoleBackupRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $BackupRoot
    )

    $resolved = Get-MoleCanonicalPath -Path $BackupRoot
    if (Test-MolePathProtected -Path $resolved) {
        throw "Backup root is protected: $resolved"
    }

    if (-not (Test-Path -LiteralPath $resolved)) {
        New-Item -ItemType Directory -Path $resolved -Force -ErrorAction Stop | Out-Null
    }

    $item = Get-Item -LiteralPath $resolved -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) {
        throw "Backup root is not a directory: $resolved"
    }

    return $resolved
}

function Test-MoleBackupRootSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $BackupRoot,

        [Parameter(Mandatory = $true)]
        [object[]] $Plan
    )

    $backup = ConvertTo-MoleComparablePath -Path (Get-MoleCanonicalPath -Path $BackupRoot)

    foreach ($entry in @($Plan | Where-Object { $_.Action -eq 'Delete' })) {
        $target = ConvertTo-MoleComparablePath -Path $entry.Path
        $backupContainsTarget = Test-MolePathWithin -Path $backup -Root $target
        $targetContainsBackup = Test-MolePathWithin -Path $target -Root $backup

        if ($backupContainsTarget -or $targetContainsBackup) {
            return $false
        }
    }

    return $true
}

function Get-MoleFileHashSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    }
    catch {
        return $null
    }
}

function Invoke-MoleBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Plan,

        [Parameter(Mandatory = $true)]
        [string] $BackupRoot
    )

    if (-not (Test-MoleBackupRootSafe -BackupRoot $BackupRoot -Plan $Plan)) {
        throw 'Backup root overlaps a cleanup target.'
    }

    $root = Get-MoleBackupRoot -BackupRoot $BackupRoot
    $runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runRoot = Join-Path $root $runId
    $itemsRoot = Join-Path $runRoot 'items'
    New-Item -ItemType Directory -Path $itemsRoot -Force -ErrorAction Stop | Out-Null

    $records = New-Object System.Collections.Generic.List[object]
    $index = 0

    foreach ($entry in @($Plan | Where-Object { $_.Action -eq 'Delete' -and $_.Exists })) {
        $source = Get-Item -LiteralPath $entry.Path -Force -ErrorAction Stop
        $itemId = '{0:D5}' -f $index
        $destination = Join-Path $itemsRoot $itemId
        $index++

        if ($source.PSIsContainer) {
            $children = @(Get-ChildItem -LiteralPath $source.FullName -Force -ErrorAction Stop)
            if ($children.Count -gt 0) {
                throw "Refusing to back up a non-empty directory: $($source.FullName)"
            }

            New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop | Out-Null
            $itemType = 'Directory'
            $length = 0
            $hash = $null
        }
        else {
            Copy-Item -LiteralPath $source.FullName -Destination $destination -Force -ErrorAction Stop
            $itemType = 'File'
            $length = $source.Length
            $hash = Get-MoleFileHashSafe -Path $source.FullName
        }

        $records.Add([pscustomobject]@{
                Id           = $itemId
                OriginalPath = $source.FullName
                BackupPath   = $destination
                ItemType     = $itemType
                Length       = $length
                SHA256       = $hash
            })
    }

    $manifest = [pscustomobject]@{
        FormatVersion = 1
        CreatedAt     = (Get-Date).ToUniversalTime().ToString('o')
        BackupRoot    = $runRoot
        Items         = @($records.ToArray())
    }
    $manifestPath = Join-Path $runRoot 'manifest.json'
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -Force

    return [pscustomobject]@{
        ManifestPath = $manifestPath
        BackupRoot   = $runRoot
        ItemCount    = $records.Count
        Items        = @($records.ToArray())
    }
}

function Restore-MoleBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ManifestPath,

        [switch] $Force
    )

    $manifestFile = Get-Item -LiteralPath $ManifestPath -Force -ErrorAction Stop
    $manifestRoot = $manifestFile.Directory.FullName
    $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json

    if ($manifest.FormatVersion -ne 1) {
        throw "Unsupported backup manifest format: $($manifest.FormatVersion)"
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($record in @($manifest.Items)) {
        $backupPath = Get-MoleCanonicalPath -Path $record.BackupPath
        if (-not (Test-MolePathWithin -Path $backupPath -Root $manifestRoot)) {
            throw "Backup item escapes manifest directory: $backupPath"
        }

        if (-not (Test-Path -LiteralPath $backupPath)) {
            throw "Backup item is missing: $backupPath"
        }

        if ($record.SHA256) {
            $backupHash = Get-MoleFileHashSafe -Path $backupPath
            if ($backupHash -ne $record.SHA256) {
                throw "Backup hash verification failed: $backupPath"
            }
        }

        $originalPath = Get-MoleCanonicalPath -Path $record.OriginalPath
        if (Test-MolePathProtected -Path $originalPath) {
            throw "Refusing to restore into a protected path: $originalPath"
        }
        $originalItem = Get-Item -LiteralPath $originalPath -Force -ErrorAction SilentlyContinue

        if ($null -ne $originalItem -and -not $Force) {
            $results.Add([pscustomobject]@{
                    OriginalPath = $originalPath
                    Action       = 'Skip'
                    Reason       = 'DestinationExists'
                })
            continue
        }

        if ($record.ItemType -eq 'Directory') {
            New-Item -ItemType Directory -Path $originalPath -Force -ErrorAction Stop | Out-Null
        }
        elseif ($record.ItemType -eq 'File') {
            $parent = Split-Path -Parent $originalPath
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
            }
            Copy-Item -LiteralPath $backupPath -Destination $originalPath -Force:$Force -ErrorAction Stop

            if ($record.SHA256) {
                $restoredHash = Get-MoleFileHashSafe -Path $originalPath
                if ($restoredHash -ne $record.SHA256) {
                    throw "Hash verification failed after restoring '$originalPath'."
                }
            }
        }
        else {
            throw "Unsupported backup item type: $($record.ItemType)"
        }

        $results.Add([pscustomobject]@{
                OriginalPath = $originalPath
                Action       = 'Restored'
                Reason       = $null
            })
    }

    return @($results.ToArray())
}
