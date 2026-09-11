# Alien Crisis: Grey Consensus

![Alien Crisis: Grey Consensus](Mod/thumbnail.png)

Alien Crisis is a standalone, non-commercial **Hearts of Iron IV** mod in
active development. It prototypes the extraterrestrial endgame crisis planned
for later integration into **Century of Iron**: play the Grey Consensus from
Pale Anchorage at Point Nemo, study humanity, infiltrate its institutions, and
shape the route from classified anomalies to catastrophic first contact.

This repository contains the mod's original source, authored game data, build
tools, documentation, and generated art masters. It is a development project,
not a balanced public release.

- Development version: **0.6.0**
- Launcher name: **Alien Crisis: Grey Consensus [DEV]**
- Supported game line: **HOI4 1.19.x**
- Build scripts currently pinned to: **HOI4 1.19.2.0**
- Stable namespace: `coi_alien_`
- Playable country tag: `XAC`
- Reserved map IDs: province `13414`, state `1082`

## What is playable

- The **Grey Consensus**, starting in 1936 from a custom Artificial Arcology at
  Pale Anchorage, with its own leaders, navy, aircraft, agency, and operatives.
- A sealed, 36-node **Consensus Sciences** tree. XAC receives four research
  slots and cannot use humanity's ordinary technology folders.
- Eight alien-only special projects, including Energy Gateways, Interorbital
  Sentinels, Atomic Disruption, human cultural modelling, genome analysis,
  viable cloning, self-healing material, and molecular aircraft printing.
- **The Quiet Chorus**, with three Grey infiltrators, three autonomous drones,
  three escalating access tokens, three agency upgrades, and eight custom
  operations for surveillance, sabotage, archive theft, and scientist
  extraction.
- A three-axis discovery model for classified knowledge, public awareness, and
  national preparedness, plus Black Archive, Prepared Public, international
  coordination, and Open Files policy routes.
- Project NIGHT LANTERN recoveries, Italian RS/33 and Vatican flavor, secret
  reverse engineering, managed and open disclosure, catastrophic contact, and
  the narrative **Signals in the Noise** event season.
- Alien **Tic Tac** transit capsules implemented through HOI4's supported
  country-specific `convoy_1` variant system, with a 1938 Tic Tac Fabrication
  Lattice research unlock and save-safe reserve migration.

The final Signals in the Noise headline currently sets only a future XCOM
integration flag. It does not yet create a defense organization, faction,
country, or unit.

## Requirements

- A legally owned Windows installation of Hearts of Iron IV 1.19.2.0 for the
  current reproducible build workflow.
- **Götterdämmerung** for the intended special-project experience.
- **Man the Guns** for the present starting alien navy.
- **La Résistance** for Quiet Chorus operatives and operations.
- PowerShell 7 is recommended for the build and validation scripts.

There is no third-party mod dependency. Century of Iron is a future integration
target, not a dependency; do not enable both mods in the same playset yet.

## Building from source

The repository deliberately does not redistribute full Paradox map, interface,
technology-tag, building, raid, or special-project files. Those compatibility
overrides are reconstructed from a locally installed copy of HOI4 1.19.2.0;
the interface, database, and raid builders are hash-pinned to their tested
sources. This keeps Steam credentials and Paradox-owned baseline data out of
GitHub while leaving the complete build reproducible for game owners.

From the repository root, run:

```powershell
pwsh -NoProfile -File ./Source/Build-PointNemoMap.ps1
pwsh -NoProfile -File ./Source/Build-AlienResearchIsolation.ps1
pwsh -NoProfile -File ./Source/Build-AlienTechnologyUI.ps1
pwsh -NoProfile -File ./Source/Build-AlienIntelligenceUI.ps1
pwsh -NoProfile -File ./Source/Build-AlienNuclearRaids.ps1
pwsh -NoProfile -File ./Source/Build-ArtAssets.ps1
pwsh -NoProfile -File ./Source/Validate-Mod.ps1
```

Each game-derived builder accepts `-GameRoot` if HOI4 is installed somewhere
other than Steam's default Windows location. The art builder uses the original
masters under `Source/Art/Masters` and regenerates the derived DDS/TGA assets
and local preview folder.

After a successful build, register the local development mod with:

```powershell
pwsh -NoProfile -File ./InstallLocal.ps1
```

This writes a launcher descriptor beneath the current user's HOI4 documents
folder and does not enable the mod in a playset. Use a dedicated playset and a
new 1936 campaign. Steam Deck/Linux source automation is not yet supported;
the private Workshop item remains the practical cross-device testing channel.

## Validation and test status

`Source/Validate-Mod.ps1` performs the full static contract check. Version
0.6.0 has also passed fresh XAC and Germany one-day runtime smoke tests plus a
copied recent-save migration/reload test. The private Workshop payload was
authenticated and matched all 324 local `Mod` files byte-for-byte after upload.

Validated areas include country setup, reserved map IDs, technology isolation,
four research slots, all eight alien projects, gateway and orbital mechanics,
Tic Tac reserve idempotence, Quiet Chorus initialization, discovery/disclosure
state, event timing, localization, GFX bindings, and namespace isolation.

Known gaps remain:

- Long campaigns, multiplayer, deployed air combat, and complete player-driven
  operation chains are not yet fully tested.
- Unattended DirectX sessions can crash after the required autosave; that same
  behavior reproduces against an earlier untouched Workshop baseline.
- HOI4 supports only one convoy equipment type. The Tic Tac implementation is a
  country variant, so vanilla convoy resource costs, transfer/licensing
  behavior, counters, trade-route models, and the 3D entity remain shared.
- The namespaced Tic Tac naval-combat strip is staged for a future
  engine-supported hook; HOI4 presently chooses this art by the shared
  `convoy_1` key.
- A real alien moving model will require a Paradox-compatible 3D mesh rather
  than raster art.

The engine error log may contain documented custom-equipment enumeration
warnings. They are accepted intentionally instead of replacing the global
`script_enums.txt` file.

## Repository layout

- `Mod/` — original mod content and generated runtime output.
- `Source/` — reproducible builders, validators, art masters, and prompt records.
- `Docs/` — design, engine-hook, map, espionage, disclosure, and integration notes.
- `Launcher/` — portable launcher descriptor template.
- `Workshop/` — sanitized private-publishing example; the active VDF is ignored.

Useful starting documents:

- [Component research](Docs/Component-Research.md)
- [Engine audit](Docs/Engine-Audit.md)
- [Vertical slice](Docs/Vertical-Slice.md)
- [Alien design brief](Docs/Alien-Design-Brief.md)
- [Quiet Chorus](Docs/Quiet-Chorus.md)
- [Discovery and disclosure](Docs/Discovery-Disclosure.md)
- [Integration contract](Docs/Integration-Contract.md)

## Contributing and rights

Please read [CONTRIBUTING.md](CONTRIBUTING.md), [ASSET_SOURCES.md](ASSET_SOURCES.md),
[NOTICE.md](NOTICE.md), and [LICENSE.md](LICENSE.md) before contributing or
redistributing any part of the project.

Hearts of Iron IV and related game content are owned by Paradox Interactive AB
and/or its licensors. This is an unofficial fan project and is not affiliated
with or endorsed by Paradox Interactive, Valve, or Steam.
