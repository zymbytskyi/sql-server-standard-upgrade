#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$WorkRoot='C:\SqlServerUpgradeData',[string]$InstanceName,[switch]$LabDeveloper,
    [ValidateSet('Menu','Discover','Prepare','Backup','Preflight','Upgrade','Verify','Recovery','ReviewAgent')][string]$Mode='Menu')
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
if(-not[Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell as administrator.'}
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'Library.ps1')
if($LabDeveloper){Write-Warning 'LAB DEVELOPER ONLY: this run does not qualify Standard licensing or edition behavior.'}
if($Mode -eq 'Discover'){Get-LocalStandardInstance;return}
$WorkRoot=[IO.Path]::GetFullPath($WorkRoot).TrimEnd('\')
if($WorkRoot -notmatch '^[A-Za-z]:\\' -or $WorkRoot.Length -le 3 -or $WorkRoot.Contains('"') -or $WorkRoot -eq $PSScriptRoot -or $WorkRoot.StartsWith($PSScriptRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Use a dedicated local runtime folder outside this package.'}
$planPath=Join-Path $WorkRoot 'plan.json';$machineGuid=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
if(Test-Path $planPath){$saved=Get-Content $planPath -Raw|ConvertFrom-Json;if($InstanceName -and $InstanceName -ne $saved.Instance){throw 'Instance differs from saved plan.'};$InstanceName=$saved.Instance;$null=Read-Plan}else{$InstanceName=Select-StandardInstance $InstanceName}
Assert-InstanceName $InstanceName
$mutex=[Threading.Mutex]::new($false,'Global\SqlServerUpgrade-'+$InstanceName);$held=$false
$ValidationMode='VerifyOnly';$BackupScope='All'
try{
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not$held){throw 'Another campaign menu is running for this instance.'}
    Initialize-PrivateRuntime
    function Invoke-Action([string]$Action){
        switch($Action){Prepare {Prepare-Local} Backup {Backup-Local} Preflight {Final-Readiness} Upgrade {Open-UpgradeWizard} Verify {Verify-Local} Recovery {Record-Recovery} ReviewAgent {Approve-AgentStepChanges}}
    }
    if($Mode -ne 'Menu'){Invoke-Action $Mode;return}
    do{
        Write-Host "`nSQL SERVER STANDARD EDITION UPGRADE | $env:COMPUTERNAME\$InstanceName | $WorkRoot"
        if(Test-Path $planPath){$p=Read-Plan;Write-Host "Target: $($p.Target.Year) | Phase: $($p.Phase)"}
        Write-Host '1 Prepare (target 2022/2025, ISO, update and plans)'
        Write-Host '2 Backups | 3 Final readiness | 4 Upgrade Wizard'
        Write-Host '5 Verify after restart | 6 Record/read rollback plan'
        Write-Host '7 Optional full restore rehearsal | 8 Read instructions | 9 Review changed Agent steps | 0 Exit'
        $choice=Read-Host 'Choose'
        if($choice -eq '0'){break}
        try{
            Write-Host 'START'
            switch($choice){
                '1' {Prepare-Local} '2' {Backup-Local} '3' {Final-Readiness} '4' {Open-UpgradeWizard} '5' {Verify-Local} '6' {Record-Recovery}
                '7' {Assert-NoSetup;Write-Host 'Full temporary user database restores plus CHECKDB: high I/O and additional scratch disk. Failed scratch databases remain for diagnosis.';if((Read-Host 'Type REHEARSE') -ceq 'REHEARSE'){$ValidationMode='FullRestore';try{Invoke-ValidateBackups}finally{$ValidationMode='VerifyOnly'}}}
                '9' {Approve-AgentStepChanges}
                '8' {Write-Plans;Get-Content (Join-Path $WorkRoot 'UPGRADE-PLAN.txt')|Out-Host}
                default {throw 'Choose a displayed option.'}
            }
            Write-Host 'SUCCESS' -ForegroundColor Green
        }catch{Write-Host ('FAILED: '+$_.Exception.Message) -ForegroundColor Red}
        [void](Read-Host 'Press Enter to return to the menu')
    }while($true)
}finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
