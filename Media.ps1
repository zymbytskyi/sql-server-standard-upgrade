function Assert-StandardMedia([string]$Directory,$Profile) {
    $setup=Join-Path $Directory 'setup.exe';Assert-MicrosoftFile $setup
    if((Get-Item -LiteralPath $setup).VersionInfo.ProductMajorPart -ne $Profile.Major){throw "ISO Setup is not SQL $($Profile.Year)."}
    [xml]$xml=Get-Content -LiteralPath (Join-Path $Directory 'MediaInfo.xml') -Raw
    $layout=@($xml.MediaInfo.Properties.Property|Where-Object Id -eq 'MediaLayout')
    if($layout.Count -ne 1 -or $layout[0].Value -ne 'Full'){throw 'Use full licensed SQL Server media; Express Core media is not supported.'}
    $languages=@(Get-ChildItem -LiteralPath $Directory -Directory -Filter '*_LP'|ForEach-Object {
        [xml]$lang=Get-Content -LiteralPath (Join-Path $_.FullName 'MediaInfo.xml') -Raw
        @($lang.MediaInfo.Properties.Property|Where-Object Id -eq 'Language').Value
    })
    if($languages.Count -ne 1 -or [int]$languages[0] -ne 1033){throw 'This first version supports English source SQL and English target media only.'}
    if(-not(Test-Path -LiteralPath (Join-Path $Directory 'x64\Setup\SQL_ENGINE_CORE_INST.MSI'))){throw 'Missing x64 database engine media.'}
    # Do not read/print/serialize the embedded product key. Setup reads its own media.
    if(-not(Test-Path -LiteralPath (Join-Path $Directory 'x64\DefaultSetup.ini'))){throw 'Expected licensed media DefaultSetup.ini is absent. Obtain your licensed Standard ISO.'}
}
function Stage-Iso($Plan) {
    if($Plan.Prepared){Assert-MediaHashes $Plan;return}
    $iso=[IO.Path]::GetFullPath($Plan.IsoPath)
    if([IO.Path]::GetExtension($iso) -ne '.iso' -or -not(Test-Path -LiteralPath $iso -PathType Leaf)){throw 'Provide an existing SQL Standard ISO path.'}
    if((Get-FileHash -LiteralPath $iso).Hash -ne $Plan.IsoSha256){throw 'ISO changed since target approval. Use a new campaign.'}
    Assert-Disk $WorkRoot ((Get-Item -LiteralPath $iso).Length*2+8GB)
    $media=Join-Path $WorkRoot 'Media'
    if(Test-Path $media){Move-Item -LiteralPath $media -Destination ($media+'.incomplete-'+[guid]::NewGuid().ToString('N'))}
    $mountedHere=$false
    try {
        $disk=Get-DiskImage -ImagePath $iso -ErrorAction Stop
        if(-not$disk.Attached){$disk=Mount-DiskImage -ImagePath $iso -PassThru -ErrorAction Stop;$mountedHere=$true}
        $volumes=@($disk|Get-Volume|Where-Object DriveLetter)
        if($volumes.Count -ne 1){throw 'Cannot determine one ISO drive letter.'}
        $source=$volumes[0].DriveLetter+':\'
        Assert-StandardMedia $source $Plan.Target
        New-Item -ItemType Directory $media|Out-Null
        foreach($item in Get-ChildItem -LiteralPath $source -Force){Copy-Item -LiteralPath $item.FullName -Destination $media -Recurse -Force}
        Assert-StandardMedia $media $Plan.Target
        $Plan.MediaFiles=@(Get-ChildItem -LiteralPath $media -File -Recurse|ForEach-Object {[pscustomobject]@{Path=$_.FullName.Substring($media.Length+1);Sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
        $Plan.Prepared=$true;Save-Json $planPath $Plan
    }finally{if($mountedHere){Dismount-DiskImage -ImagePath $iso|Out-Null}}
}
function Assert-MediaHashes($Plan) {
    $root=Join-Path $WorkRoot 'Media'
    if(-not$Plan.Prepared -or @($Plan.MediaFiles).Count -eq 0){throw 'Media preparation incomplete. Run menu 1.'}
    if(@(Get-ChildItem -LiteralPath $root -File -Recurse).Count -ne @($Plan.MediaFiles).Count){throw 'Staged media file count changed.'}
    foreach($file in $Plan.MediaFiles){
        $path=[IO.Path]::GetFullPath((Join-Path $root $file.Path))
        if(-not$path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $path).Hash -ne $file.Sha256){throw "Staged media changed: $($file.Path)"}
    }
    Assert-StandardMedia $root $Plan.Target
}
function Convert-ServicingCatalog([string]$Html,[int]$Major) {
    $result=@()
    foreach($row in [regex]::Matches($Html,'(?is)<tr\b[^>]*>.*?</tr>')){
        $plain=[Net.WebUtility]::HtmlDecode([regex]::Replace($row.Value,'<[^>]+>',' '))
        if($plain -notmatch '(?i)\bCU\s*\d+\b|Cumulative Update'){continue}
        $build=[regex]::Match($plain,('\b'+$Major+'\.0\.\d+\.\d+\b')).Value
        $kb=[regex]::Match($plain,'(?i)\bKB\d{7}\b').Value.ToUpperInvariant()
        if(-not$kb){$match=[regex]::Match($row.Value,'(?i)\bkb(\d{7})\b');if($match.Success){$kb='KB'+$match.Groups[1].Value}}
        if(-not$build -or -not$kb){continue}
        $links=@([regex]::Matches($row.Value,'(?i)href=["'']([^"'']+)["'']')|ForEach-Object {[Net.WebUtility]::HtmlDecode($_.Groups[1].Value)})
        $url=@($links|Where-Object {$_ -match '(?i)'+$kb.Substring(2)}|Select-Object -First 1)
        $result+=[pscustomobject]@{Build=$build;KB=$kb;Description=([regex]::Replace($plain,'\s+',' ')).Trim();KbUrl=if($url.Count){$url[0]}else{'https://support.microsoft.com/help/'+$kb.Substring(2)}}
    }
    @($result|Group-Object Build|ForEach-Object {$_.Group[0]}|Sort-Object @{Expression={[version]$_.Build};Descending=$true})
}
function Assert-UpdateIdentity([int]$Year,[int]$Major,[string]$Build,[string]$KB,[string]$FileName) {
    $profile=Get-TargetProfile $Year
    if($Major -ne $profile.Major -or $Build -notmatch ('^'+$Major+'\.0\.\d+\.\d+$') -or ([version]$Build).Build -lt 4000 -or $KB -notmatch '^KB\d{7}$' -or $FileName -ne "SQLServer$Year-$KB-x64.exe"){throw 'Update metadata is not a matching CU-branch target.'}
}
function Assert-DownloadUri([string]$Url,[string]$FileName) {
    $uri=[uri]$Url
    if(-not$uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'download.microsoft.com' -or [IO.Path]::GetFileName($uri.AbsolutePath) -ne $FileName){throw 'Expected exact selected KB x64 EXE on HTTPS download.microsoft.com.'}
}
function Get-UpdatePackageUrl($Target,$Profile) {
    $kbUri=[uri]::new([uri]'https://support.microsoft.com',$Target.KbUrl)
    if($kbUri.Scheme -ne 'https' -or $kbUri.Host -notin @('support.microsoft.com','learn.microsoft.com')){throw 'Unexpected KB source.'}
    $file="SQLServer$($Profile.Year)-$($Target.KB)-x64.exe"
    foreach($page in @($kbUri.AbsoluteUri,$Profile.CuPage)){
        try{
            $html=[Net.WebUtility]::HtmlDecode((Invoke-WebRequest $page -UseBasicParsing).Content)
            $match=[regex]::Match($html,('https://download\.microsoft\.com/[^"''\s<>]+/'+[regex]::Escape($file)),'IgnoreCase')
            if($match.Success){Assert-DownloadUri $match.Value $file;return $match.Value}
        }catch{Write-Host 'Could not resolve the selected package from this Microsoft page.'}
    }
    $url=Read-Host "Paste the official download.microsoft.com EXE URL for $($Target.KB) (from its Microsoft KB page)"
    Assert-DownloadUri $url $file;$url
}
function Prepare-Update($Plan) {
    $path=Join-Path $WorkRoot 'update.json'
    if(Test-Path $path){$null=Assert-PreparedUpdate $Plan;Write-Host 'Pinned update reused; no target refresh.';return}
    $catalog='https://support.microsoft.com/en-us/servicing/sql/kb321185-download-and-install-latest-updates'
    $rows=@(Convert-ServicingCatalog (Invoke-WebRequest $catalog -UseBasicParsing).Content $Plan.Target.Major)
    if(-not$rows.Count){throw 'Microsoft catalog is unreadable/unsupported. No RTM fallback; retry preparation when metadata is available.'}
    $target=$rows[0];$file="SQLServer$($Plan.Target.Year)-$($target.KB)-x64.exe"
    Assert-UpdateIdentity $Plan.Target.Year $Plan.Target.Major $target.Build $target.KB $file
    Write-Host "Proposed target: $($target.KB) | $($target.Build) | $($target.Description)"
    Write-Host "Review Microsoft KB prerequisites, known issues and vendor support: $($target.KbUrl)"
    if((Read-Host 'Type APPROVE to pin this CU-branch target for integration') -cne 'APPROVE'){throw 'Update target not approved.'}
    $url=Get-UpdatePackageUrl $target $Plan.Target
    $dir=Join-Path $WorkRoot ('Updates\'+$target.KB+'-'+$target.Build);New-Item -ItemType Directory $dir -Force|Out-Null
    Assert-Disk $WorkRoot 8GB
    $package=Join-Path $dir $file
    if(-not(Test-Path $package)){
        $partial=Join-Path $WorkRoot ($file+'.partial-'+[guid]::NewGuid().ToString('N'))
        $curl=Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue
        if($curl){Invoke-CurlMediaDownload $curl.Source $url $partial}else{Invoke-WebRequest $url -OutFile $partial -UseBasicParsing}
        Assert-MicrosoftFile $partial
        Move-Item -LiteralPath $partial -Destination $package
    }
    Assert-MicrosoftFile $package
    $v=(Get-Item $package).VersionInfo
    $actual='{0}.{1}.{2}.{3}' -f $v.ProductMajorPart,$v.ProductMinorPart,$v.ProductBuildPart,$v.ProductPrivatePart
    if($actual -ne $target.Build){throw 'Update package build differs from selected target.'}
    $hash=(Get-FileHash -LiteralPath $package).Hash
    $published=Read-Host 'Microsoft-published SHA256 if available (Enter if not published)'
    if($published -and ($published -notmatch '^[A-Fa-f0-9]{64}$' -or $published -ne $hash)){throw 'Published SHA256 mismatch.'}
    Save-Json $path @{PlanId=$Plan.Id;Year=$Plan.Target.Year;Major=$Plan.Target.Major;KB=$target.KB;Build=$target.Build;PackagePath=$package;Sha256=$hash;PublishedHashChecked=[bool]$published;Source=$url;Catalog=$catalog;PreparedUtc=[datetime]::UtcNow.ToString('o')}
    $null=Assert-PreparedUpdate $Plan
}
function Assert-PreparedUpdate($Plan) {
    $u=Get-Content (Join-Path $WorkRoot 'update.json') -Raw|ConvertFrom-Json
    if($u.PlanId -ne $Plan.Id -or $u.Year -ne $Plan.Target.Year -or $u.Major -ne $Plan.Target.Major){throw 'Update belongs to another target/campaign.'}
    $file="SQLServer$($u.Year)-$($u.KB)-x64.exe"
    Assert-UpdateIdentity $u.Year $u.Major $u.Build $u.KB $file
    $dir=Join-Path $WorkRoot ('Updates\'+$u.KB+'-'+$u.Build);$expected=Join-Path $dir $file
    if($u.PackagePath -ne $expected -or @(Get-ChildItem -LiteralPath $dir -Recurse -File).Count -ne 1){throw 'Keep only the pinned update in its dedicated source folder.'}
    if((Get-FileHash -LiteralPath $expected).Hash -ne $u.Sha256){throw 'Pinned update hash mismatch.'}
    Assert-MicrosoftFile $expected
    $v=(Get-Item -LiteralPath $expected).VersionInfo
    if(('{0}.{1}.{2}.{3}' -f $v.ProductMajorPart,$v.ProductMinorPart,$v.ProductBuildPart,$v.ProductPrivatePart) -ne $u.Build){throw 'Pinned update version mismatch.'}
    $u
}
