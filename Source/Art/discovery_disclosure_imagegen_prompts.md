# Discovery/disclosure image-generation provenance

All new raster masters in this set were authored with Codex's built-in ImageGen
workflow and then converted by `Source\Build-ArtAssets.ps1`; no CLI image model
was used. The retained production briefs below describe the submitted prompts.
They intentionally request no text, flags, insignia, or identifiable real-world
leaders so the art survives multiple countries and eras.

## Generated masters

### `coi_alien_discovery_anomaly.png`

Square HOI4-style painted intelligence illustration: a dark 1930s radar room,
green phosphor scope showing several impossible converging tracks that subtly
form an eye-like geometry, analysts seen only as silhouettes, cyan-green light,
archival paper and brass controls, ominous scientific realism, no words or
logos, strong central read at small icon size.

### `coi_alien_magenta_recovery.png`

Square cinematic 1933 northern-Italian military hangar at night, a compact
bell-shaped metallic craft recovered under canvas and work lights, black-uniform
guards and engineers kept generic and unidentifiable, wet concrete reflections,
sepia-black palette with cold highlights, grounded alternate-history dossier
illustration, no symbols, text, or gore.

### `coi_alien_vatican_reliquary.png`

Square atmospheric subterranean Vatican reliquary, candlelit stone chamber and
ornate glass sarcophagus containing small Grey extraterrestrial remains beneath
a linen veil, anonymous clergy studying it at a respectful distance, sacred
gold against cold alien pallor, serious historical-horror painting, no text,
modern logos, or explicit gore.

### `coi_alien_disclosure_secrecy.png`

Square transparent-background HOI4 policy emblem: closed black intelligence
dossier bound with red cord, brass clasp, red wax seal, one cyan edge-glow from
hidden alien evidence, dramatic three-quarter view, clean silhouette, no text.

### `coi_alien_disclosure_managed.png`

Square transparent-background HOI4 policy emblem: austere government podium and
single vintage microphone framed by dark blue curtains opening to a controlled
white spotlight, faint saucer silhouette above, formal restrained composition,
no words, flags, or logos.

### `coi_alien_disclosure_international.png`

Square transparent-background HOI4 policy emblem: dark globe enclosed by a ring
of vintage radio transmitters and cyan communication arcs, small gold diplomatic
accents, cooperative but secretive, bold readable silhouette, no text or flags.

### `coi_alien_disclosure_open_files.png`

Square transparent-background HOI4 policy emblem: archival cabinet bursting
open with photographs, radar plots, film canisters, and classified folders,
severed red secrecy ribbon, hard white light flooding outward, energetic but
legible composition, no readable words or national markings.

### `coi_alien_catastrophic_disclosure.png`

Wide cinematic HOI4 news-event painting: immense alien mothership openly
hovering over a generic 1940s capital in daylight, multiple smaller discs,
crowds and press photographers staring upward, military vehicles and radio
trucks unable to conceal the event, steel-grey and cyan alien light against
warm stone city, global-history scale, no text, flags, leaders, or destruction.

### `coi_alien_human_exotic_materials.png`

Square transparent-background special-project emblem: gloved human hands use
calipers and a compact spectrometer on a fractured blue-black alien laminate,
impossible crystalline layers glowing cyan and amber, 1940s laboratory tools,
high-detail painted object cluster, clean silhouette, no text or insignia.

## Field-dynamics fallback

The unique prompt requested a compact levitating black-cyan propulsion core in
a 1940s laboratory, surrounded by three orthogonal luminous field rings,
vacuum-tube instruments, cables, and gloved hands, isolated on transparency with
no text. Built-in ImageGen timed out on that replacement three times. To keep
the implementation deterministic, `coi_alien_human_field_dynamics.png` reuses
the earlier built-in-ImageGen master `coi_alien_tech_inertial_field_theory.png`
byte-for-byte. Both files have SHA-256
`986003D2556FFF67B594E567CAFEBE47360D4504154168AEF5B536697FDD16D1`.
The retained prompt can be retried later without changing any GFX identifier.
