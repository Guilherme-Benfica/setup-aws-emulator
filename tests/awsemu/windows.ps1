# End-to-end test of awsemu on Windows. Run it from the repository root.
$ErrorActionPreference = 'Stop'

function Check($what) { if ($LASTEXITCODE -ne 0) { throw "$what failed with exit code $LASTEXITCODE" } }

$env:AWSEMU_SOURCE = (Get-Location).Path
& ./install.ps1
$env:PATH = (Join-Path $env:USERPROFILE '.awsemu\app\bin') + ';' + $env:PATH

# Windows 11 blocks .ps1 scripts by default. awsemu must still work from PowerShell,
# so PowerShell has to resolve it to awsemu.cmd, never to a .ps1 on PATH.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Restricted -Force

# Real-looking credentials in the shell must not leak into emulator calls.
$env:AWS_ACCESS_KEY_ID = 'AKIAFAKEFAKEFAKEFAKE'
$env:AWS_SECRET_ACCESS_KEY = 'fake'
$env:AWS_PROFILE = 'real'

awsemu up; Check 'awsemu up'
$out = awsemu up | Out-String; Check 'second awsemu up'
if ($out -notmatch 'already running') { throw "second awsemu up should say 'already running', got: $out" }

awsemu env --shell pwsh | Out-String | Invoke-Expression
$account = (aws sts get-caller-identity --query Account --output text | Out-String).Trim(); Check 'sts'
if ($account -ne '000000000000') { throw "expected account 000000000000, got $account" }
aws s3 mb s3://awsemu-test; Check 's3 mb'
awsemu status; Check 'awsemu status'

awsemu up --port 9400 | Out-Null; Check 'awsemu up --port 9400'
awsemu env --port 9400 --shell pwsh | Out-String | Invoke-Expression
if ($env:AWS_ENDPOINT_URL -ne 'https://127.0.0.1:9400') { throw "wrong endpoint $env:AWS_ENDPOINT_URL" }
aws s3 ls | Out-Null; Check 's3 ls on 9400'
awsemu down --port 9400; Check 'awsemu down --port 9400'

awsemu down; Check 'awsemu down'

awsemu status
if ($LASTEXITCODE -eq 0) { throw 'awsemu status should fail after awsemu down' }
Write-Output 'awsemu Windows test passed'
exit 0
