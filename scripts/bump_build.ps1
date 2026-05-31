#!/usr/bin/env pwsh
# bump_build.ps1 — increments the build number in mobile/pubspec.yaml,
# stages the file, and commits + pushes with an optional message.
#
# Usage:
#   .\scripts\bump_build.ps1                       # commits with auto message
#   .\scripts\bump_build.ps1 "feat: my changes"   # uses custom commit message

param(
    [string]$Message = ""
)

$pubspec = "mobile\pubspec.yaml"
$content = Get-Content $pubspec -Raw

# Extract current version line: e.g.  version: 1.0.0+42
if ($content -notmatch 'version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
    Write-Error "Could not parse version from $pubspec"
    exit 1
}

$versionName = $Matches[1]
$buildNumber = [int]$Matches[2] + 1
$newVersion  = "version: $versionName+$buildNumber"

$content = $content -replace 'version:\s*\d+\.\d+\.\d+\+\d+', $newVersion
Set-Content $pubspec $content -NoNewline

Write-Host "Bumped build to $versionName+$buildNumber" -ForegroundColor Green

# Stage pubspec
git add $pubspec

# Commit message
if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = "chore: bump build number to $buildNumber"
}

git commit -m $Message
git push origin (git branch --show-current)

Write-Host "Done. Build $buildNumber pushed." -ForegroundColor Cyan
