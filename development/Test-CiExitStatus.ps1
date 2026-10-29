param([string[]]$SuiteNames=@('Test-BehaviorParity.ps1'))
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot ('test-results\ci-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $root -Force|Out-Null
function Quote-PowerShellLiteral([string]$Value){return "'"+$Value.Replace("'","''")+"'"}
function Invoke-RunnerStep([string]$Suite,[string]$Name){
    $marker=Join-Path $root ($Name+'.continued')
    $wrapper=Join-Path $root ($Name+'.ps1')
    # Match actions/runner ScriptHandlerHelpers.FixUpScriptContents: the
    # PowerShell step is dot-sourced, and its final native exit code is forwarded.
    $contents=@(
        '$ErrorActionPreference = ''stop''',
        ('& '+(Quote-PowerShellLiteral $Suite)),
        ('[IO.File]::WriteAllText('+(Quote-PowerShellLiteral $marker)+',''continued'')'),
        'if ((Test-Path -LiteralPath variable:\LASTEXITCODE)) { exit $LASTEXITCODE }'
    ) -join "`r`n"
    [IO.File]::WriteAllText($wrapper,$contents,[Text.UTF8Encoding]::new($false))
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ". '+(Quote-PowerShellLiteral $wrapper)+'"'
    $info.WorkingDirectory=$project;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    # Let Windows PowerShell discover its own built-in modules when this
    # harness is launched from PowerShell 7 rather than inheriting its paths.
    $info.EnvironmentVariables.Remove('PSModulePath')
    $process=New-Object Diagnostics.Process;$process.StartInfo=$info
    try{
        if(-not$process.Start()){throw 'Could not start the CI exit-status check'}
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not$process.WaitForExit(300000)){
            # Only terminate this owned fixture process tree if a test hangs.
            $kill=New-Object Diagnostics.ProcessStartInfo
            $kill.FileName=Join-Path $env:WINDIR 'System32\taskkill.exe';$kill.Arguments='/PID '+$process.Id+' /T /F'
            $kill.UseShellExecute=$false;$kill.CreateNoWindow=$true
            $stop=[Diagnostics.Process]::Start($kill);try{$stop.WaitForExit()}finally{$stop.Dispose()}
            throw ('Timed out running '+$Suite)
        }
        $text=$stdout.Result;$errors=$stderr.Result
        [IO.File]::WriteAllText((Join-Path $root ($Name+'.stdout.txt')),$text)
        [IO.File]::WriteAllText((Join-Path $root ($Name+'.stderr.txt')),$errors)
        return [pscustomobject]@{Code=$process.ExitCode;Continued=(Test-Path -LiteralPath $marker);Output=$text;Errors=$errors}
    }finally{$process.Dispose()}
}
if(-not$SuiteNames.Count){throw 'Choose at least one test suite'}
foreach($name in $SuiteNames){
    if($name-notmatch'^Test-[A-Za-z0-9]+\.ps1$'-or$name-eq'Test-CiExitStatus.ps1'){throw 'Choose a nonrecursive development test script'}
    $path=Join-Path $PSScriptRoot $name
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('Test suite missing: '+$name)}
    Write-Host ('Checking GitHub-style exit status: '+$name)
    $result=Invoke-RunnerStep $path ([IO.Path]::GetFileNameWithoutExtension($name))
    Write-Output $result.Output.TrimEnd()
    if($result.Code-ne0-or-not$result.Continued){throw ($name+' passed-runner check failed: exit '+$result.Code+'. '+$result.Errors)}
    'PASS: '+$name+' returns success to the GitHub runner and allows the next command to run.'
}
# Exercise an actual assertion in an isolated copy. No converters or real
# settings are needed: an invalid corpus is rejected before fixture creation.
$bad=Join-Path $root 'invalid\development';New-Item -ItemType Directory -Path (Join-Path $bad 'contracts') -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Test-BehaviorParity.ps1') -Destination $bad
[IO.File]::WriteAllText((Join-Path $bad 'contracts\behavior-v1.json'),'{"schemaVersion":999}')
$rejected=Invoke-RunnerStep (Join-Path $bad 'Test-BehaviorParity.ps1') 'assertion-failure'
if($rejected.Code-eq0-or$rejected.Continued-or$rejected.Errors-notmatch'Unsupported behavior corpus'){throw 'The runner check masked a real test assertion failure'}
'PASS: a real corpus assertion still fails the runner step and prevents the following command.'
$global:LASTEXITCODE=0
