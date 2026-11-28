@echo off
setlocal
set "VIEWER_ROOT=%~dp0"
set "VIEWER_APP=%VIEWER_ROOT%app\VehicleStudio.exe"
if not exist "%VIEWER_APP%" set "VIEWER_APP=%VIEWER_ROOT%work\winui\bin\VehicleStudio\release_win-x64\VehicleStudio.exe"
if not exist "%VIEWER_APP%" (
    echo VehicleStudio.exe is missing. Extract the complete Windows release ZIP or run setup.ps1 from the source checkout.
    pause
    exit /b 1
)

if not exist "%VIEWER_ROOT%tools\godot\Godot_v4.7.2-stable_win64.exe" goto install
if defined SIXNG_EXE if exist "%SIXNG_EXE%" goto launch
if exist "%VIEWER_ROOT%tools\SixNG-v0.11.0-windows-x64\sixng.exe" goto launch

:install
echo Installing Godot and SixNG from their official releases. Internet access is needed for this first launch.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%VIEWER_ROOT%Install-ViewerRuntime.ps1"
if errorlevel 1 (
    echo Runtime setup did not complete. Check the message above, then rerun Start-Viewer.cmd to resume.
    pause
    exit /b 1
)

:launch
set "VIEWER_MODE="
if defined GTA6_VIEWER_RT set "VIEWER_MODE=--ray-tracing"
start "" /d "%VIEWER_ROOT%." "%VIEWER_APP%" %VIEWER_MODE% %*
