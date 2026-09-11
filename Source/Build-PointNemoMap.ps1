param(
    [string]$GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\Hearts of Iron IV"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$modRoot = Join-Path $projectRoot "Mod"
$sourceMap = Join-Path $GameRoot "map"
$targetMap = Join-Path $modRoot "map"

$provinceId = 13414
$stateId = 1082
$seaProvinceId = 601
$centerX = 1146
$centerY = 1875
$radiusX = 9
$radiusY = 6
$provinceRed = [byte]211
$provinceGreen = [byte]90
$provinceBlue = [byte]211

if (-not (Test-Path -LiteralPath $sourceMap)) {
    throw "HOI4 map directory was not found: $sourceMap"
}

New-Item -ItemType Directory -Path $targetMap -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $targetMap "strategicregions") -Force | Out-Null

foreach ($name in @(
    "provinces.bmp",
    "heightmap.bmp",
    "terrain.bmp",
    "rivers.bmp",
    "definition.csv",
    "buildings.txt",
    "unitstacks.txt",
    "supply_nodes.txt"
)) {
    Copy-Item -LiteralPath (Join-Path $sourceMap $name) -Destination (Join-Path $targetMap $name) -Force
}

Copy-Item `
    -LiteralPath (Join-Path $sourceMap "strategicregions\32-Southern Ocean.txt") `
    -Destination (Join-Path $targetMap "strategicregions\32-Southern Ocean.txt") `
    -Force

$pixels = [System.Collections.Generic.List[object]]::new()
for ($dy = -$radiusY; $dy -le $radiusY; $dy++) {
    for ($dx = -$radiusX; $dx -le $radiusX; $dx++) {
        $normalized = (($dx * $dx) / [double]($radiusX * $radiusX)) + (($dy * $dy) / [double]($radiusY * $radiusY))
        if ($normalized -le 1.0) {
            $pixels.Add([pscustomobject]@{
                X = $centerX + $dx
                Y = $centerY + $dy
                Distance = [Math]::Sqrt($normalized)
            })
        }
    }
}

function Get-BitmapMetadata {
    param(
        [Parameter(Mandatory)] [byte[]]$Bytes,
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [int]$ExpectedBitsPerPixel
    )

    if ($Bytes.Length -lt 54 -or [Text.Encoding]::ASCII.GetString($Bytes, 0, 2) -ne 'BM') {
        throw "Not a Windows BMP: $Path"
    }

    $pixelOffset = [BitConverter]::ToInt32($Bytes, 10)
    $width = [BitConverter]::ToInt32($Bytes, 18)
    $signedHeight = [BitConverter]::ToInt32($Bytes, 22)
    $bitsPerPixel = [BitConverter]::ToUInt16($Bytes, 28)
    $compression = [BitConverter]::ToInt32($Bytes, 30)

    if ($width -le 0 -or $signedHeight -eq 0) {
        throw "Invalid BMP dimensions in $Path."
    }
    if ($bitsPerPixel -ne $ExpectedBitsPerPixel) {
        throw "$Path is $bitsPerPixel bpp; expected $ExpectedBitsPerPixel bpp."
    }
    if ($compression -ne 0) {
        throw "$Path uses unsupported BMP compression $compression."
    }

    $height = [Math]::Abs($signedHeight)
    $rowStride = [int](([Math]::Floor((($width * $bitsPerPixel) + 31) / 32.0)) * 4)

    [pscustomobject]@{
        PixelOffset = $pixelOffset
        Width = $width
        Height = $height
        BottomUp = $signedHeight -gt 0
        BitsPerPixel = $bitsPerPixel
        RowStride = $rowStride
    }
}

$provincePath = Join-Path $targetMap "provinces.bmp"
$provinceBytes = [IO.File]::ReadAllBytes($provincePath)
$provinceMetadata = Get-BitmapMetadata -Bytes $provinceBytes -Path $provincePath -ExpectedBitsPerPixel 24
foreach ($pixel in $pixels) {
    $row = if ($provinceMetadata.BottomUp) { $provinceMetadata.Height - 1 - $pixel.Y } else { $pixel.Y }
    $offset = $provinceMetadata.PixelOffset + ($row * $provinceMetadata.RowStride) + ($pixel.X * 3)
    $existingBlue = $provinceBytes[$offset]
    $existingGreen = $provinceBytes[$offset + 1]
    $existingRed = $provinceBytes[$offset + 2]

    if ($existingRed -ne 3 -or $existingGreen -ne 8 -or $existingBlue -ne 236) {
        throw "Point Nemo patch escaped sea province $seaProvinceId at $($pixel.X),$($pixel.Y). Found RGB $existingRed,$existingGreen,$existingBlue."
    }

    $provinceBytes[$offset] = $provinceBlue
    $provinceBytes[$offset + 1] = $provinceGreen
    $provinceBytes[$offset + 2] = $provinceRed
}
[IO.File]::WriteAllBytes($provincePath, $provinceBytes)

function Set-IndexedPixels {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [scriptblock]$ValueForPixel
    )

    $bytes = [IO.File]::ReadAllBytes($Path)
    $metadata = Get-BitmapMetadata -Bytes $bytes -Path $Path -ExpectedBitsPerPixel 8

    foreach ($pixel in $pixels) {
        $row = if ($metadata.BottomUp) { $metadata.Height - 1 - $pixel.Y } else { $pixel.Y }
        $offset = $metadata.PixelOffset + ($row * $metadata.RowStride) + $pixel.X
        $bytes[$offset] = [byte](& $ValueForPixel $pixel)
    }

    [IO.File]::WriteAllBytes($Path, $bytes)
}

Set-IndexedPixels -Path (Join-Path $targetMap "heightmap.bmp") -ValueForPixel {
    param($pixel)
    [Math]::Round(100 + ((1.0 - $pixel.Distance) * 30))
}

Set-IndexedPixels -Path (Join-Path $targetMap "terrain.bmp") -ValueForPixel {
    param($pixel)
    # Palette index 1 is the vanilla plains/land color. Index 0 is the
    # diagnostic unknown-terrain color and must never be painted into the map.
    1
}

Set-IndexedPixels -Path (Join-Path $targetMap "rivers.bmp") -ValueForPixel {
    param($pixel)
    # 254 is vanilla no-river terrain at this location and on comparable
    # Pacific islands. Preserve that sentinel across the new land pixels.
    254
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)

$definitionPath = Join-Path $targetMap "definition.csv"
$definition = [IO.File]::ReadAllText($definitionPath)
if ($definition -match "(?m)^$provinceId;") {
    throw "Province ID $provinceId already exists in the copied definition.csv."
}
if ($definition -match "(?m)^\d+;211;90;211;") {
    throw "The selected Point Nemo province RGB is already in use."
}
[IO.File]::AppendAllText(
    $definitionPath,
    "`r`n$provinceId;211;90;211;land;true;plains;6`r`n",
    $utf8NoBom
)

$strategicRegionPath = Join-Path $targetMap "strategicregions\32-Southern Ocean.txt"
$strategicRegion = [IO.File]::ReadAllText($strategicRegionPath)
if ($strategicRegion -notmatch "(?m)^\s*$provinceId\s") {
    $strategicRegion = $strategicRegion -replace "provinces=\{\s*", "provinces={`r`n`t`t$provinceId "
    [IO.File]::WriteAllText($strategicRegionPath, $strategicRegion, $utf8NoBom)
}

$buildingPath = Join-Path $targetMap "buildings.txt"
$buildingLines = @(
    "$stateId;arms_factory;1142.00;10.50;174.00;0.45;0",
    "$stateId;arms_factory;1145.00;11.00;176.00;1.91;0",
    "$stateId;arms_factory;1149.00;10.50;175.00;3.47;0",
    "$stateId;arms_factory;1151.00;10.00;172.00;5.20;0",
    "$stateId;industrial_complex;1143.00;10.50;171.00;0.96;0",
    "$stateId;industrial_complex;1148.00;10.80;170.00;3.98;0",
    "$stateId;dockyard;1139.00;9.80;173.00;-1.57;0",
    "$stateId;dockyard;1140.00;9.80;170.00;-1.20;0",
    "$stateId;dockyard;1143.00;9.80;169.50;-0.70;0",
    "$stateId;dockyard;1149.00;9.80;169.50;0.70;0",
    "$stateId;dockyard;1152.00;9.80;171.00;1.20;0",
    "$stateId;dockyard;1153.00;9.80;174.00;1.57;0",
    "$stateId;air_base;1146.00;10.50;173.00;0.00;0",
    "$stateId;supply_node;1146.00;10.50;174.00;1.42;0",
    "$stateId;radar_station;1147.00;11.50;177.00;0.00;0",
    "$stateId;bunker;1148.00;10.50;176.00;5.96;0",
    "$stateId;coastal_bunker;1138.00;9.80;173.00;1.57;0",
    "$stateId;anti_air_building;1141.00;10.50;175.00;0.00;0",
    "$stateId;anti_air_building;1151.00;10.50;175.00;3.14;0",
    "$stateId;anti_air_building;1146.00;11.20;170.50;1.57;0",
    "$stateId;synthetic_refinery;1144.00;10.50;177.00;3.46;0",
    "$stateId;fuel_silo;1146.00;10.50;170.00;0.00;0",
    "$stateId;rocket_site_spawn;1150.00;10.50;174.00;5.52;0",
    "$stateId;nuclear_reactor_spawn;1142.00;10.50;171.00;0.79;0",
    "$stateId;floating_harbor;1136.00;9.80;175.00;-1.82;$provinceId",
    "$stateId;special_project_facility_spawn;1147.00;10.50;171.00;5.05;0",
    "$stateId;stronghold_network;1144.00;10.50;174.00;3.61;0",
    "$stateId;naval_supply_hub;1140.00;9.80;173.00;-1.57;0",
    # The locator itself must sit on land; the final field identifies the
    # adjacent sea province used by the port connection.
    "$stateId;naval_base_spawn;1138.00;9.80;172.00;-1.57;$seaProvinceId",
    "$stateId;naval_headquarters;1139.00;9.80;173.00;1.57;0"
)
# Vanilla buildings.txt has no terminal newline. A trailing CR/LF is parsed as
# an empty locator record and reports an invalid argument count at runtime.
[IO.File]::AppendAllText($buildingPath, "`r`n" + ($buildingLines -join "`r`n"), $utf8NoBom)

$unitStackByType = @{
    # Canonical tiny-island land subset. Sea-only and large-landform stack
    # types are deliberately absent, matching vanilla and total conversions.
    0 = "$provinceId;0;1146.00;10.50;173.00;0.00;0.36"
    1 = "$provinceId;1;1146.50;10.50;173.00;1.57;0.36"
    9 = "$provinceId;9;1142.00;10.50;173.00;1.57;0.36"
    10 = "$provinceId;10;1150.00;10.50;173.00;-1.57;0.36"
    21 = "$provinceId;21;1143.00;10.50;173.00;0.00;0.36"
    22 = "$provinceId;22;1146.50;10.50;173.00;1.57;0.36"
    38 = "$provinceId;38;1141.80;10.50;170.60;-1.57;0.36"
}

# unitstacks.txt is grouped by stack type, and the engine builds one lookup
# array per contiguous block. Insert the new island anchors at the end of their
# corresponding blocks instead of appending mixed types at end-of-file.
$unitStackPath = Join-Path $targetMap "unitstacks.txt"
$sourceUnitStackLines = [IO.File]::ReadAllLines($unitStackPath)
$outputUnitStackLines = [System.Collections.Generic.List[string]]::new($sourceUnitStackLines.Length + $unitStackByType.Count)
$insertedUnitStackTypes = [System.Collections.Generic.HashSet[int]]::new()
$previousType = $null

foreach ($line in $sourceUnitStackLines) {
    $currentType = $null
    if ($line -match '^\d+;(\d+);') {
        $currentType = [int]$Matches[1]
    }

    if ($null -ne $previousType -and $null -ne $currentType -and $currentType -ne $previousType) {
        if ($currentType -ne ($previousType + 1)) {
            throw "Unexpected unit-stack type transition $previousType -> $currentType."
        }
        if ($unitStackByType.ContainsKey($previousType)) {
            $outputUnitStackLines.Add($unitStackByType[$previousType])
            [void]$insertedUnitStackTypes.Add($previousType)
        }
    }

    $outputUnitStackLines.Add($line)
    if ($null -ne $currentType) {
        $previousType = $currentType
    }
}

if ($null -ne $previousType -and $unitStackByType.ContainsKey($previousType)) {
    $outputUnitStackLines.Add($unitStackByType[$previousType])
    [void]$insertedUnitStackTypes.Add($previousType)
}

$expectedUnitStackTypes = @($unitStackByType.Keys | Sort-Object)
$missingUnitStackTypes = @($expectedUnitStackTypes | Where-Object { -not $insertedUnitStackTypes.Contains($_) })
if ($missingUnitStackTypes.Count -gt 0) {
    throw "Vanilla unitstacks.txt is missing expected type group(s): $($missingUnitStackTypes -join ', ')."
}

[IO.File]::WriteAllLines($unitStackPath, $outputUnitStackLines, $utf8NoBom)

[IO.File]::AppendAllText(
    (Join-Path $targetMap "supply_nodes.txt"),
    "`r`n1 $provinceId`r`n",
    $utf8NoBom
)

Write-Host "Generated Point Nemo map layer:"
Write-Host "  Province $provinceId at bitmap $centerX,$centerY (sea province $seaProvinceId)"
Write-Host "  State reservation $stateId"
Write-Host "  Output $targetMap"
