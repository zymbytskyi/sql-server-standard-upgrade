#Requires -Version 5.1
# Fixture validation only: no real SQL, ISO mount, installer, credentials or restart.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Library.ps1')
$root=Join-Path $env:TEMP ('SqlStandardFixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root|Out-Null
$WorkRoot=$root;$planPath=Join-Path $root 'plan.json';$InstanceName='APPDATA';$machineGuid='fixture-machine';$ValidationMode='VerifyOnly';$BackupScope='All'
function Check($Value,[string]$Message){if(-not$Value){throw $Message};Write-Host "PASS: $Message"}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $Message}
try{
    $file='caller-file-variable';. (Join-Path $PSScriptRoot 'Library.ps1');Check ($file -eq 'caller-file-variable') 'library import preserves caller file variable'
    Check ((Get-TargetProfile 2022).Major -eq 16 -and (Get-TargetProfile 2025).Major -eq 17) 'target profiles map 2022/2025 to SQL 16/17'
    Reject {Get-TargetProfile 2019} 'unknown target rejected'
    Assert-Os ([pscustomobject]@{ProductType=3;BuildNumber=14393}) (Get-TargetProfile 2022)
    Reject {Assert-Os ([pscustomobject]@{ProductType=3;BuildNumber=14393}) (Get-TargetProfile 2025)} '2025 blocks Windows Server 2016'
    Assert-Os ([pscustomobject]@{ProductType=3;BuildNumber=20348}) (Get-TargetProfile 2025)
    Reject {Assert-Os ([pscustomobject]@{ProductType=3;BuildNumber=26100}) (Get-TargetProfile 2022)} 'SQL 2017 source on Windows Server 2025 remains blocked'
    Reject {Assert-Os ([pscustomobject]@{ProductType=2;BuildNumber=20348}) (Get-TargetProfile 2025)} 'domain controller excluded'
    Assert-InstanceName MSSQLSERVER;Assert-InstanceName APPDATA
    Reject {Assert-InstanceName 'remote\APPDATA'} 'remote instance rejected'
    $html='<table><tr><td>16.0.4305.5</td><td>CU27 + GDR</td><td>KB5126934</td></tr><tr><td>16.0.4295.3</td><td>CU27</td><td>KB5104824</td></tr><tr><td>16.0.1210.3</td><td>GDR</td><td>KB5128493</td></tr><tr><td>17.0.5035.5</td><td>CU10</td><td>KB5125471</td></tr><tr><td>17.0.4006.2</td><td>CU1</td><td>KB5078298</td></tr></table>'
    $a=@(Convert-ServicingCatalog $html 16);$b=@(Convert-ServicingCatalog $html 17)
    Check ($a.Count -eq 2 -and $a[0].Build -eq '16.0.4305.5') 'CU-branch security wins; RTM GDR excluded'
    Check ($b.Count -eq 2 -and $b[0].Build -eq '17.0.5035.5') 'numeric newest-first ordering survives grouping'
    Check (@(Convert-ServicingCatalog '<p>unknown response</p>' 17).Count -eq 0) 'unrecognized catalog yields no target'
    Assert-UpdateIdentity 2025 17 '17.0.5035.5' KB5125471 'SQLServer2025-KB5125471-x64.exe'
    Reject {Assert-UpdateIdentity 2025 16 '16.0.4305.5' KB5126934 'SQLServer2022-KB5126934-x64.exe'} 'cross-version update rejected'
    Reject {Assert-UpdateIdentity 2025 17 '17.0.1000.7' KB5125471 'SQLServer2025-KB5125471-x64.exe'} 'RTM update target rejected'
    Assert-DownloadUri 'https://download.microsoft.com/path/SQLServer2025-KB5125471-x64.exe' 'SQLServer2025-KB5125471-x64.exe'
    Reject {Assert-DownloadUri 'https://download.microsoft.com.evil.test/SQLServer2025-KB5125471-x64.exe' 'SQLServer2025-KB5125471-x64.exe'} 'foreign package host rejected'
    function Get-Service {param($Name,$ErrorAction) $null}
    $db=[pscustomobject]@{Name='Demo';State='ONLINE';Compatibility=140;ReadOnly=0;Encrypted=0;Distributor=0;Published=0;Subscribed=0;MergePublished=0;SnapshotSource=[DBNull]::Value;Bytes=30GB;DataBytes=30GB}
    $live=[pscustomobject]@{Server=[pscustomobject]@{Machine=$env:COMPUTERNAME;EngineEdition=2;Edition='Standard Edition (64-bit)';Build='14.0.1000.169';IsSysadmin=1;Clustered=0;Hadr=0};Databases=@($db)}
    Assert-Inventory $live
    Check $true 'Standard database larger than Express 10 GiB cap accepted'
    $live.Server.EngineEdition=4;Reject {Assert-Inventory $live} 'Express edition rejected';$live.Server.EngineEdition=2
    $live.Server.Edition='Developer Edition (64-bit)';$live.Server.EngineEdition=3
    Reject {Assert-Inventory $live} 'production mode blocks Developer'
    $LabDeveloper=$true;Assert-Inventory $live;Check $true 'explicit lab mode accepts Developer'
    Check (Test-SelectedEdition 'Enterprise Developer Edition (64-bit)' 3) 'lab mode accepts Enterprise Developer 2025 target'
    Check (-not(Test-SelectedEdition 'Enterprise Edition (64-bit)' 3)) 'lab mode rejects paid Enterprise edition'
    $live.Server.Edition='Standard Edition (64-bit)';$live.Server.EngineEdition=2
    Reject {Assert-Inventory $live} 'lab mode does not relax Standard production guard'
    $LabDeveloper=$false
    $live.Server.Hadr=1;Reject {Assert-Inventory $live} 'AG rejected';$live.Server.Hadr=0
    $live.Server.Clustered=1;Reject {Assert-Inventory $live} 'FCI rejected';$live.Server.Clustered=0
    $db.Encrypted=1;Reject {Assert-Inventory $live} 'unsupported encrypted database blocked';$db.Encrypted=0
    $p=[pscustomobject]@{Schema=1;Product='SqlServerUpgrade';Id='campaign';MachineGuid=$machineGuid;Computer=$env:COMPUTERNAME;Instance=$InstanceName;SourceBuild=$live.Server.Build;Target=(Get-TargetProfile 2025);Baseline=$live;ApprovedBuild='17.0.5035.5';BackupDirectory=(Join-Path $root 'backups')}
    New-Item -ItemType Directory $p.BackupDirectory|Out-Null;Save-Json $planPath $p
    $null=Read-Plan
    $LabDeveloper=$true;Reject {Read-Plan} 'Standard campaign cannot reopen in lab mode';$LabDeveloper=$false
    $p.Product='SqlExpressUpgrade';Save-Json $planPath $p;Reject {Read-Plan} 'Express campaign cannot be reused';$p.Product='SqlServerUpgrade';Save-Json $planPath $p
    $u=[pscustomobject]@{PlanId=$p.Id;Major=17;PackagePath='C:\Stage With Spaces\Updates\SQLServer2025-KB5125471-x64.exe'}
    $args=@(Get-UpgradeArguments $p $u)
    Check ($args -contains '/UPDATEENABLED=True' -and $args -contains '/UIMODE=Normal' -and $args -notcontains '/Q' -and ($args -join '|') -notmatch '/PID') 'interactive launch integrates update and never extracts/passes old PID'
    Check ($args -contains '/UPDATESOURCE="C:\Stage With Spaces\Updates"') 'UpdateSource path with spaces quoted'
    $u.Major=16;Reject {Get-UpgradeArguments $p $u} 'launcher rejects wrong update target'
    Assert-FinalBuild $p '17.0.5035.5'
    Reject {Assert-FinalBuild $p '17.0.1000.7'} 'RTM cannot pass final acceptance'
    Reject {Assert-FinalBuild $p '17.0.5040.1'} 'unapproved newer build cannot pass exact acceptance'
    $agent=[pscustomobject]@{Jobs=@();Steps=@();Schedules=@();JobSchedules=@();Operators=@();Proxies=@();Credentials=@();ServiceAccount='NT SERVICE\SQLAgent$APPDATA';StartMode='Auto';WasRunning=$true}
    $other=$agent|ConvertTo-Json -Depth 10|ConvertFrom-Json
    Assert-AgentUnchanged $agent $other
    $other.WasRunning=$false;Reject {Assert-AgentUnchanged $agent $other} 'previously running Agent must restart';$other.WasRunning=$true
    $other.Jobs=@('changed');Reject {Assert-AgentUnchanged $agent $other} 'Agent job metadata changes block acceptance'
    $other.Jobs=@();$other.Steps=@([pscustomobject]@{JobId='fixture';StepId=1;DefinitionHash='changed'})
    $reviewPlan=[pscustomobject]@{Id='review-fixture';ApprovedBuild='16.0.4305.5';Agent=$agent}
    Reject {Assert-AgentAfterUpgrade $reviewPlan $other} 'changed steps require explicit review'
    Save-Json (Join-Path $WorkRoot 'agent-step-review.json') @{PlanId=$reviewPlan.Id;Build=$reviewPlan.ApprovedBuild;BeforeHash=(Get-AgentStepsHash $agent.Steps);AfterHash=(Get-AgentStepsHash $other.Steps);Reason='Fixture-only approval'}
    Assert-AgentAfterUpgrade $reviewPlan $other;Check $true 'exact reviewed steps accepted'
    $reviewPlan.Id='different';Reject {Assert-AgentAfterUpgrade $reviewPlan $other} 'step approval is campaign-bound';$reviewPlan.Id='review-fixture'
    $other.Jobs=@('changed');Reject {Assert-AgentAfterUpgrade $reviewPlan $other} 'step approval never bypasses job metadata';$other.Jobs=@()
    $other.Steps[0].DefinitionHash='changed-again';Reject {Assert-AgentAfterUpgrade $reviewPlan $other} 'later step changes invalidate approval'
    # Real manifest/cache/backup orchestration with SQL and storage fixtures only.
    function Get-Inventory {param($Instance) $live}
    function Assert-Disk {param($Directory,$Required)}
    function Show-RebootIndicators {}
    function Invoke-Query {param($Instance,$Sql)
        if($Sql -like 'BACKUP DATABASE*'){$match=[regex]::Match($Sql,"TO DISK=N'((?:''|[^'])*)'");Set-Content -LiteralPath ($match.Groups[1].Value.Replace("''","'")) 'fixture backup'}
    }
    Invoke-Backup
    Check (Test-Path (Join-Path $root 'backups.json')) 'source manifest recorded separately'
    Invoke-ValidateBackups -ReuseOnly
    $sourceHash=(Get-FileHash (Join-Path $root 'backups.json')).Hash
    $live.Server.Build='17.0.5035.5';Invoke-Backup
    Check ((Get-FileHash (Join-Path $root 'backups.json')).Hash -eq $sourceHash -and (Test-Path (Join-Path $root 'backups-target.json'))) 'target backups preserve original SQL 2017 recovery manifest'
    # Reject media damage before Setup; metadata/signature calls are fixtures.
    & {
        $media=Join-Path $WorkRoot 'Media';New-Item -ItemType Directory $media|Out-Null
        'media fixture'|Set-Content (Join-Path $media 'setup.exe')
        $mp=[pscustomobject]@{Prepared=$true;Target=$p.Target;MediaFiles=@([pscustomobject]@{Path='setup.exe';Sha256=(Get-FileHash (Join-Path $media 'setup.exe')).Hash})}
        function Assert-StandardMedia {param($Directory,$Profile)}
        Assert-MediaHashes $mp
        Add-Content (Join-Path $media 'setup.exe') 'changed';Reject {Assert-MediaHashes $mp} 'changed base media blocks launch'
    }
    & {
        $dir=Join-Path $WorkRoot 'Updates\KB5125471-17.0.5035.5';New-Item -ItemType Directory $dir -Force|Out-Null
        $file=Join-Path $dir 'SQLServer2025-KB5125471-x64.exe';'update fixture'|Set-Content $file
        $update=@{PlanId=$p.Id;Year=2025;Major=17;KB='KB5125471';Build='17.0.5035.5';PackagePath=$file;Sha256=(Get-FileHash $file).Hash}
        Save-Json (Join-Path $WorkRoot 'update.json') $update
        function Assert-MicrosoftFile {param($Path)}
        function Get-Item {param($LiteralPath) [pscustomobject]@{VersionInfo=[pscustomobject]@{ProductMajorPart=17;ProductMinorPart=0;ProductBuildPart=5035;ProductPrivatePart=5}}}
        $null=Assert-PreparedUpdate $p
        Add-Content $file 'modified';Reject {Assert-PreparedUpdate $p} 'tampered CU bytes rejected'
        'update fixture'|Set-Content $file;'other'|Set-Content (Join-Path $dir 'other.exe');Reject {Assert-PreparedUpdate $p} 'mixed update source rejected'
    }
    'PASS: isolated Standard target/backup/Agent/media/update checks. No live upgrade performed.'
}finally{
    $safe=[IO.Path]::GetFullPath($root)
    if(-not$safe.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\SqlStandardFixture-',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup path'}
    Remove-Item -LiteralPath $safe -Recurse -Force
}
