function Test-LabDeveloper {
    $flag=Get-Variable LabDeveloper -ErrorAction SilentlyContinue
    [bool]($flag -and $flag.Value)
}
function Test-SelectedEdition([string]$Edition,[int]$EngineEdition=0) {
    if(Test-LabDeveloper){return ($Edition -match '^(Enterprise )?Developer Edition' -and $EngineEdition -in @(0,3))}
    $Edition -match '^Standard Edition' -and $EngineEdition -in @(0,2)
}
function Get-TargetProfile([int]$Year) {
    switch($Year){
        2022 {[pscustomobject]@{Year=2022;Major=16;MinimumOsBuild=14393;CuPage='https://www.microsoft.com/en-us/download/details.aspx?id=105013'}}
        2025 {[pscustomobject]@{Year=2025;Major=17;MinimumOsBuild=17763;CuPage='https://www.microsoft.com/en-us/download/details.aspx?id=108788'}}
        default {throw 'Choose target 2022 or 2025.'}
    }
}
function Assert-Os($Os,$Profile) {
    if($Os.ProductType -ne 3 -or [int]$Os.BuildNumber -notin @(14393,17763,20348) -or [int]$Os.BuildNumber -lt $Profile.MinimumOsBuild){
        throw "Unsupported OS for this SQL 2017-source campaign. Target $($Profile.Year) requires a qualified member/standalone Windows Server build >= $($Profile.MinimumOsBuild). Supported source hosts: Server 2016/2019/2022."
    }
}
function Assert-InstanceName([string]$Name) {
    if($Name -notmatch '^[A-Za-z][A-Za-z0-9_]{0,15}$'){throw 'Use a local default or named instance, not a server/network address.'}
}
function Get-LocalStandardInstance {
    $key='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    if(-not(Test-Path $key)){return}
    foreach($entry in (Get-ItemProperty $key).PSObject.Properties|Where-Object Name -NotLike 'PS*'){
        $setup=Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$($entry.Value)\Setup"
        $service=if($entry.Name -eq 'MSSQLSERVER'){'MSSQLSERVER'}else{'MSSQL$'+$entry.Name}
        $status=Get-Service $service -ErrorAction SilentlyContinue
        if((Test-SelectedEdition $setup.Edition) -and $setup.Version -like '14.*' -and $status -and $status.Status -eq 'Running'){
            [pscustomobject]@{Instance=$entry.Name;InstanceId=$entry.Value;Build=$setup.Version;Edition=$setup.Edition}
        }
    }
}
function Select-StandardInstance([string]$Requested) {
    $items=@(Get-LocalStandardInstance)
    if($Requested){Assert-InstanceName $Requested;$items=@($items|Where-Object Instance -EQ $Requested)}
    if($items.Count -eq 0){throw 'No matching running local SQL 2017 Standard instance.'}
    if($items.Count -eq 1){return $items[0].Instance}
    for($i=0;$i -lt $items.Count;$i++){Write-Host "$($i+1): $($items[$i].Instance) | $($items[$i].Build)"}
    $index=0
    if(-not[int]::TryParse((Read-Host 'Instance number'),[ref]$index) -or $index -lt 1 -or $index -gt $items.Count){throw 'Invalid instance selection.'}
    $items[$index-1].Instance
}
function Read-Plan {
    $p=Get-Content -LiteralPath $planPath -Raw|ConvertFrom-Json
    if($p.Schema -ne 1 -or $p.Product -ne 'SqlServerUpgrade' -or $p.Computer -ne $env:COMPUTERNAME -or $p.MachineGuid -ne $machineGuid){throw 'Plan belongs to another product, computer or schema. Express runtime cannot be reused.'}
    $isLab=($p.PSObject.Properties.Name -contains 'LabDeveloper') -and [bool]$p.LabDeveloper
    if($isLab -ne (Test-LabDeveloper)){throw 'Campaign mode mismatch. Use -LabDeveloper only for non-production Developer campaigns.'}
    Assert-InstanceName $p.Instance
    if($p.Instance -ne $InstanceName){throw 'Instance differs from the saved campaign.'}
    $profile=Get-TargetProfile $p.Target.Year
    if($p.Target.Major -ne $profile.Major){throw 'Target profile mismatch.'}
    $p
}
function Assert-Inventory($Inventory,[int]$Major=14) {
    $s=$Inventory.Server
    if($s.Machine -ne $env:COMPUTERNAME -or -not(Test-SelectedEdition $s.Edition $s.EngineEdition) -or ([version]$s.Build).Major -ne $Major){throw "Expected local SQL $Major.x Standard Edition; detected $($s.Edition) $($s.Build)."}
    if($s.IsSysadmin -ne 1){throw 'Windows-authenticated SQL sysadmin access is required.'}
    if($s.Clustered -ne 0 -or $s.Hadr -ne 0 -or (Get-Service ClusSvc -ErrorAction SilentlyContinue)){throw 'Only standalone instances are supported; AG/FCI are blocked.'}
    foreach($db in $Inventory.Databases){
        if($db.State -ne 'ONLINE' -or $db.Encrypted -or $db.Distributor -or $db.Published -or $db.Subscribed -or $db.MergePublished -or $db.SnapshotSource -isnot [DBNull]){throw "Unsupported database state, TDE, replication or snapshot: $($db.Name)."}
    }
}
function Get-Boot {(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')}
function Get-LiveBuild {(Get-Inventory $InstanceName).Server.Build}
function Assert-NoSetup {
    if(Get-Process setup -ErrorAction SilentlyContinue){throw 'SQL Setup is already running. Finish or close it before continuing.'}
}
function Get-AgentInventory {
    # Persist metadata/hashes only. Job command text and credentials are not exported.
    $jobs=@(Invoke-Query $InstanceName 'SELECT job_id AS Id,name AS Name,enabled AS Enabled,CONVERT(varchar(130),owner_sid,1) AS OwnerSid FROM msdb.dbo.sysjobs ORDER BY job_id;')
    $steps=@(Invoke-Query $InstanceName "SELECT job_id AS JobId,step_id AS StepId,CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),CONCAT(subsystem,N'|',command,N'|',database_name,N'|',proxy_id,N'|',on_success_action,N'|',on_fail_action))),2) AS DefinitionHash FROM msdb.dbo.sysjobsteps ORDER BY job_id,step_id;")
    $schedules=@(Invoke-Query $InstanceName 'SELECT schedule_uid AS Id,name AS Name,enabled AS Enabled,freq_type,freq_interval,freq_subday_type,freq_subday_interval,freq_relative_interval,freq_recurrence_factor,active_start_date,active_end_date,active_start_time,active_end_time FROM msdb.dbo.sysschedules ORDER BY schedule_uid;')
    $links=@(Invoke-Query $InstanceName 'SELECT job_id,schedule_id FROM msdb.dbo.sysjobschedules ORDER BY job_id,schedule_id;')
    $operators=@(Invoke-Query $InstanceName "SELECT id AS Id,name AS Name,enabled AS Enabled,CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),CONCAT(email_address,N'|',pager_address))),2) AS AddressHash FROM msdb.dbo.sysoperators ORDER BY id;")
    $proxies=@(Invoke-Query $InstanceName 'SELECT proxy_id AS Id,name AS Name,credential_id AS CredentialId,enabled AS Enabled FROM msdb.dbo.sysproxies ORDER BY proxy_id;')
    $credentials=@(Invoke-Query $InstanceName 'SELECT credential_id AS Id,name AS Name,credential_identity AS IdentityName FROM sys.credentials ORDER BY credential_id;')
    $serviceName=if($InstanceName -eq 'MSSQLSERVER'){'SQLSERVERAGENT'}else{'SQLAgent$'+$InstanceName}
    $service=Get-CimInstance Win32_Service -Filter ("Name='"+$serviceName+"'")
    if(-not$service){throw 'SQL Agent service is missing.'}
    [pscustomobject]@{Jobs=$jobs;Steps=$steps;Schedules=$schedules;JobSchedules=$links;Operators=$operators;Proxies=$proxies;Credentials=$credentials;ServiceName=$serviceName;ServiceAccount=$service.StartName;StartMode=$service.StartMode;WasRunning=($service.State -eq 'Running')}
}
function Assert-AgentUnchanged($Before,$After) {
    foreach($name in @('Jobs','Steps','Schedules','JobSchedules','Operators','Proxies','Credentials','ServiceAccount','StartMode')){
        if(($Before.$name|ConvertTo-Json -Depth 10 -Compress) -ne ($After.$name|ConvertTo-Json -Depth 10 -Compress)){throw "SQL Agent metadata changed: $name. Review before acceptance."}
    }
    if($Before.WasRunning -and -not$After.WasRunning){throw 'SQL Agent was running before upgrade and is now stopped.'}
}
function Initialize-PrivateRuntime {
    # The copied licensed media can contain a PID. Restrict the entire new runtime.
    if(Test-Path $WorkRoot){
        $allowed=@('S-1-5-18','S-1-5-32-544',[Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        foreach($rule in (Get-Acl -LiteralPath $WorkRoot).Access){
            if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin $allowed){throw 'Runtime permissions expose licensed media to other users. Use a new dedicated runtime folder or have its ACL reviewed.'}
        }
        return
    }
    New-Item -ItemType Directory $WorkRoot|Out-Null
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach($id in @('S-1-5-18','S-1-5-32-544')){
        $sid=New-Object Security.Principal.SecurityIdentifier($id)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    }
    Set-Acl -LiteralPath $WorkRoot -AclObject $acl
}

function Get-AgentStepsHash($Steps) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @($Steps) -Depth 10 -Compress))))).Replace('-','') }
    finally {$sha.Dispose()}
}
function Assert-AgentAfterUpgrade($Plan,$After) {
    $beforeHash=Get-AgentStepsHash $Plan.Agent.Steps
    $afterHash=Get-AgentStepsHash $After.Steps
    if($beforeHash -eq $afterHash){Assert-AgentUnchanged $Plan.Agent $After;return}
    $reviewPath=Join-Path $WorkRoot 'agent-step-review.json'
    if(-not(Test-Path $reviewPath)){throw 'SQL Agent job steps changed. Review SQL Agent > Jobs in SSMS and run menu 9 to explicitly approve reviewed step changes; other Agent checks remain strict.'}
    $review=Get-Content $reviewPath -Raw|ConvertFrom-Json
    if($review.PlanId -ne $Plan.Id -or $review.Build -ne $Plan.ApprovedBuild -or $review.BeforeHash -ne $beforeHash -or $review.AfterHash -ne $afterHash -or -not$review.Reason){throw 'Agent step approval does not match this campaign/build/current steps. Review again.'}
    $copy=$After|ConvertTo-Json -Depth 10|ConvertFrom-Json
    $copy.Steps=$Plan.Agent.Steps
    Assert-AgentUnchanged $Plan.Agent $copy
    Write-Host ('Using explicit Agent step approval: '+$review.Reason)
}
