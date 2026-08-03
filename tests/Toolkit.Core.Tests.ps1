$ErrorActionPreference = 'Stop'

function Assert-DgTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$corePath = Join-Path $PSScriptRoot '..\DeGoogler-Toolkit.Core.ps1'
. (Resolve-Path $corePath)
$root = Join-Path $env:TEMP ('degoogler-core-test-' + [guid]::NewGuid().ToString('N'))

try {
    $keepIn = Join-Path $root 'keep-in'; $keepOut = Join-Path $root 'keep-out'
    $fitIn = Join-Path $root 'fit-in'; $fitOut = Join-Path $root 'fit-out'
    $mapsIn = Join-Path $root 'maps-in'; $mapsOut = Join-Path $root 'maps-out'
    $chatIn = Join-Path $root 'chat-in'; $chatOut = Join-Path $root 'chat-out'
    foreach ($path in @($keepIn, $fitIn, $mapsIn, $chatIn)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }

    [IO.File]::WriteAllText((Join-Path $keepIn 'note.json'), '{"title":"Trip","textContent":"Pack camera","labels":[{"name":"Travel"}],"userEditedTimestampUsec":"1700000000000000"}')
    [IO.File]::WriteAllText((Join-Path $fitIn 'activity.json'), '{"startTimeNanos":"1700000000000000000","endTimeNanos":"1700000060000000000","activityType":"walking","value":42,"latitude":40.1,"longitude":-73.9}')
    [IO.File]::WriteAllText((Join-Path $mapsIn 'saved.json'), '[{"title":"Home","latitude":40.1,"longitude":-73.9}]')
    [IO.File]::WriteAllText((Join-Path $chatIn 'chat.mbox'), "From sender@example.com Mon Jan 01 00:00:00 2024`nFrom: Sender <sender@example.com>`nSubject: Hello`n`nMessage body`n")

    $keep = Convert-DgKeepTakeout -InputPath $keepIn -OutputPath $keepOut
    $fit = Convert-DgFitTakeout -InputPath $fitIn -OutputPath $fitOut
    $maps = Convert-DgMapsSavedPlaces -InputPath $mapsIn -OutputPath $mapsOut
    $chat = Convert-DgChatMbox -InputPath $chatIn -OutputPath $chatOut

    Assert-DgTest (Test-Path (Join-Path $keepOut 'Travel\Trip.md')) 'Keep Markdown output missing'
    Assert-DgTest (Test-Path (Join-Path $fitOut 'fit-activities.tcx')) 'Fit TCX output missing'
    Assert-DgTest (Test-Path (Join-Path $fitOut 'fit-apple-health.xml')) 'Fit Apple Health output missing'
    Assert-DgTest (Test-Path (Join-Path $mapsOut 'saved-places.geojson')) 'Maps GeoJSON output missing'
    Assert-DgTest (Test-Path (Join-Path $mapsOut 'saved-places.gpx')) 'Maps GPX output missing'
    Assert-DgTest (Test-Path (Join-Path $mapsOut 'saved-places.kml')) 'Maps KML output missing'
    Assert-DgTest (Test-Path (Join-Path $chatOut 'chat-migration.json')) 'Chat JSON output missing'
    Assert-DgTest ($keep.Written -eq 1) 'Keep summary count incorrect'
    Assert-DgTest ($fit.Records -ge 1) 'Fit record extraction failed'
    Assert-DgTest ($maps.Records -eq 1) 'Maps record extraction failed'
    Assert-DgTest ($chat.Messages -eq 1) 'Chat message extraction failed'

    $photoDir = Join-Path $root 'photo-in'; New-Item -ItemType Directory -Path $photoDir -Force | Out-Null
    $photo = Join-Path $photoDir 'IMG_20240102_030405_1.jpg'
    [IO.File]::WriteAllText($photo, 'placeholder')
    [IO.File]::WriteAllText((Join-Path $photoDir 'IMG_20240102_030405_1.jpg.supplemental-metadata.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $photoDir '.picasa.ini'), "[IMG_20240102_030405_1.jpg]`ncaption=Trip photo`ndate=2024-01-02T03:04:05Z`n")
    $sidecar = Find-DgPhotoMetadataFile -MediaPath $photo -JsonFiles @(Get-ChildItem -LiteralPath $photoDir -Filter '*.json')
    $filenameDate = Get-DgFilenameDate -MediaPath $photo
    $picasa = Get-DgPicasaMetadata -MediaPath $photo
    $xmp = Write-DgXmpSidecar -MediaPath $photo -Date $filenameDate -Description 'Trip photo'
    Assert-DgTest ($sidecar -like '*.supplemental-metadata.json') 'Supplemental sidecar matcher failed'
    Assert-DgTest ($filenameDate.Year -eq 2024 -and $filenameDate.Hour -eq 3) 'Filename date fallback failed'
    Assert-DgTest ($picasa.Caption -eq 'Trip photo') 'Picasa metadata parser failed'
    Assert-DgTest (Test-Path $xmp) 'XMP sidecar output missing'
    Assert-DgTest ((Get-Content -LiteralPath $xmp -Raw) -match 'DateTimeOriginal') 'XMP date metadata missing'
    Assert-DgTest ((Get-DgBurstKey -MediaPath $photo -Date $filenameDate) -ne $null) 'Burst key detection failed'
    Write-Output 'PASS converter core smoke'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
