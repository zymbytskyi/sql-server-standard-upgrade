function Initialize-Plan {
    if(Test-Path $planPath){return}
    $yearText=Read-Host 'Target SQL version: 2022 or 2025'
    if($yearText -notin @('2022','2025')){throw 'Choose 2022 or 2025.'}
    $profile=Get-TargetProfile ([int]$yearText)
    Assert-Os (Get-CimInstance Win32_OperatingSystem) $profile
    $inventory=Get-Inventory $InstanceName;Assert-Inventory $inventory
    $map=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    $id=$map.$InstanceName;$setup=Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$id\Setup"
    if($setup.Language -ne 1033){throw 'English SQL source is required for this first version.'}
    $fulltext=@(Invoke-Query $InstanceName "SELECT CONVERT(int,FULLTEXTSERVICEPROPERTY('IsFullTextInstalled')) AS Installed;")[0]
    if($fulltext.Installed -ne 0){throw 'This first version qualifies Database Engine and Agent only. Full-Text needs a separate tested profile.'}
    $edition=if(Test-LabDeveloper){'Developer (non-production only)'}else{'Standard'}
    $iso=(Read-Host ("Full path to target $edition ISO (local or UNC)")).Trim().Trim('"')
    if($iso -notmatch '^(?:[A-Za-z]:\\|\\\\)' -or [IO.Path]::GetExtension($iso) -ne '.iso' -or -not(Test-Path -LiteralPath $iso -PathType Leaf)){throw 'Specify an existing absolute .iso path.'}
    Write-Host ("Use target $edition media. Setup handles the edition/key; no SQL 2017 key is extracted.")
    $confirm=if(Test-LabDeveloper){'LAB'}else{'STANDARD'}
    if((Read-Host ("Confirm target $edition media and permitted use: type $confirm")) -cne $confirm){throw 'Target edition/licensing not confirmed.'}
    $default=(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$id\MSSQLServer").BackupDirectory
    if(-not$default -or -not(Test-Path $default -PathType Container)){throw 'SQL default backup folder must exist before configuring.'}
    $agent=Get-AgentInventory
    Save-Json $planPath @{Schema=1;Product='SqlServerUpgrade';LabDeveloper=(Test-LabDeveloper);Id=[guid]::NewGuid().ToString();MachineGuid=$machineGuid;Computer=$env:COMPUTERNAME;Instance=$InstanceName;InstanceId=$id;SourceBuild=$inventory.Server.Build;Target=$profile;IsoPath=[IO.Path]::GetFullPath($iso);IsoSha256=(Get-FileHash -LiteralPath $iso).Hash;BackupDirectory=$default;Baseline=$inventory;Agent=$agent;Prepared=$false;MediaFiles=@();Phase='Configured';BootBeforeSetup='';ApprovedBuild='';ApprovedUpdateHash='';CreatedUtc=[datetime]::UtcNow.ToString('o')}
}
function Prepare-Local {
    Assert-NoSetup
    if(Test-Path $planPath){$p=Read-Plan;if($p.Phase -in @('WizardOpened','Verified')){throw 'Setup was already launched. Use Verify/recovery; do not reprepare blindly.'}}
    Initialize-Plan
    $p=Read-Plan;Assert-Inventory (Get-Inventory $InstanceName)
    $null=Show-RebootIndicators
    Stage-Iso $p
    $p=Read-Plan;Prepare-Update $p
    $p.Phase='Prepared';Save-Json $planPath $p
    Write-Plans
    Write-Host 'Preparation complete. Next: menu 2; record external recovery with 6; then menu 3.'
}
function Select-BackupDirectory {
    $p=Read-Plan;$live=Get-Inventory $InstanceName
    $needed=[long](($live.Databases|Measure-Object Bytes -Sum).Sum*1.2)+2GB
    $drives=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'|Where-Object {$_.FileSystem -in @('NTFS','ReFS')}|Sort-Object FreeSpace -Descending)
    $drives|Select-Object DeviceID,@{n='FreeGiB';e={[math]::Round($_.FreeSpace/1GB,1)}},@{n='Enough';e={$_.FreeSpace -ge $needed}}|Format-Table|Out-Host
    $best=@($drives|Where-Object {$_.FreeSpace -ge $needed}|Select-Object -First 1)
    if(-not$best.Count){throw 'No fixed volume has estimated backup capacity plus reserve.'}
    $recommended=$best[0].DeviceID+'\SqlUpgradeBackups\'+$InstanceName+'\'+$p.Id
    Write-Host "Required estimate: $([math]::Round($needed/1GB,1)) GiB | recommended: $recommended"
    $path=(Read-Host 'Backup folder (Enter = recommendation)').Trim().Trim('"');if(-not$path){$path=$recommended}
    if($path -notmatch '^[A-Za-z]:\\' -or $path.IndexOfAny([char[]]'"*?') -ge 0){throw 'Use a dedicated absolute local backup folder.'}
    $path=[IO.Path]::GetFullPath($path).TrimEnd('\')
    if($path.Length -le 3 -or $path -eq $WorkRoot -or $path.StartsWith($WorkRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $path -eq $PSScriptRoot -or $path.StartsWith($PSScriptRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Backups must be outside the package and runtime folder.'}
    $parent=$path;while(-not(Test-Path $parent)){$parent=Split-Path $parent -Parent;if(-not$parent){throw 'Backup volume unavailable.'}}
    Assert-Disk $parent $needed
    if(-not(Test-Path $path)){
        New-Item -ItemType Directory $path -Force|Out-Null
        $service=if($InstanceName -eq 'MSSQLSERVER'){'MSSQLSERVER'}else{'MSSQL$'+$InstanceName}
        $sid=([Security.Principal.NTAccount]::new('NT SERVICE\'+$service)).Translate([Security.Principal.SecurityIdentifier])
        $acl=Get-Acl $path;$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'Modify','ContainerInherit,ObjectInherit','None','Allow'));Set-Acl $path $acl
    }
    $p.BackupDirectory=$path;Save-Json $planPath $p
}
function Backup-Local {
    Assert-NoSetup;$p=Read-Plan
    Assert-Inventory (Get-Inventory $InstanceName) (([version](Get-LiveBuild)).Major)
    Select-BackupDirectory;Invoke-Backup;Write-Plans
}
function Assert-RecoveryRecord($Plan) {
    $r=Get-Content (Join-Path $WorkRoot 'recovery.json') -Raw|ConvertFrom-Json
    if($r.PlanId -ne $Plan.Id -or -not$r.Provider -or -not$r.Reference -or -not$r.Procedure){throw 'Record a tested external recovery point and procedure with menu 6.'}
}
function Write-Readiness([string]$Status,[string]$Reason) {
    $p=Read-Plan;$lines=@("FINAL READINESS: $Status","Checked UTC: $([datetime]::UtcNow.ToString('o'))","$($p.Computer)\$($p.Instance): SQL $($p.SourceBuild) -> $($p.Target.Year) | source edition: $($p.Baseline.Server.Edition)","Details: $Reason")
    if(Test-Path (Join-Path $WorkRoot 'update.json')){$u=Get-Content (Join-Path $WorkRoot 'update.json') -Raw|ConvertFrom-Json;$lines+="Pinned update: $($u.KB) | $($u.Build) | $($u.PackagePath)"}
    $path=Get-ActiveBackupPath $p
    if(Test-Path $path){$b=Get-Content $path -Raw|ConvertFrom-Json;$age=([datetime]::UtcNow-([datetime]$b.CreatedUtc).ToUniversalTime()).TotalHours;$lines+="Backup set UTC: $($b.CreatedUtc) | age $([math]::Round($age,2)) hours";foreach($f in $b.Files){$lines+="$($f.Database): $($f.Path)"};if($age -gt 24){$lines+='ATTENTION: backups older than 24 hours. Take final backups after stopping writers.'}}else{$lines+="Missing backup manifest: $path. Run menu 2."}
    $lines+='Technical readiness does not prove application acceptance or recovery. Stop application writers and coordinate SQL Agent jobs before the upgrade.'
    $lines|Set-Content (Join-Path $WorkRoot 'FINAL-READINESS.txt') -Encoding UTF8;$lines|ForEach-Object {Write-Host $_}
}
function Assert-Preflight {
    Assert-NoSetup;$p=Read-Plan
    Assert-Os (Get-CimInstance Win32_OperatingSystem) $p.Target
    Assert-NoReboot
    $framework=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release
    if($framework.Release -lt 461808){throw '.NET Framework 4.7.2 or newer is required.'}
    $live=Get-Inventory $InstanceName;Assert-Inventory $live
    if($live.Server.Build -ne $p.SourceBuild -or (@($live.Databases.Name|Sort-Object)-join '|') -ne (@($p.Baseline.Databases.Name|Sort-Object)-join '|')){throw 'Source build/database scope changed. Use a new campaign.'}
    Assert-MediaHashes $p;$null=Assert-PreparedUpdate $p
    Assert-Disk $WorkRoot 8GB;Assert-Disk $env:SystemRoot 8GB
    foreach($f in @(Invoke-Query $InstanceName 'SELECT physical_name AS Path FROM sys.master_files;')){Assert-Disk (Split-Path $f.Path -Parent) 1GB}
    Assert-AgentUnchanged $p.Agent (Get-AgentInventory)
    Assert-RecoveryRecord $p
}
function Final-Readiness {
    try{Assert-Preflight;Invoke-ValidateBackups;Write-Readiness 'TECHNICAL CHECKS PASSED' 'VERIFYONLY WITH CHECKSUM, media/update hashes and Agent baseline checked. Any separate full restore rehearsal is recorded in validation-FullRestore.json.'}
    catch{$failure=$_;if(Test-Path $planPath){Write-Readiness 'NOT READY' $failure.Exception.Message};throw $failure}
}
function Get-UpgradeArguments($Plan,$Update) {
    Assert-InstanceName $Plan.Instance
    if($Update.PlanId -ne $Plan.Id -or $Update.Major -ne $Plan.Target.Major){throw 'Wrong update for this campaign.'}
    @('/ACTION=Upgrade',"/INSTANCENAME=$($Plan.Instance)",'/UPDATEENABLED=True',('/UPDATESOURCE="{0}"' -f (Split-Path $Update.PackagePath -Parent)),'/UIMODE=Normal')
}
function Open-UpgradeWizard {
    if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Use an interactive desktop/RDP PowerShell window for the Wizard.'}
    Assert-Preflight;Invoke-ValidateBackups -ReuseOnly
    $p=Read-Plan;$u=Assert-PreparedUpdate $p
    $edition=if(Test-LabDeveloper){'Developer (Enterprise Developer for 2025)'}else{'Standard'}
    Write-Host "Setup will use SQL $($p.Target.Year) media and $($u.KB), target $($u.Build). Confirm $edition on the Product Key/edition page, and the KB on Product Updates. Do not deselect updates."
    Write-Host 'This version has not completed licensed Standard end-to-end qualification. Rehearse on a restored non-production copy first.'
    if((Read-Host 'Confirm application writers/Agent jobs are stopped or coordinated and recovery is ready. Type UPGRADE') -cne 'UPGRADE'){return}
    $active=@(Invoke-Query $InstanceName 'SELECT a.job_id FROM msdb.dbo.sysjobactivity a WHERE a.session_id=(SELECT MAX(session_id) FROM msdb.dbo.syssessions) AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL;')
    if($active.Count){throw 'SQL Agent jobs are still executing. Coordinate them before starting Upgrade.'}
    Assert-NoSetup;Assert-NoReboot
    $p.Phase='WizardOpened';$p.BootBeforeSetup=Get-Boot;$p.ApprovedBuild=$u.Build;$p.ApprovedUpdateHash=$u.Sha256;Save-Json $planPath $p
    Start-Process -FilePath (Join-Path $WorkRoot 'Media\setup.exe') -ArgumentList (Get-UpgradeArguments $p $u)|Out-Null
}
function Assert-FinalBuild($Plan,[string]$Build) {
    if(-not$Plan.ApprovedBuild -or $Build -ne $Plan.ApprovedBuild){throw "Expected exact approved build $($Plan.ApprovedBuild); detected $Build. RTM/wrong target cannot pass."}
}
function Verify-Local {
    Assert-NoSetup;$p=Read-Plan
    if(-not$p.BootBeforeSetup -or (Get-Boot) -eq $p.BootBeforeSetup){throw 'Finish Setup and restart Windows before verification.'}
    $u=Assert-PreparedUpdate $p
    if($u.Sha256 -ne $p.ApprovedUpdateHash -or $u.Build -ne $p.ApprovedBuild){throw 'Update target changed after Setup launch.'}
    Assert-FinalBuild $p (Get-LiveBuild)
    Invoke-Verify
    Assert-AgentAfterUpgrade $p (Get-AgentInventory)
    $p.Phase='Verified';Save-Json $planPath $p
    @('TECHNICAL VERIFICATION PASSED',"$($p.Computer)\$($p.Instance): $($p.SourceBuild) -> $($u.Build) | campaign lab mode: $(Test-LabDeveloper) | $($u.KB)",'SQL Agent metadata/account/start-mode and initial running state checked.','Original user database compatibility levels retained.','Application owner: validate login, representative reads/writes, scheduled jobs and performance before reopening traffic.','No automatic compatibility change or application start is performed.')|Set-Content (Join-Path $WorkRoot 'COMPLETION.txt') -Encoding UTF8
    Get-Content (Join-Path $WorkRoot 'COMPLETION.txt')|Out-Host
}
function Write-Plans {
    $p=Read-Plan
    $edition=if(Test-LabDeveloper){'Developer LAB ONLY'}else{'Standard'}
    $target='Not prepared: run menu 1'
    if(Test-Path (Join-Path $WorkRoot 'update.json')){$u=Get-Content (Join-Path $WorkRoot 'update.json') -Raw|ConvertFrom-Json;$target="$($u.KB) / $($u.Build) / $($u.PackagePath)"}
    $menu=Join-Path $PSScriptRoot 'Start-SqlServerUpgrade.ps1'
    $modeArg=if(Test-LabDeveloper){' -LabDeveloper'}else{''}
    @('SQL SERVER STANDARD EDITION UPGRADE PLAN',"Campaign edition: $edition","Instance: $($p.Computer)\$($p.Instance)","Source: $($p.SourceBuild) | target: SQL $($p.Target.Year) $edition", "Update: $target", "Prepared media: $WorkRoot\Media\setup.exe", "Backups: $($p.BackupDirectory)",
      '1. Sign in to this SQL server; open 64-bit Windows PowerShell as administrator.',
      "2. Open menu: & '$menu' -WorkRoot '$WorkRoot'$modeArg",
      "3. Prepare: menu 1. Provide target $edition ISO, approve target update. No old product key is extracted.",
      '4. Backups: menu 2. Choose storage, wait for COPY_ONLY/CHECKSUM and VERIFYONLY. Copy backups off-server.',
      '5. Recovery: menu 6. Record the tested external full-server recovery point and exact procedure. Read ROLLBACK-PLAN.txt.',
      '6. Optional menu 7 restores user backups into scratch databases and runs CHECKDB; allow additional time/space.',
      '7. Resolve pending Windows restart during approved downtime. Reopen the same menu/runtime.',
      '8. Stop application writers and coordinate Agent jobs. Take final menu 2 backups, copy off-server; run menu 3.',
      "9. Only after readiness passes: menu 4. Confirm existing instance, $edition edition and pinned KB in Product Updates. Keep updates selected; review rules and click Upgrade.",
      "10. Review Complete and logs under SQL Server\$($p.Target.Major)0\Setup Bootstrap\Log. Close Setup, restart Windows.",
      '11. Reopen the same menu; choose 5. Never rerun 4 for verification. Review COMPLETION.txt and obtain application-owner acceptance.',
      '12. Keep original user database compatibility levels until separately approved application testing. No automatic level change.')|Set-Content (Join-Path $WorkRoot 'UPGRADE-PLAN.txt') -Encoding UTF8
    $record=Join-Path $WorkRoot 'recovery.json'
    $recovery=if(Test-Path $record){$r=Get-Content $record -Raw|ConvertFrom-Json;"Provider: $($r.Provider) | point: $($r.Reference) | procedure: $($r.Procedure)"}else{'NOT RECORDED: choose menu 6 before readiness/upgrade.'}
    @('FULL-SERVER ROLLBACK PLAN',"Instance: $($p.Computer)\$($p.Instance) | restore SQL $($p.SourceBuild)",$recovery,
      '1. Agree rollback deadline and expected data loss with the application owner before downtime.',
      '2. On failure keep writers stopped. Preserve Setup logs and any later business writes off-server.',
      '3. Use the recorded provider console/procedure to restore the full server to the pre-upgrade recovery point. Confirm its exact machine identity. All later changes may be lost.',
      '4. SQL backup files alone do not roll back the installed engine. There is no in-place downgrade. Newer SQL backups cannot restore onto SQL 2017.',
      '5. Keep original system/user backups, external VM recovery and this package/plan off-server. Protect licensed media and runtime from general access.',
      "6. On the restored SQL server, run: & '$(Join-Path $PSScriptRoot 'Verify-Recovery.ps1')' -WorkRoot '$WorkRoot'$modeArg",
      '   This script checks original build/edition, original databases and Agent metadata, then runs CHECKDB. It does not restore a VM or database.',
      '7. Verify domain trust, logins, scheduled tasks and application reads/writes. Reopen traffic only after application-owner acceptance.')|Set-Content (Join-Path $WorkRoot 'ROLLBACK-PLAN.txt') -Encoding UTF8
    Write-Host "Instructions: $WorkRoot\UPGRADE-PLAN.txt and ROLLBACK-PLAN.txt"
}
function Record-Recovery {
    $p=Read-Plan
    $provider=Read-Host 'External full-server recovery provider'
    $reference=Read-Host 'Existing tested pre-upgrade recovery point/reference (no secrets)'
    $procedure=Read-Host 'Exact restore procedure or protected runbook path and responsible operator'
    if(-not$provider -or -not$reference -or -not$procedure){throw 'All recovery fields are required.'}
    Save-Json (Join-Path $WorkRoot 'recovery.json') @{PlanId=$p.Id;Provider=$provider;Reference=$reference;Procedure=$procedure;RecordedUtc=[datetime]::UtcNow.ToString('o')}
    Write-Plans;Get-Content (Join-Path $WorkRoot 'ROLLBACK-PLAN.txt')|Out-Host
}





function Approve-AgentStepChanges {
    Assert-NoSetup;$p=Read-Plan
    Assert-FinalBuild $p (Get-LiveBuild)
    Assert-Inventory (Get-Inventory $InstanceName) $p.Target.Major
    $after=Get-AgentInventory
    $copy=$after|ConvertTo-Json -Depth 10|ConvertFrom-Json;$copy.Steps=$p.Agent.Steps
    Assert-AgentUnchanged $p.Agent $copy
    $beforeHash=Get-AgentStepsHash $p.Agent.Steps;$afterHash=Get-AgentStepsHash $after.Steps
    if($beforeHash -eq $afterHash){Write-Host 'No Agent step changes to approve.';return}
    $changes=@(Compare-Object -ReferenceObject @($p.Agent.Steps) -DifferenceObject @($after.Steps) -Property JobId,StepId,DefinitionHash)
    $changes|Select-Object @{n='Job';e={$id=$_.JobId;(@($after.Jobs|Where-Object Id -eq $id)[0]).Name}},StepId,SideIndicator,DefinitionHash|Format-Table -AutoSize|Out-Host
    Write-Host '=> current; <= source. In SSMS open SQL Server Agent > Jobs > job Properties > Steps. Compare with the pre-upgrade job definition or original msdb backup. Setup can update syspolicy_purge_history; do not assume every change is expected.'
    $reason=Read-Host 'Review explanation (no commands, credentials or secrets)'
    if(-not$reason -or (Read-Host 'Type APPROVE-STEPS only after reviewing these exact changes') -cne 'APPROVE-STEPS'){throw 'Agent changes not approved.'}
    Save-Json (Join-Path $WorkRoot 'agent-step-review.json') @{PlanId=$p.Id;Build=$p.ApprovedBuild;BeforeHash=$beforeHash;AfterHash=$afterHash;Reason=$reason;ReviewedUtc=[datetime]::UtcNow.ToString('o');OperatorSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
    Write-Host 'Approval recorded for these exact steps. Run menu 5 again; job identities, schedules, proxies, credentials and service checks are unchanged.'
}
