# Tic Tac convoy image-generation provenance

`coi_alien_tic_tac_convoy.png` was authored with Codex's built-in ImageGen
workflow in `stylized-concept` mode. No CLI image model was used. The exact
submitted production brief is retained below so the transparent master can be
reproduced or deliberately revised without changing its downstream GFX keys.

## Submitted prompt

**Use case:** stylized-concept

**Asset type:** reusable transparent master for Hearts of Iron IV equipment,
technology, and naval-combat UI icons

**Primary request:** Create one alien logistics transit craft with the
unmistakable silhouette of a classic white “Tic Tac” UAP.

**Scene/backdrop:** genuinely transparent background with tight, clean alpha;
no environment, ground plane, stars, sky, frame, or backdrop.

**Subject:** exactly one seamless pearl-white elongated capsule with smoothly
rounded ends. It has no cockpit, windows, doors, seams, panels, wings, fins,
landing gear, visible engines, weapons, markings, symbols, or text. The capsule
is elegant, technologically overwhelming, and physically plausible as a
gravitic alien craft.

**Style/medium:** premium hard-surface science-fiction game-asset render; crisp
polished ceramic/pearlescent material; restrained realism rather than cartoon
styling.

**Composition/framing:** horizontal landscape master, three-quarter side view
facing right, centered, the full craft visible and filling about 82 percent of
the canvas width. Preserve a strong clean silhouette that remains readable when
reduced to a 146×54 icon and a two-frame 52×17 naval-combat strip.

**Lighting/mood:** neutral studio-like rim lighting contained on the object; a
subtle cyan-white gravitic field halo concentrated directly beneath and around
the craft’s center, controlled and symmetrical, with a bright central field
focus suitable for a square technology-icon crop.

**Color palette:** pearl white and ivory craft, subtle cool silver shading,
restrained cyan-white energy only.

**Constraints:** actual transparent background and preserved alpha; exactly one
craft; full silhouette unobstructed; no cast shadow disconnected from the craft;
no bloom extending far from the object; no text, letters, numerals, logos,
trademarks, borders, or watermark.

**Avoid:** flying saucer shape, airplane shape, rocket, missile, ship hull,
visible thrusters, ornamentation, panel lines, scenery, multiple objects,
excessive glow, painterly brushwork.

## Deterministic derivatives

`Source\Build-ArtAssets.ps1` alpha-trims this master and emits three uncompressed
32-bit ARGB DDS assets without mipmaps:

- 146×54 full-silhouette equipment icon;
- 64×64 center-focused technology icon;
- 104×17 naval-combat strip containing two mirrored 52×17 frames.

## HOI4 1.19.2 binding note

The equipment derivative is safe to bind to a named `convoy_1` variant with
`icon = "GFX_coi_alien_tic_tac_convoy_medium"`. Equipment-variant display names
and owning countries are not part of the naval-combat sprite lookup, however,
so a country-specific `convoy_1` variant cannot select the combat strip.

The strip remains namespaced for the distinct `coi_alien_tic_tac_convoy`
equipment type. Never alias it to the shared `GFX_unit_convoy_1_icon_medium` or
`GFX_navalcombat_ship_icon_convoy` keys: doing so would replace human convoy art
globally. The namespaced type lookup should be confirmed in-game; if the convoy
archetype's `sprite = convoy` fallback wins, the result is the vanilla strip and
not a cross-country override.
