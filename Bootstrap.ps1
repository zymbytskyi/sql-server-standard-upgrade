#Requires -Version 5.1
[CmdletBinding()]
param([string]$Destination='C:\Tools\SqlServerStandardEditionUpgrade-v0.1.0-preview1',[switch]$NoLaunch)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$work=Join-Path $env:TEMP ('SqlStandardUpgradeDownload-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$archive=Join-Path $work 'package.zip'
$url='https://github.com/zymbytskyi/sql-server-standard-upgrade/releases/download/v0.1.0-preview1/sql-server-standard-upgrade-v0.1.0-preview1.zip'
Write-Host 'Downloading SQL Server Standard Edition Upgrade v0.1.0-preview1...'
Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne '836CE88782EAAA2D22F478FABB126DB2D82DC00ECA500012C9E2BB5CC00999DB'){throw 'Package SHA-256 mismatch. Nothing was installed.'}
$source=Join-Path $work 'package'
Expand-Archive -LiteralPath $archive -DestinationPath $source
Get-ChildItem -LiteralPath $source -Filter '*.ps1' | Unblock-File
& (Join-Path $source 'Install.ps1') -Destination $Destination -NoLaunch:$NoLaunch
