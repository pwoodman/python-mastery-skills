param(
    [string]$RepoUrl = "https://github.com/pwoodman/python-mastery-skills.git",
    [string]$InstallRoot = "$env:USERPROFILE\.claude\skills",
    [string]$SkillName = "python-mastery"
)

$target = Join-Path $InstallRoot $SkillName
$tempRoot = Join-Path $env:TEMP "python-mastery-skills-install"
$tempRepo = Join-Path $tempRoot "repo"

Write-Host "Installing Python Mastery skill (Windows)..."

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required but was not found on PATH."
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

if (Test-Path $target) {
    Remove-Item -Recurse -Force $target
}

if (Test-Path $tempRoot) {
    Remove-Item -Recurse -Force $tempRoot
}

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    git clone --depth 1 $RepoUrl $tempRepo | Out-Null

    $sourceDir = Join-Path $tempRepo "docs"
    if (-not (Test-Path $sourceDir)) {
        throw "Expected docs directory not found in cloned repository."
    }

    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Path (Join-Path $sourceDir "*") -Destination $target -Recurse -Force

    Write-Host "Installed to $target"
    Write-Host "Restart Claude Code to use the skill."
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
    }
}
