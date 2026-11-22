<#
.SYNOPSIS
    Bump version in pubspec.yaml, commit, create a git tag, and push.
.PARAMETER Bump
    Which part to bump: major, minor, or patch (default: patch).
.EXAMPLE
    ./prepare_release.ps1 -Bump minor
#>
param(
    [ValidateSet('major','minor','patch')]
    [string]$Bump = 'patch'
)

function Get-CurrentVersion {
    $yaml = Get-Content -Path "pubspec.yaml" -Raw
    if ($yaml -match "version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)") {
        return [pscustomobject]@{Major=$Matches[1]; Minor=$Matches[2]; Patch=$Matches[3]}
    } else { throw "Version not found in pubspec.yaml" }
}

$ver = Get-CurrentVersion
switch ($Bump) {
    'major' { $ver.Major = [int]$ver.Major + 1; $ver.Minor = 0; $ver.Patch = 0 }
    'minor' { $ver.Minor = [int]$ver.Minor + 1; $ver.Patch = 0 }
    'patch' { $ver.Patch = [int]$ver.Patch + 1 }
}
$newVersion = "${ver.Major}.${ver.Minor}.${ver.Patch}"
# Update pubspec.yaml
(Get-Content pubspec.yaml) -replace "version:\s*[0-9]+\.[0-9]+\.[0-9]+", "version: $newVersion" | Set-Content pubspec.yaml
# Git commit and tag
git add pubspec.yaml
git commit -m "chore: bump version to $newVersion"
git tag "v$newVersion"
git push origin HEAD
git push origin "v$newVersion"
Write-Host "Version bumped to $newVersion and tagged as v$newVersion"
