param(
    [string]$SourceDir = "docs",
    [string]$SkillName = "python-mastery",
    [string]$SkillFile = "python-mastery.skill"
)

Set-StrictMode -Version Latest

$root = Resolve-Path .
$skillMd = Join-Path $root $SourceDir "SKILL.md"
$refDir = Join-Path $root $SourceDir "references"
$checkScript = Join-Path $root "scripts" "check-python-mastery-skill.ps1"

if (!(Test-Path $skillMd)) {
    Write-Host "Missing: $skillMd"
    exit 1
}
if (!(Test-Path $refDir)) {
    Write-Host "Missing: $refDir"
    exit 1
}

$content = Get-Content -Path $skillMd -Raw
$matches = [regex]::Matches($content, '`([^`]+\.md)`')
$referenced = @()
foreach ($m in $matches) {
    $path = $m.Groups[1].Value.Trim()
    if ($path -ieq "SKILL.md") { continue }
    $referenced += $path
}
$referenced = $referenced | Sort-Object -Unique

if ($referenced.Count -eq 0) {
    Write-Host "No referenced markdown files found in SKILL.md."
    exit 1
}

$missing = @()
foreach ($ref in $referenced) {
    $normalized = $ref -replace '/', '\'
    if ($normalized -match '[\\/]' ) {
        $candidate = Join-Path $root $SourceDir $normalized
    } else {
        $candidate = Join-Path $refDir $normalized
    }
    if (!(Test-Path $candidate)) {
        $missing += $ref
    }
}

$allRefFiles = Get-ChildItem -Path $refDir -File -Filter *.md | Select-Object -ExpandProperty Name
$refNames = @()
foreach ($ref in $referenced) {
    $refNames += [System.IO.Path]::GetFileName($ref)
}
$refNames = $refNames | Sort-Object -Unique

$orphans = @()
foreach ($f in $allRefFiles) {
    if ($refNames -notcontains $f) {
        $orphans += $f
    }
}

$failed = $false
if ($missing.Count -gt 0) {
    Write-Host "Missing referenced files:"
    $missing | ForEach-Object { Write-Host "  - $_" }
    $failed = $true
}
if ($orphans.Count -gt 0) {
    Write-Host "Unreferenced files in docs/references:"
    $orphans | ForEach-Object { Write-Host "  - $_" }
    $failed = $true
}

$skillPath = Join-Path $root $SkillFile
if (!(Test-Path $skillPath)) {
    Write-Host "Skill bundle missing: $SkillFile"
    $failed = $true
} else {
    if (!(Test-Path $checkScript)) {
        Write-Host "Check script missing: $checkScript"
        $failed = $true
    } else {
        & $checkScript -SourceDir $SourceDir -SkillName $SkillName -SkillFile $SkillFile
        if ($LASTEXITCODE -ne 0) {
            $failed = $true
        }
    }
}

if ($failed) { exit 1 }

Write-Host "Validation passed."
