function Get-MoleTestPesterMajorVersion {
    $module = Get-Module -Name Pester | Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($null -eq $module) {
        throw 'Pester must be imported before running Mole test helpers.'
    }

    return [int] $module.Version.Major
}

function Assert-MoleEqual {
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Actual,

        [Parameter(Position = 1)]
        [AllowNull()]
        [object] $Expected
    )

    if ((Get-MoleTestPesterMajorVersion) -ge 5) {
        $Actual | Should -Be $Expected
    }
    else {
        $Actual | Should Be $Expected
    }
}

function Assert-MoleTrue {
    param([Parameter(Position = 0)][object] $Actual)
    Assert-MoleEqual $Actual $true
}

function Assert-MoleFalse {
    param([Parameter(Position = 0)][object] $Actual)
    Assert-MoleEqual $Actual $false
}

function Assert-MoleNullOrEmpty {
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Actual
    )

    if ((Get-MoleTestPesterMajorVersion) -ge 5) {
        $Actual | Should -BeNullOrEmpty
    }
    else {
        $Actual | Should BeNullOrEmpty
    }
}

function Assert-MoleThrows {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [scriptblock] $ScriptBlock
    )

    if ((Get-MoleTestPesterMajorVersion) -ge 5) {
        $ScriptBlock | Should -Throw
    }
    else {
        $ScriptBlock | Should Throw
    }
}
