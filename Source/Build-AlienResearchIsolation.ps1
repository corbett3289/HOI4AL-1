param(
	[string]$GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\Hearts of Iron IV"
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$modRoot = Join-Path $projectRoot 'Mod'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

$technologyTagSource = Join-Path $GameRoot 'common\technology_tags\00_technology.txt'
$expectedTechnologyTagHash = 'FCCF0824ABCF0D741F740704D92310C430B84D062A5B43E65119DCDB2896EEEA'
$buildingSource = Join-Path $GameRoot 'common\buildings\00_buildings.txt'
$expectedBuildingHash = '9FA27D266F726DE04C71311551698C6466257636DCC34D2573A3568D397BD539'

$projectSources = [ordered]@{
	'air_projects.txt' = '9A8E41F1DD41D22BCB6BA8974BC217AE9F2404F262E508A4D32B3F7C10C077E1'
	'land_projects.txt' = 'EEA9C3722209AEC2EAFF25E37090903458726B91EA147BF484B9082EEF0DB8EF'
	'naval_projects.txt' = 'E0F61BE0AEA1635863C460EB2C4D4A15EC18ABE05151FCD409559B3F56BFB7CB'
	'nuclear_projects.txt' = 'B822068268CF848BA9DC9000D762C7005BDDE4F6773DD5509E17CE895165E83F'
	'radar_projects.txt' = '1A7CC30969A3C896887EDCCAE6A75945996E4DC77312DD02A818AA6E66F9A69A'
	'rocket_projects.txt' = 'C2AA6F2822C6A5DC1F7EDC34D917EF2440F245C47EA02358AD05F8F38C7DE6DA'
}

function Assert-PinnedSource {
	param(
		[Parameter(Mandatory)] [string]$Path,
		[Parameter(Mandatory)] [string]$ExpectedHash
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		throw "Required HOI4 source was not found: $Path"
	}
	$actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
	if ($actualHash -cne $ExpectedHash) {
		throw "Unsupported HOI4 1.19.2 source hash for $Path. Expected $ExpectedHash, found $actualHash."
	}
}

function Get-CodeBraceDelta {
	param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Line)

	$delta = 0
	$inQuote = $false
	$escaped = $false
	foreach ($character in $Line.ToCharArray()) {
		if ($inQuote) {
			if ($escaped) {
				$escaped = $false
				continue
			}
			if ($character -eq '\') {
				$escaped = $true
				continue
			}
			if ($character -eq '"') {
				$inQuote = $false
			}
			continue
		}

		if ($character -eq '#') { break }
		if ($character -eq '"') {
			$inQuote = $true
			continue
		}
		if ($character -eq '{') { $delta++ }
		elseif ($character -eq '}') { $delta-- }
	}
	$delta
}

function Get-LineDepths {
	param([Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Lines)

	$depth = 0
	$depths = [int[]]::new($Lines.Count)
	for ($index = 0; $index -lt $Lines.Count; $index++) {
		$depths[$index] = $depth
		$depth += Get-CodeBraceDelta -Line $Lines[$index]
		if ($depth -lt 0) { throw "Unbalanced closing brace at line $($index + 1)." }
	}
	if ($depth -ne 0) { throw "Unbalanced Clausewitz braces; final depth is $depth." }
	$depths
}

function Get-RootBlockRanges {
	param([Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Lines)

	$depths = Get-LineDepths -Lines $Lines
	$ranges = [Collections.Generic.List[object]]::new()
	for ($index = 0; $index -lt $Lines.Count; $index++) {
		if ($depths[$index] -ne 0 -or $Lines[$index] -notmatch '^([A-Za-z0-9_]+)\s*=\s*\{\s*$') { continue }
		$name = $Matches[1]
		$next = $index + 1
		while ($next -lt $Lines.Count -and $depths[$next] -ne 0) { $next++ }
		$end = if ($next -lt $Lines.Count) { $next - 1 } else { $Lines.Count - 1 }
		$ranges.Add([pscustomobject]@{ Name = $name; Start = $index; End = $end })
		$index = $next - 1
	}
	$ranges
}

function Replace-LineRange {
	param(
		[Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Lines,
		[Parameter(Mandatory)] [int]$Start,
		[Parameter(Mandatory)] [int]$End,
		[Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Replacement
	)

	[string[]]$before = if ($Start -gt 0) { @($Lines[0..($Start - 1)]) } else { @() }
	[string[]]$after = if ($End + 1 -lt $Lines.Count) { @($Lines[($End + 1)..($Lines.Count - 1)]) } else { @() }
	@($before + $Replacement + $after)
}

function Add-ProjectClauseGate {
	param(
		[Parameter(Mandatory)] [AllowEmptyString()] [string[]]$BlockLines,
		[Parameter(Mandatory)] [ValidateSet('allowed', 'visible', 'available')] [string]$Clause
	)

	$depths = Get-LineDepths -Lines $BlockLines
	$clauseIndex = -1
	for ($index = 1; $index -lt $BlockLines.Count - 1; $index++) {
		if ($depths[$index] -eq 1 -and $BlockLines[$index] -match ('^\s*' + $Clause + '\s*=\s*\{\s*$')) {
			$clauseIndex = $index
			break
		}
	}

	if ($Clause -eq 'allowed') {
		$gateLines = @("`t`tNOT = { original_tag = XAC }")
		$newClause = @("`tallowed = {", "`t`tNOT = { original_tag = XAC }", "`t}", '')
	}
	else {
		$gateLines = @("`t`tFROM = {", "`t`t`tNOT = { original_tag = XAC }", "`t`t}")
		$newClause = @("`t$Clause = {", "`t`tFROM = {", "`t`t`tNOT = { original_tag = XAC }", "`t`t}", "`t}", '')
	}

	if ($clauseIndex -ge 0) {
		return Replace-LineRange -Lines $BlockLines -Start ($clauseIndex + 1) -End $clauseIndex -Replacement $gateLines
	}
	Replace-LineRange -Lines $BlockLines -Start 1 -End 0 -Replacement $newClause
}

function Get-AssignedBlockText {
	param(
		[Parameter(Mandatory)] [AllowEmptyString()] [string[]]$BlockLines,
		[Parameter(Mandatory)] [string]$Clause
	)

	$depths = Get-LineDepths -Lines $BlockLines
	for ($index = 1; $index -lt $BlockLines.Count - 1; $index++) {
		if ($depths[$index] -ne 1 -or $BlockLines[$index] -notmatch ('^\s*' + $Clause + '\s*=\s*\{\s*$')) { continue }
		$next = $index + 1
		while ($next -lt $BlockLines.Count -and $depths[$next] -ne 1) { $next++ }
		if ($next -ge $BlockLines.Count) { throw "Could not find the end of $Clause." }
		$end = $next - 1
		return ($BlockLines[$index..$end] -join "`n")
	}
	throw "Missing $Clause block."
}

function Add-TechnologyFolderGate {
	param([Parameter(Mandatory)] [AllowEmptyString()] [string[]]$FolderLines)

	$depths = Get-LineDepths -Lines $FolderLines
	$availableIndex = -1
	for ($index = 1; $index -lt $FolderLines.Count - 1; $index++) {
		if ($depths[$index] -eq 1 -and $FolderLines[$index] -match '^\s*available\s*=\s*\{') {
			$availableIndex = $index
			break
		}
	}
	if ($availableIndex -ge 0) {
		if ((Get-CodeBraceDelta -Line $FolderLines[$availableIndex]) -eq 0) {
			if ($FolderLines[$availableIndex] -notmatch '^\s*available\s*=\s*\{\s*(.+)\s*\}\s*$') {
				throw 'Could not expand inline technology-folder availability clause.'
			}
			$existingCondition = $Matches[1].Trim()
			return Replace-LineRange -Lines $FolderLines -Start $availableIndex -End $availableIndex -Replacement @(
				"`t`tavailable = {",
				"`t`t`tNOT = { original_tag = XAC }",
				"`t`t`t$existingCondition",
				"`t`t}")
		}
		return Replace-LineRange -Lines $FolderLines -Start ($availableIndex + 1) -End $availableIndex -Replacement @("`t`t`tNOT = { original_tag = XAC }")
	}
	Replace-LineRange -Lines $FolderLines -Start 1 -End 0 -Replacement @(
		"`t`tavailable = {",
		"`t`t`tNOT = { original_tag = XAC }",
		"`t`t}")
}

### Vanilla technology-folder isolation ####################################
Assert-PinnedSource -Path $technologyTagSource -ExpectedHash $expectedTechnologyTagHash
$technologyTagText = [IO.File]::ReadAllText($technologyTagSource)
if ($technologyTagText.Contains("`r`n")) { throw 'Expected vanilla 1.19.2 technology tags to use LF line endings.' }
$technologyTagLines = [string[]]($technologyTagText -split "`n", 0, 'SimpleMatch')
$technologyFolderIds = @(
	'infantry_folder', 'support_folder', 'armour_folder', 'nsb_armour_folder',
	'artillery_folder', 'air_techs_folder', 'bba_air_techs_folder', 'naval_folder',
	'mtgnavalfolder', 'mtgnavalsupportfolder', 'industry_folder',
	'land_doctrine_folder', 'naval_doctrine_folder', 'air_doctrine_folder',
	'special_forces_doctrine_folder', 'electronics_folder'
)

foreach ($folderId in $technologyFolderIds) {
	$depths = Get-LineDepths -Lines $technologyTagLines
	$start = -1
	for ($index = 0; $index -lt $technologyTagLines.Count; $index++) {
		if ($depths[$index] -eq 1 -and $technologyTagLines[$index] -match ('^\s*' + [regex]::Escape($folderId) + '\s*=\s*\{\s*$')) {
			$start = $index
			break
		}
	}
	if ($start -lt 0) { throw "Technology folder $folderId was not found at the expected depth." }
	$next = $start + 1
	while ($next -lt $technologyTagLines.Count -and $depths[$next] -ne 1) { $next++ }
	if ($next -ge $technologyTagLines.Count) { throw "Could not find the end of technology folder $folderId." }
	$end = $next - 1
	$folderLines = [string[]]$technologyTagLines[$start..$end]
	$folderLines = [string[]](Add-TechnologyFolderGate -FolderLines $folderLines)
	$technologyTagLines = [string[]](Replace-LineRange -Lines $technologyTagLines -Start $start -End $end -Replacement $folderLines)
}

$technologyTagOutput = $technologyTagLines -join "`n"
if ([regex]::Matches($technologyTagOutput, 'NOT\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}').Count -ne $technologyFolderIds.Count) {
	throw 'Generated technology tags do not contain exactly one XAC exclusion per vanilla folder.'
}
$technologyTagTarget = Join-Path $modRoot 'common\technology_tags\00_technology.txt'
[IO.Directory]::CreateDirectory((Split-Path -Parent $technologyTagTarget)) | Out-Null
[IO.File]::WriteAllText($technologyTagTarget, $technologyTagOutput, $utf8NoBom)

### Human experimental-facility isolation ###############################
# The four vanilla facilities are otherwise globally constructible as soon as
# Götterdämmerung is active. Shadow the pinned definition and make them use
# the normal technology-unlock path. A hidden helper technology is granted to
# every non-XAC country by on_action, preserving vanilla human behavior while
# preventing XAC from constructing irrelevant human laboratories.
Assert-PinnedSource -Path $buildingSource -ExpectedHash $expectedBuildingHash
$buildingText = [IO.File]::ReadAllText($buildingSource)
$buildingLines = [string[]]($buildingText -split "`r?`n")
$facilityIds = @('naval_facility', 'nuclear_facility', 'air_facility', 'land_facility')
foreach ($facilityId in $facilityIds) {
	$depths = Get-LineDepths -Lines $buildingLines
	$start = -1
	for ($index = 0; $index -lt $buildingLines.Count; $index++) {
		if ($depths[$index] -eq 1 -and $buildingLines[$index] -match ('^\s*' + [regex]::Escape($facilityId) + '\s*=\s*\{\s*$')) {
			$start = $index
			break
		}
	}
	if ($start -lt 0) { throw "Building $facilityId was not found at the expected depth." }
	$next = $start + 1
	while ($next -lt $buildingLines.Count -and $depths[$next] -ne 1) { $next++ }
	if ($next -ge $buildingLines.Count) { throw "Could not find the end of building $facilityId." }
	$end = $next - 1
	$blockText = $buildingLines[$start..$end] -join "`n"
	if ($blockText -match '(?m)^\s*hide_if_missing_tech\s*=') {
		throw "Building $facilityId unexpectedly already has hide_if_missing_tech; rebase the pinned transformation."
	}
	$buildingLines = [string[]](Replace-LineRange -Lines $buildingLines -Start ($start + 1) -End $start -Replacement @("`t`thide_if_missing_tech = yes"))
}
$buildingOutput = $buildingLines -join "`n"
if ([regex]::Matches($buildingOutput, '(?m)^\s*hide_if_missing_tech\s*=\s*yes\s*$').Count -lt $facilityIds.Count) {
	throw 'Generated building shadow is missing one or more facility technology gates.'
}
$buildingTarget = Join-Path $modRoot 'common\buildings\00_buildings.txt'
[IO.Directory]::CreateDirectory((Split-Path -Parent $buildingTarget)) | Out-Null
[IO.File]::WriteAllText($buildingTarget, $buildingOutput, $utf8NoBom)

### Vanilla special-project isolation ######################################
$projectSourceDirectory = Join-Path $GameRoot 'common\special_projects\projects'
$projectTargetDirectory = Join-Path $modRoot 'common\special_projects\projects'
[IO.Directory]::CreateDirectory($projectTargetDirectory) | Out-Null
$totalProjects = 0

foreach ($entry in $projectSources.GetEnumerator()) {
	$sourcePath = Join-Path $projectSourceDirectory $entry.Key
	Assert-PinnedSource -Path $sourcePath -ExpectedHash $entry.Value
	$text = [IO.File]::ReadAllText($sourcePath)
	if ($text.Contains("`r`n")) { throw "Expected $($entry.Key) to use LF line endings." }
	$lines = [string[]]($text -split "`n", 0, 'SimpleMatch')
	$ranges = @(Get-RootBlockRanges -Lines $lines)
	$totalProjects += $ranges.Count

	foreach ($range in @($ranges | Sort-Object Start -Descending)) {
		$blockLines = [string[]]$lines[$range.Start..$range.End]
		foreach ($clause in @('allowed', 'visible', 'available')) {
			$blockLines = [string[]](Add-ProjectClauseGate -BlockLines $blockLines -Clause $clause)
		}

		$allowedText = Get-AssignedBlockText -BlockLines $blockLines -Clause 'allowed'
		$visibleText = Get-AssignedBlockText -BlockLines $blockLines -Clause 'visible'
		$availableText = Get-AssignedBlockText -BlockLines $blockLines -Clause 'available'
		if ([regex]::Matches($allowedText, 'NOT\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}').Count -ne 1) {
			throw "$($range.Name) does not have exactly one startup XAC exclusion."
		}
		foreach ($contract in @($visibleText, $availableText)) {
			if ([regex]::Matches($contract, 'FROM\s*=\s*\{\s*NOT\s*=\s*\{\s*original_tag\s*=\s*XAC\s*\}\s*\}').Count -ne 1) {
				throw "$($range.Name) does not have exactly one loaded-save XAC visibility/availability exclusion."
			}
		}

		$lines = [string[]](Replace-LineRange -Lines $lines -Start $range.Start -End $range.End -Replacement $blockLines)
	}

	$targetPath = Join-Path $projectTargetDirectory $entry.Key
	[IO.File]::WriteAllText($targetPath, ($lines -join "`n"), $utf8NoBom)
}

if ($totalProjects -ne 49) {
	throw "Expected 49 vanilla projects in pinned 1.19.2 sources, found $totalProjects."
}

Write-Host "Built XAC research isolation for $($technologyFolderIds.Count) vanilla folders, $totalProjects vanilla special projects, and $($facilityIds.Count) human facilities."
