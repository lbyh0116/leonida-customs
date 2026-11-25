@echo off
setlocal
set "VIEWER_ROOT=%~dp0"
set "VIEWER_GODOT=%VIEWER_ROOT%tools\godot\Godot_v4.7.2-stable_win64.exe"
set "VIEWER_LOG=viewer.log"
if defined GTA6_VIEWER_RT (
    set "VIEWER_GODOT=%VIEWER_ROOT%tools\godot-preview\Godot_v4.8-beta5_win64.exe"
    set "VIEWER_LOG=viewer-raytracing.log"
)
if not exist "%VIEWER_GODOT%" (
    if defined GTA6_VIEWER_RT (
        echo The Godot ray-tracing build is missing. Run setup.ps1 -RayTracing first.
    ) else (
        echo Godot is missing. Run setup.ps1 first.
    )
    pause
    exit /b 1
)
if not exist "%VIEWER_ROOT%work" mkdir "%VIEWER_ROOT%work"
if not exist "%VIEWER_ROOT%work\.gdignore" type nul > "%VIEWER_ROOT%work\.gdignore"
start "" "%VIEWER_GODOT%" --path "%VIEWER_ROOT%." --log-file "%VIEWER_ROOT%work\%VIEWER_LOG%" -- %*
