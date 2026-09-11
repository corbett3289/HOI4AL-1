param()

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$masterRoot = Join-Path $projectRoot "Source\Art\Masters"
$previewRoot = Join-Path $projectRoot "Source\Art\Preview"
$modRoot = Join-Path $projectRoot "Mod"

Add-Type -AssemblyName System.Drawing.Common

New-Item -ItemType Directory -Path $previewRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\leaders\XAC") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\leaders\XAC\Operatives") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\flags\medium") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\flags\small") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\coi_alien") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\traits") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\operatives\agencies") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\operatives\icons") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\operations") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\operations\images") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\operations\phases_small") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\mapicons") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\navalcombat\ships") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\counters\ships_small") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\ideas") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\special_project\project_icons") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\interface\special_project\blueprints") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\texticons") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $modRoot "gfx\event_pictures") -Force | Out-Null

function Get-CoverRectangle {
    param(
        [Parameter(Mandatory)] [System.Drawing.Image]$Image,
        [Parameter(Mandatory)] [int]$TargetWidth,
        [Parameter(Mandatory)] [int]$TargetHeight
    )

    $sourceAspect = $Image.Width / [double]$Image.Height
    $targetAspect = $TargetWidth / [double]$TargetHeight

    if ($sourceAspect -gt $targetAspect) {
        $height = $Image.Height
        $width = [int][Math]::Round($height * $targetAspect)
        $x = [int][Math]::Round(($Image.Width - $width) / 2.0)
        return [System.Drawing.Rectangle]::new($x, 0, $width, $height)
    }

    $width = $Image.Width
    $height = [int][Math]::Round($width / $targetAspect)
    $y = [int][Math]::Round(($Image.Height - $height) / 2.0)
    return [System.Drawing.Rectangle]::new(0, $y, $width, $height)
}

function New-RenderedBitmap {
    param(
        [Parameter(Mandatory)] [string]$SourcePath,
        [Parameter(Mandatory)] [int]$Width,
        [Parameter(Mandatory)] [int]$Height,
        [ValidateSet("Cover", "Contain", "Stretch")] [string]$Mode = "Cover",
        [System.Drawing.Color]$Background = [System.Drawing.Color]::Transparent
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Art master is missing: $SourcePath"
    }

    $source = [System.Drawing.Bitmap]::new($SourcePath)
    $target = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($target)

    try {
        $graphics.Clear($Background)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        switch ($Mode) {
            "Cover" {
                $sourceRectangle = Get-CoverRectangle -Image $source -TargetWidth $Width -TargetHeight $Height
                $destinationRectangle = [System.Drawing.Rectangle]::new(0, 0, $Width, $Height)
            }
            "Contain" {
                $scale = [Math]::Min($Width / [double]$source.Width, $Height / [double]$source.Height)
                $renderWidth = [int][Math]::Round($source.Width * $scale)
                $renderHeight = [int][Math]::Round($source.Height * $scale)
                $destinationRectangle = [System.Drawing.Rectangle]::new(
                    [int][Math]::Round(($Width - $renderWidth) / 2.0),
                    [int][Math]::Round(($Height - $renderHeight) / 2.0),
                    $renderWidth,
                    $renderHeight
                )
                $sourceRectangle = [System.Drawing.Rectangle]::new(0, 0, $source.Width, $source.Height)
            }
            "Stretch" {
                $sourceRectangle = [System.Drawing.Rectangle]::new(0, 0, $source.Width, $source.Height)
                $destinationRectangle = [System.Drawing.Rectangle]::new(0, 0, $Width, $Height)
            }
        }

        $graphics.DrawImage(
            $source,
            $destinationRectangle,
            $sourceRectangle.X,
            $sourceRectangle.Y,
            $sourceRectangle.Width,
            $sourceRectangle.Height,
            [System.Drawing.GraphicsUnit]::Pixel
        )
    }
    finally {
        $graphics.Dispose()
        $source.Dispose()
    }

    return $target
}

function Get-AlphaRectangle {
    param(
        [Parameter(Mandatory)] [System.Drawing.Bitmap]$Bitmap,
        [byte]$Threshold = 8
    )

    $minimumX = $Bitmap.Width
    $minimumY = $Bitmap.Height
    $maximumX = -1
    $maximumY = -1
    $rectangle = [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
    $data = $Bitmap.LockBits(
        $rectangle,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $row = [byte[]]::new($Bitmap.Width * 4)
        for ($y = 0; $y -lt $Bitmap.Height; $y++) {
            $sourceY = if ($data.Stride -ge 0) { $y } else { $Bitmap.Height - 1 - $y }
            $pointer = [IntPtr]::Add($data.Scan0, $sourceY * [Math]::Abs($data.Stride))
            [Runtime.InteropServices.Marshal]::Copy($pointer, $row, 0, $row.Length)

            for ($x = 0; $x -lt $Bitmap.Width; $x++) {
                if ($row[($x * 4) + 3] -le $Threshold) {
                    continue
                }
                if ($x -lt $minimumX) { $minimumX = $x }
                if ($x -gt $maximumX) { $maximumX = $x }
                if ($y -lt $minimumY) { $minimumY = $y }
                if ($y -gt $maximumY) { $maximumY = $y }
            }
        }
    }
    finally {
        $Bitmap.UnlockBits($data)
    }

    if ($maximumX -lt $minimumX -or $maximumY -lt $minimumY) {
        throw "Bitmap contains no visible pixels."
    }

    # Preserve the faint antialiased fringe immediately around the thresholded
    # subject without admitting remote near-transparent generation speckles.
    $left = [Math]::Max(0, $minimumX - 4)
    $top = [Math]::Max(0, $minimumY - 4)
    $right = [Math]::Min($Bitmap.Width, $maximumX + 5)
    $bottom = [Math]::Min($Bitmap.Height, $maximumY + 5)
    return [System.Drawing.Rectangle]::FromLTRB($left, $top, $right, $bottom)
}

function New-TrimmedRenderedBitmap {
    param(
        [Parameter(Mandatory)] [string]$SourcePath,
        [Parameter(Mandatory)] [int]$Width,
        [Parameter(Mandatory)] [int]$Height,
        [ValidateSet("Contain", "Cover", "Stretch")] [string]$Mode = "Contain",
        [int]$PaddingX = 0,
        [int]$PaddingY = 0
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Art master is missing: $SourcePath"
    }

    $availableWidth = $Width - (2 * $PaddingX)
    $availableHeight = $Height - (2 * $PaddingY)
    if ($availableWidth -le 0 -or $availableHeight -le 0) {
        throw "Padding leaves no drawable area in ${Width}x${Height}."
    }

    $source = [System.Drawing.Bitmap]::new($SourcePath)
    $sourceRectangle = Get-AlphaRectangle -Bitmap $source
    $target = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($target)

    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        if ($Mode -eq "Contain") {
            $scale = [Math]::Min(
                $availableWidth / [double]$sourceRectangle.Width,
                $availableHeight / [double]$sourceRectangle.Height
            )
            $renderWidth = [Math]::Max(1, [int][Math]::Round($sourceRectangle.Width * $scale))
            $renderHeight = [Math]::Max(1, [int][Math]::Round($sourceRectangle.Height * $scale))
            $destinationRectangle = [System.Drawing.Rectangle]::new(
                [int][Math]::Round(($Width - $renderWidth) / 2.0),
                [int][Math]::Round(($Height - $renderHeight) / 2.0),
                $renderWidth,
                $renderHeight
            )
        }
        elseif ($Mode -eq "Cover") {
            # Square technology icons need a tight, center-weighted crop of a
            # wide transparent subject rather than the empty source canvas.
            $scale = [Math]::Max(
                $availableWidth / [double]$sourceRectangle.Width,
                $availableHeight / [double]$sourceRectangle.Height
            )
            $renderWidth = [Math]::Max(1, [int][Math]::Round($sourceRectangle.Width * $scale))
            $renderHeight = [Math]::Max(1, [int][Math]::Round($sourceRectangle.Height * $scale))
            $destinationRectangle = [System.Drawing.Rectangle]::new(
                $PaddingX + [int][Math]::Round(($availableWidth - $renderWidth) / 2.0),
                $PaddingY + [int][Math]::Round(($availableHeight - $renderHeight) / 2.0),
                $renderWidth,
                $renderHeight
            )
        }
        else {
            # Tiny HOI4 ship silhouettes have class-specific canonical aspect
            # ratios. Stretch only the alpha-trimmed ship, not the source canvas,
            # so each design remains legible inside its required frame.
            $destinationRectangle = [System.Drawing.Rectangle]::new(
                $PaddingX,
                $PaddingY,
                $availableWidth,
                $availableHeight
            )
        }

        $graphics.DrawImage(
            $source,
            $destinationRectangle,
            $sourceRectangle.X,
            $sourceRectangle.Y,
            $sourceRectangle.Width,
            $sourceRectangle.Height,
            [System.Drawing.GraphicsUnit]::Pixel
        )
    }
    finally {
        $graphics.Dispose()
        $source.Dispose()
    }

    return $target
}

function New-TintedBitmap {
    param(
        [Parameter(Mandatory)] [System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)] [System.Drawing.Color]$Tint,
        [switch]$PreserveLuminance
    )

    $target = [System.Drawing.Bitmap]::new(
        $Bitmap.Width,
        $Bitmap.Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $rectangle = [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
    $sourceData = $Bitmap.LockBits(
        $rectangle,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $targetData = $target.LockBits(
        $rectangle,
        [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $sourceRow = [byte[]]::new($Bitmap.Width * 4)
        $targetRow = [byte[]]::new($Bitmap.Width * 4)
        for ($y = 0; $y -lt $Bitmap.Height; $y++) {
            $sourceY = if ($sourceData.Stride -ge 0) { $y } else { $Bitmap.Height - 1 - $y }
            $targetY = if ($targetData.Stride -ge 0) { $y } else { $Bitmap.Height - 1 - $y }
            $sourcePointer = [IntPtr]::Add($sourceData.Scan0, $sourceY * [Math]::Abs($sourceData.Stride))
            $targetPointer = [IntPtr]::Add($targetData.Scan0, $targetY * [Math]::Abs($targetData.Stride))
            [Runtime.InteropServices.Marshal]::Copy($sourcePointer, $sourceRow, 0, $sourceRow.Length)

            for ($x = 0; $x -lt $Bitmap.Width; $x++) {
                $offset = $x * 4
                $sourceAlpha = $sourceRow[$offset + 3]
                if ($sourceAlpha -eq 0) {
                    $targetRow[$offset] = 0
                    $targetRow[$offset + 1] = 0
                    $targetRow[$offset + 2] = 0
                    $targetRow[$offset + 3] = 0
                    continue
                }

                $shade = 1.0
                if ($PreserveLuminance) {
                    $luminance = (
                        (77 * $sourceRow[$offset + 2]) +
                        (150 * $sourceRow[$offset + 1]) +
                        (29 * $sourceRow[$offset]) +
                        128
                    ) -shr 8
                    $shade = 0.60 + (0.40 * ($luminance / 255.0))
                }

                $targetRow[$offset] = [byte][Math]::Round($Tint.B * $shade)
                $targetRow[$offset + 1] = [byte][Math]::Round($Tint.G * $shade)
                $targetRow[$offset + 2] = [byte][Math]::Round($Tint.R * $shade)
                $targetRow[$offset + 3] = [byte][Math]::Round($sourceAlpha * ($Tint.A / 255.0))
            }
            [Runtime.InteropServices.Marshal]::Copy($targetRow, 0, $targetPointer, $targetRow.Length)
        }
    }
    finally {
        $Bitmap.UnlockBits($sourceData)
        $target.UnlockBits($targetData)
    }

    return $target
}

function New-ShipGlyph {
    param(
        [Parameter(Mandatory)] [string]$SourcePath,
        [Parameter(Mandatory)] [int]$Width,
        [Parameter(Mandatory)] [int]$Height,
        [Parameter(Mandatory)] [System.Drawing.Color]$Foreground,
        [Parameter(Mandatory)] [System.Drawing.Color]$Shadow
    )

    $mask = New-TrimmedRenderedBitmap `
        -SourcePath $SourcePath `
        -Width ($Width - 1) `
        -Height ($Height - 1) `
        -Mode Stretch `
        -PaddingX 1 `
        -PaddingY 1
    $foregroundBitmap = New-TintedBitmap -Bitmap $mask -Tint $Foreground -PreserveLuminance
    $shadowBitmap = New-TintedBitmap -Bitmap $mask -Tint $Shadow
    $target = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($target)

    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.DrawImageUnscaled($shadowBitmap, 1, 1)
        $graphics.DrawImageUnscaled($foregroundBitmap, 0, 0)
    }
    finally {
        $graphics.Dispose()
        $shadowBitmap.Dispose()
        $foregroundBitmap.Dispose()
        $mask.Dispose()
    }

    return $target
}

function New-MirroredShipStrip {
    param(
        [Parameter(Mandatory)] [string]$SourcePath,
        [Parameter(Mandatory)] [int]$FrameWidth,
        [Parameter(Mandatory)] [int]$Height,
        [Parameter(Mandatory)] [bool]$SourceFacesLeft
    )

    $sourceFrame = New-TrimmedRenderedBitmap `
        -SourcePath $SourcePath `
        -Width $FrameWidth `
        -Height $Height `
        -Mode Stretch `
        -PaddingX 2 `
        -PaddingY 1
    $leftFrame = [System.Drawing.Bitmap]$sourceFrame.Clone()
    $rightFrame = [System.Drawing.Bitmap]$sourceFrame.Clone()
    if ($SourceFacesLeft) {
        $rightFrame.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX)
    }
    else {
        $leftFrame.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX)
    }

    $strip = [System.Drawing.Bitmap]::new(
        $FrameWidth * 2,
        $Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($strip)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.DrawImageUnscaled($leftFrame, 0, 0)
        $graphics.DrawImageUnscaled($rightFrame, $FrameWidth, 0)
    }
    finally {
        $graphics.Dispose()
        $rightFrame.Dispose()
        $leftFrame.Dispose()
        $sourceFrame.Dispose()
    }

    return $strip
}

function Write-DdsArgb {
    param(
        [Parameter(Mandatory)] [System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)] [string]$Path
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = [IO.BinaryWriter]::new($stream)
    $rectangle = [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
    $data = $Bitmap.LockBits(
        $rectangle,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes("DDS "))
        $writer.Write([uint32]124)
        $writer.Write([uint32]0x0000100F)
        $writer.Write([uint32]$Bitmap.Height)
        $writer.Write([uint32]$Bitmap.Width)
        $writer.Write([uint32]($Bitmap.Width * 4))
        $writer.Write([uint32]0)
        $writer.Write([uint32]0)
        for ($index = 0; $index -lt 11; $index++) { $writer.Write([uint32]0) }
        $writer.Write([uint32]32)
        $writer.Write([uint32]0x00000041)
        $writer.Write([uint32]0)
        $writer.Write([uint32]32)
        $writer.Write([uint32]0x00FF0000)
        $writer.Write([uint32]0x0000FF00)
        $writer.Write([uint32]0x000000FF)
        $writer.Write([uint32]4278190080)
        $writer.Write([uint32]0x00001000)
        $writer.Write([uint32]0)
        $writer.Write([uint32]0)
        $writer.Write([uint32]0)
        $writer.Write([uint32]0)

        $rowSize = $Bitmap.Width * 4
        $row = [byte[]]::new($rowSize)
        for ($y = 0; $y -lt $Bitmap.Height; $y++) {
            $sourceY = if ($data.Stride -ge 0) { $y } else { $Bitmap.Height - 1 - $y }
            $pointer = [IntPtr]::Add($data.Scan0, $sourceY * [Math]::Abs($data.Stride))
            [Runtime.InteropServices.Marshal]::Copy($pointer, $row, 0, $rowSize)
            $writer.Write($row)
        }
    }
    finally {
        $Bitmap.UnlockBits($data)
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Write-Tga32 {
    param(
        [Parameter(Mandatory)] [System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)] [string]$Path
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = [IO.BinaryWriter]::new($stream)
    $rectangle = [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
    $data = $Bitmap.LockBits(
        $rectangle,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([byte]2)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]$Bitmap.Width)
        $writer.Write([uint16]$Bitmap.Height)
		# HOI4 accepts uncompressed true-color TGA. Keep eight alpha bits and a
		# top-left origin so the in-memory BGRA rows can be written unchanged.
		$writer.Write([byte]32)
		$writer.Write([byte]0x28)

		$sourceRow = [byte[]]::new($Bitmap.Width * 4)
		for ($y = 0; $y -lt $Bitmap.Height; $y++) {
			$sourceY = if ($data.Stride -ge 0) { $y } else { $Bitmap.Height - 1 - $y }
			$pointer = [IntPtr]::Add($data.Scan0, $sourceY * [Math]::Abs($data.Stride))
			[Runtime.InteropServices.Marshal]::Copy($pointer, $sourceRow, 0, $sourceRow.Length)
			$writer.Write($sourceRow)
        }
    }
    finally {
        $Bitmap.UnlockBits($data)
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Save-Preview {
    param(
        [Parameter(Mandatory)] [System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)] [string]$Name
    )
    $Bitmap.Save((Join-Path $previewRoot "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
}

function New-AlienAgencyLogoSheet {
    param(
        [Parameter(Mandatory)] [string]$SourcePath
    )

    # Agency logos are an engine-defined 233x119, two-frame horizontal sheet.
    # Match vanilla's intentionally odd total width: a 116px normal frame and
    # a 117px highlighted frame.
    $normal = New-RenderedBitmap -SourcePath $SourcePath -Width 104 -Height 104 -Mode Contain
    $sheet = [System.Drawing.Bitmap]::new(233, 119, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($sheet)

    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $normalPlate = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(185, 20, 28, 31))
        $selectedGlow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(85, 91, 220, 231))
        $selectedPlate = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(215, 20, 30, 34))
        try {
            $graphics.FillEllipse($normalPlate, 7, 10, 102, 99)
            $graphics.DrawImage($normal, 6, 8, 104, 104)

            $graphics.FillEllipse($selectedGlow, 119, 4, 112, 111)
            $graphics.FillEllipse($selectedPlate, 124, 10, 102, 99)
            $graphics.DrawImage($normal, 123, 8, 104, 104)
        }
        finally {
            $normalPlate.Dispose()
            $selectedGlow.Dispose()
            $selectedPlate.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
        $normal.Dispose()
    }

    return $sheet
}

$portraitNames = @("eir", "vael", "thren", "oru", "saal")
foreach ($name in $portraitNames) {
    $master = Join-Path $masterRoot "coi_alien_$name.png"

    $large = New-RenderedBitmap -SourcePath $master -Width 156 -Height 210 -Mode Cover
    Save-Preview -Bitmap $large -Name "portrait_$name"
    Write-DdsArgb -Bitmap $large -Path (Join-Path $modRoot "gfx\leaders\XAC\coi_alien_$name.dds")
    $large.Dispose()

    $small = New-RenderedBitmap -SourcePath $master -Width 65 -Height 67 -Mode Cover
    Save-Preview -Bitmap $small -Name "portrait_${name}_small"
    Write-DdsArgb -Bitmap $small -Path (Join-Path $modRoot "gfx\leaders\XAC\coi_alien_${name}_small.dds")
    $small.Dispose()
}

$operativePortraitNames = @(
    "neth_witness",
    "ysil_lattice",
    "cael_current",
    "drone_quiet_orbit",
    "drone_pale_echo",
    "drone_outer_witness",
    "facsimile_lena_marlow",
    "facsimile_daniel_voss"
)
foreach ($name in $operativePortraitNames) {
    $master = Join-Path $masterRoot "coi_alien_$name.png"
    $portrait = New-RenderedBitmap -SourcePath $master -Width 156 -Height 210 -Mode Cover
    Save-Preview -Bitmap $portrait -Name "operative_$name"
    Write-DdsArgb `
        -Bitmap $portrait `
        -Path (Join-Path $modRoot "gfx\leaders\XAC\Operatives\coi_alien_$name.dds")
    $portrait.Dispose()
}

$droneTrait = New-TrimmedRenderedBitmap `
    -SourcePath (Join-Path $masterRoot "coi_alien_trait_autonomous_infiltration_drone.png") `
    -Width 23 `
    -Height 33 `
    -Mode Contain `
    -PaddingX 1 `
    -PaddingY 1
Save-Preview -Bitmap $droneTrait -Name "trait_autonomous_infiltration_drone"
Write-DdsArgb `
    -Bitmap $droneTrait `
    -Path (Join-Path $modRoot "gfx\interface\traits\coi_alien_trait_autonomous_infiltration_drone.dds")
$droneTrait.Dispose()

$facsimileTrait = New-TrimmedRenderedBitmap `
    -SourcePath (Join-Path $masterRoot "coi_alien_sp_viable_adult_clone.png") `
    -Width 23 `
    -Height 33 `
    -Mode Contain `
    -PaddingX 1 `
    -PaddingY 1
Save-Preview -Bitmap $facsimileTrait -Name "trait_conditioned_human_facsimile"
Write-DdsArgb `
    -Bitmap $facsimileTrait `
    -Path (Join-Path $modRoot "gfx\interface\traits\coi_alien_trait_conditioned_human_facsimile.dds")
$facsimileTrait.Dispose()

$agencyLogo = New-AlienAgencyLogoSheet `
    -SourcePath (Join-Path $masterRoot "coi_alien_flag_master.png")
Save-Preview -Bitmap $agencyLogo -Name "agency_quiet_chorus"
Write-DdsArgb `
    -Bitmap $agencyLogo `
    -Path (Join-Path $modRoot "gfx\interface\operatives\agencies\coi_alien_quiet_chorus.dds")
$agencyLogo.Dispose()

$equipment = @{
    pale_horizon = "coi_alien_pale_horizon_ui_v3.png"
    silent_current = "coi_alien_silent_current_ui_v3.png"
    needle = "coi_alien_needle.png"
    gleam = "coi_alien_gleam.png"
}

foreach ($name in $equipment.Keys) {
    $bitmap = New-RenderedBitmap `
        -SourcePath (Join-Path $masterRoot $equipment[$name]) `
        -Width 146 `
        -Height 54 `
        -Mode Contain
    Save-Preview -Bitmap $bitmap -Name "equipment_$name"
    Write-DdsArgb -Bitmap $bitmap -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_${name}.dds")
    $bitmap.Dispose()
}

$technologyIcons = @{
    adaptive_metamaterials = "coi_alien_tech_adaptive_metamaterials.png"
    inertial_field_theory = "coi_alien_tech_inertial_field_theory.png"
    coherent_energy_control = "coi_alien_tech_coherent_energy_control.png"
    predictive_computation = "coi_alien_tech_predictive_computation.png"
    human_sciences = "coi_alien_tech_human_sciences.png"
    fabrication = "coi_alien_tech_fabrication.png"
}

foreach ($name in $technologyIcons.Keys) {
    $bitmap = New-RenderedBitmap `
        -SourcePath (Join-Path $masterRoot $technologyIcons[$name]) `
        -Width 64 `
        -Height 64 `
        -Mode Contain
    Save-Preview -Bitmap $bitmap -Name "technology_$name"
    Write-DdsArgb -Bitmap $bitmap -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_tech_${name}.dds")
    $bitmap.Dispose()
}

# The Tic Tac logistics craft uses one transparent master for all three native
# UI contracts. Preserve the complete silhouette for equipment, crop tightly
# around its central field generator for research, and mirror its combat frame
# so the two-frame naval strip reads correctly in either engagement direction.
$ticTacMaster = Join-Path $masterRoot "coi_alien_tic_tac_convoy.png"

$ticTacEquipment = New-TrimmedRenderedBitmap `
    -SourcePath $ticTacMaster `
    -Width 146 `
    -Height 54 `
    -Mode Contain `
    -PaddingX 4 `
    -PaddingY 2
Save-Preview -Bitmap $ticTacEquipment -Name "equipment_tic_tac_convoy"
Write-DdsArgb `
    -Bitmap $ticTacEquipment `
    -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_tic_tac_convoy.dds")
$ticTacEquipment.Dispose()

$ticTacTechnology = New-TrimmedRenderedBitmap `
    -SourcePath $ticTacMaster `
    -Width 64 `
    -Height 64 `
    -Mode Cover
Save-Preview -Bitmap $ticTacTechnology -Name "technology_tic_tac_fabrication"
Write-DdsArgb `
    -Bitmap $ticTacTechnology `
    -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_tech_tic_tac_fabrication.dds")
$ticTacTechnology.Dispose()

$ticTacCombatStrip = New-MirroredShipStrip `
    -SourcePath $ticTacMaster `
    -FrameWidth 52 `
    -Height 17 `
    -SourceFacesLeft $false
Save-Preview -Bitmap $ticTacCombatStrip -Name "navalcombat_strip_tic_tac_convoy"
Write-DdsArgb `
    -Bitmap $ticTacCombatStrip `
    -Path (Join-Path $modRoot "gfx\interface\navalcombat\ships\coi_alien_tic_tac_convoy.dds")
$ticTacCombatStrip.Dispose()

# Quiet Chorus operation art is derived from eight image-generated transparent
# emblem masters. Each master feeds the four native La Resistance UI contracts:
# operation list, map marker, small phase badge, and large phase report picture.
$operationArt = [ordered]@{
    silent_systems_survey = "coi_alien_operation_silent_systems_survey.png"
    seed_mimetic_access = "coi_alien_operation_seed_mimetic_access.png"
    penetrate_research_networks = "coi_alien_operation_penetrate_research_networks.png"
    spoil_the_evidence = "coi_alien_operation_spoil_the_evidence.png"
    introduce_cascading_faults = "coi_alien_operation_introduce_cascading_faults.png"
    harvest_project_archives = "coi_alien_operation_harvest_project_archives.png"
    disrupt_research_complex = "coi_alien_operation_disrupt_research_complex.png"
    extract_lead_scientist = "coi_alien_operation_extract_lead_scientist.png"
}

foreach ($name in $operationArt.Keys) {
    $masterPath = Join-Path $masterRoot $operationArt[$name]

    $operationIcon = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 85 `
        -Height 85 `
        -Mode Contain `
        -PaddingX 5 `
        -PaddingY 5
    Save-Preview -Bitmap $operationIcon -Name "operation_$name"
    Write-DdsArgb `
        -Bitmap $operationIcon `
        -Path (Join-Path $modRoot "gfx\interface\operations\coi_alien_operation_$name.dds")
    $operationIcon.Dispose()

    $mapIcon = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 48 `
        -Height 48 `
        -Mode Contain `
        -PaddingX 3 `
        -PaddingY 3
    Save-Preview -Bitmap $mapIcon -Name "operation_${name}_map"
    Write-DdsArgb `
        -Bitmap $mapIcon `
        -Path (Join-Path $modRoot "gfx\interface\mapicons\coi_alien_operation_${name}_map.dds")
    $mapIcon.Dispose()

    $phaseIcon = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 59 `
        -Height 58 `
        -Mode Contain `
        -PaddingX 4 `
        -PaddingY 4
    Save-Preview -Bitmap $phaseIcon -Name "operation_${name}_phase_icon"
    Write-DdsArgb `
        -Bitmap $phaseIcon `
        -Path (Join-Path $modRoot "gfx\interface\operations\phases_small\coi_alien_operation_${name}_phase_icon.dds")
    $phaseIcon.Dispose()

    $phasePicture = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 210 `
        -Height 176 `
        -Mode Contain `
        -PaddingX 14 `
        -PaddingY 10
    Save-Preview -Bitmap $phasePicture -Name "operation_${name}_phase_picture"
    Write-DdsArgb `
        -Bitmap $phasePicture `
        -Path (Join-Path $modRoot "gfx\interface\operations\images\coi_alien_operation_${name}_phase_picture.dds")
    $phasePicture.Dispose()
}

# Access tokens reuse the visual language of the survey, identity-insertion, and
# research-penetration operations. Both the dossier icon and inline text icon are
# required by the operation-token database.
$operationTokens = [ordered]@{
    surface_profile = $operationArt.silent_systems_survey
    institutional_access = $operationArt.seed_mimetic_access
    research_access = $operationArt.penetrate_research_networks
}

foreach ($name in $operationTokens.Keys) {
    $masterPath = Join-Path $masterRoot $operationTokens[$name]

    $tokenIcon = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 33 `
        -Height 29 `
        -Mode Contain `
        -PaddingX 1 `
        -PaddingY 1
    Save-Preview -Bitmap $tokenIcon -Name "operation_token_$name"
    Write-DdsArgb `
        -Bitmap $tokenIcon `
        -Path (Join-Path $modRoot "gfx\interface\operations\coi_alien_token_$name.dds")
    $tokenIcon.Dispose()

    $tokenTextIcon = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 24 `
        -Height 21 `
        -Mode Contain `
        -PaddingX 1 `
        -PaddingY 1
    Save-Preview -Bitmap $tokenTextIcon -Name "operation_token_${name}_text"
    Write-DdsArgb `
        -Bitmap $tokenTextIcon `
        -Path (Join-Path $modRoot "gfx\texticons\coi_alien_token_${name}_text.dds")
    $tokenTextIcon.Dispose()
}

# Three XAC-only agency upgrades use dedicated 68x68 emblems while staying
# visually linked to the operations they unlock.
$agencyUpgradeArt = [ordered]@{
    mimetic_interface_lab = $operationArt.seed_mimetic_access
    cognitive_translation_matrix = $operationArt.penetrate_research_networks
    distributed_drone_cells = $operationArt.introduce_cascading_faults
}

foreach ($name in $agencyUpgradeArt.Keys) {
    $upgradeIcon = New-TrimmedRenderedBitmap `
        -SourcePath (Join-Path $masterRoot $agencyUpgradeArt[$name]) `
        -Width 68 `
        -Height 68 `
        -Mode Contain `
        -PaddingX 4 `
        -PaddingY 4
    Save-Preview -Bitmap $upgradeIcon -Name "agency_upgrade_$name"
    Write-DdsArgb `
        -Bitmap $upgradeIcon `
        -Path (Join-Path $modRoot "gfx\interface\operatives\icons\coi_alien_upgrade_$name.dds")
    $upgradeIcon.Dispose()
}

# Each custom sub-unit sprite token drives four separate engine UI contracts.
# Keep all of them derived from the final transparent v3 ship masters:
#   * 50x34 navy/leader roster art;
#   * class-sized two-frame mirrored naval-combat/selected-fleet strips;
#   * 30x12 white and black compact counters;
#   * 30x12 teal inline texticons.
$navalUiShips = @(
    @{
        Name = "mothership"
        Master = "coi_alien_pale_horizon_ui_v3.png"
        FrameWidth = 80
        FrameHeight = 19
        SourceFacesLeft = $false
    },
    @{
        Name = "escort"
        Master = "coi_alien_silent_current_ui_v3.png"
        FrameWidth = 43
        FrameHeight = 18
        SourceFacesLeft = $true
    }
)

$counterForeground = [System.Drawing.Color]::FromArgb(255, 242, 248, 248)
$counterShadow = [System.Drawing.Color]::FromArgb(180, 0, 0, 0)
$invertedCounterForeground = [System.Drawing.Color]::FromArgb(255, 18, 24, 26)
$invertedCounterShadow = [System.Drawing.Color]::FromArgb(180, 255, 255, 255)
$texticonForeground = [System.Drawing.Color]::FromArgb(255, 104, 220, 213)
$texticonShadow = [System.Drawing.Color]::FromArgb(190, 0, 0, 0)

foreach ($ship in $navalUiShips) {
    $name = $ship.Name
    $masterPath = Join-Path $masterRoot $ship.Master

    $roster = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 50 `
        -Height 34 `
        -Mode Contain `
        -PaddingX 1 `
        -PaddingY 1
    Save-Preview -Bitmap $roster -Name "navy_icon_$name"
    Write-DdsArgb `
        -Bitmap $roster `
        -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_${name}_navy_icon.dds")
    $roster.Dispose()

    $strip = New-MirroredShipStrip `
        -SourcePath $masterPath `
        -FrameWidth $ship.FrameWidth `
        -Height $ship.FrameHeight `
        -SourceFacesLeft $ship.SourceFacesLeft
    Save-Preview -Bitmap $strip -Name "navalcombat_strip_$name"
    Write-DdsArgb `
        -Bitmap $strip `
        -Path (Join-Path $modRoot "gfx\interface\navalcombat\ships\coi_alien_${name}.dds")
    $strip.Dispose()

    $counter = New-ShipGlyph `
        -SourcePath $masterPath `
        -Width 30 `
        -Height 12 `
        -Foreground $counterForeground `
        -Shadow $counterShadow
    Save-Preview -Bitmap $counter -Name "counter_$name"
    Write-DdsArgb `
        -Bitmap $counter `
        -Path (Join-Path $modRoot "gfx\interface\counters\ships_small\onmap_coi_alien_${name}.dds")
    $counter.Dispose()

    $invertedCounter = New-ShipGlyph `
        -SourcePath $masterPath `
        -Width 30 `
        -Height 12 `
        -Foreground $invertedCounterForeground `
        -Shadow $invertedCounterShadow
    Save-Preview -Bitmap $invertedCounter -Name "counter_${name}_inverted"
    Write-DdsArgb `
        -Bitmap $invertedCounter `
        -Path (Join-Path $modRoot "gfx\interface\counters\ships_small\onmap_coi_alien_${name}_inverted.dds")
    $invertedCounter.Dispose()

    $texticon = New-ShipGlyph `
        -SourcePath $masterPath `
        -Width 30 `
        -Height 12 `
        -Foreground $texticonForeground `
        -Shadow $texticonShadow
    Save-Preview -Bitmap $texticon -Name "texticon_$name"
    Write-DdsArgb `
        -Bitmap $texticon `
        -Path (Join-Path $modRoot "gfx\texticons\ship_coi_alien_${name}_icon_small.dds")
    $texticon.Dispose()
}

# Discovery and disclosure use ten image-generated masters. Transparent emblem
# masters feed decision/category/idea contracts; wide cinematic masters feed
# report and news events. No global vanilla sprite is replaced.
$discoveryAnomalyMaster = Join-Path $masterRoot "coi_alien_discovery_anomaly.png"

$discoveryCategory = New-TrimmedRenderedBitmap `
    -SourcePath $discoveryAnomalyMaster `
    -Width 52 `
    -Height 40 `
    -Mode Contain `
    -PaddingX 2 `
    -PaddingY 2
Save-Preview -Bitmap $discoveryCategory -Name "decision_category_discovery"
Write-DdsArgb `
    -Bitmap $discoveryCategory `
    -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_decision_category_discovery.dds")
$discoveryCategory.Dispose()

$discoveryDecision = New-TrimmedRenderedBitmap `
    -SourcePath $discoveryAnomalyMaster `
    -Width 33 `
    -Height 32 `
    -Mode Contain `
    -PaddingX 1 `
    -PaddingY 1
Save-Preview -Bitmap $discoveryDecision -Name "decision_discovery_anomaly"
Write-DdsArgb `
    -Bitmap $discoveryDecision `
    -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_decision_discovery_anomaly.dds")
$discoveryDecision.Dispose()

$discoveryReport = New-RenderedBitmap `
    -SourcePath $discoveryAnomalyMaster `
    -Width 210 `
    -Height 176 `
    -Mode Contain `
    -Background ([System.Drawing.Color]::FromArgb(255, 8, 16, 20))
Save-Preview -Bitmap $discoveryReport -Name "event_discovery_anomaly"
Write-DdsArgb `
    -Bitmap $discoveryReport `
    -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_discovery_anomaly.dds")
$discoveryReport.Dispose()

$disclosureStances = [ordered]@{
    secrecy = "coi_alien_disclosure_secrecy.png"
    managed = "coi_alien_disclosure_managed.png"
    international = "coi_alien_disclosure_international.png"
    open_files = "coi_alien_disclosure_open_files.png"
}

foreach ($name in $disclosureStances.Keys) {
    $masterPath = Join-Path $masterRoot $disclosureStances[$name]

    $decisionIcon = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 33 `
        -Height 32 `
        -Mode Contain `
        -PaddingX 1 `
        -PaddingY 1
    Save-Preview -Bitmap $decisionIcon -Name "decision_disclosure_$name"
    Write-DdsArgb `
        -Bitmap $decisionIcon `
        -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_decision_disclosure_$name.dds")
    $decisionIcon.Dispose()

    $ideaIcon = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 60 `
        -Height 68 `
        -Mode Contain `
        -PaddingX 3 `
        -PaddingY 3
    Save-Preview -Bitmap $ideaIcon -Name "idea_disclosure_$name"
    Write-DdsArgb `
        -Bitmap $ideaIcon `
        -Path (Join-Path $modRoot "gfx\interface\ideas\coi_alien_disclosure_$name.dds")
    $ideaIcon.Dispose()
}

$managedReport = New-RenderedBitmap `
    -SourcePath (Join-Path $masterRoot $disclosureStances.managed) `
    -Width 210 `
    -Height 176 `
    -Mode Contain `
    -Background ([System.Drawing.Color]::FromArgb(255, 15, 16, 18))
Save-Preview -Bitmap $managedReport -Name "event_disclosure_managed"
Write-DdsArgb `
    -Bitmap $managedReport `
    -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_disclosure_managed.dds")
$managedReport.Dispose()

$magentaMaster = Join-Path $masterRoot "coi_alien_magenta_recovery.png"
$magentaReport = New-RenderedBitmap `
    -SourcePath $magentaMaster `
    -Width 210 `
    -Height 176 `
    -Mode Cover
Save-Preview -Bitmap $magentaReport -Name "event_magenta_recovery"
Write-DdsArgb `
    -Bitmap $magentaReport `
    -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_magenta_recovery.dds")
$magentaReport.Dispose()

$magentaIdea = New-RenderedBitmap `
    -SourcePath $magentaMaster `
    -Width 60 `
    -Height 68 `
    -Mode Cover
Save-Preview -Bitmap $magentaIdea -Name "idea_magenta_recovery"
Write-DdsArgb `
    -Bitmap $magentaIdea `
    -Path (Join-Path $modRoot "gfx\interface\ideas\coi_alien_magenta_recovery.dds")
$magentaIdea.Dispose()

$vaticanMaster = Join-Path $masterRoot "coi_alien_vatican_reliquary.png"
$vaticanReport = New-RenderedBitmap `
    -SourcePath $vaticanMaster `
    -Width 210 `
    -Height 176 `
    -Mode Cover
Save-Preview -Bitmap $vaticanReport -Name "event_vatican_reliquary"
Write-DdsArgb `
    -Bitmap $vaticanReport `
    -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_vatican_reliquary.dds")
$vaticanReport.Dispose()

$vaticanIdea = New-RenderedBitmap `
    -SourcePath $vaticanMaster `
    -Width 60 `
    -Height 68 `
    -Mode Cover
Save-Preview -Bitmap $vaticanIdea -Name "idea_vatican_reliquary"
Write-DdsArgb `
    -Bitmap $vaticanIdea `
    -Path (Join-Path $modRoot "gfx\interface\ideas\coi_alien_vatican_reliquary.dds")
$vaticanIdea.Dispose()

$catastropheMaster = Join-Path $masterRoot "coi_alien_catastrophic_disclosure.png"
$catastropheCategory = New-RenderedBitmap `
    -SourcePath $catastropheMaster `
    -Width 52 `
    -Height 40 `
    -Mode Cover
Save-Preview -Bitmap $catastropheCategory -Name "decision_category_catastrophic_disclosure"
Write-DdsArgb `
    -Bitmap $catastropheCategory `
    -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_decision_category_catastrophic_disclosure.dds")
$catastropheCategory.Dispose()

$catastropheDecision = New-RenderedBitmap `
    -SourcePath $catastropheMaster `
    -Width 33 `
    -Height 32 `
    -Mode Cover
Save-Preview -Bitmap $catastropheDecision -Name "decision_catastrophic_disclosure"
Write-DdsArgb `
    -Bitmap $catastropheDecision `
    -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_decision_catastrophic_disclosure.dds")
$catastropheDecision.Dispose()

$catastropheIdea = New-RenderedBitmap `
    -SourcePath $catastropheMaster `
    -Width 60 `
    -Height 68 `
    -Mode Cover
Save-Preview -Bitmap $catastropheIdea -Name "idea_catastrophic_disclosure"
Write-DdsArgb `
    -Bitmap $catastropheIdea `
    -Path (Join-Path $modRoot "gfx\interface\ideas\coi_alien_catastrophic_disclosure.dds")
$catastropheIdea.Dispose()

$catastropheReport = New-RenderedBitmap `
    -SourcePath $catastropheMaster `
    -Width 210 `
    -Height 176 `
    -Mode Cover
Save-Preview -Bitmap $catastropheReport -Name "event_catastrophic_disclosure"
Write-DdsArgb `
    -Bitmap $catastropheReport `
    -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_catastrophic_disclosure.dds")
$catastropheReport.Dispose()

$catastropheNews = New-RenderedBitmap `
    -SourcePath $catastropheMaster `
    -Width 397 `
    -Height 153 `
    -Mode Cover
Save-Preview -Bitmap $catastropheNews -Name "news_catastrophic_disclosure"
Write-DdsArgb `
    -Bitmap $catastropheNews `
    -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_catastrophic_disclosure_news.dds")
$catastropheNews.Dispose()

# Signals in the Noise uses landscape masters with center-safe subjects so one
# source can feed both the native HOI4 newspaper strip and, where required, the
# taller country-report crop. All sprites remain namespaced; no shared vanilla
# event picture is replaced.
$alienNewsMasters = [ordered]@{
    black_program = "coi_alien_news_black_program.png"
    luminous_escorts = "coi_alien_news_luminous_escorts.png"
    northern_rockets = "coi_alien_news_northern_rockets.png"
    new_mexico_1947 = "coi_alien_news_new_mexico_1947.png"
    capital_radar = "coi_alien_news_capital_radar.png"
    returned_witness = "coi_alien_news_returned_witness.png"
    archive_leak = "coi_alien_news_archive_leak.png"
    public_inquiry = "coi_alien_news_public_inquiry.png"
    authenticated_film = "coi_alien_news_authenticated_film.png"
    official_podium = "coi_alien_news_official_podium.png"
    contact_council = "coi_alien_news_contact_council.png"
    public_crash = "coi_alien_news_public_crash.png"
    first_transmission = "coi_alien_news_first_transmission.png"
    consensus_verdict = "coi_alien_news_consensus_verdict.png"
    unified_defense = "coi_alien_news_unified_defense.png"
}

$alienNewsReportSubjects = @(
    "black_program",
    "luminous_escorts",
    "northern_rockets",
    "new_mexico_1947",
    "capital_radar",
    "returned_witness",
    "archive_leak",
    "public_inquiry"
)

foreach ($name in $alienNewsMasters.Keys) {
    $masterPath = Join-Path $masterRoot $alienNewsMasters[$name]

    $newsPicture = New-RenderedBitmap `
        -SourcePath $masterPath `
        -Width 397 `
        -Height 153 `
        -Mode Cover
    Save-Preview -Bitmap $newsPicture -Name "news_alien_$name"
    Write-DdsArgb `
        -Bitmap $newsPicture `
        -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_news_${name}_news.dds")
    $newsPicture.Dispose()

    if ($alienNewsReportSubjects -contains $name) {
        $reportPicture = New-RenderedBitmap `
            -SourcePath $masterPath `
            -Width 210 `
            -Height 176 `
            -Mode Cover
        Save-Preview -Bitmap $reportPicture -Name "event_alien_news_$name"
        Write-DdsArgb `
            -Bitmap $reportPicture `
            -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_news_$name.dds")
        $reportPicture.Dispose()
    }
}

# The Vatican revelation reuses its established cinematic master but needs a
# native newspaper crop in addition to the existing 210x176 report picture.
$vaticanNews = New-RenderedBitmap `
    -SourcePath $vaticanMaster `
    -Width 397 `
    -Height 153 `
    -Mode Cover
Save-Preview -Bitmap $vaticanNews -Name "news_vatican_reliquary"
Write-DdsArgb `
    -Bitmap $vaticanNews `
    -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_vatican_reliquary_news.dds")
$vaticanNews.Dispose()

# Human special projects use native 161x98 project cards and 508x248
# blueprints. The same image-generated emblem is placed over a dark archival
# field for the wide blueprint rather than stretched into the wrong aspect.
$reverseEngineeringProjects = [ordered]@{
    exotic_materials_characterization = "coi_alien_human_exotic_materials.png"
    field_propulsion_reconstruction = "coi_alien_human_field_dynamics.png"
}

foreach ($name in $reverseEngineeringProjects.Keys) {
    $masterPath = Join-Path $masterRoot $reverseEngineeringProjects[$name]

    $projectIcon = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 161 `
        -Height 98 `
        -Mode Contain `
        -PaddingX 8 `
        -PaddingY 5
    Save-Preview -Bitmap $projectIcon -Name "special_project_$name"
    Write-DdsArgb `
        -Bitmap $projectIcon `
        -Path (Join-Path $modRoot "gfx\interface\special_project\project_icons\coi_alien_sp_$name.dds")
    $projectIcon.Dispose()

    $blueprint = New-RenderedBitmap `
        -SourcePath $masterPath `
        -Width 508 `
        -Height 248 `
        -Mode Contain `
        -Background ([System.Drawing.Color]::FromArgb(255, 8, 18, 23))
    Save-Preview -Bitmap $blueprint -Name "special_project_${name}_blueprint"
    Write-DdsArgb `
        -Bitmap $blueprint `
        -Path (Join-Path $modRoot "gfx\interface\special_project\blueprints\coi_alien_sp_${name}_blueprint.dds")
    $blueprint.Dispose()
}

# The first playable Consensus Sciences core has eight transformational alien
# projects. Each transparent emblem becomes both a native project card and a
# wide blueprint on the same dark archival field used by human reconstruction.
$alienScienceProjects = [ordered]@{
    self_healing_lattice_demonstrator = "coi_alien_sp_self_healing_lattice.png"
    aperture_stabilization_experiment = "coi_alien_sp_aperture_stabilization.png"
    interorbital_sentinel_prototype = "coi_alien_sp_interorbital_sentinel.png"
    controlled_atomic_decoherence = "coi_alien_sp_atomic_decoherence.png"
    full_spectrum_human_culture_model = "coi_alien_sp_human_culture_model.png"
    human_genome_atlas = "coi_alien_sp_human_genome_atlas.png"
    viable_adult_clone = "coi_alien_sp_viable_adult_clone.png"
    molecular_airframe_printer = "coi_alien_sp_molecular_airframe_printer.png"
}

foreach ($name in $alienScienceProjects.Keys) {
    $masterPath = Join-Path $masterRoot $alienScienceProjects[$name]
    $projectIcon = New-TrimmedRenderedBitmap `
        -SourcePath $masterPath `
        -Width 161 `
        -Height 98 `
        -Mode Contain `
        -PaddingX 8 `
        -PaddingY 5
    Save-Preview -Bitmap $projectIcon -Name "special_project_$name"
    Write-DdsArgb `
        -Bitmap $projectIcon `
        -Path (Join-Path $modRoot "gfx\interface\special_project\project_icons\coi_alien_sp_$name.dds")
    $projectIcon.Dispose()

    $blueprint = New-RenderedBitmap `
        -SourcePath $masterPath `
        -Width 508 `
        -Height 248 `
        -Mode Contain `
        -Background ([System.Drawing.Color]::FromArgb(255, 8, 18, 23))
    Save-Preview -Bitmap $blueprint -Name "special_project_${name}_blueprint"
    Write-DdsArgb `
        -Bitmap $blueprint `
        -Path (Join-Path $modRoot "gfx\interface\special_project\blueprints\coi_alien_sp_${name}_blueprint.dds")
    $blueprint.Dispose()
}

$humanSciencesMaster = Join-Path $masterRoot "coi_alien_tech_human_sciences.png"
$humanSciencesCategory = New-TrimmedRenderedBitmap -SourcePath $humanSciencesMaster -Width 52 -Height 40 -Mode Contain -PaddingX 2 -PaddingY 2
Save-Preview -Bitmap $humanSciencesCategory -Name "decision_category_human_sciences"
Write-DdsArgb -Bitmap $humanSciencesCategory -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_decision_category_human_sciences.dds")
$humanSciencesCategory.Dispose()
$humanSciencesDecision = New-TrimmedRenderedBitmap -SourcePath $humanSciencesMaster -Width 33 -Height 32 -Mode Contain -PaddingX 1 -PaddingY 1
Save-Preview -Bitmap $humanSciencesDecision -Name "decision_human_sciences"
Write-DdsArgb -Bitmap $humanSciencesDecision -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_decision_human_sciences.dds")
$humanSciencesDecision.Dispose()
$humanSciencesIdea = New-TrimmedRenderedBitmap -SourcePath $humanSciencesMaster -Width 60 -Height 68 -Mode Contain -PaddingX 3 -PaddingY 3
Save-Preview -Bitmap $humanSciencesIdea -Name "idea_human_sciences"
Write-DdsArgb -Bitmap $humanSciencesIdea -Path (Join-Path $modRoot "gfx\interface\ideas\coi_alien_human_sciences.dds")
$humanSciencesIdea.Dispose()
$humanSciencesReport = New-RenderedBitmap -SourcePath (Join-Path $masterRoot "coi_alien_sp_human_culture_model.png") -Width 210 -Height 176 -Mode Contain -Background ([System.Drawing.Color]::FromArgb(255, 8, 18, 23))
Save-Preview -Bitmap $humanSciencesReport -Name "event_human_sciences"
Write-DdsArgb -Bitmap $humanSciencesReport -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_human_sciences.dds")
$humanSciencesReport.Dispose()

$cloneMaster = Join-Path $masterRoot "coi_alien_sp_viable_adult_clone.png"
$cloneDecision = New-TrimmedRenderedBitmap -SourcePath $cloneMaster -Width 33 -Height 32 -Mode Contain -PaddingX 1 -PaddingY 1
Save-Preview -Bitmap $cloneDecision -Name "decision_viable_adult_clone"
Write-DdsArgb -Bitmap $cloneDecision -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_decision_viable_adult_clone.dds")
$cloneDecision.Dispose()
$cloneIdea = New-TrimmedRenderedBitmap -SourcePath $cloneMaster -Width 60 -Height 68 -Mode Contain -PaddingX 3 -PaddingY 3
Save-Preview -Bitmap $cloneIdea -Name "idea_viable_adult_clone"
Write-DdsArgb -Bitmap $cloneIdea -Path (Join-Path $modRoot "gfx\interface\ideas\coi_alien_viable_adult_clone.dds")
$cloneIdea.Dispose()
$cloneReport = New-RenderedBitmap -SourcePath $cloneMaster -Width 210 -Height 176 -Mode Contain -Background ([System.Drawing.Color]::FromArgb(255, 8, 18, 23))
Save-Preview -Bitmap $cloneReport -Name "event_viable_adult_clone"
Write-DdsArgb -Bitmap $cloneReport -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_viable_adult_clone.dds")
$cloneReport.Dispose()

$gatewayMaster = Join-Path $masterRoot "coi_alien_sp_aperture_stabilization.png"
$gatewayIcon = New-TrimmedRenderedBitmap -SourcePath $gatewayMaster -Width 64 -Height 64 -Mode Contain -PaddingX 2 -PaddingY 2
Save-Preview -Bitmap $gatewayIcon -Name "energy_gateway"
Write-DdsArgb -Bitmap $gatewayIcon -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_energy_gateway.dds")
$gatewayIcon.Dispose()

$sentinelMaster = Join-Path $masterRoot "coi_alien_sp_interorbital_sentinel.png"
$sentinelEquipment = New-TrimmedRenderedBitmap -SourcePath $sentinelMaster -Width 146 -Height 54 -Mode Contain -PaddingX 3 -PaddingY 2
Save-Preview -Bitmap $sentinelEquipment -Name "equipment_orbital_sentinel"
Write-DdsArgb -Bitmap $sentinelEquipment -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_orbital_sentinel.dds")
$sentinelEquipment.Dispose()
$sentinelTechnology = New-TrimmedRenderedBitmap -SourcePath $sentinelMaster -Width 64 -Height 64 -Mode Contain -PaddingX 2 -PaddingY 2
Save-Preview -Bitmap $sentinelTechnology -Name "technology_orbital_sentinel"
Write-DdsArgb -Bitmap $sentinelTechnology -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_tech_orbital_sentinel.dds")
$sentinelTechnology.Dispose()

# Keep the phase-transit glyph namespaced. The stock naval activity widget uses
# a global sprite, so this is safe project art for an XAC-specific UI hook rather
# than a global replacement that would reskin every human navy.
$phaseMovement = New-RenderedBitmap `
    -SourcePath (Join-Path $masterRoot "coi_alien_phase_movement_ui_v2.png") `
    -Width 24 `
    -Height 24 `
    -Mode Contain
Save-Preview -Bitmap $phaseMovement -Name "phase_movement"
Write-DdsArgb -Bitmap $phaseMovement -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_phase_movement.dds")
$phaseMovement.Dispose()

$anchorage = New-RenderedBitmap `
    -SourcePath (Join-Path $masterRoot "coi_alien_anchorage.png") `
    -Width 64 `
    -Height 64 `
    -Mode Cover
Save-Preview -Bitmap $anchorage -Name "anchorage_icon"
Write-DdsArgb -Bitmap $anchorage -Path (Join-Path $modRoot "gfx\interface\coi_alien\coi_alien_anchorage.dds")
$anchorage.Dispose()

$landfall = New-RenderedBitmap `
    -SourcePath (Join-Path $masterRoot "coi_alien_landfall.png") `
    -Width 397 `
    -Height 153 `
    -Mode Cover
Save-Preview -Bitmap $landfall -Name "event_landfall"
Write-DdsArgb -Bitmap $landfall -Path (Join-Path $modRoot "gfx\event_pictures\coi_alien_landfall.dds")
$landfall.Dispose()

# Steam Workshop presents mod art as a square tile. Keep the full-resolution
# imagegen master in Source and derive a compact launcher/upload asset here.
$workshopCover = New-RenderedBitmap `
    -SourcePath (Join-Path $masterRoot "coi_alien_workshop_cover.png") `
    -Width 512 `
    -Height 512 `
    -Mode Cover
Save-Preview -Bitmap $workshopCover -Name "workshop_cover"
$workshopCover.Save(
    (Join-Path $modRoot "thumbnail.png"),
    [System.Drawing.Imaging.ImageFormat]::Png
)
$workshopCover.Dispose()

$flagBackground = [System.Drawing.Color]::FromArgb(255, 29, 36, 38)
$flagSizes = @(
    @{ Width = 82; Height = 52; Path = "gfx\flags\XAC.tga"; Preview = "flag_large" },
    @{ Width = 41; Height = 26; Path = "gfx\flags\medium\XAC.tga"; Preview = "flag_medium" },
    @{ Width = 10; Height = 7; Path = "gfx\flags\small\XAC.tga"; Preview = "flag_small" }
)

foreach ($flag in $flagSizes) {
    $bitmap = New-RenderedBitmap `
        -SourcePath (Join-Path $masterRoot "coi_alien_flag_master.png") `
        -Width $flag.Width `
        -Height $flag.Height `
        -Mode Stretch `
        -Background $flagBackground
    Save-Preview -Bitmap $bitmap -Name $flag.Preview
	Write-Tga32 -Bitmap $bitmap -Path (Join-Path $modRoot $flag.Path)
    $bitmap.Dispose()
}

Write-Host "Built Grey Consensus art assets from $masterRoot"
Write-Host "  Portraits: 5 leaders (large/small) and 6 operative DDS"
Write-Host "  Intelligence: 1 operative-trait icon and 1 two-frame agency logo"
Write-Host "  Quiet Chorus: 8 operation sets, 3 token pairs, and 3 agency-upgrade icons"
Write-Host "  Equipment: 6 transparent DDS icons including Tic Tac and Sentinel"
Write-Host "  Technology: 8 transparent DDS icons across six domains"
Write-Host "  Discovery/disclosure: 4 stance pairs, 4 category/decision icons, 5 report/news pictures, and 3 idea pictures"
Write-Host "  Alien news: 15 native news strips, 8 report crops, and 1 reused-art Vatican news strip"
Write-Host "  Human reverse engineering: 2 native project cards and 2 native blueprints"
Write-Host "  Consensus Sciences: 8 native project cards and 8 native blueprints"
Write-Host "  Naval UI: 2 roster icons, 3 mirrored strips, 4 counters, 2 texticons, and 1 movement glyph"
Write-Host "  UI/event: anchorage icon and landfall picture"
Write-Host "  Workshop: 512x512 thumbnail.png"
Write-Host "  Flags: 82x52, 41x26, and 10x7 32bpp TGA"
