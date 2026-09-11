# Discovery and Disclosure

Version 0.6.0 implements the first terrestrial side of the Alien Crisis. It is
designed as reusable crisis infrastructure rather than one fixed historical
story: nations can know the truth, tell their population, and prepare for it at
different rates.

## Signals in the Noise

The news layer translates those saved systems into a public chronology without
creating a second awareness model. Eleven classified country reports cover the
RS/33 custody brief, correlation and black-program milestones, wartime lights,
postwar rocket and radar incidents, New Mexico in 1947, an abducted witness,
two Black Archive leak thresholds, and contact contingencies. Their single
acknowledgment options are narrative only; state changes occur in the scripted
effect that dispatches the report.

Seventeen world-news events cover the corresponding public arc from rumor to
undeniable contact. Optional pre-contact stories share a 120-day global
cooldown. Dated wartime and postwar opportunities are evaluated monthly, are
individually one-shot, and are marked resolved once their date windows expire
so an old save cannot receive a backlog. The RS/33 opening brief is the single
cheap daily exception so a fresh Italy receives its introduction promptly and
an eligible old save can migrate it once. Milestone stories such as official
acknowledgment, Open Files, public wreckage, the Vatican reliquary, landfall,
transmission, the Consensus verdict, and the XCOM demand bypass that rumor
cooldown.

Catastrophic disclosure records its cause before choosing exactly one opening
headline: public wreckage, deliberate landfall, or the existing fallback
announcement. The first intelligible transmission follows after seven days;
the four-way doctrine verdict follows at the next eligible doctrine tick; the
international demand for a unified extraterrestrial defense command follows
fourteen days later. That last event sets
`coi_alien_xcom_demand_established` only. XCOM formation remains future work.

The doctrine headline reports the existing country-count census unchanged:
fascist plurality seeks Galactic Federation, democratic plurality selects
Annihilation, communist plurality asserts Singular Sovereignty, and a
non-aligned plurality imposes a Planetary Mandate. The originating country,
XAC, and other human governments receive contextual reactions, but all visible
news options remain effect-free.

## Three independent tracks

Every terrestrial country stores three exact, monotonic values from 0 through
4. Scripted effects advance a track to a named threshold and never reduce it.

| Track | 0 | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- | --- |
| Classified knowledge | no case | anomalous reports | correlated pattern | classified confirmation | material proof |
| Public awareness | unaware | rumors | credible controversy | official acknowledgment | undeniable contact |
| Preparedness | unprepared | quiet monitoring | contingency planning | national mobilization | crisis war footing |

Legacy `coi_alien_awareness` checks remain compatibility aliases over the new
knowledge track so older saves and already-authored mechanics keep working.

## Policy routes

At classified confirmation, a country adopts one disclosure stance. AI base
weights are 80 Black Archive, 8 Prepared Public, 8 The World Must Know, and 4
Open the Files. Government, stability, faction membership, and existing public
controversy modify those weights. A player can pivot for 100 political power,
5% stability, and a 180-day policy lock.

- Black Archive suppresses public evidence and accepts leak risk.
- Prepared Public runs a measured three-stage managed-disclosure sequence.
- The World Must Know joins a cooperative international council. It shares
  evidence but never creates, joins, or changes a faction.
- Open the Files discloses immediately at high political cost.
- Catastrophic disclosure bypasses policy once contact becomes globally
  undeniable.

## Recovery and reverse engineering

Project NIGHT LANTERN is a 30-day, 25-command-power interception decision for a
country with the required detection or military infrastructure. Its baseline
outcomes are 50% lost signal, 30% fragments, 15% damaged craft, and 5% public
crash. Radar, preparedness, and later dates improve the result. The United
States receives a 1947 echo, while an intact recovery uses a five-year global
cooldown and each participant has a one-year country cooldown.

Evidence opens a Special Access Program. With Götterdämmerung, fragments feed
Exotic Materials Characterization in a land facility. Its completion unlocks
the helper technology and enables the air-facility Field Propulsion
Reconstruction project when intact field evidence exists. These are the first
two nodes in the eventual human reverse-engineering tree; completion does not
grant alien production lines wholesale.

## Magenta and Vatican flavor

The claimed 1933 Lombardy/Magenta recovery is used as mod-canon alternate-
history flavor, not asserted as verified history. Italy begins with material
proof, no public awareness, quiet monitoring, the RS-33 custody flag, and a
Black Archive. Germany receives the transferred dossier and sample trail. The
Vatican holds a permanent sealed-reliquary idea and Grey-remains flag, providing
the religious and institutional implications requested for later content.

## Catastrophic disclosure

`coi_alien_begin_catastrophic_disclosure_effect` is the integration hook for a
public crash, terrestrial debug test, or XAC's prepared-landfall decision. It
sets both the new catastrophic flag and the legacy disclosure flag without
declaring war or transferring land.

The global wave reaches countries in tranches at 0, 14, 30, 60, and 90 days.
An unfiltered hidden sentinel is redundantly queued on every terrestrial
country, so a surviving host closes the wave at day 90 even if every country
was processed early or XAC and the original contact country were annexed.
Initial crisis shock is derived from prior public awareness, prior preparedness,
and policy stance before all three tracks advance to 4.

For 180 days each country can:

- address the nation;
- open emergency shelters;
- empower scientific authority;
- activate military continuity;
- expose the cover-up; or
- coordinate international aid.

The first four are broad stabilization tools. Exposing the cover-up is stronger
but politically disruptive; international aid rewards prior council work and
cooperation. Scores at or below 40 stabilize. Scores from 41 through 70 produce
leadership collapse. A score above 70 with stability below 25% opens an explicit
warning event; only accepting that warned risk can start a guarded civil war.
Capitulated countries, countries already in civil war, and one-state countries
cannot enter that branch, and all characters are retained.

Response projects cancel when the 180-day crisis closes. A response begun too
late cannot apply score or idea effects after the country has already resolved
its disclosure outcome.

## Integration boundary

The Grey Consensus remains separate from these human systems. The disclosure
hook creates a world condition, not an invasion. Later event chains can decide
whether contact becomes federation, extermination, resistance, accommodation,
religious crisis, or war. National focus trees should call the named scripted
effects rather than write the three variables directly.

## Version 0.6.0 verification

An isolated fresh-XAC smoke run on HOI4 1.19.2.0.a729 loaded all 13,415
provinces and all 28 `coi_alien_news` events, entered single player, advanced to
1936.1.5.1, and autosaved with the narrative framework and RS/33 state
initialized. No news, GFX, localization, event, scope, or parser errors were
reported, and no crash directory was created. The error log contained only the
existing equipment-enum documentation notices and two established remote-file
allocation warnings.

An isolated copy of `Ironman Grey Consensus 1.hoi4` likewise parsed the active
0.6.0 mod, map, and all 28 events without a mod error. Unattended command-line
resume stopped at HOI4's front-end save-confirmation boundary, so that copy was
not advanced. The source save and both test copies remained byte-identical at
SHA-256
`B1760CE98A0FCCB40988EE5AD64EC0FD8EFAA9FD45E355D0A243CD6A595FCDAA`.

Version 0.6.0 is live on the permanent private Workshop item with visibility
`2` and has been verified by authenticated download.
