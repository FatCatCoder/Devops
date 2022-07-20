function SemVer {
    [cmdletbinding()]
    Param (
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true
        )]
        [Alias('version', 'v')]
        [string]$VersionNumber
    )

    $v  = [System.Version]::Parse($VersionNumber)
    $vu = [version]::New($v.Major,$v.Minor,$v.build+1)
    switch -wildcard ($v) 
    { 
            {$v.build -eq '9'} {$vu = [version]::New($v.Major,$v.Minor+1,0)}
            {$v.Minor -eq '9' -AND $v.build -eq '9'} {$vu = [version]::New($v.Major+1,0,0)}
            {$v.Major -eq '9' -AND $v.Minor -eq '9' -AND $v.build -eq '9'} {$vu = [version]::New($v.Major+1,0,0)}
            {$v.Major -eq '99' -AND $v.Minor -eq '9' -AND $v.build -eq '9'} {$vu = [version]::New($v.Major+1,0,0)}
        default {$vu = [version]::New($v.Major,$v.Minor,$v.build+1)}
    }

    Write-host $vu
}

Export-ModuleMember -Function SemVer