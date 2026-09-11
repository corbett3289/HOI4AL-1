# Contributing

Alien Crisis: Grey Consensus is an early, non-commercial Hearts of Iron IV mod.
Small fixes, compatibility research, testing reports, localization, and focused
feature contributions are welcome. For a large feature or structural change,
open an issue before investing substantial work so its save, engine, and
integration boundaries can be agreed first.

## Rights and provenance

Submit only material that you created or that you have explicit permission to
contribute. By intentionally submitting a contribution, you agree to offer it
under `LICENSE.md` and represent that you have authority to do so.

Do not submit:

- code, writing, or art copied from another mod or Workshop item;
- game executables, DLC payloads, unpublished or leaked materials, save files,
  crash dumps, logs, or complete Paradox files outside the documented local
  build boundary;
- credentials, Steam Guard data, account identifiers, personal filesystem
  paths, or other private information; or
- generated media without recording the tool, mode, prompt, input references,
  human edits, and resulting project master in `ASSET_SOURCES.md` and the
  relevant file under `Source/Art/`.

## Project conventions

- Use the permanent `coi_alien_` namespace wherever the database permits it.
- Preserve stable IDs and migration guards unless a documented compatibility
  plan replaces them.
- Prefer additive files. Do not add `replace_path` without an engine audit and
  an explicit update to the integration contract.
- Keep the standalone mod independently loadable and avoid undocumented
  coupling to Century of Iron.
- Keep player-facing localization in UTF-8 with BOM and preserve the existing
  line-ending contracts of generated GUI shadows.
- Document engine limitations honestly; do not present a staged or inferred
  capability as runtime-proven.

## Local setup and validation

A clean public clone intentionally omits Paradox-derived generated shadows.
Reconstruct them from a lawful Hearts of Iron IV 1.19.2 installation before
running the complete validator:

```powershell
& ./Source/Build-PointNemoMap.ps1 -GameRoot '<path-to-Hearts of Iron IV>'
& ./Source/Build-AlienResearchIsolation.ps1 -GameRoot '<path-to-Hearts of Iron IV>'
& ./Source/Build-AlienTechnologyUI.ps1 -GameRoot '<path-to-Hearts of Iron IV>'
& ./Source/Build-AlienIntelligenceUI.ps1 -GameRoot '<path-to-Hearts of Iron IV>'
& ./Source/Build-AlienNuclearRaids.ps1 -GameRoot '<path-to-Hearts of Iron IV>'
& ./Source/Build-ArtAssets.ps1
```

The validator accepts either a maintainer's ignored local Workshop VDF or the
sanitized public example. Contributors never need a publisher account, item ID,
or manifest number to run the complete static suite:

```powershell
pwsh -NoProfile -File ./Source/Validate-Mod.ps1
```

Before submitting a change:

1. Run the complete static validator.
2. Use a dedicated launcher playset with no unrelated mods.
3. Smoke-test a fresh 1936 Grey Consensus start through at least the first daily
   tick and review the HOI4 logs for new script, scope, localization, map, or GFX
   errors.
4. Exercise the changed feature and, when it affects persistent state, reload a
   copied save to check idempotence.
5. Describe what was tested, which DLC were active, and what remains unverified.

Raw runtime profiles and saves belong outside Git. A concise, sanitized test
summary may be committed to project documentation when it adds durable evidence.
