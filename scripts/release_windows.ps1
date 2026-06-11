# ── IMLiti Windows release script ────────────────────────────────────────────
# Usage:  .\scripts\release_windows.ps1 -Version 1.0.1
#
# Prerequisites:
#   - aws CLI configured (eu-west-3)
#   - Flutter installed
#   - Run from the repo root
#
# What it does:
#   1. Bumps version in pubspec.yaml
#   2. Builds the Windows release
#   3. Zips the Release/ folder contents
#   4. Uploads to S3 at app/windows/imliti-<version>.zip
#   5. Updates app/latest.json  (only updates the windows field)
# ─────────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory)][string]$Version
)

$ErrorActionPreference = "Stop"

$AccountId = (aws sts get-caller-identity --query Account --output text)
$Bucket    = "imliti-scrapes-$AccountId"
$S3Key     = "app/windows/imliti-$Version.zip"
$S3Url     = "https://$Bucket.s3.eu-west-3.amazonaws.com/$S3Key"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$FrontendDir = Join-Path $ScriptDir "..\frontend"
$ReleaseDir  = Join-Path $FrontendDir "build\windows\x64\runner\Release"
$ZipPath     = Join-Path $env:TEMP "imliti-$Version-windows.zip"

Write-Host "── Bumping version to $Version ────────────────────────────────────"
$Pubspec = Get-Content "$FrontendDir\pubspec.yaml" -Raw
$Pubspec = $Pubspec -replace 'version: \d+\.\d+\.\d+\+\d+', "version: $Version+1"
Set-Content "$FrontendDir\pubspec.yaml" -Value $Pubspec -NoNewline

Write-Host "── Building Windows release ──────────────────────────────────────"
Push-Location $FrontendDir
flutter build windows --release
Pop-Location

Write-Host "── Packaging release folder ──────────────────────────────────────"
if (Test-Path $ZipPath) { Remove-Item $ZipPath }

# Zip the contents of Release/ (not the folder itself), so extracting to
# the install dir works without an extra nesting level.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')

Get-ChildItem -Path $ReleaseDir -Recurse | ForEach-Object {
    if (-not $_.PSIsContainer) {
        $relative = $_.FullName.Substring($ReleaseDir.Length + 1)
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $_.FullName, $relative,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
}
$zip.Dispose()

$zipSizeMB = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Write-Host "Zip size: ${zipSizeMB} MB"

Write-Host "── Uploading to S3 ───────────────────────────────────────────────"
aws s3 cp $ZipPath "s3://$Bucket/$S3Key" `
    --region eu-west-3 `
    --content-type "application/zip"

Write-Host "── Updating latest.json ──────────────────────────────────────────"
$ManifestKey = "app/latest.json"
try {
    $Existing = aws s3 cp "s3://$Bucket/$ManifestKey" - --region eu-west-3 2>$null | ConvertFrom-Json
} catch {
    $Existing = @{}
}

$Manifest = @{
    version = $Version
    notes   = if ($Existing.notes) { $Existing.notes } else { "" }
    windows = $S3Url
    macos   = if ($Existing.macos) { $Existing.macos } else { "" }
} | ConvertTo-Json -Depth 2

$ManifestPath = Join-Path $env:TEMP "imliti_latest.json"
Set-Content $ManifestPath -Value $Manifest -Encoding UTF8
aws s3 cp $ManifestPath "s3://$Bucket/$ManifestKey" `
    --region eu-west-3 `
    --content-type "application/json"

Remove-Item $ZipPath -Force
Remove-Item $ManifestPath -Force

Write-Host ""
Write-Host "OK  Released Windows $Version"
Write-Host "    Manifest: https://$Bucket.s3.eu-west-3.amazonaws.com/$ManifestKey"
Write-Host "    Download: $S3Url"
