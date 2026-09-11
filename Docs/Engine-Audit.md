# Alien Crisis Engine Audit

Audit date: 2026-08-29. Local authority: Hearts of Iron IV 1.19.2.0,
Operation Postern, Steam build 23969257.

The entries below distinguish documented engine capability from runtime proof.
Point Nemo and the complete payload now boot explicitly as XAC. Custom naval
units, the exact 1+4 OOB, the 30/20 air stockpile, and the headline live map
view are proven. Detailed panels, save/load, AI, combat, and multiplayer remain
unvalidated.

## Verified capabilities

| Capability | Local evidence | Design use |
|---|---|---|
| Static countries | `common/country_tags`, `common/countries`, `history/countries` | Playable `XAC` owns Pale Anchorage from the 1936 start. |
| Dynamic countries | `create_dynamic_country`, `reserve_dynamic_country` in `documentation/effects_documentation.md` | Later schisms, protectorates, or collaborators. |
| Player handoff | `change_tag_from` in `documentation/effects_documentation.md` | Future Century of Iron switch only; standalone XAC is selectable in 1936. |
| Runtime territory | `set_state_owner_to`, `set_state_controller_to`, `transfer_state_to` | Future occupation and settlement only; landfall preparation performs no transfer. |
| Runtime forces | `set_naval_oob`, history OOB schema, equipment stockpile effects | Proven 1+4 Point Nemo fleet and 30/20 carrier-air stockpile. |
| Off-map industry | `add_offsite_building` and removal counterpart | Orbital/fleet fabrication capacity. |
| Map visuals | `create_entity`/`destroy_entity`, including position, height, scale, and visibility | Mothership and gateway presentation. |
| Raids | `common/raids/_documentation.md` | Orbital attacks and anti-gateway operations. |
| Special projects | `common/special_projects/**/documentation.md` | Alien adaptation and human reverse engineering. |
| Scientists | `common/characters/_documentation.md` and scientist traits | Named researchers assigned to facilities. |
| Equipment | `common/units/equipment/_documentation.md` | Alien weapons, platforms, drones, and craft. |
| AI strategies | `common/ai_strategy/_documentation.md` | Fronts, production, research, air, raids, construction. |
| AI templates | `common/ai_templates/_documentation.md` | Alien force composition. |
| Doctrine folders | `common/doctrines/**/_documentation.md` | Additive alien doctrine package. |
| Occupation | `common/occupation_laws/occupation_laws.txt` | Alien administration and human resistance. |
| Scripted settlement | `white_peace`, state effects, `start_peace_conference` | Nonstandard crisis outcomes. |
| Faction templates | `common/factions/_documentation.md` and shipped templates | Optional voluntary unification route. |
| On-actions | `common/on_actions/_documentation.md` | War, capitulation, state control, peace, nuke, invasion hooks. |

## High-value details

### Country creation and statehood

- The game registers 364 fixed country tags and 75 shared dynamic slots,
  `D01`–`D75`, in the inspected build.
- Dynamic tags are shared temporary resources; they are unsuitable for the main
  invader. Use them only for disposable or tracked splinters.
- Vanilla Israel is a useful dormant-country pattern. It proves a registered
  tag may await later appearance.
- Ownership and cores are state-level. Permanent ownership of half a state is
  impossible even though individual province control exists during war.
- The implemented prototype avoids zero-state activation: `XAC` owns and cores
  state `1082`, has capital `1082`, and is selectable in 1936. Province `13414`
  is its only starting province.
- State `1082` uses custom category `coi_alien_arcology` with 16 local building
  slots. Its 14 shared starting levels are 2 civilian, 4 military, 6 dockyard,
  and 2 fuel-silo levels; two slots remain. A one-person state sentinel removes
  the engine's zero-population diagnostic without supplying recruitable Grey
  manpower.
- Retain every human core. If surrender logic needs it, give `XAC` only a
  temporary core through a later, explicitly tested settlement path. Landfall
  preparation itself never changes cores, ownership, or control.

### Starting naval-air OOB

- Runtime `create_ship` did not instantiate the custom modular hulls reliably.
  The canonical and now proven path registers the equipment variants in country
  history, then calls `set_naval_oob = "XAC_1936_naval"`.
- `history/units/XAC_1936_naval.txt` creates one Pale Horizon and four Silent
  Current escorts in a task force explicitly based at province `13414`.
- The startup verifier separately and idempotently grants 30 Needle interceptors
  and 20 Gleam strike craft. Keeping the air grant independent prevents an OOB
  reconciliation retry from duplicating aircraft.

### Special projects

- `allowed` is evaluated at startup and accepts only limited conditions. Use it
  for tag/original-tag/DLC instantiation; use `visible` and `available` for
  crisis-phase gates.
- Projects have parent chains, breakthrough costs, prototype time, resource
  drain, complexity, AI weights, completion outputs, and iterative rewards.
- Outputs can enable equipment, modules, and sub-units and run effects on the
  country, facility state, or scientist.
- Scripted completion can lack a facility or scientist, so guaranteed unlocks
  cannot depend on those optional scopes.
- A specialization and its facility building must be aligned one-to-one. New
  alien specializations are feasible but not free.
- Local source:
  `common/special_projects/projects/documentation.md`,
  `common/special_projects/specialization/documentation.md`, and
  `common/special_projects/prototype_rewards/documentation.md`.

### Technology, equipment, and doctrine

- Adding a branch to an existing technology folder is additive. A completely
  new tab requires editing fixed entries in `interface/countrytechtreeview.gui`.
- New equipment archetypes, variants, modules, module categories, equipment
  groups, sub-units, and AI designs can be additive.
- Operation Postern's new doctrine database supports additive folders, grand
  doctrines, tracks, and subdoctrines.
- The shipped airborne mothership aircraft/project is an implementation example
  for project-gated unusual aircraft; it does not simulate an orbital layer.
- Modular ground vehicles, aircraft, ships, and MIOs introduce their respective
  DLC dependencies and AI-design obligations.

### Raids

- Categories may allow free province targeting.
- Raid targets may be provinces, states, or buildings.
- A raid may require units, equipment, stockpile assets, command power,
  preparation time, and a valid physical starting point.
- Four native result tiers are available: failure, limited success, success,
  and critical success.
- AI weights, minimum success chance, map icons, moving entities, animations,
  sounds, and effects are scriptable.
- Pale Anchorage supplies a real terrestrial naval/air starting point before a
  human target is chosen. Use events for truly orbital actions that still lack
  a valid physical raid origin; use the anchorage or a later gateway for native
  raids where its category and unit requirements permit.

### Character and art limits

- Useful character roles include country leader, field marshal, corps
  commander, navy leader, advisor, and scientist. There is no air-force
  commander character role.
- Generated character pools are internally male/female and default to human
  names/faces unless the mod supplies controlled alien pools.
- Measured vanilla references: 156x210 scientist portrait, 161x98 project icon,
  146x54 equipment/technology icon, and 24x33 scientist-trait icon.
- Flags use 82x52, 41x26, and 10x7 textures.
- The install has PDX exporter settings but no exporter executable. Bespoke 3D
  work needs a separate mesh-export pipeline.

### Country and map limits

- Runtime effects can activate a predefined tag or create a dynamic derivative,
  but the province/state map itself is static.
- No supported orbital province, state, strategic region, or unit layer was
  found. Treat orbit as a strategic system.
- A scripted entity can depict a mothership but has no inherent country, combat,
  supply, or pathfinding behavior.
- A country can belong to only one ordinary faction. A universal defense system
  should preserve existing alliances unless a voluntary political outcome
  replaces them.
- The 30/20 custom-air stockpile grant is runtime-proven. Deployment into wings,
  carrier assignment, missions, visuals, and AI use still need testing because
  air OOBs reference fixed states and stockpile success alone proves none of
  those player-facing behaviors.

### Resources and production

- The current databases contain oil, aluminium, rubber, tungsten, steel,
  chromium, and coal; coal participates in the 1.19 energy system.
- Oil is explicitly forbidden as a special-project resource cost.
- There is no per-equipment electricity-cost field.
- A new eighth resource would require fixed resource-strip and production/trade
  interface overrides. Use a saved exotic-matter inventory first.
- Off-map factories are invulnerable. Cap them and make their use dependent on
  destructible gateway state.

### Peace and end-of-game limits

- Script can stop wars, restore/transfer territory, clean up units/buildings,
  apply subjects, or launch a normal peace conference.
- Exposed peace-conference actions remain built-in families such as taking
  states, puppeting, forcing government, and liberating. A wholly new “alien
  treaty” action should be an event/decision settlement.
- No documented effect opens the final score screen. The crisis should produce
  an epilogue and permanent state; Century of Iron's configured end date can
  finish the campaign normally.

## Runtime evidence: 2026-08-30

- `TestUserDirMinimalState8/logs/game.log` loaded 13,415 provinces and completed
  the device-object restoration handoff with the isolated Point Nemo state.
- `TestUserDirFull7_GER` is the first run after the custom mothership and escort
  sub-unit correction. It retained the exact 1+4 count and eliminated Full6's
  locked `ship_hull_carrier`/`ship_hull_light` requirements warning.
- `TestUserDirFull8_XAC` and `TestUserDirFull9_XAC_Windowed` explicitly booted
  XAC, accepted the custom units and designs, reached
  `End RestoreDeviceObjects`, reported the complete 1+4 alien fleet, and logged
  exactly 30 Needle plus 20 Gleam craft stocked.
- Full9 has no tech-grid, missing-localisation, state, map, scope, or
  `create_ship` warnings. Its error log has only eight hardcoded equipment-enum
  documentation notices and two expected vanilla/test-harness remote-file
  allocation warnings.
- A Steam screenshot captured during the Full9 test proves the live Grey flag,
  Pale Anchorage label, 100.00K manpower, and
  five-ship stack. It does not expose unit models or detailed UI fields.
- The DirectX capture/input helper failed before opening the politics, portrait,
  state, naval, and air panels. Those panel details and all save/reload behavior
  remain outside the proven boundary.

## Runtime evidence: discovery/disclosure 0.4.0

- Fresh Italy and United States launches reached `End RestoreDeviceObjects`
  after the special-project complexity values were changed to the engine's
  named `sp_complexity.small` and `sp_complexity.medium` constants.
- Both final error logs contained only the 12 established hardcoded equipment-
  enum documentation notices: no script, GFX, localization, scope, state, map,
  event, decision, or special-project parse errors were produced.
- A test-only overlay in
  `RuntimeVariants\DisclosureRuntimeTest` asserted the 1933 Italy/Vatican state
  and invoked catastrophic disclosure in a fresh United States run. Both
  assertions logged PASS, including the dual global flags, country crisis
  ledger, and exact monotonic 4/4/4 transition.
- The disclosure overlay is not installed, copied into `Mod`, or included in
  Workshop staging. It exists only as a reproducible diagnostic fixture.
- An unattended later-tick direct-client access violation also reproduces with
  the untouched authenticated 0.3.0 Workshop tree, earlier than the 0.4.0 run.
  It is therefore a limitation of this hidden/headless harness. No claim of a
  successful long-duration simulation is made from those runs.

## Engine spikes still required

These are feasible-looking but must be proven in a running game before content
expands:

1. Open and capture XAC's politics, portraits, Pale Anchorage state/building,
   naval, and air panels; confirm the capital, core, arcology, leaders, research,
   diplomacy, supply, variants, models, and detailed task-force basing fields
   that the live map screenshot cannot show.
2. Save and reload the proven 1+4 fleet and 30/20 stockpile, confirm no duplicate
   grants, then deploy and exercise the aircraft complement.
3. Select and reset a landfall country across save/reload, confirm its awareness
   reaches at least Confirmed, and prove no owner/controller change occurs.
4. Grant and remove the special landfall war goal without an automatic war.
5. Place a custom gateway in a dynamically chosen province, target it with a
   raid, damage/repair it, and show a safe map representation.
6. Confirm an alien project instantiated at startup can become visible at the
   intended awareness/crisis gate for the already-landed XAC country.
7. Produce and deploy custom alien sub-units/equipment through AI templates.
8. Use custom aircraft in normal air missions and as raid visuals/requirements.
9. End a multi-party alien war with scripted cleanup without leaving phantom
   wars, units, occupations, or peace-conference state.
10. Verify any later Century of Iron `change_tag_from` handoff in multiplayer
    and after reload.
11. Confirm alien manpower cannot be drawn from occupied human populations.
12. Measure weekly crisis-controller cost in a late-game 2100 world.

## Performance and synchronization rules

- Initialize with `on_startup`; no exposed `on_game_load` hook was found.
- Make weekly reconciliation idempotent and separately guard transition effects.
- Never use MTTH events or daily global scans for the controller.
- Cache landing candidates; do not evaluate every state at invasion time.
- Keep raid and targeted-decision visibility conditions cheap.
- Resolve randomness once and persist the selected result.
- Give every event choice an AI weight, deterministic default, and timeout where
  appropriate.
- Use a single authoritative controller for global transitions.

## Primary local references

The locally installed game files are the current implementation authority.
Here, `<HOI4_ROOT>` means the installation directory for Hearts of Iron IV:

- `<HOI4_ROOT>/documentation/effects_documentation.md`
- `<HOI4_ROOT>/documentation/triggers_documentation.md`
- `<HOI4_ROOT>/common/characters/_documentation.md`
- `<HOI4_ROOT>/common/special_projects/projects/documentation.md`
- `<HOI4_ROOT>/common/special_projects/specialization/documentation.md`
- `<HOI4_ROOT>/common/special_projects/prototype_rewards/documentation.md`
- `<HOI4_ROOT>/common/raids/_documentation.md`
- `<HOI4_ROOT>/common/units/equipment/_documentation.md`
- `<HOI4_ROOT>/common/ai_strategy/_documentation.md`
- `<HOI4_ROOT>/common/ai_templates/_documentation.md`
- `<HOI4_ROOT>/common/doctrines`
- `<HOI4_ROOT>/common/on_actions/_documentation.md`
- `<HOI4_ROOT>/common/factions/_documentation.md`
- `<HOI4_ROOT>/common/peace_conference`

Primary public cross-check:

- Paradox developer diary, Historical Germany and Götterdämmerung special
  projects:
  https://forum.paradoxplaza.com/forum/threads/developer-diary-historical-germany.1708873/page-3
