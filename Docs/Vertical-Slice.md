# Alien Crisis First Vertical Slice

Status: implementation target and acceptance contract. The Point Nemo map path
and explicit XAC full-mod boots now pass, including custom naval units, the
exact starting naval OOB, and air stockpile. A live Steam screenshot confirms
the headline XAC map state, but detailed panels and save/reload testing still
prevent the complete contract from being marked passed.

## Objective

Prove one understandable, save-safe playable loop before expanding the species,
land equipment, project tree, or narrative campaign:

`Unaware -> Anomalies -> Suspicious -> Confirmed -> Mobilized -> selected landfall -> war -> resolution`

Awareness is national, not one global phase. Countries can occupy different
steps at the same time. The wider invasion and resolution phases will later be
integrated into Century of Iron's endgame timeline.

## Implemented foundation

### Static 1936 setup

- `XAC` is a static playable country from the 1936 start; it is not a dormant
  landless tag waiting to be activated.
- Pale Anchorage at Point Nemo is its capital, core, and starting territory:
  state `1082`, province `13414`.
- The state uses custom 16-slot category `coi_alien_arcology`. Its 2 civilian,
  4 military, 6 dockyard, and 2 fuel-silo levels occupy 14 shared slots and
  leave two for expansion, alongside the prototype anchorage, naval base, air
  base, supply, and defensive infrastructure.
- The startup hook initializes the awareness framework and the XAC expedition
  idempotently. Crisis rules govern disclosure and landfall access, not whether
  XAC or Pale Anchorage exists.

### Awareness and rules

- Every country has saved variable `coi_alien_awareness`, clamped to:

  | Value | Name | Meaning |
  |---:|---|---|
  | 0 | Unaware | No accepted evidence. |
  | 1 | Anomalies | Isolated unexplained incidents. |
  | 2 | Suspicious | A connected hostile pattern is suspected. |
  | 3 | Confirmed | The extraterrestrial actor is confirmed. |
  | 4 | Mobilized | National institutions are actively preparing. |

- Normal gameplay effects only raise awareness. Exact assignments, including
  lower stages, are debug controls.
- The implemented operations are Silent Survey, Specimen Acquisition, and
  Infrastructure Probe, with visibility and targeting gated by awareness.
- Start modes are Inert, Hidden, Immediate Disclosure, and Immediate Landfall.
  Inert disables crisis processing but does not remove the playable XAC start.

### Player-selected landfall

- Landfall preparation is an explicit player choice, either from the XAC target
  interface or the eligible human country's prepare-here decision.
- The first legal choice is saved as the single target and is not rerolled on
  reload.
- Preparation raises that country to at least `3 Confirmed` and grants `XAC`
  `coi_alien_landfall_wargoal` against it.
- Preparation does **not** declare war and does **not** transfer state ownership
  or control. Any later territorial change belongs to war, occupation, or a
  separately scripted settlement.
- Immediate Landfall bypasses the normal awareness gate for target selection,
  then still raises the selected target to Confirmed and uses the same saved,
  one-time preparation flow.

### Starting naval-air expedition

- The Pale Horizon mothership pattern and Silent Current escort pattern form
  the initial naval kernel. Country history registers both modular designs and
  calls `set_naval_oob = "XAC_1936_naval"`; the canonical loader reads
  `history/units/XAC_1936_naval.txt` and bases one Pale Horizon plus four named
  escorts at province `13414`. Runtime `create_ship` is not the fleet loader.
- The separately guarded startup hook adds 30 Needle interceptors and 20 Gleam
  strike craft to XAC's stockpile. Deployment as operational air wings remains
  a separate gameplay and AI task.
- The anchorage, expeditionary naval architecture, aircraft programs, equipment
  variants, and online-anchorage national rule are namespaced prototype assets.

## Runtime evidence as of 2026-08-30

- `TestUserDirMinimalState8` loaded 13,415 provinces and completed the in-game
  device-object handoff with the isolated Point Nemo state payload.
- `TestUserDirFull7_GER` proved the custom sub-unit correction removed Full6's
  locked `ship_hull_carrier`/`ship_hull_light` equipment-requirements warning.
- `TestUserDirFull8_XAC` and `TestUserDirFull9_XAC_Windowed` explicitly booted
  as XAC, accepted both custom naval units/designs, reached
  `End RestoreDeviceObjects`, reported the exact 1+4 Point Nemo fleet, and
  stocked exactly 30 Needle plus 20 Gleam craft.
- Full9 has no tech-grid, missing-localisation, state, map, scope, or
  `create_ship` warnings. Its ten remaining error entries are the eight expected
  equipment-enum documentation notices and two vanilla/test-harness remote-file
  allocation warnings.
- A Steam screenshot captured during the Full9 test visually confirms the Grey
  flag, Pale Anchorage label, 100.00K manpower, and
  five-ship stack in the live XAC session.
- The DirectX capture/input helper failed before opening the detailed politics,
  portrait, state, and naval panels. Those details, deployed air wings, combat,
  and save/reload idempotence remain unproven.

## Remaining vertical-slice content

- A small land expedition with shock, autonomous-support, and heavy-assault
  roles plus bounded off-world reinforcement.
- One alien adaptation project and one human reverse-engineering project.
- An alien strike or reconnaissance raid and a human anti-anchorage operation.
- AI plans for XAC projection, anchorage defense, human preparation, and target
  response.
- Human and alien outcomes with idempotent war cleanup and short epilogues.

## Explicit exclusions

- A complete Grey biology, culture, language, motive, and polished lore bible.
- New top-level ideology.
- Full alien navy or broad ship generation tree.
- Full focus tree or large land-equipment generation tree.
- Multiple simultaneous prepared landfalls, global coalition politics, or an
  alien civil war.
- Final 3D models, animation set, soundtrack, or voice pack.
- Direct edits to Century of Iron before the documented adapter is built.

## Acceptance tests

These remain the acceptance contract. Full8/Full9 materially prove the
fresh-boot and headline-visual portions of tests 1, 2, 9, and 10. Detailed panel,
deployed-air, and save/reload clauses remain open.

1. A fresh 1936 game presents playable `XAC` at state `1082`, with capital and
   core intact, the 16-slot arcology accepted, and no unintended human territory.
2. The country-history OOB loads the exact 1+4 fleet and startup stocks exactly
   30/20 aircraft no more than once, including after save/reload and startup
   reconciliation.
3. Every extant country initializes to the correct awareness value; released
   countries initialize without a daily world scan.
4. Normal operations never lower awareness, never exceed `4`, and survive
   save/reload at each stage.
5. Inert, Hidden, Immediate Disclosure, and Immediate Landfall each produce the
   documented framework state while leaving XAC playable.
6. A legal player-selected target is saved exactly once and becomes Confirmed
   if it was below that stage.
7. Preparation grants only the special XAC war goal: it neither declares war
   nor changes any state's owner or controller.
8. Reset/debug controls clean up the target and war goal without lowering
   awareness through normal gameplay paths or duplicating effects.
9. The anchorage has a valid coastal port connection, the OOB fleet is based at
   province `13414`, and the aircraft stock can be deployed through supported
   gameplay.
10. Custom equipment, technologies, characters, ideas, buildings, decisions,
    and localisation load without unknown-token or missing-reference errors.
11. Saves load before and after target preparation without rerolls, duplicate
    assets, or divergent global targets.
12. Two-player multiplayer produces the same target, awareness, and war-goal
    state for both peers.
13. A 12-month observer run shows no runaway spawning or daily-loop performance
    regression.

## Build order

1. Open and capture XAC's politics, portrait, state, naval, and air panels to
   verify the capital, core, arcology, buildings, leaders, basing, and equipment
   details not visible in the Steam map screenshot.
2. Repeat the proven 1+4 OOB and 30/20 stockpile across save/reload, then deploy
   and exercise the air complement without duplication.
3. Prove awareness operations, the exact five-stage ladder, and all game rules.
4. Prove player-selected landfall preparation with no automatic transfer.
5. Add the bounded land expedition and production/AI support.
6. Add alien and human projects, scientists, and raids.
7. Add war objectives, outcomes, settlements, cleanup, and epilogues.
8. Complete single-player, observer, multiplayer, and performance validation.

Only after all acceptance tests pass should the prototype scale into the full
alien roster, multiple landing patterns, internal politics, global diplomacy,
and its Century of Iron integration adapter.
