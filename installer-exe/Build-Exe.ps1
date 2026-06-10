# Rebuilds dist\RescueDrive.exe from source (needs the .NET SDK: winget install Microsoft.DotNet.SDK.8)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$payload = Join-Path $PSScriptRoot 'payload.zip'

Remove-Item $payload -ErrorAction SilentlyContinue
$staging = Join-Path $env:TEMP 'rescue_payload'
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $staging | Out-Null
Copy-Item "$root\RescueDrive-Installer.ps1" $staging
Copy-Item "$root\Toolkit" "$staging\Toolkit" -Recurse
Copy-Item "$root\WinPE" "$staging\WinPE" -Recurse
if (Test-Path "$root\Drivers") { Copy-Item "$root\Drivers" "$staging\Drivers" -Recurse }
Compress-Archive "$staging\*" $payload

dotnet publish $PSScriptRoot -c Release -o "$root\dist"
Get-ChildItem "$root\dist" -Exclude RescueDrive.exe | Remove-Item -Recurse -Force
Write-Host "Built $root\dist\RescueDrive.exe"
