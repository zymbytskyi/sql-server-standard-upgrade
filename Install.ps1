#Requires -Version 5.1
[CmdletBinding()]
param([string]$Destination='C:\Tools\SqlServerStandardEditionUpgrade-v0.1.0-preview1',[switch]$NoLaunch)
$ErrorActionPreference='Stop'
$names=@('Actions.ps1','Core.ps1','Download.ps1','Library.ps1','Media.ps1','Sql.ps1','WorkflowOperations.ps1','WorkflowSupport.ps1','Start-SqlServerUpgrade.ps1','Verify-Recovery.ps1','Test-SqlServerUpgrade.ps1','README.md','VALIDATION.md','Install.ps1')
$Destination=[IO.Path]::GetFullPath($Destination)
if($Destination.TrimEnd('\') -eq $PSScriptRoot.TrimEnd('\')){throw 'Choose a destination different from the source folder.'}
foreach($name in $names){if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)){throw "Incomplete package: $name"}}
if(Test-Path -LiteralPath $Destination){
    foreach($name in $names){
        $target=Join-Path $Destination $name
        if(-not(Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash){throw 'Destination differs. Choose a new versioned directory; existing files were preserved.'}
    }
}else{
    New-Item -ItemType Directory -Path $Destination | Out-Null
    foreach($name in $names){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $Destination}
}
foreach($name in $names){Unblock-File -LiteralPath (Join-Path $Destination $name)}
Write-Host "Installed SQL Server Standard Edition Upgrade preview to $Destination. Licensed Standard end-to-end qualification remains required."
if(-not$NoLaunch){& (Join-Path $Destination 'Start-SqlServerUpgrade.ps1')}
