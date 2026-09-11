# Notices and third-party boundaries

Alien Crisis: Grey Consensus is an unofficial, non-commercial fan modification
for Hearts of Iron IV. It is not affiliated with, sponsored by, or endorsed by
Paradox Interactive AB, Valve Corporation, or their affiliates.

Hearts of Iron IV, the Clausewitz engine, and related game content are owned by
Paradox Interactive AB and/or its licensors. Steam and Steam Workshop are owned
or operated by Valve Corporation. All trademarks remain the property of their
respective owners.

Use and publication of this project remain subject to the current
[Paradox User Agreement](https://legal.paradoxplaza.com/eula), the applicable
Hearts of Iron IV terms, and, for Workshop distribution, the
[Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement/).
The project license does not replace or enlarge permissions granted by those
agreements.

## Paradox-derived local build outputs

The standalone mod must shadow several complete Hearts of Iron IV 1.19.2 files
because the engine provides no additive hook for the required changes. These
files contain substantial Paradox game content and are not covered by the
project's license. With the exception noted below, the public source repository
does not track them; project build scripts reconstruct them from a user's
lawfully installed game files.

Research, building, and interface shadows:

- `Mod/common/buildings/00_buildings.txt`
- `Mod/common/special_projects/projects/air_projects.txt`
- `Mod/common/special_projects/projects/land_projects.txt`
- `Mod/common/special_projects/projects/naval_projects.txt`
- `Mod/common/special_projects/projects/nuclear_projects.txt`
- `Mod/common/special_projects/projects/radar_projects.txt`
- `Mod/common/special_projects/projects/rocket_projects.txt`
- `Mod/common/technology_tags/00_technology.txt`
- `Mod/interface/countryintelligenceagencyview.gui`
- `Mod/interface/countrytechtreeview.gui`

Point Nemo map shadows:

- `Mod/map/buildings.txt`
- `Mod/map/definition.csv`
- `Mod/map/heightmap.bmp`
- `Mod/map/provinces.bmp`
- `Mod/map/rivers.bmp`
- `Mod/map/strategicregions/32-Southern Ocean.txt`
- `Mod/map/supply_nodes.txt`
- `Mod/map/terrain.bmp`
- `Mod/map/unitstacks.txt`

`Mod/map/rivers.bmp` is copied without project-authored pixel changes because
the full-map override contract requires it. The other files above are modified
or generated shadows of the corresponding HOI4 1.19.2 files.

`Mod/common/raids/nuclear_raids.txt` is a modified full-file shadow of a
Paradox file and is also excluded from version control. The hash-pinned
`Source/Build-AlienNuclearRaids.ps1` builder reconstructs it locally and adds
the project's Atomic Disruption and orbital-interception hooks. Paradox retains
all rights in the underlying game material; only the project-authored additions
are within the scope of the project license.

## Original project content and generated art

Namespaced scripts, narrative text, build tooling, and project-specific visual
designs are original project work except where a file says otherwise.
Machine-generated raster masters were created for this project with OpenAI
ImageGen and then transformed by `Source/Build-ArtAssets.ps1`. Prompt and mode
records are checked in under `Source/Art/`; the consolidated inventory is in
`ASSET_SOURCES.md`.

As between OpenAI and its user, OpenAI's terms assign its rights in output to
the user to the extent permitted by law, while noting that outputs may not be
unique. The project makes no broader claim about copyright eligibility in a
particular jurisdiction.

The project contract prohibits copying third-party Steam Workshop mod assets.
No third-party Workshop asset is intentionally included in this repository.
