param([switch]$RayTracing)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Work = Join-Path $Root 'work'
$null = New-Item -ItemType Directory -Force -Path $Work
$null = New-Item -ItemType File -Force -Path (Join-Path $Work '.gdignore')
$env:TEMP = $Work
$env:TMP = $Work

function Install-Godot([string]$Version, [string]$Folder, [string]$Sha256) {
    $GodotFolder = Join-Path $Root $Folder
    $GodotName = "Godot_v${Version}_win64"
    $GodotExe = Join-Path $GodotFolder "$GodotName.exe"
    if (Test-Path -LiteralPath $GodotExe -PathType Leaf) {
        return
    }

    $null = New-Item -ItemType Directory -Force -Path $GodotFolder
    $Zip = Join-Path $Work "$GodotName.exe.zip"
    $Url = "https://github.com/godotengine/godot-builds/releases/download/$Version/$GodotName.exe.zip"
    curl.exe --fail --silent --show-error --location $Url --output $Zip
    if ($LASTEXITCODE -ne 0) { throw 'Godot download failed.' }
    if ((Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash -ne $Sha256) {
        throw 'Godot download does not match the expected SHA256.'
    }
    tar.exe -xf $Zip -C $GodotFolder
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
        throw 'Could not extract Godot.'
    }
}

Install-Godot '4.7.2-stable' 'tools/godot' '731980F9608D61333E5BAF54A2EF17210ACC7A538446C0CB9969F002ACA1E953'
if ($RayTracing) {
    Install-Godot '4.8-beta5' 'tools/godot-preview' '253F11023A4FE21F5420E0DF038CE5446B79C501E1168B8178DF3D70A23F5553'
}
& (Join-Path $Root 'tools/install-sixng.ps1')
& (Join-Path $Root 'Build-WinUI.ps1')
if ($RayTracing) {
    Write-Host 'Setup complete. Run Start-Viewer-RayTracing.cmd or Start-Viewer.cmd.'
} else {
    Write-Host 'Setup complete. Run Start-Viewer.cmd.'
}
