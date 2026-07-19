<#
.SYNOPSIS
    Authenticode-signs dist\RescueDrive.exe when a code-signing certificate is
    available. Safe to call unconditionally: if no certificate is configured it
    prints a notice and exits 0, leaving the (working) unsigned exe in place.

.DESCRIPTION
    A signature is what stops Windows SmartScreen and most antivirus engines
    from blocking the installer. Provide a certificate in ONE of these ways
    (checked in order):

      1. RESCUE_SIGN_PFX_BASE64 + RESCUE_SIGN_PFX_PASSWORD
         A base64-encoded .pfx and its password. Best for CI — store both as
         repository/organization secrets and pass them as env vars. Create the
         base64 once with:
            [Convert]::ToBase64String([IO.File]::ReadAllBytes('mycert.pfx')) > cert.txt

      2. RESCUE_SIGN_PFX_PATH + RESCUE_SIGN_PFX_PASSWORD
         Path to a .pfx file on disk and its password. Best for local builds.

      3. RESCUE_SIGN_THUMBPRINT
         Thumbprint of a certificate already installed in the current user's
         "My" certificate store (e.g. a hardware/token cert).

    The signature is RFC-3161 timestamped so it stays valid after the
    certificate expires. Override the timestamp server with RESCUE_SIGN_TSA.
#>
param(
    # Files to sign. Defaults to the built exe; Build-Exe.ps1 also calls this
    # with every .ps1 in the repo, because Smart App Control / WDAC require
    # the SCRIPTS to be Authenticode-signed too, not just the exe.
    [string[]] $Paths = @((Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\RescueDrive.exe'))
)
$ErrorActionPreference = 'Stop'

$missing = $Paths | Where-Object { -not (Test-Path $_) }
if ($missing) { throw "Nothing to sign at: $($missing -join ', ')" }

$tsa = if ($env:RESCUE_SIGN_TSA) { $env:RESCUE_SIGN_TSA } else { 'http://timestamp.digicert.com' }

function Get-SigningCert {
    if ($env:RESCUE_SIGN_PFX_BASE64) {
        if (-not $env:RESCUE_SIGN_PFX_PASSWORD) { throw 'RESCUE_SIGN_PFX_BASE64 is set but RESCUE_SIGN_PFX_PASSWORD is missing.' }
        $bytes = [Convert]::FromBase64String($env:RESCUE_SIGN_PFX_BASE64)
        $pw    = ConvertTo-SecureString $env:RESCUE_SIGN_PFX_PASSWORD -AsPlainText -Force
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes, $pw,
            'Exportable,PersistKeySet')
    }
    if ($env:RESCUE_SIGN_PFX_PATH) {
        if (-not (Test-Path $env:RESCUE_SIGN_PFX_PATH)) { throw "RESCUE_SIGN_PFX_PATH not found: $($env:RESCUE_SIGN_PFX_PATH)" }
        if (-not $env:RESCUE_SIGN_PFX_PASSWORD) { throw 'RESCUE_SIGN_PFX_PATH is set but RESCUE_SIGN_PFX_PASSWORD is missing.' }
        $bytes = [IO.File]::ReadAllBytes($env:RESCUE_SIGN_PFX_PATH)
        $pw    = ConvertTo-SecureString $env:RESCUE_SIGN_PFX_PASSWORD -AsPlainText -Force
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes, $pw, 'Exportable,PersistKeySet')
    }
    if ($env:RESCUE_SIGN_THUMBPRINT) {
        $thumb = ($env:RESCUE_SIGN_THUMBPRINT -replace '\s', '').ToUpperInvariant()
        $cert  = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
        if (-not $cert) { throw "No certificate with thumbprint $thumb in Cert:\CurrentUser\My." }
        return $cert
    }
    return $null
}

$cert = Get-SigningCert
if (-not $cert) {
    Write-Host 'No signing certificate configured (RESCUE_SIGN_* env vars unset).'
    Write-Host 'Leaving files UNSIGNED — they still run, but SmartScreen/Smart App Control may block them.'
    Write-Host 'See installer-exe\Sign-Exe.ps1 for how to supply a certificate.'
    exit 0
}

Write-Host "Signing $($Paths.Count) file(s) with certificate: $($cert.Subject)"
foreach ($f in $Paths) {
    $result = Set-AuthenticodeSignature -FilePath $f -Certificate $cert `
        -HashAlgorithm SHA256 -TimestampServer $tsa -ErrorAction Stop
    if ($result.Status -ne 'Valid') {
        throw "Signing failed for ${f}: $($result.Status) — $($result.StatusMessage)"
    }
    Write-Host "  Signed OK: $f"
}
Write-Host "All signed; timestamped via $tsa."
