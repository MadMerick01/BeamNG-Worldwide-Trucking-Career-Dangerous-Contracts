@echo off
rem Updates this trucking server to the newest BeamNG.Earth and trucking releases. See SERVER-UPDATES.md.
rem Add -CheckOnly to only see what's new, -Now to skip the 10 minute countdown.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-server.ps1" %*
echo.
pause
