param([switch]$RequireLinkTest)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Workflow-Support.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Run-Control.ps1')
$root=Join-Path $PSScriptRoot ('test-results\cleanup-'+[guid]::NewGuid().ToString('N').Substring(0,10))
$work=Join-Path $root 'w';$output=Join-Path $root 'out'
New-Item -ItemType Directory -Path $work,$output -Force|Out-Null
$config=[pscustomobject]@{AutoCleanup=$false;SuccessRetentionDays=7;FailureRetentionDays=30}
function Log($Text){Write-Host $Text}
function Require($Condition,$Message){if(-not$Condition){throw $Message}}
$book=Join-Path $output 'published.epub';[IO.File]::WriteAllText($book,'verified published book')
$receipt=@([pscustomobject]@{Path=$book;Hash=(Get-FileHash -LiteralPath $book).Hash})
function New-Attempt([char]$Key,$Result){
    $job=Join-Path $work (([string]$Key)*64);$attempt=Join-Path $job ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $attempt 'images') -Force|Out-Null
    [IO.File]::WriteAllText((Join-Path $attempt 'book.epub'),'temporary output')
    [IO.File]::WriteAllText((Join-Path $attempt 'images\page.png'),'temporary expanded page')
    [IO.File]::WriteAllText((Join-Path $attempt 'kcc.log'),'retained converter log')
    [IO.File]::WriteAllText((Join-Path $attempt 'images\djxl.log'),'retained decoder log')
    if($null-ne$Result){[IO.File]::WriteAllText((Join-Path $attempt 'result.json'),($Result|ConvertTo-Json -Depth 8))}
    return $attempt
}
$fresh=New-Attempt 'A' @{Succeeded=$true;Outputs=$receipt}
$legacy=New-Attempt 'B' @{Succeeded=$true}
$legacyReceipt=Join-Path (Split-Path $legacy -Parent) 'receipt.json';ConvertTo-Json -InputObject $receipt|Set-Content -LiteralPath $legacyReceipt -Encoding utf8
$group=New-Attempt 'C' @{Succeeded=$true}
$ledger=Join-Path $work 'chapter-receipts.json';$entries=@{};$entries[('C'*64)]=$receipt
@{Version=1;Entries=$entries}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ledger -Encoding utf8
$missing=New-Attempt 'D' @{Succeeded=$true;Outputs=@(@{Path=(Join-Path $output 'missing.epub');Hash=('1'*64)})}
$changed=New-Attempt 'E' @{Succeeded=$true;Outputs=@(@{Path=$book;Hash=('2'*64)})}
$failed=New-Attempt 'F' @{Succeeded=$false}
$stopped=New-Attempt '0' $null
$invalid=New-Attempt '1' @{Succeeded='true';Outputs=$receipt}
$unrelated=Join-Path $work 'manual-files';New-Item -ItemType Directory -Path $unrelated|Out-Null;[IO.File]::WriteAllText((Join-Path $unrelated 'keep.txt'),'keep unrelated work')
$ledgerHash=(Get-FileHash -LiteralPath $ledger).Hash;$receiptHash=(Get-FileHash -LiteralPath $legacyReceipt).Hash
Remove-ExpiredAttempts
foreach($attempt in @($fresh,$legacy,$group)){
    Require (-not(Test-Path -LiteralPath (Join-Path $attempt 'book.epub'))-and-not(Test-Path -LiteralPath (Join-Path $attempt 'images\page.png'))) 'Completed scratch files remained with optional diagnostic expiry off'
    Require ((Test-Path -LiteralPath (Join-Path $attempt 'kcc.log'))-and(Test-Path -LiteralPath (Join-Path $attempt 'images\djxl.log'))-and(Get-Content -LiteralPath (Join-Path $attempt 'result.json') -Raw|ConvertFrom-Json).ScratchCleaned) 'Successful logs or compact completion marker were lost'
}
foreach($attempt in @($missing,$changed,$failed,$stopped,$invalid)){
    Require (Test-Path -LiteralPath (Join-Path $attempt 'book.epub')) 'Unverified, failed, stopped or malformed work was removed'
}
Require ((Get-FileHash -LiteralPath $book).Hash-eq$receipt[0].Hash-and(Get-FileHash -LiteralPath $ledger).Hash-eq$ledgerHash-and(Get-FileHash -LiteralPath $legacyReceipt).Hash-eq$receiptHash-and(Test-Path -LiteralPath (Join-Path $unrelated 'keep.txt'))) 'Published output, receipts or unrelated files changed'
$marker=Join-Path $fresh 'result.json';$markerHash=(Get-FileHash -LiteralPath $marker).Hash;Remove-ExpiredAttempts
Require ((Get-FileHash -LiteralPath $marker).Hash-eq$markerHash) 'Repeated cleanup rewrote already-cleaned completion records'
'PASS: completed single-book and legacy bundle scratch clears immediately with diagnostic expiry disabled; logs, exact receipts, published books, failed/stopped work and unverifiable attempts are retained.'

$outside=Join-Path $root 'outside';New-Item -ItemType Directory -Path $outside|Out-Null;[IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'keep outside')
$linked=New-Attempt '2' @{Succeeded=$true;Outputs=$receipt};$link=Join-Path $linked 'linked'
try{
    $created=$false
    try{New-Item -ItemType Junction -Path $link -Target $outside|Out-Null;$created=$true}catch{if($RequireLinkTest){throw};'SKIP: junction creation is unavailable in this test environment.'}
    if($created){
        Clear-CompletedAttempt $linked
        Require ((Test-Path -LiteralPath (Join-Path $linked 'book.epub'))-and(Test-Path -LiteralPath (Join-Path $outside 'keep.txt'))) 'Cleanup followed a junction or partly cleared an unsafe tree'
        'PASS: cleanup rejects an entire attempt containing a junction.'
    }
}finally{
    if(Test-Path -LiteralPath $link){if(-not((Get-Item -LiteralPath $link -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Unexpected junction fixture'};[IO.Directory]::Delete($link)}
}
Clear-CompletedAttempt $outside
Require (Test-Path -LiteralPath (Join-Path $outside 'keep.txt')) 'Cleanup accepted a path outside Working'
'PASS: cleanup rejects paths outside its hash/GUID layout.'

$config.AutoCleanup=$true
foreach($attempt in @($fresh,$failed,$stopped,$missing,$changed)){
    [IO.Directory]::SetLastWriteTimeUtc($attempt,[DateTime]::UtcNow.AddDays(-40))
}
Remove-ExpiredAttempts
Require (-not(Test-Path -LiteralPath $fresh)-and-not(Test-Path -LiteralPath $failed)-and-not(Test-Path -LiteralPath $stopped)-and(Test-Path -LiteralPath $missing)-and(Test-Path -LiteralPath $changed)) 'Diagnostic expiry removed a last temporary copy or failed to expire selected old diagnostics'
Require ((Get-FileHash -LiteralPath $book).Hash-eq$receipt[0].Hash-and(Get-FileHash -LiteralPath $ledger).Hash-eq$ledgerHash) 'Diagnostic expiry changed output or bundle receipts'
'PASS: opt-in expiry removes old successful logs and failed/stopped attempts while preserving completion receipts and successful scratch whose output is missing or changed.'
