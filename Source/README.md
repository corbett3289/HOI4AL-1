# Structured authoring source

This directory will hold machine-readable definitions for alien capabilities,
equipment generations, projects, leaders, invasion waves, landing packages,
human response options, AI priorities, art manifests, and localisation stubs.

Generated HOI4 output belongs under `Mod`. Hand-authored exceptional scripts
remain clearly separated from generated files so later integration into Century
of Iron can be reviewed and reproduced.

## Reproducible vanilla shadows

`Build-AlienNuclearRaids.ps1` reconstructs
`Mod\common\raids\nuclear_raids.txt` from the installed HOI4 1.19.2 vanilla
file, then applies the Alien Crisis Atomic Disruption and orbital-interception
insertions. The builder pins both source and output SHA-256 hashes and stops
without changing the target when the game file or expected anchors differ.

Run it from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\Source\Build-AlienNuclearRaids.ps1
```

For a non-default Steam library, pass the HOI4 installation directory with
`-GameRoot`.
