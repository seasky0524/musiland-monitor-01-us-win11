@echo off
setlocal
set "SCRIPT=%~dp0Install-MUSILAND-ControlPanel-Win11.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%SCRIPT%""'"
endlocal
