param([switch]$RayTracing, [switch]$DLSS)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
& (Join-Path $Root 'Install-ViewerRuntime.ps1') -RayTracing:$RayTracing -DLSS:$DLSS
& (Join-Path $Root 'Build-WinUI.ps1')
if ($RayTracing -or $DLSS) {
    Write-Host 'Setup complete. Run Start-Viewer-RayTracing.cmd or Start-Viewer.cmd.'
} else {
    Write-Host 'Setup complete. Run Start-Viewer.cmd.'
}
