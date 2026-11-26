param([switch]$Publish)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Work = Join-Path $Root 'work'
$null = New-Item -ItemType Directory -Force -Path $Work
$null = New-Item -ItemType File -Force -Path (Join-Path $Work '.gdignore')
$env:NUGET_PACKAGES = Join-Path $Work 'nuget'
$env:NUGET_HTTP_CACHE_PATH = Join-Path $Work 'nuget-http'
$env:NUGET_PLUGINS_CACHE_PATH = Join-Path $Work 'nuget-plugins'
$env:DOTNET_CLI_HOME = Join-Path $Work 'dotnet'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:TEMP = $Work
$env:TMP = $Work
if (!(Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '.NET 10 SDK is required to build the WinUI interface.'
}
$Command = if ($Publish) { 'publish' } else { 'build' }
dotnet $Command (Join-Path $Root 'winui/VehicleStudio.csproj') -c Release --artifacts-path (Join-Path $Work 'winui') --nologo
if ($LASTEXITCODE -ne 0) { throw 'The WinUI interface did not build.' }
