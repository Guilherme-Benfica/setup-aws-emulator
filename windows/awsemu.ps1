# awsemu for Windows: runs AWS Emulator in WSL and points PowerShell at it.
# Same commands as the Linux awsemu. Always started through bin\awsemu.cmd in a new
# PowerShell process, which bypasses the default script policy for this one script and
# keeps its variable changes out of the caller's session. This file is deliberately not
# on PATH: PowerShell would run it directly instead of awsemu.cmd.
$ErrorActionPreference = 'Continue'

# wsl.exe writes UTF-8; read it as UTF-8 so paths like C:\Users\João survive.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$AppDir = Split-Path -Parent $PSScriptRoot
$Scripts = Join-Path $AppDir 'scripts'
$CredentialVars = @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN', 'AWS_PROFILE',
  'AWS_DEFAULT_PROFILE', 'AWS_WEB_IDENTITY_TOKEN_FILE', 'AWS_ROLE_ARN', 'AWS_ROLE_SESSION_NAME',
  'AWS_CONTAINER_CREDENTIALS_RELATIVE_URI', 'AWS_CONTAINER_CREDENTIALS_FULL_URI', 'AWS_CONTAINER_AUTHORIZATION_TOKEN')

function Show-Usage {
  @'
Usage: awsemu <command> [options]

Commands:
  up       Install AWS Emulator in WSL if needed, start it and run init steps
  env      Print the variables that point the AWS CLI and SDKs at it
           PowerShell: awsemu env | Out-String | Invoke-Expression
  status   Show whether it is running
  logs     Show its log (-f to follow)
  down     Stop it and delete its files

Options:
  --port N          Port (default 9297)
  --region R        Region for the SDKs (default us-east-1, up only)
  --init PATH       .ps1 file or Terraform directory to run after up (repeatable)
  --telemetry on    Turn emulator telemetry on (default off)
  --shell pwsh|bash Output format for env (default pwsh)
'@
}

function Fail($message) { [Console]::Error.WriteLine("awsemu: $message"); exit 1 }

$Command = if ($args.Count -gt 0) { $args[0] } else { '' }
$Port = '9297'; $Region = 'us-east-1'; $Telemetry = 'off'; $Shell = 'pwsh'; $Follow = $false
$Inits = @()
for ($i = 1; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    '--port' { $Port = $args[++$i] }
    '--region' { $Region = $args[++$i] }
    '--init' { $Inits += $args[++$i] }
    '--telemetry' { $Telemetry = $args[++$i] }
    '--shell' { $Shell = $args[++$i] }
    '-f' { $Follow = $true }
    default { Show-Usage; Fail "unknown option $($args[$i])" }
  }
}

$State = Join-Path $env:USERPROFILE ".awsemu\$Port"
$EmulatorDir = Join-Path $env:USERPROFILE ".aws\emulator\$Port"
$Ca = Join-Path $EmulatorDir 'ca.pem'
$EnvFile = Join-Path $State 'env'
$LogFile = Join-Path $State 'emulator.log'
$PidFile = Join-Path $State 'pid'

# Values the WSL scripts read. /p makes WSL translate the Windows paths itself.
$env:EMULATOR_PORT = $Port
$env:EMULATOR_REGION = $Region
$env:EMULATOR_TELEMETRY = $Telemetry
$env:AWSEMU_LOG = $LogFile
$env:WSLENV = 'USERPROFILE/p:AWSEMU_LOG/p:EMULATOR_PORT:EMULATOR_REGION:EMULATOR_TELEMETRY'

# Runs scripts\<name> in WSL from the scripts folder (wsl --cd translates the path).
function Invoke-WslScript($name) { & wsl.exe --cd $Scripts --exec bash $name }

function Test-Healthy {
  if (-not (Test-Path $Ca)) { return $false }
  Invoke-WslScript health.sh | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Assert-Wsl {
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { Fail 'WSL is not installed. Install it with: wsl --install -d Ubuntu-24.04' }
  & wsl.exe --exec true
  if ($LASTEXITCODE -ne 0) { Fail 'WSL has no Linux distribution. Install one with: wsl --install -d Ubuntu-24.04' }
}

function Read-Pairs {
  Get-Content -Encoding UTF8 $EnvFile | Where-Object { $_ -match '=' } | ForEach-Object {
    $key, $value = $_ -split '=', 2
    [pscustomobject]@{ Key = $key; Value = $value }
  }
}

# Sets the emulator variables in this process and removes real credentials.
function Use-EmulatorEnv {
  foreach ($name in $CredentialVars) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
  foreach ($pair in Read-Pairs) { Set-Item "Env:$($pair.Key)" $pair.Value }
}

function New-JavaTrustStore {
  $keytool = Get-Command keytool -ErrorAction SilentlyContinue
  if (-not $keytool) { return $null }
  $javaHome = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { Split-Path -Parent (Split-Path -Parent $keytool.Source) }
  $cacerts = Join-Path $javaHome 'lib\security\cacerts'
  $store = Join-Path $State 'truststore.p12'
  Remove-Item $store -ErrorAction SilentlyContinue
  if (Test-Path $cacerts) {
    & $keytool.Source -importkeystore -noprompt -srckeystore $cacerts -srcstorepass changeit -destkeystore $store -deststoretype PKCS12 -deststorepass changeit 2>$null | Out-Null
  }
  & $keytool.Source -importcert -noprompt -alias aws-emulator -file $Ca -keystore $store -storetype PKCS12 -storepass changeit 2>$null | Out-Null
  return "-Djavax.net.ssl.trustStore=$store -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12"
}

switch ($Command) {
  'up' {
    Assert-Wsl
    New-Item -ItemType Directory -Force $State | Out-Null

    Invoke-WslScript install.sh
    if ($LASTEXITCODE -ne 0) { Fail 'installing AWS Emulator in WSL failed' }

    if (Test-Healthy) {
      Write-Output "AWS Emulator is already running at https://127.0.0.1:$Port"
    } else {
      # The emulator writes its config, keys and certificate under the Windows profile, so
      # Windows programs can read them. This wsl.exe stays open while the emulator runs:
      # WSL 2 shuts a distribution down once no wsl.exe is attached.
      $process = Start-Process wsl.exe -ArgumentList "--cd `"$Scripts`" --exec bash wsl-run.sh" -WindowStyle Hidden -PassThru
      Set-Content $PidFile $process.Id
      $ready = $false
      for ($t = 0; $t -lt 60; $t++) {
        if (Test-Healthy) { $ready = $true; break }
        if ($process.HasExited) { break }
        Start-Sleep -Seconds 1
      }
      if (-not $ready) {
        if (Test-Path $LogFile) { Get-Content $LogFile }
        Fail 'AWS Emulator did not start'
      }
      Write-Output "AWS Emulator is healthy at https://127.0.0.1:$Port"
    }

    $pairs = @(Invoke-WslScript env.sh)
    if ($LASTEXITCODE -ne 0) { Fail 'reading the emulator settings failed' }
    $pairs += "NODE_EXTRA_CA_CERTS=$Ca"
    $javaOpts = New-JavaTrustStore
    if ($javaOpts) { $pairs += "AWS_EMULATOR_JAVA_OPTS=$javaOpts" }
    Set-Content -Encoding UTF8 $EnvFile $pairs

    if ($Inits.Count -gt 0) {
      Use-EmulatorEnv
      foreach ($path in $Inits) {
        if ((Test-Path $path -PathType Leaf) -and $path.EndsWith('.ps1')) {
          Write-Output "init: $path"
          & powershell -NoProfile -ExecutionPolicy Bypass -File $path
          if ($LASTEXITCODE -ne 0) { Get-Content $LogFile -Tail 50; Fail "init script $path failed" }
        } elseif ((Test-Path $path -PathType Container) -and (Get-ChildItem $path -Filter *.tf)) {
          if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { Fail "init: $path is a Terraform directory. Install Terraform first." }
          Write-Output "init: terraform apply in $path"
          & terraform "-chdir=$path" init -input=false
          if ($LASTEXITCODE -eq 0) { & terraform "-chdir=$path" apply -input=false -auto-approve }
          if ($LASTEXITCODE -ne 0) { Get-Content $LogFile -Tail 50; Fail "terraform failed in $path" }
        } else {
          Fail "on Windows, init accepts .ps1 files or Terraform directories, got: $path"
        }
      }
    }

    $portFlag = if ($Port -ne '9297') { " --port $Port" } else { '' }
    Write-Output ''
    Write-Output 'Point this PowerShell at the emulator with:'
    Write-Output "  awsemu env$portFlag | Out-String | Invoke-Expression"
  }
  'env' {
    if (-not (Test-Healthy) -or -not (Test-Path $EnvFile)) { Fail "no emulator on port $Port, run awsemu up" }
    if ($Shell -eq 'bash') {
      Write-Output "unset $($CredentialVars -join ' ')"
      foreach ($pair in Read-Pairs) { Write-Output ("export {0}='{1}'" -f $pair.Key, ($pair.Value -replace "'", "'\''")) }
    } else {
      Write-Output ('Remove-Item ' + (($CredentialVars | ForEach-Object { "Env:$_" }) -join ', ') + ' -ErrorAction SilentlyContinue')
      foreach ($pair in Read-Pairs) { Write-Output ("`$env:{0} = '{1}'" -f $pair.Key, ($pair.Value -replace "'", "''")) }
    }
  }
  'status' {
    if (-not (Test-Healthy)) { Write-Output "AWS Emulator is not running on port $Port"; exit 1 }
    Write-Output "AWS Emulator is running at https://127.0.0.1:$Port"
    if ((Get-Command aws -ErrorAction SilentlyContinue) -and (Test-Path $EnvFile)) {
      Use-EmulatorEnv
      Write-Output ("Account: " + (& aws sts get-caller-identity --query Account --output text | Out-String).Trim())
    }
  }
  'logs' {
    if ($Follow) { Get-Content $LogFile -Tail 100 -Wait } else { Get-Content $LogFile -Tail 100 }
  }
  'down' {
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) { & wsl.exe --exec pkill -f "aws-emulator -p $Port" | Out-Null }
    if (Test-Path $PidFile) { Stop-Process -Id ([int](Get-Content $PidFile)) -ErrorAction SilentlyContinue }
    for ($t = 0; $t -lt 20 -and (Test-Healthy); $t++) { Start-Sleep -Milliseconds 500 }
    Remove-Item $State -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "AWS Emulator on port $Port is stopped"
  }
  { $_ -in '', 'help', '-h', '--help' } { Show-Usage }
  default { Show-Usage; Fail "unknown command $Command" }
}
exit 0
