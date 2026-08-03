# DeGoogler Toolkit conversion core. This file has no UI or elevation side effects.

function ConvertTo-DgSafeFileName {
    param([AllowNull()][string]$Name, [string]$Fallback = 'untitled')
    $value = if ([string]::IsNullOrWhiteSpace($Name)) { $Fallback } else { $Name.Trim() }
    $value = $value -replace '[\/:*?"<>|]', '_'
    $value = $value -replace '[\x00-\x1f]', '_'
    $value = $value.TrimEnd('.', ' ')
    if ([string]::IsNullOrWhiteSpace($value)) { $value = $Fallback }
    if ($value.Length -gt 120) { $value = $value.Substring(0, 120).TrimEnd('.', ' ') }
    return $value
}

function Get-DgInputFiles {
    param([Parameter(Mandatory=$true)][string]$InputPath, [string[]]$Extensions)
    if (-not (Test-Path -LiteralPath $InputPath)) { throw "Input path does not exist: $InputPath" }
    $item = Get-Item -LiteralPath $InputPath
    if (-not $item.PSIsContainer) { return @($item) }
    $files = @(Get-ChildItem -LiteralPath $item.FullName -File -Recurse -ErrorAction Stop)
    if ($Extensions -and $Extensions.Count -gt 0) {
        $wanted = @($Extensions | ForEach-Object { $_.ToLowerInvariant() })
        $files = @($files | Where-Object { $wanted -contains $_.Extension.ToLowerInvariant() })
    }
    return $files
}

function Write-DgAtomicText {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($temp, $Content, $utf8)
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Get-DgProperty {
    param([AllowNull()]$Object, [Parameter(Mandatory=$true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($property) { return $property.Value }
    return $null
}

function Import-DgMigrationPlan {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Migration plan does not exist: $Path" }
    try { $plan = (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop } catch { throw "Migration plan is not valid JSON: $Path" }
    foreach ($required in @('schema','version','profile','generatedAt','actions','connectedServices')) {
        if (-not ($plan.PSObject.Properties.Name -contains $required)) { throw "Migration plan is missing required property: $required" }
    }
    if ([string]$plan.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Migration plan version must use semver.' }
    if ($plan.actions -isnot [System.Collections.IEnumerable] -or $plan.connectedServices -isnot [System.Collections.IEnumerable]) { throw 'Migration plan actions and connectedServices must be arrays.' }
    foreach ($action in @($plan.actions)) {
        foreach ($required in @('id','phase','title','required','automated','timeEstimate','difficultyScore','done')) {
            if ($null -eq (Get-DgProperty $action $required)) { throw "Migration action is missing required property: $required" }
        }
        $score = [int](Get-DgProperty $action 'difficultyScore')
        if ($score -lt 1 -or $score -gt 5) { throw "Migration action difficultyScore must be between 1 and 5: $($action.id)" }
    }
    return $plan
}

function ConvertFrom-DgDeepLink {
    param([Parameter(Mandatory=$true)][string]$Uri)
    try { $parsed = New-Object System.Uri($Uri) } catch { throw 'Deep link is not a valid URI.' }
    if ($parsed.Scheme -ne 'degoogler' -or $parsed.Host -ne 'toolkit') { throw 'Unsupported DeGoogler deep-link scheme.' }
    $values = @{}
    foreach ($pair in ($parsed.Query.TrimStart('?') -split '&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $parts = $pair -split '=', 2
        $key = [Uri]::UnescapeDataString($parts[0]).ToLowerInvariant()
        $value = if ($parts.Count -gt 1) { [Uri]::UnescapeDataString(($parts[1] -replace '\+', ' ')) } else { '' }
        $values[$key] = $value
    }
    $tool = [string]$values['tool']
    if ($tool -notin @('takeout','photos','passwords','email','bookmarks','contacts','converter')) { throw "Unsupported toolkit deep-link tool: $tool" }
    return [pscustomobject]@{ Tool = $tool; Path = [string]$values['path']; Plan = [string]$values['plan'] }
}

function Get-DgFirstProperty {
    param([AllowNull()]$Object, [Parameter(Mandatory=$true)][string[]]$Names)
    foreach ($name in $Names) {
        $value = Get-DgProperty $Object $name
        if ($null -ne $value -and -not ([string]::IsNullOrWhiteSpace([string]$value))) { return $value }
    }
    return $null
}

function ConvertTo-DgDouble {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    $number = 0.0
    if ([double]::TryParse(([string]$Value).Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return $number
    }
    return $null
}

function ConvertTo-DgDateTimeOffset {
    param([AllowNull()]$Value, [switch]$Nanos)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try {
        if ($Nanos -or ([string]$Value -match '^\d{15,}$')) {
            return [DateTimeOffset]::FromUnixTimeMilliseconds([long](([decimal]$Value) / 1000000))
        }
        if ([string]$Value -match '^\d{10}$') { return [DateTimeOffset]::FromUnixTimeSeconds([long]$Value) }
        return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
    } catch { return $null }
}

function Format-DgIsoDate {
    param([AllowNull()][DateTimeOffset]$Value)
    if ($null -eq $Value) { return $null }
    return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
}

function Find-DgPhotoMetadataFile {
    param([Parameter(Mandatory=$true)][string]$MediaPath, [object[]]$JsonFiles = @())
    $directory = Split-Path -Parent $MediaPath
    $name = [System.IO.Path]::GetFileName($MediaPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($MediaPath)
    $direct = @(
        "$MediaPath.json",
        ([System.IO.Path]::ChangeExtension($MediaPath, '.json')),
        (Join-Path $directory ($name + '.supplemental-metadata.json')),
        (Join-Path $directory ($base + '.supplemental-metadata.json')),
        (Join-Path $directory ($base + '.json'))
    )
    foreach ($candidate in $direct) { if (Test-Path -LiteralPath $candidate) { return $candidate } }
    $truncated = if ($base.Length -gt 32) { $base.Substring(0, 32) } else { $base }
    $matches = @($JsonFiles | Where-Object {
        $jsonName = $_.Name
        $jsonName -match [regex]::Escape($name) -or
        $jsonName -match [regex]::Escape($base) -or
        ($truncated.Length -ge 12 -and $jsonName -match [regex]::Escape($truncated))
    })
    if ($matches.Count -gt 0) {
        return ($matches | Sort-Object @{Expression={
            $jsonName = $_.Name
            if ($jsonName -ieq ($name + '.json')) { 0 }
            elseif ($jsonName -ieq ($base + '.json')) { 1 }
            elseif ($jsonName -match 'supplemental-metadata') { 2 }
            elseif ($jsonName -match [regex]::Escape($base)) { 3 }
            else { 4 }
        }}, Name | Select-Object -First 1).FullName
    }
    return $null
}

function Get-DgFilenameDate {
    param([Parameter(Mandatory=$true)][string]$MediaPath)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($MediaPath)
    $patterns = @(
        '(?<year>20\d{2})[-_](?<month>\d{2})[-_](?<day>\d{2})(?:[T _-](?<hour>\d{2})[-_:]?(?<minute>\d{2})[-_:]?(?<second>\d{2}))?',
        '(?<year>20\d{2})(?<month>\d{2})(?<day>\d{2})[_-]?(?<hour>\d{2})(?<minute>\d{2})(?<second>\d{2})?'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($stem, $pattern)
        if (-not $match.Success) { continue }
        try {
            $hour = if ($match.Groups['hour'].Success) { [int]$match.Groups['hour'].Value } else { 0 }
            $minute = if ($match.Groups['minute'].Success) { [int]$match.Groups['minute'].Value } else { 0 }
            $second = if ($match.Groups['second'].Success) { [int]$match.Groups['second'].Value } else { 0 }
            return [DateTimeOffset]::new([int]$match.Groups['year'].Value, [int]$match.Groups['month'].Value, [int]$match.Groups['day'].Value, $hour, $minute, $second, [TimeSpan]::Zero)
        } catch {}
    }
    return $null
}

function Get-DgPicasaMetadata {
    param([Parameter(Mandatory=$true)][string]$MediaPath)
    $directory = Split-Path -Parent $MediaPath
    $fileName = [System.IO.Path]::GetFileName($MediaPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($MediaPath)
    $iniPath = $null
    for ($i = 0; $i -lt 5 -and $directory; $i++) {
        foreach ($candidateName in @('.picasa.ini','Picasa.ini')) {
            $candidate = Join-Path $directory $candidateName
            if (Test-Path -LiteralPath $candidate) { $iniPath = $candidate; break }
        }
        if ($iniPath) { break }
        $parent = Split-Path -Parent $directory
        if ($parent -eq $directory) { break }
        $directory = $parent
    }
    if (-not $iniPath) { return $null }
    $section = $null; $values = @{}
    foreach ($line in (Get-Content -LiteralPath $iniPath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\[([^]]+)\]') {
            $section = $Matches[1]
            continue
        }
        if ($section -and $section -ieq $fileName -or $section -and $section -ieq $base -or $section -and $section -ieq ($base + '.jpg')) {
            if ($line -match '^([^=]+)=(.*)$') { $values[$Matches[1].Trim().ToLowerInvariant()] = $Matches[2].Trim() }
        }
    }
    if ($values.Count -eq 0) { return $null }
    return [pscustomobject]@{
        Caption = $values['caption']
        Date = (ConvertTo-DgDateTimeOffset $values['date'])
        Latitude = (ConvertTo-DgDouble $values['latitude'])
        Longitude = (ConvertTo-DgDouble $values['longitude'])
    }
}

function Write-DgXmpSidecar {
    param([Parameter(Mandatory=$true)][string]$MediaPath, [AllowNull()][DateTimeOffset]$Date, [AllowNull()]$Latitude, [AllowNull()]$Longitude, [AllowNull()][string]$Description)
    if ($null -eq $Date -and $null -eq $Latitude -and $null -eq $Longitude -and [string]::IsNullOrWhiteSpace($Description)) { return $null }
    $xmpPath = $MediaPath + '.xmp'
    $lines = @(
        '<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>',
        '<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="DeGoogler">',
        ' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">',
        '  <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/"'
    )
    if ($Date) { $lines += ('   xmp:CreateDate="' + (Format-DgIsoDate $Date) + '" xmp:ModifyDate="' + (Format-DgIsoDate $Date) + '" exif:DateTimeOriginal="' + (Format-DgIsoDate $Date) + '"') }
    if ($Latitude -ne $null) { $lines += ('   exif:GPSLatitude="' + $Latitude + '"') }
    if ($Longitude -ne $null) { $lines += ('   exif:GPSLongitude="' + $Longitude + '"') }
    $lines += '  >'
    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $safe = [System.Security.SecurityElement]::Escape($Description)
        $lines += ('   <dc:description><rdf:Alt><rdf:li xml:lang="x-default">' + $safe + '</rdf:li></rdf:Alt></dc:description>')
    }
    $lines += @('  </rdf:Description>', ' </rdf:RDF>', '</x:xmpmeta>', '<?xpacket end="w"?>')
    Write-DgAtomicText -Path $xmpPath -Content ($lines -join "`n")
    return $xmpPath
}

function Get-DgBurstKey {
    param([Parameter(Mandatory=$true)][string]$MediaPath, [AllowNull()][DateTimeOffset]$Date)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($MediaPath)
    $normalized = $stem -replace '(?i)(?:\(\d+\)|[-_](?:burst|img|image)?\d+)$', ''
    if ($normalized -eq $stem -or $null -eq $Date) { return $null }
    return ($normalized.ToLowerInvariant() + '|' + $Date.ToUniversalTime().ToString('yyyyMMddHHmmss'))
}

function Convert-DgKeepTakeout {
    param([Parameter(Mandatory=$true)][string]$InputPath, [Parameter(Mandatory=$true)][string]$OutputPath)
    $files = @(Get-DgInputFiles -InputPath $InputPath -Extensions @('.json'))
    $written = 0; $skipped = 0
    foreach ($file in $files) {
        try { $note = (Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop } catch { $skipped++; continue }
        if ($null -eq $note -or $null -eq (Get-DgFirstProperty $note @('title','textContent','listContent','labels'))) { $skipped++; continue }
        $title = [string](Get-DgFirstProperty $note @('title','name'))
        if ([string]::IsNullOrWhiteSpace($title)) { $title = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }
        $labels = @($note.labels | ForEach-Object { [string](Get-DgFirstProperty $_ @('name','label')) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $folder = $OutputPath
        if ($labels.Count -gt 0) {
            foreach ($label in $labels) { $folder = Join-Path $folder (ConvertTo-DgSafeFileName $label 'Unlabeled') }
        } else { $folder = Join-Path $folder '_Unlabeled' }
        $stamp = ConvertTo-DgDateTimeOffset (Get-DgFirstProperty $note @('userEditedTimestampUsec','createdTimestampUsec'))
        $front = @(
            '---',
            ('title: "' + ($title -replace '"','\\"') + '"'),
            ('source: "' + $file.Name + '"'),
            ('labels: [' + (($labels | ForEach-Object { '"' + ($_ -replace '"','\\"') + '"' }) -join ', ') + ']'),
            ('trashed: ' + [bool]$note.isTrashed),
            ('archived: ' + [bool]$note.isArchived)
        )
        if ($stamp) { $front += ('updated: ' + (Format-DgIsoDate $stamp)) }
        $front += '---'
        $body = [string]$note.textContent
        $list = @($note.listContent)
        if ($list.Count -gt 0) {
            $items = @($list | ForEach-Object {
                $text = [string](Get-DgFirstProperty $_ @('text','content'))
                if ([string]::IsNullOrWhiteSpace($text)) { return }
                $checked = [bool](Get-DgFirstProperty $_ @('isChecked','checked'))
                '- [' + (if ($checked) { 'x' } else { ' ' }) + '] ' + $text
            } | Where-Object { $_ })
            if ($items.Count -gt 0) { $body = ($items -join "`n") }
        }
        if ([string]::IsNullOrWhiteSpace($body)) { $body = '_Empty note_' }
        $attachments = @($note.attachments | ForEach-Object { [string](Get-DgFirstProperty $_ @('filePath','name')) } | Where-Object { $_ })
        if ($attachments.Count -gt 0) { $body += "`n`nAttachments:`n" + (($attachments | ForEach-Object { '- ' + $_ }) -join "`n") }
        $path = Join-Path $folder ((ConvertTo-DgSafeFileName $title 'untitled') + '.md')
        $suffix = 1
        while (Test-Path -LiteralPath $path) { $path = Join-Path $folder ((ConvertTo-DgSafeFileName $title 'untitled') + " ($suffix).md"); $suffix++ }
        Write-DgAtomicText -Path $path -Content (($front -join "`n") + "`n`n" + $body.Trim() + "`n")
        $written++
    }
    return [pscustomobject]@{ Converter = 'Keep'; InputFiles = $files.Count; Written = $written; Skipped = $skipped; Output = $OutputPath }
}

function Get-DgFitRecords {
    param([AllowNull()]$Node, [string]$SourceName = '')
    $result = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Node) { return $result.ToArray() }
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string]) -and -not ($Node -is [System.Collections.IDictionary])) {
        foreach ($child in $Node) { foreach ($record in (Get-DgFitRecords $child $SourceName)) { $result.Add($record) } }
        return $result.ToArray()
    }
    $startRaw = Get-DgFirstProperty $Node @('startTimeNanos','startTime','startDate','timestamp')
    $endRaw = Get-DgFirstProperty $Node @('endTimeNanos','endTime','endDate')
    $start = if ([string]$startRaw -match '^\d{15,}$') { ConvertTo-DgDateTimeOffset $startRaw -Nanos } else { ConvertTo-DgDateTimeOffset $startRaw }
    $end = if ([string]$endRaw -match '^\d{15,}$') { ConvertTo-DgDateTimeOffset $endRaw -Nanos } else { ConvertTo-DgDateTimeOffset $endRaw }
    if ($start) {
        $value = Get-DgFirstProperty $Node @('value','quantity','distance','calories','steps')
        if ($value -is [array]) { $value = $value | Select-Object -First 1 }
        if ($value -isnot [string] -and $value -isnot [ValueType]) { $value = Get-DgFirstProperty $value @('fpVal','intVal','doubleVal','value','rawValue') }
        $lat = ConvertTo-DgDouble (Get-DgFirstProperty $Node @('latitude','lat'))
        $lon = ConvertTo-DgDouble (Get-DgFirstProperty $Node @('longitude','lon','lng'))
        $alt = ConvertTo-DgDouble (Get-DgFirstProperty $Node @('altitude','elevation'))
        $activity = [string](Get-DgFirstProperty $Node @('activityType','activity','dataType','name'))
        $result.Add([pscustomobject]@{ Start = $start; End = $(if ($end) { $end } else { $start.AddMinutes(1) }); Value = (ConvertTo-DgDouble $value); Latitude = $lat; Longitude = $lon; Altitude = $alt; Activity = $(if ($activity) { $activity } else { $SourceName }) })
    }
    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Value -is [pscustomobject] -or ($property.Value -is [System.Collections.IEnumerable] -and -not ($property.Value -is [string]))) {
            foreach ($record in (Get-DgFitRecords $property.Value $SourceName)) { $result.Add($record) }
        }
    }
    return $result.ToArray()
}

function Convert-DgFitTakeout {
    param([Parameter(Mandatory=$true)][string]$InputPath, [Parameter(Mandatory=$true)][string]$OutputPath)
    $files = @(Get-DgInputFiles -InputPath $InputPath -Extensions @('.json'))
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in $files) {
        try { $json = (Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        foreach ($record in (Get-DgFitRecords $json ([System.IO.Path]::GetFileNameWithoutExtension($file.Name)))) { $records.Add($record) }
    }
    $records = @($records | Sort-Object Start, End -Unique)
    if (-not (Test-Path -LiteralPath $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $health = New-Object System.Text.StringBuilder
    [void]$health.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$health.AppendLine('<HealthData locale="en_US"><ExportDate value="' + (Format-DgIsoDate ([DateTimeOffset]::Now)) + '"/>')
    $tcx = New-Object System.Text.StringBuilder
    [void]$tcx.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$tcx.AppendLine('<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><Activities>')
    $index = 0
    foreach ($record in $records) {
        $index++
        $start = Format-DgIsoDate $record.Start; $end = Format-DgIsoDate $record.End
        $duration = [math]::Max(0, ($record.End - $record.Start).TotalSeconds)
        $activity = ConvertTo-DgSafeFileName ([string]$record.Activity) 'Other'
        $healthType = 'HKWorkoutActivityTypeOther'
        if ($activity -match 'walk') { $healthType = 'HKWorkoutActivityTypeWalking' } elseif ($activity -match 'run|jog') { $healthType = 'HKWorkoutActivityTypeRunning' } elseif ($activity -match 'bike|cycl') { $healthType = 'HKWorkoutActivityTypeCycling' } elseif ($activity -match 'swim') { $healthType = 'HKWorkoutActivityTypeSwimming' }
        [void]$health.AppendLine('<Workout workoutActivityType="' + $healthType + '" duration="' + ('{0:0.###}' -f $duration) + '" startDate="' + $start + '" endDate="' + $end + '"/>')
        [void]$tcx.AppendLine('<Activity Sport="Other"><Id>' + $start + '</Id><Lap StartTime="' + $start + '"><TotalTimeSeconds>' + ('{0:0.###}' -f $duration) + '</TotalTimeSeconds><Track><Trackpoint><Time>' + $start + '</Time>')
        if ($record.Latitude -ne $null -and $record.Longitude -ne $null) { [void]$tcx.AppendLine('<Position><LatitudeDegrees>' + $record.Latitude + '</LatitudeDegrees><LongitudeDegrees>' + $record.Longitude + '</LongitudeDegrees></Position>') }
        if ($record.Altitude -ne $null) { [void]$tcx.AppendLine('<AltitudeMeters>' + $record.Altitude + '</AltitudeMeters>') }
        [void]$tcx.AppendLine('</Trackpoint></Track></Lap></Activity>')
    }
    [void]$health.AppendLine('</HealthData>'); [void]$tcx.AppendLine('</Activities></TrainingCenterDatabase>')
    Write-DgAtomicText -Path (Join-Path $OutputPath 'fit-apple-health.xml') -Content $health.ToString()
    Write-DgAtomicText -Path (Join-Path $OutputPath 'fit-activities.tcx') -Content $tcx.ToString()
    return [pscustomobject]@{ Converter = 'Fit'; InputFiles = $files.Count; Records = $records.Count; Written = 2; Output = $OutputPath }
}

function Get-DgMapRecords {
    param([AllowNull()]$Node, [string]$FallbackName = 'Saved place')
    $result = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Node) { return $result.ToArray() }
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string]) -and -not ($Node -is [System.Collections.IDictionary])) {
        foreach ($child in $Node) { foreach ($item in (Get-DgMapRecords $child $FallbackName)) { $result.Add($item) } }
        return $result.ToArray()
    }
    $lat = ConvertTo-DgDouble (Get-DgFirstProperty $Node @('latitude','lat'))
    $lon = ConvertTo-DgDouble (Get-DgFirstProperty $Node @('longitude','lng','lon'))
    $location = Get-DgFirstProperty $Node @('location','coordinates','geometry')
    if ($null -ne $location -and ($lat -eq $null -or $lon -eq $null)) {
        if ($location.coordinates) { $coords = @($location.coordinates); if ($coords.Count -ge 2) { $lon = ConvertTo-DgDouble $coords[0]; $lat = ConvertTo-DgDouble $coords[1] } }
        if ($lat -eq $null) { $lat = ConvertTo-DgDouble (Get-DgFirstProperty $location @('latitude','lat')) }
        if ($lon -eq $null) { $lon = ConvertTo-DgDouble (Get-DgFirstProperty $location @('longitude','lng','lon')) }
    }
    if ($lat -eq $null -or $lon -eq $null) {
        $geo = [string](Get-DgFirstProperty $Node @('geo','coordinates'))
        if ($geo -match '(-?\d+(?:\.\d+)?)[, ]+(-?\d+(?:\.\d+)?)') { $lat = ConvertTo-DgDouble $Matches[1]; $lon = ConvertTo-DgDouble $Matches[2] }
    }
    if ($lat -ne $null -and $lon -ne $null -and $lat -ge -90 -and $lat -le 90 -and $lon -ge -180 -and $lon -le 180) {
        $name = [string](Get-DgFirstProperty $Node @('title','name','label','description'))
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $FallbackName }
        $url = [string](Get-DgFirstProperty $Node @('url','googleMapsUrl','link'))
        $result.Add([pscustomobject]@{ Name = $name; Latitude = $lat; Longitude = $lon; Url = $url })
    }
    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Value -is [pscustomobject] -or ($property.Value -is [System.Collections.IEnumerable] -and -not ($property.Value -is [string]))) {
            foreach ($item in (Get-DgMapRecords $property.Value $FallbackName)) { $result.Add($item) }
        }
    }
    return $result.ToArray()
}

function Convert-DgMapsSavedPlaces {
    param([Parameter(Mandatory=$true)][string]$InputPath, [Parameter(Mandatory=$true)][string]$OutputPath)
    $records = New-Object System.Collections.Generic.List[object]
    $files = @(Get-DgInputFiles -InputPath $InputPath -Extensions @('.json','.csv'))
    foreach ($file in $files) {
        if ($file.Extension -ieq '.csv') {
            foreach ($row in @(Import-Csv -LiteralPath $file.FullName)) {
                $lat = ConvertTo-DgDouble (Get-DgFirstProperty $row @('latitude','lat','Latitude'))
                $lon = ConvertTo-DgDouble (Get-DgFirstProperty $row @('longitude','lng','lon','Longitude'))
                if ($lat -ne $null -and $lon -ne $null) { $records.Add([pscustomobject]@{ Name = [string](Get-DgFirstProperty $row @('name','title','Name')); Latitude = $lat; Longitude = $lon; Url = [string](Get-DgFirstProperty $row @('url','link')) }) }
            }
        } else {
            try { $json = (Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            foreach ($item in (Get-DgMapRecords $json ([System.IO.Path]::GetFileNameWithoutExtension($file.Name)))) { $records.Add($item) }
        }
    }
    $records = @($records | Group-Object { '{0:0.######}|{1:0.######}|{2}' -f $_.Latitude, $_.Longitude, $_.Name } | ForEach-Object { $_.Group[0] })
    if (-not (Test-Path -LiteralPath $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $features = @($records | ForEach-Object { [pscustomobject]@{ type = 'Feature'; properties = [pscustomobject]@{ name = $_.Name; url = $_.Url }; geometry = [pscustomobject]@{ type = 'Point'; coordinates = @([double]$_.Longitude, [double]$_.Latitude) } } })
    $geojson = [pscustomobject]@{ type = 'FeatureCollection'; features = $features } | ConvertTo-Json -Depth 10
    $gpx = New-Object System.Text.StringBuilder; [void]$gpx.AppendLine('<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="DeGoogler" xmlns="http://www.topografix.com/GPX/1/1">')
    $kml = New-Object System.Text.StringBuilder; [void]$kml.AppendLine('<?xml version="1.0" encoding="UTF-8"?><kml xmlns="http://www.opengis.net/kml/2.2"><Document>')
    foreach ($record in $records) {
        $name = [System.Security.SecurityElement]::Escape([string]$record.Name); $url = [System.Security.SecurityElement]::Escape([string]$record.Url)
        [void]$gpx.AppendLine('<wpt lat="' + $record.Latitude + '" lon="' + $record.Longitude + '"><name>' + $name + '</name>' + $(if ($url) { '<link href="' + $url + '"/>' } else { '' }) + '</wpt>')
        [void]$kml.AppendLine('<Placemark><name>' + $name + '</name>' + $(if ($url) { '<description>' + $url + '</description>' } else { '' }) + '<Point><coordinates>' + $record.Longitude + ',' + $record.Latitude + ',0</coordinates></Point></Placemark>')
    }
    [void]$gpx.AppendLine('</gpx>'); [void]$kml.AppendLine('</Document></kml>')
    Write-DgAtomicText -Path (Join-Path $OutputPath 'saved-places.geojson') -Content $geojson
    Write-DgAtomicText -Path (Join-Path $OutputPath 'saved-places.gpx') -Content $gpx.ToString()
    Write-DgAtomicText -Path (Join-Path $OutputPath 'saved-places.kml') -Content $kml.ToString()
    return [pscustomobject]@{ Converter = 'Maps'; InputFiles = $files.Count; Records = $records.Count; Written = 3; Output = $OutputPath }
}

function Get-DgMboxMessages {
    param([Parameter(Mandatory=$true)][string]$Path)
    $messages = New-Object System.Collections.Generic.List[object]
    $reader = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::UTF8, $true)
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line -match '^From (?:\S+\s+)?\w{3}\s') {
                if ($lines.Count -gt 0) { $messages.Add((ConvertFrom-DgMboxLines $lines)); $lines = New-Object System.Collections.Generic.List[string] }
            }
            $lines.Add($line)
        }
        if ($lines.Count -gt 0) { $messages.Add((ConvertFrom-DgMboxLines $lines)) }
    } finally { $reader.Dispose() }
    return $messages.ToArray()
}

function ConvertFrom-DgMboxLines {
    param([System.Collections.Generic.List[string]]$Lines)
    $header = @{}; $bodyIndex = $Lines.Count; $current = $null
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { $bodyIndex = $i + 1; break }
        if ($line -match '^\s' -and $current) { $header[$current] = ($header[$current] + ' ' + $line.Trim()); continue }
        if ($line -match '^([^:]+):\s*(.*)$') { $current = $Matches[1].ToLowerInvariant(); $header[$current] = $Matches[2] }
    }
    $body = if ($bodyIndex -lt $Lines.Count) { ($Lines[$bodyIndex..($Lines.Count - 1)] -join "`n") } else { '' }
    [pscustomobject]@{ id = [guid]::NewGuid().ToString(); date = $header['date']; from = $header['from']; to = $header['to']; cc = $header['cc']; subject = $header['subject']; body = $body; headers = $header }
}

function Convert-DgChatMbox {
    param([Parameter(Mandatory=$true)][string]$InputPath, [Parameter(Mandatory=$true)][string]$OutputPath)
    $files = @(Get-DgInputFiles -InputPath $InputPath -Extensions @('.mbox','.mbx','.txt'))
    $messages = New-Object System.Collections.Generic.List[object]
    foreach ($file in $files) { foreach ($message in (Get-DgMboxMessages $file.FullName)) { $messages.Add($message) } }
    if (-not (Test-Path -LiteralPath $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $base = [pscustomobject]@{ schema = 'https://sysadmindoc.github.io/DeGoogler/chat.schema.json'; version = '1.0.0'; sourceFiles = @($files | ForEach-Object { $_.Name }); messages = $messages.ToArray() }
    foreach ($format in @('matrix','signal')) {
        $payload = [pscustomobject]@{ format = $format; schema = $base.schema; version = $base.version; messages = $messages.ToArray() } | ConvertTo-Json -Depth 8
        Write-DgAtomicText -Path (Join-Path $OutputPath ("chat-$format.json")) -Content $payload
    }
    Write-DgAtomicText -Path (Join-Path $OutputPath 'chat-migration.json') -Content ($base | ConvertTo-Json -Depth 8)
    return [pscustomobject]@{ Converter = 'Chat'; InputFiles = $files.Count; Messages = $messages.Count; Written = 3; Output = $OutputPath }
}
