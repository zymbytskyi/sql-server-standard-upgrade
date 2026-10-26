function Invoke-CurlMediaDownload([string]$Executable,[string]$Uri,[string]$Destination) {
    # Windows PowerShell hosts may promote native stderr into terminating errors.
    # Keep stderr out of the PowerShell pipeline; use the real process exit code.
    if($Uri.Contains('"') -or $Destination.Contains('"')){throw 'Invalid download argument.'}
    $log=$Destination+'.curl-'+[guid]::NewGuid().ToString('N')+'.log'
    $arguments=@('--fail','--location','--silent','--show-error','--retry','2','--connect-timeout','30','--max-time','1800','--continue-at','-','--output',('"{0}"' -f $Destination),('"{0}"' -f $Uri))
    $process=Start-Process -FilePath $Executable -ArgumentList $arguments -RedirectStandardError $log -WindowStyle Hidden -PassThru -Wait
    if($process.ExitCode -ne 0){
        $details=if(Test-Path -LiteralPath $log){(Get-Content -LiteralPath $log -Tail 12) -join ' '}else{'No stderr captured.'}
        throw "curl download failed (exit $($process.ExitCode)): $details | Diagnostic file: $log"
    }
    if(-not(Test-Path -LiteralPath $Destination -PathType Leaf) -or (Get-Item -LiteralPath $Destination).Length -eq 0){throw "curl exited successfully but produced no media. Diagnostic file: $log"}
}
