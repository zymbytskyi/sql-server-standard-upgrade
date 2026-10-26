#Requires -Version 5.1
#Requires -RunAsAdministrator
param([string]$WorkRoot='C:\SqlServerUpgradeData',[switch]$LabDeveloper)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Library.ps1')
$planPath=Join-Path $WorkRoot 'plan.json';$machineGuid=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
$InstanceName=(Get-Content $planPath -Raw|ConvertFrom-Json).Instance;$p=Read-Plan
Assert-NoSetup;$live=Get-Inventory $InstanceName;Assert-Inventory $live 14
if($live.Server.Build -ne $p.SourceBuild){throw 'Recovered build differs from original SQL 2017 build.'}
if((@($live.Databases.Name|Sort-Object)-join '|') -ne (@($p.Baseline.Databases.Name|Sort-Object)-join '|')){throw 'Recovered database scope differs.'}
Assert-AgentUnchanged $p.Agent (Get-AgentInventory)
Invoke-FullCheckDB
Write-Host 'Recovered SQL build, edition, database scope, Agent and CHECKDB passed. Check domain trust and obtain application-owner acceptance before reopening traffic.'
