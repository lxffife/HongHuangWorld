# Fengdu 256m Terrain Prototype

This isolated scene is a terrain-shape study. It is not referenced by the live
world scene and does not change the production map.

## Open

Open `scenes/experiments/FengduTerrainPrototype.tscn` in Godot and run the
current scene (F6). The scene generates a deterministic 128 x 128 heightfield
at runtime, split into 4 x 4 independently bounded terrain tiles. Each 64m x
64m tile owns its visual mesh and trimesh collision body. The layout includes a
Forgotten River valley, raised Reincarnation Hall terrace, broken perimeter
ridges, and a Blood Sea coast/shelf.

## Coordinate contract

- World unit: 1 unit = 1 meter.
- Horizontal plane: X/Z; elevation: Y.
- Prototype extent: X/Z from -128m to +128m.
- Tile layout: 4 x 4; each tile is 64m x 64m with 32 x 32 cells.
- Tile nodes carry integer tile coordinates and world-space bounds in metadata.
- The Forgotten River remains centered near X=22m to align with the existing
  Fengdu prototype landmark.
- The Blood Sea is an eastern coastal study, not an unlocked gameplay region.
- Markers are visual annotations only. Server region IDs, POIs, spawn rules,
  tide hazards, and access permissions remain server-authoritative.

## Data-driven map metadata

`scripts/world_map_catalog.gd` is the shared client metadata source for:
- Fengdu and Qingyun display-region rectangles, with explicit priority/order.
- The isolated Fengdu prototype bounds, heightfield resolution, tile count, and world size.
- Visual water-body definitions (Forgotten River and Blood Sea) and landmark IDs, labels, coordinates, and colors.

`world_region_catalog.gd` delegates region-name resolution to this catalog. The existing region order and rectangles are preserved, including Qingyun's two pine-forest rectangles, so this refactor is intended to keep current HUD labels unchanged.

The terrain experiment now reads water and landmark placement from the catalog instead of embedding those coordinates in its scene script. Adding a new visual landmark or water body should therefore be a data change, while its rendering remains handled by the prototype.

These definitions are client presentation metadata, not gameplay permissions or authoritative world topology. A future Blood Sea deep-water, island, wreck, or ritual-island region must receive its authoritative region/POI and access rules from the server; adding a catalog entry alone does not make it traversable or discoverable.

## Minimap integration

The live world scene now supplies catalog landmarks to the shared minimap as normalized X/Z marker records. Catalog landmarks are rendered as purple diamond markers and can be clicked to set a navigation target, using the same world-to-radar projection as exploration points, NPCs, and monsters. The minimap remains a local radar centered on the player; this does not create a full-world map UI or reveal undiscovered server content.

## Why this is not Terrain3D yet

The mesh is deliberately generated with built-in Godot APIs so the shape and
coordinate contract can be reviewed without introducing a native plugin.
After the exact editor and NativeNet godot-cpp versions are confirmed, this
heightfield can become a reference surface for a version-matched Terrain3D
import/tiling test. The live map remains unchanged until that test passes.

## Current limitations

- `fengdu_terrain_streaming_manager.gd` incrementally creates and frees tile nodes
  around a focus node, with separate load/unload radii and a per-frame operation budget.
- The prototype focus marker starts at the map center, so its current 4 x 4 sample
  remains visible. A moving player/camera controller can drive the same focus node later
  through `set_focus_world_position()`. The manager emits `tile_loaded` and
  `tile_unloaded` signals and exposes `get_loaded_tile_count()`.
- Tile creation and collision cooking still run on the main thread; this is not
  threaded background streaming and has no LOD or visibility scheduler.
- No navigation baking, vegetation scatter, or runtime region transitions.
- Water surfaces are visual placeholders; tides, currents, damage, and
  traversal are not implemented.
- Each tile currently uses one trimesh collision surface; the prototype is not a production open-world setup.
