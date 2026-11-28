function Get-VerifiedRuntimeArchive {
    param([string]$Name, [string]$Url, [string]$Archive, [string]$Sha256)

    $partial = "$Archive.part"
    $lock = [IO.File]::Open("$Archive.lock", 'OpenOrCreate', 'Write', 'None')
    try {
        if (Test-Path -LiteralPath $Archive -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $Archive).Hash -eq $Sha256) {
                Write-Host "Using verified $Name archive."
                return
            }
            Write-Warning "The cached $Name archive failed SHA-256 verification. Downloading a fresh copy."
            Remove-Item -LiteralPath $Archive
        }

        $options = @('--fail', '--location', '--show-error', '--progress-bar',
            '--connect-timeout', '15', '--speed-limit', '1', '--speed-time', '45',
            '--write-out', '%{http_code}', '--output', $partial)
        for ($attempt = 1; $attempt -le 4; $attempt++) {
            $resume = (Test-Path -LiteralPath $partial -PathType Leaf) -and
                (Get-Item -LiteralPath $partial).Length -gt 0
            $range = @()
            if ($resume) {
                $range = @('--continue-at', '-')
            }

            $action = if ($resume) { 'Resuming' } else { 'Downloading' }
            Write-Host "$action $Name (attempt $attempt/4)..."
            $status = curl.exe @options @range $Url
            $code = $LASTEXITCODE

            # A prior run may have stopped after writing the final byte.
            if (($code -eq 0 -or ($resume -and ($code -eq 33 -or $status -eq '416'))) -and
                (Test-Path -LiteralPath $partial -PathType Leaf)) {
                if ((Get-FileHash -LiteralPath $partial).Hash -eq $Sha256) {
                    Move-Item -LiteralPath $partial -Destination $Archive
                    return
                }
                Remove-Item -LiteralPath $partial
                if (!$resume) {
                    throw "$Name download failed SHA-256 verification. Official archive: $Url"
                }
                Write-Warning "The partial $Name download could not be reused. Restarting the transfer."
            } elseif ($code -eq 22 -and $status -notmatch '^(408|429|5\d\d)$') {
                break
            }

            if ($attempt -lt 4) {
                Start-Sleep -Seconds ([math]::Pow(2, $attempt - 1))
            }
        }

        throw "Could not download $Name (curl $code, HTTP $status). Rerun the installer to resume, or download $Url and save the ZIP as $Archive."
    } finally {
        $lock.Dispose()
    }
}
