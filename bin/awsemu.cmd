@echo off
rem Runs windows\awsemu.ps1 in a new PowerShell, without changing the script policy of the machine.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\windows\awsemu.ps1" %*
exit /b %ERRORLEVEL%
