param(
    [string]$SourceDir = "docs",
    [string]$SkillName = "python-mastery",
    [string]$SkillFile = "python-mastery.skill",
    [switch]$Fix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path .
$sourcePath = Join-Path $root $SourceDir
$skillPath = Join-Path $root $SkillFile
$sourceRoot = (Resolve-Path $sourcePath).Path

function Get-RelPath([string]$BasePath, [string]$FullPath) {
    return [System.IO.Path]::GetRelativePath($BasePath, $FullPath)
}

if (-not (Test-Path $sourcePath)) {
    Write-Error "Source directory not found: $sourcePath"
    exit 1
}
if (-not (Test-Path $skillPath)) {
    Write-Error "Skill archive not found: $skillPath"
    exit 1
}

$staging = Join-Path $root "tmp_skill_check"
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Path $staging | Out-Null

try {
    Expand-Archive -Path $skillPath -DestinationPath $staging -Force

    $skillRoot = Join-Path $staging $SkillName
    if (-not (Test-Path $skillRoot)) {
        # The build script creates a zip without the base directory, so files may be at archive root.
        $skillRoot = $staging
        if (-not (Test-Path (Join-Path $skillRoot "SKILL.md"))) {
            $top = Get-ChildItem -Path $staging -Directory | Select-Object -ExpandProperty Name
            Write-Error "Skill root '$SkillName' not found in archive. Found: $($top -join ', ')"
            exit 1
        }
    }

    $sourceFiles = Get-ChildItem -Path $sourcePath -File -Recurse |
        ForEach-Object { Get-RelPath $sourceRoot $_.FullName } |
        Sort-Object

    $skillFiles = Get-ChildItem -Path $skillRoot -File -Recurse |
        ForEach-Object { Get-RelPath $skillRoot $_.FullName } |
        Sort-Object

    $diff = Compare-Object -ReferenceObject $sourceFiles -DifferenceObject $skillFiles
    $hashMismatches = @()

    foreach ($rel in $sourceFiles) {
        $srcFile = Join-Path $sourcePath $rel
        $skFile = Join-Path $skillRoot $rel

        if (-not (Test-Path $skFile)) { continue }

        $srcHash = (Get-FileHash -Algorithm SHA256 -Path $srcFile).Hash
        $skHash = (Get-FileHash -Algorithm SHA256 -Path $skFile).Hash

        if ($srcHash -ne $skHash) {
            $hashMismatches += $rel
        }
    }

    $hasMismatch = ($diff -ne $null) -or ($hashMismatches.Count -gt 0)
    if (-not $hasMismatch) {
        Write-Host "OK: Skill archive matches source content."
        exit 0
    }

    Write-Host "Mismatch detected between source and skill archive."
    if ($diff) {
        Write-Host "File list mismatch:"
        $diff | ForEach-Object {
            $side = if ($_.SideIndicator -eq "<=") { "Missing in skill" } else { "Extra in skill" }
            Write-Host " - ${side}: $($_.InputObject)"
        }
    }
    if ($hashMismatches.Count -gt 0) {
        Write-Host "Content mismatch for files:"
        $hashMismatches | ForEach-Object { Write-Host " - $_" }
    }

    if (-not $Fix) { exit 1 }

    Write-Host "Fix enabled: rebuilding skill archive."
    $buildScript = Join-Path $root "scripts\\build-python-mastery-skill.ps1"
    if (-not (Test-Path $buildScript)) {
        Write-Error "Build script not found: $buildScript"
        exit 1
    }

    & $buildScript -SourceDir $SourceDir -SkillName $SkillName -OutFile $SkillFile

    Write-Host "Re-run verification after rebuild."
    exit 0
}
finally {
    if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
}
