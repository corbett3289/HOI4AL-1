# The Quiet Chorus

The Quiet Chorus is the Grey Consensus intelligence service introduced in
version 0.3.0. It is a La Resistance-native system: operations, operatives,
agency upgrades, network strength, risk, and preparation all use HOI4's own
espionage databases rather than parallel political decisions.

## Roster

The authored complement contains three Greys and three autonomous drones. Neth
Witness and Quiet Orbit begin active; Ysil Lattice, Cael Current, Pale Echo,
and Outer Witness are XAC-only reserve candidates. The agency spirit supplies a
second initial operative slot, while Distributed Drone Cells supplies a third.
All procedural XAC recruits use alien portrait pools and Consensus signal
designations rather than human portraits or codenames.

Autonomous drones share the `coi_alien_autonomous_infiltration_drone` trait.
They are hard to detect and interrogate, improve general and infiltration
outcomes slightly, and reduce infiltration, sabotage, and archive-operation
risk. They also carry the vanilla Tough trait so capture and escape behavior
remains compatible with HOI4's operative systems.

## Access and operations

| Operation | Operatives | Days | Network | Base risk | Result |
|---|---:|---:|---:|---:|---|
| Silent Systems Survey | 1 | 45 | 20 | 5% | Surface Profile, +1 Survey Data |
| Seed Mimetic Access | 2 | 75 | 35 | 10% | Institutional Access |
| Penetrate Research Networks | 2 | 90 | 50 | 10% | Research Access, +1 Survey Data |
| Spoil the Evidence | 2 | 60 | 40 | 10% | Consumes deep access; halts investigation for 180 days |
| Introduce Cascading Faults | 3 | 90 | 60 | 20% | Damages selected-state infrastructure and, when present, a radar/air/naval node |
| Harvest Project Archives | 3 | 120 | 60 | 20% | Consumes Research Access; +2 data and one Alien Science bonus |
| Disrupt Research Complex | 3 | 105 | 60 | 25% | Damages a selected facility and injures its active scientist |
| Extract Lead Scientist | 3 | 150 | 70 | 30% | Removes an active scientist and opens the XAC disposition event |

Surface Profile is durable. Institutional and Research Access are rebuilt after
payloads consume them. Survey Data is global, cumulative, and never spent. The
three XAC-only upgrades unlock at 1, 3, and 5 data:

1. Mimetic Interface Lab, after Observe a Divided World.
2. Cognitive Translation Matrix, after Classify Human Order.
3. Distributed Drone Cells.

The AI scores unprofiled countries overwhelmingly while below five data, so it
surveys multiple human polities rather than stalling on one target. Afterward it
preserves mature access networks, favors project archives, and uses scientist
extraction or controlled sabotage when eligible.

## Scientist disposition and raid boundary

Extract Lead Scientist is covert infiltration and exfiltration, not a tactical
abduction raid. The operation selects a controlled special-project facility
state containing an active, uninjured scientist. Completion immediately removes
that scientist from the target roster, raises awareness, consumes deep access,
and applies a two-year per-target cooldown; leaving the disposition event open
cannot leave the scientist working.

The XAC event then chooses among study (50% AI weight), off-world transplant
(30%), or permanent strategic removal (20%). No branch transfers, naturalizes,
generates, or adds a human scientist to XAC. Strategic removal temporarily
reduces the target's research and special-project performance.

Forced specimen seizure and overt physical abduction remain reserved for the
future raid layer. The old Specimen Acquisition decision ID is retained only as
a hidden, disabled save-compatibility shell.

## Art and compatibility

Eight built-in imagegen masters supply all operation-list, map, phase, token,
inline-text, and agency-upgrade assets at native HOI4 dimensions. The three
custom token hooks are injected through a hash-pinned 1.19.2 copy of
`countryintelligenceagencyview.gui`; stripping the generated block must reproduce
the vanilla SHA-256 contract.

All operation and roster initialization is guarded by La Resistance and XAC's
original tag. Special-project operations rely on content and scientist/facility
eligibility rather than a hard Götterdämmerung gate; they disappear naturally
when no valid facility/scientist target exists. AI operation IDs stored in saved
variables are registered as synchronized dynamic tokens for multiplayer safety.
