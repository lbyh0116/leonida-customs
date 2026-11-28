param([switch]$RayTracing, [switch]$DLSS)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Work = Join-Path $Root 'work'
$null = New-Item -ItemType Directory -Force -Path $Work
$null = New-Item -ItemType File -Force -Path (Join-Path $Work '.gdignore')
$env:TEMP = $Work
$env:TMP = $Work
. (Join-Path $Root 'tools/download-runtime.ps1')

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
    Get-VerifiedRuntimeArchive -Name Godot -Url $Url -Archive $Zip -Sha256 $Sha256
    tar.exe -xf $Zip -C $GodotFolder
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
        throw 'Could not extract Godot.'
    }
}

Install-Godot '4.7.2-stable' 'tools/godot' '731980F9608D61333E5BAF54A2EF17210ACC7A538446C0CB9969F002ACA1E953'
if ($RayTracing -or $DLSS) {
    & (Join-Path $Root 'tools/install-rtx.ps1') -DLSS:$DLSS
}
& (Join-Path $Root 'tools/install-sixng.ps1')
