$ErrorActionPreference = 'Stop'
$Version = '0.11.0'
$Name = "SixNG-v$Version-windows-x64"
$Url = "https://github.com/holdmysocks/SixNG/releases/download/v$Version/$Name.zip"
$Sha256 = '3077EBEFFB9428BF09BF7EBC0D9A5D75F7CBBE1AAEA62213B4FFE1654303F673'
$ToolDirectory = $PSScriptRoot
$WorkDirectory = Join-Path (Split-Path -Parent $ToolDirectory) 'work'
$Destination = Join-Path $ToolDirectory $Name
$Exe = Join-Path $Destination 'sixng.exe'

if (Test-Path -LiteralPath $Exe -PathType Leaf) {
    Write-Output $Exe
    exit 0
}

$null = New-Item -ItemType Directory -Path $WorkDirectory -Force
$env:TEMP = $WorkDirectory
$env:TMP = $WorkDirectory
$Zip = Join-Path $WorkDirectory "$Name.zip"
curl.exe --fail --silent --show-error --location $Url --output $Zip
if ($LASTEXITCODE -ne 0) { throw 'SixNG download failed.' }
if ((Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash -ne $Sha256) {
    throw 'SixNG download does not match the expected SHA256.'
}
tar.exe -xf $Zip -C $ToolDirectory
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $Exe -PathType Leaf)) {
    throw 'Could not extract the SixNG release.'
}
Write-Output $Exe
