<#
.SYNOPSIS
    Rollback to a previous version tag, rebuild the Flutter app.
.PARAMETER Tag
    Specific tag to rollback to (e.g., v1.0.0). If omitted, the script uses the previous tag.
.EXAMPLE
    ./rollback.ps1 -Tag v1.2.3
    ./rollback.ps1   # rolls back to the most recent prior tag
#>
param(
    [string]$Tag
)

function Get-PreviousTag {
    $tags = git tag --sort=-creatordate
    if (-not $tags) { throw "No tags found in repository" }
    $tagsArray = $tags -split "\n"
    if ($Tag) {
        return $Tag
    } else {
        if ($tagsArray.Length -lt 2) { throw "Only one tag exists; cannot determine previous version" }
        return $tagsArray[1]
    }
}

$targetTag = Get-PreviousTag
Write-Host "Rolling back to tag: $targetTag"
# Create a temporary branch for rollback
$branchName = "rollback-$targetTag"
if (git rev-parse --verify $branchName 2>$null) {
    git checkout $branchName
} else {
    git checkout -b $branchName $targetTag
}
# Clean and get dependencies
flutter clean
flutter pub get
# Build the app (adjust platform as needed)
# Example for Android APK:
flutter build apk --release
Write-Host "Rollback complete. Built APK for tag $targetTag on branch $branchName."
