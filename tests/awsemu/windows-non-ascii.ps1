# awsemu with a non-ASCII profile path. Run after windows.ps1 installed awsemu.
$ErrorActionPreference = 'Stop'
function Check($what) { if ($LASTEXITCODE -ne 0) { throw "$what failed with exit code $LASTEXITCODE" } }
$env:PATH = (Join-Path $env:USERPROFILE '.awsemu\app\bin') + ';' + $env:PATH
# A profile path with non-ASCII characters (common on pt-BR machines) must survive the
# round trip between Windows and WSL.
$realProfile = $env:USERPROFILE
$env:USERPROFILE = Join-Path $env:RUNNER_TEMP 'perfil-João'
New-Item -ItemType Directory -Force $env:USERPROFILE | Out-Null
awsemu up --port 9500; Check 'awsemu up with a non-ASCII profile'
awsemu env --port 9500 | Out-String | Invoke-Expression
$account = (aws sts get-caller-identity --query Account --output text | Out-String).Trim(); Check 'sts with a non-ASCII profile'
if ($account -ne '000000000000') { throw "expected account 000000000000 with a non-ASCII profile, got $account" }
awsemu down --port 9500; Check 'awsemu down --port 9500'
$env:USERPROFILE = $realProfile
Write-Output 'awsemu non-ASCII profile test passed'
exit 0
