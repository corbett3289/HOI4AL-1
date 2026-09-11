# Alien Crisis Integration Contract

## Boundary

The alien module is developed as a standalone HOI4 mod and later imported into
Century of Iron as an endgame package. It does not edit the Century of Iron
source tree during prototype development.

## Permanent rules

- Every event, decision, variable, flag, idea, trigger, effect, technology,
  project, equipment, unit, AI plan, localisation key, and sprite begins with
  `coi_alien_` where the database permits namespacing.
- The provisional static country tag is `XAC`. The working species identity is
  the Greys and the displayed polity is the Grey Consensus. Cosmetic wording
  may evolve without changing persistent script IDs.
- In the standalone prototype, `XAC` is playable from 1936 and owns Pale
  Anchorage (state `1082`, province `13414`). Century of Iron may adapt the
  presentation or timing, but it must not assume the prototype tag is landless
  or created by the landfall effect.
- Pale Anchorage uses 16-slot category `coi_alien_arcology`. Its state category,
  one-person engine sentinel, port anchors, and province/state IDs are part of
  the standalone map contract and require an explicit map-overhaul adapter.
- The canonical standalone fleet loader is country-history
  `set_naval_oob = "XAC_1936_naval"` backed by
  `history/units/XAC_1936_naval.txt`. Century of Iron integration must preserve
  its design-registration ordering and must not silently replace it with the
  unsuccessful runtime `create_ship` approach.
- No `replace_path` declaration is allowed without an explicit engine audit and
  recorded justification.
- Prefer additive files. Shadow a vanilla file only when HOI4 provides no
  additive hook, and list the override in a manifest.
- Awareness initializes through one startup hook and is saved per country as
  `coi_alien_awareness`: `0 Unaware`, `1 Anomalies`, `2 Suspicious`,
  `3 Confirmed`, and `4 Mobilized`. Broader Century of Iron crisis phases remain
  a separate adapter concern. Loading the standalone prototype always retains
  playable XAC and its starting expedition, but must not automatically select a
  target, declare war, or transfer human territory.
- Standalone defaults and Century of Iron adapters remain separate. The core
  alien simulation must not directly read undocumented `coi_` internals.
- Generated content is deterministic and produced from structured source data.
- Placeholder art is original or clearly reusable; third-party Workshop assets
  are never copied.
- The standalone development package is version `0.6.0`, named
  `Alien Crisis: Grey Consensus [DEV]`. The name is a development contract and
  does not imply that a public Steam Workshop release exists.

## Public integration surface

The eventual module exposes namespaced scripted effects and triggers rather than
requiring Century of Iron to know its internal files:

- Initialize or reset the awareness and landfall-control framework.
- Read or raise a country's exact awareness stage without a normal-gameplay
  downgrade path.
- Test future global contact, invasion, occupation, counteroffensive, and
  resolution phases separately from national awareness.
- Add or read global preparedness, alien adaptation, human unity, collaboration,
  and orbital-control values.
- Request a legal target country, save the player-selected target, raise it to
  at least Confirmed, and grant XAC the special landfall war goal. This public
  preparation operation must not declare war or change state ownership/control.
- Reconcile the existing XAC polity and Pale Anchorage startup package when the
  standalone prototype is adapted into Century of Iron.
- Grant captured-technology progress or a reverse-engineering opportunity.
- Produce a diagnostic report for observer tests.

The standalone implementation already uses `coi_alien_` scripted effects,
triggers, variables, flags, decisions, and war goals. Stable adapter wrapper
names will be finalized when the Century of Iron integration layer is built.

## DLC and version policy

The research architecture assumes Götterdämmerung because scientists,
facilities, prototypes, and breakthrough projects are central to alien and
reverse-engineering progression. Other DLC-dependent outputs receive explicit
fallbacks or are declared required before implementation.

The first supported game line is 1.19.x. Every HOI4 update requires a re-audit
of local documentation, defines, AI hooks, GUI overrides, and the override
manifest before changing `supported_version`.

## Local packaging boundary

- The launcher entry is installed beneath the current user's Hearts of Iron IV
  `mod` directory as `coi_alien_crisis_dev.mod`.
- The original image-generation cover is
  `Source/Art/Masters/coi_alien_workshop_cover.png`.
- The derived 512×512 review cover is
  `Source/Art/Preview/workshop_cover.png`; the 512×512 launcher/upload thumbnail
  is `Mod/thumbnail.png`.
- `picture="thumbnail.png"` is present in both local descriptors. No Workshop
  upload, public listing, published-file identifier, or compatibility promise
  follows from these local files.
