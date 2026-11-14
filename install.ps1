# Installs the awsemu command for the current user, from the v1 release:
#   irm https://raw.githubusercontent.com/Guilherme-Benfica/setup-aws-emulator/v1/install.ps1 | iex
# $env:AWSEMU_REF picks another tag; $env:AWSEMU_SOURCE installs from a local checkout.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ref = if ($env:AWSEMU_REF) { $env:AWSEMU_REF } else { 'v1' }
$app = Join-Path $env:USERPROFILE '.awsemu\app'

if ($env:AWSEMU_SOURCE) {
  $src = $env:AWSEMU_SOURCE
} else {
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("awsemu-" + [guid]::NewGuid())
  New-Item -ItemType Directory $tmp | Out-Null
  $zip = Join-Path $tmp 'awsemu.zip'
  Invoke-WebRequest -UseBasicParsing "https://github.com/Guilherme-Benfica/setup-aws-emulator/archive/refs/tags/$ref.zip" -OutFile $zip
  Expand-Archive $zip -DestinationPath $tmp
  $src = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
}

if (Test-Path $app) { Remove-Item $app -Recurse -Force }
New-Item -ItemType Directory -Force $app | Out-Null
Copy-Item (Join-Path $src 'bin'), (Join-Path $src 'scripts'), (Join-Path $src 'windows') -Destination $app -Recurse

$bin = Join-Path $app 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (($userPath -split ';') -contains $bin)) {
  [Environment]::SetEnvironmentVariable('Path', ($(if ($userPath) { "$userPath;" } else { '' }) + $bin), 'User')
  Write-Output "Added $bin to your PATH. Open a new terminal to use awsemu."
}
Write-Output 'Installed awsemu. Start the emulator with: awsemu up'
