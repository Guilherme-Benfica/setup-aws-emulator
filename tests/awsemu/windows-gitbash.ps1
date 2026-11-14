# awsemu from Git Bash on Windows. Run after windows.ps1 installed awsemu.
$ErrorActionPreference = 'Stop'
function Check($what) { if ($LASTEXITCODE -ne 0) { throw "$what failed with exit code $LASTEXITCODE" } }
$env:PATH = (Join-Path $env:USERPROFILE '.awsemu\app\bin') + ';' + $env:PATH
awsemu up --port 9600; Check 'awsemu up --port 9600'
# In Git Bash, awsemu must use the Windows implementation, not the Linux script.
$gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
$binUnix = (& $gitBash -c "cygpath -u '$(Join-Path $env:USERPROFILE '.awsemu\app\bin')'" | Out-String).Trim()
$status = & $gitBash -lc "export PATH='$binUnix':`$PATH; awsemu status --port 9600" | Out-String; Check 'awsemu status from Git Bash'
Write-Output $status
if ($status -notmatch 'Account: 000000000000') { throw "awsemu status from Git Bash did not reach the emulator: $status" }

awsemu down --port 9600; Check 'awsemu down --port 9600'
Write-Output 'awsemu Git Bash test passed'
exit 0
