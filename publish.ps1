<#
Publishes a converted UF2 build:
  1. Uploads SoftRF-VB008-<Letter>-dev.uf2 as an asset on a new GitHub Release (tag = version-letter).
  2. Copies it (renamed, no letter) to Binaries/SoftRF-VB008-dev.uf2, commits, and pushes to main.

Usage:
  .\publish.ps1 -Letter w
  .\publish.ps1 -Letter w -NotesFile notes.md
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z]$')]
    [string]$Letter,

    [string]$NotesFile,

    [string]$Version = "VB008"
)

$ErrorActionPreference = "Stop"
$gh = "C:\Program Files\GitHub CLI\gh.exe"

$RepoDir     = $PSScriptRoot
$SourceDir   = "C:\Users\v-b2\Documents\SoftRF\Binaries\SoftRF-VB0008-binaries"
$SourceName  = "SoftRF-$Version-$Letter-dev.uf2"
$SourceFile  = Join-Path $SourceDir $SourceName
$FixedName   = "SoftRF-$Version-dev.uf2"
$FixedFile   = Join-Path $RepoDir "Binaries\$FixedName"
$Tag         = "$Version-$Letter"

if (-not (Test-Path $SourceFile)) {
    throw "Build not found: $SourceFile (run convert.ps1 -Letter $Letter first)"
}

Push-Location $RepoDir
try {
    $branch = git rev-parse --abbrev-ref HEAD
    if ($branch -ne "main") {
        throw "Expected to be on 'main', currently on '$branch'. Switch branches before publishing."
    }

    $status = git status --porcelain
    if ($status) {
        throw "Working tree not clean. Commit or stash changes before publishing:`n$status"
    }

    Write-Host "Pulling latest main..."
    git pull --ff-only

    Write-Host "Creating GitHub release $Tag with asset $SourceName..."
    $releaseArgs = @(
        "release", "create", $Tag,
        $SourceFile,
        "--title", $Tag,
        "--repo", "slash-bit/SoftRF-T1000"
    )
    if ($NotesFile) {
        $releaseArgs += @("--notes-file", $NotesFile)
    } else {
        $releaseArgs += @("--notes", "SoftRF $Version build $Letter")
    }
    & $gh @releaseArgs
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed with exit code $LASTEXITCODE" }

    Write-Host "Updating $FixedName in Binaries/..."
    Copy-Item $SourceFile $FixedFile -Force

    git add "Binaries\$FixedName"
    $diff = git diff --cached --quiet; $hasDiff = $LASTEXITCODE -ne 0
    if (-not $hasDiff) {
        Write-Host "No change in $FixedName content, nothing to commit."
    } else {
        git commit -m "Update $FixedName to release $Tag"
        git push
        Write-Host "Pushed updated $FixedName to main."
    }

    Write-Host ""
    Write-Host "Release: https://github.com/slash-bit/SoftRF-T1000/releases/tag/$Tag"
    Write-Host "Fixed link: https://github.com/slash-bit/SoftRF-T1000/blob/main/Binaries/$FixedName"
}
finally {
    Pop-Location
}
