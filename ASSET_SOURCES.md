# Asset sources and provenance

This inventory records the source boundary for visual assets in Alien Crisis:
Grey Consensus. It is a provenance record, not a representation that every
machine-generated image is copyrightable or unique in every jurisdiction.

## Build relationship

High-resolution project masters live in `Source/Art/Masters/`. The deterministic
builder `Source/Build-ArtAssets.ps1` derives review PNGs and HOI4-native DDS/TGA
runtime assets from those masters. Derived files inherit the source status of
their master and do not create a separate license grant.

`Source/Art/Preview/` is generated review output and is intentionally not
tracked. Runtime assets under `Mod/gfx/` and `Mod/thumbnail.png` remain part of
the playable package.

No third-party Workshop art is an approved source. Existing project masters may
be supplied to ImageGen as style-only references; the relevant prompt record
identifies those references.

## Recorded ImageGen families

| Asset family | Masters | Provenance record | Status |
| --- | --- | --- | --- |
| Spy roster and drone trait | Neth Witness, Ysil Lattice, Cael Current, Quiet Orbit, Pale Echo, Outer Witness, and Autonomous Infiltration Drone | `Source/Art/spy_roster_imagegen_prompts.md` | Built-in ImageGen prompts and project-reference use recorded |
| Quiet Chorus operations | `coi_alien_operation_*.png` (eight masters) | `Source/Art/quiet_chorus_operations_imagegen_prompts.md` | Built-in ImageGen prompt contract and generation/edit mode recorded |
| Discovery and disclosure | Discovery anomaly, Magenta recovery, Vatican reliquary, four policy emblems, catastrophic disclosure, exotic materials, and the field-dynamics fallback | `Source/Art/discovery_disclosure_imagegen_prompts.md` | Prompts recorded; field dynamics is an explicitly documented byte-for-byte reuse of a project master |
| Consensus Sciences | Human Sciences, Fabrication, eight special-project masters, and two conditioned-facsimile portraits | `Source/Art/consensus_sciences_imagegen_prompts.md` | Twelve built-in ImageGen outputs and prompts recorded |
| Tic Tac convoy | `coi_alien_tic_tac_convoy.png` | `Source/Art/tic_tac_convoy_imagegen_prompt.md` | Built-in ImageGen prompt, mode, and deterministic derivatives recorded |
| Signals in the Noise | `coi_alien_news_*.png` (fifteen masters) | `Source/Art/alien_news_imagegen_prompts.md` | Fifteen selected outputs, exact prompts, style-only project references, and one refinement edit recorded |

## Legacy core masters awaiting consolidated per-file records

The following masters predate the family provenance documents above. The
working-tree history treats them as project-created source assets, but a
complete per-file prompt/edit record has not yet been consolidated. They remain
under the conservative project license; contributors must not replace this
status with a more permissive claim without supporting evidence.

- `coi_alien_anchorage.png`
- `coi_alien_eir.png`
- `coi_alien_flag_master.png`
- `coi_alien_gleam.png`
- `coi_alien_landfall.png`
- `coi_alien_needle.png`
- `coi_alien_oru.png`
- `coi_alien_pale_horizon.png`
- `coi_alien_pale_horizon_ui_v2.png`
- `coi_alien_pale_horizon_ui_v3.png`
- `coi_alien_phase_movement_ui_v1.png`
- `coi_alien_phase_movement_ui_v2.png`
- `coi_alien_saal.png`
- `coi_alien_silent_current.png`
- `coi_alien_silent_current_ui_v2.png`
- `coi_alien_silent_current_ui_v3.png`
- `coi_alien_species_anchor.png`
- `coi_alien_tech_adaptive_metamaterials.png`
- `coi_alien_tech_coherent_energy_control.png`
- `coi_alien_tech_inertial_field_theory.png`
- `coi_alien_tech_predictive_computation.png`
- `coi_alien_thren.png`
- `coi_alien_vael.png`
- `coi_alien_workshop_cover.png`

## Non-project and derived material

Full-file HOI4 shadows and local build outputs are documented in `NOTICE.md`.
They are not original art and are outside the project license except for
identifiable project-authored additions. Do not add extracted game art, logos,
screenshots, or assets from another mod to this inventory as if they were
project originals.

When adding a new master, record at minimum:

1. its exact filename and intended derivatives;
2. the authoring tool and generation/edit mode;
3. the complete submitted prompt or a durable hand-authored source description;
4. every input or reference asset and the right to use it;
5. material human edits; and
6. any separate license or attribution requirement.
