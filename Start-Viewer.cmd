@echo off
setlocal
set "VIEWER_ROOT=%~dp0"
set "VIEWER_APP=%VIEWER_ROOT%work\winui\bin\VehicleStudio\release_win-x64\VehicleStudio.exe"
set "VIEWER_MODE="
if defined GTA6_VIEWER_RT set "VIEWER_MODE=--ray-tracing"
if not exist "%VIEWER_APP%" (
    echo The WinUI application is missing. Run setup.ps1 first.
    pause
    exit /b 1
)
start "" /d "%VIEWER_ROOT%." "%VIEWER_APP%" %VIEWER_MODE% %*
