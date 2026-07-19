# Rebuilds dist\RescueDrive.exe from source (needs the .NET SDK: winget install Microsoft.DotNet.SDK.8)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$payload = Join-Path $PSScriptRoot 'payload.zip'
$sign = Join-Path $PSScriptRoot 'Sign-Exe.ps1'

# 1. Sign every PowerShell script IN PLACE first (no-op without a cert), so
#    both the repo copies and the payload embedded in the exe carry the
#    signature. Smart App Control / WDAC require signed scripts, not just a
#    signed exe.
$scripts = @(Get-ChildItem $root -Filter *.ps1 -File) +
           @(Get-ChildItem "$root\Toolkit", "$root\WinPE" -Filter *.ps1 -Recurse -File)
& $sign -Paths ($scripts.FullName)

# 2. Stage and zip the (now signed) payload.
Remove-Item $payload -ErrorAction SilentlyContinue
$staging = Join-Path $env:TEMP 'rescue_payload'
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $staging | Out-Null
Copy-Item "$root\RescueDrive.ps1" $staging
Copy-Item "$root\RescueDrive-Installer.ps1" $staging
Copy-Item "$root\Toolkit" "$staging\Toolkit" -Recurse
Copy-Item "$root\WinPE" "$staging\WinPE" -Recurse
if (Test-Path "$root\Drivers") { Copy-Item "$root\Drivers" "$staging\Drivers" -Recurse }
Compress-Archive "$staging\*" $payload

# 3. Build the exe, then sign it.
dotnet publish $PSScriptRoot -c Release -o "$root\dist"
Get-ChildItem "$root\dist" -Exclude RescueDrive.exe | Remove-Item -Recurse -Force
Write-Host "Built $root\dist\RescueDrive.exe"
& $sign -Paths @("$root\dist\RescueDrive.exe")
