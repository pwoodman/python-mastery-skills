param(
    [string]$SourceDir = "docs",
    [string]$SkillName = "python-mastery",
    [string]$OutFile = "python-mastery.skill"
)

$root = Resolve-Path .
$staging = Join-Path $root "tmp_skill_build"
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Path $staging | Out-Null

$target = Join-Path $staging $SkillName
New-Item -ItemType Directory -Path $target | Out-Null

Write-Host "Copying skill content from $SourceDir to $target"
Copy-Item -Path (Join-Path $SourceDir "*") -Destination $target -Recurse -Force

if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($target, (Join-Path $root $OutFile), [System.IO.Compression.CompressionLevel]::Optimal, $true)

Write-Host "Built skill archive: $OutFile"
Write-Host "Cleanup: removing staging directory"
Remove-Item -Recurse -Force $staging
