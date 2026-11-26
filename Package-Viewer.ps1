$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Work = Join-Path $Root 'work'
$Project = [xml](Get-Content -Raw -LiteralPath (Join-Path $Root 'winui/VehicleStudio.csproj'))
$Version = [string]$Project.Project.PropertyGroup.Version
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw 'The WinUI project must specify a valid release version.'
}

& (Join-Path $Root 'Build-WinUI.ps1') -Publish
$App = Join-Path $Work 'winui/publish/VehicleStudio/release_win-x64'
if (!(Test-Path -LiteralPath (Join-Path $App 'VehicleStudio.exe') -PathType Leaf)) {
    throw 'The self-contained WinUI application was not published.'
}

$Dist = Join-Path $Work 'dist'
$null = New-Item -ItemType Directory -Force -Path $Dist
$Zip = Join-Path $Dist "Leonida-Customs-$Version-windows-x64.zip"
$Pending = Join-Path $Dist ([System.IO.Path]::GetRandomFileName())
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-ZipFile($Archive, [string]$File, [string]$Entry) {
    $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $Archive, $File, $Entry.Replace('\', '/'), [System.IO.Compression.CompressionLevel]::Optimal)
}

try {
    $Archive = [System.IO.Compression.ZipFile]::Open($Pending, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($Name in @('LICENSE', 'README.md', 'SHARE-CODE.md', 'project.godot', 'main.tscn',
            'preview-worker.tscn', 'Install-ViewerRuntime.ps1', 'Start-Viewer.cmd', 'Start-Viewer-Safe-Mode.cmd',
            'Start-Viewer-RayTracing.cmd', 'tools/.gdignore', 'tools/install-sixng.ps1', 'tools/install-rtx.ps1')) {
            Write-ZipFile $Archive (Join-Path $Root $Name) $Name
        }
        foreach ($Source in Get-ChildItem -LiteralPath (Join-Path $Root 'src') -File) {
            if ($Source.Extension -in @('.gd', '.gdshader', '.uid')) {
                Write-ZipFile $Archive $Source.FullName "src/$($Source.Name)"
            }
        }
        foreach ($File in Get-ChildItem -LiteralPath $App -Recurse -File) {
            if ($File.Extension -ne '.pdb') {
                $Relative = $File.FullName.Substring($App.Length + 1)
                Write-ZipFile $Archive $File.FullName "app/$Relative"
            }
        }
    } finally {
        $Archive.Dispose()
    }
    Move-Item -LiteralPath $Pending -Destination $Zip -Force
} finally {
    if (Test-Path -LiteralPath $Pending) {
        Remove-Item -LiteralPath $Pending
    }
}
$Hash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$Zip.sha256" -Encoding ascii -Value "$Hash  $([System.IO.Path]::GetFileName($Zip))"
Write-Output $Zip
