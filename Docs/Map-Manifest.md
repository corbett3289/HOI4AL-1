# Point Nemo Map Manifest

The Grey Consensus prototype reserves the following additive identifiers against
the Hearts of Iron IV 1.19.2 map:

- Province `13414`: Pale Anchorage, centered at map bitmap coordinate
  `1146,1875`, carved entirely from Southern Ocean sea province `601`.
- State `1082`: Pale Anchorage.
- Strategic region `32`: the existing Southern Ocean region, extended to include
  province `13414`.
- Province color: RGB `211,90,211`.

Pale Anchorage uses custom state category `coi_alien_arcology` (“Artificial
Arcology”) with 16 local building slots. Fourteen shared slots are occupied in
1936: 2 civilian factories, 4 military factories, 6 dockyards, and 2 fuel
silos. Two shared slots remain for expansion. Infrastructure, air base, radar,
anti-air, naval base, and the mothership anchorage follow their normal
state/province building rules and do not change that 14-of-16 accounting.

The current map is `5632 x 2048`. Bitmap coordinates use a top-left origin,
while HOI4 locator world coordinates use the vertically inverted `Z` axis:

`Z = height - 1 - bitmapY`

For the province center this is `2048 - 1 - 1875 = 172`. Do not use
`height - bitmapY`; that one-row error can move locators into the surrounding
sea. The BMP's physical storage direction is a separate concern: for a
bottom-up BMP, the raw byte row is also `height - 1 - bitmapY`.

## Required ancillary map records

- `definition.csv` defines province `13414` as coastal land, plains, continent
  `6`.
- State `1082` contains the province, XAC owns and cores the state in 1936, and
  strategic region `32` includes the province.
- A coastal province requires a valid nudger port anchor in `map/buildings.txt`.
  The canonical `naval_base_spawn` locator is on the new land at
  `1137.00;9.80;173.00`, with adjacent sea province `601` in its final field.
  The floating-harbor locator targets province `13414` separately.
- The canonical tiny-island unitstack subset is exactly types
  `0, 1, 9, 10, 21, 22, 38`. These are standstill, first movement, attack,
  defense, standstill RG, first movement RG, and victory-point anchors. The
  generator inserts each record into its matching contiguous type block;
  the island does not require all types `0` through `38`.

## Bitmap preservation rule

The generator copies the vanilla BMPs and edits their raw byte arrays in place.
It must preserve each BMP header, palette, bit depth, compression mode, signed
row orientation, row padding, and every pixel outside the Point Nemo patch.
Do not open and re-save these files through a general image encoder: palette
reordering or format conversion can make an otherwise unchanged HOI4 map
invalid. The supported inputs remain uncompressed 24-bit `provinces.bmp` and
uncompressed indexed 8-bit `heightmap.bmp`, `terrain.bmp`, and `rivers.bmp`.

`Source/Build-PointNemoMap.ps1` regenerates the required full map overrides from
the installed 1.19.2 base game. Re-run and re-audit it after any HOI4 map update;
the generated bitmap and map database files must not be assumed compatible with
another game version or another map overhaul.

## Runtime evidence

- `TestUserDirMinimalState8/logs/game.log` loaded 13,415 provinces and reached
  both `Start RestoreDeviceObjects` and `End RestoreDeviceObjects`, proving the
  isolated Point Nemo province/state map path can enter a 1936 game.
- `TestUserDirFull8_XAC/logs/game.log` and
  `TestUserDirFull9_XAC_Windowed/logs/game.log` explicitly entered 1936 as XAC,
  loaded 13,415 provinces, and reached `End RestoreDeviceObjects`. Full9 has no
  state, province, map, building-slot, zero-population, or scope diagnostics.
- A live Steam screenshot captured during the Full9 test shows the Grey flag,
  the Pale Anchorage map label, 100.00K manpower, and the
  five-ship stack at the anchorage.
- That image is valid evidence for the live map view and headline country/fleet
  state only. The DirectX capture/input helper failed before it could open and
  record the politics, portrait, state, naval, or other detail panels, so those
  panel contents and save/reload behavior remain unproven.
