[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutputDirectory,
    [switch]$SkipZip
)

$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root 'dist' }

$manifestPath = Join-Path $root 'manifest.json'
if ([string]::IsNullOrWhiteSpace($Version)) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $Version = [string]$manifest.version
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Release version must use semver: $Version" }

$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$releaseName = "DeGoogler-v$Version"
$stage = Join-Path $outputRoot $releaseName
$zipPath = Join-Path $outputRoot "$releaseName.zip"
$stagePrefix = $outputRoot.TrimEnd('\') + '\'
if (-not ([IO.Path]::GetFullPath($stage).StartsWith($stagePrefix, [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Release staging path must remain inside the requested output directory.'
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if ((-not $SkipZip) -and (Test-Path -LiteralPath $zipPath)) { Remove-Item -LiteralPath $zipPath -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$sourceFiles = @(
    'index.html',
    'alternatives.json',
    'manifest.json',
    'service-worker.js',
    'icon.svg',
    'plan.schema.json',
    'degoogler.jsx',
    'DeGoogler-BrowserAssistant.user.js',
    'DeGoogler-Toolkit.ps1',
    'DeGoogler-Toolkit.Core.ps1',
    'README.md',
    'LICENSE',
    'CHANGELOG.md',
    'build-release.ps1'
)
foreach ($relative in $sourceFiles) {
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Release source is missing: $relative" }
    $destination = Join-Path $stage $relative
    $destinationParent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$toolsSource = Join-Path $root 'tools'
if (-not (Test-Path -LiteralPath (Join-Path $toolsSource 'exiftool.exe') -PathType Leaf)) { throw 'Bundled ExifTool executable is missing.' }
if (-not (Test-Path -LiteralPath (Join-Path $toolsSource 'exiftool_files') -PathType Container)) { throw 'Bundled ExifTool support directory is missing.' }
Copy-Item -LiteralPath $toolsSource -Destination (Join-Path $stage 'tools') -Recurse -Force

$hashLines = Get-ChildItem -LiteralPath $stage -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
        "$hash  $relative"
    }
[IO.File]::WriteAllLines((Join-Path $stage 'SHA256SUMS'), $hashLines, [Text.Encoding]::ASCII)

if (-not $SkipZip) {
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -CompressionLevel Optimal
}

$result = [ordered]@{
    Version = $Version
    StagingDirectory = $stage
    ZipPath = if ($SkipZip) { $null } else { $zipPath }
    FileCount = @(Get-ChildItem -LiteralPath $stage -File -Recurse).Count
}
if (-not $SkipZip) { $result.ZipSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant() }
[pscustomobject]$result
