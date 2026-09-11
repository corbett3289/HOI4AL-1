param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Hearts of Iron IV'
)

$ErrorActionPreference = 'Stop'
$modRoot = Join-Path $ProjectRoot 'Mod'
$errors = [System.Collections.Generic.List[string]]::new()

function Require-File([string]$RelativePath) {
    $path = Join-Path $modRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $script:errors.Add("Missing $RelativePath")
    }
    return $path
}

function Require-Count([string]$Text, [string]$Pattern, [int]$Count, [string]$Message) {
    $actual = [regex]::Matches($Text, $Pattern, 'Multiline').Count
    if ($actual -ne $Count) {
        $script:errors.Add("$Message (found $actual, expected $Count)")
    }
}

function Get-ClausewitzBlock([string]$Text, [string]$Identifier) {
    $header = [regex]::Match($Text, '(?m)^\s*' + [regex]::Escape($Identifier) + '\s*=\s*\{')
    if (-not $header.Success) { return $null }

    $openBrace = $Text.IndexOf('{', $header.Index)
    $depth = 0
    for ($index = $openBrace; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($header.Index, $index - $header.Index + 1) }
        }
    }
    return $null
}

$paths = @(
    'common\buildings\coi_alien_gateway_buildings.txt',
	'common\buildings\coi_alien_naval_buildings.txt',
    'common\units\equipment\coi_alien_orbital_equipment.txt',
    'common\units\equipment\coi_alien_naval_and_air_equipment.txt',
    'common\decisions\coi_alien_gateway_decisions.txt',
    'common\scripted_effects\coi_alien_gateway_effects.txt',
    'common\scripted_effects\coi_alien_naval_effects.txt',
    'common\scripted_triggers\coi_alien_gateway_triggers.txt',
    'common\dynamic_modifiers\coi_alien_orbital_dynamic_modifiers.txt',
    'common\on_actions\coi_alien_gateway_on_actions.txt',
    'common\operations\coi_alien_orbital_operations.txt',
    'common\operation_phases\coi_alien_orbital_phases.txt',
    'common\raids\nuclear_raids.txt',
    'events\coi_alien_gateway_events.txt',
    'localisation\english\coi_alien_gateway_l_english.yml'
)
foreach ($relativePath in $paths) { [void](Require-File $relativePath) }

$building = [IO.File]::ReadAllText((Join-Path $modRoot 'common\buildings\coi_alien_gateway_buildings.txt'))
Require-Count $building '^\s*coi_alien_energy_gateway\s*=\s*\{' 1 'Energy Gateway building definition must be unique'
foreach ($contract in @('is_buildable\s*=\s*no', 'state_max\s*=\s*3', 'damage_factor\s*=\s*1')) {
    if ($building -notmatch $contract) { $errors.Add("Energy Gateway missing contract: $contract") }
}
if ($building -match '(?m)^\s*need_supply\s*=') {
    $errors.Add('Energy Gateway must not require terrestrial supply')
}

$navalBuildings = [IO.File]::ReadAllText((Join-Path $modRoot 'common\buildings\coi_alien_naval_buildings.txt'))
Require-Count $navalBuildings '^\s*coi_alien_mothership_anchorage\s*=\s*\{' 1 'Mothership Anchorage building definition must be unique'
if ($navalBuildings -notmatch '(?s)coi_alien_mothership_anchorage\s*=\s*\{.*?\bdamage_factor\s*=\s*0') {
	$errors.Add('The province-scoped Mothership Anchorage must be damage-immune so its online state is engine-observable')
}

$equipment = [IO.File]::ReadAllText((Join-Path $modRoot 'common\units\equipment\coi_alien_orbital_equipment.txt'))
foreach ($contract in @(
    'coi_alien_orbital_sentinel_equipment\s*=\s*\{',
    'coi_alien_orbital_sentinel_equipment_1\s*=\s*\{',
    '(?m)^\s*type\s*=\s*missile\s*$',
    '(?m)^\s*air_map_icon_frame\s*=\s*9\s*$',
    'can_license\s*=\s*no',
    'can_be_lend_leased\s*=\s*\{\s*always\s*=\s*no\s*\}',
    'can_be_produced\s*=\s*\{\s*always\s*=\s*no\s*\}'
)) {
    if ($equipment -notmatch $contract) { $errors.Add("Sentinel equipment missing contract: $contract") }
}

$dynamicModifiers = [IO.File]::ReadAllText((Join-Path $modRoot 'common\dynamic_modifiers\coi_alien_orbital_dynamic_modifiers.txt'))
Require-Count $dynamicModifiers '^\s*nuclear_production_factor\s*=\s*-' 2 'Both Atomic Disruption tiers must suppress atomic production'
Require-Count $dynamicModifiers '^\s*thermonuclear_production_factor\s*=\s*-' 2 'Both Atomic Disruption tiers must suppress thermonuclear production'

$decisions = [IO.File]::ReadAllText((Join-Path $modRoot 'common\decisions\coi_alien_gateway_decisions.txt'))
foreach ($id in @(
    'coi_alien_construct_energy_gateway',
    'coi_alien_upgrade_energy_gateway_tier_two',
    'coi_alien_upgrade_energy_gateway_tier_three',
    'coi_alien_print_needle_batch',
    'coi_alien_print_gleam_batch',
    'coi_alien_print_orbital_sentinel',
    'coi_alien_offer_orbital_protection_accord',
    'coi_alien_revoke_orbital_protection_accord'
)) {
    Require-Count $decisions ("^\s*" + [regex]::Escape($id) + '\s*=\s*\{') 1 "Decision $id must be unique"
}
foreach ($literal in @(
    'coi_alien_gateway_committed_count < 3',
    'coi_alien_fabrication_capacity = -20',
    'coi_alien_fabrication_capacity = -15',
    'coi_alien_orbital_sentinel_equipment < 12'
)) {
    if (-not $decisions.Contains($literal)) { $errors.Add("Decision contract missing: $literal") }
}
foreach ($airframeContract in @(
    'type\s*=\s*coi_alien_needle_equipment_3\s+amount\s*=\s*20',
    'type\s*=\s*coi_alien_needle_equipment_4\s+amount\s*=\s*30',
    'type\s*=\s*coi_alien_gleam_equipment_3\s+amount\s*=\s*12',
    'type\s*=\s*coi_alien_gleam_equipment_4\s+amount\s*=\s*18'
)) {
    Require-Count $decisions $airframeContract 1 "Printed-aircraft batch contract $airframeContract must be unique"
}
Require-Count $decisions 'coi_alien_(?:needle|gleam)_equipment_[12]\b' 0 'Fabrication batches must never emit legacy aircraft generations'
Require-Count $decisions 'add_to_variable\s*=\s*\{\s*coi_alien_gateway_committed_count\s*=\s*1\s*\}' 1 'A new Gateway order must reserve one slot immediately'
Require-Count $decisions 'clamp_variable\s*=\s*\{\s*var\s*=\s*coi_alien_gateway_committed_count\s+min\s*=\s*0\s+max\s*=\s*3\s*\}' 1 'The same-day Gateway reservation must remain clamped'
Require-Count $decisions 'coi_alien_reconcile_gateway_committed_count_effect\s*=\s*yes' 3 'Gateway completion and both refund paths must reconcile the cap'
Require-Count $decisions 'add_command_power\s*=\s*25\s*$' 2 'Gateway failure and cancellation must retain their command-power refunds'
if ($decisions -match 'coi_alien_gateway_committed_count\s*=\s*-1') {
    $errors.Add('Gateway refunds must reconcile current commitments instead of blindly decrementing the cap')
}

$effects = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_effects\coi_alien_gateway_effects.txt'))
Require-Count $effects '^coi_alien_reconcile_mothership_anchorage_status_effect\s*=\s*\{' 1 'Anchorage health reconciliation effect must be unique'
foreach ($contract in @(
    'coi_alien_has_healthy_mothership_anchorage_trigger\s*=\s*yes',
    'coi_alien_activate_mothership_anchorage\s*=\s*yes',
    'coi_alien_shutdown_mothership_anchorage\s*=\s*yes'
)) {
    if ($effects -notmatch $contract) { $errors.Add("Anchorage health reconciliation missing contract: $contract") }
}
Require-Count $effects '^coi_alien_initialize_basic_sentinel_reserve_effect\s*=\s*\{' 1 'Basic Sentinel reserve initializer must be unique'
foreach ($contract in @(
    'has_tech\s*=\s*coi_alien_predictive_intercept_lattice',
    'has_idea\s*=\s*coi_alien_mothership_anchorage_online',
    'has_country_flag\s*=\s*coi_alien_basic_sentinel_reserve_stocked',
    'has_equipment\s*=\s*\{\s*coi_alien_orbital_sentinel_equipment\s*<\s*1\s*\}',
    'type\s*=\s*coi_alien_orbital_sentinel_equipment_1\s+amount\s*=\s*3\s+producer\s*=\s*XAC',
    'set_country_flag\s*=\s*coi_alien_basic_sentinel_reserve_stocked'
)) {
    if ($effects -notmatch $contract) { $errors.Add("Basic Sentinel reserve missing contract: $contract") }
}
Require-Count $effects '^coi_alien_reconcile_gateway_committed_count_effect\s*=\s*\{' 1 'Gateway commitment reconciliation effect must be unique'
foreach ($contract in @(
    'set_variable\s*=\s*\{\s*coi_alien_gateway_committed_count\s*=\s*0\s*\}',
    'every_owned_state\s*=\s*\{',
    'is_controlled_by\s*=\s*ROOT',
    'coi_alien_energy_gateway\s*>\s*0',
    'has_state_flag\s*=\s*coi_alien_gateway_construction_in_progress',
    'add_to_variable\s*=\s*\{\s*coi_alien_gateway_committed_count\s*=\s*1\s*\}',
    'clamp_variable\s*=\s*\{\s*var\s*=\s*coi_alien_gateway_committed_count\s+min\s*=\s*0\s+max\s*=\s*3\s*\}'
)) {
    if ($effects -notmatch $contract) { $errors.Add("Gateway commitment reconciliation missing contract: $contract") }
}
$outputEffect = Get-ClausewitzBlock $effects 'coi_alien_recalculate_gateway_output_effect'
if ($null -eq $outputEffect) {
    $errors.Add('Gateway output reconciliation effect could not be parsed')
}
else {
    Require-Count $outputEffect 'set_variable\s*=\s*\{\s*coi_alien_gateway_productive_count\s*=\s*0\s*\}' 1 'Gateway productivity selector must start from zero'
    Require-Count $outputEffect 'ROOT\s*=\s*\{\s*check_variable\s*=\s*\{\s*coi_alien_gateway_productive_count\s*<\s*3\s*\}\s*\}' 1 'Gateway output must stop selecting structures at three'
    Require-Count $outputEffect 'add_to_variable\s*=\s*\{\s*coi_alien_gateway_productive_count\s*=\s*1\s*\}' 1 'Each selected Gateway must consume one productive slot'
    Require-Count $outputEffect 'set_state_flag\s*=\s*coi_alien_gateway_productive' 1 'Selected Gateways must be marked productive'
    Require-Count $outputEffect 'set_state_flag\s*=\s*coi_alien_gateway_dormant_over_cap' 1 'Excess healthy Gateways must be marked dormant'
    Require-Count $outputEffect 'clr_state_flag\s*=\s*coi_alien_gateway_productive' 1 'Productive Gateway state must be rebuilt idempotently'
    Require-Count $outputEffect 'clr_state_flag\s*=\s*coi_alien_gateway_dormant_over_cap' 1 'Dormant Gateway state must be rebuilt idempotently'
    Require-Count $outputEffect 'clear_variable\s*=\s*coi_alien_gateway_productive_count' 1 'Temporary Gateway productivity counter must be cleared'
    if ($outputEffect -notmatch 'check_variable\s*=\s*\{\s*coi_alien_gateway_productive_count\s*<\s*3\s*\}[\s\S]*?set_state_flag\s*=\s*coi_alien_gateway_productive[\s\S]*?add_to_variable\s*=\s*\{\s*coi_alien_gateway_productive_count\s*=\s*1\s*\}[\s\S]*?add_to_variable\s*=\s*\{\s*coi_alien_gateway_desired_mil\s*=\s*2\s*\}') {
        $errors.Add('Gateway base output is not nested behind the three-structure productivity selector')
    }
}
Require-Count $effects 'limit\s*=\s*\{\s*NOT\s*=\s*\{\s*has_variable\s*=\s*coi_alien_fabrication_capacity\s*\}\s*\}' 1 'Gateway migration must guard fabrication-capacity initialization'
Require-Count $effects 'set_variable\s*=\s*\{\s*coi_alien_fabrication_capacity\s*=\s*0\s*\}' 1 'Gateway migration must initialize fabrication capacity exactly once'
foreach ($literal in @(
    'type = arms_factory level = coi_alien_gateway_mil_delta',
    'type = industrial_complex level = coi_alien_gateway_civ_delta',
    'type = dockyard level = coi_alien_gateway_dock_delta',
    'max = 100',
    'amount = -1',
    'add_nuclear_bombs = -1'
)) {
    if (-not $effects.Contains($literal)) { $errors.Add("Gateway/orbital effect contract missing: $literal") }
}
foreach ($threshold in @(0, 1, 2)) {
    Require-Count $effects ("level\s*>\s*" + $threshold) 1 "Gateway cumulative undamaged-tier threshold $threshold must be unique"
}
Require-Count $effects 'coi_alien_operation_state_has_nuclear_launch_site_trigger\s*=\s*yes' 3 'Every Atomic Disruption damage tier must revalidate the selected launch site'
Require-Count $effects 'type\s*=\s*coi_alien_orbital_sentinel_equipment_1\s+amount\s*=\s*-1\s+producer\s*=\s*XAC' 2 'Atomic and thermonuclear interceptions must each consume a finite Sentinel on their attrition roll'

$onActions = [IO.File]::ReadAllText((Join-Path $modRoot 'common\on_actions\coi_alien_gateway_on_actions.txt'))
Require-Count $onActions 'coi_alien_reconcile_mothership_anchorage_status_effect\s*=\s*yes' 3 'Anchorage health must reconcile at startup, daily, and on control changes'
Require-Count $onActions 'coi_alien_initialize_basic_sentinel_reserve_effect\s*=\s*yes' 3 'Basic Sentinel reserve migration must run at startup, daily, and after control restoration'
Require-Count $onActions 'coi_alien_reconcile_gateway_committed_count_effect\s*=\s*yes' 3 'Gateway commitments must reconcile at startup, daily, and on control changes'
Require-Count $onActions 'is_operation_type\s*=\s*coi_alien_atomic_disruption' 1 'Atomic Disruption must trigger immediate AI replanning'

$triggers = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_triggers\coi_alien_gateway_triggers.txt'))
Require-Count $triggers '^coi_alien_has_healthy_mothership_anchorage_trigger\s*=\s*\{' 1 'Healthy Anchorage trigger must be unique'
Require-Count $triggers 'building\s*=\s*coi_alien_mothership_anchorage' 1 'Healthy Anchorage trigger must check physical province-building presence exactly once'
if ($triggers -match '(?s)non_damaged_building_level\s*=\s*\{\s*building\s*=\s*coi_alien_mothership_anchorage') {
	$errors.Add('Province-scoped Anchorage must not use the state-building-only non_damaged_building_level trigger')
}
foreach ($contract in @(
    'any_owned_state\s*=\s*\{',
    'is_controlled_by\s*=\s*ROOT',
    'has_tech\s*=\s*coi_alien_predictive_intercept_lattice',
    'has_equipment\s*=\s*\{\s*coi_alien_orbital_sentinel_equipment\s*>\s*0\s*\}',
    'has_tech\s*=\s*coi_alien_sentinel_reserve_fabrication',
    'has_tech\s*=\s*coi_alien_atomic_disruption_protocols'
)) {
    if ($triggers -notmatch $contract) { $errors.Add("Anchorage/Sentinel trigger contract missing: $contract") }
}

$navalEffects = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_effects\coi_alien_naval_effects.txt'))
Require-Count $navalEffects '^\s*coi_alien_has_healthy_mothership_anchorage_trigger\s*=\s*yes\s*$' 2 'Anchorage activation and Tic Tac registration must both validate physical ownership and control'
Require-Count $navalEffects '^coi_alien_shutdown_mothership_anchorage\s*=\s*\{' 1 'Anchorage shutdown effect must remain unique'

$airEquipment = [IO.File]::ReadAllText((Join-Path $modRoot 'common\units\equipment\coi_alien_naval_and_air_equipment.txt'))
foreach ($equipmentId in @(
    'coi_alien_needle_equipment_3',
    'coi_alien_needle_equipment_4',
    'coi_alien_gleam_equipment_3',
    'coi_alien_gleam_equipment_4'
)) {
    Require-Count $airEquipment ("^\s*" + [regex]::Escape($equipmentId) + '\s*=\s*\{') 1 "Printed aircraft equipment $equipmentId must be unique"
}

$gatewayEvents = [IO.File]::ReadAllText((Join-Path $modRoot 'events\coi_alien_gateway_events.txt'))
Require-Count $gatewayEvents '^\s*id\s*=\s*coi_alien_gateway\.14\s*$' 1 'Basic Sentinel field-reserve event must be unique'

$aiPlanner = [IO.File]::ReadAllText((Join-Path $modRoot 'common\scripted_effects\coi_alien_operation_ai_effects.txt'))
Require-Count $aiPlanner 'coi_alien_ai_operation_type\s*=\s*token:coi_alien_atomic_disruption' 1 'Quiet Chorus AI planner must select Atomic Disruption'
foreach ($literal in @(
    'has_tech = coi_alien_atomic_disruption_protocols',
    'coi_alien_target_has_nuclear_strike_assets_trigger = yes',
    'has_dynamic_modifier = coi_alien_atomic_disruption_degraded',
    'has_dynamic_modifier = coi_alien_atomic_disruption_critical'
)) {
    if (-not $aiPlanner.Contains($literal)) { $errors.Add("Atomic Disruption AI gate missing: $literal") }
}

$operation = [IO.File]::ReadAllText((Join-Path $modRoot 'common\operations\coi_alien_orbital_operations.txt'))
foreach ($literal in @(
    'days = 120',
    'operatives = 3',
    'coi_alien_token_institutional_access',
    'coi_alien_token_research_access',
    'has_tech = coi_alien_atomic_disruption_protocols'
)) {
    if (-not $operation.Contains($literal)) { $errors.Add("Atomic Disruption operation missing: $literal") }
}

$vanillaRaidPath = Join-Path $GameRoot 'common\raids\nuclear_raids.txt'
$expectedHash = '966408C81EBA9F5928ED352D5F95F6648977B23A8E12CE9AA2CD2CDBCA76256F'
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $vanillaRaidPath).Hash
if ($actualHash -ne $expectedHash) {
    $errors.Add("Installed nuclear_raids.txt hash is $actualHash; override expects $expectedHash")
}
$raids = [IO.File]::ReadAllText((Join-Path $modRoot 'common\raids\nuclear_raids.txt'))
Require-Count $raids '^\s*coi_alien_atomic_disruption\s*=\s*\{' 6 'Atomic Disruption must affect all six nuclear raid types'
Require-Count $raids '^\s*coi_alien_orbital_intercept_lattice\s*=\s*\{' 4 'Sentinels must affect only four missile raid types'
Require-Count $raids 'coi_alien_resolve_orbital_atomic_interception_effect\s*=\s*yes' 4 'Atomic missile failure/limited hooks'
Require-Count $raids 'coi_alien_resolve_orbital_thermonuclear_interception_effect\s*=\s*yes' 4 'Thermonuclear missile failure/limited hooks'
Require-Count $raids 'coi_alien_orbital_target_has_basic_defense_trigger\s*=\s*yes\s+add\s*=\s*35' 4 'Basic Sentinel protection must subtract 35 points from all missile raids'
Require-Count $raids 'coi_alien_orbital_target_has_sentinel_defense_trigger\s*=\s*yes\s+add\s*=\s*20' 4 'Sentinel Reserve Fabrication must raise protection from 35 to 55'
Require-Count $raids 'coi_alien_orbital_target_has_atomic_defense_trigger\s*=\s*yes\s+add\s*=\s*15' 4 'Atomic Disruption Protocols must raise protection from 55 to 70'
foreach ($raidId in @(
    'nuclear_strike',
    'nuclear_missile_strike',
    'nuclear_missile_strike_submarine',
    'thermonuclear_strike',
    'thermonuclear_missile_strike',
    'thermonuclear_missile_strike_submarine'
)) {
    Require-Count $raids ("^\s*" + [regex]::Escape($raidId) + '\s*=\s*\{') 1 "Vanilla raid $raidId must remain unique"
}

$locPath = Join-Path $modRoot 'localisation\english\coi_alien_gateway_l_english.yml'
$bytes = [IO.File]::ReadAllBytes($locPath)
if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
    $errors.Add('Gateway localization is not UTF-8 with BOM')
}
$loc = [IO.File]::ReadAllText($locPath)
foreach ($key in @(
    'coi_alien_energy_gateway',
    'coi_alien_orbital_sentinel_equipment',
    'coi_alien_gateway_category',
    'coi_alien_atomic_disruption',
    'success_modifier_coi_alien_orbital_intercept_lattice',
    'coi_alien_gateway.14.t',
    'coi_alien_gateway.14.desc',
    'coi_alien_gateway.14.a'
)) {
    Require-Count $loc ("^\s*" + [regex]::Escape($key) + ':') 1 "Localization key $key must be unique in gateway file"
}

if ($errors.Count -gt 0) {
    Write-Host "Gateway/orbital validation FAILED ($($errors.Count) problem(s)):" -ForegroundColor Red
    foreach ($errorMessage in $errors) { Write-Host "  - $errorMessage" -ForegroundColor Red }
    exit 1
}

Write-Host 'Gateway/orbital validation PASSED:' -ForegroundColor Green
Write-Host '  - three-tier, three-node Gateway network and reversible off-map output'
Write-Host '  - deterministic three-structure productivity cap with non-destructive excess dormancy'
Write-Host '  - capped fabrication batches and non-transferable Sentinel reserve'
Write-Host '  - protected-country missile interception and Atomic Disruption operation'
Write-Host "  - vanilla nuclear-raid override pinned to $expectedHash"
