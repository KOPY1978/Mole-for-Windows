@{
    RootModule        = 'Mole.Windows.psm1'
    ModuleVersion     = '0.5.0'
    GUID              = '8c6ff8e7-7b4f-4d47-bf4c-6b2da5c6f4de'
    Author            = 'Mole for Windows contributors'
    Description       = 'Safety-first Windows cleanup primitives for Mole for Windows.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
