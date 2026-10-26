# Shared SQL helpers adapted from the local Express tool. No entry point or mutations on import.
function Save-Json($Path, $Value) {
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$Path.tmp" -Encoding UTF8
    Move-Item -LiteralPath "$Path.tmp" -Destination $Path -Force
}
function Invoke-Query([string]$Instance, [string]$Sql) {
    $server = if ($Instance -eq 'MSSQLSERVER') { 'lpc:.' } else { "lpc:.\$Instance" }
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source']=$server; $builder['Initial Catalog']='master'; $builder['Integrated Security']=$true; $builder['Connect Timeout']=15
    $builder['Asynchronous Processing']=$true
    $connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
    try {
        $connection.Open()
        $command=$connection.CreateCommand(); $command.CommandText=$Sql; $command.CommandTimeout=1800
        $table=New-Object System.Data.DataTable
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $pending=$command.BeginExecuteReader()
        $last=-1
        while(-not$pending.IsCompleted){
            Start-Sleep -Milliseconds 500
            $seconds=[int]$timer.Elapsed.TotalSeconds
            if($seconds -ge $last+10){Write-Host "SQL operation in progress on $Instance | elapsed $($timer.Elapsed.ToString('hh\:mm\:ss'))";$last=$seconds}
        }
        $reader=$command.EndExecuteReader($pending)
        try { $table.Load($reader) } finally { $reader.Dispose() }
        foreach ($row in $table.Rows) {
            $record=[ordered]@{}
            foreach ($column in $table.Columns) { $record[$column.ColumnName]=$row[$column] }
            [pscustomobject]$record
        }
    } finally { $connection.Dispose() }
}
function Quote-Sql([string]$Value) { "N'"+$Value.Replace("'","''")+"'" }
function Quote-Name([string]$Value) { '['+$Value.Replace(']',']]')+']' }
function Assert-MicrosoftFile([string]$Path) {
    $signature=Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|, )O=Microsoft Corporation(,|$)') {
        throw "Invalid Microsoft Authenticode signature: $Path"
    }
}
function Get-Inventory([string]$Instance) {
    $server=@(Invoke-Query $Instance @"
SELECT CONVERT(nvarchar(128),SERVERPROPERTY('MachineName')) AS [Machine],
 CONVERT(nvarchar(128),SERVERPROPERTY('Edition')) AS [Edition],
 CONVERT(nvarchar(32),SERVERPROPERTY('ProductVersion')) AS [Build],
 CONVERT(int,SERVERPROPERTY('EngineEdition')) AS [EngineEdition],
 CONVERT(int,SERVERPROPERTY('IsClustered')) AS [Clustered],
 CONVERT(int,SERVERPROPERTY('IsHadrEnabled')) AS [Hadr],
 IS_SRVROLEMEMBER('sysadmin') AS [IsSysadmin];
"@)[0]
    $databases=@(Invoke-Query $Instance @"
SELECT d.name AS [Name],d.state_desc AS [State],d.compatibility_level AS [Compatibility],
 d.is_read_only AS [ReadOnly],d.is_encrypted AS [Encrypted],d.source_database_id AS [SnapshotSource],
 d.is_distributor AS [Distributor],d.is_published AS [Published],d.is_subscribed AS [Subscribed],d.is_merge_published AS [MergePublished],
 CONVERT(bigint,SUM(CONVERT(bigint,f.size))*8192) AS [Bytes],
 CONVERT(bigint,SUM(CASE WHEN f.type=0 THEN CONVERT(bigint,f.size) ELSE 0 END)*8192) AS [DataBytes]
FROM sys.databases d JOIN sys.master_files f ON d.database_id=f.database_id
WHERE d.database_id<>2 GROUP BY d.name,d.state_desc,d.compatibility_level,d.is_read_only,
 d.is_encrypted,d.source_database_id,d.is_distributor,d.is_published,d.is_subscribed,d.is_merge_published;
"@)
    [pscustomobject]@{Server=$server; Databases=$databases}
}
function Assert-Disk([string]$Directory,[long]$Required) {
    if ($Directory -notmatch '^[A-Za-z]:\\') { throw "Only local drive paths are supported: $Directory" }
    $volume=Get-Volume -FilePath $Directory -ErrorAction Stop
    if ($volume.FileSystemType -notin @('NTFS','ReFS') -or $volume.SizeRemaining -lt $Required) { throw "Insufficient/unsupported disk at $Directory; need $([math]::Ceiling($Required/1GB)) GiB free." }
}
