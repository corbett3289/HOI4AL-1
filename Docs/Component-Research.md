# Alien Crisis Component Research

Status: architecture plus standalone prototype implementation against local
HOI4 1.19.2 files. The Greys and Grey Consensus are the working species and
polity identities. Detailed lore, art direction, final balance, XAC panel
inspection, and save/load validation remain open; the headline live XAC map
view is now captured.

## Executive conclusion

The alien invasion is feasible as a standalone HOI4 crisis and as a later
Century of Iron endgame module. The strongest implementation is not a second
map layer or an alien faction that behaves exactly like a human major. It is a
hybrid system:

- A static alien country (`XAC`) is playable from the 1936 start at Pale
  Anchorage, Point Nemo; landfall selects a human target rather than creating
  the alien country or transferring it an enclave.
- Orbit is an abstract strategic theater represented by saved variables,
  events, special projects, raids, off-map industry, and visible map entities.
- One or more destructible gateways or reinforcement relays connect orbital
  power to the land war.
- Alien armies are qualitatively superior expeditionary formations with a
  limited off-world force pool, not infinitely spawned divisions.
- Humans gain evidence, preparedness, captured samples, coalition tools, and
  gated reverse-engineering projects.
- Each country advances independently through the implemented awareness ladder:
  Unaware, Anomalies, Suspicious, Confirmed, and Mobilized.
- Outcomes are resolved by scripted crisis settlements. Vanilla peace
  conferences remain available only when an ordinary territorial settlement
  is actually appropriate.

This gives both sides strategic objectives that HOI4 understands: countries,
states, divisions, production, research facilities, raids, buildings, air
regions, occupation, and wars.

## Supported baseline

- Game: Hearts of Iron IV 1.19.2.0, Operation Postern.
- Steam build inspected: 23969257.
- DLC baseline: Götterdämmerung is required for scientists, facilities,
  breakthroughs, prototypes, and special projects.
- Development form: independently loadable local mod.
- Current development package: version `0.6.0`, launcher name
  `Alien Crisis: Grey Consensus [DEV]`.
- Permanent script namespace: `coi_alien_`.
- Provisional static tag: `XAC`; this is an implementation handle, not the
  species or civilization name.
- Working identity: the Grey species and the playable Grey Consensus polity.
- Man the Guns is required by the current modular 1936 naval OOB path; explicit
  fallback behavior remains future work.
- Main-mod destination: later integration into Century of Iron's endgame,
  through a documented adapter rather than direct source coupling.

## Mechanical architecture

The module is divided into four layers.

1. **Crisis core** owns phases, saved state, events, rules, decisions, raids,
   landing selection, settlements, debug controls, and telemetry.
2. **Alien country package** owns the tag, characters, government bridge,
   equipment, units, technology outputs, production, occupation, and AI.
3. **Human-response package** owns evidence, preparedness, diplomatic choices,
   captured technology, counter-projects, collaboration, resistance, and
   recovery.
4. **Adapters** provide either accelerated standalone setup or the Century of
   Iron handoff. The crisis core never reads undocumented main-mod internals.

### Saved awareness and crisis state

The implemented public-awareness state is country-scoped variable
`coi_alien_awareness`, clamped to the exact ladder below:

| Value | Awareness | Primary gameplay |
|---:|---|---|
| 0 | Unaware | No accepted evidence. |
| 1 | Anomalies | Isolated incidents and early investigation. |
| 2 | Suspicious | A connected extraterrestrial pattern is suspected. |
| 3 | Confirmed | The actor is confirmed; ordinary landfall targeting is legal. |
| 4 | Mobilized | National institutions actively prepare for conflict. |

Normal gameplay transitions only raise awareness. Debug assignments can force
an exact stage for testing. The selected landfall country is persisted once as
a global event target and country flag; global flags guard preparation,
disclosure mode, immediate-landfall mode, and reset behavior.

Future Century of Iron phases such as invasion, adaptation, resolution, and
aftermath are a separate global crisis timeline and must not be confused with
the five national awareness values. Future global values can include orbital
control, human unity, command integrity, adaptation, off-world force pool, and
civilian losses.

Each transition receives a one-time guard. Reconciliation may restore a
missing modifier or AI plan, but it must never repeat unit creation, target
selection, war-goal grants, gateway placement, or off-map factory grants.

## Component inventory

This matrix is the master checklist. “Slice” means required for the first
playable vertical slice; “Alpha” means needed before broad campaign testing;
“Later” means it should not block proving the core loop.

| Component | HOI4 content or hook | Purpose | Target |
|---|---|---|---|
| Initialization | game rules, on-actions, scripted effects | Enable, seed, or debug the crisis without accidental activation. | Slice |
| Crisis controller | variables, flags, arrays, weekly pulse | Advance phases and reconcile saved state. | Slice |
| Alien polity | country tag, country definition/history, flags, localisation | Provide a stable playable invader scope. | Slice |
| Landfall | targeted decisions, saved target, special war goal | Let a player prepare one target without automatic war or territory transfer. | Slice |
| Gateway | building/state marker, map entity, modifiers | Make reinforcement and orbital access attackable. | Slice |
| Characters | character database and traits | Ruler, commanders, scientist, advisors, succession. | Slice/Alpha |
| Alien land force | equipment, sub-units, templates, technologies | Deliver the central combat fantasy. | Slice |
| Alien air force | aircraft equipment, missions, AI | Contest airspace and support the gateway. | Slice/Alpha |
| Orbital war | variables, raids, events, entities | Bombardment, interdiction, landing support, interception. | Slice |
| Alien science | projects, scientist traits, hidden application techs | Adaptation and capability choices. | Slice/Alpha |
| Human science | evidence, projects, captured-tech outputs | Let humans learn counters collectively. | Slice/Alpha |
| Alien economy | offsite factories, local production, force-pool decisions | Separate terrestrial manufacture from reinforcement. | Slice |
| Manpower | national rules, scripted reinforcement pool | Prevent recruitment of occupied humans as alien soldiers. | Slice |
| Diplomacy | events, decisions, wars, faction overlay | Cooperation, appeasement, negotiation, collaboration. | Alpha |
| Occupation | occupation laws, resistance/compliance, state modifiers | Distinct occupation choices and human responses. | Alpha |
| Settlements | scripted effects, white peace, state restoration | End the crisis reliably and support multiple outcomes. | Slice/Alpha |
| Alien AI | strategies, templates, production/research/raid weights | Make the invader playable by AI. | Slice |
| Human AI | crisis priorities and decision weights | Make countries respond to the shared threat. | Slice/Alpha |
| Presentation | 2D art, map entities, models, VFX, sound, music | Sell the crisis and communicate its systems. | Alpha/Later |
| Localisation | names, tooltips, news, dynamic epilogues | Explain rules and support narrative variation. | Slice/Alpha |
| Tooling | generators, validators, debug decisions, logs | Keep a large content package safe and reproducible. | Slice |
| Compatibility | adapters and override manifest | Preserve standalone use and later mergeability. | Slice |

## Alien identity and country content

The working names are settled: the species are the Greys and the playable polity
is the Grey Consensus. The species bible must still settle biology, cognition,
language, motive, internal politics, visual grammar, limitations, and victory
conditions before large amounts of equipment or narrative are written. The
open decisions are listed in `Alien-Design-Brief.md`.

The implementation uses a registered static tag rather than a dynamic country
for the main invader. `XAC` is present and playable in 1936, owns and cores Pale
Anchorage (state `1082`, province `13414`), and uses it as its capital. The
stable tag gives AI and content a reliable scope and survives later renaming
through localisation or cosmetic identity. Dynamic countries remain useful for
alien schisms, protectorates, and collaborator regimes.

Required country assets include:

- Country tag, graphical culture, map color, country history, capital setup,
  localisation, and all flag sizes.
- A translated government identity. “Alien” is a species classification, not
  an ideology; the first slice should bridge to the existing neutrality family
  and express actual alien politics with leaders, traits, national systems,
  flags, and decisions. A new top-level ideology can be revisited only if it
  supplies real diplomatic gameplay worth the compatibility cost.
- Rules for diplomacy, guarantees, volunteers, subjects, faction behavior,
  intelligence, occupation, and peace.
- Succession and failure behavior if the expedition leader dies, defects, is
  captured, or loses contact with higher authority.

No landfall handoff is needed for an XAC campaign because XAC is selectable at
the 1936 start. A future Century of Iron narrative may still offer a player
switch through `change_tag_from`, but that is adapter work and remains an
unvalidated engine spike.

The canonical starting-fleet loader is country history, not runtime
`create_ship`. After registering the modular Pale Horizon and Silent Current
designs, `history/countries/XAC - Grey Consensus.txt` calls
`set_naval_oob = "XAC_1936_naval"`. The matching
`history/units/XAC_1936_naval.txt` places one Pale Horizon and four individually
named escorts in one task force at province `13414`. The startup verifier owns
the independent, guarded 30 Needle/20 Gleam stockpile grant.

## Leaders, scientists, and internal factions

A believable alien state needs an ensemble, not one portrait:

- Civilizational authority or translated head of state.
- Expedition commander and a rival or successor.
- Assault, occupation, and defensive-adaptation commanders.
- Air/orbital command represented through an advisor or scripted character;
  HOI4 has no air-force-commander character role.
- Reinforcement-corridor and fabrication director.
- Chief scientist and specialists in materials, power, propulsion, biology,
  sensors/computation, and human technology.
- Intelligence/infiltration director.
- Occupation governor or collaborator liaison.
- Diplomat/interpreter and at least one dissident or defector.

Each important character needs a stable ID, portrait, translated name/title,
role, traits, internal alignment, AI meaning, succession conditions, and death,
capture, or defection reactions. Scientist characters can use the native
facility/project system. Internal factions should first be national spirits,
character alignments, decisions, and saved influence values; a bespoke GUI is
not required to prove the gameplay.

The full package also needs alien-specific generated portrait/name pools, or it
must disable random recruitment. Otherwise generated commanders, scientists,
and aces can receive human faces and names. Genderless localisation is possible,
but the internal generated-character system still uses male/female pools.

## Landfall, territory, and map representation

HOI4 provinces, states, continents, and strategic regions are static. The
standalone prototype therefore gives XAC a prepared permanent base at Pale
Anchorage. Its landfall system chooses a target country, not a dynamically
created province or automatically transferred state.

Pale Anchorage uses custom state category `coi_alien_arcology`, which supplies
16 local building slots. The 1936 history occupies 14 shared slots with 2
civilian factories, 4 military factories, 6 dockyards, and 2 fuel silos,
leaving two expansion slots. A one-person state-manpower sentinel avoids the
engine's zero-population state diagnostic; expedition manpower remains a
separate country-level grant.

The implemented preparation sequence is deliberately narrow:

1. A player selects one eligible target through the XAC interface or that
   country's prepare-here decision.
2. Validate and save the country once as the global landfall target.
3. Raise it to at least `3 Confirmed` without lowering any higher stage.
4. Grant XAC the special `coi_alien_landfall_wargoal` against that target.
5. Do not declare war and do not alter any state's owner or controller.

The immediate-landfall rule bypasses the usual awareness eligibility test but
uses the same idempotent save-and-grant flow. Actual hostilities, occupation,
gateway placement on conquered soil, and settlements are later systems.
Ordinary conquered Earth states are never alien cores. The mothership can
appear as a scripted map entity created at a state/province position with a
height offset and conditional visibility. It remains a visual representation,
not a province or selectable fleet.

### Gateway design

The gateway/relay is the invasion's most important shared objective. It should
control some combination of:

- Maximum alien divisions and reinforcement cadence.
- Off-world manpower and equipment deliveries.
- Off-map factories and local fabrication efficiency.
- Supply, fuel/energy conversion, air reinforcement, and raid availability.
- Orbital-control recovery and alien command integrity.

A custom building is scriptable and can be damaged, repaired, removed, and
targeted by raids. The implementation spike must establish whether a dynamically
chosen province can display it safely. A robust fallback is a hidden building
or state marker for mechanics plus a separately created map entity for visuals.
Off-map factories are physically invulnerable, so every grant and reinforcement
cap must depend on one or more destructible gateways.

## Research and special projects

The preferred chain is:

`foundation technology -> breakthrough -> special project -> application technology -> equipment/sub-unit`

Special projects should be the visible research language for genuinely alien
capabilities and human reverse engineering. Alien foundation science and human
derived xenotechnology remain separate; humans learn adapted applications, not
the alien civilization's complete scientific base.

The native system supports project parent chains, visibility and availability
gates, breakthrough costs from multiple specializations, resource drain,
complexity, prototype iterations, scientist effects, equipment/module/sub-unit
unlocks, and weighted prototype rewards.

Important constraints from the local schema:

- A project's `allowed` block is evaluated at startup and accepts only a narrow
  set of conditions such as tag, original tag, and DLC. Later crisis state must
  be handled by `visible` and `available`, not by a phase flag in `allowed`.
- Scripted `complete_special_project` skips facility-state and scientist
  effects. Essential unlocks belong in guaranteed project output or country
  effects.
- Project resource costs do not accept oil.
- A new project specialization must be perfectly aligned with its own facility
  building. That adds building, map-position, art, UI, and AI work.

Therefore the first release maps alien domains onto the four native
specializations:

- Land: materials, armor, drones, fabrication, and biological protection.
- Air: propulsion, atmospheric craft, guidance, and orbital interception.
- Nuclear: power, field physics, strategic energy, and gateway theory.
- Naval: the Point Nemo expedition already establishes one mothership, four
  escorts, their modular systems, and a mothership-anchorage dependency.
  Special-project expansion beyond this proven kernel remains deferred.

Custom computing, biology, or energy specializations can be tested later. They
are not required for compelling project chains. An alien-only branch can be
added to an existing technology folder with `allow_branch`; a wholly new
technology tab would require overriding fixed GUI entries and is deferred.

The 1.19 game files include a conventional airborne “mothership aircraft”
equipment and project chain. It is not an orbital system, but it is a valuable
native example of project-gated unusual aircraft and AI/equipment integration.

### Capability families

- Power generation, storage, and distribution.
- Advanced materials, armor, self-repair, and construction.
- Propulsion, atmospheric flight, field control, and transport.
- Directed energy, projectiles, guided weapons, and area denial.
- Sensors, communications, electronic warfare, stealth, and command networks.
- Computation, autonomy, coordination, and machine intelligence.
- Biology, medicine, environmental protection, and ecosystem manipulation.
- Logistics, fabrication, recycling, gateways, and reinforcement relays.
- Orbital reconnaissance, interdiction, bombardment, and landing support.
- Translation, influence, occupation, and exploitation of human technology.

Every capability must have a visible limitation, resource cost, prerequisite,
counter, or operational burden. Alien origin alone does not justify universal
bonuses.

### Doctrine and industrial organizations

Operation Postern's doctrine folders, grand doctrines, tracks, and subdoctrines
are additive. A later alien doctrine package could contrast hierarchical
conquest, distributed swarm, ecological assimilation, and precision
decapitation without replacing the doctrine UI.

A custom expeditionary-fabricator military industrial organization can improve
alien equipment groups, research, production, reliability, and field
replication. It requires Arms Against Tyranny; without that DLC the same core
effects need national-modifier fallbacks. Modular grav vehicles, aircraft, and
ships similarly depend on No Step Back, By Blood Alone, and Man the Guns.

## Equipment, units, production, and manpower

The likely complete equipment roster includes:

- Individual weapon/protection system and heavy squad weapon.
- Command/sensor, shield/defense, medical/repair, and engineering support.
- Autonomous scout or combat drone.
- Protected carrier or mechanized transport.
- Heavy assault platform, walker, grav vehicle, organism, or equivalent.
- Mobile siege or indirect-fire platform.
- Interceptor/air-superiority and strike/support craft.
- Landing/airlift craft.
- Gateway, relay, fabrication, and occupation assets.
- Orbital capabilities represented through raids rather than stockpiled ships.

The slice needs only three land roles—shock infantry, drone/support, and heavy
assault—plus one atmospheric strike/interceptor craft. Ocean-going forces are
deferred unless the final civilization has a specific reason to fight with
Earth-style fleets.

New archetypes, variants, modules, module categories, sub-units, and equipment
groups can be additive. Begin with non-modular alien infantry equipment. Use
vehicle/aircraft designers only when their choices add real gameplay and supply
matching AI designs.

Alien logistics should use two connected economies:

1. Normal factories, the seven current resources (including coal), supply,
   energy, and fuel keep the land war legible to HOI4 and let captured
   territory matter.
2. A saved off-world force pool and active gateways govern reinforcement waves,
   rare equipment, and expeditionary manpower.

Do not introduce an eighth strategic resource in the first slice. Existing
resources can represent locally convertible inputs while alien matter or
energy is a bounded scripted stock. A new resource would require deposits,
trade balance, fixed resource-strip and production UI overrides, icons, and AI
understanding.

The alien polity must not recruit the population of occupied Earth as though it
were alien manpower. Conquered states remain non-core and a permanent alien
modifier suppresses ordinary recruitable population. Off-world arrivals add a
controlled manpower amount. Human auxiliaries, clones, converted populations,
or collaborator formations are separate explicit paths if the lore permits.

## Orbital theater and raids

No supported orbital map layer exists. Orbital control is a strategic value
that changes access, costs, success chances, reinforcement, detection, and
damage. It can be communicated with decisions, alerts, map entities, and raid
tooltips.

XAC already has a physical foothold, naval base, air base, and anchorage at
Point Nemo, so supported native raids may originate there. Truly off-map or
orbital actions should still use events or decisions when no valid raid origin
fits. As the crisis expands, custom raids can cover:

- Orbital reconnaissance and abduction.
- Landing preparation and reinforcement drops.
- Bombardment, interdiction, terror, or precision strikes.
- Human commando attacks on the gateway.
- Anti-orbital missile or aircraft interception.
- Probe, wreckage, prisoner, or data recovery.
- Mothership disruption or forced withdrawal.

The local raid schema supports free targeting, state/province/building targets,
unit and equipment requirements, preparation and command cost, AI weighting,
four outcome levels, custom sounds/icons, moving entities, animations, and
outcome effects. Raid visibility and target triggers must stay simple because
they are evaluated frequently.

## Human response

The invasion is not complete content unless Earth receives meaningful choices:

- Evidence gathering, secrecy, disclosure timing, panic, and preparedness.
- National stances: cooperate, conceal, exploit, appease, collaborate, or
  pursue independent survival.
- Shared samples, intelligence, basing, aid, and coordinated targeting.
- Captured equipment, defectors, autopsies, signals, and reverse-engineering
  projects.
- Countermeasures against alien protection, sensors, drones, air power,
  gateways, command networks, logistics, and biological weaknesses.
- Resistance, accommodation, collaboration, and postwar treatment of survivors
  and technology.

Do not force every country out of its existing faction to create one Earth
Defense faction; HOI4 permits only one normal faction membership. Use a global
defense overlay of decisions, contributions, access, research support, and
scripted war participation. A voluntary unification route may use native
faction-template content if the campaign reaches that political outcome.

Small countries should contribute samples, facilities, resources, intelligence,
or bases to pooled programs rather than each independently completing an alien
technology tree. This matches Century of Iron's planned research hierarchy.

## Occupation, diplomacy, and settlements

Alien-only occupation laws can represent scientific observation, controlled
protectorates, extraction, pacification, harvesting, and collaboration. Native
resistance/compliance values, garrison costs, state modifiers, supply penalties,
and threshold events give humanity a terrestrial response loop. Earth states
should generally remain non-core while occupied. A custom alien-client autonomy
level can govern collaborators' wars, manpower, trade, research, and overlord
authority.

The crisis should resolve before ordinary alien capitulation whenever possible.
Command integrity, gateway loss, orbital defeat, negotiation, or human collapse
can invoke one atomic settlement:

- Stop or narrow wars.
- Restore or deliberately redistribute ownership/control.
- Remove invasion-only units, gateways, off-map industry, and temporary AI.
- Preserve captured assets and permanent consequences.
- Apply the chosen ending state and fire its epilogue.

Candidate endings are decisive human victory, pyrrhic victory, containment,
negotiated withdrawal, coexistence, alien protectorate, collaborator victory,
alien conquest, and an unresolved frozen conflict.

The exposed peace-conference scripting supports built-in action families rather
than arbitrary new treaty actions. Unusual alien agreements therefore belong in
scripted events and decisions; a normal conference can still be launched for a
conventional territorial settlement. No documented effect opens the final score
screen, so the crisis should set its outcome and epilogue while Century of Iron
finishes normally at its configured end date.

## AI requirements

The alien AI needs explicit logic for:

- Project selection and scientist assignment.
- Equipment production, off-world wave requests, and factory construction.
- Division templates, desired force mix, front concentration, and objectives.
- Air-region priority and strike-craft allocation.
- Raid selection, target country, and minimum success chance.
- Gateway defense, repairs, expansion, and occupation law.
- Diplomacy, negotiation, collaborator support, and ending choices.

Human AI needs phase-dependent logic for:

- Preparedness and disclosure choices.
- Protecting likely landing regions and concentrating on alien fronts.
- Anti-air, fortification, logistics, and crisis equipment production.
- Reverse-engineering priorities and pooled contributions.
- Raids against gateways and orbital assets.
- Avoiding opportunistic human wars when the shared threat is existential.
- Collaboration or accommodation when survival odds justify it.

This requires all four AI layers: per-content `ai_will_do`, phase-specific AI
strategies, division templates, and design files for modular equipment. Run one
bounded weekly controller calculation during invasion, not a daily world scan.
Recalculate large AI packages on phase changes. Every AI strategy plan needs a
defined abort path.

## Presentation inventory

The complete presentation layer includes:

- Alien flags, emblem, script, palette, country names, ranks, and unit naming.
- Ruler, commander, scientist, advisor, collaborator, and defector portraits.
- Event pictures, news art, decision category art, project blueprints, project
  icons, equipment icons, traits, ideas, alerts, and tooltips.
- Gateway/mothership map entities, alien unit entities, aircraft, animations,
  weapon effects, impacts, destruction, and environmental effects.
- Contact, disclosure, invasion, victory, and defeat music.
- Voices, warnings, engines, weapons, raids, UI confirmations, and ambient sound.
- English localisation first, with short sentences and explicit mechanical
  tooltips; translated names must follow one consistent language guide.
- Color-blind-safe state and phase indicators and non-audio warning cues.

Measured vanilla asset references are 156x210 for scientist portraits, 161x98
for project icons, 146x54 for equipment/technology icons, and 24x33 for
scientist traits. Flags are 82x52, 41x26, and 10x7. The install contains PDX
exporter settings but not an exporter executable, so original 3D models require
a separate mesh-export pipeline. Reuse a vanilla entity only as a temporary
mechanical stand-in.

Original placeholders or vanilla references are acceptable during prototyping.
Third-party Workshop assets are research references only and are never copied.

## Tooling, validation, and testing

Structured source should eventually generate repetitive equipment, projects,
leaders, waves, localisation stubs, and manifests. Hand-authored narrative and
exceptional effects remain separate.

### Runtime evidence as of 2026-08-30

- The isolated `TestUserDirMinimalState8` run loaded 13,415 provinces and
  completed `Start RestoreDeviceObjects` through `End RestoreDeviceObjects`,
  proving the Point Nemo province/state payload can enter the game.
- `TestUserDirFull7_GER` removed Full6's locked-equipment-requirements warning by
  using the custom mothership and escort sub-units in the history OOB.
- `TestUserDirFull8_XAC` and `TestUserDirFull9_XAC_Windowed` explicitly booted
  as XAC, accepted the custom units and both modular designs, reached
  `End RestoreDeviceObjects`, reported the complete 1+4 history OOB, and stocked
  exactly 30 Needle plus 20 Gleam aircraft.
- Full9 contains no tech-grid, missing-localisation, state, map, scope, or
  `create_ship` warnings. Its remaining error log is exactly eight equipment
  script-enum documentation notices plus two expected vanilla/test-harness
  remote-file allocation warnings.
- A live Steam screenshot captured during the Full9 test shows the Grey flag,
  Pale Anchorage label, 100.00K manpower, and a five-ship
  stack. The DirectX capture/input helper failed before it could expose the
  politics, portrait, state, naval, or air-detail panels. Those panels,
  save/reload idempotence, deployed wings, AI, combat, and multiplayer remain
  unproven.

### Historical version 0.2.0 local-package milestone

- `Mod/descriptor.mod` and `Launcher/alien_crisis_dev.mod.template` declare
  version `0.2.0`, name `Alien Crisis: Grey Consensus [DEV]`, and
  `picture="thumbnail.png"`.
- The local launcher descriptor is installed beneath the current user's Hearts
  of Iron IV `mod` directory as `coi_alien_crisis_dev.mod`.
- The original image-generation source is
  `Source/Art/Masters/coi_alien_workshop_cover.png`; the derived 512×512 review
  cover is `Source/Art/Preview/workshop_cover.png`, and the derived 512×512
  launcher/Workshop asset is `Mod/thumbnail.png`.
- At that milestone this was local packaging evidence only. The later Workshop
  testing channel began privately and is now public; the public repository
  continues to omit account and manifest IDs.

Required validation includes:

- Namespace and duplicate-token linting.
- Brace and encoding checks.
- Country tag, localisation, portrait, sprite, equipment, project, and template
  reference checks.
- Override manifest; broad `replace_path` is forbidden.
- Debug decisions to force every phase, landing, wave, raid, project, and ending.
- A periodic diagnostic log containing phase, gateway state, alien holdings,
  divisions, manpower/force pool, equipment, orbital control, readiness, and
  command integrity.
- Save/load tests during each transition and settlement.
- Single-player, observer, and at least two-player multiplayer tests.
- Tests with annexed original owners, existing world wars, several human
  factions, occupied landing states, and alien final-state capture.

Avoid daily `every_country` or `every_state` loops, expensive per-frame targeted
decision scans, and unsaved random rerolls. Use one controller country/scope for
global choices and deterministic AI defaults for every player prompt.

## Provisional content scale for a first alpha

These are planning numbers, not a promise or cap:

- 1 main alien polity with 2–3 internal political alignments.
- 10–15 named alien characters.
- 6–8 battalion/support roles and 6–10 division templates.
- 10–16 equipment families or major variants and 2–3 aircraft roles.
- 12–18 alien adaptation projects and 10–15 human counter-projects.
- 5–8 orbital/commando raid types.
- 30–50 narrative, news, and mechanical events.
- 20–30 decisions and targeted crisis actions.
- 4–6 occupation/collaboration approaches.
- At least 6 mechanically distinct resolutions.
- 3 tested landing packages plus a deterministic debug landfall.

The vertical slice deliberately builds much less. Its job is to prove the risky
engine interactions before this content scale expands; see `Vertical-Slice.md`.

## Decisions needed before mass content production

1. Biological, synthetic, cybernetic, distributed, or mixed civilization.
2. Expedition motive and what the force needs from Earth.
3. Whether communication is possible at Disclosure, only after research, or
   only through a dissident/interpreter.
4. Degree of internal unity and the major alien factions.
5. Main combat silhouette: soldiers, drones, walkers, grav vehicles, organisms,
   or a deliberate mix.
6. Limits: reinforcement distance, environment, command lag, rare matter,
   biology, culture, or another constraint.
7. Rules for civilians, occupation, collaboration, and negotiation.
8. Visual geometry, materials, light, palette, writing, and sound language.
9. Default arrival window and strength in Century of Iron.
10. Which outcomes can legitimately count as the end of the 2100 campaign.
