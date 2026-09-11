param(
	[string]$GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\Hearts of Iron IV"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$sourcePath = Join-Path $GameRoot 'common\raids\nuclear_raids.txt'
$targetPath = Join-Path $projectRoot 'Mod\common\raids\nuclear_raids.txt'
$expectedSourceHash = '966408C81EBA9F5928ED352D5F95F6648977B23A8E12CE9AA2CD2CDBCA76256F'
$expectedOutputHash = '0CD1D77F18DF5A2B05D7DA95A9360F9836F519492F91AC5AAB7C5EFAEB09F620'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

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

function Get-RaidBlockRanges {
	param([Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Lines)

	$depths = Get-LineDepths -Lines $Lines
	$ranges = [Collections.Generic.List[object]]::new()
	for ($index = 0; $index -lt $Lines.Count; $index++) {
		if ($depths[$index] -ne 1 -or $Lines[$index] -notmatch '^\s*([A-Za-z0-9_]+)\s*=\s*\{') { continue }
		$name = $Matches[1]
		$next = $index + 1
		while ($next -lt $Lines.Count -and $depths[$next] -ne 1) { $next++ }
		if ($next -ge $Lines.Count) { throw "Could not find the end of raid $name." }
		$ranges.Add([pscustomobject]@{ Name = $name; Start = $index; End = $next - 1 })
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

function Add-AfterUniqueSequence {
	param(
		[Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Lines,
		[Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Anchor,
		[Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Insertion,
		[Parameter(Mandatory)] [string]$Context
	)

	$matches = [Collections.Generic.List[int]]::new()
	for ($index = 0; $index -le $Lines.Count - $Anchor.Count; $index++) {
		$isMatch = $true
		for ($offset = 0; $offset -lt $Anchor.Count; $offset++) {
			if ($Lines[$index + $offset] -cne $Anchor[$offset]) {
				$isMatch = $false
				break
			}
		}
		if ($isMatch) { $matches.Add($index) }
	}

	if ($matches.Count -ne 1) {
		throw "Expected one $Context anchor, found $($matches.Count)."
	}

	$insertAt = $matches[0] + $Anchor.Count
	Replace-LineRange -Lines $Lines -Start $insertAt -End ($insertAt - 1) -Replacement $Insertion
}

function Get-Sha256Hex {
	param([Parameter(Mandatory)] [byte[]]$Bytes)

	$sha256 = [Security.Cryptography.SHA256]::Create()
	try {
		([BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '')
	}
	finally {
		$sha256.Dispose()
	}
}

function Assert-ExactLineCount {
	param(
		[Parameter(Mandatory)] [AllowEmptyString()] [string[]]$Lines,
		[Parameter(Mandatory)] [AllowEmptyString()] [string]$Line,
		[Parameter(Mandatory)] [int]$ExpectedCount
	)

	$actualCount = @($Lines | Where-Object { $_ -ceq $Line }).Count
	if ($actualCount -ne $ExpectedCount) {
		throw "Expected $ExpectedCount generated '$($Line.Trim())' lines, found $actualCount."
	}
}

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
	throw "HOI4 nuclear raid source was not found: $sourcePath"
}

$actualSourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
if ($actualSourceHash -cne $expectedSourceHash) {
	throw "Unsupported nuclear_raids.txt hash $actualSourceHash. This builder is pinned to HOI4 1.19.2 ($expectedSourceHash)."
}

$sourceText = [IO.File]::ReadAllText($sourcePath)
if ($sourceText.Contains("`r`n")) {
	throw 'Expected the HOI4 1.19.2 nuclear raid source to use LF line endings.'
}

$lines = [string[]]($sourceText -split "`n", 0, 'SimpleMatch')
$raidRanges = @(Get-RaidBlockRanges -Lines $lines)
$expectedRaidNames = @(
	'nuclear_strike',
	'nuclear_missile_strike',
	'nuclear_missile_strike_submarine',
	'thermonuclear_strike',
	'thermonuclear_missile_strike',
	'thermonuclear_missile_strike_submarine'
)
$actualRaidNames = @($raidRanges | ForEach-Object { $_.Name })
if (($actualRaidNames -join '|') -cne ($expectedRaidNames -join '|')) {
	throw "Unexpected HOI4 1.19.2 raid definitions: $($actualRaidNames -join ', ')."
}

$atomicDisruptionFactor = @(
	"`t`t`t`tcoi_alien_atomic_disruption = {",
	"`t`t`t`t`tscope = country",
	"`t`t`t`t`tformula = {",
	"`t`t`t`t`t`tbase = 0",
	"`t`t`t`t`t`tmodifier = {",
	"`t`t`t`t`t`t`thas_dynamic_modifier = { modifier = coi_alien_atomic_disruption_degraded }",
	"`t`t`t`t`t`t`tadd = 35",
	"`t`t`t`t`t`t}",
	"`t`t`t`t`t`tmodifier = {",
	"`t`t`t`t`t`t`thas_dynamic_modifier = { modifier = coi_alien_atomic_disruption_critical }",
	"`t`t`t`t`t`t`tadd = 50",
	"`t`t`t`t`t`t}",
	"`t`t`t`t`t}",
	"`t`t`t`t`tweight = -1",
	"`t`t`t`t`treference = 100",
	"`t`t`t`t`tcan_actor_affect = yes",
	"`t`t`t`t`tcan_target_affect = no",
	"`t`t`t`t}"
)

$orbitalInterceptFactor = @(
	"`t`t`t`tcoi_alien_orbital_intercept_lattice = {",
	"`t`t`t`t`tscope = state",
	"`t`t`t`t`tformula = {",
	"`t`t`t`t`t`tbase = 0",
	"`t`t`t`t`t`tmodifier = {",
	"`t`t`t`t`t`t`tcoi_alien_orbital_target_has_basic_defense_trigger = yes",
	"`t`t`t`t`t`t`tadd = 35",
	"`t`t`t`t`t`t}",
	"`t`t`t`t`t`tmodifier = {",
	"`t`t`t`t`t`t`tcoi_alien_orbital_target_has_sentinel_defense_trigger = yes",
	"`t`t`t`t`t`t`tadd = 20",
	"`t`t`t`t`t`t}",
	"`t`t`t`t`t`tmodifier = {",
	"`t`t`t`t`t`t`tcoi_alien_orbital_target_has_atomic_defense_trigger = yes",
	"`t`t`t`t`t`t`tadd = 15",
	"`t`t`t`t`t`t}",
	"`t`t`t`t`t}",
	"`t`t`t`t`tweight = -1",
	"`t`t`t`t`treference = 100",
	"`t`t`t`t`tcan_actor_affect = no",
	"`t`t`t`t`tcan_target_affect = yes",
	"`t`t`t`t}"
)

foreach ($raidRange in @($raidRanges | Sort-Object Start -Descending)) {
	$blockLines = [string[]]$lines[$raidRange.Start..$raidRange.End]
	$isMissileRaid = $raidRange.Name -match '_missile_strike'
	$baseValue = if ($isMissileRaid) { '0.8' } else { '0.5' }
	$successAnchor = @(
		"`t`tsuccess_factors = {",
		"`t`t`tsuccess = {",
		"`t`t`t`tbase = $baseValue"
	)
	$successInsertion = if ($isMissileRaid) {
		[string[]]@($atomicDisruptionFactor + $orbitalInterceptFactor)
	}
	else {
		[string[]]$atomicDisruptionFactor
	}
	$blockLines = [string[]](Add-AfterUniqueSequence `
		-Lines $blockLines `
		-Anchor $successAnchor `
		-Insertion $successInsertion `
		-Context "$($raidRange.Name) success-factor")

	if ($isMissileRaid) {
		$interceptionEffect = if ($raidRange.Name -match '^thermonuclear_') {
			'coi_alien_resolve_orbital_thermonuclear_interception_effect'
		}
		else {
			'coi_alien_resolve_orbital_atomic_interception_effect'
		}
		$victimEffects = @(
			"`t`t`t`tvictim_effects = {",
			"`t`t`t`t`tvar:target_state = {",
			"`t`t`t`t`t`tif = {",
			"`t`t`t`t`t`t`tlimit = { coi_alien_orbital_target_has_basic_defense_trigger = yes }",
			"`t`t`t`t`t`t`tcustom_effect_tooltip = coi_alien_orbital_interception_attempt_tt",
			"`t`t`t`t`t`t`t$interceptionEffect = yes",
			"`t`t`t`t`t`t}",
			"`t`t`t`t`t}",
			"`t`t`t`t}"
		)
		foreach ($outcome in @('failure', 'limited_success')) {
			$outcomeAnchor = @(
				"`t`t`t$outcome = {",
				"`t`t`t`tactor_effects = {",
				"`t`t`t`t`tvar:actor_country = {",
				"`t`t`t`t`t`tcustom_effect_tooltip = dud_missile_tt",
				"`t`t`t`t`t}",
				"`t`t`t`t}"
			)
			$blockLines = [string[]](Add-AfterUniqueSequence `
				-Lines $blockLines `
				-Anchor $outcomeAnchor `
				-Insertion $victimEffects `
				-Context "$($raidRange.Name) $outcome")
		}
	}

	$lines = [string[]](Replace-LineRange `
		-Lines $lines `
		-Start $raidRange.Start `
		-End $raidRange.End `
		-Replacement $blockLines)
}

$header = @(
	'# Exact-file shadow of Hearts of Iron IV 1.19.2 nuclear_raids.txt.',
	"# Vanilla source SHA-256: $expectedSourceHash",
	'# The six vanilla raid definitions remain intact. COI adds only an actor-side',
	'# Atomic Disruption factor to all six and a target-side Sentinel factor plus',
	'# outcome notification/attrition to the four ballistic missile definitions.'
)
$lines = [string[]]@($header + $lines)

[void](Get-LineDepths -Lines $lines)
Assert-ExactLineCount -Lines $lines -Line "`t`t`t`tcoi_alien_atomic_disruption = {" -ExpectedCount 6
Assert-ExactLineCount -Lines $lines -Line "`t`t`t`tcoi_alien_orbital_intercept_lattice = {" -ExpectedCount 4
Assert-ExactLineCount -Lines $lines -Line "`t`t`t`t`t`t`tcoi_alien_resolve_orbital_atomic_interception_effect = yes" -ExpectedCount 4
Assert-ExactLineCount -Lines $lines -Line "`t`t`t`t`t`t`tcoi_alien_resolve_orbital_thermonuclear_interception_effect = yes" -ExpectedCount 4

$outputText = $lines -join "`n"
$outputBytes = $utf8NoBom.GetBytes($outputText)
$actualOutputHash = Get-Sha256Hex -Bytes $outputBytes
if ($actualOutputHash -cne $expectedOutputHash) {
	throw "Generated nuclear_raids.txt hash $actualOutputHash does not match the pinned Alien Crisis output $expectedOutputHash."
}

$targetIsCurrent = $false
if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
	$targetIsCurrent = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash -ceq $expectedOutputHash
}

if (-not $targetIsCurrent) {
	[IO.Directory]::CreateDirectory((Split-Path -Parent $targetPath)) | Out-Null
	[IO.File]::WriteAllBytes($targetPath, $outputBytes)
}

$writtenHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
if ($writtenHash -cne $expectedOutputHash) {
	throw "Built nuclear_raids.txt failed its post-write hash check: $writtenHash."
}

$status = if ($targetIsCurrent) { 'already current' } else { 'rebuilt' }
Write-Host "Alien Crisis nuclear raids $status from the pinned HOI4 1.19.2 source: $targetPath"
