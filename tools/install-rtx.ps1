param([switch]$DLSS)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $Root 'work'
$Target = Join-Path $PSScriptRoot 'godot-rtx'
$ExeName = 'godot.windows.editor.x86_64.exe'
$ExeHash = '9AA8D1DD7C73197FAB13947CF204EA07770696B4DF46DFA38220FB7DE3CCC480'
$Exe = Join-Path $Target $ExeName
$null = New-Item -ItemType Directory -Force -Path $Work,$Target
$env:TEMP = $Work
$env:TMP = $Work
. (Join-Path $PSScriptRoot 'download-runtime.ps1')

if (!(Test-Path -LiteralPath $Exe)) {
    if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'Install GitHub CLI and sign in to download the official NVIDIA Godot artifact.'
    }
    $Staging = Join-Path $Work 'nvidia-godot-49a825dc5'
    $null = New-Item -ItemType Directory -Force -Path $Staging
    gh run download 41390391716 --repo NVIDIA-RTX/godot --name windows-editor --dir $Staging
    if ($LASTEXITCODE -ne 0) { throw 'The official NVIDIA artifact could not be downloaded. See the RTX setup section in README.md.' }
    $DownloadedExe = Join-Path $Staging $ExeName
    if ((Get-FileHash -LiteralPath $DownloadedExe -Algorithm SHA256).Hash -ne $ExeHash) {
        throw 'The official NVIDIA Godot executable does not match the expected SHA-256.'
    }
    foreach ($name in @('D3D12Core.dll', 'd3d12SDKLayers.dll', $ExeName)) {
        Copy-Item -LiteralPath (Join-Path $Staging $name) -Destination $Target
    }
}

if ($DLSS) {
    $Archive = Join-Path $Work 'streamline-2.10.0.zip'
    $Hash = 'B0CC810C86B0335D4FD76A02D35FFF53E528D2FB66C29860565130F76C9383B0'
    $Url = 'https://github.com/NVIDIA-RTX/Streamline/releases/download/v2.10.0/streamline-sdk-v2.10.0.zip'
    Get-VerifiedRuntimeArchive -Name 'NVIDIA Streamline' -Url $Url -Archive $Archive -Sha256 $Hash
    $Staging = Join-Path $Work 'streamline-2.10.0'
    $null = New-Item -ItemType Directory -Force -Path $Staging
    tar.exe -xf $Archive -C $Staging bin/x64
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract NVIDIA Streamline.' }
    Get-ChildItem -LiteralPath (Join-Path $Staging 'bin/x64') -File |
        Where-Object { $_.Name -match '^(sl\.|nvngx_dlss|NvLowLatencyVk)|\.license\.txt$' } |
        Copy-Item -Destination $Target
}
