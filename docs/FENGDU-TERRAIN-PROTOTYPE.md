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
  remains visible. A moving player/camera controller can drive the same focus node later.
- Tile creation and collision cooking still run on the main thread; this is not
  threaded background streaming and has no LOD or visibility scheduler.
- No LOD, navigation baking, vegetation scatter, or runtime region transitions.
- Water surfaces are visual placeholders; tides, currents, damage, and
  traversal are not implemented.
- Each tile currently uses one trimesh collision surface; the prototype is not a production open-world setup.
