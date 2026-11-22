# Fengdu Capital — Environment Art Direction

## Visual pillars

1. **Imperial underworld authority** — monumental axial planning, heavy stone plinths, layered gates and a distant palace silhouette.
2. **Cold, inhabited afterlife** — blue-gray stone, restrained bronze/gold trim, warm soul-lantern accents, low-contrast fog.
3. **Readable MMORPG city** — clear street hierarchy, recognizable district entrances, uncluttered landmarks and traversable public space.

## Palette and material rules

| Role | Direction | Current graybox |
|---|---|---|
| Primary stone | blue-gray basalt, rough | #59616a |
| Deep stone | charcoal, near-black | #303941 |
| Roof | dark slate / blue-black | #252d3a |
| Metal trim | aged bronze, not polished gold | #c39a5b |
| Road | worn gray flagstone | #77736d |
| Soul light | warm amber, emissive | #e8ad5d |
| Water | deep desaturated blue | #172f45 |
| Atmosphere | cold blue-gray fog | #424b59 |

## Architecture grammar

- City walls: continuous heavy masonry, crenellations, four controlled gate openings.
- Gates: paired gate towers, broad lintel, layered roof silhouette, visible approach bridge.
- Public halls: raised stone plinth, central hall, repeated columns, two or three roof tiers.
- Roofs: dark ceramic tile mass with bronze edge accents. Later art pass should add curved eaves and ridge ornaments as reusable mesh modules.
- Street props: lantern posts at regular intervals; warm emissive geometry is used instead of dozens of real-time point lights.
- Districts: one dominant hall plus smaller subordinate buildings; each has a clear forecourt and visible name marker.

## Scale and readability

- One Godot world unit = one meter.
- Player capsule: 0.96m diameter × 1.8m height.
- Main streets: 13m; central ceremonial way: 20m.
- Gate opening: 16m; wall height: 13m.
- District footprints: roughly 18–40m.
- Landmark names should be readable from the main approach but must not overlap the player HUD.
- Fog is for depth separation, not a gameplay blocker; important gates and palace silhouette must remain visible.

## Performance policy

- Prefer shared materials and repeated primitive meshes for graybox.
- Use emissive lantern meshes before adding dynamic lights.
- Avoid per-prop real-time shadows. Reserve shadow casting for the sun and major landmarks.
- Later production pass should instance repeated props (MultiMeshInstance3D) and use LOD for distant city silhouettes.
- Do not import third-party assets without recording source, license, attribution and local file path.

## Next art pass

1. Replace roof blocks with a reusable curved-eave roof module.
2. Add modular gatehouse pieces: brackets, columns, ridge caps, corner finials and door leaves.
3. Add terrain height bands and navigable ramps before adding decorative cliff meshes.
4. Validate at the actual target resolution and on the target low-end GPU.

## Market and residential quarter blockout

- The ghost market uses a continuous central trading aisle, six inward-facing stalls, an auction dais, service-side lanes, notice boards and emissive lantern props.
- The soul ward uses four offset courtyard homes around a shared square and well, with a small tea pavilion as a social anchor.
- Candidate NPC activity coordinates are stored locally for later integration; they are not authoritative spawn points and do not imply NPC navigation is implemented.

## Military, intake and patrol blockout

- The barracks now has a central drill yard, perimeter barracks, watch posts, weapon racks and training dummies. These are visual blockout props only.
- The soul waystation reads as an arrival → registration → waiting → dispatch sequence, with queue rails and a dispatch gate. No actual queue or reincarnation logic is implemented.
- The patrol office combines a dispatch hall, route table, watch posts and signal tower. Candidate NPC activity coordinates are local scene data only; patrol navigation and server synchronization remain future work.


## Local activity-point visualization

- The scene converts the legacy per-district candidate positions into semantic activity records: district, role, activity, position, facing, schedule tag, capacity and radius.
- F6 toggles a lightweight debug overlay; it is off by default. Marker colors distinguish merchants, residents, soldiers, guides and patrol guards.
- The patrol planning loop follows the existing distributor/perimeter road grid. It is not a navigation mesh, a live NPC simulation or server-authoritative movement.


## First local NPC visual pass

- Use primitive, low-cost humanoid silhouettes as temporary placeholders: robe capsule, head sphere, simple arms and role props. No external model dependency is introduced.
- Role accents: merchant headwear silhouette, soldier spear, guide soul lantern and a small registration ledger, plus distinct role material tints.
- Activity-point facing is assigned by district purpose rather than a universal forward direction. Residents orient toward the shared square; the guide faces the intake approach; soldiers and merchants face their work areas.
- Idle motions use per-agent phase offsets and cadence variation: merchant greeting, resident conversation turns, soldier readying motions, and guide ledger-check/directing gestures. One patrol guard interpolates between the closed-loop road nodes; it does not use NavigationAgent3D.
- These figures are local scene decoration only: no collision, combat, dialogue, shop, quest, network identity or authoritative state. Replace them with licensed rigged assets and server-backed actors in later production passes.
