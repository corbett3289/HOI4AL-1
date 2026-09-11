# Alien Design Brief

Status: the working species identity is the Greys and the playable polity is the
Grey Consensus. Detailed biology, culture, motive, visual language, and final
balance remain design work.

## Recommended mechanical premise

The invader should be an expeditionary force, not the alien civilization's
unlimited total strength. It has a decisive qualitative advantage at arrival
but depends on a narrow interstellar or orbital reinforcement corridor, a small
number of terrestrial anchors, unfamiliar local conditions, and finite command
attention.

This premise creates HOI4 counterplay:

- Alien units begin superior without requiring impossible stat inflation.
- Humanity can target landing zones, relays, supply anchors, collaborators, and
  research assets rather than winning only by grinding every division down.
- The invader must choose where to concentrate scarce elite formations and when
  to request another wave.
- Captured equipment and battlefield observation let both sides adapt.
- Alien losses matter even if the civilization behind them is vastly larger.

The mothership and orbital theater are strategic systems, raids, map entities,
and event state. HOI4 has no orbital province layer. In the standalone
prototype, the alien polity is already a normal playable map country in 1936,
based at the artificial Pale Anchorage at Point Nemo. A later landfall selects
the first human target; it does not create `XAC` or award it human territory.

## Implemented prototype baseline

- `XAC` owns and cores Pale Anchorage (state `1082`, province `13414`) and uses
  it as its 1936 capital.
- Pale Anchorage is a custom 16-slot Artificial Arcology. Fourteen shared slots
  are occupied at scenario start, leaving two for expansion.
- The starting expedition is naval-air: one Pale Horizon, four Silent Current
  escorts, 30 Needle interceptors, and 20 Gleam strike craft. The 1+4 fleet is
  loaded through the canonical history naval OOB at Point Nemo; aircraft enter
  the stockpile through a separately guarded startup effect. These assets are
  an expeditionary kernel, not the civilization's total strength.
- Each human country tracks awareness independently as `0 Unaware`,
  `1 Anomalies`, `2 Suspicious`, `3 Confirmed`, or `4 Mobilized`.
- A player selects the landfall target. Preparation raises that target to at
  least Confirmed and grants `XAC` a special war goal, but does not declare war
  or change state ownership or control.
- The standalone design remains namespaced and is intended for later inclusion
  in Century of Iron. Full8 and Full9 explicitly booted as XAC and proved the
  custom naval units, OOB, and stockpile counts. A live Steam screenshot also
  shows the Grey flag, Pale Anchorage, 100K manpower, and five-ship stack;
  politics, portraits, detailed panels, and save/reload remain pending.

## Creative decisions required

### Biology and culture

- What “Grey” means biologically: organic, synthetic, cybernetic, distributed,
  mixed, or a human translation that obscures a more complicated reality.
- Body plan, scale, senses, atmosphere and gravity tolerance, lifespan,
  reproduction, disease exposure, and dependence on protective equipment.
- Individual minds, hive or networked cognition, castes, clones, artificial
  persons, or another social structure.
- Spoken or non-spoken communication and the rules for names, ranks, and
  translation.

### Civilization and motive

- Colonization, extraction, refuge, containment, extermination, forced unity,
  ideological mission, scientific intervention, or pursuit of another threat.
- Whether the expedition represents a united civilization, one faction, a
  private venture, a machine mandate, or fugitives.
- What it needs from Earth and what outcome counts as victory.
- What it refuses to do, fears, misunderstands, or cannot replace.
- Whether negotiation is sincere, tactical, culturally difficult, or impossible
  until particular events occur.

### Internal politics

- Supreme authority and the expedition commander's actual freedom.
- Military, scientific, logistical, intelligence, occupation, religious, and
  dissident factions.
- Conditions under which commanders defect, split, negotiate, or radicalize.
- Treatment of human governments, collaborators, prisoners, civilians, and
  reverse-engineering efforts.

### Visual language

- Dominant silhouette and geometry.
- Materials, surface treatment, light, energy effects, and palette.
- Symbols, writing, flags, uniforms, rank markers, architecture, and interfaces.
- Whether machines resemble their makers or follow a separate industrial logic.
- Sound palette, voice treatment, alarms, weapons, engines, and music direction.

## Leadership roster

The complete alien country will need roles, not merely one ruler:

- Civilizational authority or translated head of state.
- Expedition commander and potential successor or rival.
- Land-warfare commanders for assault, occupation, and defensive adaptation.
- Air or orbital-warfare commander.
- Logistics and reinforcement-corridor director.
- Chief scientist plus specialists for materials, energy, biology, computation,
  propulsion, and human reverse engineering.
- Intelligence or infiltration director.
- Occupation governor or liaison responsible for collaborators.
- Diplomat, interpreter, defector, or dissident who can support non-conquest
  outcomes.
- Industrial and strategic advisors represented through characters, traits,
  organisations, or national systems as appropriate.

Each important character requires a stable ID, name and title, portrait, role,
traits, ideology or faction alignment, AI meaning, succession conditions,
capture and death rules, and narrative reactions.

## Capability families

Alien technology should be coherent enough that players can infer strengths and
counters. Candidate domains are:

- Power generation, storage, and distribution.
- Advanced materials, armor, self-repair, and construction.
- Propulsion, atmospheric flight, gravitic or field control, and transport.
- Directed energy, projectiles, guided weapons, area denial, and strategic fire.
- Sensors, communications, electronic warfare, stealth, and command networks.
- Computation, autonomy, coordination, and machine intelligence.
- Biology, medicine, environmental protection, genetic engineering, and
  ecosystem manipulation.
- Logistics, fabrication, recycling, reinforcement anchors, and portal or relay
  systems.
- Orbital reconnaissance, interdiction, bombardment, and landing support.
- Occupation, translation, influence, collaboration, and human-technology
  exploitation.

Every capability needs a limitation, resource, prerequisite, counter, or
operational cost. "Alien" is not permission for unexplained universal bonuses.

## Equipment families

The first complete roster probably needs:

- Standard individual weapon and protective system.
- Heavy infantry weapon and squad support package.
- Command, sensor, shield or defensive, medical/repair, and engineering support.
- Light autonomous scout or combat drone.
- Protected transport or mechanized carrier.
- Heavy assault vehicle, walker, grav platform, organism, or equivalent.
- Mobile indirect-fire or siege system.
- Air-superiority or interception craft.
- Strike or close-support craft.
- Airlift or landing craft.
- Relay, anchor, fabrication, and occupation infrastructure.
- Orbital assets represented through strategic systems and raids.

The prototype uses a small ocean-going naval-air expedition because Point Nemo
is the playable starting anchor. The canonical OOB loader, custom sub-units,
exact 1+4 fleet, and 30/20 air complement are runtime-proven in explicit XAC
boots. The live map screenshot confirms the five-ship stack, but detailed fleet
panels, aircraft deployment, combat, portrait/politics presentation, and
save/reload behavior still require direct tests before expansion.

## Human interaction

Alien content is incomplete unless humans have tools to understand and oppose
it:

- Anomaly detection, secrecy, disclosure, panic, diplomacy, and preparedness.
- Captured equipment, defectors, intelligence, and reverse-engineering projects.
- Coalition command, research sharing, aid, basing, and competing national
  agendas.
- Collaboration, accommodation, resistance, exploitation, and independent
  survival strategies.
- Military counters to alien protection, sensors, supply anchors, air power,
  command networks, and biological vulnerabilities.
- Postwar treatment of alien survivors, technology, territory, collaborators,
  and damaged ecosystems.

## Balance contract

- Arrival is frightening and changes the rules of war.
- Alien equipment is qualitatively advanced but expensive or difficult to
  replace locally.
- The expedition cannot immediately cover the entire map.
- Landing anchors and orbital control matter at least as much as raw industry.
- Humans who cooperate intelligently can learn and counter; isolated countries
  cannot all reverse-engineer the full tree independently.
- The alien AI can win, but it does not receive invisible omnipotence or endless
  unit spawning.
- Playing the aliens offers strategic choices and constraints rather than a
  cheat-mode conquest.
