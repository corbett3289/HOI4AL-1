param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = "Stop"

$modRoot = Join-Path $ProjectRoot "Mod"
$errors = [System.Collections.Generic.List[string]]::new()
$checks = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $script:errors.Add($Message)
}

function Add-Pass {
    param([string]$Message)
    $script:checks.Add($Message)
}

function Test-DdsArgbContract {
    param(
        [Parameter(Mandatory)] [string]$RelativePath,
        [Parameter(Mandatory)] [int]$Width,
        [Parameter(Mandatory)] [int]$Height
    )

    $path = Join-Path $script:modRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing contracted DDS: $RelativePath"
        return
    }

    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 128 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DDS ') {
        Add-Failure "$RelativePath is not a valid DDS container."
        return
    }

    $actualHeight = [BitConverter]::ToInt32($bytes, 12)
    $actualWidth = [BitConverter]::ToInt32($bytes, 16)
    $mipmapCount = [BitConverter]::ToInt32($bytes, 28)
    $pixelFlags = [BitConverter]::ToUInt32($bytes, 80)
    $fourCc = [BitConverter]::ToUInt32($bytes, 84)
    $rgbBits = [BitConverter]::ToInt32($bytes, 88)
    $redMask = [BitConverter]::ToUInt32($bytes, 92)
    $greenMask = [BitConverter]::ToUInt32($bytes, 96)
    $blueMask = [BitConverter]::ToUInt32($bytes, 100)
    $alphaMask = [BitConverter]::ToUInt32($bytes, 104)
    $expectedLength = 128L + ([long]$Width * [long]$Height * 4L)

    if ($actualWidth -ne $Width -or $actualHeight -ne $Height) {
        Add-Failure "$RelativePath is ${actualWidth}x${actualHeight}; expected ${Width}x${Height}."
    }
    if ($mipmapCount -ne 0 -or $pixelFlags -ne 0x41 -or $fourCc -ne 0 -or $rgbBits -ne 32 -or
        $redMask -ne 0x00FF0000 -or $greenMask -ne 0x0000FF00 -or
        $blueMask -ne 0x000000FF -or $alphaMask -ne 4278190080) {
        Add-Failure "$RelativePath is not an unmipped 32-bit BGRA/ARGB8888 DDS with full alpha."
    }
    if ($bytes.LongLength -ne $expectedLength) {
        Add-Failure "$RelativePath is $($bytes.LongLength) bytes; expected exact ARGB payload length $expectedLength."
    }
}

function Test-DdsHorizontalFramesDiffer {
    param(
        [Parameter(Mandatory)] [string]$RelativePath,
        [Parameter(Mandatory)] [int]$Width,
        [Parameter(Mandatory)] [int]$Height
    )

    $path = Join-Path $script:modRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return
    }

    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.LongLength -lt 128L + ([long]$Width * [long]$Height * 4L)) {
        return
    }
    $frameWidth = [int][Math]::Floor($Width / 2)
    $different = $false
    for ($y = 0; $y -lt $Height -and -not $different; $y++) {
        for ($x = 0; $x -lt $frameWidth -and -not $different; $x++) {
            $leftOffset = 128 + (($y * $Width + $x) * 4)
            $rightOffset = 128 + (($y * $Width + $frameWidth + $x) * 4)
            for ($channel = 0; $channel -lt 4; $channel++) {
                if ($bytes[$leftOffset + $channel] -ne $bytes[$rightOffset + $channel]) {
                    $different = $true
                    break
                }
            }
        }
    }

    if (-not $different) {
        Add-Failure "$RelativePath duplicates its normal agency-logo frame into the hover/highlight frame."
    }
}

function Test-GfxSpriteContract {
    param(
        [Parameter(Mandatory)] [string]$Text,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Texture,
        [int]$Frames = 0,
        [switch]$RequireLegacyLazyLoad
    )

    $spriteBlocks = [regex]::Matches($Text, '(?is)\bSpriteType\s*=\s*\{.*?\}')
    $namePattern = '(?i)(?:^|\s)name\s*=\s*"' + [regex]::Escape($Name) + '"(?=\s|\})'
    $matchingBlocks = @($spriteBlocks | Where-Object {
        $_.Value -match $namePattern
    })
    if ($matchingBlocks.Count -ne 1) {
        Add-Failure "GFX sprite $Name must be defined exactly once; found $($matchingBlocks.Count)."
        return
    }

    $block = $matchingBlocks[0].Value
    if ([regex]::Matches($block, '(?i)(?:^|\s)texturefile\s*=\s*"' + [regex]::Escape($Texture) + '"(?=\s|\})').Count -ne 1) {
        Add-Failure "GFX sprite $Name must bind exact texture path $Texture."
    }
    $frameMatches = [regex]::Matches($block, '(?i)(?:^|\s)noOfFrames\s*=\s*(\d+)(?=\s|\})')
    if ($Frames -gt 0) {
        if ($frameMatches.Count -ne 1 -or [int]$frameMatches[0].Groups[1].Value -ne $Frames) {
            Add-Failure "GFX sprite $Name must declare noOfFrames = $Frames exactly once."
        }
    }
    elseif ($frameMatches.Count -ne 0) {
        Add-Failure "One-frame GFX sprite $Name must omit noOfFrames."
    }
    if ($RequireLegacyLazyLoad -and
        [regex]::Matches($block, '(?i)(?:^|\s)legacy_lazy_load\s*=\s*no(?=\s|\})').Count -ne 1) {
        Add-Failure "Texticon sprite $Name must declare legacy_lazy_load = no."
    }
}

function Get-ClausewitzAssignedBlocks {
    param(
        [Parameter(Mandatory)] [string]$Text,
        [Parameter(Mandatory)] [string]$Assignment
    )

    $blocks = [System.Collections.Generic.List[string]]::new()
    $assignmentPattern = '(?m)^\s*' + [regex]::Escape($Assignment) + '\s*=\s*\{'
    foreach ($assignmentMatch in [regex]::Matches($Text, $assignmentPattern)) {
        $openingBrace = $Text.IndexOf('{', $assignmentMatch.Index)
        if ($openingBrace -lt 0) {
            continue
        }

        $depth = 0
        $inQuote = $false
        $escaped = $false
        $inComment = $false
        for ($index = $openingBrace; $index -lt $Text.Length; $index++) {
            $character = $Text[$index]

            if ($inComment) {
                if ($character -eq "`n") {
                    $inComment = $false
                }
                continue
            }

            if ($inQuote) {
                if ($escaped) {
                    $escaped = $false
                }
                elseif ($character -eq '\') {
                    $escaped = $true
                }
                elseif ($character -eq '"') {
                    $inQuote = $false
                }
                continue
            }

            if ($character -eq '#') {
                $inComment = $true
            }
            elseif ($character -eq '"') {
                $inQuote = $true
            }
            elseif ($character -eq '{') {
                $depth++
            }
            elseif ($character -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $blocks.Add($Text.Substring($assignmentMatch.Index, $index - $assignmentMatch.Index + 1))
                    break
                }
            }
        }
    }

    return @($blocks)
}

function Test-ClausewitzSyntax {
    param([string]$Path)

    $text = [IO.File]::ReadAllText($Path)
    $depth = 0
    $inQuote = $false
    $escaped = $false
    $line = 1

    for ($i = 0; $i -lt $text.Length; $i++) {
        $character = $text[$i]

        if ($character -eq "`n") {
            $line++
        }

        if (-not $inQuote -and $character -eq '#') {
            while ($i -lt $text.Length -and $text[$i] -ne "`n") {
                $i++
            }
            $line++
            continue
        }

        if ($inQuote) {
            if ($escaped) {
                $escaped = $false
            }
            elseif ($character -eq '\') {
                $escaped = $true
            }
            elseif ($character -eq '"') {
                $inQuote = $false
            }
            continue
        }

        if ($character -eq '"') {
            $inQuote = $true
        }
        elseif ($character -eq '{') {
            $depth++
        }
        elseif ($character -eq '}') {
            $depth--
            if ($depth -lt 0) {
                Add-Failure "$Path has an unmatched closing brace near line $line."
                return
            }
        }
    }

    if ($inQuote) {
        Add-Failure "$Path has an unterminated quoted string."
    }
    if ($depth -ne 0) {
        Add-Failure "$Path has a final brace depth of $depth."
    }
}

if (-not (Test-Path -LiteralPath $modRoot -PathType Container)) {
    throw "Mod directory not found: $modRoot"
}

$clausewitzFiles = Get-ChildItem -LiteralPath $modRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.txt', '.gfx', '.gui', '.asset', '.mod') }
foreach ($file in $clausewitzFiles) {
    Test-ClausewitzSyntax -Path $file.FullName
}
if ($errors.Count -eq 0) {
    Add-Pass "Balanced braces and quotes in $($clausewitzFiles.Count) Clausewitz files"
}

$localisationKeys = @{}
$localisationFiles = Get-ChildItem -LiteralPath (Join-Path $modRoot 'localisation') -Recurse -File -Filter '*.yml'
foreach ($file in $localisationFiles) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        Add-Failure "$($file.FullName) is not UTF-8 with BOM."
    }

    $lines = [IO.File]::ReadAllLines($file.FullName)
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne 'l_english:') {
        Add-Failure "$($file.FullName) does not begin with l_english:."
    }

    for ($lineIndex = 1; $lineIndex -lt $lines.Count; $lineIndex++) {
        if ($lines[$lineIndex] -match '^\s*([^\s:#]+):\d*\s') {
            $key = $Matches[1]
            if ($localisationKeys.ContainsKey($key)) {
                Add-Failure "Duplicate localisation key $key in $($file.Name) and $($localisationKeys[$key])."
            }
            else {
                $localisationKeys[$key] = $file.Name
            }
        }
	}
}
$allEnglishLocalisationText = ($localisationFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
Add-Pass "Checked $($localisationFiles.Count) UTF-8 BOM localisation files and $($localisationKeys.Count) unique keys"

$textureReferences = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$interfaceFiles = Get-ChildItem -LiteralPath (Join-Path $modRoot 'interface') -File -Filter '*.gfx'
foreach ($file in $interfaceFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($match in [regex]::Matches($text, 'texturefile\s*=\s*"([^"]+)"', 'IgnoreCase')) {
        [void]$textureReferences.Add($match.Groups[1].Value)
    }
}
foreach ($reference in $textureReferences) {
    $candidate = Join-Path $modRoot ($reference -replace '/', '\')
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        Add-Failure "Missing GFX texture: $reference"
    }
}
Add-Pass "Resolved $($textureReferences.Count) unique GFX texture references"

$ddsFiles = Get-ChildItem -LiteralPath (Join-Path $modRoot 'gfx') -Recurse -File -Filter '*.dds'
foreach ($file in $ddsFiles) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 128 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DDS ') {
        Add-Failure "$($file.FullName) is not a valid DDS container."
        continue
    }
    $height = [BitConverter]::ToInt32($bytes, 12)
    $width = [BitConverter]::ToInt32($bytes, 16)
    $fourCc = [BitConverter]::ToUInt32($bytes, 84)
    $rgbBits = [BitConverter]::ToInt32($bytes, 88)
    if ($width -le 0 -or $height -le 0) {
        Add-Failure "$($file.FullName) has invalid DDS dimensions ${width}x${height}."
    }
    if ($fourCc -eq 0 -and $rgbBits -eq 32) {
        $minimumLength = 128L + ([long]$width * [long]$height * 4L)
        if ($bytes.LongLength -lt $minimumLength) {
            Add-Failure "$($file.FullName) is truncated: $($bytes.LongLength) bytes, expected at least $minimumLength."
        }
    }
}
Add-Pass "Validated $($ddsFiles.Count) DDS headers and payload sizes"

$expectedFlags = @(
    @{ Path = 'gfx\flags\XAC.tga'; Width = 82; Height = 52 },
    @{ Path = 'gfx\flags\medium\XAC.tga'; Width = 41; Height = 26 },
    @{ Path = 'gfx\flags\small\XAC.tga'; Width = 10; Height = 7 }
)
foreach ($flag in $expectedFlags) {
    $path = Join-Path $modRoot $flag.Path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing flag: $path"
        continue
    }
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 18) {
        Add-Failure "$path is too short to be TGA."
        continue
    }
	$width = [BitConverter]::ToUInt16($bytes, 12)
	$height = [BitConverter]::ToUInt16($bytes, 14)
	$depth = $bytes[16]
	$imageType = $bytes[2]
	$descriptor = $bytes[17]
	$expectedLength = 18L + ([long]$flag.Width * [long]$flag.Height * 4L)
	if ($width -ne $flag.Width -or $height -ne $flag.Height -or $depth -ne 32) {
		Add-Failure "$path is ${width}x${height} at $depth bpp; expected $($flag.Width)x$($flag.Height) at 32 bpp."
	}
	if ($imageType -ne 2 -or ($descriptor -band 0x0F) -ne 8 -or ($descriptor -band 0x20) -eq 0) {
		Add-Failure "$path is not an uncompressed, top-origin TGA with eight alpha bits."
	}
	if ($bytes.LongLength -lt $expectedLength) {
		Add-Failure "$path is truncated: $($bytes.LongLength) bytes, expected at least $expectedLength."
	}
}
Add-Pass "Validated all three XAC flags as 32bpp BGRA TGA"

$expectedBitmapProperties = @(
    @{ Name = 'provinces.bmp'; Width = 5632; Height = 2048; Bpp = 24 },
    @{ Name = 'heightmap.bmp'; Width = 5632; Height = 2048; Bpp = 8 },
    @{ Name = 'terrain.bmp'; Width = 5632; Height = 2048; Bpp = 8 },
    @{ Name = 'rivers.bmp'; Width = 5632; Height = 2048; Bpp = 8 }
)
foreach ($expected in $expectedBitmapProperties) {
    $path = Join-Path $modRoot "map\$($expected.Name)"
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 54 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 2) -ne 'BM') {
        Add-Failure "$path is not a Windows BMP."
        continue
    }
    $width = [BitConverter]::ToInt32($bytes, 18)
    $height = [Math]::Abs([BitConverter]::ToInt32($bytes, 22))
    $bpp = [BitConverter]::ToUInt16($bytes, 28)
    if ($width -ne $expected.Width -or $height -ne $expected.Height -or $bpp -ne $expected.Bpp) {
        Add-Failure "$path is ${width}x${height} at $bpp bpp; expected $($expected.Width)x$($expected.Height) at $($expected.Bpp) bpp."
    }
}
Add-Pass "Validated province, height, terrain, and river bitmap formats"

try {
	Add-Type -AssemblyName System.Drawing.Common -ErrorAction Stop
}
catch {
	Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}
$thumbnailPath = Join-Path $modRoot 'thumbnail.png'
if (-not (Test-Path -LiteralPath $thumbnailPath -PathType Leaf)) {
	Add-Failure "Missing Steam Workshop thumbnail: $thumbnailPath"
}
else {
	$thumbnail = [System.Drawing.Image]::FromFile($thumbnailPath)
	try {
		if ($thumbnail.Width -ne 512 -or $thumbnail.Height -ne 512) {
			Add-Failure "Workshop thumbnail is $($thumbnail.Width)x$($thumbnail.Height); expected 512x512."
		}
	}
	finally {
		$thumbnail.Dispose()
	}
	if ((Get-Item -LiteralPath $thumbnailPath).Length -gt 1MB) {
		Add-Failure "Workshop thumbnail exceeds the 1 MiB upload-safety target."
	}
}
Add-Pass "Validated the 512x512 Workshop thumbnail and upload-safe file size"

$provinceBitmapPath = Join-Path $modRoot 'map\provinces.bmp'
$buildingPath = Join-Path $modRoot 'map\buildings.txt'
$buildingLines = [IO.File]::ReadAllLines($buildingPath)
$provinceBitmap = [System.Drawing.Bitmap]::new($provinceBitmapPath)
try {
    $expectedColor = [System.Drawing.Color]::FromArgb(211, 90, 211)
    $centerColor = $provinceBitmap.GetPixel(1146, 1875)
    if ($centerColor.ToArgb() -ne $expectedColor.ToArgb()) {
        Add-Failure "Pale Anchorage center pixel is RGB $($centerColor.R),$($centerColor.G),$($centerColor.B), not 211,90,211."
    }
    foreach ($point in @(@(1137,1875), @(1155,1875), @(1146,1869), @(1146,1881))) {
        $color = $provinceBitmap.GetPixel($point[0], $point[1])
        if ($color.ToArgb() -ne $expectedColor.ToArgb()) {
            Add-Failure "Pale Anchorage boundary pixel $($point[0]),$($point[1]) has the wrong province color."
        }
    }

    $locatorChecks = @(
        [pscustomobject]@{
            Type = 'naval_base_spawn'
            ExpectedRow = '1082;naval_base_spawn;1138.00;9.80;172.00;-1.57;601'
            ExpectedColor = [System.Drawing.Color]::FromArgb(211, 90, 211)
            ExpectedProvince = 13414
        },
        [pscustomobject]@{
            Type = 'floating_harbor'
            ExpectedRow = '1082;floating_harbor;1136.00;9.80;175.00;-1.82;13414'
            ExpectedColor = [System.Drawing.Color]::FromArgb(3, 8, 236)
            ExpectedProvince = 601
        },
        [pscustomobject]@{
            Type = 'naval_headquarters'
            ExpectedRow = '1082;naval_headquarters;1139.00;9.80;173.00;1.57;0'
            ExpectedColor = [System.Drawing.Color]::FromArgb(211, 90, 211)
            ExpectedProvince = 13414
        }
    )

    foreach ($locator in $locatorChecks) {
        $matchingRows = @($buildingLines | Where-Object { $_ -like "1082;$($locator.Type);*" })
        if ($matchingRows.Count -ne 1) {
            Add-Failure "State 1082 has $($matchingRows.Count) $($locator.Type) locator rows; expected one."
            continue
        }
        if ($matchingRows[0] -cne $locator.ExpectedRow) {
            Add-Failure "$($locator.Type) locator is '$($matchingRows[0])'; expected '$($locator.ExpectedRow)'."
        }

        $fields = $matchingRows[0].Split(';')
        if ($fields.Count -ne 7) {
            Add-Failure "$($locator.Type) locator has $($fields.Count) fields; expected seven."
            continue
        }
        try {
            $worldX = [double]::Parse($fields[2], [Globalization.CultureInfo]::InvariantCulture)
            $worldZ = [double]::Parse($fields[4], [Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            Add-Failure "$($locator.Type) locator has an invalid X or Z coordinate."
            continue
        }

        $bitmapX = [int][Math]::Round($worldX)
        # Clausewitz world Z maps to a top-down BMP row with a zero-based
        # vertical flip. The -1 is essential: height-Z samples the next row.
        $bitmapY = $provinceBitmap.Height - 1 - [int][Math]::Round($worldZ)
        if ($bitmapX -lt 0 -or $bitmapX -ge $provinceBitmap.Width -or
            $bitmapY -lt 0 -or $bitmapY -ge $provinceBitmap.Height) {
            Add-Failure "$($locator.Type) maps outside provinces.bmp at $bitmapX,$bitmapY."
            continue
        }

        $locatorColor = $provinceBitmap.GetPixel($bitmapX, $bitmapY)
        if ($locatorColor.ToArgb() -ne $locator.ExpectedColor.ToArgb()) {
            Add-Failure "$($locator.Type) maps to RGB $($locatorColor.R),$($locatorColor.G),$($locatorColor.B) at bitmap $bitmapX,$bitmapY, not province $($locator.ExpectedProvince)."
        }
    }
}
finally {
    $provinceBitmap.Dispose()
}
Add-Pass "Verified Pale Anchorage province color at center and ellipse boundaries"
Add-Pass "Validated state 1082 locator rows with bitmapY = height - 1 - round(Z)"

$buildingBytes = [IO.File]::ReadAllBytes($buildingPath)
if ($buildingBytes.Length -eq 0 -or $buildingBytes[$buildingBytes.Length - 1] -ne 0x30) {
    Add-Failure "buildings.txt must end at the final naval_headquarters value 0 (byte 0x30), with no trailing newline."
}
Add-Pass "Verified buildings.txt ends at byte 0x30 with no trailing record"

$pointNemoStackLines = @(
    [IO.File]::ReadAllLines((Join-Path $modRoot 'map\unitstacks.txt')) |
        Where-Object { $_ -match '^13414;' }
)
$expectedPointNemoStackTypes = @(0, 1, 9, 10, 21, 22, 38)
$actualPointNemoStackTypes = @()
foreach ($line in $pointNemoStackLines) {
    $fields = $line.Split(';')
    if ($fields.Count -lt 2 -or $fields[1] -notmatch '^\d+$') {
        Add-Failure "Malformed Point Nemo unit-stack row: $line"
        continue
    }
    $actualPointNemoStackTypes += [int]$fields[1]
}
if ($pointNemoStackLines.Count -ne 7 -or
    ($actualPointNemoStackTypes -join ',') -cne ($expectedPointNemoStackTypes -join ',')) {
    Add-Failure "Province 13414 unit-stack types are '$($actualPointNemoStackTypes -join ',')'; expected canonical types '0,1,9,10,21,22,38'."
}
Add-Pass "Validated the seven canonical Point Nemo unit-stack types"

$definitionRows = Get-Content -LiteralPath (Join-Path $modRoot 'map\definition.csv') |
    Where-Object { $_ -match '^\d+;' }
$ids = [System.Collections.Generic.HashSet[int]]::new()
$colors = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$newProvinceRows = 0
foreach ($row in $definitionRows) {
    $columns = $row.Split(';')
    $id = [int]$columns[0]
    $color = "$($columns[1]);$($columns[2]);$($columns[3])"
    if (-not $ids.Add($id)) {
        Add-Failure "Duplicate province ID $id in definition.csv."
    }
    if (-not $colors.Add($color)) {
        Add-Failure "Duplicate province color $color in definition.csv."
    }
    if ($id -eq 13414 -and $color -eq '211;90;211' -and $columns[4] -eq 'land' -and $columns[5] -eq 'true') {
        $newProvinceRows++
    }
}
if ($newProvinceRows -ne 1) {
    Add-Failure "definition.csv has $newProvinceRows valid rows for land province 13414; expected one."
}
Add-Pass "Validated $($definitionRows.Count) unique province definitions"

$stateText = [IO.File]::ReadAllText((Join-Path $modRoot 'history\states\1082-Pale Anchorage.txt'))
foreach ($requiredPattern in @(
	'id\s*=\s*1082',
	'owner\s*=\s*XAC',
	'add_core_of\s*=\s*XAC',
	'state_category\s*=\s*coi_alien_arcology',
	'provinces\s*=\s*\{\s*13414\s*\}',
	'coi_alien_mothership_anchorage\s*=\s*1'
)) {
    if ($stateText -notmatch $requiredPattern) {
        Add-Failure "Pale Anchorage state is missing required pattern: $requiredPattern"
	}
}

$stateCategoryPath = Join-Path $modRoot 'common\state_category\coi_alien_state_categories.txt'
$stateCategoryText = [IO.File]::ReadAllText($stateCategoryPath)
$arcologyMatch = [regex]::Match(
	$stateCategoryText,
	'(?s)coi_alien_arcology\s*=\s*\{.*?local_building_slots\s*=\s*(\d+)'
)
if (-not $arcologyMatch.Success) {
	Add-Failure "The coi_alien_arcology state category or its local_building_slots value is missing."
}
else {
	$arcologySlots = [int]$arcologyMatch.Groups[1].Value
	$sharedBuildingCounts = @{
		industrial_complex = 2
		arms_factory = 4
		dockyard = 6
		fuel_silo = 2
	}
	$occupiedSharedSlots = 0
	foreach ($building in $sharedBuildingCounts.GetEnumerator()) {
		$pattern = '(?m)^\s*' + [regex]::Escape($building.Key) + '\s*=\s*' + $building.Value + '\s*$'
		if ($stateText -notmatch $pattern) {
			Add-Failure "Pale Anchorage must start with $($building.Value) $($building.Key)."
		}
		$occupiedSharedSlots += $building.Value
	}
	if ($arcologySlots -lt $occupiedSharedSlots) {
		Add-Failure "Pale Anchorage occupies $occupiedSharedSlots shared slots, but coi_alien_arcology provides only $arcologySlots."
	}
	if ($arcologySlots -gt 25) {
		Add-Failure "coi_alien_arcology provides $arcologySlots shared slots, above HOI4's MAX_SHARED_SLOTS of 25."
	}
}

$namePoolPath = Join-Path $modRoot 'common\names\coi_alien_names.txt'
$namePoolText = [IO.File]::ReadAllText($namePoolPath)
foreach ($requiredPattern in @(
	'(?s)XAC\s*=\s*\{.*?male\s*=\s*\{\s*names\s*=\s*\{\s*\S+',
	'(?s)XAC\s*=\s*\{.*?female\s*=\s*\{\s*names\s*=\s*\{\s*\S+',
	'(?s)XAC\s*=\s*\{.*?surnames\s*=\s*\{\s*\S+'
)) {
	if ($namePoolText -notmatch $requiredPattern) {
		Add-Failure "The XAC generic character name pool is missing required pattern: $requiredPattern"
	}
}
Add-Pass "Validated Pale Anchorage shared slots and XAC generic character names"

$regionText = [IO.File]::ReadAllText((Join-Path $modRoot 'map\strategicregions\32-Southern Ocean.txt'))
$regionMatches = [regex]::Matches($regionText, '(?<!\d)13414(?!\d)').Count
if ($regionMatches -ne 1) {
    Add-Failure "Strategic region 32 contains province 13414 $regionMatches times; expected once."
}
Add-Pass "Validated state 1082 and Southern Ocean strategic-region membership"

$countryTagText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\country_tags\coi_alien_country_tags.txt'))
if ($countryTagText -notmatch '(?m)^\s*XAC\s*=\s*"countries/coi_alien_grey_consensus.txt"') {
    Add-Failure "XAC country tag mapping is missing or malformed."
}

$countryHistoryText = [IO.File]::ReadAllText((Join-Path $modRoot 'history\countries\XAC - Grey Consensus.txt'))
if ($countryHistoryText -notmatch '(?m)^\s*capital\s*=\s*1082\s*$') {
    Add-Failure "XAC does not start with capital 1082."
}
if ([regex]::Matches($countryHistoryText, '(?m)^\s*set_naval_oob\s*=\s*"XAC_1936_naval"\s*$').Count -ne 1) {
    Add-Failure 'XAC country history must register XAC_1936_naval exactly once.'
}
if ($countryHistoryText -notmatch '(?s)coi_alien_activate_mothership_anchorage\s*=\s*yes.*?set_naval_oob\s*=\s*"XAC_1936_naval"') {
    Add-Failure 'XAC must activate its alien ship designs before registering XAC_1936_naval.'
}

$navalUnitText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\units\coi_alien_naval_units.txt'))
$navalUnitContracts = @(
    [pscustomobject]@{
        Id = 'coi_alien_mothership'
        Type = 'carrier'
        Need = 'coi_alien_mothership_hull'
        Sprite = 'coi_alien_mothership'
    },
    [pscustomobject]@{
        Id = 'coi_alien_escort'
        Type = 'screen_ship'
        Need = 'coi_alien_escort_hull'
        Sprite = 'coi_alien_escort'
    }
)
foreach ($contract in $navalUnitContracts) {
    $definitionPattern = '(?m)^\s*' + [regex]::Escape($contract.Id) + '\s*=\s*\{\s*$'
    if ([regex]::Matches($navalUnitText, $definitionPattern).Count -ne 1) {
        Add-Failure "Naval sub-unit $($contract.Id) must be defined exactly once."
    }
    foreach ($requiredPattern in @(
        ('(?m)^\s*sprite\s*=\s*' + [regex]::Escape($contract.Sprite) + '\s*$'),
        ('(?m)^\s*type\s*=\s*\{\s*' + [regex]::Escape($contract.Type) + '\s*\}\s*$'),
        ('(?m)^\s*need\s*=\s*\{\s*' + [regex]::Escape($contract.Need) + '\s*=\s*1\s*\}\s*$')
    )) {
        if ([regex]::Matches($navalUnitText, $requiredPattern).Count -ne 1) {
            Add-Failure "Naval sub-unit contract for $($contract.Id) is missing or duplicates pattern: $requiredPattern"
        }
    }
}
if ($navalUnitText -match '\bship_hull_(?:carrier|light)\b') {
    Add-Failure 'Alien naval sub-units must not retain vanilla carrier or destroyer hull requirements.'
}

$navalGfxText = [IO.File]::ReadAllText((Join-Path $modRoot 'interface\coi_alien_naval.gfx'))
$navalEntityText = [IO.File]::ReadAllText((Join-Path $modRoot 'gfx\entities\zz_coi_alien_naval_entities.asset'))
$navalUiContracts = @(
    [pscustomobject]@{
        Sprite = 'coi_alien_mothership'
        NavyTexture = 'gfx/interface/coi_alien/coi_alien_mothership_navy_icon.dds'
        StripTexture = 'gfx/interface/navalcombat/ships/coi_alien_mothership.dds'
        CounterTexture = 'gfx/interface/counters/ships_small/onmap_coi_alien_mothership.dds'
        InvertedTexture = 'gfx/interface/counters/ships_small/onmap_coi_alien_mothership_inverted.dds'
        TexticonTexture = 'gfx/texticons/ship_coi_alien_mothership_icon_small.dds'
        StripWidth = 160
        StripHeight = 19
        Clone = 'ship_hull_super_carrier_entity'
    },
    [pscustomobject]@{
        Sprite = 'coi_alien_escort'
        NavyTexture = 'gfx/interface/coi_alien/coi_alien_escort_navy_icon.dds'
        StripTexture = 'gfx/interface/navalcombat/ships/coi_alien_escort.dds'
        CounterTexture = 'gfx/interface/counters/ships_small/onmap_coi_alien_escort.dds'
        InvertedTexture = 'gfx/interface/counters/ships_small/onmap_coi_alien_escort_inverted.dds'
        TexticonTexture = 'gfx/texticons/ship_coi_alien_escort_icon_small.dds'
        StripWidth = 86
        StripHeight = 18
        Clone = 'destroyer_entity'
    }
)

foreach ($contract in $navalUiContracts) {
    Test-DdsArgbContract -RelativePath $contract.NavyTexture -Width 50 -Height 34
    Test-DdsArgbContract -RelativePath $contract.StripTexture -Width $contract.StripWidth -Height $contract.StripHeight
    Test-DdsArgbContract -RelativePath $contract.CounterTexture -Width 30 -Height 12
    Test-DdsArgbContract -RelativePath $contract.InvertedTexture -Width 30 -Height 12
    Test-DdsArgbContract -RelativePath $contract.TexticonTexture -Width 30 -Height 12

    Test-GfxSpriteContract `
        -Text $navalGfxText `
        -Name "GFX_navy_icon_$($contract.Sprite)" `
        -Texture $contract.NavyTexture

    foreach ($stripKey in @(
        "GFX_navalcombat_ship_icon_$($contract.Sprite)",
        "GFX_unit_$($contract.Sprite)_icon_medium",
        "GFX_unit_$($contract.Sprite)_1_icon_medium",
        "GFX_unit_$($contract.Sprite)_2_icon_medium"
    )) {
        Test-GfxSpriteContract `
            -Text $navalGfxText `
            -Name $stripKey `
            -Texture $contract.StripTexture `
            -Frames 2
    }

    Test-GfxSpriteContract `
        -Text $navalGfxText `
        -Name "GFX_unit_$($contract.Sprite)_icon_medium_white" `
        -Texture $contract.CounterTexture
    Test-GfxSpriteContract `
        -Text $navalGfxText `
        -Name "GFX_unit_$($contract.Sprite)_icon_medium_black" `
        -Texture $contract.InvertedTexture

    foreach ($texticonKey in @(
        "GFX_ship_$($contract.Sprite)_icon_small",
        "unit_$($contract.Sprite)_icon_small"
    )) {
        Test-GfxSpriteContract `
            -Text $navalGfxText `
            -Name $texticonKey `
            -Texture $contract.TexticonTexture `
            -RequireLegacyLazyLoad
    }

    $entityKey = "$($contract.Sprite)_entity"
    $entityPattern = '(?s)entity\s*=\s*\{\s*clone\s*=\s*"' +
        [regex]::Escape($contract.Clone) + '"\s*name\s*=\s*"' +
        [regex]::Escape($entityKey) + '"\s*\}'
    if ([regex]::Matches($navalEntityText, $entityPattern).Count -ne 1) {
        Add-Failure "Strategic-map entity $entityKey must retain clone $($contract.Clone) exactly once."
    }
}

Test-DdsArgbContract `
    -RelativePath 'gfx/interface/coi_alien/coi_alien_phase_movement.dds' `
    -Width 24 `
    -Height 24
Test-GfxSpriteContract `
    -Text $navalGfxText `
    -Name 'GFX_coi_alien_phase_movement' `
    -Texture 'gfx/interface/coi_alien/coi_alien_phase_movement.dds'

foreach ($globalUiKey in @(
    'GFX_navy_anchor',
    'GFX_onmap_fleet_entry',
    'GFX_theatre_naval_control_panel',
    'navalMissionArrow'
)) {
    $globalUiPattern = '(?m)^\s*name\s*=\s*"' + [regex]::Escape($globalUiKey) + '"\s*$'
    if ($navalGfxText -match $globalUiPattern) {
        Add-Failure "Alien naval UI must not override global human UI key $globalUiKey."
    }
}
Add-Pass 'Validated exact per-unit XAC naval DDS dimensions, sprite frames, texticons, and preserved global UI isolation'

$advisorHistoryText = [IO.File]::ReadAllText((Join-Path $modRoot 'history\general\zz_coi_alien_advisor_isolation.txt'))
$advisorEffectText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_effects\coi_alien_advisor_effects.txt'))
$advisorOnActionText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\on_actions\coi_alien_advisor_on_actions.txt'))
$advisorIsolationEffect = 'coi_alien_isolate_human_fallback_advisors_effect'
$advisorIsolationFlag = 'coi_alien_human_fallback_advisors_isolated'

if ([regex]::Matches($advisorEffectText, '(?m)^' + [regex]::Escape($advisorIsolationEffect) + '\s*=\s*\{\s*$').Count -ne 1) {
    Add-Failure "XAC advisor isolation scripted effect $advisorIsolationEffect must be defined exactly once."
}
foreach ($requiredPattern in @(
    '(?m)^\s*original_tag\s*=\s*XAC\s*$',
    '(?m)^\s*every_character\s*=\s*\{\s*$',
    '(?m)^\s*is_advisor\s*=\s*yes\s*$',
    '(?m)^\s*retire\s*=\s*yes\s*$'
)) {
    if ([regex]::Matches($advisorEffectText, $requiredPattern).Count -ne 1) {
        Add-Failure "XAC advisor isolation effect is missing or duplicates required pattern: $requiredPattern"
    }
}
if ($advisorEffectText -match '(?m)^\s*include_invisible\s*=') {
    Add-Failure 'XAC every_character advisor isolation must not use include_invisible; HOI4 1.19.2 rejects it at runtime.'
}
foreach ($trait in @('communist_revolutionary', 'democratic_reformer', 'fascist_demagogue', 'head_of_intelligence')) {
    $traitPattern = '(?m)^\s*has_trait\s*=\s*' + [regex]::Escape($trait) + '\s*$'
    if ([regex]::Matches($advisorEffectText, $traitPattern).Count -ne 1) {
        Add-Failure "XAC advisor isolation must match vanilla fallback trait $trait exactly once."
    }
}
foreach ($text in @($advisorEffectText, $advisorHistoryText, $advisorOnActionText)) {
    if ($text -match '(?m)^\s*(?:has_character|retire_character)\s*=\s*XAC_generic_') {
        Add-Failure 'XAC advisor isolation must not rely on unstable generated character tokens.'
    }
}
if ([regex]::Matches($advisorEffectText, '(?m)^\s*has_country_flag\s*=\s*' + [regex]::Escape($advisorIsolationFlag) + '\s*$').Count -ne 1 -or
    [regex]::Matches($advisorEffectText, '(?m)^\s*set_country_flag\s*=\s*' + [regex]::Escape($advisorIsolationFlag) + '\s*$').Count -ne 1) {
    Add-Failure "XAC advisor isolation must test and set its one-time country flag $advisorIsolationFlag exactly once."
}
if ([regex]::Matches($advisorHistoryText, '(?m)^\s*' + [regex]::Escape($advisorIsolationEffect) + '\s*=\s*yes\s*$').Count -ne 1) {
    Add-Failure 'Late new-game history must invoke the XAC advisor isolation effect exactly once.'
}
foreach ($hook in @('on_startup', 'on_daily_XAC')) {
    if ([regex]::Matches($advisorOnActionText, '(?m)^\s*' + [regex]::Escape($hook) + '\s*=\s*\{\s*$').Count -ne 1) {
        Add-Failure "XAC advisor save migration hook $hook must be defined exactly once."
    }
}
if ([regex]::Matches($advisorOnActionText, '(?m)^\s*' + [regex]::Escape($advisorIsolationEffect) + '\s*=\s*yes\s*$').Count -ne 2) {
    Add-Failure 'XAC advisor isolation must be invoked once at startup and once by the tag-scoped daily migration hook.'
}

$alienCharacterText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\characters\coi_alien_characters.txt'))
foreach ($token in @('coi_alien_eir', 'coi_alien_vael', 'coi_alien_thren', 'coi_alien_oru', 'coi_alien_saal')) {
    $characterPattern = '(?m)^\s*' + [regex]::Escape($token) + '\s*=\s*\{\s*$'
    if ([regex]::Matches($alienCharacterText, $characterPattern).Count -ne 1) {
        Add-Failure "Authored XAC character $token must remain defined exactly once."
    }
    $recruitPattern = '(?m)^\s*recruit_character\s*=\s*' + [regex]::Escape($token) + '\s*$'
    if ([regex]::Matches($countryHistoryText, $recruitPattern).Count -ne 1) {
        Add-Failure "Authored XAC character $token must remain recruited exactly once."
    }
}
Add-Pass 'Validated XAC-only advisor isolation and namespaced naval UI/entity hooks'

$intelligenceEffectText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_effects\coi_alien_intelligence_effects.txt'))
$intelligenceOnActionText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\on_actions\coi_alien_intelligence_on_actions.txt'))
$intelligenceIdeaText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\ideas\coi_alien_intelligence_ideas.txt'))
$intelligenceAgencyText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\intelligence_agencies\coi_alien_intelligence_agencies.txt'))
$operativeTraitText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\unit_leader\coi_alien_operative_traits.txt'))
$operativeCodenameText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\units\codenames_operatives\coi_alien_xac_operative_codenames.txt'))
$operativePortraitPoolText = [IO.File]::ReadAllText((Join-Path $modRoot 'portraits\coi_alien_operative_portraits.txt'))
$intelligenceLocalisationText = [IO.File]::ReadAllText((Join-Path $modRoot 'localisation\english\coi_alien_intelligence_l_english.yml'))
$spyInitializer = 'coi_alien_initialize_spy_roster_v1_effect'
$spyInitializerFlag = 'coi_alien_spy_roster_v1_initialized'
$spyComplementIdea = 'coi_alien_expeditionary_intelligence_complement'
$droneTrait = 'coi_alien_autonomous_infiltration_drone'

$spyInitializerBlocks = @(Get-ClausewitzAssignedBlocks -Text $intelligenceEffectText -Assignment $spyInitializer)
if ($spyInitializerBlocks.Count -ne 1) {
    Add-Failure "Spy-roster initializer $spyInitializer must be defined exactly once; found $($spyInitializerBlocks.Count)."
}
else {
    $spyInitializerBlock = $spyInitializerBlocks[0]
    foreach ($requiredPattern in @(
        '(?m)^\s*original_tag\s*=\s*XAC\s*$',
        '(?m)^\s*has_dlc\s*=\s*"La Resistance"\s*$',
        ('(?m)^\s*has_country_flag\s*=\s*' + [regex]::Escape($spyInitializerFlag) + '\s*$'),
        ('(?m)^\s*set_country_flag\s*=\s*' + [regex]::Escape($spyInitializerFlag) + '\s*$'),
        ('(?m)^\s*add_ideas\s*=\s*' + [regex]::Escape($spyComplementIdea) + '\s*$'),
        '(?m)^\s*has_intelligence_agency\s*=\s*yes\s*$'
    )) {
        if ([regex]::Matches($spyInitializerBlock, $requiredPattern).Count -ne 1) {
            Add-Failure "DLC-guarded spy-roster initializer is missing or duplicates required pattern: $requiredPattern"
        }
    }
    $idempotenceGuardPattern = '(?s)NOT\s*=\s*\{\s*has_country_flag\s*=\s*' + [regex]::Escape($spyInitializerFlag) + '\s*\}'
    if ([regex]::Matches($spyInitializerBlock, $idempotenceGuardPattern).Count -ne 1) {
        Add-Failure 'The spy-roster country flag must appear exactly once as a negated initialization guard.'
    }

    $lastOperativeCreation = $spyInitializerBlock.LastIndexOf('create_operative_leader', [StringComparison]::Ordinal)
    $guardCommit = $spyInitializerBlock.IndexOf("set_country_flag = $spyInitializerFlag", [StringComparison]::Ordinal)
    if ($lastOperativeCreation -lt 0 -or $guardCommit -le $lastOperativeCreation) {
        Add-Failure 'The spy-roster idempotence flag must be committed only after all six dynamic operatives are created.'
    }

    $agencyCreationBlocks = @(Get-ClausewitzAssignedBlocks -Text $spyInitializerBlock -Assignment 'create_intelligence_agency')
    if ($agencyCreationBlocks.Count -ne 1 -or
        [regex]::Matches($agencyCreationBlocks[0], '(?m)^\s*name\s*=\s*coi_alien_quiet_chorus_agency_name\s*$').Count -ne 1 -or
        [regex]::Matches($agencyCreationBlocks[0], '(?m)^\s*icon\s*=\s*GFX_intelligence_agency_logo_coi_alien_quiet_chorus\s*$').Count -ne 1) {
        Add-Failure 'The spy initializer must explicitly create The Quiet Chorus with its authored name and agency logo exactly once.'
    }
}

foreach ($hook in @('on_startup', 'on_daily_XAC')) {
    if ([regex]::Matches($intelligenceOnActionText, '(?m)^\s*' + [regex]::Escape($hook) + '\s*=\s*\{\s*$').Count -ne 1) {
        Add-Failure "Spy-roster migration hook $hook must be defined exactly once."
    }
}
if ([regex]::Matches($intelligenceOnActionText, '(?m)^\s*' + [regex]::Escape($spyInitializer) + '\s*=\s*yes\s*$').Count -ne 2) {
    Add-Failure 'The spy-roster initializer must be invoked exactly once at startup and once by on_daily_XAC for old-save migration.'
}

$operativeContracts = @(
    [pscustomobject]@{ Id = 'coi_alien_operative_neth_witness'; DisplayName = 'Neth Witness'; Gfx = 'GFX_portrait_coi_alien_neth_witness'; Active = $true; Drone = $false; Gender = 'male'; Texture = 'gfx/leaders/XAC/Operatives/coi_alien_neth_witness.dds' },
    [pscustomobject]@{ Id = 'coi_alien_operative_ysil_lattice'; DisplayName = 'Ysil Lattice'; Gfx = 'GFX_portrait_coi_alien_ysil_lattice'; Active = $false; Drone = $false; Gender = 'female'; Texture = 'gfx/leaders/XAC/Operatives/coi_alien_ysil_lattice.dds' },
    [pscustomobject]@{ Id = 'coi_alien_operative_cael_current'; DisplayName = 'Cael Current'; Gfx = 'GFX_portrait_coi_alien_cael_current'; Active = $false; Drone = $false; Gender = 'male'; Texture = 'gfx/leaders/XAC/Operatives/coi_alien_cael_current.dds' },
    [pscustomobject]@{ Id = 'coi_alien_operative_drone_quiet_orbit'; DisplayName = 'Quiet Orbit'; Gfx = 'GFX_portrait_coi_alien_drone_quiet_orbit'; Active = $true; Drone = $true; Gender = 'male'; Texture = 'gfx/leaders/XAC/Operatives/coi_alien_drone_quiet_orbit.dds' },
    [pscustomobject]@{ Id = 'coi_alien_operative_drone_pale_echo'; DisplayName = 'Pale Echo'; Gfx = 'GFX_portrait_coi_alien_drone_pale_echo'; Active = $false; Drone = $true; Gender = 'female'; Texture = 'gfx/leaders/XAC/Operatives/coi_alien_drone_pale_echo.dds' },
    [pscustomobject]@{ Id = 'coi_alien_operative_drone_outer_witness'; DisplayName = 'Outer Witness'; Gfx = 'GFX_portrait_coi_alien_drone_outer_witness'; Active = $false; Drone = $true; Gender = 'male'; Texture = 'gfx/leaders/XAC/Operatives/coi_alien_drone_outer_witness.dds' }
)
$operativeBlocks = @(Get-ClausewitzAssignedBlocks -Text $intelligenceEffectText -Assignment 'create_operative_leader')
if ($operativeBlocks.Count -ne 6) {
    Add-Failure "Spy roster defines $($operativeBlocks.Count) dynamic operatives; expected exactly six."
}
foreach ($operative in $operativeContracts) {
    $namePattern = '(?m)^\s*name\s*=\s*' + [regex]::Escape($operative.Id) + '\s*$'
    $matchingBlocks = @($operativeBlocks | Where-Object { $_ -match $namePattern })
    if ($matchingBlocks.Count -ne 1) {
        Add-Failure "Dynamic operative $($operative.Id) must be authored exactly once; found $($matchingBlocks.Count)."
        continue
    }

    $operativeBlock = $matchingBlocks[0]
    $bypassValue = if ($operative.Active) { 'yes' } else { 'no' }
    foreach ($requiredPattern in @(
        ('(?m)^\s*GFX\s*=\s*' + [regex]::Escape($operative.Gfx) + '\s*$'),
        '(?m)^\s*portrait_tag_override\s*=\s*XAC\s*$',
        '(?m)^\s*nationalities\s*=\s*\{\s*XAC\s*\}\s*$',
        ('(?m)^\s*bypass_recruitment\s*=\s*' + $bypassValue + '\s*$'),
        ('(?m)^\s*gender\s*=\s*' + $operative.Gender + '\s*$')
    )) {
        if ([regex]::Matches($operativeBlock, $requiredPattern).Count -ne 1) {
            Add-Failure "Operative $($operative.Id) is missing or duplicates roster pattern: $requiredPattern"
        }
    }
    if (-not $operative.Active -and [regex]::Matches($operativeBlock, '(?m)^\s*available_to_spy_master\s*=\s*no\s*$').Count -ne 1) {
        Add-Failure "Recruitable operative $($operative.Id) must remain private from allied human spy masters."
    }

    $droneTraitPattern = '(?m)^\s*traits\s*=\s*\{[^}]*\b' + [regex]::Escape($droneTrait) + '\b[^}]*\}\s*$'
    if ($operative.Drone -and [regex]::Matches($operativeBlock, $droneTraitPattern).Count -ne 1) {
        Add-Failure "Drone operative $($operative.Id) must carry $droneTrait exactly once."
    }
    elseif (-not $operative.Drone -and $operativeBlock -match ('\b' + [regex]::Escape($droneTrait) + '\b')) {
        Add-Failure "Biological Grey operative $($operative.Id) must not carry the autonomous-drone trait."
    }
}
if ([regex]::Matches($intelligenceEffectText, '(?m)^\s*bypass_recruitment\s*=\s*yes\s*$').Count -ne 2 -or
    [regex]::Matches($intelligenceEffectText, '(?m)^\s*bypass_recruitment\s*=\s*no\s*$').Count -ne 4) {
    Add-Failure 'The first spy roster must contain exactly two active operatives and four recruitable reserves.'
}
if ($intelligenceEffectText -match 'GFX_portrait_operative_unknown|GFX_portrait_(?:generic|generic_[A-Z]{3})') {
    Add-Failure 'Authored XAC operatives must never bind a vanilla human or unknown portrait fallback.'
}

$spyIdeaBlocks = @(Get-ClausewitzAssignedBlocks -Text $intelligenceIdeaText -Assignment $spyComplementIdea)
if ($spyIdeaBlocks.Count -ne 1) {
    Add-Failure "Operative-slot idea $spyComplementIdea must be defined exactly once."
}
else {
    foreach ($requiredPattern in @(
        '(?m)^\s*original_tag\s*=\s*XAC\s*$',
        '(?m)^\s*removal_cost\s*=\s*-1\s*$',
        '(?m)^\s*operative_slot\s*=\s*1\s*$'
    )) {
        if ([regex]::Matches($spyIdeaBlocks[0], $requiredPattern).Count -ne 1) {
            Add-Failure "Expeditionary intelligence complement is missing or duplicates pattern: $requiredPattern"
        }
    }
}

$agencyBlocks = @(Get-ClausewitzAssignedBlocks -Text $intelligenceAgencyText -Assignment 'intelligence_agency')
if ($agencyBlocks.Count -ne 1) {
    Add-Failure "The Quiet Chorus agency file must define exactly one intelligence_agency block; found $($agencyBlocks.Count)."
}
else {
    foreach ($requiredPattern in @(
        '(?m)^\s*picture\s*=\s*GFX_intelligence_agency_logo_coi_alien_quiet_chorus\s*$',
        '(?m)^\s*names\s*=\s*\{\s*coi_alien_quiet_chorus_agency_name\s*\}\s*$',
        '(?m)^\s*default\s*=\s*\{\s*tag\s*=\s*XAC\s*\}\s*$',
        '(?m)^\s*available\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}\s*$'
    )) {
        if ([regex]::Matches($agencyBlocks[0], $requiredPattern).Count -ne 1) {
            Add-Failure "The Quiet Chorus agency contract is missing or duplicates pattern: $requiredPattern"
        }
    }
}

$droneTraitBlocks = @(Get-ClausewitzAssignedBlocks -Text $operativeTraitText -Assignment $droneTrait)
if ($droneTraitBlocks.Count -ne 1) {
    Add-Failure "Custom drone operative trait $droneTrait must be defined exactly once."
}
else {
    foreach ($requiredPattern in @(
        '(?m)^\s*type\s*=\s*operative\s*$',
        '(?m)^\s*trait_type\s*=\s*personality_trait\s*$',
        '(?m)^\s*factor\s*=\s*0\s*$'
    )) {
        if ([regex]::Matches($droneTraitBlocks[0], $requiredPattern).Count -ne 1) {
            Add-Failure "Custom drone operative trait is missing or duplicates pattern: $requiredPattern"
        }
    }
}

$codenameGroup = 'COI_ALIEN_XAC_OPERATIVE_CODENAMES'
$codenameGroupBlocks = @(Get-ClausewitzAssignedBlocks -Text $operativeCodenameText -Assignment $codenameGroup)
if ($codenameGroupBlocks.Count -ne 1) {
    Add-Failure "XAC operative codename group $codenameGroup must be defined exactly once."
}
else {
    foreach ($requiredPattern in @(
        '(?m)^\s*name\s*=\s*coi_alien_xac_operative_codename_theme\s*$',
        '(?m)^\s*for_countries\s*=\s*\{\s*XAC\s*\}\s*$',
        '(?m)^\s*type\s*=\s*codename\s*$',
        '(?m)^\s*fallback_name\s*=\s*"Signal %d"\s*$'
    )) {
        if ([regex]::Matches($codenameGroupBlocks[0], $requiredPattern).Count -ne 1) {
            Add-Failure "XAC operative codename group is missing or duplicates pattern: $requiredPattern"
        }
    }
}
$expectedCodenames = @(
    'Far Signal', 'Still Light', 'Third Voice', 'Cold Meridian',
    'Glass Rain', 'Null Star', 'Silent Vector', 'Deep Listener',
    'Last Reflection', 'Dark Current', 'Empty Shore', 'Unblinking Eye'
)
$uniqueCodenameBlocks = @(Get-ClausewitzAssignedBlocks -Text $operativeCodenameText -Assignment 'unique')
if ($uniqueCodenameBlocks.Count -ne 1) {
    Add-Failure 'XAC operative codenames must contain exactly one unique pool.'
}
else {
    $actualCodenames = @([regex]::Matches($uniqueCodenameBlocks[0], '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $missingCodenames = @($expectedCodenames | Where-Object { $_ -notin $actualCodenames })
    if ($actualCodenames.Count -ne 12 -or ($actualCodenames | Select-Object -Unique).Count -ne 12 -or $missingCodenames.Count -ne 0) {
        Add-Failure 'XAC operative codename pool must contain the twelve distinct authored Consensus signal designations.'
    }
}

$xacPortraitBlocks = @(Get-ClausewitzAssignedBlocks -Text $operativePortraitPoolText -Assignment 'XAC')
if ($xacPortraitBlocks.Count -ne 1) {
    Add-Failure 'The XAC random-operative portrait pool must be defined exactly once.'
}
else {
    $operativePoolBlocks = @(Get-ClausewitzAssignedBlocks -Text $xacPortraitBlocks[0] -Assignment 'operative')
    if ($operativePoolBlocks.Count -ne 1) {
        Add-Failure 'The XAC portrait pool must contain exactly one operative branch.'
    }
    else {
        $expectedGreyPortraits = @(
            'GFX_portrait_coi_alien_neth_witness',
            'GFX_portrait_coi_alien_ysil_lattice',
            'GFX_portrait_coi_alien_cael_current'
        )
        foreach ($gender in @('male', 'female')) {
            $genderBlocks = @(Get-ClausewitzAssignedBlocks -Text $operativePoolBlocks[0] -Assignment $gender)
            if ($genderBlocks.Count -ne 1) {
                Add-Failure "The XAC random-operative portrait pool must define exactly one $gender branch."
                continue
            }
            $actualPortraits = @([regex]::Matches($genderBlocks[0], '"(GFX_[^"]+)"') | ForEach-Object { $_.Groups[1].Value })
            $missingPortraits = @($expectedGreyPortraits | Where-Object { $_ -notin $actualPortraits })
            if ($actualPortraits.Count -ne 3 -or ($actualPortraits | Select-Object -Unique).Count -ne 3 -or $missingPortraits.Count -ne 0) {
                Add-Failure "The XAC $gender random-operative pool must contain only the same three Grey portraits, with no human fallback."
            }
        }
    }
}
if ($operativePortraitPoolText -match 'GFX_portrait_operative_unknown|GFX_portrait_(?:generic|generic_[A-Z]{3})') {
    Add-Failure 'The XAC random-operative portrait pool must not reference a vanilla human or unknown portrait.'
}

$allInterfaceGfxText = ($interfaceFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
foreach ($operative in $operativeContracts) {
    Test-DdsArgbContract -RelativePath $operative.Texture -Width 156 -Height 210
    Test-GfxSpriteContract -Text $allInterfaceGfxText -Name $operative.Gfx -Texture $operative.Texture
    $displayNamePattern = '(?m)^\s*' + [regex]::Escape($operative.Id) + ':\s*"' + [regex]::Escape($operative.DisplayName) + '"\s*$'
    if ([regex]::Matches($intelligenceLocalisationText, $displayNamePattern).Count -ne 1) {
        Add-Failure "Operative $($operative.Id) must localise exactly once as '$($operative.DisplayName)'."
    }
    foreach ($localisationSuffix in @('', '_desc')) {
        if (-not $localisationKeys.ContainsKey($operative.Id + $localisationSuffix)) {
            Add-Failure "Missing English operative localisation key $($operative.Id + $localisationSuffix)."
        }
    }
}
$droneTraitTexture = 'gfx/interface/traits/coi_alien_trait_autonomous_infiltration_drone.dds'
Test-DdsArgbContract -RelativePath $droneTraitTexture -Width 23 -Height 33
Test-GfxSpriteContract -Text $allInterfaceGfxText -Name 'GFX_trait_coi_alien_autonomous_infiltration_drone' -Texture $droneTraitTexture
$agencyLogoTexture = 'gfx/interface/operatives/agencies/coi_alien_quiet_chorus.dds'
Test-DdsArgbContract -RelativePath $agencyLogoTexture -Width 233 -Height 119
Test-DdsHorizontalFramesDiffer -RelativePath $agencyLogoTexture -Width 233 -Height 119
Test-GfxSpriteContract -Text $allInterfaceGfxText -Name 'GFX_intelligence_agency_logo_coi_alien_quiet_chorus' -Texture $agencyLogoTexture -Frames 2
foreach ($localisationKey in @(
    'coi_alien_quiet_chorus_agency_name',
    $spyComplementIdea,
    ($spyComplementIdea + '_desc'),
    $droneTrait,
    ($droneTrait + '_desc'),
    'coi_alien_xac_operative_codename_theme'
)) {
    if (-not $localisationKeys.ContainsKey($localisationKey)) {
        Add-Failure "Missing English intelligence localisation key $localisationKey."
    }
}
$intelligenceDisplayNames = [ordered]@{
    'coi_alien_quiet_chorus_agency_name' = 'The Quiet Chorus'
    $spyComplementIdea = 'Expeditionary Intelligence Complement'
    $droneTrait = 'Autonomous Infiltration Drone'
    'coi_alien_xac_operative_codename_theme' = 'Consensus Signal Designations'
}
foreach ($entry in $intelligenceDisplayNames.GetEnumerator()) {
    $displayNamePattern = '(?m)^\s*' + [regex]::Escape($entry.Key) + ':\s*"' + [regex]::Escape($entry.Value) + '"\s*$'
    if ([regex]::Matches($intelligenceLocalisationText, $displayNamePattern).Count -ne 1) {
        Add-Failure "Intelligence localisation $($entry.Key) must resolve exactly once to '$($entry.Value)'."
    }
}
Add-Pass 'Validated DLC-guarded, idempotent Quiet Chorus initialization and old-save migration'
Add-Pass 'Validated exact three-Grey/three-drone roster with two active and four recruitable operatives'
Add-Pass 'Validated XAC-only operative slots, codenames, portrait pools, custom trait, and intelligence art contracts'

function Get-RequiredModText {
	param([Parameter(Mandatory)] [string]$RelativePath)

	$path = Join-Path $script:modRoot $RelativePath
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
		Add-Failure "Missing required mod contract file: $RelativePath"
		return ''
	}
	return [IO.File]::ReadAllText($path)
}

function Get-UniqueContractBlock {
	param(
		[Parameter(Mandatory)] [string]$Text,
		[Parameter(Mandatory)] [string]$Assignment,
		[Parameter(Mandatory)] [string]$Label
	)

	$blocks = @(Get-ClausewitzAssignedBlocks -Text $Text -Assignment $Assignment)
	if ($blocks.Count -ne 1) {
		Add-Failure "$Label must define $Assignment exactly once; found $($blocks.Count)."
		return ''
	}
	return $blocks[0]
}

function Test-TokenMutationContract {
	param(
		[Parameter(Mandatory)] [string]$Block,
		[Parameter(Mandatory)] [string]$Assignment,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$ExpectedTokens,
		[Parameter(Mandatory)] [string]$Label
	)

	$mutationBlocks = @(Get-ClausewitzAssignedBlocks -Text $Block -Assignment $Assignment)
	$actualTokens = @()
	foreach ($mutationBlock in $mutationBlocks) {
		$tokenMatches = [regex]::Matches($mutationBlock, '(?m)^\s*token\s*=\s*(coi_alien_token_[a-z0-9_]+)\s*$')
		if ($tokenMatches.Count -ne 1) {
			Add-Failure "$Label contains a malformed $Assignment block."
			continue
		}
		$actualTokens += $tokenMatches[0].Groups[1].Value
	}

	$missing = @($ExpectedTokens | Where-Object { $_ -notin $actualTokens })
	$unexpected = @($actualTokens | Where-Object { $_ -notin $ExpectedTokens })
	if ($actualTokens.Count -ne $ExpectedTokens.Count -or $missing.Count -ne 0 -or $unexpected.Count -ne 0) {
		Add-Failure "$Label $Assignment token set is [$($actualTokens -join ', ')]; expected [$($ExpectedTokens -join ', ')]."
	}
}

function Test-AwarenessRandomContract {
	param(
		[Parameter(Mandatory)] [string]$Block,
		[Parameter(Mandatory)] [int]$AwarenessWeight,
		[Parameter(Mandatory)] [int]$NoEffectWeight,
		[Parameter(Mandatory)] [string]$Label
	)

	$randomBlocks = @(Get-ClausewitzAssignedBlocks -Text $Block -Assignment 'random_list' | Where-Object {
		$_ -match '\bcoi_alien_raise_awareness_one_effect\s*=\s*yes\b'
	})
	if ($randomBlocks.Count -ne 1) {
		Add-Failure "$Label must contain exactly one awareness random_list; found $($randomBlocks.Count)."
		return
	}

	$randomBlock = $randomBlocks[0]
	$branchMatches = [regex]::Matches($randomBlock, '(?m)^\s*(\d+)\s*=\s*\{')
	$hitPattern = '(?m)^\s*' + $AwarenessWeight + '\s*=\s*\{\s*coi_alien_raise_awareness_one_effect\s*=\s*yes\s*\}\s*$'
	$missPattern = '(?m)^\s*' + $NoEffectWeight + '\s*=\s*\{\s*\}\s*$'
	if ($branchMatches.Count -ne 2 -or
		[regex]::Matches($randomBlock, $hitPattern).Count -ne 1 -or
		[regex]::Matches($randomBlock, $missPattern).Count -ne 1) {
		Add-Failure "$Label must use the exact $AwarenessWeight/$NoEffectWeight one-awareness outcome split."
	}
}

$operationText = Get-RequiredModText 'common\operations\coi_alien_quiet_chorus_operations.txt'
$operationPhaseText = Get-RequiredModText 'common\operation_phases\coi_alien_quiet_chorus_phases.txt'
$operationTokenText = Get-RequiredModText 'common\operation_tokens\coi_alien_operation_tokens.txt'
$operationDynamicTokenText = Get-RequiredModText 'common\synchronized_dynamic_tokens\coi_alien_operation_tokens.txt'
$operationUpgradeText = Get-RequiredModText 'common\intelligence_agency_upgrades\coi_alien_intelligence_agency_upgrades.txt'
$operationEffectText = Get-RequiredModText 'common\scripted_effects\coi_alien_operation_effects.txt'
$operationTriggerText = Get-RequiredModText 'common\scripted_triggers\coi_alien_operation_triggers.txt'
$operationIdeaText = Get-RequiredModText 'common\ideas\coi_alien_operation_ideas.txt'
$operationAiEffectText = Get-RequiredModText 'common\scripted_effects\coi_alien_operation_ai_effects.txt'
$operationAiStrategyText = Get-RequiredModText 'common\ai_strategy\coi_alien_operation_strategies.txt'
$operationTargetScorerText = Get-RequiredModText 'common\scorers\country\coi_alien_operation_target_scorer.txt'
$awarenessDecisionText = Get-RequiredModText 'common\decisions\coi_alien_awareness_decisions.txt'
$operationLocalisationText = Get-RequiredModText 'localisation\english\coi_alien_operations_l_english.yml'
$operationGfxText = Get-RequiredModText 'interface\coi_alien_operations.gfx'
$intelligenceAgencyGuiText = Get-RequiredModText 'interface\countryintelligenceagencyview.gui'

$operationContracts = @(
	[pscustomobject]@{
		Id = 'coi_alien_silent_systems_survey'; DisplayName = 'Silent Systems Survey'; Days = 45; Network = 20; Operatives = 1; Risk = '0.05';
		RiskModifier = 'operation_infiltrate_risk'; FactoryDays = 0; Required = @(); Awarded = @('coi_alien_token_surface_profile');
		NormalEffect = 'coi_alien_complete_silent_systems_survey_effect'; ExtraEffect = '';
		Phases = @('coi_alien_phase_silent_systems_survey_calibrate', 'coi_alien_phase_silent_systems_survey_observe', 'coi_alien_phase_silent_systems_survey_withdraw')
	},
	[pscustomobject]@{
		Id = 'coi_alien_seed_mimetic_access'; DisplayName = 'Seed Mimetic Access'; Days = 75; Network = 35; Operatives = 2; Risk = '0.10';
		RiskModifier = 'operation_infiltrate_risk'; FactoryDays = 0; Required = @('coi_alien_token_surface_profile'); Awarded = @('coi_alien_token_institutional_access');
		NormalEffect = 'coi_alien_complete_seed_mimetic_access_effect'; ExtraEffect = '';
		Phases = @('coi_alien_phase_seed_mimetic_access_model', 'coi_alien_phase_seed_mimetic_access_insert', 'coi_alien_phase_seed_mimetic_access_stabilize')
	},
	[pscustomobject]@{
		Id = 'coi_alien_penetrate_research_networks'; DisplayName = 'Penetrate Research Networks'; Days = 90; Network = 50; Operatives = 2; Risk = '0.10';
		RiskModifier = 'operation_infiltrate_risk'; FactoryDays = 0; Required = @('coi_alien_token_institutional_access'); Awarded = @('coi_alien_token_research_access');
		NormalEffect = 'coi_alien_complete_penetrate_research_networks_effect'; ExtraEffect = '';
		Phases = @('coi_alien_phase_penetrate_research_networks_map', 'coi_alien_phase_penetrate_research_networks_mirror', 'coi_alien_phase_penetrate_research_networks_bury')
	},
	[pscustomobject]@{
		Id = 'coi_alien_spoil_the_evidence'; DisplayName = 'Spoil the Evidence'; Days = 60; Network = 40; Operatives = 2; Risk = '0.10';
		RiskModifier = 'target_sabotage_risk'; FactoryDays = 0; Required = @('coi_alien_token_institutional_access'); Awarded = @();
		NormalEffect = 'coi_alien_complete_spoil_the_evidence_effect'; ExtraEffect = '';
		Phases = @('coi_alien_phase_spoil_the_evidence_identify', 'coi_alien_phase_spoil_the_evidence_replace', 'coi_alien_phase_spoil_the_evidence_redirect')
	},
	[pscustomobject]@{
		Id = 'coi_alien_introduce_cascading_faults'; DisplayName = 'Introduce Cascading Faults'; Days = 90; Network = 60; Operatives = 3; Risk = '0.20';
		RiskModifier = 'target_sabotage_risk'; FactoryDays = 30; Required = @('coi_alien_token_institutional_access'); Awarded = @();
		NormalEffect = 'coi_alien_complete_introduce_cascading_faults_effect'; ExtraEffect = '';
		Phases = @('coi_alien_phase_introduce_cascading_faults_reconnoiter', 'coi_alien_phase_introduce_cascading_faults_seed', 'coi_alien_phase_introduce_cascading_faults_trigger')
	},
	[pscustomobject]@{
		Id = 'coi_alien_harvest_project_archives'; DisplayName = 'Harvest Project Archives'; Days = 120; Network = 60; Operatives = 3; Risk = '0.20';
		RiskModifier = 'operation_steal_tech_risk'; FactoryDays = 30; Required = @('coi_alien_token_research_access'); Awarded = @();
		NormalEffect = 'coi_alien_complete_harvest_project_archives_effect'; ExtraEffect = 'coi_alien_complete_harvest_project_archives_effect';
		Phases = @('coi_alien_phase_harvest_project_archives_classify', 'coi_alien_phase_harvest_project_archives_copy', 'coi_alien_phase_harvest_project_archives_sanitize')
	},
	[pscustomobject]@{
		Id = 'coi_alien_disrupt_research_complex'; DisplayName = 'Disrupt Research Complex'; Days = 105; Network = 60; Operatives = 3; Risk = '0.25';
		RiskModifier = 'operation_steal_tech_risk'; FactoryDays = 30; Required = @('coi_alien_token_research_access'); Awarded = @();
		NormalEffect = 'coi_alien_disrupt_research_complex_standard_effect'; ExtraEffect = 'coi_alien_disrupt_research_complex_bonus_effect';
		Phases = @('coi_alien_phase_disrupt_research_complex_fix', 'coi_alien_phase_disrupt_research_complex_infiltrate', 'coi_alien_phase_disrupt_research_complex_overload')
	},
	[pscustomobject]@{
		Id = 'coi_alien_extract_lead_scientist'; DisplayName = 'Extract Lead Scientist'; Days = 150; Network = 70; Operatives = 3; Risk = '0.30';
		RiskModifier = 'operation_steal_tech_risk'; FactoryDays = 45; Required = @('coi_alien_token_research_access'); Awarded = @();
		NormalEffect = 'coi_alien_complete_extract_lead_scientist'; ExtraEffect = 'coi_alien_complete_extract_lead_scientist';
		Phases = @('coi_alien_phase_extract_lead_scientist_contact', 'coi_alien_phase_extract_lead_scientist_substitute', 'coi_alien_phase_extract_lead_scientist_exfiltrate')
	}
)

$definedOperationIds = @([regex]::Matches($operationText, '(?m)^(coi_alien_[a-z0-9_]+)\s*=\s*\{') | ForEach-Object { $_.Groups[1].Value })
$expectedOperationIds = @($operationContracts | ForEach-Object { $_.Id })
if ($definedOperationIds.Count -ne 8 -or
	@($definedOperationIds | Where-Object { $_ -notin $expectedOperationIds }).Count -ne 0 -or
	@($expectedOperationIds | Where-Object { $_ -notin $definedOperationIds }).Count -ne 0) {
	Add-Failure "Quiet Chorus operation file must define only the exact eight contracted IDs; found [$($definedOperationIds -join ', ')]."
}
$serializedOperationTokens = @($operationDynamicTokenText -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object {
	$_.Length -gt 0 -and -not $_.StartsWith('#', [StringComparison]::Ordinal)
})
if ($serializedOperationTokens.Count -ne 8 -or
	@($serializedOperationTokens | Where-Object { $_ -notin $expectedOperationIds }).Count -ne 0 -or
	@($expectedOperationIds | Where-Object { ([regex]::Matches(($serializedOperationTokens -join "`n"), '(?m)^' + [regex]::Escape($_) + '$')).Count -ne 1 }).Count -ne 0) {
	Add-Failure "Synchronized operation-token database must serialize each exact operation ID once; found [$($serializedOperationTokens -join ', ')]."
}

foreach ($operation in $operationContracts) {
	$operationBlock = Get-UniqueContractBlock -Text $operationText -Assignment $operation.Id -Label 'Quiet Chorus operation file'
	if ($operationBlock.Length -eq 0) {
		continue
	}

	$scalarContracts = [ordered]@{
		name = $operation.Id
		days = [string]$operation.Days
		network_strength = [string]$operation.Network
		operatives = [string]$operation.Operatives
		risk_chance = $operation.Risk
	}
	foreach ($scalar in $scalarContracts.GetEnumerator()) {
		$pattern = '(?m)^\s*' + [regex]::Escape($scalar.Key) + '\s*=\s*' + [regex]::Escape($scalar.Value) + '\s*$'
		if ([regex]::Matches($operationBlock, $pattern).Count -ne 1) {
			Add-Failure "$($operation.Id) must declare $($scalar.Key) = $($scalar.Value) exactly once."
		}
	}

	$allowedBlock = Get-UniqueContractBlock -Text $operationBlock -Assignment 'allowed' -Label $operation.Id
	foreach ($allowedPattern in @(
		'(?m)^\s*original_tag\s*=\s*XAC\s*$',
		'(?m)^\s*has_dlc\s*=\s*"La Resistance"\s*$'
	)) {
		if ([regex]::Matches($allowedBlock, $allowedPattern).Count -ne 1) {
			Add-Failure "$($operation.Id) must be gated to XAC and La Resistance in its allowed block."
		}
	}
	if ($operationBlock -match '(?i)Gotterdammerung') {
		Add-Failure "$($operation.Id) must not hard-gate the operation card or target contract behind Gotterdammerung."
	}

	$riskModifierBlocks = @(Get-ClausewitzAssignedBlocks -Text $operationBlock -Assignment 'risk_modifiers')
	if ($riskModifierBlocks.Count -ne 1) {
		Add-Failure "$($operation.Id) must define exactly one risk_modifiers block."
	}
	else {
		$riskTokens = @([regex]::Matches($riskModifierBlocks[0], '\b(?:operation|target)_[a-z0-9_]+\b') | ForEach-Object { $_.Value })
		$expectedRiskTokens = @($operation.RiskModifier, 'operation_risk')
		if ($riskTokens.Count -ne 2 -or
			@($riskTokens | Where-Object { $_ -notin $expectedRiskTokens }).Count -ne 0 -or
			@($expectedRiskTokens | Where-Object { $_ -notin $riskTokens }).Count -ne 0) {
			Add-Failure "$($operation.Id) risk_modifiers must contain exactly $($operation.RiskModifier) and operation_risk."
		}
	}

	$equipmentBlocks = @(Get-ClausewitzAssignedBlocks -Text $operationBlock -Assignment 'equipment')
	if ($operation.FactoryDays -eq 0) {
		if ($equipmentBlocks.Count -ne 0) {
			Add-Failure "$($operation.Id) must have no preparation equipment cost."
		}
	}
	elseif ($equipmentBlocks.Count -ne 1) {
		Add-Failure "$($operation.Id) must define exactly one civilian-factory preparation cost."
	}
	else {
		$factoryBlocks = @(Get-ClausewitzAssignedBlocks -Text $equipmentBlocks[0] -Assignment 'civilian_factories')
		if ($factoryBlocks.Count -ne 1 -or
			[regex]::Matches($factoryBlocks[0], '(?m)^\s*amount\s*=\s*1\s*$').Count -ne 1 -or
			[regex]::Matches($factoryBlocks[0], '(?m)^\s*days\s*=\s*' + $operation.FactoryDays + '\s*$').Count -ne 1) {
			Add-Failure "$($operation.Id) must reserve one civilian factory for $($operation.FactoryDays) days."
		}
	}

	foreach ($tokenContract in @(
		[pscustomobject]@{ Assignment = 'required_tokens'; Values = @($operation.Required) },
		[pscustomobject]@{ Assignment = 'awarded_tokens'; Values = @($operation.Awarded) }
	)) {
		$tokenBlocks = @(Get-ClausewitzAssignedBlocks -Text $operationBlock -Assignment $tokenContract.Assignment)
		if ($tokenContract.Values.Count -eq 0) {
			if ($tokenBlocks.Count -ne 0) {
				Add-Failure "$($operation.Id) must omit $($tokenContract.Assignment)."
			}
		}
		elseif ($tokenBlocks.Count -ne 1) {
			Add-Failure "$($operation.Id) must define $($tokenContract.Assignment) exactly once."
		}
		else {
			$actualTokenIds = @([regex]::Matches($tokenBlocks[0], '\bcoi_alien_token_[a-z0-9_]+\b') | ForEach-Object { $_.Value })
			if ($actualTokenIds.Count -ne $tokenContract.Values.Count -or
				@($actualTokenIds | Where-Object { $_ -notin $tokenContract.Values }).Count -ne 0) {
				Add-Failure "$($operation.Id) has the wrong $($tokenContract.Assignment) contract."
			}
		}
	}

	$phaseReferences = @([regex]::Matches($operationBlock, '(?m)^\s*(coi_alien_phase_[a-z0-9_]+)\s*=\s*\{\s*base\s*=\s*100\s*\}\s*$') | ForEach-Object { $_.Groups[1].Value })
	if ($phaseReferences.Count -ne 3 -or
		@($phaseReferences | Where-Object { $_ -notin $operation.Phases }).Count -ne 0 -or
		@($operation.Phases | Where-Object { $_ -notin $phaseReferences }).Count -ne 0) {
		Add-Failure "$($operation.Id) must bind its exact three contracted phases at base 100."
	}

	# HOI4 selects outcome_extra_execute instead of outcome_execute when the
	# superior roll succeeds (common/operations/_documentation.md, Outcome).
	# Each branch must therefore invoke a complete result, including mandatory
	# cleanup/rewards; the extra branch is not an additive follow-up.
	$normalOutcome = Get-UniqueContractBlock -Text $operationBlock -Assignment 'outcome_execute' -Label $operation.Id
	if ([regex]::Matches($normalOutcome, '(?m)^\s*' + [regex]::Escape($operation.NormalEffect) + '\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "$($operation.Id) normal outcome must invoke $($operation.NormalEffect) exactly once."
	}
	$extraOutcomes = @(Get-ClausewitzAssignedBlocks -Text $operationBlock -Assignment 'outcome_extra_execute')
	if ([string]::IsNullOrEmpty($operation.ExtraEffect)) {
		if ($extraOutcomes.Count -ne 0) {
			Add-Failure "$($operation.Id) must not define a bonus outcome branch."
		}
	}
	elseif ($extraOutcomes.Count -ne 1 -or
		[regex]::Matches($extraOutcomes[0], '(?m)^\s*' + [regex]::Escape($operation.ExtraEffect) + '\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "$($operation.Id) bonus outcome must invoke $($operation.ExtraEffect) exactly once."
	}

	$displayNamePattern = '(?m)^\s*' + [regex]::Escape($operation.Id) + ':\d*\s*"' + [regex]::Escape($operation.DisplayName) + '"\s*$'
	if ([regex]::Matches($operationLocalisationText, $displayNamePattern).Count -ne 1) {
		Add-Failure "$($operation.Id) must localise exactly once as '$($operation.DisplayName)'."
	}
	foreach ($key in @($operation.Id, ($operation.Id + '_desc'), ($operation.Id + '_outcome_tt'))) {
		if (-not $localisationKeys.ContainsKey($key)) {
			Add-Failure "Missing Quiet Chorus operation localisation key $key."
		}
	}
}
Add-Pass 'Validated exact eight-operation Quiet Chorus timing, network, operative, risk, preparation, token, outcome, phase, and localisation contracts'

$tokenContracts = @(
	[pscustomobject]@{ Id = 'coi_alien_token_surface_profile'; DisplayName = 'Surface Profile' },
	[pscustomobject]@{ Id = 'coi_alien_token_institutional_access'; DisplayName = 'Institutional Access' },
	[pscustomobject]@{ Id = 'coi_alien_token_research_access'; DisplayName = 'Research Access' }
)
$definedTokenIds = @([regex]::Matches($operationTokenText, '(?m)^(coi_alien_token_[a-z0-9_]+)\s*=\s*\{') | ForEach-Object { $_.Groups[1].Value })
if ($definedTokenIds.Count -ne 3 -or @($definedTokenIds | Where-Object { $_ -notin $tokenContracts.Id }).Count -ne 0) {
	Add-Failure "Quiet Chorus token database must define only the exact three access tokens; found [$($definedTokenIds -join ', ')]."
}
foreach ($token in $tokenContracts) {
	$tokenBlock = Get-UniqueContractBlock -Text $operationTokenText -Assignment $token.Id -Label 'Quiet Chorus operation-token file'
	$tokenLineContracts = [ordered]@{
		name = $token.Id
		desc = ($token.Id + '_desc')
		icon = ('GFX_' + $token.Id)
		text_icon = ('GFX_' + $token.Id + '_text')
	}
	foreach ($line in $tokenLineContracts.GetEnumerator()) {
		if ([regex]::Matches($tokenBlock, '(?m)^\s*' + $line.Key + '\s*=\s*' + [regex]::Escape($line.Value) + '\s*$').Count -ne 1) {
			Add-Failure "$($token.Id) must bind exact $($line.Key) value $($line.Value)."
		}
	}
	foreach ($key in @($token.Id, ($token.Id + '_desc'))) {
		if (-not $localisationKeys.ContainsKey($key)) {
			Add-Failure "Missing access-token localisation key $key."
		}
	}
	$displayNamePattern = '(?m)^\s*' + [regex]::Escape($token.Id) + ':\d*\s*"' + [regex]::Escape($token.DisplayName) + '"\s*$'
	if ([regex]::Matches($operationLocalisationText, $displayNamePattern).Count -ne 1) {
		Add-Failure "$($token.Id) must localise exactly once as '$($token.DisplayName)'."
	}
}

$upgradeContracts = @(
	[pscustomobject]@{
		Id = 'coi_alien_upgrade_mimetic_interface_lab'; DisplayName = 'Mimetic Interface Lab'; Threshold = 1; Comparison = '0';
		Focus = 'coi_alien_observe_divided_world'; Previous = ''; Modifier = 'operation_infiltrate_risk'; ModifierValue = '-0.05'
	},
	[pscustomobject]@{
		Id = 'coi_alien_upgrade_cognitive_translation_matrix'; DisplayName = 'Cognitive Translation Matrix'; Threshold = 3; Comparison = '2';
		Focus = 'coi_alien_classify_human_order'; Previous = 'coi_alien_upgrade_mimetic_interface_lab'; Modifier = 'operation_steal_tech_outcome'; ModifierValue = '0.10'
	},
	[pscustomobject]@{
		Id = 'coi_alien_upgrade_distributed_drone_cells'; DisplayName = 'Distributed Drone Cells'; Threshold = 5; Comparison = '4';
		Focus = ''; Previous = 'coi_alien_upgrade_cognitive_translation_matrix'; Modifier = 'operative_slot'; ModifierValue = '1'
	}
)
$definedUpgradeIds = @([regex]::Matches($operationUpgradeText, '(?m)^\s*(coi_alien_upgrade_[a-z0-9_]+)\s*=\s*\{') | ForEach-Object { $_.Groups[1].Value })
if ($definedUpgradeIds.Count -ne 3 -or @($definedUpgradeIds | Where-Object { $_ -notin $upgradeContracts.Id }).Count -ne 0) {
	Add-Failure "Quiet Chorus agency branch must define only the exact three custom upgrades; found [$($definedUpgradeIds -join ', ')]."
}
if (@(Get-ClausewitzAssignedBlocks -Text $operationUpgradeText -Assignment 'coi_alien_branch_quiet_chorus').Count -ne 1) {
	Add-Failure 'Quiet Chorus intelligence upgrades must live in exactly one coi_alien_branch_quiet_chorus branch.'
}
foreach ($upgrade in $upgradeContracts) {
	$upgradeBlock = Get-UniqueContractBlock -Text $operationUpgradeText -Assignment $upgrade.Id -Label 'Quiet Chorus agency-upgrade file'
	if ([regex]::Matches($upgradeBlock, '(?m)^\s*picture\s*=\s*GFX_' + [regex]::Escape($upgrade.Id) + '\s*$').Count -ne 1) {
		Add-Failure "$($upgrade.Id) must use its custom GFX_$($upgrade.Id) picture."
	}
	$visibleBlock = Get-UniqueContractBlock -Text $upgradeBlock -Assignment 'visible' -Label $upgrade.Id
	if ([regex]::Matches($visibleBlock, '(?m)^\s*original_tag\s*=\s*XAC\s*$').Count -ne 1 -or
		[regex]::Matches($visibleBlock, '(?m)^\s*has_dlc\s*=\s*"La Resistance"\s*$').Count -ne 1) {
		Add-Failure "$($upgrade.Id) must be visible only to XAC with La Resistance."
	}

	$availableBlock = Get-UniqueContractBlock -Text $upgradeBlock -Assignment 'available' -Label $upgrade.Id
	$focusMatches = [regex]::Matches($availableBlock, '(?m)^\s*has_completed_focus\s*=\s*(coi_alien_[a-z0-9_]+)\s*$')
	if ([string]::IsNullOrEmpty($upgrade.Focus)) {
		if ($focusMatches.Count -ne 0) {
			Add-Failure "$($upgrade.Id) must not add an extra focus gate beyond the preceding upgrade."
		}
	}
	elseif ($focusMatches.Count -ne 1 -or $focusMatches[0].Groups[1].Value -cne $upgrade.Focus) {
		Add-Failure "$($upgrade.Id) must require focus $($upgrade.Focus) exactly once."
	}
	$previousMatches = [regex]::Matches($availableBlock, '(?m)^\s*has_done_agency_upgrade\s*=\s*(coi_alien_upgrade_[a-z0-9_]+)\s*$')
	if ([string]::IsNullOrEmpty($upgrade.Previous)) {
		if ($previousMatches.Count -ne 0) {
			Add-Failure "$($upgrade.Id) must be the first upgrade in the chain."
		}
	}
	elseif ($previousMatches.Count -ne 1 -or $previousMatches[0].Groups[1].Value -cne $upgrade.Previous) {
		Add-Failure "$($upgrade.Id) must require preceding upgrade $($upgrade.Previous)."
	}
	$surveyPattern = '(?m)^\s*check_variable\s*=\s*\{\s*coi_alien_survey_data\s*>\s*' + $upgrade.Comparison + '\s*\}\s*$'
	$tooltipPattern = '(?m)^\s*tooltip\s*=\s*coi_alien_requires_survey_data_' + $upgrade.Threshold + '_tt\s*$'
	if ([regex]::Matches($availableBlock, $surveyPattern).Count -ne 1 -or
		[regex]::Matches($availableBlock, $tooltipPattern).Count -ne 1) {
		Add-Failure "$($upgrade.Id) must enforce the exact Survey Data >= $($upgrade.Threshold) tooltip and threshold."
	}

	$progressBlock = Get-UniqueContractBlock -Text $upgradeBlock -Assignment 'modifiers_during_progress' -Label $upgrade.Id
	if ([regex]::Matches($progressBlock, '(?m)^\s*civilian_factory_use\s*=\s*1\s*$').Count -ne 1) {
		Add-Failure "$($upgrade.Id) must reserve exactly one civilian factory during its standard 30-day agency-upgrade build."
	}
	$levelBlock = Get-UniqueContractBlock -Text $upgradeBlock -Assignment 'level' -Label $upgrade.Id
	if ([regex]::Matches($levelBlock, '(?m)^\s*' + [regex]::Escape($upgrade.Modifier) + '\s*=\s*' + [regex]::Escape($upgrade.ModifierValue) + '\s*$').Count -ne 1) {
		Add-Failure "$($upgrade.Id) must apply $($upgrade.Modifier) = $($upgrade.ModifierValue)."
	}
	foreach ($key in @($upgrade.Id, ($upgrade.Id + '_desc'), ('coi_alien_requires_survey_data_' + $upgrade.Threshold + '_tt'))) {
		if (-not $localisationKeys.ContainsKey($key)) {
			Add-Failure "Missing Quiet Chorus upgrade localisation key $key."
		}
	}
	$displayNamePattern = '(?m)^\s*' + [regex]::Escape($upgrade.Id) + ':\d*\s*"' + [regex]::Escape($upgrade.DisplayName) + '"\s*$'
	if ([regex]::Matches($operationLocalisationText, $displayNamePattern).Count -ne 1) {
		Add-Failure "$($upgrade.Id) must localise exactly once as '$($upgrade.DisplayName)'."
	}
}
Add-Pass 'Validated exact three-token access ladder and three-upgrade XAC/La Resistance, focus, Survey Data, factory, picture, and modifier contracts'

$expectedPhaseIds = @($operationContracts | ForEach-Object { $_.Phases } | ForEach-Object { $_ })
$definedPhaseIds = @([regex]::Matches($operationPhaseText, '(?m)^(coi_alien_phase_[a-z0-9_]+)\s*=\s*\{') | ForEach-Object { $_.Groups[1].Value })
if ($definedPhaseIds.Count -ne 24 -or
	@($definedPhaseIds | Where-Object { $_ -notin $expectedPhaseIds }).Count -ne 0 -or
	@($expectedPhaseIds | Where-Object { $_ -notin $definedPhaseIds }).Count -ne 0) {
	Add-Failure "Quiet Chorus phase database must define only the exact 24 contracted phases; found $($definedPhaseIds.Count)."
}
foreach ($operation in $operationContracts) {
	for ($phaseIndex = 0; $phaseIndex -lt $operation.Phases.Count; $phaseIndex++) {
		$phaseId = $operation.Phases[$phaseIndex]
		$phaseBlock = Get-UniqueContractBlock -Text $operationPhaseText -Assignment $phaseId -Label 'Quiet Chorus operation-phase file'
		$phaseLineContracts = [ordered]@{
			name = $phaseId
			desc = ($phaseId + '_desc')
			icon = ('GFX_' + ($operation.Id -replace '^coi_alien_', 'coi_alien_operation_') + '_phase_icon')
			picture = ('GFX_' + ($operation.Id -replace '^coi_alien_', 'coi_alien_operation_') + '_phase_picture')
			outcome = ($phaseId + '_outcome')
		}
		foreach ($line in $phaseLineContracts.GetEnumerator()) {
			if ([regex]::Matches($phaseBlock, '(?m)^\s*' + $line.Key + '\s*=\s*' + [regex]::Escape($line.Value) + '\s*$').Count -ne 1) {
				Add-Failure "$phaseId must bind exact $($line.Key) value $($line.Value)."
			}
		}
		$riskMatches = [regex]::Matches($phaseBlock, '(?m)^\s*risk_extra\s*=\s*(coi_alien_phase_[a-z0-9_]+_risk)\s*$')
		if ($phaseIndex -eq 2) {
			if ($riskMatches.Count -ne 1 -or $riskMatches[0].Groups[1].Value -cne ($phaseId + '_risk')) {
				Add-Failure "$phaseId must own the operation's one final risk localisation hook."
			}
		}
		elseif ($riskMatches.Count -ne 0) {
			Add-Failure "$phaseId must not define an early risk_extra hook."
		}
		foreach ($key in @($phaseId, ($phaseId + '_desc'), ($phaseId + '_outcome'))) {
			if (-not $localisationKeys.ContainsKey($key)) {
				Add-Failure "Missing operation-phase localisation key $key."
			}
		}
		if ($phaseIndex -eq 2 -and -not $localisationKeys.ContainsKey($phaseId + '_risk')) {
			Add-Failure "Missing operation-phase risk localisation key $($phaseId + '_risk')."
		}
	}
}
Add-Pass 'Validated all 24 operation phases and their exact per-operation icon, picture, outcome, risk, and localisation bindings'

$surveyCompletionBlock = Get-UniqueContractBlock -Text $operationEffectText -Assignment 'coi_alien_complete_silent_systems_survey_effect' -Label 'Quiet Chorus completion effects'
Test-TokenMutationContract -Block $surveyCompletionBlock -Assignment 'add_operation_token' -ExpectedTokens @('coi_alien_token_surface_profile') -Label 'Silent Systems Survey'
Test-TokenMutationContract -Block $surveyCompletionBlock -Assignment 'remove_operation_token' -ExpectedTokens @() -Label 'Silent Systems Survey'
if ([regex]::Matches($surveyCompletionBlock, '(?m)^\s*coi_alien_add_survey_data_one_effect\s*=\s*yes\s*$').Count -ne 1) {
	Add-Failure 'Silent Systems Survey must add exactly one cumulative Survey Data.'
}
Test-AwarenessRandomContract -Block $surveyCompletionBlock -AwarenessWeight 20 -NoEffectWeight 80 -Label 'Silent Systems Survey'

$seedCompletionBlock = Get-UniqueContractBlock -Text $operationEffectText -Assignment 'coi_alien_complete_seed_mimetic_access_effect' -Label 'Quiet Chorus completion effects'
Test-TokenMutationContract -Block $seedCompletionBlock -Assignment 'add_operation_token' -ExpectedTokens @('coi_alien_token_institutional_access') -Label 'Seed Mimetic Access'
Test-TokenMutationContract -Block $seedCompletionBlock -Assignment 'remove_operation_token' -ExpectedTokens @() -Label 'Seed Mimetic Access'
if ($seedCompletionBlock -match '\bcoi_alien_add_survey_data_(?:one|two|three)_effect\b') {
	Add-Failure 'Seed Mimetic Access must not add Survey Data.'
}
Test-AwarenessRandomContract -Block $seedCompletionBlock -AwarenessWeight 25 -NoEffectWeight 75 -Label 'Seed Mimetic Access'

$penetrateCompletionBlock = Get-UniqueContractBlock -Text $operationEffectText -Assignment 'coi_alien_complete_penetrate_research_networks_effect' -Label 'Quiet Chorus completion effects'
Test-TokenMutationContract -Block $penetrateCompletionBlock -Assignment 'add_operation_token' -ExpectedTokens @('coi_alien_token_research_access') -Label 'Penetrate Research Networks'
Test-TokenMutationContract -Block $penetrateCompletionBlock -Assignment 'remove_operation_token' -ExpectedTokens @() -Label 'Penetrate Research Networks'
if ([regex]::Matches($penetrateCompletionBlock, '(?m)^\s*coi_alien_add_survey_data_one_effect\s*=\s*yes\s*$').Count -ne 1) {
	Add-Failure 'Penetrate Research Networks must add exactly one cumulative Survey Data.'
}
Test-AwarenessRandomContract -Block $penetrateCompletionBlock -AwarenessWeight 35 -NoEffectWeight 65 -Label 'Penetrate Research Networks'

$spoilCompletionBlock = Get-UniqueContractBlock -Text $operationEffectText -Assignment 'coi_alien_complete_spoil_the_evidence_effect' -Label 'Quiet Chorus completion effects'
Test-TokenMutationContract -Block $spoilCompletionBlock -Assignment 'add_operation_token' -ExpectedTokens @() -Label 'Spoil the Evidence'
Test-TokenMutationContract -Block $spoilCompletionBlock -Assignment 'remove_operation_token' -ExpectedTokens @('coi_alien_token_institutional_access', 'coi_alien_token_research_access') -Label 'Spoil the Evidence'
$investigationFlagBlocks = @(Get-ClausewitzAssignedBlocks -Text $spoilCompletionBlock -Assignment 'set_country_flag')
if ($investigationFlagBlocks.Count -ne 1 -or
	[regex]::Matches($investigationFlagBlocks[0], '(?m)^\s*flag\s*=\s*coi_alien_investigation_disrupted\s*$').Count -ne 1 -or
	[regex]::Matches($investigationFlagBlocks[0], '(?m)^\s*value\s*=\s*1\s*$').Count -ne 1 -or
	[regex]::Matches($investigationFlagBlocks[0], '(?m)^\s*days\s*=\s*180\s*$').Count -ne 1) {
	Add-Failure 'Spoil the Evidence must set coi_alien_investigation_disrupted for exactly 180 days.'
}
Test-AwarenessRandomContract -Block $spoilCompletionBlock -AwarenessWeight 20 -NoEffectWeight 80 -Label 'Spoil the Evidence'

$cascadingCompletionBlock = Get-UniqueContractBlock -Text $operationEffectText -Assignment 'coi_alien_complete_introduce_cascading_faults_effect' -Label 'Quiet Chorus completion effects'
Test-TokenMutationContract -Block $cascadingCompletionBlock -Assignment 'add_operation_token' -ExpectedTokens @() -Label 'Introduce Cascading Faults'
Test-TokenMutationContract -Block $cascadingCompletionBlock -Assignment 'remove_operation_token' -ExpectedTokens @('coi_alien_token_institutional_access', 'coi_alien_token_research_access') -Label 'Introduce Cascading Faults'
$cascadingDamageBlocks = @(Get-ClausewitzAssignedBlocks -Text $cascadingCompletionBlock -Assignment 'damage_building')
$expectedCascadingBuildings = @('infrastructure', 'radar_station', 'air_base', 'naval_base')
if ($cascadingDamageBlocks.Count -ne 4) {
	Add-Failure "Introduce Cascading Faults must define exactly four contracted damage branches; found $($cascadingDamageBlocks.Count)."
}
foreach ($building in $expectedCascadingBuildings) {
	$buildingBlocks = @($cascadingDamageBlocks | Where-Object {
		[regex]::Matches($_, '(?m)^\s*type\s*=\s*' + [regex]::Escape($building) + '\s*$').Count -eq 1
	})
	if ($buildingBlocks.Count -ne 1 -or
		[regex]::Matches($buildingBlocks[0], '(?m)^\s*damage\s*=\s*1\s*$').Count -ne 1 -or
		[regex]::Matches($buildingBlocks[0], '(?m)^\s*repair_speed_modifier\s*=\s*-0\.25\s*$').Count -ne 1) {
		Add-Failure "Introduce Cascading Faults must damage $building by 1 with -0.25 repair speed exactly once."
	}
}
$nodePositions = @($expectedCascadingBuildings | Select-Object -Skip 1 | ForEach-Object {
	$cascadingCompletionBlock.IndexOf("type = $_", [StringComparison]::Ordinal)
})
if ($nodePositions.Count -ne 3 -or $nodePositions[0] -lt 0 -or $nodePositions[1] -le $nodePositions[0] -or $nodePositions[2] -le $nodePositions[1]) {
	Add-Failure 'Introduce Cascading Faults must retain deterministic Radar Station -> Air Base -> Naval Base damage priority.'
}
$cascadingIdeaBlocks = @(Get-ClausewitzAssignedBlocks -Text $cascadingCompletionBlock -Assignment 'add_timed_idea')
if ($cascadingIdeaBlocks.Count -ne 1 -or
	[regex]::Matches($cascadingIdeaBlocks[0], '(?m)^\s*idea\s*=\s*coi_alien_cascading_faults\s*$').Count -ne 1 -or
	[regex]::Matches($cascadingIdeaBlocks[0], '(?m)^\s*days\s*=\s*90\s*$').Count -ne 1) {
	Add-Failure 'Introduce Cascading Faults must apply its target-country penalty for exactly 90 days.'
}
if ([regex]::Matches($cascadingCompletionBlock, '(?m)^\s*coi_alien_raise_awareness_one_effect\s*=\s*yes\s*$').Count -ne 1) {
	Add-Failure 'Introduce Cascading Faults must raise target awareness exactly once.'
}
$cascadingIdeaBlock = Get-UniqueContractBlock -Text $operationIdeaText -Assignment 'coi_alien_cascading_faults' -Label 'Quiet Chorus operation ideas'
foreach ($ideaModifier in @(
	[pscustomobject]@{ Name = 'supply_factor'; Value = '-0.05' },
	[pscustomobject]@{ Name = 'repair_speed_factor'; Value = '-0.10' }
)) {
	if ([regex]::Matches($cascadingIdeaBlock, '(?m)^\s*' + $ideaModifier.Name + '\s*=\s*' + [regex]::Escape($ideaModifier.Value) + '\s*$').Count -ne 1) {
		Add-Failure "Cascading Faults idea must apply $($ideaModifier.Name) = $($ideaModifier.Value)."
	}
}

$archiveCompletionBlock = Get-UniqueContractBlock -Text $operationEffectText -Assignment 'coi_alien_complete_harvest_project_archives_effect' -Label 'Quiet Chorus completion effects'
Test-TokenMutationContract -Block $archiveCompletionBlock -Assignment 'add_operation_token' -ExpectedTokens @() -Label 'Harvest Project Archives'
Test-TokenMutationContract -Block $archiveCompletionBlock -Assignment 'remove_operation_token' -ExpectedTokens @('coi_alien_token_research_access') -Label 'Harvest Project Archives'
if ([regex]::Matches($archiveCompletionBlock, '(?m)^\s*coi_alien_add_survey_data_two_effect\s*=\s*yes\s*$').Count -ne 1) {
	Add-Failure 'Harvest Project Archives must add exactly two cumulative Survey Data.'
}
$archiveTechBonusBlocks = @(Get-ClausewitzAssignedBlocks -Text $archiveCompletionBlock -Assignment 'add_tech_bonus')
if ($archiveTechBonusBlocks.Count -ne 1 -or
	[regex]::Matches($archiveTechBonusBlocks[0], '(?m)^\s*bonus\s*=\s*1\.0\s*$').Count -ne 1 -or
	[regex]::Matches($archiveTechBonusBlocks[0], '(?m)^\s*uses\s*=\s*1\s*$').Count -ne 1 -or
	[regex]::Matches($archiveTechBonusBlocks[0], '(?m)^\s*category\s*=\s*coi_alien_science\s*$').Count -ne 1) {
	Add-Failure 'Harvest Project Archives must grant one 100% Alien Science research bonus.'
}
Test-AwarenessRandomContract -Block $archiveCompletionBlock -AwarenessWeight 40 -NoEffectWeight 60 -Label 'Harvest Project Archives'

$archiveBreakthroughBlock = Get-UniqueContractBlock -Text $operationEffectText -Assignment 'coi_alien_grant_archive_breakthrough_effect' -Label 'Quiet Chorus completion effects'
if ([regex]::Matches($archiveBreakthroughBlock, '\bhas_dlc\s*=\s*"Gotterdammerung"').Count -ne 1) {
	Add-Failure 'Only the optional archive breakthrough must be explicitly gated behind Gotterdammerung.'
}
$breakthroughBlocks = @(Get-ClausewitzAssignedBlocks -Text $archiveBreakthroughBlock -Assignment 'add_breakthrough_progress')
if ($breakthroughBlocks.Count -ne 1 -or
	[regex]::Matches($breakthroughBlocks[0], '(?m)^\s*specialization\s*=\s*coi_alien_specialization_matter_fabrication\s*$').Count -ne 1 -or
	[regex]::Matches($breakthroughBlocks[0], '(?m)^\s*value\s*=\s*0\.1\s*$').Count -ne 1) {
	Add-Failure 'Archive superior outcome must grant exactly 0.1 Consensus Sciences breakthrough progress.'
}
foreach ($humanSpecialization in @('specialization_land', 'specialization_air', 'specialization_naval', 'specialization_nuclear')) {
	if ([regex]::Matches($archiveBreakthroughBlock, '(?m)^\s*specialization\s*=\s*' + $humanSpecialization + '\s*$').Count -ne 0) {
		Add-Failure "Archive superior outcome must not grant human $humanSpecialization breakthrough progress."
	}
}
$archiveOperationBlock = Get-UniqueContractBlock -Text $operationText -Assignment 'coi_alien_harvest_project_archives' -Label 'Quiet Chorus operation file'
$archiveNormalOutcome = Get-UniqueContractBlock -Text $archiveOperationBlock -Assignment 'outcome_execute' -Label 'Harvest Project Archives'
$archiveExtraOutcome = Get-UniqueContractBlock -Text $archiveOperationBlock -Assignment 'outcome_extra_execute' -Label 'Harvest Project Archives'
if ($archiveNormalOutcome -match '\bcoi_alien_grant_archive_breakthrough_effect\b' -or
	[regex]::Matches($archiveExtraOutcome, '(?m)^\s*coi_alien_grant_archive_breakthrough_effect\s*=\s*yes\s*$').Count -ne 1) {
	Add-Failure 'Only the archive superior branch may add the optional breakthrough after executing the mandatory shared result.'
}

$disruptSharedBlock = Get-UniqueContractBlock -Text $operationEffectText -Assignment 'coi_alien_complete_disrupt_research_complex_effect' -Label 'Quiet Chorus completion effects'
Test-TokenMutationContract -Block $disruptSharedBlock -Assignment 'add_operation_token' -ExpectedTokens @() -Label 'Disrupt Research Complex shared result'
Test-TokenMutationContract -Block $disruptSharedBlock -Assignment 'remove_operation_token' -ExpectedTokens @('coi_alien_token_institutional_access', 'coi_alien_token_research_access') -Label 'Disrupt Research Complex shared result'
if ([regex]::Matches($disruptSharedBlock, '(?m)^\s*coi_alien_raise_awareness_one_effect\s*=\s*yes\s*$').Count -ne 1) {
	Add-Failure 'Both Disrupt Research Complex outcomes must share one guaranteed awareness increase.'
}
foreach ($disruptVariant in @(
	[pscustomobject]@{ Id = 'coi_alien_disrupt_research_complex_standard_effect'; Damage = '0.5'; InjuryDays = 45 },
	[pscustomobject]@{ Id = 'coi_alien_disrupt_research_complex_bonus_effect'; Damage = '0.8'; InjuryDays = 90 }
)) {
	$variantBlock = Get-UniqueContractBlock -Text $operationEffectText -Assignment $disruptVariant.Id -Label 'Disrupt Research Complex outcome effects'
	if ([regex]::Matches($variantBlock, '(?m)^\s*coi_alien_complete_disrupt_research_complex_effect\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "$($disruptVariant.Id) must execute the shared token/awareness result exactly once."
	}
	$facilityDamageBlocks = @(Get-ClausewitzAssignedBlocks -Text $variantBlock -Assignment 'damage_building')
	if ($facilityDamageBlocks.Count -ne 1 -or
		[regex]::Matches($facilityDamageBlocks[0], '(?m)^\s*tags\s*=\s*facility\s*$').Count -ne 1 -or
		[regex]::Matches($facilityDamageBlocks[0], '(?m)^\s*damage\s*=\s*' + [regex]::Escape($disruptVariant.Damage) + '\s*$').Count -ne 1 -or
		[regex]::Matches($facilityDamageBlocks[0], '(?m)^\s*repair_speed_modifier\s*=\s*-0\.50\s*$').Count -ne 1) {
		Add-Failure "$($disruptVariant.Id) must damage the selected facility by $($disruptVariant.Damage) with -0.50 repair speed."
	}
	$scientistSelectionBlocks = @(Get-ClausewitzAssignedBlocks -Text $variantBlock -Assignment 'random_scientist')
	if ($scientistSelectionBlocks.Count -ne 1 -or
		[regex]::Matches($scientistSelectionBlocks[0], '(?m)^\s*coi_alien_extractable_scientist_character_trigger\s*=\s*yes\s*$').Count -ne 1 -or
		[regex]::Matches($scientistSelectionBlocks[0], '(?m)^\s*is_in_state\s*=\s*FROM\.FROM\s*$').Count -ne 1 -or
		[regex]::Matches($scientistSelectionBlocks[0], '(?m)^\s*injure_scientist_for_days\s*=\s*' + $disruptVariant.InjuryDays + '\s*$').Count -ne 1) {
		Add-Failure "$($disruptVariant.Id) must injure one revalidated facility scientist for $($disruptVariant.InjuryDays) days."
	}
}

$operationAndTargetTriggerText = $operationText + "`n" + $operationTriggerText
if ($operationAndTargetTriggerText -match '(?i)Gotterdammerung') {
	Add-Failure 'Quiet Chorus operation definitions and operation-target triggers must not hard-gate behind Gotterdammerung.'
}
$operationEffectWithoutArchiveGate = $operationEffectText.Replace($archiveBreakthroughBlock, '')
if ($operationEffectWithoutArchiveGate -match '(?i)Gotterdammerung') {
	Add-Failure 'The optional archive-breakthrough effect must be the only Gotterdammerung gate in Quiet Chorus operation effects.'
}

$investigationDecisionIds = @(
	'coi_alien_investigate_anomalies',
	'coi_alien_form_investigation_cell',
	'coi_alien_mobilize_against_extraterrestrial_threat'
)
foreach ($decisionId in $investigationDecisionIds) {
	$decisionBlock = Get-UniqueContractBlock -Text $awarenessDecisionText -Assignment $decisionId -Label 'Alien-awareness investigation decisions'
	$visibleBlock = Get-UniqueContractBlock -Text $decisionBlock -Assignment 'visible' -Label $decisionId
	if ([regex]::Matches($visibleBlock, '(?m)^\s*NOT\s*=\s*\{\s*has_country_flag\s*=\s*coi_alien_investigation_disrupted\s*\}\s*$').Count -ne 1 -or
		[regex]::Matches($decisionBlock, '(?m)^\s*cancel_if_not_visible\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "$decisionId must hide and cancel while coi_alien_investigation_disrupted is active."
	}
}

$legacyDecisionIds = @('coi_alien_silent_survey', 'coi_alien_specimen_acquisition', 'coi_alien_infrastructure_probe')
foreach ($decisionId in $legacyDecisionIds) {
	$decisionBlock = Get-UniqueContractBlock -Text $awarenessDecisionText -Assignment $decisionId -Label 'Legacy alien-operation compatibility decisions'
	$visibleBlocks = @(Get-ClausewitzAssignedBlocks -Text $decisionBlock -Assignment 'visible')
	$allowedBlocks = @(Get-ClausewitzAssignedBlocks -Text $decisionBlock -Assignment 'allowed')
	$aiBlocks = @(Get-ClausewitzAssignedBlocks -Text $decisionBlock -Assignment 'ai_will_do')
	if ($visibleBlocks.Count -ne 1 -or [regex]::Matches($visibleBlocks[0], '\balways\s*=\s*no\b').Count -ne 1 -or
		$allowedBlocks.Count -ne 1 -or [regex]::Matches($allowedBlocks[0], '\balways\s*=\s*no\b').Count -ne 1 -or
		$aiBlocks.Count -ne 1 -or [regex]::Matches($aiBlocks[0], '(?m)^\s*base\s*=\s*0\s*$').Count -ne 1) {
		Add-Failure "$decisionId must remain a hidden, disallowed, AI-zero old-save compatibility shell."
	}
}

$surveyScriptFiles = Get-ChildItem -LiteralPath $modRoot -Recurse -File -Filter '*.txt' |
	Where-Object { $_.FullName -match '\\(?:common|events)\\' }
$surveyScriptText = ($surveyScriptFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
$surveyMutationPattern = '(?is)\b(set_variable|add_to_variable|subtract_from_variable|multiply_variable|divide_variable)\s*=\s*\{\s*coi_alien_survey_data\s*=\s*(-?\d+(?:\.\d+)?)\s*\}'
$surveyMutations = [regex]::Matches($surveyScriptText, $surveyMutationPattern)
if ($surveyMutations.Count -eq 0) {
	Add-Failure 'No Survey Data mutations were found; the cumulative reconnaissance ledger is disconnected.'
}
foreach ($mutation in $surveyMutations) {
	$verb = $mutation.Groups[1].Value
	$value = [double]::Parse($mutation.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
	if (($verb -eq 'set_variable' -and $value -ne 0) -or
		($verb -eq 'add_to_variable' -and $value -le 0) -or
		($verb -notin @('set_variable', 'add_to_variable'))) {
		Add-Failure "Survey Data must be globally cumulative; forbidden mutation found: $($mutation.Value.Trim())."
	}
}
Add-Pass 'Validated exact access-token transitions, Survey Data gains, awareness probabilities, investigation suppression, sabotage, archive, and both research-complex outcome branches'
Add-Pass 'Validated globally cumulative Survey Data and hidden AI-zero compatibility decisions'

$operationPlannerBlock = Get-UniqueContractBlock -Text $operationAiEffectText -Assignment 'coi_alien_update_operation_ai_effect' -Label 'Quiet Chorus AI effects'
$operationClearPlanBlock = Get-UniqueContractBlock -Text $operationAiEffectText -Assignment 'coi_alien_clear_operation_ai_plan_effect' -Label 'Quiet Chorus AI effects'
foreach ($plannerVariable in @('coi_alien_ai_operation_target', 'coi_alien_ai_operation_type')) {
	if ([regex]::Matches($operationClearPlanBlock, '(?m)^\s*set_variable\s*=\s*\{\s*' + $plannerVariable + '\s*=\s*0\s*\}\s*$').Count -ne 1) {
		Add-Failure "Quiet Chorus AI clear effect must reset $plannerVariable exactly once."
	}
}
if ([regex]::Matches($operationPlannerBlock, '\boriginal_tag\s*=\s*XAC\b').Count -lt 1 -or
	[regex]::Matches($operationPlannerBlock, '\bhas_dlc\s*=\s*"La Resistance"').Count -lt 1 -or
	[regex]::Matches($operationPlannerBlock, '\bhas_intelligence_agency\s*=\s*yes\b').Count -lt 1) {
	Add-Failure 'Quiet Chorus AI planner must shut down outside AI-controlled XAC with La Resistance and an agency.'
}
$targetSelectionBlocks = @(Get-ClausewitzAssignedBlocks -Text $operationPlannerBlock -Assignment 'get_highest_scored_country')
if ($targetSelectionBlocks.Count -ne 1 -or
	[regex]::Matches($targetSelectionBlocks[0], '(?m)^\s*scorer\s*=\s*coi_alien_quiet_chorus_target_scorer\s*$').Count -ne 1 -or
	[regex]::Matches($targetSelectionBlocks[0], '(?m)^\s*var\s*=\s*coi_alien_ai_operation_target\s*$').Count -ne 1) {
	Add-Failure 'Quiet Chorus AI planner must select its target through coi_alien_quiet_chorus_target_scorer.'
}
foreach ($operationId in $expectedOperationIds) {
	if ([regex]::Matches($operationPlannerBlock, '\btoken:' + [regex]::Escape($operationId) + '\b').Count -lt 1) {
		Add-Failure "Quiet Chorus AI planner never serializes operation $operationId."
	}
}
$plannerTechGateCounts = [ordered]@{
	coi_alien_multi_agent_infiltration_models = 1
	coi_alien_institutional_behavior_prediction = 3
	coi_alien_cascading_failure_models = 2
	coi_alien_deep_substitution_architecture = 2
	coi_alien_atomic_disruption_protocols = 1
}
foreach ($plannerTechGate in $plannerTechGateCounts.GetEnumerator()) {
	$gatePattern = '(?m)^\s*has_tech\s*=\s*' + [regex]::Escape($plannerTechGate.Key) + '\s*$'
	$actualGateCount = [regex]::Matches($operationPlannerBlock, $gatePattern).Count
	if ($actualGateCount -ne $plannerTechGate.Value) {
		Add-Failure "Quiet Chorus AI planner must apply $($plannerTechGate.Key) exactly $($plannerTechGate.Value) time(s); found $actualGateCount."
	}
}
if ([regex]::Matches($operationPlannerBlock, '(?m)^\s*set_country_flag\s*=\s*coi_alien_operation_ai_v1_initialized\s*$').Count -ne 1) {
	Add-Failure 'Quiet Chorus AI planner must commit its versioned initialization flag exactly once.'
}

$operationStrategyBlock = Get-UniqueContractBlock -Text $operationAiStrategyText -Assignment 'coi_alien_run_quiet_chorus_operation' -Label 'Quiet Chorus AI strategy'
foreach ($strategyPattern in @(
	'(?m)^\s*type\s*=\s*operative_operation\s*$',
	'(?m)^\s*operation\s*=\s*var:coi_alien_ai_operation_type\s*$',
	'(?m)^\s*operation_target\s*=\s*var:coi_alien_ai_operation_target\s*$',
	'(?m)^\s*value\s*=\s*950\s*$'
)) {
	if ([regex]::Matches($operationStrategyBlock, $strategyPattern).Count -ne 1) {
		Add-Failure "Quiet Chorus operative-operation AI strategy is missing or duplicates exact contract: $strategyPattern"
	}
}

$targetScorerBlock = Get-UniqueContractBlock -Text $operationTargetScorerText -Assignment 'coi_alien_quiet_chorus_target_scorer' -Label 'Quiet Chorus target scorer'
$scorerModifierBlocks = @(Get-ClausewitzAssignedBlocks -Text $targetScorerBlock -Assignment 'modifier')
$preFiveProfiledZeroBlocks = @($scorerModifierBlocks | Where-Object {
	$_ -match 'coi_alien_survey_data\s*<\s*5' -and
	$_ -match 'coi_alien_token_surface_profile' -and
	$_ -match '(?m)^\s*factor\s*=\s*0\s*$' -and
	$_ -notmatch '(?s)NOT\s*=\s*\{\s*has_operation_token'
})
$preFiveUnprofiledBoostBlocks = @($scorerModifierBlocks | Where-Object {
	$_ -match 'coi_alien_survey_data\s*<\s*5' -and
	$_ -match 'coi_alien_token_surface_profile' -and
	$_ -match '(?m)^\s*factor\s*=\s*20\.0\s*$' -and
	$_ -match '(?s)NOT\s*=\s*\{\s*has_operation_token'
})
if ($preFiveProfiledZeroBlocks.Count -ne 1 -or $preFiveUnprofiledBoostBlocks.Count -ne 1) {
	Add-Failure 'Before Survey Data reaches 5, the target scorer must zero profiled countries and boost unprofiled countries by exactly 20x.'
}

foreach ($hook in @('on_startup', 'on_daily_XAC', 'on_monthly_XAC')) {
	$hookBlock = Get-UniqueContractBlock -Text $intelligenceOnActionText -Assignment $hook -Label 'Quiet Chorus intelligence on_actions'
	if ([regex]::Matches($hookBlock, '(?m)^\s*coi_alien_update_operation_ai_effect\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "$hook must refresh the Quiet Chorus AI plan exactly once."
	}
}
$operationCompletedHook = Get-UniqueContractBlock -Text $intelligenceOnActionText -Assignment 'on_operation_completed' -Label 'Quiet Chorus intelligence on_actions'
if ([regex]::Matches($operationCompletedHook, '\bcoi_alien_update_operation_ai_effect\s*=\s*yes\b').Count -ne 1) {
	Add-Failure 'on_operation_completed must immediately refresh the Quiet Chorus AI plan exactly once.'
}
foreach ($operationId in $expectedOperationIds) {
	if ([regex]::Matches($operationCompletedHook, '(?m)^\s*is_operation_type\s*=\s*' + [regex]::Escape($operationId) + '\s*$').Count -ne 1) {
		Add-Failure "on_operation_completed must recognize $operationId exactly once."
	}
}

foreach ($operative in @($operativeContracts | Where-Object { $_.Drone })) {
	$matchingBlocks = @($operativeBlocks | Where-Object {
		$_ -match ('(?m)^\s*name\s*=\s*' + [regex]::Escape($operative.Id) + '\s*$')
	})
	if ($matchingBlocks.Count -ne 1) {
		continue
	}
	$traitBlocks = @(Get-ClausewitzAssignedBlocks -Text $matchingBlocks[0] -Assignment 'traits')
	if ($traitBlocks.Count -ne 1 -or
		[regex]::Matches($traitBlocks[0], '\bcoi_alien_autonomous_infiltration_drone\b').Count -ne 1 -or
		[regex]::Matches($traitBlocks[0], '\boperative_tough\b').Count -ne 1) {
		Add-Failure "Drone operative $($operative.Id) must carry both its autonomous-drone trait and operative_tough in its authored template."
	}
}
$droneReconciliationBlock = Get-UniqueContractBlock -Text $intelligenceEffectText -Assignment 'coi_alien_reconcile_autonomous_drone_traits_effect' -Label 'Quiet Chorus intelligence effects'
foreach ($reconciliationPattern in @(
	'(?m)^\s*original_tag\s*=\s*XAC\s*$',
	'(?m)^\s*has_dlc\s*=\s*"La Resistance"\s*$',
	'(?m)^\s*has_trait\s*=\s*coi_alien_autonomous_infiltration_drone\s*$',
	'(?m)^\s*NOT\s*=\s*\{\s*has_trait\s*=\s*operative_tough\s*\}\s*$',
	'(?m)^\s*add_unit_leader_trait\s*=\s*operative_tough\s*$'
)) {
	if ([regex]::Matches($droneReconciliationBlock, $reconciliationPattern).Count -ne 1) {
		Add-Failure "Old-save drone reconciliation is missing or duplicates contract: $reconciliationPattern"
	}
}
$operativeRecruitedHook = Get-UniqueContractBlock -Text $intelligenceOnActionText -Assignment 'on_operative_recruited' -Label 'Quiet Chorus intelligence on_actions'
if ([regex]::Matches($operativeRecruitedHook, '(?m)^\s*add_unit_leader_trait\s*=\s*operative_tough\s*$').Count -ne 1 -or
	[regex]::Matches($operativeRecruitedHook, '(?m)^\s*has_trait\s*=\s*coi_alien_autonomous_infiltration_drone\s*$').Count -ne 1) {
	Add-Failure 'Newly recruited authored drones must be reconciled to operative_tough immediately.'
}
Add-Pass 'Validated all-eight-operation AI planning, 950 strategy priority, monthly/completion refresh, pre-five unprofiled rotation, and hardened drone migration'

$scientistTriggerText = Get-RequiredModText 'common\scripted_triggers\coi_alien_scientist_extraction_triggers.txt'
$scientistEffectText = Get-RequiredModText 'common\scripted_effects\coi_alien_scientist_extraction_effects.txt'
$scientistEventText = Get-RequiredModText 'events\coi_alien_scientist_extraction_events.txt'
$scientistIdeaText = Get-RequiredModText 'common\ideas\coi_alien_scientist_extraction_ideas.txt'
$scientistTraitText = Get-RequiredModText 'common\scientist_traits\coi_alien_scientist_extraction_traits.txt'
$scientistLocalisationText = Get-RequiredModText 'localisation\english\coi_alien_scientist_extraction_l_english.yml'

if ($scientistTriggerText -match '(?i)Gotterdammerung') {
	Add-Failure 'Scientist/facility operation-target triggers must not hard-gate behind Gotterdammerung.'
}
$eligibleScientistTriggerBlock = Get-UniqueContractBlock -Text $scientistTriggerText -Assignment 'coi_alien_extractable_scientist_character_trigger' -Label 'Scientist extraction triggers'
foreach ($eligibilityPattern in @(
	'(?m)^\s*is_active_scientist\s*=\s*yes\s*$',
	'(?m)^\s*is_scientist_injured\s*=\s*no\s*$',
	'(?m)^\s*is_advisor\s*=\s*no\s*$',
	'(?m)^\s*is_country_leader\s*=\s*no\s*$',
	'(?m)^\s*is_unit_leader\s*=\s*no\s*$',
	'(?m)^\s*is_operative\s*=\s*no\s*$'
)) {
	if ([regex]::Matches($eligibleScientistTriggerBlock, $eligibilityPattern).Count -ne 1) {
		Add-Failure "Extractable scientist eligibility is missing or duplicates exact condition: $eligibilityPattern"
	}
}
$facilityTriggerBlock = Get-UniqueContractBlock -Text $scientistTriggerText -Assignment 'coi_alien_state_has_special_project_facility_trigger' -Label 'Scientist extraction triggers'
foreach ($facility in @('land_facility', 'air_facility', 'naval_facility', 'nuclear_facility')) {
	if ([regex]::Matches($facilityTriggerBlock, '(?m)^\s*' + $facility + '\s*>\s*0\s*$').Count -ne 1) {
		Add-Failure "Special-project facility trigger must recognize $facility exactly once."
	}
}
foreach ($targetTriggerId in @('coi_alien_target_has_extractable_scientist_trigger', 'coi_alien_operation_state_has_extractable_scientist_trigger')) {
	$targetTriggerBlock = Get-UniqueContractBlock -Text $scientistTriggerText -Assignment $targetTriggerId -Label 'Scientist extraction triggers'
	if ([regex]::Matches($targetTriggerBlock, '\bhas_country_flag\s*=\s*coi_alien_scientist_extraction_cooldown\b').Count -ne 1 -or
		[regex]::Matches($targetTriggerBlock, '(?m)^\s*coi_alien_extractable_scientist_character_trigger\s*=\s*yes\s*$').Count -ne 1 -or
		[regex]::Matches($targetTriggerBlock, '(?m)^\s*coi_alien_state_has_special_project_facility_trigger\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "$targetTriggerId must enforce cooldown, facility, and eligible active-scientist contracts exactly once."
	}
}

$scientistEntryBlock = Get-UniqueContractBlock -Text $scientistEffectText -Assignment 'coi_alien_complete_extract_lead_scientist' -Label 'Scientist extraction effects'
Test-TokenMutationContract -Block $scientistEntryBlock -Assignment 'add_operation_token' -ExpectedTokens @() -Label 'Extract Lead Scientist'
Test-TokenMutationContract -Block $scientistEntryBlock -Assignment 'remove_operation_token' -ExpectedTokens @('coi_alien_token_institutional_access', 'coi_alien_token_research_access') -Label 'Extract Lead Scientist'
foreach ($completionRevalidationPattern in @(
	'\bcoi_alien_target_has_extractable_scientist_trigger\s*=\s*yes\b',
	'\bcoi_alien_operation_state_has_extractable_scientist_trigger\s*=\s*yes\b',
	'(?m)^\s*coi_alien_extractable_scientist_character_trigger\s*=\s*yes\s*$',
	'(?m)^\s*is_in_state\s*=\s*FROM\.FROM\s*$'
)) {
	if ([regex]::Matches($scientistEntryBlock, $completionRevalidationPattern).Count -ne 1) {
		Add-Failure "Extract Lead Scientist completion must revalidate exact condition: $completionRevalidationPattern"
	}
}
$extractionCooldownBlocks = @(Get-ClausewitzAssignedBlocks -Text $scientistEntryBlock -Assignment 'set_country_flag')
if ($extractionCooldownBlocks.Count -ne 1 -or
	[regex]::Matches($extractionCooldownBlocks[0], '(?m)^\s*flag\s*=\s*coi_alien_scientist_extraction_cooldown\s*$').Count -ne 1 -or
	[regex]::Matches($extractionCooldownBlocks[0], '(?m)^\s*days\s*=\s*730\s*$').Count -ne 1) {
	Add-Failure 'Successful scientist extraction must apply the exact 730-day target cooldown.'
}
if ([regex]::Matches($scientistEntryBlock, '\bcoi_alien_raise_awareness_one_effect\s*=\s*yes\b').Count -ne 2) {
	Add-Failure 'Scientist extraction must guarantee one awareness increase and define one possible additional increase.'
}
Test-AwarenessRandomContract -Block $scientistEntryBlock -AwarenessWeight 25 -NoEffectWeight 75 -Label 'Extract Lead Scientist'
foreach ($eventId in @('coi_alien_scientist_extraction.1', 'coi_alien_scientist_extraction.2')) {
	if ([regex]::Matches($scientistEntryBlock, '(?m)^\s*ROOT\s*=\s*\{\s*country_event\s*=\s*\{\s*id\s*=\s*' + [regex]::Escape($eventId) + '\s*\}\s*\}\s*$').Count -ne 1) {
		Add-Failure "Scientist extraction must route exactly once to completion event $eventId in its appropriate branch."
	}
}

$scientistTopLevelEvents = @(Get-ClausewitzAssignedBlocks -Text $scientistEventText -Assignment 'country_event' | Where-Object {
	[regex]::Matches($_, '(?m)^\s*is_triggered_only\s*=\s*yes\s*$').Count -eq 1
})
if ($scientistTopLevelEvents.Count -ne 5) {
	Add-Failure "Scientist extraction event file must define exactly five top-level events; found $($scientistTopLevelEvents.Count)."
}
function Get-ScientistEventBlock {
	param([Parameter(Mandatory)] [string]$EventId)
	$matching = @($script:scientistTopLevelEvents | Where-Object {
		$firstIdMatch = [regex]::Match($_, '(?m)^\s*id\s*=\s*(coi_alien_scientist_extraction\.\d+)\s*$')
		$firstIdMatch.Success -and $firstIdMatch.Groups[1].Value -ceq $EventId
	})
	if ($matching.Count -ne 1) {
		Add-Failure "Scientist extraction event $EventId must be defined exactly once; found $($matching.Count)."
		return ''
	}
	return $matching[0]
}

$dispositionEventBlock = Get-ScientistEventBlock 'coi_alien_scientist_extraction.1'
$dispositionOptions = @(Get-ClausewitzAssignedBlocks -Text $dispositionEventBlock -Assignment 'option')
if ($dispositionOptions.Count -ne 3) {
	Add-Failure "Scientist disposition event must offer exactly three choices; found $($dispositionOptions.Count)."
}
$dispositionContracts = @(
	[pscustomobject]@{ Suffix = 'a'; Chance = 50; Record = 'coi_alien_record_scientist_studied_effect' },
	[pscustomobject]@{ Suffix = 'b'; Chance = 30; Record = 'coi_alien_record_scientist_offworld_effect' },
	[pscustomobject]@{ Suffix = 'c'; Chance = 20; Record = 'coi_alien_record_scientist_removed_effect' }
)
foreach ($disposition in $dispositionContracts) {
	$optionName = 'coi_alien_scientist_extraction.1.' + $disposition.Suffix
	$matchingOptions = @($dispositionOptions | Where-Object {
		[regex]::Matches($_, '(?m)^\s*name\s*=\s*' + [regex]::Escape($optionName) + '\s*$').Count -eq 1
	})
	if ($matchingOptions.Count -ne 1) {
		Add-Failure "Scientist disposition option $optionName must exist exactly once."
		continue
	}
	$chanceBlocks = @(Get-ClausewitzAssignedBlocks -Text $matchingOptions[0] -Assignment 'ai_chance')
	if ($chanceBlocks.Count -ne 1 -or
		[regex]::Matches($chanceBlocks[0], '\bfactor\s*=\s*' + $disposition.Chance + '\b').Count -ne 1) {
		Add-Failure "Scientist disposition option $optionName must have exact AI weight $($disposition.Chance)."
	}
	if ([regex]::Matches($matchingOptions[0], '(?m)^\s*' + $disposition.Record + '\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "Scientist disposition option $optionName must record its ledger exactly once."
	}
	if ($matchingOptions[0] -match '(?m)^\s*(?:remove_scientist_role|retire|coi_alien_remove_and_notify_extracted_scientist_effect|coi_alien_finalize_extracted_scientist_effect)\s*=') {
		Add-Failure "Scientist disposition option $optionName must not remove or retire the scientist again after completion-time extraction."
	}
}

$scientistLedgerInitializer = Get-UniqueContractBlock -Text $scientistEffectText -Assignment 'coi_alien_initialize_scientist_disposition_ledgers_effect' -Label 'Scientist extraction effects'
$scientistLedgerVariables = @(
	'coi_alien_scientist_dispositions_total',
	'coi_alien_scientist_dispositions_studied',
	'coi_alien_scientist_dispositions_offworld',
	'coi_alien_scientist_dispositions_removed'
)
foreach ($ledgerVariable in $scientistLedgerVariables) {
	if ([regex]::Matches($scientistLedgerInitializer, '(?m)^\s*set_variable\s*=\s*\{\s*' + $ledgerVariable + '\s*=\s*0\s*\}\s*$').Count -ne 1) {
		Add-Failure "Scientist disposition ledger must initialize $ledgerVariable exactly once."
	}
}
foreach ($recordContract in @(
	[pscustomobject]@{ Effect = 'coi_alien_record_scientist_studied_effect'; Variable = 'coi_alien_scientist_dispositions_studied' },
	[pscustomobject]@{ Effect = 'coi_alien_record_scientist_offworld_effect'; Variable = 'coi_alien_scientist_dispositions_offworld' },
	[pscustomobject]@{ Effect = 'coi_alien_record_scientist_removed_effect'; Variable = 'coi_alien_scientist_dispositions_removed' }
)) {
	$recordBlock = Get-UniqueContractBlock -Text $scientistEffectText -Assignment $recordContract.Effect -Label 'Scientist disposition ledger effects'
	foreach ($ledgerVariable in @($recordContract.Variable, 'coi_alien_scientist_dispositions_total')) {
		if ([regex]::Matches($recordBlock, '(?m)^\s*add_to_variable\s*=\s*\{\s*' + $ledgerVariable + '\s*=\s*1\s*\}\s*$').Count -ne 1) {
			Add-Failure "$($recordContract.Effect) must increment $ledgerVariable exactly once."
		}
	}
}

$removeAndNotifyScientistBlock = Get-UniqueContractBlock -Text $scientistEffectText -Assignment 'coi_alien_remove_and_notify_extracted_scientist_effect' -Label 'Scientist extraction effects'
if ([regex]::Matches($removeAndNotifyScientistBlock, '(?m)^\s*remove_scientist_role\s*=\s*yes\s*$').Count -ne 1 -or
	[regex]::Matches($removeAndNotifyScientistBlock, '(?m)^\s*retire\s*=\s*yes\s*$').Count -ne 1 -or
	[regex]::Matches($removeAndNotifyScientistBlock, '(?m)^\s*country_event\s*=\s*\{\s*id\s*=\s*coi_alien_scientist_extraction\.3\s*\}\s*$').Count -ne 1 -or
	[regex]::Matches($removeAndNotifyScientistBlock, '(?m)^\s*country_event\s*=\s*\{\s*id\s*=\s*coi_alien_scientist_extraction\.4\s*\}\s*$').Count -ne 1) {
	Add-Failure 'Completion-time extraction must remove/retire the scientist and select one low/high-awareness target notification exactly once.'
}
if ([regex]::Matches($scientistEntryBlock, '(?m)^\s*coi_alien_remove_and_notify_extracted_scientist_effect\s*=\s*yes\s*$').Count -ne 1) {
	Add-Failure 'Successful extraction must call the completion-time remove-and-notify effect exactly once.'
}
$removeCallIndex = $scientistEntryBlock.IndexOf('coi_alien_remove_and_notify_extracted_scientist_effect = yes', [StringComparison]::Ordinal)
$dispositionEventIndex = $scientistEntryBlock.IndexOf('ROOT = { country_event = { id = coi_alien_scientist_extraction.1 } }', [StringComparison]::Ordinal)
if ($removeCallIndex -lt 0 -or $dispositionEventIndex -le $removeCallIndex) {
	Add-Failure 'The scientist must be removed and the target notified before XAC receives the disposition event.'
}

$strategicRemovalOption = @($dispositionOptions | Where-Object {
	$_ -match '(?m)^\s*name\s*=\s*coi_alien_scientist_extraction\.1\.c\s*$'
}) | Select-Object -First 1
$strategicRemovalIdeaBlocks = @(Get-ClausewitzAssignedBlocks -Text $strategicRemovalOption -Assignment 'add_timed_idea')
$strategicRemovalCleanupCalls = @(Get-ClausewitzAssignedBlocks -Text $strategicRemovalOption -Assignment 'country_event' | Where-Object {
	$_ -match '(?m)^\s*id\s*=\s*coi_alien_scientist_extraction\.5\s*$'
})
if ($strategicRemovalIdeaBlocks.Count -ne 1 -or
	[regex]::Matches($strategicRemovalIdeaBlocks[0], '(?m)^\s*idea\s*=\s*coi_alien_scientific_leadership_disrupted\s*$').Count -ne 1 -or
	[regex]::Matches($strategicRemovalIdeaBlocks[0], '(?m)^\s*days\s*=\s*180\s*$').Count -ne 1 -or
	[regex]::Matches($strategicRemovalOption, '(?m)^\s*add_scientist_trait\s*=\s*coi_alien_scientist_breakthrough_disrupted\s*$').Count -ne 1 -or
	$strategicRemovalCleanupCalls.Count -ne 1 -or
	[regex]::Matches($strategicRemovalCleanupCalls[0], '(?m)^\s*days\s*=\s*180\s*$').Count -ne 1) {
	Add-Failure 'Strategic Removal must apply its country idea and scientist trait together and schedule cleanup at exactly 180 days.'
}
$scientistCleanupEvent = Get-ScientistEventBlock 'coi_alien_scientist_extraction.5'
if ([regex]::Matches($scientistCleanupEvent, '(?m)^\s*hidden\s*=\s*yes\s*$').Count -ne 1 -or
	[regex]::Matches($scientistCleanupEvent, '(?m)^\s*remove_trait\s*=\s*\{\s*trait\s*=\s*coi_alien_scientist_breakthrough_disrupted\s*\}\s*$').Count -ne 1) {
	Add-Failure 'The 180-day hidden cleanup event must remove the temporary scientist breakthrough trait from every remaining holder.'
}
$scientificDisruptionIdea = Get-UniqueContractBlock -Text $scientistIdeaText -Assignment 'coi_alien_scientific_leadership_disrupted' -Label 'Scientist extraction ideas'
foreach ($ideaModifier in @(
	[pscustomobject]@{ Name = 'research_speed_factor'; Value = '-0.05' },
	[pscustomobject]@{ Name = 'special_project_speed_factor'; Value = '-0.15' }
)) {
	if ([regex]::Matches($scientificDisruptionIdea, '(?m)^\s*' + $ideaModifier.Name + '\s*=\s*' + [regex]::Escape($ideaModifier.Value) + '\s*$').Count -ne 1) {
		Add-Failure "Scientific Leadership Disrupted must apply $($ideaModifier.Name) = $($ideaModifier.Value)."
	}
}
$scientificDisruptionTrait = Get-UniqueContractBlock -Text $scientistTraitText -Assignment 'coi_alien_scientist_breakthrough_disrupted' -Label 'Scientist extraction traits'
if ([regex]::Matches($scientificDisruptionTrait, '(?m)^\s*scientist_breakthrough_bonus_factor\s*=\s*-0\.15\s*$').Count -ne 1) {
	Add-Failure 'The temporary scientist trait must apply scientist_breakthrough_bonus_factor = -0.15.'
}

$scientistSubsystemText = $scientistTriggerText + "`n" + $scientistEffectText + "`n" + $scientistEventText + "`n" + $scientistIdeaText + "`n" + $scientistTraitText
if ($scientistEventText -match '\binclude_invisible\b') {
	Add-Failure 'Scientist event iterators must omit include_invisible because the HOI4 1.19.2 executable rejects it in this event context.'
}
foreach ($forbiddenScientistCommand in @('set_nationality', 'add_scientist_role', 'create_scientist', 'generate_scientist', 'recruit_character')) {
	if ($scientistSubsystemText -match ('(?m)^\s*' + [regex]::Escape($forbiddenScientistCommand) + '\s*=')) {
		Add-Failure "Scientist extraction must never transfer, generate, recruit, or add the captive to XAC; forbidden command found: $forbiddenScientistCommand."
	}
}
if ($scientistLocalisationText -match '(?<!\?)\[event_target:') {
	Add-Failure 'Scientist extraction localisation must dereference saved event targets with the [?event_target:...Get...] form.'
}
foreach ($savedTargetFragment in @(
	'[?event_target:coi_alien_extracted_scientist.GetName]',
	'[?event_target:coi_alien_extraction_target.GetNameDef]'
)) {
	if ([regex]::Matches($scientistLocalisationText, [regex]::Escape($savedTargetFragment)).Count -lt 1) {
		Add-Failure "Scientist extraction localisation never uses required saved-target dereference $savedTargetFragment."
	}
}
foreach ($key in @(
	'coi_alien_scientific_leadership_disrupted',
	'coi_alien_scientific_leadership_disrupted_desc',
	'coi_alien_scientist_breakthrough_disrupted',
	'coi_alien_scientist_breakthrough_disrupted_desc'
)) {
	if (-not $localisationKeys.ContainsKey($key)) {
		Add-Failure "Missing scientist-extraction localisation key $key."
	}
}
foreach ($eventNumber in 1..5) {
	foreach ($suffix in @('.t', '.desc')) {
		$key = 'coi_alien_scientist_extraction.' + $eventNumber + $suffix
		if ($eventNumber -eq 5) { continue }
		if (-not $localisationKeys.ContainsKey($key)) {
			Add-Failure "Missing scientist-extraction event localisation key $key."
		}
	}
}
Add-Pass 'Validated scientist target eligibility, 730-day cooldown, completion-time removal/notification, 50/30/20 disposition ledger, executable-safe iterators, saved-target localisation, no XAC scientist transfer, and exact 180-day disruption cleanup'

$operationAssetContracts = [System.Collections.Generic.List[object]]::new()
foreach ($operation in $operationContracts) {
	$operationArtId = $operation.Id -replace '^coi_alien_', 'coi_alien_operation_'
	$operationAssetContracts.Add([pscustomobject]@{
		Name = ('GFX_' + $operationArtId)
		Texture = ('gfx/interface/operations/' + $operationArtId + '.dds')
		Width = 85
		Height = 85
	})
	$operationAssetContracts.Add([pscustomobject]@{
		Name = ('GFX_' + $operationArtId + '_map')
		Texture = ('gfx/interface/mapicons/' + $operationArtId + '_map.dds')
		Width = 48
		Height = 48
	})
	$operationAssetContracts.Add([pscustomobject]@{
		Name = ('GFX_' + $operationArtId + '_phase_icon')
		Texture = ('gfx/interface/operations/phases_small/' + $operationArtId + '_phase_icon.dds')
		Width = 59
		Height = 58
	})
	$operationAssetContracts.Add([pscustomobject]@{
		Name = ('GFX_' + $operationArtId + '_phase_picture')
		Texture = ('gfx/interface/operations/images/' + $operationArtId + '_phase_picture.dds')
		Width = 210
		Height = 176
	})
}
if ($operationAssetContracts.Count -ne 32) {
	Add-Failure "Internal operation-art contract must contain exactly 32 assets; found $($operationAssetContracts.Count)."
}
foreach ($asset in $operationAssetContracts) {
	Test-DdsArgbContract -RelativePath $asset.Texture -Width $asset.Width -Height $asset.Height
	Test-GfxSpriteContract -Text $operationGfxText -Name $asset.Name -Texture $asset.Texture -RequireLegacyLazyLoad
}

$tokenAssetContracts = [System.Collections.Generic.List[object]]::new()
foreach ($token in $tokenContracts) {
	$tokenAssetContracts.Add([pscustomobject]@{
		Name = ('GFX_' + $token.Id)
		Texture = ('gfx/interface/operations/' + $token.Id + '.dds')
		Width = 33
		Height = 29
	})
	$tokenAssetContracts.Add([pscustomobject]@{
		Name = ('GFX_' + $token.Id + '_text')
		Texture = ('gfx/texticons/' + $token.Id + '_text.dds')
		Width = 24
		Height = 21
	})
}
if ($tokenAssetContracts.Count -ne 6) {
	Add-Failure "Internal access-token art contract must contain exactly six assets; found $($tokenAssetContracts.Count)."
}
foreach ($asset in $tokenAssetContracts) {
	Test-DdsArgbContract -RelativePath $asset.Texture -Width $asset.Width -Height $asset.Height
	Test-GfxSpriteContract -Text $operationGfxText -Name $asset.Name -Texture $asset.Texture -RequireLegacyLazyLoad
}

$upgradeAssetContracts = @($upgradeContracts | ForEach-Object {
	[pscustomobject]@{
		Name = ('GFX_' + $_.Id)
		Texture = ('gfx/interface/operatives/icons/' + $_.Id + '.dds')
		Width = 68
		Height = 68
	}
})
if ($upgradeAssetContracts.Count -ne 3) {
	Add-Failure "Internal agency-upgrade art contract must contain exactly three assets; found $($upgradeAssetContracts.Count)."
}
foreach ($asset in $upgradeAssetContracts) {
	Test-DdsArgbContract -RelativePath $asset.Texture -Width $asset.Width -Height $asset.Height
	Test-GfxSpriteContract -Text $operationGfxText -Name $asset.Name -Texture $asset.Texture -RequireLegacyLazyLoad
}

$operationSpriteNames = @([regex]::Matches($operationGfxText, '(?m)^\s*name\s*=\s*"(GFX_coi_alien_(?:operation|token|upgrade)_[^"]+)"\s*$') | ForEach-Object { $_.Groups[1].Value })
$expectedOperationSpriteNames = @($operationAssetContracts.Name) + @($tokenAssetContracts.Name) + @($upgradeAssetContracts.Name)
if ($operationSpriteNames.Count -ne 41 -or
	@($operationSpriteNames | Where-Object { $_ -notin $expectedOperationSpriteNames }).Count -ne 0 -or
	@($expectedOperationSpriteNames | Where-Object { $_ -notin $operationSpriteNames }).Count -ne 0) {
	Add-Failure "coi_alien_operations.gfx must define only the exact 41 contracted operation/token/upgrade sprites; found $($operationSpriteNames.Count)."
}
Add-Pass 'Validated exact 32 operation, six token, and three upgrade DDS paths, native dimensions, ARGB8888 alpha, no-mip payloads, and GFX bindings'

$expectedTokenGuiNames = @($tokenContracts | ForEach-Object { $_.Id + '_icon' })
$actualTokenGuiNames = @([regex]::Matches($intelligenceAgencyGuiText, '(?m)^\s*iconType\s*=\s*\{\s*name\s*=\s*"(coi_alien_token_[a-z0-9_]+_icon)"\s*\}\s*$') | ForEach-Object { $_.Groups[1].Value })
if ($actualTokenGuiNames.Count -ne 3 -or
	@($actualTokenGuiNames | Where-Object { $_ -notin $expectedTokenGuiNames }).Count -ne 0 -or
	@($expectedTokenGuiNames | Where-Object { $_ -notin $actualTokenGuiNames }).Count -ne 0) {
	Add-Failure "countryintelligenceagencyview.gui must contain only the exact three custom token icon hooks; found [$($actualTokenGuiNames -join ', ')]."
}
$tokenGuiInjectionPattern = '(?m)^\s*# COI_ALIEN_OPERATION_TOKENS_BEGIN - generated by Build-AlienIntelligenceUI\.ps1\r?\n' +
	'\s*iconType = \{ name = "coi_alien_token_surface_profile_icon" \}\r?\n' +
	'\s*iconType = \{ name = "coi_alien_token_institutional_access_icon" \}\r?\n' +
	'\s*iconType = \{ name = "coi_alien_token_research_access_icon" \}\r?\n' +
	'\s*# COI_ALIEN_OPERATION_TOKENS_END\r?\n'
$tokenGuiInjectionMatches = [regex]::Matches($intelligenceAgencyGuiText, $tokenGuiInjectionPattern)
if ($tokenGuiInjectionMatches.Count -ne 1) {
	Add-Failure "Intelligence-agency GUI must contain one exact generated token-hook block; found $($tokenGuiInjectionMatches.Count)."
}
else {
	$strippedIntelligenceGui = $intelligenceAgencyGuiText.Remove($tokenGuiInjectionMatches[0].Index, $tokenGuiInjectionMatches[0].Length)
	$sha256 = [Security.Cryptography.SHA256]::Create()
	try {
		$strippedBytes = [Text.UTF8Encoding]::new($false).GetBytes($strippedIntelligenceGui)
		$strippedHashBytes = $sha256.ComputeHash($strippedBytes)
		$strippedHash = -join ($strippedHashBytes | ForEach-Object { $_.ToString('X2') })
	}
	finally {
		$sha256.Dispose()
	}
	$expectedVanillaIntelligenceGuiHash = '00153F0968113C3F29D914BDA227C729BA5D95F5888135C0DD98DB89748EF3E5'
	if ($strippedHash -cne $expectedVanillaIntelligenceGuiHash) {
		Add-Failure "Stripping the generated token hooks yields intelligence-GUI hash $strippedHash; expected HOI4 1.19.2.0 vanilla $expectedVanillaIntelligenceGuiHash."
	}
}
Add-Pass 'Validated exact three native operation-token GUI hooks and strip-to-vanilla HOI4 1.19.2.0 hash'

$operationMasterRoot = Join-Path $ProjectRoot 'Source\Art\Masters'
$operationProvenancePath = Join-Path $ProjectRoot 'Source\Art\quiet_chorus_operations_imagegen_prompts.md'
$expectedOperationMasterNames = @($operationContracts | ForEach-Object { ($_.Id -replace '^coi_alien_', 'coi_alien_operation_') + '.png' })
if (-not (Test-Path -LiteralPath $operationMasterRoot -PathType Container)) {
	Add-Failure "Missing ImageGen operation-master directory: $operationMasterRoot"
}
else {
	$actualOperationMasters = @(Get-ChildItem -LiteralPath $operationMasterRoot -File -Filter 'coi_alien_operation_*.png')
	if ($actualOperationMasters.Count -ne 8 -or
		@($actualOperationMasters.Name | Where-Object { $_ -notin $expectedOperationMasterNames }).Count -ne 0 -or
		@($expectedOperationMasterNames | Where-Object { $_ -notin $actualOperationMasters.Name }).Count -ne 0) {
		Add-Failure "ImageGen master directory must contain the exact eight operation PNGs; found [$($actualOperationMasters.Name -join ', ')]."
	}
	foreach ($masterName in $expectedOperationMasterNames) {
		$masterPath = Join-Path $operationMasterRoot $masterName
		if (-not (Test-Path -LiteralPath $masterPath -PathType Leaf)) {
			continue
		}
		$masterBytes = [IO.File]::ReadAllBytes($masterPath)
		if ($masterBytes.Length -lt 33 -or
			$masterBytes[0] -ne 0x89 -or $masterBytes[1] -ne 0x50 -or $masterBytes[2] -ne 0x4E -or $masterBytes[3] -ne 0x47 -or
			$masterBytes[24] -ne 8 -or $masterBytes[25] -ne 6) {
			Add-Failure "$masterName must remain an 8-bit RGBA PNG ImageGen master."
			continue
		}
		$masterWidth = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($masterBytes, 16))
		$masterHeight = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($masterBytes, 20))
		if ($masterWidth -lt 512 -or $masterHeight -lt 512) {
			Add-Failure "$masterName is ${masterWidth}x${masterHeight}; retain a high-resolution source master of at least 512x512."
		}
		$masterBitmap = $null
		try {
			$masterBitmap = [System.Drawing.Bitmap]::new($masterPath)
			$cornerAlphas = @(
				$masterBitmap.GetPixel(0, 0).A,
				$masterBitmap.GetPixel($masterBitmap.Width - 1, 0).A,
				$masterBitmap.GetPixel(0, $masterBitmap.Height - 1).A,
				$masterBitmap.GetPixel($masterBitmap.Width - 1, $masterBitmap.Height - 1).A
			)
			if (@($cornerAlphas | Where-Object { $_ -gt 1 }).Count -ne 0) {
				Add-Failure "$masterName must retain transparent or effectively transparent alpha at all four canvas corners."
			}
		}
		catch {
			Add-Failure "Could not decode ImageGen master ${masterName}: $($_.Exception.Message)"
		}
		finally {
			if ($null -ne $masterBitmap) {
				$masterBitmap.Dispose()
			}
		}
	}
}
if (-not (Test-Path -LiteralPath $operationProvenancePath -PathType Leaf)) {
	Add-Failure "Missing Quiet Chorus ImageGen prompt provenance: $operationProvenancePath"
}
else {
	$operationProvenanceText = [IO.File]::ReadAllText($operationProvenancePath)
	foreach ($provenancePattern in @(
		'Generated with the built-in OpenAI `imagegen` tool',
		'transparent-background image-generation/edit mode',
		'style and material references',
		'second imagegen background-extraction edit'
	)) {
		if ([regex]::Matches($operationProvenanceText, [regex]::Escape($provenancePattern), 'IgnoreCase').Count -ne 1) {
			Add-Failure "Quiet Chorus art provenance must state exactly once: $provenancePattern"
		}
	}
	foreach ($masterName in $expectedOperationMasterNames) {
		if ([regex]::Matches($operationProvenanceText, [regex]::Escape($masterName)).Count -ne 1) {
			Add-Failure "Quiet Chorus art provenance must record the final subject prompt for $masterName exactly once."
		}
	}
}
Add-Pass 'Validated eight transparent high-resolution ImageGen operation masters and checked-in built-in-mode prompt provenance'

$navalLocalisationText = [IO.File]::ReadAllText((Join-Path $modRoot 'localisation\english\coi_alien_naval_l_english.yml'))
$navalExperienceLocalisations = [ordered]@{
    'modifier_experience_gain_coi_alien_mothership_training_factor' = 'Mothership Training Experience Gain'
    'modifier_experience_gain_coi_alien_mothership_mission_factor' = 'Mothership mission Experience Gain'
    'modifier_experience_gain_coi_alien_mothership_combat_factor' = 'Mothership Combat Experience Gain'
    'modifier_experience_gain_coi_alien_escort_training_factor' = 'Alien Escort Training Experience Gain'
    'modifier_experience_gain_coi_alien_escort_mission_factor' = 'Alien Escort mission Experience Gain'
    'modifier_experience_gain_coi_alien_escort_combat_factor' = 'Alien Escort Combat Experience Gain'
}
foreach ($entry in $navalExperienceLocalisations.GetEnumerator()) {
    $localisationPattern = '(?m)^\s*' + [regex]::Escape($entry.Key) + ':\s*"' + [regex]::Escape($entry.Value) + '"\s*$'
    if ([regex]::Matches($navalLocalisationText, $localisationPattern).Count -ne 1) {
        Add-Failure "Missing or malformed naval experience localisation: $($entry.Key)"
    }
}

$navalOobText = [IO.File]::ReadAllText((Join-Path $modRoot 'history\units\XAC_1936_naval.txt'))
$navalOobCounts = [ordered]@{
    'fleet blocks' = @([regex]::Matches($navalOobText, '(?m)^\s*fleet\s*=\s*\{')).Count
    'task-force blocks' = @([regex]::Matches($navalOobText, '(?m)^\s*task_force\s*=\s*\{')).Count
    'ship blocks' = @([regex]::Matches($navalOobText, '(?m)^\s*ship\s*=\s*\{')).Count
    'mothership definitions' = @([regex]::Matches($navalOobText, '(?m)^\s*definition\s*=\s*coi_alien_mothership\s*$')).Count
    'escort definitions' = @([regex]::Matches($navalOobText, '(?m)^\s*definition\s*=\s*coi_alien_escort\s*$')).Count
    'mothership hull entries' = @([regex]::Matches($navalOobText, '(?m)^\s*coi_alien_mothership_hull_1\s*=\s*\{')).Count
    'escort hull entries' = @([regex]::Matches($navalOobText, '(?m)^\s*coi_alien_escort_hull_1\s*=\s*\{')).Count
    'amount-one entries' = @([regex]::Matches($navalOobText, '(?m)^\s*amount\s*=\s*1\s*$')).Count
    'XAC owner entries' = @([regex]::Matches($navalOobText, '(?m)^\s*owner\s*=\s*XAC\s*$')).Count
    'Pale Horizon variant references' = @([regex]::Matches($navalOobText, '(?m)^\s*version_name\s*=\s*"Pale Horizon Pattern"\s*$')).Count
    'Silent Current variant references' = @([regex]::Matches($navalOobText, '(?m)^\s*version_name\s*=\s*"Silent Current Escort Pattern"\s*$')).Count
    'Point Nemo naval bases' = @([regex]::Matches($navalOobText, '(?m)^\s*naval_base\s*=\s*13414(?:\s*#.*)?$')).Count
    'Point Nemo task-force locations' = @([regex]::Matches($navalOobText, '(?m)^\s*location\s*=\s*13414(?:\s*#.*)?$')).Count
}
$expectedNavalOobCounts = [ordered]@{
    'fleet blocks' = 1
    'task-force blocks' = 1
    'ship blocks' = 5
    'mothership definitions' = 1
    'escort definitions' = 4
    'mothership hull entries' = 1
    'escort hull entries' = 4
    'amount-one entries' = 5
    'XAC owner entries' = 5
    'Pale Horizon variant references' = 1
    'Silent Current variant references' = 4
    'Point Nemo naval bases' = 1
    'Point Nemo task-force locations' = 1
}
foreach ($key in $expectedNavalOobCounts.Keys) {
    if ($navalOobCounts[$key] -ne $expectedNavalOobCounts[$key]) {
        Add-Failure "XAC naval OOB has $($navalOobCounts[$key]) $key; expected $($expectedNavalOobCounts[$key])."
    }
}
foreach ($shipName in @('Pale Horizon', 'Silent Current I', 'Silent Current II', 'Silent Current III', 'Silent Current IV')) {
    $namePattern = '(?m)^\s*name\s*=\s*"' + [regex]::Escape($shipName) + '"\s*$'
    if ([regex]::Matches($navalOobText, $namePattern).Count -ne 1) {
        Add-Failure "XAC naval OOB must contain ship name '$shipName' exactly once."
    }
}
if ($navalOobText -match '(?m)^\s*definition\s*=\s*(?:carrier|destroyer)\s*$') {
    Add-Failure 'XAC naval OOB must use alien sub-unit definitions, not vanilla carrier/destroyer requirements.'
}

$navalEffectText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_effects\coi_alien_naval_effects.txt'))
if ($navalEffectText -match '(?m)^\s*create_ship\s*=') {
    Add-Failure 'Runtime create_ship must not be reintroduced; XAC ships load through the history naval OOB.'
}
$navalActivationBlocks = @(Get-ClausewitzAssignedBlocks -Text $navalEffectText -Assignment 'coi_alien_activate_mothership_anchorage')
$navalDesignRegistrationFlag = 'coi_alien_naval_designs_v050_registered'
if ($navalActivationBlocks.Count -ne 1) {
    Add-Failure 'The Mothership Anchorage activation effect must be defined exactly once.'
}
else {
    $navalActivationBlock = $navalActivationBlocks[0]
    $runtimeShipVariants = @(Get-ClausewitzAssignedBlocks -Text $navalActivationBlock -Assignment 'create_equipment_variant')
    if ($runtimeShipVariants.Count -ne 2) {
        Add-Failure 'The one-shot alien naval registration path must issue exactly two runtime ship variants.'
    }
    foreach ($runtimeShipContract in @(
        [pscustomobject]@{ Name = 'Pale Horizon Pattern'; Type = 'coi_alien_mothership_hull_1' },
        [pscustomobject]@{ Name = 'Silent Current Escort Pattern'; Type = 'coi_alien_escort_hull_1' }
    )) {
        $runtimeShipPattern = '(?s)create_equipment_variant\s*=\s*\{\s*name\s*=\s*"' + [regex]::Escape($runtimeShipContract.Name) + '"\s+type\s*=\s*' + [regex]::Escape($runtimeShipContract.Type)
        if ([regex]::Matches($navalActivationBlock, $runtimeShipPattern).Count -ne 1) {
            Add-Failure "Alien naval registration must issue $($runtimeShipContract.Name) from $($runtimeShipContract.Type) exactly once."
        }
    }
    if ([regex]::Matches($navalActivationBlock, '(?m)^\s*NOT\s*=\s*\{\s*has_country_flag\s*=\s*' + [regex]::Escape($navalDesignRegistrationFlag) + '\s*\}\s*$').Count -ne 1 -or
        [regex]::Matches($navalActivationBlock, '(?m)^\s*set_country_flag\s*=\s*' + [regex]::Escape($navalDesignRegistrationFlag) + '\s*$').Count -ne 2) {
        Add-Failure 'Alien naval registration must use one v0.5.0 guard and complete both legacy-migration and fresh-creation paths.'
    }
    if ([regex]::Matches($navalActivationBlock, '(?m)^\s*has_design_based_on\s*=').Count -ne 0) {
        Add-Failure 'Alien naval registration must not use has_design_based_on; it rejects the accepted custom variants and causes unbounded duplicate designs.'
    }
    $secondVariantIndex = $navalActivationBlock.LastIndexOf('create_equipment_variant', [StringComparison]::Ordinal)
    $freshFlagIndex = $navalActivationBlock.LastIndexOf("set_country_flag = $navalDesignRegistrationFlag", [StringComparison]::Ordinal)
    if ($secondVariantIndex -lt 0 -or $freshFlagIndex -le $secondVariantIndex) {
        Add-Failure 'Fresh alien naval registration must commit its versioned idempotence flag immediately after both variant effects are issued.'
    }
}
$pointNemoFleetBlocks = @(Get-ClausewitzAssignedBlocks -Text $navalEffectText -Assignment 'coi_alien_create_point_nemo_reserve_fleet')
if ($pointNemoFleetBlocks.Count -ne 1 -or
    [regex]::Matches($pointNemoFleetBlocks[0], '(?m)^\s*has_country_flag\s*=\s*' + [regex]::Escape($navalDesignRegistrationFlag) + '\s*$').Count -ne 1 -or
    [regex]::Matches($pointNemoFleetBlocks[0], '(?m)^\s*NOT\s*=\s*\{\s*has_country_flag\s*=\s*' + [regex]::Escape($navalDesignRegistrationFlag) + '\s*\}\s*$').Count -ne 1) {
    Add-Failure 'Point Nemo reserve-fleet reconciliation must retry and proceed using the versioned naval-design registration flag.'
}
foreach ($stockContract in @(
    [pscustomobject]@{ Type = 'coi_alien_needle_equipment_1'; Amount = 30 },
    [pscustomobject]@{ Type = 'coi_alien_gleam_equipment_1'; Amount = 20 }
)) {
    $stockPattern = '(?s)add_equipment_to_stockpile\s*=\s*\{\s*type\s*=\s*' + [regex]::Escape($stockContract.Type) + '\s+amount\s*=\s*' + $stockContract.Amount + '\s+producer\s*=\s*XAC\s*\}'
    if ([regex]::Matches($navalEffectText, $stockPattern).Count -ne 1) {
        Add-Failure "The idempotent XAC air complement must stock exactly $($stockContract.Amount) $($stockContract.Type)."
    }
}
if ([regex]::Matches($navalEffectText, '(?m)^\s*set_country_flag\s*=\s*coi_alien_point_nemo_air_complement_stocked\s*$').Count -ne 1) {
    Add-Failure 'The Point Nemo aircraft stockpile must have exactly one idempotence flag setter.'
}

$alienTechnologyText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\technologies\coi_alien_naval_technologies.txt'))
$alienHelperTechnologies = @(
    'coi_alien_expeditionary_naval_architecture',
    'coi_alien_needle_interceptor_program',
    'coi_alien_gleam_strike_program'
)
foreach ($technology in $alienHelperTechnologies) {
    $definitionPattern = '(?m)^\s*' + [regex]::Escape($technology) + '\s*=\s*\{\s*$'
    if ([regex]::Matches($alienTechnologyText, $definitionPattern).Count -ne 1) {
        Add-Failure "Alien helper technology $technology must be defined exactly once."
    }
    $grantPattern = '(?m)^\s*' + [regex]::Escape($technology) + '\s*=\s*1\s*$'
    if ([regex]::Matches($navalEffectText, $grantPattern).Count -ne 1) {
        Add-Failure "Alien helper technology $technology must be script-granted exactly once."
    }
}
if ($alienTechnologyText -match '(?m)^\s*(?:folder|path)\s*=\s*\{') {
    Add-Failure 'Script-granted alien helper technologies must remain folderless and pathless so the vanilla research UI does not require custom grid boxes.'
}
if ([regex]::Matches($alienTechnologyText, '(?m)^\s*always\s*=\s*no\s*$').Count -ne 3) {
    Add-Failure 'All three alien helper technologies must use the vanilla hidden-tech allow = { always = no } contract.'
}
if ([regex]::Matches($alienTechnologyText, '(?m)^\s*factor\s*=\s*0\s*$').Count -ne 3) {
    Add-Failure 'All three alien helper technologies must have zero AI research weight.'
}
if ([regex]::Matches($alienTechnologyText, '(?m)^\s*special_project_specialization\s*=\s*\{\s*coi_alien_specialization_matter_fabrication\s*\}\s*$').Count -ne 2 -or
    [regex]::Matches($alienTechnologyText, '\bcoi_alien_specialization_(?:field_energy|cognition_observation|biogenesis)\b').Count -ne 0) {
    Add-Failure 'The two breakthrough-bearing hidden helper technologies must feed the single operational Consensus Sciences specialization.'
}
foreach ($unlock in @(
    'coi_alien_mothership_hull_1',
    'coi_alien_escort_hull_1',
    'coi_alien_needle_equipment_1',
    'coi_alien_gleam_equipment_1',
    'coi_alien_gravitic_tide_drive',
    'coi_alien_phase_hangar_matrix',
    'coi_alien_lance_battery',
    'coi_alien_point_defense_matrix',
    'coi_alien_spectral_sensor_web',
    'coi_alien_phase_lattice'
)) {
    $unlockPattern = '(?m)^\s*' + [regex]::Escape($unlock) + '\s*$'
    if ([regex]::Matches($alienTechnologyText, $unlockPattern).Count -ne 1) {
        Add-Failure "Alien helper technologies must retain exactly one unlock entry for $unlock."
    }
}

$alienTechnologyTagPath = Join-Path $modRoot 'common\technology_tags\coi_alien_technology_tags.txt'
$alienTechnologyTagText = [IO.File]::ReadAllText($alienTechnologyTagPath)
foreach ($alienTechnologyCategory in @(
	'coi_alien_science', 'coi_alien_material_science', 'coi_alien_field_dynamics',
	'coi_alien_coherent_energy', 'coi_alien_predictive_cognition',
	'coi_alien_human_sciences', 'coi_alien_fabrication'
)) {
	if ([regex]::Matches($alienTechnologyTagText, '(?m)^\s*' + [regex]::Escape($alienTechnologyCategory) + '\s*$').Count -ne 1) {
		Add-Failure "The namespaced $alienTechnologyCategory technology category must be declared exactly once."
	}
}
if ([regex]::Matches($alienTechnologyTagText, '(?m)^\s*coi_alien_technology_folder\s*=\s*\{\s*$').Count -ne 1) {
    Add-Failure 'The Consensus Sciences technology folder must be declared exactly once.'
}
if ([regex]::Matches($alienTechnologyTagText, '(?m)^\s*original_tag\s*=\s*XAC\s*$').Count -ne 1 -or
	[regex]::Matches($alienTechnologyTagText, '(?m)^\s*ledger\s*=\s*civilian\s*$').Count -ne 1) {
	Add-Failure 'The Consensus Sciences folder must be available only to original tag XAC and use the civilian ledger.'
}

$alienStarterTechnologyPath = Join-Path $modRoot 'common\technologies\coi_alien_starter_technologies.txt'
$alienStarterTechnologyText = [IO.File]::ReadAllText($alienStarterTechnologyPath)
$alienResearchDomains = @(
	[pscustomobject]@{
		Category = 'coi_alien_material_science'
		Specialization = 'coi_alien_specialization_matter_fabrication'
		Nodes = @(
			'coi_alien_adaptive_metamaterials', 'coi_alien_pale_horizon_phase_refit',
			'coi_alien_terrestrial_composite_translation', 'coi_alien_personal_phase_sheaths',
			'coi_alien_self_healing_phase_lattice', 'coi_alien_adaptive_warform_shells'
		)
	},
	[pscustomobject]@{
		Category = 'coi_alien_field_dynamics'
		Specialization = 'coi_alien_specialization_matter_fabrication'
		Nodes = @(
			'coi_alien_inertial_field_theory', 'coi_alien_silent_current_field_refit',
			'coi_alien_tic_tac_fabrication', 'coi_alien_spacetime_aperture_geometry',
			'coi_alien_energy_gateway_synchronization', 'coi_alien_stabilized_transit_network'
		)
	},
	[pscustomobject]@{
		Category = 'coi_alien_coherent_energy'
		Specialization = 'coi_alien_specialization_matter_fabrication'
		Nodes = @(
			'coi_alien_coherent_energy_control', 'coi_alien_gleam_resonance_package',
			'coi_alien_atomic_resonance_cartography', 'coi_alien_predictive_intercept_lattice',
			'coi_alien_sentinel_reserve_fabrication', 'coi_alien_atomic_disruption_protocols'
		)
	},
	[pscustomobject]@{
		Category = 'coi_alien_predictive_cognition'
		Specialization = 'coi_alien_specialization_matter_fabrication'
		Nodes = @(
			'coi_alien_predictive_computation', 'coi_alien_needle_guidance_lattice',
			'coi_alien_multi_agent_infiltration_models', 'coi_alien_institutional_behavior_prediction',
			'coi_alien_cascading_failure_models', 'coi_alien_deep_substitution_architecture'
		)
	},
	[pscustomobject]@{
		Category = 'coi_alien_human_sciences'
		Specialization = 'coi_alien_specialization_matter_fabrication'
		Nodes = @(
			'coi_alien_comparative_human_ethology', 'coi_alien_mass_media_semiotics',
			'coi_alien_tissue_analysis', 'coi_alien_human_genome_atlas',
			'coi_alien_accelerated_human_cloning', 'coi_alien_conditioned_identity_imprinting'
		)
	},
	[pscustomobject]@{
		Category = 'coi_alien_fabrication'
		Specialization = 'coi_alien_specialization_matter_fabrication'
		Nodes = @(
			'coi_alien_expeditionary_pattern_libraries', 'coi_alien_molecular_feedstock_recovery',
			'coi_alien_additive_airframe_printing', 'coi_alien_continuous_airframe_lattice',
			'coi_alien_distributed_fabrication_logic', 'coi_alien_autonomous_fabrication_ecology'
		)
	}
)

function Get-TopLevelTechnologyBlock {
    param(
        [Parameter(Mandatory)] [string]$Text,
        [Parameter(Mandatory)] [string]$Id
    )

    $pattern = '(?ms)^\t' + [regex]::Escape($Id) + '\s*=\s*\{[^\r\n]*\n(?<Body>.*?)^\t\}[ \t]*$'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -ne 1) {
        Add-Failure "Expected exactly one top-level block for $Id; found $($matches.Count)."
        return $null
    }
    $matches[0].Groups['Body'].Value
}

$expectedVisibleTechnologyIds = [System.Collections.Generic.List[string]]::new()
foreach ($domain in $alienResearchDomains) {
	for ($nodeIndex = 0; $nodeIndex -lt $domain.Nodes.Count; $nodeIndex++) {
		$technologyId = $domain.Nodes[$nodeIndex]
		$expectedVisibleTechnologyIds.Add($technologyId)
		$technologyBlock = Get-TopLevelTechnologyBlock -Text $alienStarterTechnologyText -Id $technologyId
		if ($null -eq $technologyBlock) { continue }
		$expectedStartYear = if ($technologyId -eq 'coi_alien_tic_tac_fabrication') { 1938 } else { 1936 }
		$startYearContractPattern = '(?m)^\s*start_year\s*=\s*' + $expectedStartYear + '\s*$'

		$categoryContractPattern = '(?s)\bcategories\s*=\s*\{[^}]*\bcoi_alien_science\b[^}]*\b' + [regex]::Escape($domain.Category) + '\b[^}]*\}'
		$domainPatterns = @(
			'(?s)\ballow_branch\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}',
			'(?s)\bfolder\s*=\s*\{\s*name\s*=\s*coi_alien_technology_folder\s+position\s*=\s*\{\s*x\s*=\s*0\s+y\s*=\s*(?:0|2|4|6|8|10)\s*\}\s*\}',
			$startYearContractPattern,
			$categoryContractPattern,
			'(?s)\bai_will_do\s*=\s*\{\s*factor\s*=\s*(?:8|10)\s*\}'
		)
		foreach ($requiredPattern in $domainPatterns) {
			if ([regex]::Matches($technologyBlock, $requiredPattern).Count -ne 1) {
				Add-Failure "Alien technology $technologyId is missing or duplicates its XAC-only $expectedStartYear domain contract."
			}
		}

		$expectedSpecializations = $domain.Specialization
		$specializationPattern = '(?m)^\s*special_project_specialization\s*=\s*\{\s*' + [regex]::Escape($expectedSpecializations) + '\s*\}\s*$'
		if ([regex]::Matches($technologyBlock, $specializationPattern).Count -ne 1) {
			Add-Failure "Alien technology $technologyId must generate breakthroughs for $expectedSpecializations."
		}

		if ($nodeIndex -lt $domain.Nodes.Count - 1) {
			$nextTechnologyId = $domain.Nodes[$nodeIndex + 1]
			$pathPattern = '(?m)^\s*path\s*=\s*\{\s*leads_to_tech\s*=\s*' + [regex]::Escape($nextTechnologyId) + '\s+research_cost_coeff\s*=\s*1\s*\}\s*$'
			if ([regex]::Matches($technologyBlock, $pathPattern).Count -ne 1) {
				Add-Failure "Alien technology $technologyId must lead exactly once to $nextTechnologyId."
			}
		}
	}
}

foreach ($equipmentUnlock in @(
	[pscustomobject]@{ Technology = 'coi_alien_pale_horizon_phase_refit'; Equipment = 'coi_alien_mothership_hull_2' },
	[pscustomobject]@{ Technology = 'coi_alien_silent_current_field_refit'; Equipment = 'coi_alien_escort_hull_2' },
	[pscustomobject]@{ Technology = 'coi_alien_gleam_resonance_package'; Equipment = 'coi_alien_gleam_equipment_2' },
	[pscustomobject]@{ Technology = 'coi_alien_needle_guidance_lattice'; Equipment = 'coi_alien_needle_equipment_2' }
)) {
	$technologyBlock = Get-TopLevelTechnologyBlock -Text $alienStarterTechnologyText -Id $equipmentUnlock.Technology
	if ($null -ne $technologyBlock -and [regex]::Matches($technologyBlock, '(?m)^\s*enable_equipments\s*=\s*\{\s*' + [regex]::Escape($equipmentUnlock.Equipment) + '\s*\}\s*$').Count -ne 1) {
		Add-Failure "$($equipmentUnlock.Technology) must unlock $($equipmentUnlock.Equipment) exactly once."
	}
}

$ticTacTechnologyId = 'coi_alien_tic_tac_fabrication'
$ticTacTechnologyBlock = Get-TopLevelTechnologyBlock -Text $alienStarterTechnologyText -Id $ticTacTechnologyId
if ($null -ne $ticTacTechnologyBlock) {
	foreach ($requiredPattern in @(
		'(?s)\ballow_branch\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}',
		'(?m)^\s*research_cost\s*=\s*2\s*$',
		'(?m)^\s*start_year\s*=\s*1938\s*$',
		'(?m)^\s*folder\s*=\s*\{\s*name\s*=\s*coi_alien_technology_folder\s+position\s*=\s*\{\s*x\s*=\s*0\s+y\s*=\s*4\s*\}\s*\}\s*$',
		'(?m)^\s*categories\s*=\s*\{\s*coi_alien_science\s+coi_alien_field_dynamics\s*\}\s*$',
		'(?s)\bon_research_complete\s*=\s*\{\s*coi_alien_unlock_tic_tac_fabrication_effect\s*=\s*yes\s*\}',
		'(?s)\bai_will_do\s*=\s*\{\s*factor\s*=\s*8\s*\}'
    )) {
        if ([regex]::Matches($ticTacTechnologyBlock, $requiredPattern).Count -ne 1) {
            Add-Failure "Tic Tac Fabrication Lattice technology is missing or duplicates required pattern: $requiredPattern"
        }
    }
    foreach ($singleBlock in @('allow_branch', 'on_research_complete', 'folder', 'categories', 'ai_will_do')) {
        if (@(Get-ClausewitzAssignedBlocks -Text $ticTacTechnologyBlock -Assignment $singleBlock).Count -ne 1) {
            Add-Failure "Tic Tac Fabrication Lattice must contain exactly one $singleBlock block."
        }
    }
    if (@(Get-ClausewitzAssignedBlocks -Text $ticTacTechnologyBlock -Assignment 'enable_equipments').Count -ne 0) {
        Add-Failure 'Tic Tac Fabrication Lattice must register a convoy_1 country variant, not unlock a second convoy equipment type.'
    }
}

$silentCurrentTechnologyBlock = Get-TopLevelTechnologyBlock `
    -Text $alienStarterTechnologyText `
    -Id 'coi_alien_silent_current_field_refit'
if ($null -ne $silentCurrentTechnologyBlock) {
	$ticTacPathPattern = '(?s)\bpath\s*=\s*\{\s*leads_to_tech\s*=\s*coi_alien_tic_tac_fabrication\s+research_cost_coeff\s*=\s*1\s*\}'
	if ([regex]::Matches($silentCurrentTechnologyBlock, $ticTacPathPattern).Count -ne 1) {
		Add-Failure 'Silent Current Field Refit must lead exactly once to Tic Tac Fabrication Lattice.'
	}
	if ([regex]::Matches($silentCurrentTechnologyBlock, '(?s)\bpath\s*=\s*\{[^}]*\bresearch_cost_coeff\s*=\s*1\s*\}').Count -ne 1) {
        Add-Failure 'The Silent Current-to-Tic Tac research path must retain research_cost_coeff = 1.'
    }
}

$topLevelVisibleTechnologyCount = [regex]::Matches($alienStarterTechnologyText, '(?m)^\tcoi_alien_[a-z0-9_]+\s*=\s*\{\s*$').Count
if ($topLevelVisibleTechnologyCount -ne 36) {
	Add-Failure "The Consensus Sciences tree defines $topLevelVisibleTechnologyCount visible technologies; expected exactly 36."
}
if ($alienStarterTechnologyText -match '(?m)^\s*always\s*=\s*no\s*$') {
	Add-Failure 'Visible Consensus Sciences technologies must not use the hidden-helper allow = { always = no } contract.'
}
$alienResearchCostTotal = 0.0
foreach ($researchCostMatch in [regex]::Matches($alienStarterTechnologyText, '(?m)^\s*research_cost\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*$')) {
	$alienResearchCostTotal += [double]::Parse($researchCostMatch.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
}
if ([Math]::Abs($alienResearchCostTotal - 70.0) -gt 0.001) {
	Add-Failure "The 36-node Consensus Sciences core totals $alienResearchCostTotal research-cost units; expected 70."
}

$fabricationTechnologyContracts = @(
	[pscustomobject]@{
		Technology = 'coi_alien_additive_airframe_printing'
		Equipment = @('coi_alien_needle_equipment_3', 'coi_alien_gleam_equipment_3')
	},
	[pscustomobject]@{
		Technology = 'coi_alien_continuous_airframe_lattice'
		Equipment = @('coi_alien_needle_equipment_4', 'coi_alien_gleam_equipment_4')
	}
)
foreach ($fabricationContract in $fabricationTechnologyContracts) {
	$fabricationTechnologyBlock = Get-TopLevelTechnologyBlock -Text $alienStarterTechnologyText -Id $fabricationContract.Technology
	if ($null -eq $fabricationTechnologyBlock) { continue }
	$unlockPattern = '(?m)^\s*enable_equipments\s*=\s*\{\s*' +
		([string]::Join('\s+', @($fabricationContract.Equipment | ForEach-Object { [regex]::Escape($_) }))) +
		'\s*\}\s*$'
	if ([regex]::Matches($fabricationTechnologyBlock, $unlockPattern).Count -ne 1) {
		Add-Failure "$($fabricationContract.Technology) must unlock its two sequentially cheaper printed alien-aircraft patterns."
	}
	if ($fabricationTechnologyBlock -match 'production_resource_need_factor|add_equipment_bonus') {
		Add-Failure "$($fabricationContract.Technology) must use real equipment generations rather than unsupported production-resource/equipment-bonus syntax."
	}
}
$additivePrintingBlock = Get-TopLevelTechnologyBlock -Text $alienStarterTechnologyText -Id 'coi_alien_additive_airframe_printing'
if ($null -ne $additivePrintingBlock -and
	$additivePrintingBlock -notmatch '(?s)\ballow\s*=\s*\{\s*ROOT\s*=\s*\{\s*has_tech\s*=\s*coi_alien_needle_guidance_lattice\s+has_tech\s*=\s*coi_alien_gleam_resonance_package\s*\}\s*\}') {
	Add-Failure 'Additive Airframe Printing must require both mature Needle and Gleam patterns so fabrication cannot bypass combat progression.'
}

### XAC research isolation and transformative-project contracts ############
$alienResearchIsolationErrorStart = $errors.Count
$vanillaFolderIds = @(
	'infantry_folder', 'support_folder', 'armour_folder', 'nsb_armour_folder',
	'artillery_folder', 'air_techs_folder', 'bba_air_techs_folder', 'naval_folder',
	'mtgnavalfolder', 'mtgnavalsupportfolder', 'industry_folder',
	'land_doctrine_folder', 'naval_doctrine_folder', 'air_doctrine_folder',
	'special_forces_doctrine_folder', 'electronics_folder'
)
$vanillaTechnologyTagShadowPath = Join-Path $modRoot 'common\technology_tags\00_technology.txt'
$vanillaTechnologyTagShadowText = [IO.File]::ReadAllText($vanillaTechnologyTagShadowPath)
foreach ($folderId in $vanillaFolderIds) {
	$folderBlocks = @(Get-ClausewitzAssignedBlocks -Text $vanillaTechnologyTagShadowText -Assignment $folderId)
	if ($folderBlocks.Count -ne 1 -or
		[regex]::Matches($folderBlocks[0], '(?s)\bavailable\s*=\s*\{.*?\bNOT\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}').Count -ne 1) {
		Add-Failure "Vanilla technology folder $folderId must contain exactly one XAC exclusion in available."
	}
}
if ([regex]::Matches($vanillaTechnologyTagShadowText, '\bNOT\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}').Count -ne 16) {
	Add-Failure 'The generated vanilla technology-folder shadow must contain exactly 16 XAC exclusions.'
}

$vanillaProjectShadowCounts = [ordered]@{
	'air_projects.txt' = 8
	'land_projects.txt' = 9
	'naval_projects.txt' = 19
	'nuclear_projects.txt' = 6
	'radar_projects.txt' = 1
	'rocket_projects.txt' = 6
}
foreach ($entry in $vanillaProjectShadowCounts.GetEnumerator()) {
	$shadowPath = Join-Path $modRoot (Join-Path 'common\special_projects\projects' $entry.Key)
	$shadowText = [IO.File]::ReadAllText($shadowPath)
	$topLevelProjectCount = [regex]::Matches($shadowText, '(?m)^sp_[a-z0-9_]+\s*=\s*\{\s*$').Count
	if ($topLevelProjectCount -ne $entry.Value) {
		Add-Failure "$($entry.Key) shadows $topLevelProjectCount vanilla projects; expected $($entry.Value)."
	}
	$expectedExclusions = 3 * $entry.Value
	if ([regex]::Matches($shadowText, '\bNOT\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}').Count -ne $expectedExclusions) {
		Add-Failure "$($entry.Key) must contain one startup and two loaded-save XAC exclusions per project."
	}
}

$alienSpecialProjectPath = Join-Path $modRoot 'common\special_projects\projects\coi_alien_consensus_science_projects.txt'
$alienSpecialProjectText = [IO.File]::ReadAllText($alienSpecialProjectPath)
$alienSpecialProjectIds = @(
	'coi_alien_sp_self_healing_lattice_demonstrator',
	'coi_alien_sp_molecular_airframe_printer',
	'coi_alien_sp_aperture_stabilization_experiment',
	'coi_alien_sp_interorbital_sentinel_prototype',
	'coi_alien_sp_controlled_atomic_decoherence',
	'coi_alien_sp_full_spectrum_human_culture_model',
	'coi_alien_sp_human_genome_atlas',
	'coi_alien_sp_viable_adult_clone'
)
foreach ($projectId in $alienSpecialProjectIds) {
	$projectBlocks = @(Get-ClausewitzAssignedBlocks -Text $alienSpecialProjectText -Assignment $projectId)
	if ($projectBlocks.Count -ne 1) {
		Add-Failure "Consensus special project $projectId must be defined exactly once."
		continue
	}
	$projectIconPattern = '(?m)^\s*icon\s*=\s*GFX_' + [regex]::Escape($projectId) + '\s*$'
	$projectBlueprintPattern = '(?m)^\s*blueprint_image\s*=\s*GFX_' + [regex]::Escape($projectId) + '_blueprint\s*$'
	foreach ($projectPattern in @(
		'(?s)\ballowed\s*=\s*\{[^}]*\boriginal_tag\s*=\s*XAC\b[^}]*\}',
		$projectIconPattern,
		$projectBlueprintPattern
	)) {
		if ([regex]::Matches($projectBlocks[0], $projectPattern).Count -ne 1) {
			Add-Failure "Consensus special project $projectId is missing or duplicates its XAC/art contract."
		}
	}
	foreach ($localisationKey in @($projectId, "${projectId}_desc")) {
		if (-not $localisationKeys.ContainsKey($localisationKey)) {
			Add-Failure "Missing English special-project localisation key $localisationKey."
		}
	}
}
$consensusBreakthroughCostTotal = 0
foreach ($costMatch in [regex]::Matches($alienSpecialProjectText, '(?m)^\s*breakthrough_cost\s*=\s*\{\s*coi_alien_specialization_matter_fabrication\s*=\s*([0-9]+)\s*\}\s*$')) {
	$consensusBreakthroughCostTotal += [int]$costMatch.Groups[1].Value
}
if ($consensusBreakthroughCostTotal -ne 10) {
	Add-Failure "The eight Consensus projects require $consensusBreakthroughCostTotal breakthrough points; expected the playable 10-point budget."
}
foreach ($capstoneProjectId in @('coi_alien_sp_controlled_atomic_decoherence', 'coi_alien_sp_viable_adult_clone')) {
	$capstoneBlocks = @(Get-ClausewitzAssignedBlocks -Text $alienSpecialProjectText -Assignment $capstoneProjectId)
	if ($capstoneBlocks.Count -eq 1 -and
		[regex]::Matches($capstoneBlocks[0], '(?m)^\s*breakthrough_cost\s*=\s*\{\s*coi_alien_specialization_matter_fabrication\s*=\s*2\s*\}\s*$').Count -ne 1) {
		Add-Failure "$capstoneProjectId must remain a two-breakthrough capstone."
	}
}

$genomeProjectBlock = @(Get-ClausewitzAssignedBlocks -Text $alienSpecialProjectText -Assignment 'coi_alien_sp_human_genome_atlas')
$cloneProjectBlock = @(Get-ClausewitzAssignedBlocks -Text $alienSpecialProjectText -Assignment 'coi_alien_sp_viable_adult_clone')
if ($genomeProjectBlock.Count -eq 1 -and
	([regex]::Matches($genomeProjectBlock[0], '\bcheck_variable\s*=\s*\{\s*coi_alien_tissue_samples\s*>\s*0\s*\}').Count -ne 1 -or
	 [regex]::Matches($genomeProjectBlock[0], '\badd_to_variable\s*=\s*\{\s*coi_alien_tissue_samples\s*=\s*-1\s*\}').Count -ne 1)) {
	Add-Failure 'Human Genome Atlas must require and consume exactly one tissue sample.'
}
if ($cloneProjectBlock.Count -eq 1) {
	foreach ($clonePattern in @(
		'(?s)\bspecial_project_parent\s*=\s*\{\s*coi_alien_sp_human_genome_atlas\s*\}',
		'\bis_special_project_completed\s*=\s*sp:coi_alien_sp_human_genome_atlas\b',
		'\bcheck_variable\s*=\s*\{\s*coi_alien_tissue_samples\s*>\s*0\s*\}',
		'\badd_to_variable\s*=\s*\{\s*coi_alien_tissue_samples\s*=\s*-1\s*\}'
	)) {
		if (-not [regex]::IsMatch($cloneProjectBlock[0], $clonePattern)) {
			Add-Failure 'Viable Adult Clone must follow Genome Atlas and require/consume another tissue sample.'
			break
		}
	}
}

$alienSpecializationText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\special_projects\specialization\coi_alien_specializations.txt'))
foreach ($specializationId in @(
	'coi_alien_specialization_matter_fabrication', 'coi_alien_specialization_field_energy',
	'coi_alien_specialization_cognition_observation', 'coi_alien_specialization_biogenesis'
)) {
	if (@(Get-ClausewitzAssignedBlocks -Text $alienSpecializationText -Assignment $specializationId).Count -ne 1) {
		Add-Failure "Alien special-project specialization $specializationId must be defined exactly once."
	}
}
$alienBuildingText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\buildings\coi_alien_naval_buildings.txt'))
$nexusBlocks = @(Get-ClausewitzAssignedBlocks -Text $alienBuildingText -Assignment 'coi_alien_consensus_research_nexus')
if ($nexusBlocks.Count -ne 1 -or
	[regex]::Matches($nexusBlocks[0], '(?m)^\s*is_buildable\s*=\s*no\s*$').Count -ne 1 -or
	[regex]::Matches($nexusBlocks[0], '(?m)^\s*specialization\s*=\s*\{\s*coi_alien_specialization_matter_fabrication\s*\}\s*$').Count -ne 1 -or
	[regex]::Matches($nexusBlocks[0], '\bcoi_alien_specialization_(?:field_energy|cognition_observation|biogenesis)\b').Count -ne 0) {
	Add-Failure 'The non-buildable Consensus Research Nexus must use exactly one engine-supported primary Consensus Sciences specialization.'
}
if ([regex]::Matches($stateText, '(?m)^\s*coi_alien_consensus_research_nexus\s*=\s*1\s*$').Count -ne 1) {
	Add-Failure 'Pale Anchorage must receive exactly one history-placed Consensus Research Nexus.'
}
if ([regex]::Matches($countryHistoryText, '(?m)^\s*set_research_slots\s*=\s*4\s*$').Count -ne 1) {
	Add-Failure 'XAC country history must start with exactly four research slots.'
}

$alienCharacterText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\characters\coi_alien_characters.txt'))
$oruBlocks = @(Get-ClausewitzAssignedBlocks -Text $alienCharacterText -Assignment 'coi_alien_oru')
if ($oruBlocks.Count -ne 1) {
	Add-Failure 'Oru must be defined exactly once as the Consensus Sciences project scientist.'
}
else {
	if ([regex]::Matches($oruBlocks[0], '(?m)^\s*coi_alien_specialization_matter_fabrication\s*=\s*3\s*$').Count -ne 1 -or
		[regex]::Matches($oruBlocks[0], '\bcoi_alien_specialization_(?:field_energy|cognition_observation|biogenesis)\b').Count -ne 0) {
		Add-Failure 'Oru must have exactly one explicit skill-3 override in the operational Consensus Sciences specialization.'
	}
}

$vanillaBuildingShadowPath = Join-Path $modRoot 'common\buildings\00_buildings.txt'
$vanillaBuildingShadowText = [IO.File]::ReadAllText($vanillaBuildingShadowPath)
foreach ($facilityId in @('naval_facility', 'nuclear_facility', 'air_facility', 'land_facility')) {
	$facilityBlocks = @(Get-ClausewitzAssignedBlocks -Text $vanillaBuildingShadowText -Assignment $facilityId)
	if ($facilityBlocks.Count -ne 1 -or [regex]::Matches($facilityBlocks[0], '(?m)^\s*hide_if_missing_tech\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "Vanilla facility $facilityId must be technology-hidden from XAC in the pinned building shadow."
	}
}
$humanFacilityTechText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\technologies\coi_alien_research_isolation_technologies.txt'))
$humanFacilityTechBlocks = @(Get-ClausewitzAssignedBlocks -Text $humanFacilityTechText -Assignment 'coi_alien_human_experimental_facility_access')
if ($humanFacilityTechBlocks.Count -ne 1 -or
	[regex]::Matches($humanFacilityTechBlocks[0], '(?m)^\s*enable_building\s*=\s*\{\s*building\s*=\s*(?:naval_facility|nuclear_facility|air_facility|land_facility)\s+level\s*=\s*1\s*\}\s*$').Count -ne 4 -or
	[regex]::Matches($humanFacilityTechBlocks[0], '\ballow\s*=\s*\{\s*always\s*=\s*no\s*\}').Count -ne 1) {
	Add-Failure 'The hidden human facility-access technology must enable all four vanilla facilities and remain unresearchable.'
}
$researchIsolationEffectText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_effects\coi_alien_research_isolation_effects.txt'))
$humanFacilityGrantBlocks = @(Get-ClausewitzAssignedBlocks -Text $researchIsolationEffectText -Assignment 'coi_alien_grant_human_facility_access_effect')
if ($humanFacilityGrantBlocks.Count -ne 1 -or
	$humanFacilityGrantBlocks[0] -notmatch '(?s)NOT\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}.*?set_technology\s*=\s*\{\s*coi_alien_human_experimental_facility_access\s*=\s*1\s*\}') {
	Add-Failure 'Only non-XAC countries may receive the hidden vanilla-facility access technology.'
}
$nexusMigrationBlocks = @(Get-ClausewitzAssignedBlocks -Text $researchIsolationEffectText -Assignment 'coi_alien_ensure_consensus_research_nexus_effect')
$nexusMigrationFlag = 'coi_alien_consensus_research_nexus_v050_migrated'
if ($nexusMigrationBlocks.Count -ne 1) {
	Add-Failure 'The versioned Consensus Research Nexus migration effect must be defined exactly once.'
}
else {
	$nexusMigrationBlock = $nexusMigrationBlocks[0]
	if ([regex]::Matches($nexusMigrationBlock, '(?m)^\s*NOT\s*=\s*\{\s*has_country_flag\s*=\s*' + [regex]::Escape($nexusMigrationFlag) + '\s*\}\s*$').Count -ne 1 -or
		[regex]::Matches($nexusMigrationBlock, '(?m)^\s*set_country_flag\s*=\s*' + [regex]::Escape($nexusMigrationFlag) + '\s*$').Count -ne 2) {
		Add-Failure 'Consensus Research Nexus migration must use one versioned guard and mark both successful recognition and placement paths complete.'
	}
	if ($nexusMigrationBlock -notmatch '(?s)original_tag\s*=\s*XAC.*?1082\s*=\s*\{\s*is_owned_by\s*=\s*ROOT\s+is_controlled_by\s*=\s*ROOT\s*\}.*?coi_alien_consensus_research_nexus\s*>\s*0.*?set_country_flag\s*=\s*coi_alien_consensus_research_nexus_v050_migrated.*?else_if.*?coi_alien_consensus_research_nexus\s*<\s*1.*?add_building_construction\s*=\s*\{.*?type\s*=\s*coi_alien_consensus_research_nexus.*?instant_build\s*=\s*yes.*?province\s*=\s*13414.*?set_country_flag\s*=\s*coi_alien_consensus_research_nexus_v050_migrated') {
		Add-Failure 'Old XAC saves must recognize or receive one immediate Nexus only while Pale Anchorage is available, then permanently complete the v0.5.0 migration.'
	}
	if ([regex]::Matches($nexusMigrationBlock, '(?m)^\s*add_building_construction\s*=\s*\{\s*$').Count -ne 1) {
		Add-Failure 'Consensus Research Nexus migration may contain exactly one construction path; post-migration destruction must not trigger replacement.'
	}
}
$oruSkillMigrationBlocks = @(Get-ClausewitzAssignedBlocks -Text $researchIsolationEffectText -Assignment 'coi_alien_ensure_oru_consensus_skill_effect')
$oruSkillMigrationFlag = 'coi_alien_oru_consensus_skill_v050_migrated'
if ($oruSkillMigrationBlocks.Count -ne 1) {
	Add-Failure 'The versioned Oru Consensus Sciences migration effect must be defined exactly once.'
}
else {
	$oruSkillMigrationBlock = $oruSkillMigrationBlocks[0]
	if ([regex]::Matches($oruSkillMigrationBlock, '(?m)^\s*NOT\s*=\s*\{\s*has_country_flag\s*=\s*' + [regex]::Escape($oruSkillMigrationFlag) + '\s*\}\s*$').Count -ne 1 -or
		[regex]::Matches($oruSkillMigrationBlock, '(?m)^\s*set_country_flag\s*=\s*' + [regex]::Escape($oruSkillMigrationFlag) + '\s*$').Count -ne 1) {
		Add-Failure 'Oru Consensus Sciences migration must use and commit one v0.5.0 country flag.'
	}
	if ([regex]::Matches($oruSkillMigrationBlock, '(?m)^\s*has_character\s*=\s*coi_alien_oru\s*$').Count -ne 1 -or
		[regex]::Matches($oruSkillMigrationBlock, '(?m)^\s*coi_alien_oru\s*=\s*\{\s*$').Count -ne 1) {
		Add-Failure 'Oru Consensus Sciences migration must defer completion until Oru exists, then enter his character scope exactly once.'
	}
	$oruSkillTriggers = @(Get-ClausewitzAssignedBlocks -Text $oruSkillMigrationBlock -Assignment 'has_scientist_level')
	$oruSkillAdds = @(Get-ClausewitzAssignedBlocks -Text $oruSkillMigrationBlock -Assignment 'add_scientist_level')
	if ($oruSkillTriggers.Count -ne 2 -or
		[regex]::Matches(($oruSkillTriggers -join "`n"), '(?m)^\s*specialization\s*=\s*coi_alien_specialization_matter_fabrication\s*$').Count -ne 2 -or
		@($oruSkillTriggers | Where-Object { $_ -match '(?m)^\s*level\s*<\s*2\s*$' }).Count -ne 1 -or
		@($oruSkillTriggers | Where-Object { $_ -match '(?m)^\s*level\s*<\s*3\s*$' }).Count -ne 1) {
		Add-Failure 'Oru migration must independently test Consensus Sciences skill below 2 and below 3 exactly once each.'
	}
	if ($oruSkillAdds.Count -ne 2 -or
		[regex]::Matches(($oruSkillAdds -join "`n"), '(?m)^\s*specialization\s*=\s*coi_alien_specialization_matter_fabrication\s*$').Count -ne 2 -or
		@($oruSkillAdds | Where-Object { $_ -match '(?m)^\s*level\s*=\s*2\s*$' }).Count -ne 1 -or
		@($oruSkillAdds | Where-Object { $_ -match '(?m)^\s*level\s*=\s*1\s*$' }).Count -ne 1) {
		Add-Failure 'Oru migration must add 2 levels below skill 2, then add 1 level below skill 3.'
	}
	if ($oruSkillMigrationBlock -match '(?m)^\s*else_if\s*=\s*\{\s*$') {
		Add-Failure 'Oru migration skill checks must be independent so a level-0 old save reaches skill 3 in one invocation.'
	}
}
$researchIsolationOnActionText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\on_actions\coi_alien_research_isolation_on_actions.txt'))
foreach ($researchIsolationHook in @(
	'every_country\s*=\s*\{\s*coi_alien_grant_human_facility_access_effect\s*=\s*yes\s*\}',
	'XAC\s*=\s*\{\s*coi_alien_ensure_consensus_research_nexus_effect\s*=\s*yes\s+coi_alien_ensure_oru_consensus_skill_effect\s*=\s*yes\s*\}',
	'on_daily_XAC\s*=\s*\{\s*effect\s*=\s*\{\s*coi_alien_ensure_consensus_research_nexus_effect\s*=\s*yes\s+coi_alien_ensure_oru_consensus_skill_effect\s*=\s*yes\s*\}'
)) {
	if ($researchIsolationOnActionText -notmatch $researchIsolationHook) {
		Add-Failure "Research-isolation startup/migration hook is missing: $researchIsolationHook"
	}
}
if ($errors.Count -eq $alienResearchIsolationErrorStart) {
	Add-Pass 'Validated six alien research domains, one engine-valid Consensus specialization, XAC isolation, eight staffed projects, one migrated Nexus, four research slots, and human-only facilities'
}

### Human Sciences, observation, tissue, and facsimile contracts ##########
$humanScienceErrorStart = $errors.Count
$humanScienceEffectText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_effects\coi_alien_human_sciences_effects.txt'))
$humanScienceDecisionText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\decisions\coi_alien_human_sciences_decisions.txt'))
$humanScienceTriggerText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_triggers\coi_alien_human_sciences_triggers.txt'))
$humanScienceOnActionText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\on_actions\coi_alien_human_sciences_on_actions.txt'))
$humanScienceEventText = [IO.File]::ReadAllText((Join-Path $modRoot 'events\coi_alien_human_sciences_events.txt'))
$humanScienceLocText = [IO.File]::ReadAllText((Join-Path $modRoot 'localisation\english\coi_alien_human_sciences_l_english.yml'))

foreach ($ledgerContract in @(
	[pscustomobject]@{ Variable = 'coi_alien_human_insights'; Maximum = 100 },
	[pscustomobject]@{ Variable = 'coi_alien_tissue_samples'; Maximum = 10 },
	[pscustomobject]@{ Variable = 'coi_alien_active_clone_operatives'; Maximum = 2 },
	[pscustomobject]@{ Variable = 'coi_alien_cultural_dossier'; Maximum = 4 }
)) {
	$ledgerPattern = 'clamp_variable\s*=\s*\{\s*var\s*=\s*' + [regex]::Escape($ledgerContract.Variable) + '\s+min\s*=\s*0\s+max\s*=\s*' + $ledgerContract.Maximum + '\s*\}'
	if ($humanScienceEffectText -notmatch $ledgerPattern) {
		Add-Failure "Human Sciences ledger $($ledgerContract.Variable) must be clamped to 0-$($ledgerContract.Maximum)."
	}
}

$observationPolicyContracts = @(
	[pscustomobject]@{ Decision = 'coi_alien_adopt_passive_observation'; Flag = 'coi_alien_observation_passive'; Gain = 'coi_alien_add_human_insights_one_effect' },
	[pscustomobject]@{ Decision = 'coi_alien_adopt_directed_infiltration'; Flag = 'coi_alien_observation_directed'; Gain = 'coi_alien_add_human_insights_two_effect' },
	[pscustomobject]@{ Decision = 'coi_alien_adopt_aggressive_sampling'; Flag = 'coi_alien_observation_aggressive'; Gain = 'coi_alien_add_human_insights_three_effect' }
)
foreach ($policy in $observationPolicyContracts) {
	$policyBlocks = @(Get-ClausewitzAssignedBlocks -Text $humanScienceDecisionText -Assignment $policy.Decision)
	if ($policyBlocks.Count -ne 1 -or [regex]::Matches($policyBlocks[0], '(?m)^\s*cost\s*=\s*25\s*$').Count -ne 1) {
		Add-Failure "Observation decision $($policy.Decision) must exist once and cost 25 PP."
	}
	if ($humanScienceEffectText -notmatch ('(?s)has_country_flag\s*=\s*' + [regex]::Escape($policy.Flag) + '.*?' + [regex]::Escape($policy.Gain) + '\s*=\s*yes')) {
		Add-Failure "Observation policy $($policy.Flag) must produce its intended monthly Human Insight gain."
	}
}
if ($humanScienceEffectText -notmatch '(?s)coi_alien_start_observation_policy_cooldown_effect\s*=\s*\{.*?days\s*=\s*90' -or
	$humanScienceEffectText -notmatch '(?s)is_ai\s*=\s*yes.*?coi_alien_adopt_passive_observation_effect\s*=\s*yes') {
	Add-Failure 'Observation policies must use a 90-day cooldown and only AI may receive the free default policy.'
}
if ($humanScienceEffectText -notmatch '(?s)has_country_flag\s*=\s*coi_alien_observation_aggressive.*?coi_alien_add_tissue_sample_effect\s*=\s*yes.*?any_country\s*=\s*\{.*?NOT\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}.*?else\s*=\s*\{.*?random_country') {
	Add-Failure 'Aggressive Sampling must retain tissue gain and discovery risk even before any country dossier exists.'
}
if ($humanScienceOnActionText -notmatch '(?s)on_state_control_changed\s*=\s*\{.*?ROOT\s*=\s*\{.*?original_tag\s*=\s*XAC.*?has_tech\s*=\s*coi_alien_tissue_analysis.*?coi_alien_add_tissue_sample_effect\s*=\s*yes.*?set_state_flag\s*=\s*coi_alien_tissue_sample_recovered') {
	Add-Failure 'First occupation of a human-controlled state after Tissue Analysis must yield one guarded tissue sample.'
}
foreach ($operationInsightContract in @(
	'coi_alien_silent_systems_survey', 'coi_alien_seed_mimetic_access',
	'coi_alien_penetrate_research_networks', 'coi_alien_extract_lead_scientist'
)) {
	if ($humanScienceOnActionText -notmatch ('(?s)is_operation_type\s*=\s*' + [regex]::Escape($operationInsightContract) + '.*?coi_alien_add_human_insights_')) {
		Add-Failure "$operationInsightContract must contribute Human Insights."
	}
}
if ($humanScienceOnActionText -notmatch '(?s)is_operation_type\s*=\s*coi_alien_extract_lead_scientist.*?coi_alien_add_tissue_sample_effect\s*=\s*yes') {
	Add-Failure 'Extract Lead Scientist must also recover one tissue sample.'
}
foreach ($cloneDecisionId in @('coi_alien_create_facsimile_lena_marlow', 'coi_alien_create_facsimile_daniel_voss')) {
	$cloneDecisionBlocks = @(Get-ClausewitzAssignedBlocks -Text $humanScienceDecisionText -Assignment $cloneDecisionId)
	if ($cloneDecisionBlocks.Count -ne 1 -or
		$cloneDecisionBlocks[0] -notmatch '(?s)complete_effect\s*=\s*\{.*?coi_alien_tissue_samples\s*=\s*-1.*?coi_alien_active_clone_operatives\s*=\s*1.*?_in_progress' -or
		$cloneDecisionBlocks[0] -notmatch '(?s)cancel_effect\s*=\s*\{.*?coi_alien_tissue_samples\s*=\s*1.*?coi_alien_active_clone_operatives\s*=\s*-1.*?clr_country_flag' -or
		$cloneDecisionBlocks[0] -notmatch '(?s)remove_effect\s*=\s*\{.*?create_operative_leader\s*=\s*\{.*?GFX\s*=\s*GFX_portrait_coi_alien_facsimile_.*?nationalities\s*=\s*\{\s*FROM\s*\}') {
		Add-Failure "$cloneDecisionId must reserve/refund its scarce slot and tissue, then create a localized human operative."
	}
}
if ($humanScienceTriggerText -notmatch '(?s)coi_alien_can_create_conditioned_facsimile_trigger\s*=\s*\{.*?has_tech\s*=\s*coi_alien_conditioned_identity_imprinting.*?OR\s*=\s*\{\s*NOT\s*=\s*\{\s*has_dlc\s*=\s*"Gotterdammerung"\s*\}.*?is_special_project_completed\s*=\s*sp:coi_alien_sp_viable_adult_clone') {
	Add-Failure 'Facsimile creation must support both the completed prototype and the no-Götterdämmerung deterministic fallback.'
}
if ($humanScienceEventText -notmatch '(?s)id\s*=\s*coi_alien_human_sciences\.6.*?coi_alien_clone_identity_resolved.*?remove_ideas\s*=\s*coi_alien_clone_personhood_protocol' -or
	$humanScienceEffectText -notmatch 'NOT\s*=\s*\{\s*has_country_flag\s*=\s*coi_alien_clone_identity_resolved\s*\}') {
	Add-Failure 'The clone identity crisis must resolve once and prevent Personhood/Reconditioning from stacking.'
}
foreach ($threshold in @(20, 50, 80)) {
	$thresholdMarkup = ([string][char]0x00A7) + 'Y' + $threshold + ([string][char]0x00A7) + '!'
	if ($humanScienceLocText -notmatch [regex]::Escape($thresholdMarkup)) {
		Add-Failure "Human Sciences category tooltip must disclose the $threshold Insight threshold."
	}
}
if ($errors.Count -eq $humanScienceErrorStart) {
	Add-Pass 'Validated Human Insights, observation risk, dossier/tissue sources, no-DLC gates, and two reserved unique facsimile operatives'
}

$consensusScienceArtErrorStart = $errors.Count
$consensusScienceMasterNames = @(
	'coi_alien_tech_human_sciences.png', 'coi_alien_tech_fabrication.png',
	'coi_alien_sp_self_healing_lattice.png', 'coi_alien_sp_aperture_stabilization.png',
	'coi_alien_sp_interorbital_sentinel.png', 'coi_alien_sp_atomic_decoherence.png',
	'coi_alien_sp_human_culture_model.png', 'coi_alien_sp_human_genome_atlas.png',
	'coi_alien_sp_viable_adult_clone.png', 'coi_alien_sp_molecular_airframe_printer.png'
)
foreach ($masterName in $consensusScienceMasterNames) {
	$masterPath = Join-Path $ProjectRoot (Join-Path 'Source\Art\Masters' $masterName)
	if (-not (Test-Path -LiteralPath $masterPath -PathType Leaf)) {
		Add-Failure "Missing Consensus Sciences ImageGen master: $masterName"
		continue
	}
	try {
		$masterBitmap = [System.Drawing.Bitmap]::new($masterPath)
		try {
			if ($masterBitmap.Width -lt 1024 -or $masterBitmap.Height -lt 1024) {
				Add-Failure "$masterName must retain at least a 1024x1024 source canvas."
			}
			$cornerAlpha = @(
				$masterBitmap.GetPixel(0, 0).A,
				$masterBitmap.GetPixel($masterBitmap.Width - 1, 0).A,
				$masterBitmap.GetPixel(0, $masterBitmap.Height - 1).A,
				$masterBitmap.GetPixel($masterBitmap.Width - 1, $masterBitmap.Height - 1).A
			)
			if (@($cornerAlpha | Where-Object { $_ -gt 8 }).Count -gt 0) {
				Add-Failure "$masterName must retain transparent or effectively transparent canvas corners."
			}
		}
		finally { $masterBitmap.Dispose() }
	}
	catch {
		Add-Failure "Could not decode Consensus Sciences ImageGen master ${masterName}: $($_.Exception.Message)"
	}
}
$consensusScienceProvenancePath = Join-Path $ProjectRoot 'Source\Art\consensus_sciences_imagegen_prompts.md'
if (-not (Test-Path -LiteralPath $consensusScienceProvenancePath -PathType Leaf)) {
	Add-Failure "Missing Consensus Sciences ImageGen provenance: $consensusScienceProvenancePath"
}
else {
	$consensusScienceProvenanceText = [IO.File]::ReadAllText($consensusScienceProvenancePath)
	if ($consensusScienceProvenanceText -notmatch 'built-in OpenAI ImageGen, new-image generation' -or
		[regex]::Matches($consensusScienceProvenanceText, 'ImageGen output:\s*`exec-[^`]+\.png`').Count -ne 12) {
		Add-Failure 'Consensus Sciences provenance must record built-in new-image mode and all 12 generated source IDs.'
	}
	foreach ($masterName in $consensusScienceMasterNames) {
		if ($consensusScienceProvenanceText -notmatch [regex]::Escape($masterName)) {
			Add-Failure "Consensus Sciences provenance does not name $masterName."
		}
	}
}
if ($errors.Count -eq $consensusScienceArtErrorStart) {
	Add-Pass 'Validated ten transparent high-resolution Consensus Sciences ImageGen masters and 12-source built-in-mode provenance'
}

$alienEquipmentText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\units\equipment\coi_alien_naval_and_air_equipment.txt'))
$alienTechnologyGfxText = (Get-ChildItem -LiteralPath (Join-Path $modRoot 'interface') -File -Filter 'coi_alien_*.gfx' |
	ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
$equipmentUpgradeContracts = @(
	[pscustomobject]@{ Id = 'coi_alien_mothership_hull_2'; Archetype = 'coi_alien_mothership_hull'; Parent = 'coi_alien_mothership_hull_1'; Year = '1937' },
	[pscustomobject]@{ Id = 'coi_alien_escort_hull_2'; Archetype = 'coi_alien_escort_hull'; Parent = 'coi_alien_escort_hull_1'; Year = '1937' },
	[pscustomobject]@{ Id = 'coi_alien_needle_equipment_2'; Archetype = 'coi_alien_needle_equipment'; Parent = 'coi_alien_needle_equipment_1'; Year = '1937' },
	[pscustomobject]@{ Id = 'coi_alien_needle_equipment_3'; Archetype = 'coi_alien_needle_equipment'; Parent = 'coi_alien_needle_equipment_2'; Year = '1936' },
	[pscustomobject]@{ Id = 'coi_alien_needle_equipment_4'; Archetype = 'coi_alien_needle_equipment'; Parent = 'coi_alien_needle_equipment_3'; Year = '1936' },
	[pscustomobject]@{ Id = 'coi_alien_gleam_equipment_2'; Archetype = 'coi_alien_gleam_equipment'; Parent = 'coi_alien_gleam_equipment_1'; Year = '1937' },
	[pscustomobject]@{ Id = 'coi_alien_gleam_equipment_3'; Archetype = 'coi_alien_gleam_equipment'; Parent = 'coi_alien_gleam_equipment_2'; Year = '1936' },
	[pscustomobject]@{ Id = 'coi_alien_gleam_equipment_4'; Archetype = 'coi_alien_gleam_equipment'; Parent = 'coi_alien_gleam_equipment_3'; Year = '1936' }
)
foreach ($equipmentContract in $equipmentUpgradeContracts) {
    $equipmentBlock = Get-TopLevelTechnologyBlock -Text $alienEquipmentText -Id $equipmentContract.Id
    if ($null -eq $equipmentBlock) { continue }
    else {
        foreach ($propertyContract in @(
            [pscustomobject]@{ Property = 'year'; Value = $equipmentContract.Year },
            [pscustomobject]@{ Property = 'archetype'; Value = $equipmentContract.Archetype },
            [pscustomobject]@{ Property = 'parent'; Value = $equipmentContract.Parent }
        )) {
            $propertyPattern = '(?m)^\s*' + [regex]::Escape($propertyContract.Property) + '\s*=\s*' + [regex]::Escape($propertyContract.Value) + '\s*$'
            if ([regex]::Matches($equipmentBlock, $propertyPattern).Count -ne 1) {
                Add-Failure "$($equipmentContract.Id) must declare $($propertyContract.Property) = $($propertyContract.Value) exactly once."
            }
        }
    }
    $equipmentIconPattern = '(?i)(?:^|\s)name\s*=\s*"GFX_' + [regex]::Escape($equipmentContract.Id) + '_medium"(?=\s|\})'
    if ([regex]::Matches($alienTechnologyGfxText, $equipmentIconPattern).Count -ne 1) {
        Add-Failure "Missing or duplicate medium GFX alias for $($equipmentContract.Id)."
    }
    foreach ($localisationSuffix in @('', '_short', '_desc')) {
        if (-not $localisationKeys.ContainsKey($equipmentContract.Id + $localisationSuffix)) {
            Add-Failure "Missing English localisation key $($equipmentContract.Id + $localisationSuffix)."
        }
    }
}

$printedAircraftContracts = @(
	[pscustomobject]@{ Id = 'coi_alien_needle_equipment_3'; Cost = '70'; Aluminium = '4'; Chromium = '4'; Tungsten = '2' },
	[pscustomobject]@{ Id = 'coi_alien_needle_equipment_4'; Cost = '63'; Aluminium = '4'; Chromium = '3'; Tungsten = '2' },
	[pscustomobject]@{ Id = 'coi_alien_gleam_equipment_3'; Cost = '101'; Aluminium = '5'; Chromium = '4'; Tungsten = '3' },
	[pscustomobject]@{ Id = 'coi_alien_gleam_equipment_4'; Cost = '91'; Aluminium = '5'; Chromium = '3'; Tungsten = '3' }
)
foreach ($printedAircraft in $printedAircraftContracts) {
	$equipmentBlock = Get-TopLevelTechnologyBlock -Text $alienEquipmentText -Id $printedAircraft.Id
	if ($null -eq $equipmentBlock) { continue }
	foreach ($propertyName in @('Cost', 'Aluminium', 'Chromium', 'Tungsten')) {
		$scriptProperty = if ($propertyName -eq 'Cost') { 'build_cost_ic' } else { $propertyName.ToLowerInvariant() }
		$propertyPattern = '(?m)^\s*' + [regex]::Escape($scriptProperty) + '\s*=\s*' + [regex]::Escape($printedAircraft.$propertyName) + '\s*$'
		if ([regex]::Matches($equipmentBlock, $propertyPattern).Count -ne 1) {
			Add-Failure "$($printedAircraft.Id) must declare $scriptProperty = $($printedAircraft.$propertyName) exactly once."
		}
	}
}

$alienAiDesignText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\ai_equipment\coi_alien_naval_designs.txt'))
foreach ($aiDesignContract in @(
    [pscustomobject]@{
        Id = 'coi_alien_pale_horizon_phase_refit_design'
        Type = 'coi_alien_mothership_hull_2'
        ReplacesAt = 'coi_alien_pale_horizon_phase_refit'
    },
    [pscustomobject]@{
        Id = 'coi_alien_silent_current_field_refit_design'
        Type = 'coi_alien_escort_hull_2'
        ReplacesAt = 'coi_alien_silent_current_field_refit'
    }
)) {
    $aiDesignBlock = Get-TopLevelTechnologyBlock -Text $alienAiDesignText -Id $aiDesignContract.Id
    if ($null -ne $aiDesignBlock) {
        $typePattern = '(?m)^\s*type\s*=\s*' + [regex]::Escape($aiDesignContract.Type) + '\s*$'
        if ([regex]::Matches($aiDesignBlock, $typePattern).Count -ne 1) {
            Add-Failure "AI design $($aiDesignContract.Id) must target $($aiDesignContract.Type) exactly once."
        }
    }
    $replacementPattern = '(?m)^\s*has_tech\s*=\s*' + [regex]::Escape($aiDesignContract.ReplacesAt) + '\s*$'
    if ([regex]::Matches($alienAiDesignText, $replacementPattern).Count -ne 1) {
        Add-Failure "The baseline alien ship design must be retired exactly once at $($aiDesignContract.ReplacesAt)."
    }
    if (-not $localisationKeys.ContainsKey($aiDesignContract.Id)) {
        Add-Failure "Missing English localisation key $($aiDesignContract.Id)."
    }
}

foreach ($technologyId in $expectedVisibleTechnologyIds) {
    $technologyIconPattern = '(?i)(?:^|\s)name\s*=\s*"GFX_' + [regex]::Escape($technologyId) + '_medium"(?=\s|\})'
    if ([regex]::Matches($alienTechnologyGfxText, $technologyIconPattern).Count -ne 1) {
        Add-Failure "Missing or duplicate medium GFX alias for technology $technologyId."
    }
    foreach ($localisationSuffix in @('', '_desc')) {
        if (-not $localisationKeys.ContainsKey($technologyId + $localisationSuffix)) {
            Add-Failure "Missing English localisation key $($technologyId + $localisationSuffix)."
        }
    }
}
foreach ($localisationKey in @(
    'coi_alien_technology_folder',
    'coi_alien_technology_folder_desc',
	'coi_alien_technology_materials_title',
	'coi_alien_technology_propulsion_title',
	'coi_alien_technology_energy_title',
	'coi_alien_technology_computation_title',
	'coi_alien_technology_human_sciences_title',
	'coi_alien_technology_fabrication_title'
)) {
    if (-not $localisationKeys.ContainsKey($localisationKey)) {
        Add-Failure "Missing English alien technology UI localisation key $localisationKey."
    }
}

$alienTechnologyItemsText = [IO.File]::ReadAllText((Join-Path $modRoot 'interface\coi_alien_technology_items.gui'))
foreach ($templateName in @(
    'techtree_coi_alien_technology_folder_item',
    'techtree_coi_alien_technology_folder_small_item'
)) {
    $templatePattern = '(?m)^\s*name\s*=\s*"' + [regex]::Escape($templateName) + '"\s*$'
    if ([regex]::Matches($alienTechnologyItemsText, $templatePattern).Count -ne 1) {
        Add-Failure "Alien technology UI item template $templateName must exist exactly once."
    }
}

$countryTechnologyUiPath = Join-Path $modRoot 'interface\countrytechtreeview.gui'
$countryTechnologyUiText = [IO.File]::ReadAllText($countryTechnologyUiPath)
if ($countryTechnologyUiText.Contains("`r`n")) {
    Add-Failure 'Generated countrytechtreeview.gui must retain the vanilla LF-only line-ending contract.'
}
foreach ($uiName in @(
    'coi_alien_technology_folder',
    'coi_alien_technology_folder_tab',
    'coi_alien_adaptive_metamaterials_tree',
	'coi_alien_inertial_field_theory_tree',
	'coi_alien_coherent_energy_control_tree',
	'coi_alien_predictive_computation_tree',
	'coi_alien_comparative_human_ethology_tree',
	'coi_alien_expeditionary_pattern_libraries_tree'
)) {
    $uiNamePattern = '(?m)^\s*name\s*=\s*"' + [regex]::Escape($uiName) + '"\s*$'
    if ([regex]::Matches($countryTechnologyUiText, $uiNamePattern).Count -ne 1) {
        Add-Failure "Generated technology-tree UI name $uiName must exist exactly once."
    }
}

# Remove the two generated blocks and prove the checked-in override is otherwise
# byte-for-byte equivalent to HOI4 1.19.2.0's vanilla GUI.
$reconstructedVanillaTechnologyUi = [regex]::Replace(
    $countryTechnologyUiText,
    '(?ms)^\t\t# COI_ALIEN_TECH_FOLDER_BEGIN.*?^\t\t# COI_ALIEN_TECH_FOLDER_END\n\n',
    ''
)
$reconstructedVanillaTechnologyUi = [regex]::Replace(
    $reconstructedVanillaTechnologyUi,
    '(?ms)^\t\t\t# COI_ALIEN_TECH_TAB_BEGIN.*?^\t\t\t# COI_ALIEN_TECH_TAB_END\n\n',
    ''
)
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
    $reconstructedBytes = [Text.UTF8Encoding]::new($false).GetBytes($reconstructedVanillaTechnologyUi)
    $reconstructedHash = [BitConverter]::ToString($sha256.ComputeHash($reconstructedBytes)).Replace('-', '')
}
finally {
    $sha256.Dispose()
}
$expectedVanillaTechnologyUiHash = 'FEC641FB738AB59369CAC40AE902FDBA793BED7CBAA2C807756207A2E1F01045'
if ($reconstructedHash -cne $expectedVanillaTechnologyUiHash) {
    Add-Failure "Alien technology UI override is not a clean patch of HOI4 1.19.2.0; reconstructed base hash is $reconstructedHash."
}

### v0.4.1 XAC Tic Tac convoy contracts. HOI4 supports exactly one convoy
### equipment type, so alien logistics use official country variants of
### convoy_1 plus an XAC-only equipment bonus. The generated combat strip is a
### staged namespaced asset because combat art is selected by equipment type.
$equipmentDirectory = Join-Path $modRoot 'common\units\equipment'
$equipmentDirectoryText = (Get-ChildItem -LiteralPath $equipmentDirectory -File -Filter '*.txt' |
    ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
foreach ($forbiddenTicTacEquipmentPath in @(
    'common\units\equipment\coi_alien_convoy_equipment.txt',
    'common\units\equipment\zz_coi_alien_convoy_equipment.txt'
)) {
    if (Test-Path -LiteralPath (Join-Path $modRoot $forbiddenTicTacEquipmentPath)) {
        Add-Failure "Unsupported second-convoy equipment file must not exist: $forbiddenTicTacEquipmentPath"
    }
}
if ([regex]::Matches($equipmentDirectoryText, '(?m)^\s*coi_alien_tic_tac_convoy\s*=\s*\{\s*$').Count -ne 0 -or
    [regex]::Matches($equipmentDirectoryText, '(?m)^\s*archetype\s*=\s*convoy\s*$').Count -ne 0) {
    Add-Failure 'Tic Tacs must not define a second convoy equipment model or child archetype; use country variants of convoy_1.'
}

$ticTacInitializer = 'coi_alien_initialize_tic_tac_reserve_effect'
$ticTacReserveFlag = 'coi_alien_tic_tac_reserve_stocked'
$ticTacReserveBlocks = @(Get-ClausewitzAssignedBlocks -Text $navalEffectText -Assignment $ticTacInitializer)
if ($ticTacReserveBlocks.Count -ne 1) {
    Add-Failure "Tic Tac reserve initializer must be defined exactly once; found $($ticTacReserveBlocks.Count)."
}
else {
    $ticTacReserveBlock = $ticTacReserveBlocks[0]
    foreach ($reservePattern in @(
        '(?m)^\s*original_tag\s*=\s*XAC\s*$',
        '(?m)^\s*add_ideas\s*=\s*coi_alien_tic_tac_transit_envelope\s*$',
        '(?m)^\s*NOT\s*=\s*\{\s*has_country_flag\s*=\s*coi_alien_tic_tac_reserve_stocked\s*\}\s*$',
        '(?m)^\s*amount\s*=\s*100\s*$',
        '(?m)^\s*producer\s*=\s*XAC\s*$',
        '(?m)^\s*variant_name\s*=\s*"Tic Tac Expeditionary Reserve"\s*$',
        '(?m)^\s*set_country_flag\s*=\s*coi_alien_tic_tac_reserve_stocked\s*$'
    )) {
        if ([regex]::Matches($ticTacReserveBlock, $reservePattern).Count -ne 1) {
            Add-Failure "One-time Tic Tac reserve grant is missing or duplicates required pattern: $reservePattern"
        }
    }
    $reserveVariantBlocks = @(Get-ClausewitzAssignedBlocks -Text $ticTacReserveBlock -Assignment 'create_equipment_variant')
    if ($reserveVariantBlocks.Count -ne 1) {
        Add-Failure "Tic Tac reserve initializer must register exactly one country variant; found $($reserveVariantBlocks.Count)."
    }
    else {
        foreach ($variantPattern in @(
            '(?m)^\s*name\s*=\s*"Tic Tac Expeditionary Reserve"\s*$',
            '(?m)^\s*type\s*=\s*convoy_1\s*$',
            '(?m)^\s*allow_without_tech\s*=\s*yes\s*$',
            '(?m)^\s*parent_version\s*=\s*0\s*$',
            '(?m)^\s*show_position\s*=\s*no\s*$',
            '(?m)^\s*obsolete\s*=\s*yes\s*$',
            '(?m)^\s*mark_older_equipment_obsolete\s*=\s*yes\s*$',
            '(?m)^\s*icon\s*=\s*"GFX_coi_alien_tic_tac_convoy_medium"\s*$'
        )) {
            if ([regex]::Matches($reserveVariantBlocks[0], $variantPattern).Count -ne 1) {
                Add-Failure "Tic Tac expeditionary reserve variant is missing or duplicates pattern: $variantPattern"
            }
        }
    }
    $reserveStockBlocks = @(Get-ClausewitzAssignedBlocks -Text $ticTacReserveBlock -Assignment 'add_equipment_to_stockpile')
    if ($reserveStockBlocks.Count -ne 1) {
        Add-Failure "Tic Tac reserve initializer must contain exactly one stockpile grant; found $($reserveStockBlocks.Count)."
    }
    elseif ([regex]::Matches($reserveStockBlocks[0], '(?m)^\s*type\s*=\s*convoy_1\s*$').Count -ne 1) {
        Add-Failure 'The Tic Tac reserve stockpile must select the sole supported convoy_1 equipment type.'
    }
    $performanceIdeaIndex = $ticTacReserveBlock.IndexOf('add_ideas = coi_alien_tic_tac_transit_envelope', [StringComparison]::Ordinal)
    $variantIndex = $ticTacReserveBlock.IndexOf('create_equipment_variant', [StringComparison]::Ordinal)
    $stockIndex = $ticTacReserveBlock.IndexOf('add_equipment_to_stockpile', [StringComparison]::Ordinal)
    $flagIndex = $ticTacReserveBlock.IndexOf('set_country_flag = coi_alien_tic_tac_reserve_stocked', [StringComparison]::Ordinal)
    if ($performanceIdeaIndex -lt 0 -or $variantIndex -le $performanceIdeaIndex -or $stockIndex -le $variantIndex -or $flagIndex -le $stockIndex) {
        Add-Failure 'Tic Tac reserve must apply the XAC transit envelope, register its named convoy_1 variant, stock 100 of it, then commit the idempotence flag.'
    }
}

$ticTacUnlockEffect = 'coi_alien_unlock_tic_tac_fabrication_effect'
$ticTacFabricationFlag = 'coi_alien_tic_tac_fabrication_registered'
$ticTacTransitIdea = 'coi_alien_tic_tac_transit_envelope'
$ticTacUnlockBlocks = @(Get-ClausewitzAssignedBlocks -Text $navalEffectText -Assignment $ticTacUnlockEffect)
if ($ticTacUnlockBlocks.Count -ne 1) {
    Add-Failure "Tic Tac fabrication unlock effect must be defined exactly once; found $($ticTacUnlockBlocks.Count)."
}
else {
    $ticTacUnlockBlock = $ticTacUnlockBlocks[0]
    foreach ($unlockPattern in @(
        '(?m)^\s*original_tag\s*=\s*XAC\s*$',
        '(?m)^\s*has_tech\s*=\s*coi_alien_tic_tac_fabrication\s*$',
        '(?m)^\s*has_idea\s*=\s*coi_alien_mothership_anchorage_online\s*$',
        '(?m)^\s*NOT\s*=\s*\{\s*has_country_flag\s*=\s*coi_alien_tic_tac_fabrication_registered\s*\}\s*$',
        '(?m)^\s*has_design_based_on\s*=\s*convoy\s*$',
        '(?m)^\s*set_country_flag\s*=\s*coi_alien_tic_tac_fabrication_registered\s*$'
    )) {
        if ([regex]::Matches($ticTacUnlockBlock, $unlockPattern).Count -ne 1) {
            Add-Failure "Tic Tac fabrication registration is missing or duplicates pattern: $unlockPattern"
        }
    }
    $productionVariantBlocks = @(Get-ClausewitzAssignedBlocks -Text $ticTacUnlockBlock -Assignment 'create_equipment_variant')
    if ($productionVariantBlocks.Count -ne 1) {
        Add-Failure "Tic Tac fabrication unlock must register exactly one production variant; found $($productionVariantBlocks.Count)."
    }
    else {
        foreach ($variantPattern in @(
            '(?m)^\s*name\s*=\s*"Tic Tac"\s*$',
            '(?m)^\s*type\s*=\s*convoy_1\s*$',
            '(?m)^\s*allow_without_tech\s*=\s*yes\s*$',
            '(?m)^\s*parent_version\s*=\s*0\s*$',
            '(?m)^\s*show_position\s*=\s*no\s*$',
            '(?m)^\s*obsolete\s*=\s*no\s*$',
            '(?m)^\s*mark_older_equipment_obsolete\s*=\s*yes\s*$',
            '(?m)^\s*icon\s*=\s*"GFX_coi_alien_tic_tac_convoy_medium"\s*$'
        )) {
            if ([regex]::Matches($productionVariantBlocks[0], $variantPattern).Count -ne 1) {
                Add-Failure "Tic Tac production variant is missing or duplicates pattern: $variantPattern"
            }
        }
    }
    $productionVariantIndex = $ticTacUnlockBlock.IndexOf('create_equipment_variant', [StringComparison]::Ordinal)
    $productionVerificationIndex = $ticTacUnlockBlock.IndexOf('has_design_based_on = convoy', [StringComparison]::Ordinal)
    $fabricationFlagIndex = $ticTacUnlockBlock.IndexOf('set_country_flag = coi_alien_tic_tac_fabrication_registered', [StringComparison]::Ordinal)
    if ($productionVariantIndex -lt 0 -or $productionVerificationIndex -le $productionVariantIndex -or $fabricationFlagIndex -le $productionVerificationIndex) {
        Add-Failure 'Tic Tac fabrication must register the convoy_1 production variant, verify that it is buildable, then commit the registration flag.'
    }
}

if ($countryHistoryText -match '(?m)^\s*set_convoys\s*=') {
    Add-Failure 'XAC country history must not retain a generic set_convoys grant after Tic Tac migration.'
}
$awarenessOnActionText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\on_actions\coi_alien_awareness_on_actions.txt'))
foreach ($hookContract in @(
    [pscustomobject]@{ Hook = 'on_startup'; Calls = 1 },
    [pscustomobject]@{ Hook = 'on_daily_XAC'; Calls = 1 }
)) {
    $hookBlocks = @(Get-ClausewitzAssignedBlocks -Text $awarenessOnActionText -Assignment $hookContract.Hook)
    if ($hookBlocks.Count -ne 1) {
        Add-Failure "Tic Tac migration hook $($hookContract.Hook) must be defined exactly once."
        continue
    }
    $callPattern = '(?m)^\s*' + [regex]::Escape($ticTacInitializer) + '\s*=\s*yes\s*$'
    if ([regex]::Matches($hookBlocks[0], $callPattern).Count -ne $hookContract.Calls) {
        Add-Failure "Tic Tac reserve initializer must be called exactly once by $($hookContract.Hook)."
    }
}
if ([regex]::Matches($awarenessOnActionText, '(?m)^\s*coi_alien_initialize_tic_tac_reserve_effect\s*=\s*yes\s*$').Count -ne 2) {
    Add-Failure 'Tic Tac reserve initializer must have only the startup and tag-scoped daily migration calls.'
}
$dailyXacBlocks = @(Get-ClausewitzAssignedBlocks -Text $awarenessOnActionText -Assignment 'on_daily_XAC')
if ($dailyXacBlocks.Count -eq 1 -and
    [regex]::Matches($dailyXacBlocks[0], '(?m)^\s*coi_alien_unlock_tic_tac_fabrication_effect\s*=\s*yes\s*$').Count -ne 1) {
    Add-Failure 'The XAC-scoped daily reconciliation must invoke Tic Tac fabrication registration exactly once.'
}
$startupTicTacIndex = $awarenessOnActionText.IndexOf('coi_alien_initialize_tic_tac_reserve_effect = yes', [StringComparison]::Ordinal)
$startupAnchorageIndex = $awarenessOnActionText.IndexOf('coi_alien_activate_mothership_anchorage = yes', [StringComparison]::Ordinal)
if ($startupAnchorageIndex -lt 0 -or $startupTicTacIndex -le $startupAnchorageIndex) {
    Add-Failure 'Fresh-start Tic Tac reserve initialization must run after Mothership Anchorage activation.'
}
$allModClausewitzText = ($clausewitzFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
if ([regex]::Matches($allModClausewitzText, '(?m)^\s*set_country_flag\s*=\s*coi_alien_tic_tac_reserve_stocked\s*$').Count -ne 1) {
    Add-Failure 'The Tic Tac reserve flag must have exactly one setter across the mod.'
}
if ([regex]::Matches($allModClausewitzText, '(?m)^\s*set_country_flag\s*=\s*coi_alien_tic_tac_fabrication_registered\s*$').Count -ne 1) {
    Add-Failure 'The Tic Tac fabrication-registration flag must have exactly one setter across the mod.'
}
if ([regex]::Matches($alienStarterTechnologyText, '\bcoi_alien_unlock_tic_tac_fabrication_effect\s*=\s*yes\b').Count -ne 1) {
    Add-Failure 'The Tic Tac research node must invoke fabrication registration exactly once.'
}
if ([regex]::Matches($allModClausewitzText, '(?m)^\s*coi_alien_tic_tac_fabrication\s*=\s*1\s*$').Count -ne 0) {
    Add-Failure 'Tic Tac Fabrication Lattice must be researched normally and never script-granted.'
}

$navalIdeaText = [IO.File]::ReadAllText((Join-Path $modRoot 'common\ideas\coi_alien_naval_ideas.txt'))
$ticTacTransitIdeaBlocks = @(Get-ClausewitzAssignedBlocks -Text $navalIdeaText -Assignment $ticTacTransitIdea)
if ($ticTacTransitIdeaBlocks.Count -ne 1) {
    Add-Failure "XAC Tic Tac transit-envelope idea must be defined exactly once; found $($ticTacTransitIdeaBlocks.Count)."
}
else {
    $ticTacTransitIdeaBlock = $ticTacTransitIdeaBlocks[0]
    foreach ($ideaPattern in @(
        '(?m)^\s*original_tag\s*=\s*XAC\s*$',
        '(?m)^\s*removal_cost\s*=\s*-1\s*$'
    )) {
        if ([regex]::Matches($ticTacTransitIdeaBlock, $ideaPattern).Count -ne 1) {
            Add-Failure "Tic Tac transit-envelope isolation is missing or duplicates pattern: $ideaPattern"
        }
    }
    if ($ticTacTransitIdeaBlock -match '(?m)^\s*visible\s*=') {
        Add-Failure 'Tic Tac transit envelope must remain visible once active; a false visible block causes HOI4 to discard the idea and its equipment bonuses.'
    }
    $ticTacEquipmentBonusBlocks = @(Get-ClausewitzAssignedBlocks -Text $ticTacTransitIdeaBlock -Assignment 'equipment_bonus')
    if ($ticTacEquipmentBonusBlocks.Count -ne 1) {
        Add-Failure "Tic Tac transit envelope must contain exactly one equipment_bonus block; found $($ticTacEquipmentBonusBlocks.Count)."
    }
    else {
        $ticTacConvoyBonusBlocks = @(Get-ClausewitzAssignedBlocks -Text $ticTacEquipmentBonusBlocks[0] -Assignment 'convoy_1')
        if ($ticTacConvoyBonusBlocks.Count -ne 1) {
            Add-Failure "Tic Tac transit envelope must target the sole convoy_1 equipment type exactly once; found $($ticTacConvoyBonusBlocks.Count)."
        }
        else {
            foreach ($bonusPattern in @(
                '(?m)^\s*instant\s*=\s*yes\s*$',
                '(?m)^\s*naval_speed\s*=\s*4\s*$',
                '(?m)^\s*surface_visibility\s*=\s*-0\.928571\s*$',
                '(?m)^\s*reliability\s*=\s*0\.2375\s*$',
                '(?m)^\s*max_strength\s*=\s*9\s*$',
                '(?m)^\s*max_organisation\s*=\s*70\s*$',
                '(?m)^\s*anti_air_attack\s*=\s*149\s*$',
                '(?m)^\s*lg_attack\s*=\s*7\s*$',
                '(?m)^\s*lg_armor_piercing\s*=\s*19\s*$',
                '(?m)^\s*build_cost_ic\s*=\s*4\s*$'
            )) {
                if ([regex]::Matches($ticTacConvoyBonusBlocks[0], $bonusPattern).Count -ne 1) {
                    Add-Failure "Tic Tac convoy_1 performance envelope is missing or duplicates required bonus: $bonusPattern"
                }
            }
        }
    }
}

$ticTacEquipmentTexture = 'gfx/interface/coi_alien/coi_alien_tic_tac_convoy.dds'
$ticTacTechnologyTexture = 'gfx/interface/coi_alien/coi_alien_tech_tic_tac_fabrication.dds'
$ticTacCombatTexture = 'gfx/interface/navalcombat/ships/coi_alien_tic_tac_convoy.dds'
Test-DdsArgbContract -RelativePath $ticTacEquipmentTexture -Width 146 -Height 54
Test-DdsArgbContract -RelativePath $ticTacTechnologyTexture -Width 64 -Height 64
Test-DdsArgbContract -RelativePath $ticTacCombatTexture -Width 104 -Height 17
Test-DdsHorizontalFramesDiffer -RelativePath $ticTacCombatTexture -Width 104 -Height 17
Test-GfxSpriteContract `
    -Text $navalGfxText `
    -Name 'GFX_coi_alien_tic_tac_convoy_medium' `
    -Texture $ticTacEquipmentTexture
Test-GfxSpriteContract `
    -Text $alienTechnologyGfxText `
    -Name 'GFX_coi_alien_tic_tac_fabrication_medium' `
    -Texture $ticTacTechnologyTexture
foreach ($ticTacCombatSprite in @(
    'GFX_navalcombat_ship_icon_coi_alien_tic_tac_convoy',
    'GFX_unit_coi_alien_tic_tac_convoy_icon_medium'
)) {
    Test-GfxSpriteContract `
        -Text $navalGfxText `
        -Name $ticTacCombatSprite `
        -Texture $ticTacCombatTexture `
        -Frames 2
}

foreach ($localisationContract in @(
    [pscustomobject]@{ Key = 'coi_alien_tic_tac_convoy'; Value = 'Tic Tac Logistics Pattern' },
    [pscustomobject]@{ Key = 'coi_alien_tic_tac_convoy_short'; Value = 'Tic Tac' },
    [pscustomobject]@{ Key = 'coi_alien_tic_tac_fabrication'; Value = 'Tic Tac Fabrication Lattice' },
    [pscustomobject]@{ Key = 'coi_alien_tic_tac_transit_envelope'; Value = 'Tic Tac Transit Envelope' }
)) {
    $localisationPattern = '(?m)^\s*' + [regex]::Escape($localisationContract.Key) + ':\s*"' + [regex]::Escape($localisationContract.Value) + '"\s*$'
    if ([regex]::Matches($allEnglishLocalisationText, $localisationPattern).Count -ne 1) {
        Add-Failure "Missing or malformed Tic Tac localisation: $($localisationContract.Key)"
    }
}
foreach ($ticTacLocalisationKey in @(
    'coi_alien_tic_tac_convoy_desc',
    'coi_alien_tic_tac_fabrication_desc',
    'coi_alien_tic_tac_transit_envelope_desc'
)) {
    if (-not $localisationKeys.ContainsKey($ticTacLocalisationKey)) {
        Add-Failure "Missing English Tic Tac localisation key $ticTacLocalisationKey."
    }
}

$ticTacMasterPath = Join-Path $ProjectRoot 'Source\Art\Masters\coi_alien_tic_tac_convoy.png'
if (-not (Test-Path -LiteralPath $ticTacMasterPath -PathType Leaf)) {
    Add-Failure "Missing Tic Tac ImageGen master: $ticTacMasterPath"
}
else {
    $ticTacMasterBytes = [IO.File]::ReadAllBytes($ticTacMasterPath)
    if ($ticTacMasterBytes.Length -lt 33 -or
        $ticTacMasterBytes[0] -ne 0x89 -or $ticTacMasterBytes[1] -ne 0x50 -or
        $ticTacMasterBytes[2] -ne 0x4E -or $ticTacMasterBytes[3] -ne 0x47 -or
        $ticTacMasterBytes[24] -ne 8 -or $ticTacMasterBytes[25] -ne 6) {
        Add-Failure 'coi_alien_tic_tac_convoy.png must remain an 8-bit RGBA PNG ImageGen master.'
    }
    else {
        $ticTacMasterWidth = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($ticTacMasterBytes, 16))
        $ticTacMasterHeight = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($ticTacMasterBytes, 20))
        if ($ticTacMasterWidth -lt 1024 -or $ticTacMasterHeight -lt 512) {
            Add-Failure "Tic Tac ImageGen master is ${ticTacMasterWidth}x${ticTacMasterHeight}; retain at least a 1024x512 landscape source."
        }
        $ticTacMasterBitmap = $null
        try {
            $ticTacMasterBitmap = [System.Drawing.Bitmap]::new($ticTacMasterPath)
            $cornerAlphas = @(
                $ticTacMasterBitmap.GetPixel(0, 0).A,
                $ticTacMasterBitmap.GetPixel($ticTacMasterBitmap.Width - 1, 0).A,
                $ticTacMasterBitmap.GetPixel(0, $ticTacMasterBitmap.Height - 1).A,
                $ticTacMasterBitmap.GetPixel($ticTacMasterBitmap.Width - 1, $ticTacMasterBitmap.Height - 1).A
            )
            if (@($cornerAlphas | Where-Object { $_ -gt 1 }).Count -ne 0) {
                Add-Failure 'Tic Tac ImageGen master must retain transparent alpha at all four canvas corners.'
            }
        }
        catch {
            Add-Failure "Could not decode Tic Tac ImageGen master: $($_.Exception.Message)"
        }
        finally {
            if ($null -ne $ticTacMasterBitmap) {
                $ticTacMasterBitmap.Dispose()
            }
        }
    }
}

$ticTacProvenancePath = Join-Path $ProjectRoot 'Source\Art\tic_tac_convoy_imagegen_prompt.md'
if (-not (Test-Path -LiteralPath $ticTacProvenancePath -PathType Leaf)) {
    Add-Failure "Missing Tic Tac ImageGen prompt provenance: $ticTacProvenancePath"
}
else {
    $ticTacProvenanceText = [IO.File]::ReadAllText($ticTacProvenancePath)
    foreach ($provenancePattern in @(
        'coi_alien_tic_tac_convoy\.png',
        'built-in ImageGen',
        'stylized-concept',
        'No CLI image model was used',
        'actual transparent background',
        '146.{1,2}54',
        '64.{1,2}64',
        '104.{1,2}17'
    )) {
        if ([regex]::Matches($ticTacProvenanceText, $provenancePattern, 'IgnoreCase').Count -lt 1) {
            Add-Failure "Tic Tac ImageGen provenance is missing required record: $provenancePattern"
        }
    }
}

$artBuilderText = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'Source\Build-ArtAssets.ps1'))
foreach ($builderPattern in @(
    '\$ticTacMaster\s*=\s*Join-Path\s+\$masterRoot\s+"coi_alien_tic_tac_convoy\.png"',
    '(?s)\$ticTacEquipment\s*=\s*New-TrimmedRenderedBitmap.*?-Width\s+146.*?-Height\s+54.*?coi_alien_tic_tac_convoy\.dds',
    '(?s)\$ticTacTechnology\s*=\s*New-TrimmedRenderedBitmap.*?-Width\s+64.*?-Height\s+64.*?coi_alien_tech_tic_tac_fabrication\.dds',
    '(?s)\$ticTacCombatStrip\s*=\s*New-MirroredShipStrip.*?-FrameWidth\s+52.*?-Height\s+17.*?coi_alien_tic_tac_convoy\.dds'
)) {
    if ([regex]::Matches($artBuilderText, $builderPattern).Count -ne 1) {
        Add-Failure "Tic Tac art builder is missing or duplicates reproducibility pattern: $builderPattern"
    }
}

foreach ($vanillaEquipmentId in @('convoy', 'convoy_1')) {
    $vanillaDefinitionPattern = '(?m)^\s*' + [regex]::Escape($vanillaEquipmentId) + '\s*=\s*\{\s*$'
    if ([regex]::Matches($equipmentDirectoryText, $vanillaDefinitionPattern).Count -ne 0) {
        Add-Failure "The mergeable mod must not redefine global vanilla equipment $vanillaEquipmentId."
    }
}
foreach ($globalConvoySprite in @(
    'GFX_archetype_convoy_medium',
    'GFX_convoy_medium',
    'GFX_convoy_texticon',
    'GFX_navalcombat_ship_icon_convoy',
    'GFX_unit_convoy_1_icon_medium',
    'GFX_unit_convoy_icon_medium_black'
)) {
    $globalConvoySpritePattern = '(?m)^\s*name\s*=\s*"' + [regex]::Escape($globalConvoySprite) + '"\s*$'
    if ([regex]::Matches($allInterfaceGfxText, $globalConvoySpritePattern).Count -ne 0) {
        Add-Failure "Tic Tac UI must not override global human convoy sprite $globalConvoySprite."
    }
}
foreach ($vanillaTexturePath in @(
    'gfx\interface\archetypes\archetype_convoy.dds',
    'gfx\interface\navalcombat\ships\convoy.dds',
    'gfx\interface\counters\ships_small\onmap_transport_inverted.dds'
)) {
    if (Test-Path -LiteralPath (Join-Path $modRoot $vanillaTexturePath)) {
        Add-Failure "Tic Tac art must not replace global human texture $vanillaTexturePath."
    }
}

Add-Pass 'Validated the sole convoy_1 architecture and absence of the engine-rejected second Tic Tac equipment type'
Add-Pass 'Validated 1938 Tic Tac Fabrication Lattice research path, country-variant registration, UI placement, AI weight, and no script grant'
Add-Pass 'Validated named fresh-start and old-save 100-craft convoy_1 reserve migration with post-grant idempotence'
Add-Pass 'Validated XAC-only convoy_1 equipment bonuses and production-variant registration order'
Add-Pass 'Validated live Tic Tac research art plus namespaced equipment/concept and staged mirrored combat assets with ImageGen provenance'
Add-Pass 'Validated preservation of vanilla convoy definitions, sprites, textures, recipe, transfer behavior, counters, and shared 3D presentation'

Add-Pass "Validated XAC tag, country history, alien naval unit contracts, and exact 1+4 OOB"
Add-Pass "Validated three folderless script-granted alien helper technologies"
Add-Pass "Validated four XAC-only research branches, their equipment upgrades, and upgraded AI ship designs"
Add-Pass "Validated the hash-pinned HOI4 1.19.2.0 Consensus Sciences folder and tab"

### v0.4.0 discovery, recovery, reverse-engineering, and catastrophic-disclosure
### release contracts. These checks intentionally validate authored transitions
### and integration seams rather than duplicating every line of implementation.
function Test-ContractPattern {
	param(
		[Parameter(Mandatory)] [string]$Text,
		[Parameter(Mandatory)] [string]$Pattern,
		[Parameter(Mandatory)] [string]$Label,
		[int]$ExpectedCount = 1
	)

	$count = [regex]::Matches($Text, $Pattern).Count
	if ($count -ne $ExpectedCount) {
		Add-Failure "$Label must appear exactly $ExpectedCount time(s); found $count."
	}
}

function Get-TopLevelContractBlocks {
	param(
		[Parameter(Mandatory)] [string]$Text,
		[Parameter(Mandatory)] [string]$Assignment
	)

	# Get-ClausewitzAssignedBlocks deliberately accepts indentation and its
	# leading \s* may retain blank lines. Inspect the assignment line itself so
	# a blank line before a top-level block is not mistaken for indentation.
	$topLevelPattern = '(?m)^([ \t]*)' + [regex]::Escape($Assignment) + '[ \t]*='
	return @(Get-ClausewitzAssignedBlocks -Text $Text -Assignment $Assignment | Where-Object {
		$assignmentLine = [regex]::Match($_, $topLevelPattern)
		$assignmentLine.Success -and $assignmentLine.Groups[1].Length -eq 0
	})
}

function Get-UniqueTopLevelEventBlock {
	param(
		[Parameter(Mandatory)] [string]$Text,
		[Parameter(Mandatory)] [ValidateSet('country_event', 'news_event')] [string]$Type,
		[Parameter(Mandatory)] [string]$Id,
		[Parameter(Mandatory)] [string]$Label
	)

	$idPattern = '(?m)^\s*id\s*=\s*' + [regex]::Escape($Id) + '\s*$'
	$blocks = @(Get-TopLevelContractBlocks -Text $Text -Assignment $Type | Where-Object {
		$_ -match $idPattern
	})
	if ($blocks.Count -ne 1) {
		Add-Failure "$Label must define top-level $Type $Id exactly once; found $($blocks.Count)."
		return ''
	}
	return $blocks[0]
}

$discoveryEffectText = Get-RequiredModText 'common\scripted_effects\coi_alien_awareness_effects.txt'
$discoveryTriggerText = Get-RequiredModText 'common\scripted_triggers\coi_alien_awareness_triggers.txt'
$discoveryDecisionText = Get-RequiredModText 'common\decisions\coi_alien_awareness_decisions.txt'
$discoveryEventText = Get-RequiredModText 'events\coi_alien_discovery_events.txt'

$knowledgeInitializer = Get-UniqueContractBlock `
	-Text $discoveryEffectText `
	-Assignment 'coi_alien_initialize_country_awareness_effect' `
	-Label 'Classified-knowledge initialization'
$discoveryInitializer = Get-UniqueContractBlock `
	-Text $discoveryEffectText `
	-Assignment 'coi_alien_initialize_country_discovery_effect' `
	-Label 'Three-track discovery initialization'

$trackContracts = @(
	[pscustomobject]@{
		Variable = 'coi_alien_awareness'
		Initializer = $knowledgeInitializer
		Transitions = @(
			@('coi_alien_raise_knowledge_to_anomalous_reports_effect', 1),
			@('coi_alien_raise_knowledge_to_correlated_pattern_effect', 2),
			@('coi_alien_raise_knowledge_to_classified_confirmation_effect', 3),
			@('coi_alien_raise_knowledge_to_material_proof_effect', 4)
		)
	},
	[pscustomobject]@{
		Variable = 'coi_alien_public_awareness'
		Initializer = $discoveryInitializer
		Transitions = @(
			@('coi_alien_raise_public_awareness_to_rumors_effect', 1),
			@('coi_alien_raise_public_awareness_to_credible_controversy_effect', 2),
			@('coi_alien_raise_public_awareness_to_official_acknowledgment_effect', 3),
			@('coi_alien_raise_public_awareness_to_undeniable_contact_effect', 4)
		)
	},
	[pscustomobject]@{
		Variable = 'coi_alien_preparedness'
		Initializer = $discoveryInitializer
		Transitions = @(
			@('coi_alien_raise_preparedness_to_quiet_monitoring_effect', 1),
			@('coi_alien_raise_preparedness_to_contingency_planning_effect', 2),
			@('coi_alien_raise_preparedness_to_national_mobilization_effect', 3),
			@('coi_alien_raise_preparedness_to_crisis_war_footing_effect', 4)
		)
	}
)

foreach ($track in $trackContracts) {
	$variablePattern = [regex]::Escape($track.Variable)
	Test-ContractPattern `
		-Text $track.Initializer `
		-Pattern ('(?m)^\s*clamp_variable\s*=\s*\{\s*var\s*=\s*' + $variablePattern + '\s+min\s*=\s*0\s+max\s*=\s*4\s*\}\s*$') `
		-Label "$($track.Variable) 0-4 initialization clamp"

	foreach ($transition in $track.Transitions) {
		$effectId = [string]$transition[0]
		$stage = [int]$transition[1]
		$transitionBlock = Get-UniqueContractBlock `
			-Text $discoveryEffectText `
			-Assignment $effectId `
			-Label "$($track.Variable) monotonic transitions"
		Test-ContractPattern `
			-Text $transitionBlock `
			-Pattern ('(?m)^\s*limit\s*=\s*\{\s*check_variable\s*=\s*\{\s*' + $variablePattern + '\s*<\s*' + $stage + '\s*\}\s*\}\s*$') `
			-Label "$effectId lower-stage guard"
		Test-ContractPattern `
			-Text $transitionBlock `
			-Pattern ('(?m)^\s*set_variable\s*=\s*\{\s*' + $variablePattern + '\s*=\s*' + $stage + '\s*\}\s*$') `
			-Label "$effectId exact stage assignment"
	}
}

$allScriptedEffectText = (Get-ChildItem -LiteralPath (Join-Path $modRoot 'common\scripted_effects') -File -Filter '*.txt' |
	ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
foreach ($variable in @('coi_alien_awareness', 'coi_alien_public_awareness', 'coi_alien_preparedness')) {
	$variablePattern = [regex]::Escape($variable)
	if ($allScriptedEffectText -match ('(?m)^\s*subtract_from_variable\s*=\s*\{\s*' + $variablePattern + '\s*=') -or
		$allScriptedEffectText -match ('(?m)^\s*add_to_variable\s*=\s*\{\s*' + $variablePattern + '\s*=\s*-')) {
		Add-Failure "$variable has a decreasing gameplay mutation; all three discovery tracks must be monotonic."
	}
}
Add-Pass 'Validated the exact monotonic 0-4 classified-knowledge, public-awareness, and preparedness tracks'

$stanceContracts = @(
	[pscustomobject]@{
		Choose = 'coi_alien_choose_black_archive'; Pivot = 'coi_alien_pivot_to_black_archive'
		Adopt = 'coi_alien_adopt_secrecy_stance_effect'; Flag = 'coi_alien_disclosure_stance_secrecy'
		Idea = 'coi_alien_disclosure_black_archive'; Weight = 80
	},
	[pscustomobject]@{
		Choose = 'coi_alien_choose_prepared_public'; Pivot = 'coi_alien_pivot_to_prepared_public'
		Adopt = 'coi_alien_adopt_managed_disclosure_stance_effect'; Flag = 'coi_alien_disclosure_stance_managed'
		Idea = 'coi_alien_disclosure_prepared_public'; Weight = 8
	},
	[pscustomobject]@{
		Choose = 'coi_alien_choose_world_must_know'; Pivot = 'coi_alien_pivot_to_world_must_know'
		Adopt = 'coi_alien_adopt_international_disclosure_stance_effect'; Flag = 'coi_alien_disclosure_stance_international'
		Idea = 'coi_alien_disclosure_international_council'; Weight = 8
	},
	[pscustomobject]@{
		Choose = 'coi_alien_choose_open_files'; Pivot = 'coi_alien_pivot_to_open_files'
		Adopt = 'coi_alien_adopt_open_files_stance_effect'; Flag = 'coi_alien_disclosure_stance_open_files'
		Idea = 'coi_alien_disclosure_open_files'; Weight = 4
	}
)

$clearStanceBlock = Get-UniqueContractBlock `
	-Text $discoveryEffectText `
	-Assignment 'coi_alien_clear_disclosure_stance_effect' `
	-Label 'Disclosure stance exclusivity'
$aiStanceBlock = Get-UniqueContractBlock `
	-Text $discoveryEffectText `
	-Assignment 'coi_alien_choose_ai_disclosure_stance_effect' `
	-Label 'AI disclosure stance selection'
$aiStanceRandomBlocks = @(Get-ClausewitzAssignedBlocks -Text $aiStanceBlock -Assignment 'random_list')
if ($aiStanceRandomBlocks.Count -ne 1) {
	Add-Failure "AI disclosure stance selection must have one random_list; found $($aiStanceRandomBlocks.Count)."
}
else {
	$actualWeights = @([regex]::Matches($aiStanceRandomBlocks[0], '(?m)^\s*(\d+)\s*=\s*\{') |
		ForEach-Object { [int]$_.Groups[1].Value })
	if (($actualWeights -join ',') -cne '80,8,8,4') {
		Add-Failure "AI disclosure stance base weights are [$($actualWeights -join ',')]; expected exact 80,8,8,4."
	}
}

foreach ($stance in $stanceContracts) {
	Test-ContractPattern -Text $clearStanceBlock `
		-Pattern ('(?m)^\s*clr_country_flag\s*=\s*' + [regex]::Escape($stance.Flag) + '\s*$') `
		-Label "Clear $($stance.Flag)"
	Test-ContractPattern -Text $clearStanceBlock `
		-Pattern ('(?m)^\s*remove_ideas\s*=\s*' + [regex]::Escape($stance.Idea) + '\s*$') `
		-Label "Remove $($stance.Idea)"

	$adoptBlock = Get-UniqueContractBlock -Text $discoveryEffectText -Assignment $stance.Adopt -Label 'Disclosure stance adoption'
	foreach ($adoptPattern in @(
		'(?m)^\s*coi_alien_clear_disclosure_stance_effect\s*=\s*yes\s*$',
		('(?m)^\s*set_country_flag\s*=\s*' + [regex]::Escape($stance.Flag) + '\s*$'),
		('(?m)^\s*add_ideas\s*=\s*' + [regex]::Escape($stance.Idea) + '\s*$'),
		'(?m)^\s*coi_alien_start_disclosure_pivot_cooldown_effect\s*=\s*yes\s*$'
	)) {
		Test-ContractPattern -Text $adoptBlock -Pattern $adoptPattern -Label "$($stance.Adopt) contract"
	}
	Test-ContractPattern -Text $aiStanceBlock `
		-Pattern ('(?m)^\s*' + [regex]::Escape($stance.Adopt) + '\s*=\s*yes\s*$') `
		-Label "$($stance.Weight)-weight AI branch for $($stance.Adopt)"

	$chooseBlock = Get-UniqueContractBlock -Text $discoveryDecisionText -Assignment $stance.Choose -Label 'Initial disclosure decisions'
	Test-ContractPattern -Text $chooseBlock `
		-Pattern ('(?m)^\s*base\s*=\s*' + $stance.Weight + '\s*$') `
		-Label "$($stance.Choose) AI base weight"

	$pivotBlock = Get-UniqueContractBlock -Text $discoveryDecisionText -Assignment $stance.Pivot -Label 'Disclosure pivot decisions'
	Test-ContractPattern -Text $pivotBlock -Pattern '(?m)^\s*cost\s*=\s*100\s*$' -Label "$($stance.Pivot) 100 PP cost"
	Test-ContractPattern -Text $pivotBlock -Pattern '(?m)^\s*coi_alien_apply_disclosure_pivot_cost_effect\s*=\s*yes\s*$' -Label "$($stance.Pivot) stability cost"
	Test-ContractPattern -Text $pivotBlock `
		-Pattern ('(?m)^\s*' + [regex]::Escape($stance.Adopt) + '\s*=\s*yes\s*$') `
		-Label "$($stance.Pivot) stance transition"
}

$pivotCostBlock = Get-UniqueContractBlock -Text $discoveryEffectText -Assignment 'coi_alien_apply_disclosure_pivot_cost_effect' -Label 'Disclosure pivot stability cost'
Test-ContractPattern -Text $pivotCostBlock -Pattern '(?m)^\s*add_stability\s*=\s*-0\.05\s*$' -Label 'Disclosure pivot -5% stability cost'
$pivotCooldownBlock = Get-UniqueContractBlock -Text $discoveryEffectText -Assignment 'coi_alien_start_disclosure_pivot_cooldown_effect' -Label 'Disclosure pivot cooldown'
Test-ContractPattern -Text $pivotCooldownBlock -Pattern '(?m)^\s*flag\s*=\s*coi_alien_disclosure_pivot_cooldown\s*$' -Label 'Disclosure pivot cooldown flag'
Test-ContractPattern -Text $pivotCooldownBlock -Pattern '(?m)^\s*days\s*=\s*180\s*$' -Label 'Disclosure pivot 180-day cooldown'
Add-Pass 'Validated four exclusive disclosure stances, exact 80/8/8/4 AI weights, and 100 PP/-5 stability/180-day pivots'

$recoveryDecisionText = Get-RequiredModText 'common\decisions\coi_alien_recovery_decisions.txt'
$recoveryEffectText = Get-RequiredModText 'common\scripted_effects\coi_alien_recovery_effects.txt'
$recoveryTriggerText = Get-RequiredModText 'common\scripted_triggers\coi_alien_recovery_triggers.txt'
$recoveryEventText = Get-RequiredModText 'events\coi_alien_recovery_events.txt'
$recoveryLocalisationText = Get-RequiredModText 'localisation\english\coi_alien_recovery_l_english.yml'

Test-ContractPattern -Text $recoveryLocalisationText `
	-Pattern '(?m)^\s*coi_alien_attempt_craft_interception:\s*"Project NIGHT LANTERN"\s*$' `
	-Label 'Project NIGHT LANTERN display name'
$nightLanternBlock = Get-UniqueContractBlock -Text $recoveryDecisionText -Assignment 'coi_alien_attempt_craft_interception' -Label 'Project NIGHT LANTERN decision'
foreach ($nightLanternPattern in @(
	'(?m)^\s*days_remove\s*=\s*30\s*$',
	'(?m)^\s*add_command_power\s*=\s*-25\s*$',
	'(?m)^\s*set_country_flag\s*=\s*coi_alien_interception_program_active\s*$',
	'(?m)^\s*hidden_effect\s*=\s*\{\s*coi_alien_resolve_craft_interception_effect\s*=\s*yes\s*\}\s*$'
)) {
	Test-ContractPattern -Text $nightLanternBlock -Pattern $nightLanternPattern -Label 'Project NIGHT LANTERN decision contract'
}

$recoveryOutcomeContracts = @(
	[pscustomobject]@{ Effect = 'coi_alien_recovery_lost_contact_effect'; Weight = 50; Evidence = @('coi_alien_evidence_signals') },
	[pscustomobject]@{ Effect = 'coi_alien_recovery_fragments_effect'; Weight = 30; Evidence = @('coi_alien_evidence_signals', 'coi_alien_evidence_fragments') },
	[pscustomobject]@{ Effect = 'coi_alien_recovery_damaged_craft_effect'; Weight = 15; Evidence = @('coi_alien_evidence_signals', 'coi_alien_evidence_fragments', 'coi_alien_evidence_damaged_craft') },
	[pscustomobject]@{ Effect = 'coi_alien_recovery_public_crash_effect'; Weight = 5; Evidence = @('coi_alien_evidence_signals', 'coi_alien_evidence_fragments', 'coi_alien_evidence_damaged_craft') }
)
$resolveRecoveryBlock = Get-UniqueContractBlock -Text $recoveryEffectText -Assignment 'coi_alien_resolve_craft_interception_effect' -Label 'Project NIGHT LANTERN outcome resolution'
$recoveryRandomBlocks = @(Get-ClausewitzAssignedBlocks -Text $resolveRecoveryBlock -Assignment 'random_list')
if ($recoveryRandomBlocks.Count -ne 1) {
	Add-Failure "Project NIGHT LANTERN must define one outcome random_list; found $($recoveryRandomBlocks.Count)."
}
else {
	$actualRecoveryWeights = @([regex]::Matches($recoveryRandomBlocks[0], '(?m)^\s*(\d+)\s*=\s*\{') |
		ForEach-Object { [int]$_.Groups[1].Value })
	if (($actualRecoveryWeights -join ',') -cne '50,30,15,5') {
		Add-Failure "Project NIGHT LANTERN outcomes are [$($actualRecoveryWeights -join ',')]; expected exact 50,30,15,5."
	}
}
Test-ContractPattern -Text $resolveRecoveryBlock -Pattern '(?m)^\s*flag\s*=\s*coi_alien_interception_program_cooldown\s*$' -Label 'Project NIGHT LANTERN country cooldown flag'
Test-ContractPattern -Text $resolveRecoveryBlock -Pattern '(?m)^\s*days\s*=\s*365\s*$' -Label 'Project NIGHT LANTERN one-year country cooldown'
foreach ($outcome in $recoveryOutcomeContracts) {
	$outcomeBlock = Get-UniqueContractBlock -Text $recoveryEffectText -Assignment $outcome.Effect -Label 'Project NIGHT LANTERN evidence outcomes'
	Test-ContractPattern -Text $resolveRecoveryBlock `
		-Pattern ('(?m)^\s*' + [regex]::Escape($outcome.Effect) + '\s*=\s*yes\s*$') `
		-Label "$($outcome.Weight)-weight $($outcome.Effect) branch"
	foreach ($evidence in $outcome.Evidence) {
		Test-ContractPattern -Text $outcomeBlock `
			-Pattern ('(?m)^\s*set_country_flag\s*=\s*' + [regex]::Escape($evidence) + '\s*$') `
			-Label "$($outcome.Effect) evidence $evidence"
	}
}
foreach ($majorRecoveryEffect in @('coi_alien_recovery_damaged_craft_effect', 'coi_alien_recovery_public_crash_effect')) {
	$majorRecoveryBlock = Get-UniqueContractBlock -Text $recoveryEffectText -Assignment $majorRecoveryEffect -Label 'Major craft recovery cooldowns'
	Test-ContractPattern -Text $majorRecoveryBlock -Pattern '(?m)^\s*flag\s*=\s*coi_alien_major_recovery_global_cooldown\s*$' -Label "$majorRecoveryEffect global cooldown flag"
	Test-ContractPattern -Text $majorRecoveryBlock -Pattern '(?m)^\s*days\s*=\s*1825\s*$' -Label "$majorRecoveryEffect five-year global cooldown"
}
$publicCrashBlock = Get-UniqueContractBlock -Text $recoveryEffectText -Assignment 'coi_alien_recovery_public_crash_effect' -Label 'Public crash disclosure trigger'
Test-ContractPattern -Text $publicCrashBlock -Pattern '(?m)^\s*coi_alien_begin_catastrophic_disclosure_effect\s*=\s*yes\s*$' -Label 'Public crash catastrophic disclosure trigger'

$recoveryEchoBlock = Get-UniqueContractBlock -Text $recoveryTriggerText -Assignment 'coi_alien_1947_recovery_echo_trigger' -Label '1947 USA recovery echo'
foreach ($echoPattern in @(
	'(?m)^\s*tag\s*=\s*USA\s*$',
	'(?m)^\s*date\s*>\s*1947\.1\.1\s*$',
	'(?m)^\s*date\s*<\s*1948\.1\.1\s*$',
	'(?m)^\s*NOT\s*=\s*\{\s*has_global_flag\s*=\s*coi_alien_post_magenta_recovery_recorded\s*\}\s*$',
	'(?m)^\s*NOT\s*=\s*\{\s*has_global_flag\s*=\s*coi_alien_catastrophic_disclosure_active\s*\}\s*$'
)) {
	Test-ContractPattern -Text $recoveryEchoBlock -Pattern $echoPattern -Label '1947 USA recovery echo gate'
}
Test-ContractPattern -Text $resolveRecoveryBlock `
	-Pattern '(?ms)^\s*modifier\s*=\s*\{\s*factor\s*=\s*3\s+coi_alien_1947_recovery_echo_trigger\s*=\s*yes\s*\}' `
	-Label '1947 USA damaged-craft weight boost'
Test-ContractPattern -Text $resolveRecoveryBlock `
	-Pattern '(?ms)^\s*modifier\s*=\s*\{\s*factor\s*=\s*2\s+coi_alien_1947_recovery_echo_trigger\s*=\s*yes\s*\}' `
	-Label '1947 USA public-crash weight boost'
foreach ($eventId in 1..4) {
	[void](Get-UniqueTopLevelEventBlock -Text $recoveryEventText -Type 'country_event' -Id "coi_alien_recovery.$eventId" -Label 'Project NIGHT LANTERN outcome events')
}
Add-Pass 'Validated Project NIGHT LANTERN, exact 50/30/15/5 evidence outcomes, one-/five-year cooldowns, and the 1947 USA echo'

$catastrophicEffectText = Get-RequiredModText 'common\scripted_effects\coi_alien_catastrophic_disclosure_effects.txt'
$catastrophicTriggerText = Get-RequiredModText 'common\scripted_triggers\coi_alien_catastrophic_disclosure_triggers.txt'
$catastrophicDecisionText = Get-RequiredModText 'common\decisions\coi_alien_catastrophic_disclosure_decisions.txt'
$catastrophicEventText = Get-RequiredModText 'events\coi_alien_catastrophic_disclosure_events.txt'
$catastrophicOnActionText = Get-RequiredModText 'common\on_actions\coi_alien_catastrophic_disclosure_on_actions.txt'

$beginDisclosureBlock = Get-UniqueContractBlock -Text $catastrophicEffectText -Assignment 'coi_alien_begin_catastrophic_disclosure_effect' -Label 'Catastrophic disclosure wave launcher'
foreach ($globalFlag in @('coi_alien_catastrophic_disclosure_active', 'coi_alien_disclosure_active')) {
	Test-ContractPattern -Text $beginDisclosureBlock `
		-Pattern ('(?m)^\s*set_global_flag\s*=\s*' + [regex]::Escape($globalFlag) + '\s*$') `
		-Label "Catastrophic dual global flag $globalFlag"
}

$worldWaveScopes = @(Get-ClausewitzAssignedBlocks -Text $beginDisclosureBlock -Assignment 'every_country' | Where-Object {
	$_ -match '\bcoi_alien_catastrophic_disclosure\.10\b'
})
if ($worldWaveScopes.Count -ne 1) {
	Add-Failure "Catastrophic disclosure must define one every-country world-wave scope; found $($worldWaveScopes.Count)."
}
else {
	$waveScope = $worldWaveScopes[0]
	Test-ContractPattern -Text $waveScope `
		-Pattern '(?ms)^\s*limit\s*=\s*\{\s*exists\s*=\s*yes\s+NOT\s*=\s*\{\s*tag\s*=\s*XAC\s*\}\s*\}\s*$' `
		-Label 'Every surviving terrestrial country wave scope'
	$waveSchedules = @(
		@('10', 'hours', '1'),
		@('11', 'days', '14'),
		@('12', 'days', '30'),
		@('13', 'days', '60'),
		@('14', 'days', '90')
	)
	foreach ($schedule in $waveSchedules) {
		Test-ContractPattern -Text $waveScope `
			-Pattern ('(?m)^\s*country_event\s*=\s*\{\s*id\s*=\s*coi_alien_catastrophic_disclosure\.' + $schedule[0] + '\s+' + $schedule[1] + '\s*=\s*' + $schedule[2] + '\s*\}\s*$') `
			-Label "Catastrophic day-$($schedule[2]) wave event .$($schedule[0])"
	}
	Test-ContractPattern -Text $waveScope `
		-Pattern '(?m)^\s*country_event\s*=\s*\{\s*id\s*=\s*coi_alien_catastrophic_disclosure\.99\s+days\s*=\s*90\s*\}\s*$' `
		-Label 'Redundant every-country day-90 sentinel schedule'
}
$legacyXacSentinelScopes = @(Get-ClausewitzAssignedBlocks -Text $beginDisclosureBlock -Assignment 'XAC' | Where-Object {
	$_ -match '\bcoi_alien_catastrophic_disclosure\.99\b'
})
if ($legacyXacSentinelScopes.Count -ne 0) {
	Add-Failure 'The .99 day-90 sentinel must not depend on XAC surviving to execute.'
}

foreach ($eventSuffix in @('10', '11', '12', '13', '14')) {
	[void](Get-UniqueTopLevelEventBlock -Text $catastrophicEventText -Type 'country_event' -Id "coi_alien_catastrophic_disclosure.$eventSuffix" -Label 'Catastrophic 0/14/30/60/90 wave events')
}
$sentinelEventBlock = Get-UniqueTopLevelEventBlock -Text $catastrophicEventText -Type 'country_event' -Id 'coi_alien_catastrophic_disclosure.99' -Label 'Catastrophic day-90 sentinel event'
foreach ($sentinelPattern in @(
	'(?m)^\s*hidden\s*=\s*yes\s*$',
	'(?m)^\s*is_triggered_only\s*=\s*yes\s*$',
	'(?m)^\s*immediate\s*=\s*\{\s*set_global_flag\s*=\s*coi_alien_catastrophic_wave_complete\s*\}\s*$'
)) {
	Test-ContractPattern -Text $sentinelEventBlock -Pattern $sentinelPattern -Label 'Catastrophic day-90 sentinel contract'
}
if ([regex]::Matches($sentinelEventBlock, '(?m)^\s*trigger\s*=').Count -ne 0) {
	Add-Failure 'The redundant .99 sentinel event must remain unfiltered for every queued terrestrial host.'
}

$responseDecisionIds = @(
	'coi_alien_address_the_nation',
	'coi_alien_open_emergency_shelters',
	'coi_alien_empower_scientific_authority',
	'coi_alien_activate_military_continuity',
	'coi_alien_expose_the_cover_up',
	'coi_alien_coordinate_international_aid'
)
foreach ($responseDecisionId in $responseDecisionIds) {
	$responseBlock = Get-UniqueContractBlock -Text $catastrophicDecisionText -Assignment $responseDecisionId -Label 'Catastrophic response decisions'
	Test-ContractPattern -Text $responseBlock -Pattern '(?m)^\s*coi_alien_catastrophic_crisis_active_trigger\s*=\s*yes\s*$' -Label "$responseDecisionId crisis gate"
}
if ([regex]::Matches($catastrophicDecisionText, '(?m)^\s*coi_alien_catastrophic_crisis_active_trigger\s*=\s*yes\s*$').Count -ne 6) {
	Add-Failure 'The catastrophic-disclosure category must expose exactly six crisis-response decisions.'
}

$applyCatastropheBlock = Get-UniqueContractBlock -Text $catastrophicEffectText -Assignment 'coi_alien_apply_catastrophic_disclosure_to_country_effect' -Label 'Country catastrophic-disclosure application'
Test-ContractPattern -Text $applyCatastropheBlock `
	-Pattern '(?m)^\s*country_event\s*=\s*\{\s*id\s*=\s*coi_alien_catastrophic_disclosure\.90\s+days\s*=\s*180\s*\}\s*$' `
	-Label 'Catastrophic 180-day national resolution schedule'
$resolutionEventBlock = Get-UniqueTopLevelEventBlock -Text $catastrophicEventText -Type 'country_event' -Id 'coi_alien_catastrophic_disclosure.90' -Label 'Catastrophic 180-day resolution event'
foreach ($resolutionPattern in @(
	'(?m)^\s*trigger\s*=\s*\{\s*check_variable\s*=\s*\{\s*coi_alien_crisis_score\s*<\s*41\s*\}\s*\}\s*$',
	'(?m)^\s*check_variable\s*=\s*\{\s*coi_alien_crisis_score\s*>\s*70\s*\}\s*$',
	'(?m)^\s*has_stability\s*<\s*0\.25\s*$',
	'(?m)^\s*country_event\s*=\s*\{\s*id\s*=\s*coi_alien_catastrophic_disclosure\.91\s+hours\s*=\s*1\s*\}\s*$'
)) {
	Test-ContractPattern -Text $resolutionEventBlock -Pattern $resolutionPattern -Label 'Catastrophic 180-day resolution thresholds'
}

$civilConflictTriggerBlock = Get-UniqueContractBlock -Text $catastrophicTriggerText -Assignment 'coi_alien_disclosure_civil_conflict_possible_trigger' -Label 'Disclosure civil-conflict guard'
foreach ($civilGuardPattern in @(
	'(?m)^\s*NOT\s*=\s*\{\s*tag\s*=\s*XAC\s*\}\s*$',
	'(?m)^\s*has_civil_war\s*=\s*no\s*$',
	'(?m)^\s*has_capitulated\s*=\s*no\s*$',
	'(?m)^\s*check_variable\s*=\s*\{\s*num_owned_states\s*>\s*1\s*\}\s*$'
)) {
	Test-ContractPattern -Text $civilConflictTriggerBlock -Pattern $civilGuardPattern -Label 'Disclosure civil-conflict safety guard'
}
if ([regex]::Matches($civilConflictTriggerBlock, '(?m)^\s*check_variable\s*=\s*\{\s*party_popularity@(fascism|democratic|communism|neutrality)\s*>\s*0\.15\s*\}\s*$').Count -ne 4) {
	Add-Failure 'Civil conflict must require more than 15% support from one of the four non-ruling ideologies.'
}

$civilConflictEffectBlock = Get-UniqueContractBlock -Text $catastrophicEffectText -Assignment 'coi_alien_start_disclosure_civil_conflict_effect' -Label 'Warned disclosure civil-conflict effect'
if ([regex]::Matches($civilConflictEffectBlock, '(?m)^\s*start_civil_war\s*=\s*\{').Count -ne 4 -or
	[regex]::Matches($civilConflictEffectBlock, '(?m)^\s*keep_all_characters\s*=\s*yes\s*$').Count -ne 4) {
	Add-Failure 'Warned disclosure civil conflict must contain exactly four guarded ideology branches that keep all characters.'
}
foreach ($sizeGuardPattern in @(
	'(?m)^\s*min\s*=\s*0\.30\s*$',
	'(?m)^\s*max\s*=\s*0\.45\s*$'
)) {
	Test-ContractPattern -Text $civilConflictEffectBlock -Pattern $sizeGuardPattern -Label 'Disclosure civil-war size guard'
}
$allCatastrophicText = $catastrophicEffectText + "`n" + $catastrophicTriggerText + "`n" + $catastrophicDecisionText + "`n" + $catastrophicEventText
if ([regex]::Matches($allCatastrophicText, '(?m)^\s*start_civil_war\s*=\s*\{').Count -ne 4) {
	Add-Failure 'Catastrophic-disclosure content contains a start_civil_war outside the single warned guard effect.'
}
$warningEventBlock = Get-UniqueTopLevelEventBlock -Text $catastrophicEventText -Type 'country_event' -Id 'coi_alien_catastrophic_disclosure.91' -Label 'Disclosure civil-conflict warning event'
Test-ContractPattern -Text $warningEventBlock -Pattern '(?m)^\s*custom_effect_tooltip\s*=\s*coi_alien_disclosure_civil_conflict_warning_tt\s*$' -Label 'Explicit civil-conflict warning tooltip'
Test-ContractPattern -Text $warningEventBlock -Pattern '(?m)^\s*hidden_effect\s*=\s*\{\s*coi_alien_start_disclosure_civil_conflict_effect\s*=\s*yes\s*\}\s*$' -Label 'Warned civil-conflict opt-in'
Test-ContractPattern -Text $warningEventBlock -Pattern '(?m)^\s*ai_chance\s*=\s*\{\s*base\s*=\s*95\s*\}\s*$' -Label 'AI emergency-rule preference'
Test-ContractPattern -Text $catastrophicOnActionText -Pattern '(?m)^\s*coi_alien_monthly_catastrophic_disclosure_country_effect\s*=\s*yes\s*$' -Label 'Post-wave released-country reconciliation'
Add-Pass 'Validated dual catastrophic flags, redundant unfiltered every-country .99 sentinel, 0/14/30/60/90 waves, six responses, 180-day resolution, and warned civil-war guards'

$magentaHistoryText = Get-RequiredModText 'history\general\zz_coi_alien_magenta_vatican_history.txt'
$magentaEffectText = Get-RequiredModText 'common\scripted_effects\coi_alien_magenta_vatican_effects.txt'
$magentaTriggerText = Get-RequiredModText 'common\scripted_triggers\coi_alien_magenta_vatican_triggers.txt'
$magentaOnActionText = Get-RequiredModText 'common\on_actions\coi_alien_magenta_vatican_on_actions.txt'
$magentaEventText = Get-RequiredModText 'events\coi_alien_magenta_vatican_events.txt'

Test-ContractPattern -Text $magentaHistoryText -Pattern '(?m)^\s*limit\s*=\s*\{\s*original_tag\s*=\s*ITA\s*\}\s*$' -Label '1936 Magenta Italy history gate'
Test-ContractPattern -Text $magentaHistoryText -Pattern '(?m)^\s*coi_alien_seed_1936_magenta_vatican_effect\s*=\s*yes\s*$' -Label '1936 Magenta seed call'
$magentaSeedBlock = Get-UniqueContractBlock -Text $magentaEffectText -Assignment 'coi_alien_seed_1936_magenta_vatican_effect' -Label '1936 Italy Magenta seed'
foreach ($italyTrack in @(
	@('coi_alien_awareness', '4'),
	@('coi_alien_public_awareness', '0'),
	@('coi_alien_preparedness', '1')
)) {
	Test-ContractPattern -Text $magentaSeedBlock `
		-Pattern ('(?m)^\s*set_variable\s*=\s*\{\s*' + $italyTrack[0] + '\s*=\s*' + $italyTrack[1] + '\s*\}\s*$') `
		-Label "Italy Magenta $($italyTrack[0]) starting stage"
}
foreach ($italyFlag in @(
	'coi_alien_rs33_black_program',
	'coi_alien_special_access_program',
	'coi_alien_evidence_signals',
	'coi_alien_evidence_fragments'
)) {
	Test-ContractPattern -Text $magentaSeedBlock `
		-Pattern ('(?m)^\s*set_country_flag\s*=\s*' + [regex]::Escape($italyFlag) + '\s*$') `
		-Label "Italy Magenta setup flag $italyFlag"
}
Test-ContractPattern -Text $magentaSeedBlock -Pattern '(?m)^\s*159\s*=\s*\{\s*set_state_flag\s*=\s*coi_alien_magenta_craft_vault\s*\}\s*$' -Label 'Magenta Lombardy vault'
Test-ContractPattern -Text $magentaSeedBlock -Pattern '(?m)^\s*coi_alien_adopt_secrecy_stance_effect\s*=\s*yes\s*$' -Label 'Italy Magenta secrecy stance'
Test-ContractPattern -Text $magentaSeedBlock -Pattern '(?m)^\s*coi_alien_assign_magenta_craft_custody_silently_effect\s*=\s*yes\s*$' -Label 'Italy Magenta physical craft custody'

$germanShareBlock = Get-UniqueContractBlock -Text $magentaEffectText -Assignment 'coi_alien_share_rs33_with_germany_effect' -Label 'RS/33 German dossier sharing'
$germanScopes = @(Get-ClausewitzAssignedBlocks -Text $germanShareBlock -Assignment 'GER' | Where-Object {
	$_ -match '\bcoi_alien_raise_knowledge_to_classified_confirmation_effect\b'
})
if ($germanScopes.Count -ne 1) {
	Add-Failure "RS/33 sharing must contain one German receipt scope; found $($germanScopes.Count)."
}
else {
	$germanScope = $germanScopes[0]
	foreach ($germanPattern in @(
		'(?m)^\s*coi_alien_raise_knowledge_to_classified_confirmation_effect\s*=\s*yes\s*$',
		'(?m)^\s*set_country_flag\s*=\s*coi_alien_special_access_program\s*$',
		'(?m)^\s*set_country_flag\s*=\s*coi_alien_evidence_signals\s*$',
		'(?m)^\s*set_country_flag\s*=\s*coi_alien_evidence_fragments\s*$',
		'(?m)^\s*add_ideas\s*=\s*coi_alien_rs33_german_dossier\s*$'
	)) {
		Test-ContractPattern -Text $germanScope -Pattern $germanPattern -Label 'German RS/33 dossier setup'
	}
	if ($germanScope -match '\bcoi_alien_evidence_damaged_craft\b') {
		Add-Failure "Germany must receive RS/33 records and samples, never Italy's physical Magenta craft."
	}
}
$alignmentBlock = Get-UniqueContractBlock -Text $magentaTriggerText -Assignment 'coi_alien_magenta_german_alignment_trigger' -Label 'Italy-Germany RS/33 alignment gate'
Test-ContractPattern -Text $alignmentBlock -Pattern '(?m)^\s*is_in_faction_with\s*=\s*GER\s*$' -Label 'RS/33 faction-alignment route'
Test-ContractPattern -Text $alignmentBlock -Pattern '(?m)^\s*has_completed_focus\s*=\s*ITA_pact_of_steel\s*$' -Label 'RS/33 Pact of Steel route'

$vaticanInitBlock = Get-UniqueContractBlock -Text $magentaEffectText -Assignment 'coi_alien_initialize_vatican_institution_effect' -Label 'Vatican hidden institution setup'
foreach ($vaticanFlag in @(
	'coi_alien_vatican_biological_remains_secured',
	'coi_alien_vatican_vault_permanent'
)) {
	Test-ContractPattern -Text $vaticanInitBlock `
		-Pattern ('(?m)^\s*set_global_flag\s*=\s*' + [regex]::Escape($vaticanFlag) + '\s*$') `
		-Label "Vatican institution flag $vaticanFlag"
}
if ([regex]::Matches($vaticanInitBlock, '(?m)^\s*set_global_flag\s*=\s*coi_alien_vatican_archive_sealed\s*$').Count -lt 1) {
	Add-Failure 'The Vatican archive must initialize sealed.'
}
$vaticanReconcileBlock = Get-UniqueContractBlock -Text $magentaEffectText -Assignment 'coi_alien_reconcile_vatican_custodian_effect' -Label 'Vatican PAP reconciliation'
foreach ($papPattern in @(
	'(?m)^\s*set_country_flag\s*=\s*coi_alien_vatican_archive_custodian\s*$',
	'(?m)^\s*set_country_flag\s*=\s*coi_alien_evidence_alien_biological_remains\s*$',
	'(?m)^\s*add_ideas\s*=\s*coi_alien_vatican_sealed_reliquary\s*$'
)) {
	Test-ContractPattern -Text $vaticanReconcileBlock -Pattern $papPattern -Label 'Vatican PAP custody setup'
}
$vaticanHostBlock = Get-UniqueContractBlock -Text $magentaTriggerText -Assignment 'coi_alien_vatican_reckoning_host_trigger' -Label 'Vatican post-catastrophe reckoning gate'
Test-ContractPattern -Text $vaticanHostBlock -Pattern '(?m)^\s*has_global_flag\s*=\s*coi_alien_catastrophic_disclosure_active\s*$' -Label 'Vatican catastrophic-disclosure gate'
Test-ContractPattern -Text $vaticanHostBlock -Pattern '(?m)^\s*has_global_flag\s*=\s*coi_alien_vatican_archive_sealed\s*$' -Label 'Vatican sealed-archive gate'
$magentaStateControlBlock = Get-UniqueContractBlock -Text $magentaOnActionText -Assignment 'on_state_control_changed' -Label 'Magenta state-control transfer action'
Test-ContractPattern -Text $magentaStateControlBlock -Pattern '(?m)^\s*state\s*=\s*159\s*$' -Label 'Magenta state-control transfer gate'
Test-ContractPattern -Text $magentaStateControlBlock -Pattern '(?m)^\s*coi_alien_transfer_magenta_craft_custody_effect\s*=\s*yes\s*$' -Label 'Magenta custody transfer action'
foreach ($eventSuffix in 1..5) {
	[void](Get-UniqueTopLevelEventBlock -Text $magentaEventText -Type 'country_event' -Id "coi_alien_magenta_vatican.$eventSuffix" -Label 'Magenta/Vatican flavor events')
}
Add-Pass 'Validated Italy craft custody, Germany dossier-only sharing, and the permanent sealed Vatican remains archive'

$humanProjectText = Get-RequiredModText 'common\special_projects\projects\coi_alien_human_reverse_engineering_projects.txt'
$humanProjectTriggerText = Get-RequiredModText 'common\scripted_triggers\coi_alien_human_reverse_engineering_triggers.txt'
$humanProjectEffectText = Get-RequiredModText 'common\scripted_effects\coi_alien_human_reverse_engineering_effects.txt'
$humanProjectGfxText = Get-RequiredModText 'interface\coi_alien_human_reverse_engineering.gfx'
$humanProjectLocalisationText = Get-RequiredModText 'localisation\english\coi_alien_human_reverse_engineering_l_english.yml'
$humanProjectContracts = @(
	[pscustomobject]@{
		Id = 'coi_alien_sp_exotic_materials_characterization'; Specialization = 'specialization_land'
		Prototype = 'sp_time.prototype.short'; Complexity = 'sp_complexity.small'; Breakthrough = 1
		Availability = 'coi_alien_can_start_exotic_materials_project_trigger'; Output = 'coi_alien_grant_human_exotic_materials_effect'
		Icon = 'GFX_coi_alien_sp_exotic_materials_characterization'; Blueprint = 'GFX_coi_alien_sp_exotic_materials_characterization_blueprint'
	},
	[pscustomobject]@{
		Id = 'coi_alien_sp_field_propulsion_reconstruction'; Specialization = 'specialization_air'
		Prototype = 'sp_time.prototype.medium'; Complexity = 'sp_complexity.medium'; Breakthrough = 2
		Availability = 'coi_alien_can_start_field_propulsion_project_trigger'; Output = 'coi_alien_grant_human_field_dynamics_effect'
		Icon = 'GFX_coi_alien_sp_field_propulsion_reconstruction'; Blueprint = 'GFX_coi_alien_sp_field_propulsion_reconstruction_blueprint'
	}
)
foreach ($project in $humanProjectContracts) {
	$projectBlock = Get-UniqueContractBlock -Text $humanProjectText -Assignment $project.Id -Label 'Human reverse-engineering special projects'
	foreach ($projectPattern in @(
		('(?m)^\s*specialization\s*=\s*' + [regex]::Escape($project.Specialization) + '\s*$'),
		('(?m)^\s*icon\s*=\s*' + [regex]::Escape($project.Icon) + '\s*$'),
		('(?m)^\s*blueprint_image\s*=\s*' + [regex]::Escape($project.Blueprint) + '\s*$'),
		'(?m)^\s*has_dlc\s*=\s*"Gotterdammerung"\s*$',
		'(?m)^\s*NOT\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}\s*$',
		('(?m)^\s*' + [regex]::Escape($project.Availability) + '\s*=\s*yes\s*$'),
		('(?m)^\s*' + [regex]::Escape($project.Specialization) + '\s*=\s*' + $project.Breakthrough + '\s*$'),
		('(?m)^\s*prototype_time\s*=\s*' + [regex]::Escape($project.Prototype) + '\s*$'),
		('(?m)^\s*complexity\s*=\s*' + [regex]::Escape($project.Complexity) + '\s*$'),
		('(?m)^\s*' + [regex]::Escape($project.Output) + '\s*=\s*yes\s*$')
	)) {
		Test-ContractPattern -Text $projectBlock -Pattern $projectPattern -Label "$($project.Id) project contract"
	}
}
$fieldProjectBlock = Get-UniqueContractBlock -Text $humanProjectText -Assignment 'coi_alien_sp_field_propulsion_reconstruction' -Label 'Field-propulsion project dependency'
Test-ContractPattern -Text $fieldProjectBlock -Pattern '(?m)^\s*coi_alien_sp_exotic_materials_characterization\s*$' -Label 'Field-propulsion exotic-materials parent'

$exoticGateBlock = Get-UniqueContractBlock -Text $humanProjectTriggerText -Assignment 'coi_alien_can_start_exotic_materials_project_trigger' -Label 'Exotic-materials evidence gate'
foreach ($exoticGatePattern in @(
	'(?m)^\s*has_country_flag\s*=\s*coi_alien_special_access_program\s*$',
	'(?m)^\s*has_country_flag\s*=\s*coi_alien_evidence_fragments\s*$',
	'(?m)^\s*any_owned_state\s*=\s*\{\s*land_facility\s*>\s*0\s*\}\s*$'
)) {
	Test-ContractPattern -Text $exoticGateBlock -Pattern $exoticGatePattern -Label 'Exotic-materials project evidence/facility gate'
}
$fieldGateBlock = Get-UniqueContractBlock -Text $humanProjectTriggerText -Assignment 'coi_alien_can_start_field_propulsion_project_trigger' -Label 'Field-propulsion evidence gate'
foreach ($fieldGatePattern in @(
	'(?m)^\s*has_country_flag\s*=\s*coi_alien_special_access_program\s*$',
	'(?m)^\s*has_country_flag\s*=\s*coi_alien_evidence_damaged_craft\s*$',
	'(?m)^\s*has_country_flag\s*=\s*coi_alien_human_exotic_materials\s*$',
	'(?m)^\s*has_tech\s*=\s*coi_alien_human_exotic_materials\s*$',
	'(?m)^\s*any_owned_state\s*=\s*\{\s*air_facility\s*>\s*0\s*\}\s*$'
)) {
	Test-ContractPattern -Text $fieldGateBlock -Pattern $fieldGatePattern -Label 'Field-propulsion project evidence/facility gate'
}
if (($humanProjectText + "`n" + $humanProjectEffectText) -match '(?m)^\s*clr_country_flag\s*=\s*coi_alien_evidence_') {
	Add-Failure 'Human reverse-engineering projects must gate on evidence without consuming permanent evidence flags.'
}
foreach ($grantEffect in @('coi_alien_grant_human_exotic_materials_effect', 'coi_alien_grant_human_field_dynamics_effect')) {
	$grantBlock = Get-UniqueContractBlock -Text $humanProjectEffectText -Assignment $grantEffect -Label 'Human reverse-engineering completion effects'
	$grantToken = if ($grantEffect -match 'exotic') { 'coi_alien_human_exotic_materials' } else { 'coi_alien_human_field_dynamics' }
	Test-ContractPattern -Text $grantBlock -Pattern ('(?m)^\s*set_country_flag\s*=\s*' + $grantToken + '\s*$') -Label "$grantEffect persistent flag"
	Test-ContractPattern -Text $grantBlock -Pattern ('(?m)^\s*' + $grantToken + '\s*=\s*1\s*$') -Label "$grantEffect hidden technology"
}
foreach ($projectTagDisplay in @(
	@('coi_alien_sp_tag_reverse_engineering', 'Alien Reverse Engineering'),
	@('coi_alien_sp_tag_exotic_materials', 'Exotic Materials'),
	@('coi_alien_sp_tag_field_propulsion', 'Field Propulsion')
)) {
	Test-ContractPattern -Text $humanProjectLocalisationText `
		-Pattern ('(?m)^\s*' + [regex]::Escape($projectTagDisplay[0]) + ':\s*"' + [regex]::Escape($projectTagDisplay[1]) + '"\s*$') `
		-Label "$($projectTagDisplay[0]) project-tag display localisation"
}
Add-Pass 'Validated both human reverse-engineering projects, named small/medium complexities, facilities, parentage, permanent evidence gates, and project-tag display localisation'

$discoveryGfxText = Get-RequiredModText 'interface\coi_alien_discovery_disclosure.gfx'
$newGfxContracts = @(
	[pscustomobject]@{ Name = 'GFX_decision_category_coi_alien_discovery'; Texture = 'gfx/interface/coi_alien/coi_alien_decision_category_discovery.dds'; Width = 52; Height = 40 },
	[pscustomobject]@{ Name = 'GFX_decision_coi_alien_discovery_anomaly'; Texture = 'gfx/interface/coi_alien/coi_alien_decision_discovery_anomaly.dds'; Width = 33; Height = 32 },
	[pscustomobject]@{ Name = 'GFX_report_event_coi_alien_discovery_anomaly'; Texture = 'gfx/event_pictures/coi_alien_discovery_anomaly.dds'; Width = 210; Height = 176 },
	[pscustomobject]@{ Name = 'GFX_decision_coi_alien_disclosure_secrecy'; Texture = 'gfx/interface/coi_alien/coi_alien_decision_disclosure_secrecy.dds'; Width = 33; Height = 32 },
	[pscustomobject]@{ Name = 'GFX_idea_coi_alien_disclosure_secrecy'; Texture = 'gfx/interface/ideas/coi_alien_disclosure_secrecy.dds'; Width = 60; Height = 68 },
	[pscustomobject]@{ Name = 'GFX_decision_coi_alien_disclosure_managed'; Texture = 'gfx/interface/coi_alien/coi_alien_decision_disclosure_managed.dds'; Width = 33; Height = 32 },
	[pscustomobject]@{ Name = 'GFX_idea_coi_alien_disclosure_managed'; Texture = 'gfx/interface/ideas/coi_alien_disclosure_managed.dds'; Width = 60; Height = 68 },
	[pscustomobject]@{ Name = 'GFX_report_event_coi_alien_disclosure_managed'; Texture = 'gfx/event_pictures/coi_alien_disclosure_managed.dds'; Width = 210; Height = 176 },
	[pscustomobject]@{ Name = 'GFX_decision_coi_alien_disclosure_international'; Texture = 'gfx/interface/coi_alien/coi_alien_decision_disclosure_international.dds'; Width = 33; Height = 32 },
	[pscustomobject]@{ Name = 'GFX_idea_coi_alien_disclosure_international'; Texture = 'gfx/interface/ideas/coi_alien_disclosure_international.dds'; Width = 60; Height = 68 },
	[pscustomobject]@{ Name = 'GFX_decision_coi_alien_disclosure_open_files'; Texture = 'gfx/interface/coi_alien/coi_alien_decision_disclosure_open_files.dds'; Width = 33; Height = 32 },
	[pscustomobject]@{ Name = 'GFX_idea_coi_alien_disclosure_open_files'; Texture = 'gfx/interface/ideas/coi_alien_disclosure_open_files.dds'; Width = 60; Height = 68 },
	[pscustomobject]@{ Name = 'GFX_report_event_coi_alien_magenta_recovery'; Texture = 'gfx/event_pictures/coi_alien_magenta_recovery.dds'; Width = 210; Height = 176 },
	[pscustomobject]@{ Name = 'GFX_idea_coi_alien_magenta_recovery'; Texture = 'gfx/interface/ideas/coi_alien_magenta_recovery.dds'; Width = 60; Height = 68 },
	[pscustomobject]@{ Name = 'GFX_report_event_coi_alien_vatican_reliquary'; Texture = 'gfx/event_pictures/coi_alien_vatican_reliquary.dds'; Width = 210; Height = 176 },
	[pscustomobject]@{ Name = 'GFX_idea_coi_alien_vatican_reliquary'; Texture = 'gfx/interface/ideas/coi_alien_vatican_reliquary.dds'; Width = 60; Height = 68 },
	[pscustomobject]@{ Name = 'GFX_decision_category_coi_alien_catastrophic_disclosure'; Texture = 'gfx/interface/coi_alien/coi_alien_decision_category_catastrophic_disclosure.dds'; Width = 52; Height = 40 },
	[pscustomobject]@{ Name = 'GFX_decision_coi_alien_catastrophic_disclosure'; Texture = 'gfx/interface/coi_alien/coi_alien_decision_catastrophic_disclosure.dds'; Width = 33; Height = 32 },
	[pscustomobject]@{ Name = 'GFX_idea_coi_alien_catastrophic_disclosure'; Texture = 'gfx/interface/ideas/coi_alien_catastrophic_disclosure.dds'; Width = 60; Height = 68 },
	[pscustomobject]@{ Name = 'GFX_report_event_coi_alien_catastrophic_disclosure'; Texture = 'gfx/event_pictures/coi_alien_catastrophic_disclosure.dds'; Width = 210; Height = 176 },
	[pscustomobject]@{ Name = 'GFX_news_event_coi_alien_catastrophic_disclosure'; Texture = 'gfx/event_pictures/coi_alien_catastrophic_disclosure_news.dds'; Width = 397; Height = 153 },
	[pscustomobject]@{ Name = 'GFX_report_event_coi_alien_recovery_debris'; Texture = 'gfx/event_pictures/coi_alien_magenta_recovery.dds'; Width = 210; Height = 176 },
	[pscustomobject]@{ Name = 'GFX_report_event_coi_alien_recovery_craft'; Texture = 'gfx/event_pictures/coi_alien_magenta_recovery.dds'; Width = 210; Height = 176 },
	[pscustomobject]@{ Name = 'GFX_report_event_coi_alien_recovery_public_crash'; Texture = 'gfx/event_pictures/coi_alien_catastrophic_disclosure.dds'; Width = 210; Height = 176 },
	[pscustomobject]@{ Name = 'GFX_coi_alien_sp_exotic_materials_characterization'; Texture = 'gfx/interface/special_project/project_icons/coi_alien_sp_exotic_materials_characterization.dds'; Width = 161; Height = 98 },
	[pscustomobject]@{ Name = 'GFX_coi_alien_sp_exotic_materials_characterization_blueprint'; Texture = 'gfx/interface/special_project/blueprints/coi_alien_sp_exotic_materials_characterization_blueprint.dds'; Width = 508; Height = 248 },
	[pscustomobject]@{ Name = 'GFX_coi_alien_sp_field_propulsion_reconstruction'; Texture = 'gfx/interface/special_project/project_icons/coi_alien_sp_field_propulsion_reconstruction.dds'; Width = 161; Height = 98 },
	[pscustomobject]@{ Name = 'GFX_coi_alien_sp_field_propulsion_reconstruction_blueprint'; Texture = 'gfx/interface/special_project/blueprints/coi_alien_sp_field_propulsion_reconstruction_blueprint.dds'; Width = 508; Height = 248 }
)
$newDdsContracts = @{}
foreach ($gfxContract in $newGfxContracts) {
	Test-GfxSpriteContract -Text $allInterfaceGfxText -Name $gfxContract.Name -Texture $gfxContract.Texture
	if ($newDdsContracts.ContainsKey($gfxContract.Texture)) {
		$existingDdsContract = $newDdsContracts[$gfxContract.Texture]
		if ($existingDdsContract.Width -ne $gfxContract.Width -or $existingDdsContract.Height -ne $gfxContract.Height) {
			Add-Failure "$($gfxContract.Texture) is referenced with conflicting DDS dimension contracts."
		}
	}
	else {
		$newDdsContracts[$gfxContract.Texture] = $gfxContract
	}
}
foreach ($ddsContract in $newDdsContracts.Values) {
	Test-DdsArgbContract -RelativePath ($ddsContract.Texture -replace '/', '\') -Width $ddsContract.Width -Height $ddsContract.Height
}
Add-Pass 'Validated all discovery/disclosure/recovery/Magenta/project GFX bindings and native DDS dimensions'

### v0.6.0 Signals in the Noise event-catalog contracts. The deeper dispatcher,
### chronology, and integration checks follow once the authored effect/on-action
### files have been loaded below; this first layer keeps failures diagnostic even
### while a parallel art or script build is incomplete.
$alienNewsEventText = Get-RequiredModText 'events\coi_alien_news_events.txt'
$alienNewsEffectText = Get-RequiredModText 'common\scripted_effects\coi_alien_news_effects.txt'
$alienNewsOnActionText = Get-RequiredModText 'common\on_actions\coi_alien_news_on_actions.txt'
$alienNewsLocalisationText = Get-RequiredModText 'localisation\english\coi_alien_news_l_english.yml'

if ([regex]::Matches($alienNewsEventText, '(?m)^\s*add_namespace\s*=\s*coi_alien_news\s*$').Count -ne 1) {
	Add-Failure 'Signals in the Noise event file must declare the coi_alien_news namespace exactly once.'
}

$expectedAlienNewsCountryIds = @(1..11 | ForEach-Object { "coi_alien_news.$_" })
$expectedAlienNewsWorldIds = @(100..116 | ForEach-Object { "coi_alien_news.$_" })
$actualAlienNewsCountryBlocks = @(Get-TopLevelContractBlocks -Text $alienNewsEventText -Assignment 'country_event')
$actualAlienNewsWorldBlocks = @(Get-TopLevelContractBlocks -Text $alienNewsEventText -Assignment 'news_event')
$actualAlienNewsCountryIds = @($actualAlienNewsCountryBlocks | ForEach-Object {
	$idMatch = [regex]::Match($_, '(?m)^\s*id\s*=\s*(coi_alien_news\.\d+)\s*$')
	if ($idMatch.Success) { $idMatch.Groups[1].Value }
})
$actualAlienNewsWorldIds = @($actualAlienNewsWorldBlocks | ForEach-Object {
	$idMatch = [regex]::Match($_, '(?m)^\s*id\s*=\s*(coi_alien_news\.\d+)\s*$')
	if ($idMatch.Success) { $idMatch.Groups[1].Value }
})
if ($actualAlienNewsCountryBlocks.Count -ne 11 -or
	@($actualAlienNewsCountryIds | Where-Object { $_ -notin $expectedAlienNewsCountryIds }).Count -ne 0 -or
	@($expectedAlienNewsCountryIds | Where-Object { $_ -notin $actualAlienNewsCountryIds }).Count -ne 0) {
	Add-Failure "Signals in the Noise country-event IDs are [$($actualAlienNewsCountryIds -join ', ')]; expected exactly coi_alien_news.1 through .11."
}
if ($actualAlienNewsWorldBlocks.Count -ne 17 -or
	@($actualAlienNewsWorldIds | Where-Object { $_ -notin $expectedAlienNewsWorldIds }).Count -ne 0 -or
	@($expectedAlienNewsWorldIds | Where-Object { $_ -notin $actualAlienNewsWorldIds }).Count -ne 0) {
	Add-Failure "Signals in the Noise news-event IDs are [$($actualAlienNewsWorldIds -join ', ')]; expected exactly coi_alien_news.100 through .116."
}

$alienNewsVisibleMutationPattern = '(?m)^\s*(?:set_|clr_|add_|remove_|create_|delete_|annex_|release\b|puppet\b|declare_|start_|end_|transfer_|save_|clear_|country_event\b|news_event\b|hidden_effect\b|custom_effect_tooltip\b|coi_alien_[a-z0-9_]*_effect\b)[a-z0-9_]*\s*='
foreach ($eventContract in @(
	@($actualAlienNewsCountryBlocks | ForEach-Object { [pscustomobject]@{ Block = $_; Type = 'country_event'; ExpectedOptions = 1 } }),
	@($actualAlienNewsWorldBlocks | ForEach-Object { [pscustomobject]@{ Block = $_; Type = 'news_event'; ExpectedOptions = 0 } })
) | ForEach-Object { $_ }) {
	$eventBlock = $eventContract.Block
	$idMatch = [regex]::Match($eventBlock, '(?m)^\s*id\s*=\s*(coi_alien_news\.\d+)\s*$')
	$eventId = if ($idMatch.Success) { $idMatch.Groups[1].Value } else { '<malformed ID>' }
	foreach ($requiredAssignment in @('title', 'desc', 'picture')) {
		if ([regex]::Matches($eventBlock, '(?m)^\s*' + $requiredAssignment + '\s*=').Count -lt 1) {
			Add-Failure "$eventId must define $requiredAssignment."
		}
	}
	if ([regex]::Matches($eventBlock, '(?m)^\s*is_triggered_only\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "$eventId must be triggered-only."
	}
	if ($eventContract.Type -eq 'news_event' -and
		[regex]::Matches($eventBlock, '(?m)^\s*major\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "$eventId must be a major world-news event."
	}
	if ($eventContract.Type -eq 'news_event' -and
		[regex]::Matches($eventBlock, '(?m)^\s*fire_only_once\s*=\s*yes\s*$').Count -ne 1) {
		Add-Failure "$eventId must retain its engine-level one-shot guard."
	}

	$pictureMatch = [regex]::Match($eventBlock, '(?m)^\s*picture\s*=\s*(GFX_[A-Za-z0-9_]+)\s*$')
	if (-not $pictureMatch.Success) {
		Add-Failure "$eventId must bind one parseable namespaced event picture."
	}
	else {
		$pictureName = $pictureMatch.Groups[1].Value
		$pictureIsValid = if ($eventContract.Type -eq 'news_event') {
			$pictureName -match '^GFX_news_event_coi_alien_' -or
			($eventId -eq 'coi_alien_news.113' -and $pictureName -eq 'GFX_coi_alien_landfall')
		}
		else {
			$pictureName -match '^GFX_report_event_coi_alien_'
		}
		if (-not $pictureIsValid) {
			Add-Failure "$eventId uses non-namespaced or wrong-format picture $($pictureMatch.Groups[1].Value)."
		}
		if ([regex]::Matches($allInterfaceGfxText, '(?m)^\s*name\s*=\s*"' + [regex]::Escape($pictureMatch.Groups[1].Value) + '"\s*$').Count -ne 1) {
			Add-Failure "$eventId picture $($pictureMatch.Groups[1].Value) must be defined exactly once."
		}
	}

	$optionBlocks = @(Get-ClausewitzAssignedBlocks -Text $eventBlock -Assignment 'option')
	if (($eventContract.ExpectedOptions -gt 0 -and $optionBlocks.Count -ne $eventContract.ExpectedOptions) -or
		($eventContract.ExpectedOptions -eq 0 -and $optionBlocks.Count -lt 1)) {
		$expectedOptionDescription = 'at least one'
		if ($eventContract.ExpectedOptions -gt 0) {
			$expectedOptionDescription = [string]$eventContract.ExpectedOptions
		}
		Add-Failure "$eventId has $($optionBlocks.Count) visible option(s); expected $expectedOptionDescription."
	}
	foreach ($optionBlock in $optionBlocks) {
		if ($optionBlock -match $alienNewsVisibleMutationPattern) {
			Add-Failure "$eventId has a state-changing visible option; all Signals in the Noise buttons must be narrative only."
		}
	}
}

$referencedAlienNewsLocalisationKeys = @([regex]::Matches(
	$alienNewsEventText,
	'(?i)\b(?:title|desc|text|name)\s*=\s*(coi_alien_news\.[A-Za-z0-9_.-]+)'
) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
foreach ($key in $referencedAlienNewsLocalisationKeys) {
	if (-not $localisationKeys.ContainsKey($key)) {
		Add-Failure "Missing English Signals in the Noise localisation key $key."
	}
}
foreach ($newsEventId in $expectedAlienNewsWorldIds) {
	$newsEventBlock = Get-UniqueTopLevelEventBlock -Text $alienNewsEventText -Type 'news_event' -Id $newsEventId -Label 'Signals in the Noise contextual reactions'
	$eventNumber = [int]($newsEventId -replace '^coi_alien_news\.', '')
	$expectedReactionKeys = if ($eventNumber -le 113) {
		@('coi_alien_news.option.xac', 'coi_alien_news.option.origin', 'coi_alien_news.option.secretive', 'coi_alien_news.option.human')
	}
	else {
		@('coi_alien_news.option.xac', 'coi_alien_news.option.secretive', 'coi_alien_news.option.human')
	}
	$actualReactionKeys = @(Get-ClausewitzAssignedBlocks -Text $newsEventBlock -Assignment 'option' | ForEach-Object {
		$nameMatch = [regex]::Match($_, '\bname\s*=\s*(coi_alien_news\.option\.[a-z]+)\b')
		if ($nameMatch.Success) { $nameMatch.Groups[1].Value }
	})
	if ($actualReactionKeys.Count -ne $expectedReactionKeys.Count -or
		@($actualReactionKeys | Where-Object { $_ -notin $expectedReactionKeys }).Count -ne 0 -or
		@($expectedReactionKeys | Where-Object { $_ -notin $actualReactionKeys }).Count -ne 0) {
		Add-Failure "$newsEventId contextual reactions are [$($actualReactionKeys -join ', ')]; expected [$($expectedReactionKeys -join ', ')]."
	}
}

foreach ($eraEventNumber in @((105..114) + 116)) {
	$eraEventId = "coi_alien_news.$eraEventNumber"
	$eraEventBlock = Get-UniqueTopLevelEventBlock -Text $alienNewsEventText -Type 'news_event' -Id $eraEventId -Label 'Signals in the Noise era-sensitive headlines'
	foreach ($eraContract in @(
		[pscustomobject]@{ Suffix = 'radio'; Trigger = 'date\s*<\s*1956\.1\.1' },
		[pscustomobject]@{ Suffix = 'broadcast'; Trigger = 'date\s*>\s*1955\.12\.31\s+date\s*<\s*1986\.1\.1' },
		[pscustomobject]@{ Suffix = 'digital'; Trigger = 'date\s*>\s*1985\.12\.31' }
	)) {
		$eraPattern = '(?s)desc\s*=\s*\{\s*text\s*=\s*' + [regex]::Escape("${eraEventId}.desc.$($eraContract.Suffix)") + '\s+trigger\s*=\s*\{\s*' + $eraContract.Trigger + '\s*\}\s*\}'
		if ([regex]::Matches($eraEventBlock, $eraPattern).Count -ne 1) {
			Add-Failure "$eraEventId must define one $($eraContract.Suffix) description with the exact era boundary."
		}
	}
}

$doctrineNewsBlock = Get-UniqueTopLevelEventBlock -Text $alienNewsEventText -Type 'news_event' -Id 'coi_alien_news.115' -Label 'Consensus doctrine-verdict news'
foreach ($doctrineContract in @(
	@('federation', 'coi_alien_doctrine_galactic_federation'),
	@('annihilation', 'coi_alien_doctrine_annihilation'),
	@('sovereignty', 'coi_alien_doctrine_singular_sovereignty'),
	@('mandate', 'coi_alien_doctrine_planetary_mandate')
)) {
	$doctrinePattern = '(?s)desc\s*=\s*\{\s*text\s*=\s*' + [regex]::Escape("coi_alien_news.115.desc.$($doctrineContract[0])") + '\s+trigger\s*=\s*\{\s*XAC\s*=\s*\{\s*has_country_flag\s*=\s*' + [regex]::Escape($doctrineContract[1]) + '\s*\}\s*\}\s*\}'
	if ([regex]::Matches($doctrineNewsBlock, $doctrinePattern).Count -ne 1) {
		Add-Failure "Consensus verdict news must bind the $($doctrineContract[0]) description to $($doctrineContract[1]) exactly once."
	}
}
Add-Pass 'Validated the exact 11-report/17-headline Signals in the Noise event catalog, localisation references, namespaced pictures, major-news presentation, and effect-free visible options'
Add-Pass 'Validated pre-broadcast/broadcast/digital descriptions plus all four existing Consensus doctrine-verdict variants'

$alienNewsDailyBlock = Get-UniqueContractBlock -Text $alienNewsEffectText -Assignment 'coi_alien_news_daily_dispatch_effect' -Label 'Signals in the Noise daily dispatcher'
$alienNewsMonthlyBlock = Get-UniqueContractBlock -Text $alienNewsEffectText -Assignment 'coi_alien_news_monthly_dispatch_effect' -Label 'Signals in the Noise monthly dispatcher'
$alienNewsInitializeBlock = Get-UniqueContractBlock -Text $alienNewsEffectText -Assignment 'coi_alien_news_initialize_effect' -Label 'Signals in the Noise migration initializer'
$alienNewsCooldownBlock = Get-UniqueContractBlock -Text $alienNewsEffectText -Assignment 'coi_alien_news_begin_optional_cooldown_effect' -Label 'Signals in the Noise optional-news cooldown'
Test-ContractPattern -Text $alienNewsCooldownBlock -Pattern '(?m)^\s*flag\s*=\s*coi_alien_news_optional_cooldown\s*$' -Label 'Optional-news cooldown global flag'
Test-ContractPattern -Text $alienNewsCooldownBlock -Pattern '(?m)^\s*days\s*=\s*120\s*$' -Label 'Optional-news 120-day duration'

$alienNewsReportContracts = @(
	[pscustomobject]@{ Event = 1; Effect = 'coi_alien_news_daily_dispatch_effect'; Seen = 'coi_alien_news_report_rs33_seen'; Resolution = 'coi_alien_news_rs33_resolved' },
	[pscustomobject]@{ Event = 2; Effect = 'coi_alien_news_record_correlated_pattern_effect'; Seen = 'coi_alien_news_report_correlated_pattern_seen'; Resolution = '' },
	[pscustomobject]@{ Event = 3; Effect = 'coi_alien_news_record_special_access_program_effect'; Seen = 'coi_alien_news_report_special_access_seen'; Resolution = '' },
	[pscustomobject]@{ Event = 4; Effect = 'coi_alien_news_resolve_luminous_escorts_effect'; Seen = 'coi_alien_news_report_luminous_escorts_seen'; Resolution = 'coi_alien_news_luminous_escorts_resolved' },
	[pscustomobject]@{ Event = 5; Effect = 'coi_alien_news_resolve_northern_rockets_effect'; Seen = 'coi_alien_news_report_northern_rockets_seen'; Resolution = 'coi_alien_news_northern_rockets_resolved' },
	[pscustomobject]@{ Event = 6; Effect = 'coi_alien_news_resolve_new_mexico_effect'; Seen = 'coi_alien_news_report_new_mexico_seen'; Resolution = 'coi_alien_news_new_mexico_resolved' },
	[pscustomobject]@{ Event = 7; Effect = 'coi_alien_news_resolve_capital_radar_effect'; Seen = 'coi_alien_news_report_capital_radar_seen'; Resolution = 'coi_alien_news_capital_radar_resolved' },
	[pscustomobject]@{ Event = 8; Effect = 'coi_alien_news_record_returned_witness_effect'; Seen = 'coi_alien_news_report_returned_witness_seen'; Resolution = '' },
	[pscustomobject]@{ Event = 9; Effect = 'coi_alien_news_record_archive_rumor_effect'; Seen = 'coi_alien_news_report_archive_rumor_seen'; Resolution = '' },
	[pscustomobject]@{ Event = 10; Effect = 'coi_alien_news_record_archive_evidence_effect'; Seen = 'coi_alien_news_report_archive_evidence_seen'; Resolution = '' },
	[pscustomobject]@{ Event = 11; Effect = 'coi_alien_news_record_contact_contingencies_effect'; Seen = 'coi_alien_news_report_contact_contingencies_seen'; Resolution = '' }
)
foreach ($report in $alienNewsReportContracts) {
	$container = Get-UniqueContractBlock -Text $alienNewsEffectText -Assignment $report.Effect -Label "coi_alien_news.$($report.Event) one-shot report dispatcher"
	$eventPattern = '(?m)^\s*country_event\s*=\s*\{\s*id\s*=\s*coi_alien_news\.' + $report.Event + '\s+hours\s*=\s*1\s*\}\s*$'
	$seenPattern = '(?m)^\s*set_country_flag\s*=\s*' + [regex]::Escape($report.Seen) + '\s*$'
	Test-ContractPattern -Text $container -Pattern $eventPattern -Label "coi_alien_news.$($report.Event) report dispatch"
	Test-ContractPattern -Text $container -Pattern $seenPattern -Label "coi_alien_news.$($report.Event) seen flag"
	$eventIndex = $container.IndexOf("country_event = { id = coi_alien_news.$($report.Event) hours = 1 }", [StringComparison]::Ordinal)
	$seenIndex = $container.IndexOf("set_country_flag = $($report.Seen)", [StringComparison]::Ordinal)
	if ($eventIndex -lt 0 -or $seenIndex -lt 0 -or $seenIndex -gt $eventIndex) {
		Add-Failure "coi_alien_news.$($report.Event) must commit $($report.Seen) before showing its report."
	}
	if ([string]::IsNullOrWhiteSpace($report.Resolution)) {
		$seenGuardPattern = '(?m)^\s*NOT\s*=\s*\{\s*has_country_flag\s*=\s*' + [regex]::Escape($report.Seen) + '\s*\}\s*$'
		Test-ContractPattern -Text $container -Pattern $seenGuardPattern -Label "coi_alien_news.$($report.Event) repeat guard"
	}
	else {
		$resolutionSetPattern = '(?m)^\s*set_global_flag\s*=\s*' + [regex]::Escape($report.Resolution) + '\s*$'
		if ([regex]::Matches($container, $resolutionSetPattern).Count -lt 1) {
			Add-Failure "coi_alien_news.$($report.Event) must commit its global resolution flag $($report.Resolution)."
		}
	}
}

$alienNewsPublicationContracts = @(
	[pscustomobject]@{ Event = 100; Effect = 'coi_alien_news_resolve_luminous_escorts_effect'; Flag = 'coi_alien_news_luminous_escorts_published'; Optional = $true },
	[pscustomobject]@{ Event = 101; Effect = 'coi_alien_news_resolve_northern_rockets_effect'; Flag = 'coi_alien_news_northern_rockets_published'; Optional = $true },
	[pscustomobject]@{ Event = 102; Effect = 'coi_alien_news_resolve_new_mexico_effect'; Flag = 'coi_alien_news_flying_disc_fever_published'; Optional = $true },
	[pscustomobject]@{ Event = 103; Effect = 'coi_alien_news_resolve_capital_radar_effect'; Flag = 'coi_alien_news_capital_radar_published'; Optional = $true },
	[pscustomobject]@{ Event = 104; Effect = 'coi_alien_news_publish_scientists_demand_effect'; Flag = 'coi_alien_news_scientists_demand_published'; Optional = $true },
	[pscustomobject]@{ Event = 105; Effect = 'coi_alien_news_publish_public_inquiry_effect'; Flag = 'coi_alien_news_public_inquiry_published'; Optional = $true },
	[pscustomobject]@{ Event = 106; Effect = 'coi_alien_news_publish_archive_rumor_effect'; Flag = 'coi_alien_news_whistleblower_published'; Optional = $true },
	[pscustomobject]@{ Event = 107; Effect = 'coi_alien_news_publish_archive_evidence_effect'; Flag = 'coi_alien_news_authenticated_film_published'; Optional = $true },
	[pscustomobject]@{ Event = 108; Effect = 'coi_alien_news_record_official_acknowledgment_effect'; Flag = 'coi_alien_news_official_acknowledgment_published'; Optional = $false },
	[pscustomobject]@{ Event = 109; Effect = 'coi_alien_news_record_open_files_effect'; Flag = 'coi_alien_news_open_files_published'; Optional = $false },
	[pscustomobject]@{ Event = 110; Effect = 'coi_alien_news_record_contact_council_effect'; Flag = 'coi_alien_news_contact_council_published'; Optional = $false },
	[pscustomobject]@{ Event = 111; Effect = 'coi_alien_news_dispatch_catastrophic_opening_effect'; Flag = 'coi_alien_news_public_crash_published'; Optional = $false },
	[pscustomobject]@{ Event = 112; Effect = 'coi_alien_news_record_vatican_reliquary_opened_effect'; Flag = 'coi_alien_news_vatican_reliquary_published'; Optional = $false },
	[pscustomobject]@{ Event = 113; Effect = 'coi_alien_news_dispatch_catastrophic_opening_effect'; Flag = 'coi_alien_news_landfall_published'; Optional = $false },
	[pscustomobject]@{ Event = 114; Effect = 'coi_alien_news_daily_dispatch_effect'; Flag = 'coi_alien_news_first_transmission_dispatched'; Optional = $false },
	[pscustomobject]@{ Event = 115; Effect = 'coi_alien_news_daily_dispatch_effect'; Flag = 'coi_alien_news_doctrine_verdict_dispatched'; Optional = $false },
	[pscustomobject]@{ Event = 116; Effect = 'coi_alien_news_daily_dispatch_effect'; Flag = 'coi_alien_news_unified_defense_dispatched'; Optional = $false }
)
foreach ($publication in $alienNewsPublicationContracts) {
	$container = Get-UniqueContractBlock -Text $alienNewsEffectText -Assignment $publication.Effect -Label "coi_alien_news.$($publication.Event) publication dispatcher"
	$eventPattern = '\bnews_event\s*=\s*\{\s*id\s*=\s*coi_alien_news\.' + $publication.Event + '\s+hours\s*=\s*1\s*\}'
	$flagPattern = '(?m)^\s*set_global_flag\s*=\s*' + [regex]::Escape($publication.Flag) + '\s*$'
	Test-ContractPattern -Text $container -Pattern $eventPattern -Label "coi_alien_news.$($publication.Event) world-news dispatch"
	Test-ContractPattern -Text $container -Pattern $flagPattern -Label "coi_alien_news.$($publication.Event) publication flag"
	if ($publication.Optional) {
		Test-ContractPattern -Text $container -Pattern '(?m)^\s*coi_alien_news_begin_optional_cooldown_effect\s*=\s*yes\s*$' -Label "coi_alien_news.$($publication.Event) optional cooldown commitment"
	}
	elseif ($container -match '(?m)^\s*coi_alien_news_begin_optional_cooldown_effect\s*=\s*yes\s*$') {
		Add-Failure "Mandatory coi_alien_news.$($publication.Event) must bypass the optional-news cooldown."
	}
}
foreach ($worldEventId in $expectedAlienNewsWorldIds) {
	$dispatchPattern = '\bnews_event\s*=\s*\{\s*id\s*=\s*' + [regex]::Escape($worldEventId) + '\s+hours\s*=\s*1\s*\}'
	if ([regex]::Matches($alienNewsEffectText, $dispatchPattern).Count -ne 1) {
		Add-Failure "$worldEventId must have exactly one scripted-effect dispatch site."
	}
}

$historicalNewsContracts = @(
	[pscustomobject]@{ Flag = 'coi_alien_news_luminous_escorts_resolved'; Resolver = 'coi_alien_news_resolve_luminous_escorts_effect'; Start = '1939\.12\.31'; End = '1946\.1\.1'; Expired = '1945\.12\.31' },
	[pscustomobject]@{ Flag = 'coi_alien_news_northern_rockets_resolved'; Resolver = 'coi_alien_news_resolve_northern_rockets_effect'; Start = '1945\.12\.31'; End = '1949\.1\.1'; Expired = '1948\.12\.31' },
	[pscustomobject]@{ Flag = 'coi_alien_news_new_mexico_resolved'; Resolver = 'coi_alien_news_resolve_new_mexico_effect'; Start = '1947\.6\.1'; End = '1948\.1\.1'; Expired = '1947\.12\.31' },
	[pscustomobject]@{ Flag = 'coi_alien_news_capital_radar_resolved'; Resolver = 'coi_alien_news_resolve_capital_radar_effect'; Start = '1951\.12\.31'; End = '1954\.1\.1'; Expired = '1953\.12\.31' }
)
foreach ($history in $historicalNewsContracts) {
	$windowPattern = '(?s)NOT\s*=\s*\{\s*has_global_flag\s*=\s*' + [regex]::Escape($history.Flag) + '\s*\}.*?date\s*>\s*' + $history.Start + '.*?date\s*<\s*' + $history.End + '.*?' + [regex]::Escape($history.Resolver) + '\s*=\s*yes'
	if ([regex]::Matches($alienNewsMonthlyBlock, $windowPattern).Count -lt 1) {
		Add-Failure "$($history.Resolver) must retain its bounded historical window and resolution guard."
	}
	$initializerPattern = '(?m)^\s*if\s*=\s*\{\s*limit\s*=\s*\{\s*date\s*>\s*' + $history.Expired + '\s*\}\s*set_global_flag\s*=\s*' + [regex]::Escape($history.Flag) + '\s*\}\s*$'
	Test-ContractPattern -Text $alienNewsInitializeBlock -Pattern $initializerPattern -Label "$($history.Flag) late-save backlog guard"
	$monthlyExpiryPattern = '(?m)^\s*if\s*=\s*\{\s*limit\s*=\s*\{\s*NOT\s*=\s*\{\s*has_global_flag\s*=\s*' + [regex]::Escape($history.Flag) + '\s*\}\s*date\s*>\s*' + $history.Expired + '\s*\}\s*set_global_flag\s*=\s*' + [regex]::Escape($history.Flag) + '\s*\}\s*$'
	Test-ContractPattern -Text $alienNewsMonthlyBlock -Pattern $monthlyExpiryPattern -Label "$($history.Flag) post-start expiry guard"
}
Test-ContractPattern -Text $alienNewsInitializeBlock -Pattern '(?m)^\s*if\s*=\s*\{\s*limit\s*=\s*\{\s*date\s*>\s*1939\.12\.31\s*\}\s*set_global_flag\s*=\s*coi_alien_news_rs33_resolved\s*\}\s*$' -Label 'RS/33 late-save backlog guard'

$catastrophicNewsBlock = Get-UniqueContractBlock -Text $alienNewsEffectText -Assignment 'coi_alien_news_dispatch_catastrophic_opening_effect' -Label 'Source-aware catastrophic headline dispatcher'
foreach ($catastrophicPattern in @(
	'(?m)^\s*limit\s*=\s*\{\s*NOT\s*=\s*\{\s*has_global_flag\s*=\s*coi_alien_news_catastrophic_opening_dispatched\s*\}\s*\}\s*$',
	'(?m)^\s*set_global_flag\s*=\s*coi_alien_news_catastrophic_opening_dispatched\s*$',
	'(?s)if\s*=\s*\{\s*limit\s*=\s*\{\s*has_global_flag\s*=\s*coi_alien_news_catastrophic_cause_public_crash\s*\}.*?coi_alien_news\.111.*?else_if\s*=\s*\{\s*limit\s*=\s*\{\s*has_global_flag\s*=\s*coi_alien_news_catastrophic_cause_landfall\s*\}.*?coi_alien_news\.113.*?else\s*=\s*\{.*?coi_alien_catastrophic_disclosure\.1',
	'(?s)set_global_flag\s*=\s*\{\s*flag\s*=\s*coi_alien_news_first_transmission_delay\s+days\s*=\s*7\s*\}'
)) {
	if ([regex]::Matches($catastrophicNewsBlock, $catastrophicPattern).Count -ne 1) {
		Add-Failure "Source-aware catastrophic headline contract is missing or duplicates: $catastrophicPattern"
	}
}

$catastrophicCoreEntryBlock = Get-UniqueContractBlock -Text $catastrophicEffectText -Assignment 'coi_alien_begin_catastrophic_disclosure_effect' -Label 'Catastrophic disclosure source recorder'
foreach ($sourceFlag in @(
	'coi_alien_news_catastrophic_cause_public_crash',
	'coi_alien_news_catastrophic_cause_landfall',
	'coi_alien_news_catastrophic_cause_other'
)) {
	Test-ContractPattern -Text $catastrophicCoreEntryBlock -Pattern ('(?m)^\s*clr_global_flag\s*=\s*' + [regex]::Escape($sourceFlag) + '\s*$') -Label "$sourceFlag stale-source cleanup"
	Test-ContractPattern -Text $catastrophicCoreEntryBlock -Pattern ('\bset_global_flag\s*=\s*' + [regex]::Escape($sourceFlag) + '\b') -Label "$sourceFlag mutually exclusive assignment"
}
if ([regex]::Matches($catastrophicCoreEntryBlock, '(?m)^\s*coi_alien_news_dispatch_catastrophic_opening_effect\s*=\s*yes\s*$').Count -ne 1) {
	Add-Failure 'Catastrophic disclosure must call its source-aware news dispatcher exactly once.'
}
$sourceRecordIndex = $catastrophicCoreEntryBlock.IndexOf('set_global_flag = coi_alien_news_catastrophic_cause_other', [StringComparison]::Ordinal)
$originRecordIndex = $catastrophicCoreEntryBlock.IndexOf('save_global_event_target_as = coi_alien_disclosure_origin', [StringComparison]::Ordinal)
$openingDispatchIndex = $catastrophicCoreEntryBlock.IndexOf('coi_alien_news_dispatch_catastrophic_opening_effect = yes', [StringComparison]::Ordinal)
if ($sourceRecordIndex -lt 0 -or $originRecordIndex -lt 0 -or $openingDispatchIndex -lt 0 -or
	$sourceRecordIndex -gt $openingDispatchIndex -or $originRecordIndex -gt $openingDispatchIndex) {
	Add-Failure 'Catastrophic disclosure must record both cause and origin before dispatching its one opening headline.'
}

$newMexicoResolverBlock = Get-UniqueContractBlock -Text $alienNewsEffectText -Assignment 'coi_alien_news_resolve_new_mexico_effect' -Label 'New Mexico 1947 evidence resolver'
foreach ($newMexicoPattern in @(
	'(?m)^\s*set_country_flag\s*=\s*coi_alien_evidence_signals\s*$',
	'(?m)^\s*set_country_flag\s*=\s*coi_alien_evidence_fragments\s*$',
	'(?m)^\s*coi_alien_raise_knowledge_to_correlated_pattern_effect\s*=\s*yes\s*$'
)) {
	if ([regex]::Matches($newMexicoResolverBlock, $newMexicoPattern).Count -ne 1) {
		Add-Failure "New Mexico 1947 is missing or duplicates its restrained evidence contract: $newMexicoPattern"
	}
}
if ($newMexicoResolverBlock -match '(?i)damaged_craft|intact_craft|material_proof|begin_catastrophic') {
	Add-Failure 'New Mexico 1947 must grant only signals, fragments, and correlated knowledge—not a damaged/intact craft or automatic disclosure.'
}

foreach ($sequencePattern in @(
	'(?s)NOT\s*=\s*\{\s*has_global_flag\s*=\s*coi_alien_news_first_transmission_delay\s*\}.*?NOT\s*=\s*\{\s*has_global_flag\s*=\s*coi_alien_news_first_transmission_dispatched\s*\}.*?set_global_flag\s*=\s*coi_alien_news_first_transmission_dispatched.*?flag\s*=\s*coi_alien_news_doctrine_verdict_delay\s+days\s*=\s*14.*?coi_alien_news\.114',
	'(?s)has_global_flag\s*=\s*coi_alien_news_first_transmission_dispatched.*?NOT\s*=\s*\{\s*has_global_flag\s*=\s*coi_alien_news_doctrine_verdict_delay\s*\}.*?has_country_flag\s*=\s*coi_alien_doctrine_selected.*?set_global_flag\s*=\s*coi_alien_news_doctrine_verdict_dispatched.*?flag\s*=\s*coi_alien_news_xcom_demand_delay\s+days\s*=\s*14.*?coi_alien_news\.115',
	'(?s)has_global_flag\s*=\s*coi_alien_news_doctrine_verdict_dispatched.*?NOT\s*=\s*\{\s*has_global_flag\s*=\s*coi_alien_news_xcom_demand_delay\s*\}.*?set_global_flag\s*=\s*coi_alien_xcom_demand_established.*?set_global_flag\s*=\s*coi_alien_news_unified_defense_dispatched.*?coi_alien_news\.116'
)) {
	if ([regex]::Matches($alienNewsDailyBlock, $sequencePattern).Count -ne 1) {
		Add-Failure "Post-contact 7/14/14-day sequence is missing or duplicates: $sequencePattern"
	}
}

foreach ($onActionContract in @(
	@('on_daily_XAC', 'coi_alien_news_daily_dispatch_effect'),
	@('on_monthly_XAC', 'coi_alien_news_monthly_dispatch_effect')
)) {
	$onActionBlock = Get-UniqueContractBlock -Text $alienNewsOnActionText -Assignment $onActionContract[0] -Label 'XAC-scoped Signals in the Noise clock'
	Test-ContractPattern -Text $onActionBlock -Pattern ('(?m)^\s*' + [regex]::Escape($onActionContract[1]) + '\s*=\s*yes\s*$') -Label "$($onActionContract[0]) news dispatcher"
}
if ($alienNewsOnActionText -match '(?m)^\s*on_(?:daily|monthly)\s*=') {
	Add-Failure 'Signals in the Noise must use XAC-scoped clocks rather than global country-wide daily/monthly on-actions.'
}

$alienNewsNoXcomCreationText = $alienNewsEventText + "`n" + $alienNewsEffectText + "`n" + $alienNewsOnActionText
if ([regex]::Matches($alienNewsNoXcomCreationText, '(?im)^\s*(?:create_country|create_faction|add_to_faction|create_unit|load_oob|declare_war_on|annex_country|start_civil_war)\s*=').Count -ne 0) {
	Add-Failure 'Signals in the Noise must not form XCOM through a country, faction, unit, war, annexation, or civil-war effect.'
}
if ([regex]::Matches($alienNewsEffectText, '(?m)^\s*set_global_flag\s*=\s*coi_alien_xcom_demand_established\s*$').Count -ne 1) {
	Add-Failure 'Signals in the Noise must set the future coi_alien_xcom_demand_established hook exactly once.'
}

foreach ($integrationContract in @(
	[pscustomobject]@{ Text = $discoveryEffectText; Hook = 'coi_alien_news_record_correlated_pattern_effect'; Count = 1 },
	[pscustomobject]@{ Text = $discoveryEffectText; Hook = 'coi_alien_news_record_special_access_program_effect'; Count = 1 },
	[pscustomobject]@{ Text = $discoveryEffectText; Hook = 'coi_alien_news_record_official_acknowledgment_effect'; Count = 1 },
	[pscustomobject]@{ Text = $discoveryEffectText; Hook = 'coi_alien_news_record_contact_contingencies_effect'; Count = 1 },
	[pscustomobject]@{ Text = $discoveryEffectText; Hook = 'coi_alien_news_record_contact_council_effect'; Count = 1 },
	[pscustomobject]@{ Text = $discoveryEffectText; Hook = 'coi_alien_news_record_open_files_effect'; Count = 1 },
	[pscustomobject]@{ Text = $discoveryEffectText; Hook = 'coi_alien_news_record_archive_rumor_effect'; Count = 1 },
	[pscustomobject]@{ Text = $discoveryEffectText; Hook = 'coi_alien_news_record_archive_evidence_effect'; Count = 1 },
	[pscustomobject]@{ Text = $humanScienceEffectText; Hook = 'coi_alien_news_record_returned_witness_effect'; Count = 2 },
	[pscustomobject]@{ Text = $magentaEventText; Hook = 'coi_alien_news_record_vatican_reliquary_opened_effect'; Count = 1 }
)) {
	$hookPattern = '\b' + [regex]::Escape($integrationContract.Hook) + '\s*=\s*yes\b'
	if ([regex]::Matches($integrationContract.Text, $hookPattern).Count -ne $integrationContract.Count) {
		Add-Failure "$($integrationContract.Hook) must have exactly $($integrationContract.Count) integration call(s)."
	}
}
Add-Pass 'Validated one-shot report/publication flags, exact 120-day optional cadence, monthly historical windows, and late-save backlog suppression'
Add-Pass 'Validated mutually exclusive public-crash/landfall/fallback disclosure headlines, the 7/14/14-day post-contact sequence, and the non-forming XCOM hook'
Add-Pass 'Validated XAC-scoped daily/monthly narrative clocks, discovery/recovery/Vatican integration hooks, and absence of country-wide high-frequency iteration'

### v0.6.0 Signals in the Noise art contracts. Every original master receives
### one native news strip; the eight masters reused by classified reports also
### receive a report crop. The Vatican headline deliberately derives from the
### existing reliquary master rather than introducing a sixteenth source.
$alienNewsArtSubjects = @(
	'black_program',
	'luminous_escorts',
	'northern_rockets',
	'new_mexico_1947',
	'capital_radar',
	'returned_witness',
	'archive_leak',
	'public_inquiry',
	'authenticated_film',
	'official_podium',
	'contact_council',
	'public_crash',
	'first_transmission',
	'consensus_verdict',
	'unified_defense'
)
$alienNewsReportSubjects = @(
	'black_program',
	'luminous_escorts',
	'northern_rockets',
	'new_mexico_1947',
	'capital_radar',
	'returned_witness',
	'archive_leak',
	'public_inquiry'
)

$expectedAlienNewsMasterNames = @($alienNewsArtSubjects | ForEach-Object { "coi_alien_news_$_.png" })
$actualAlienNewsMasterNames = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Source\Art\Masters') -File -Filter 'coi_alien_news_*.png' -ErrorAction SilentlyContinue |
	ForEach-Object { $_.Name })
if ($actualAlienNewsMasterNames.Count -ne 15 -or
	@($actualAlienNewsMasterNames | Where-Object { $_ -notin $expectedAlienNewsMasterNames }).Count -ne 0 -or
	@($expectedAlienNewsMasterNames | Where-Object { $_ -notin $actualAlienNewsMasterNames }).Count -ne 0) {
	Add-Failure "Signals in the Noise must retain exactly its 15 named master PNGs; found [$($actualAlienNewsMasterNames -join ', ')]."
}

foreach ($subject in $alienNewsArtSubjects) {
	$masterName = "coi_alien_news_${subject}.png"
	$masterPath = Join-Path $ProjectRoot (Join-Path 'Source\Art\Masters' $masterName)
	if (-not (Test-Path -LiteralPath $masterPath -PathType Leaf)) {
		Add-Failure "Missing Signals in the Noise ImageGen master: $masterName"
	}
	else {
		$masterBytes = [IO.File]::ReadAllBytes($masterPath)
		if ($masterBytes.Length -lt 33 -or
			$masterBytes[0] -ne 0x89 -or $masterBytes[1] -ne 0x50 -or
			$masterBytes[2] -ne 0x4E -or $masterBytes[3] -ne 0x47 -or
			$masterBytes[24] -ne 8 -or $masterBytes[25] -notin @(2, 6)) {
			Add-Failure "$masterName must remain an 8-bit RGB or RGBA PNG ImageGen master."
		}
		else {
			$masterWidth = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($masterBytes, 16))
			$masterHeight = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($masterBytes, 20))
			if ($masterWidth -lt 1024 -or $masterHeight -lt 512) {
				Add-Failure "$masterName is ${masterWidth}x${masterHeight}; retain at least a 1024x512 source."
			}
		}
	}

	$newsTexture = "gfx/event_pictures/coi_alien_news_${subject}_news.dds"
	$newsSprite = "GFX_news_event_coi_alien_news_${subject}"
	Test-DdsArgbContract -RelativePath ($newsTexture -replace '/', '\') -Width 397 -Height 153
	Test-GfxSpriteContract -Text $allInterfaceGfxText -Name $newsSprite -Texture $newsTexture

	if ($subject -in $alienNewsReportSubjects) {
		$reportTexture = "gfx/event_pictures/coi_alien_news_${subject}.dds"
		$reportSprite = "GFX_report_event_coi_alien_news_${subject}"
		Test-DdsArgbContract -RelativePath ($reportTexture -replace '/', '\') -Width 210 -Height 176
		Test-GfxSpriteContract -Text $allInterfaceGfxText -Name $reportSprite -Texture $reportTexture
	}
}

$expectedAlienNewsDdsNames = @($alienNewsArtSubjects | ForEach-Object { "coi_alien_news_$($_)_news.dds" }) +
	@($alienNewsReportSubjects | ForEach-Object { "coi_alien_news_$_.dds" })
$actualAlienNewsDdsNames = @(Get-ChildItem -LiteralPath (Join-Path $modRoot 'gfx\event_pictures') -File -Filter 'coi_alien_news_*.dds' -ErrorAction SilentlyContinue |
	ForEach-Object { $_.Name })
if ($actualAlienNewsDdsNames.Count -ne 23 -or
	@($actualAlienNewsDdsNames | Where-Object { $_ -notin $expectedAlienNewsDdsNames }).Count -ne 0 -or
	@($expectedAlienNewsDdsNames | Where-Object { $_ -notin $actualAlienNewsDdsNames }).Count -ne 0) {
	Add-Failure "Signals in the Noise must derive exactly 15 news strips and eight report crops; found [$($actualAlienNewsDdsNames -join ', ')]."
}

$vaticanNewsTexture = 'gfx/event_pictures/coi_alien_vatican_reliquary_news.dds'
Test-DdsArgbContract -RelativePath ($vaticanNewsTexture -replace '/', '\') -Width 397 -Height 153
Test-GfxSpriteContract `
	-Text $allInterfaceGfxText `
	-Name 'GFX_news_event_coi_alien_vatican_reliquary' `
	-Texture $vaticanNewsTexture

$alienNewsGfxText = Get-RequiredModText 'interface\coi_alien_news.gfx'
$alienNewsSpriteNames = @([regex]::Matches($alienNewsGfxText, '(?m)^\s*name\s*=\s*"([^"]+)"\s*$') |
	ForEach-Object { $_.Groups[1].Value })
foreach ($spriteName in $alienNewsSpriteNames) {
	if ($spriteName -notmatch '^GFX_(?:news_event|report_event)_coi_alien_') {
		Add-Failure "Signals in the Noise GFX file attempts to define non-namespaced sprite $spriteName."
	}
}
if ($alienNewsSpriteNames.Count -ne 24) {
	Add-Failure "Signals in the Noise GFX file defines $($alienNewsSpriteNames.Count) sprites; expected 24 namespaced bindings."
}

$alienNewsBuilderText = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'Source\Build-ArtAssets.ps1'))
foreach ($subject in $alienNewsArtSubjects) {
	$builderToken = "coi_alien_news_${subject}.png"
	if ([regex]::Matches($alienNewsBuilderText, [regex]::Escape($builderToken)).Count -ne 1) {
		Add-Failure "Signals in the Noise art builder must reference $builderToken exactly once."
	}
}
foreach ($builderPattern in @(
	'(?s)\$newsPicture\s*=\s*New-RenderedBitmap.*?-Width\s+397.*?-Height\s+153.*?coi_alien_news_\$\{name\}_news\.dds',
	'(?s)\$reportPicture\s*=\s*New-RenderedBitmap.*?-Width\s+210.*?-Height\s+176.*?coi_alien_news_\$name\.dds',
	'(?s)\$vaticanNews\s*=\s*New-RenderedBitmap.*?-Width\s+397.*?-Height\s+153.*?coi_alien_vatican_reliquary_news\.dds'
)) {
	if ([regex]::Matches($alienNewsBuilderText, $builderPattern).Count -ne 1) {
		Add-Failure "Signals in the Noise art builder is missing or duplicates reproducibility pattern: $builderPattern"
	}
}

$alienNewsProvenancePath = Join-Path $ProjectRoot 'Source\Art\alien_news_imagegen_prompts.md'
if (-not (Test-Path -LiteralPath $alienNewsProvenancePath -PathType Leaf)) {
	Add-Failure "Missing Signals in the Noise ImageGen prompt provenance: $alienNewsProvenancePath"
}
else {
	$alienNewsProvenanceText = [IO.File]::ReadAllText($alienNewsProvenancePath)
	if ($alienNewsProvenanceText -notmatch '(?i)built-in (?:OpenAI )?ImageGen') {
		Add-Failure 'Signals in the Noise provenance must identify built-in ImageGen as the generation mode.'
	}
	foreach ($subject in $alienNewsArtSubjects) {
		$masterName = "coi_alien_news_${subject}.png"
		if ([regex]::Matches($alienNewsProvenanceText, [regex]::Escape($masterName)).Count -ne 1) {
			Add-Failure "Signals in the Noise provenance must name $masterName exactly once."
		}
	}
}
Add-Pass 'Validated 15 original alien-news masters, 24 namespaced GFX bindings, 15 native news strips, eight report crops, the reused Vatican strip, and ImageGen provenance'

$descriptorText = [IO.File]::ReadAllText((Join-Path $modRoot 'descriptor.mod'))
$launcherTemplateText = [IO.File]::ReadAllText((Join-Path $projectRoot 'Launcher\alien_crisis_dev.mod.template'))
foreach ($contract in @(
	'version="0\.6\.0"',
	'name="Alien Crisis: Grey Consensus \[DEV\]"',
	'picture="thumbnail\.png"',
	'supported_version="1\.19\.\*"'
)) {
	if ($descriptorText -notmatch $contract) {
		Add-Failure "Mod descriptor is missing packaging contract: $contract"
	}
	if ($launcherTemplateText -notmatch $contract) {
		Add-Failure "Launcher template is missing packaging contract: $contract"
	}
}
if ($launcherTemplateText -notmatch 'path="@MOD_PATH@"') {
	Add-Failure "Launcher template is missing the @MOD_PATH@ placeholder."
}
foreach ($packagingText in @($descriptorText, $launcherTemplateText)) {
	if ($packagingText -match '(?m)^\s*replace_path\s*=') {
		Add-Failure 'Alien Crisis packaging must not use broad replace_path entries.'
	}
}
Add-Pass "Validated the 0.6.0 launcher and Workshop descriptor contracts"

$localWorkshopVdfPath = Join-Path $projectRoot 'Workshop\workshop_item_394360.vdf'
$exampleWorkshopVdfPath = Join-Path $projectRoot 'Workshop\workshop_item_394360.example.vdf'
$usingWorkshopExample = -not (Test-Path -LiteralPath $localWorkshopVdfPath -PathType Leaf)
$workshopVdfPath = if ($usingWorkshopExample) { $exampleWorkshopVdfPath } else { $localWorkshopVdfPath }
if (-not (Test-Path -LiteralPath $workshopVdfPath -PathType Leaf)) {
	Add-Failure "Missing local or example Steam Workshop staging file: $workshopVdfPath"
}
else {
	$workshopVdfText = [IO.File]::ReadAllText($workshopVdfPath)
	if ($workshopVdfText -notmatch '(?s)^\s*"workshopitem"\s*\{.*\}\s*$') {
		Add-Failure 'Workshop staging VDF must contain one workshopitem root object.'
	}

	$workshopFields = @{}
	foreach ($match in [regex]::Matches($workshopVdfText, '(?m)^\s*"([^"]+)"\s+"([^"]*)"\s*$')) {
		$key = $match.Groups[1].Value
		$value = $match.Groups[2].Value
		if ($workshopFields.ContainsKey($key)) {
			Add-Failure "Workshop staging VDF contains duplicate field '$key'."
		}
		else {
			$workshopFields[$key] = $value
		}
	}

	foreach ($requiredField in @(
		'appid',
		'publishedfileid',
		'contentfolder',
		'previewfile',
		'visibility',
		'title',
		'description',
		'changenote'
	)) {
		if (-not $workshopFields.ContainsKey($requiredField)) {
			Add-Failure "Workshop staging VDF is missing required field '$requiredField'."
		}
	}

	if ($workshopFields.ContainsKey('appid') -and $workshopFields['appid'] -cne '394360') {
		Add-Failure "Workshop staging appid is '$($workshopFields['appid'])'; expected 394360."
	}
	if ($workshopFields.ContainsKey('publishedfileid') -and $workshopFields['publishedfileid'] -notmatch '^\d+$') {
		Add-Failure 'Workshop staging publishedfileid must be present and numeric; 0 is valid before the first upload.'
	}
	elseif ($usingWorkshopExample -and $workshopFields.ContainsKey('publishedfileid') -and $workshopFields['publishedfileid'] -cne '0') {
		Add-Failure "Public Workshop example publishedfileid is '$($workshopFields['publishedfileid'])'; expected 0."
	}

	$expectedContentFolder = [IO.Path]::GetFullPath($modRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
	$expectedPreviewFile = [IO.Path]::GetFullPath($thumbnailPath)
	if (-not $usingWorkshopExample) {
		if ($workshopFields.ContainsKey('contentfolder') -and $workshopFields['contentfolder'] -cne $expectedContentFolder) {
			Add-Failure "Workshop staging contentfolder is '$($workshopFields['contentfolder'])'; expected '$expectedContentFolder'."
		}
		if ($workshopFields.ContainsKey('previewfile') -and $workshopFields['previewfile'] -cne $expectedPreviewFile) {
			Add-Failure "Workshop staging previewfile is '$($workshopFields['previewfile'])'; expected '$expectedPreviewFile'."
		}
		if ($workshopFields.ContainsKey('previewfile') -and -not (Test-Path -LiteralPath $workshopFields['previewfile'] -PathType Leaf)) {
			Add-Failure "Workshop staging previewfile does not exist: $($workshopFields['previewfile'])"
		}
	}
	else {
		foreach ($portableField in @('contentfolder', 'previewfile')) {
			if ($workshopFields.ContainsKey($portableField) -and $workshopFields[$portableField] -notmatch '^(?:C:\\Path\\To\\|<ABSOLUTE_PATH_TO_REPOSITORY>)') {
				Add-Failure "Public Workshop example $portableField must use a portable absolute-path placeholder."
			}
		}
	}
	if ($workshopFields.ContainsKey('visibility') -and $workshopFields['visibility'] -cne '0') {
		Add-Failure "Workshop staging visibility is '$($workshopFields['visibility'])'; expected 0 (public)."
	}

	$descriptorNameMatch = [regex]::Match($descriptorText, '(?m)^\s*name\s*=\s*"([^"]+)"\s*$')
	if (-not $descriptorNameMatch.Success) {
		Add-Failure 'Mod descriptor has no parseable name for the Workshop title contract.'
	}
	elseif ($workshopFields.ContainsKey('title') -and $workshopFields['title'] -cne $descriptorNameMatch.Groups[1].Value) {
		Add-Failure "Workshop staging title '$($workshopFields['title'])' does not match descriptor name '$($descriptorNameMatch.Groups[1].Value)'."
	}
	foreach ($textField in @('description', 'changenote')) {
		if ($workshopFields.ContainsKey($textField) -and [string]::IsNullOrWhiteSpace($workshopFields[$textField])) {
			Add-Failure "Workshop staging $textField must not be empty."
		}
	}
	if ($workshopFields.ContainsKey('description') -and $workshopFields['description'] -notmatch '\b0\.6\.0\b') {
		Add-Failure 'Workshop staging description must identify release 0.6.0.'
	}
	$publicRepositoryUrl = 'https://github.com/corbett3289/HOI4AL-1'
	if ($workshopFields.ContainsKey('description') -and $workshopFields['description'] -notmatch [regex]::Escape($publicRepositoryUrl)) {
		Add-Failure "Workshop staging description must link the public source repository at $publicRepositoryUrl."
	}
	if ($workshopFields.ContainsKey('description') -and $workshopFields['description'] -notmatch '(?i)\b(?:unfinished|development|testing|playtesting)\b') {
		Add-Failure 'Workshop staging description must identify the item as an unfinished development/testing build.'
	}
	if (-not $usingWorkshopExample -and $workshopFields.ContainsKey('changenote') -and
		$workshopFields['changenote'] -match '(?i)overwhelming but finite convoy performance') {
		Add-Failure 'Workshop staging changenote must not claim an unsupported second convoy model or per-model statistics.'
	}
}

$projectReadmeText = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'README.md'))
$workshopReadmeText = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'Workshop\README.md'))
foreach ($readmeContract in @(
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = 'Development version:\s*\*\*0\.6\.0\*\*'; Label = 'project README development version' },
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = '(?i)Signals in the Noise'; Label = 'project README alien-news season description' },
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = '(?i)future XCOM\s+integration flag'; Label = 'project README XCOM boundary' },
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = '(?i)36-node\s+\*\*Consensus Sciences\*\* tree'; Label = 'project README Consensus Sciences description' },
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = '(?i)Tic Tac Fabrication\s+Lattice'; Label = 'project README Tic Tac research description' },
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = '(?i)HOI4 supports only one convoy equipment type'; Label = 'project README engine-hardcode disclosure' },
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = '(?i)supported\s+country-specific `convoy_1` variant system'; Label = 'project README supported variant architecture' },
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = '(?is)vanilla convoy resource costs, transfer/licensing\s+behavior'; Label = 'project README shared recipe and transfer limitation' },
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = '(?is)combat strip is staged for a future\s+engine-supported hook'; Label = 'project README staged combat-art limitation' },
	[pscustomobject]@{ Text = $projectReadmeText; Pattern = '(?i)public Workshop payload was\s+authenticated and matched all 324 local `Mod` files'; Label = 'project README public-build verification' },
	[pscustomobject]@{ Text = $workshopReadmeText; Pattern = '(?i)workshop_item_394360\.example\.vdf'; Label = 'Workshop README portable example' },
	[pscustomobject]@{ Text = $workshopReadmeText; Pattern = '(?i)Steam uses\s+`0`\s+for\s+Public'; Label = 'Workshop README public visibility guidance' },
	[pscustomobject]@{ Text = $workshopReadmeText; Pattern = '(?i)Steam Guard'; Label = 'Workshop README interactive authentication guidance' },
	[pscustomobject]@{ Text = $workshopReadmeText; Pattern = '(?i)0\.6\.0'; Label = 'Workshop README current development version' }
)) {
	if ($readmeContract.Text -notmatch $readmeContract.Pattern) {
		Add-Failure "Missing $($readmeContract.Label) contract."
	}
}
Add-Pass "Validated portable/public (visibility 0) Steam Workshop 0.6.0 metadata, source link, and documentation without repository-bound account state"

$staleMatches = rg -n -i 'stillwater|set_awareness_alert|awareness_alert|confirm_extraterrestrial' $modRoot 2>$null
if ($LASTEXITCODE -eq 0) {
    Add-Failure "Stale prototype identifiers remain:`n$($staleMatches -join "`n")"
}

if ($errors.Count -gt 0) {
    Write-Host "Alien Crisis validation FAILED ($($errors.Count) problem(s)):" -ForegroundColor Red
    foreach ($problem in $errors) {
        Write-Host "  - $problem" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Alien Crisis validation passed:" -ForegroundColor Green
foreach ($check in $checks) {
    Write-Host "  - $check"
}
