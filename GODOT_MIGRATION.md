# Bitcoin Civilizations — Godot 4 Migration Plan

> Planning document for porting the HTML5/Canvas prototype to Godot 4 (GDScript).
> Source: `index.html` (~2900 lines, single-file prototype)

---

## 1. Prototype Audit

### Systems That Exist

#### Map Generation
- **Seeded Perlin noise** via custom `Noise` class (permutation table, `fade`/`lerp`/`grad`, `fbm` with configurable octaves)
- **Three noise layers**: elevation (`noise1`, scale 0.06, 5 octaves), moisture (`noise2`, scale 0.08, 4 octaves), heat (`noiseHeat`, scale 0.05, 3 octaves)
- **Island falloff**: radial distance-based falloff (`1 - pow(min(dist * 0.8, 1), 2.5)`) applied to elevation
- **Biome quadrant biases**: NE gets +0.25 heat / -0.25 moisture (desert), SW gets +0.2 moisture (forest), SE gets +0.12 elevation (mountains)
- **Terrain classification** from elevation/moisture/heat thresholds:
  - `< 0.18` → Deep Water
  - `0.18–0.28` → Coast
  - `0.28–0.55` → Plains/Desert/Forest (based on heat + moisture)
  - `0.55–0.70` → Hills
  - `0.70–0.85` → Mountains
  - `> 0.85` → Snow
- **Volcanic placement**: 10–12% chance on mountain tiles, SE quadrant gets slightly less (10% vs 12%)
- **Quadrant terrain distribution enforcement** (5 passes): each quadrant has min/max % targets for land terrain types; over-represented types donate tiles to under-represented ones
- **Hard rules**: Desert ONLY in NE, Volcanic ONLY in SE (enforced post-generation)
- **Terrain clustering**: iterative algorithm that flood-fills connected components per terrain type per quadrant, keeps the largest cluster, and grows it by relocating scattered tiles to the cluster frontier (scored by elevation/moisture/heat affinity + neighbor count)
- **Mountain range consolidation**: one contiguous range per quadrant — smaller components get merged into the largest via frontier swapping; isolated peaks (< 3 tiles) become hills
- **Mountain hole filling**: non-mountain tiles with 5+ mountain/snow/volcanic neighbors become mountains (up to 10 passes)
- **Volcanic adjacency rule**: volcanic tiles must touch at least one mountain/snow tile or get converted to mountains
- **Major River ("The Great Channel")**: north-to-south through NW/SW quadrants, noise-based meandering (scale 0.08), variable width (1–2 tiles), avoids mountains/snow/volcanic
- **Per-quadrant tributary rivers**: carved downhill from high-elevation starting points, 1–3 per quadrant (SW gets 3–4), follows lowest-elevation neighbors with seeded randomness
- **Resource deposit placement**: probabilistic per terrain type:
  - Coal: 10% on hills/mountains
  - Iron: 6% on hills/mountains
  - Uranium: 3% on hills/mountains, 15% on volcanic
  - Gas: 5% on plains/desert
- **Quadrant deposit validation**: minimum 2 coal, 2 gas, 1 uranium, 1 iron per quadrant; deficit deposits placed randomly on valid terrain
- **Quadrant river guarantee**: if a quadrant has zero river tiles, one is carved
- **Quadrant water/mountain overflow protection**: if > 70% of a quadrant is water + mountains, excess mountains → hills/forest, deep water with elevation > 0.12 → plains
- **Energy potential calculation** per tile:
  - Solar: 80–100 (desert), 40–60 (plains), 35–55 (hills), 15–30 (forest), 20–40 (mountains/snow), 25–45 (volcanic), 30–50 (water/river/coast/snow)
  - Wind: 70–90 (mountains/snow), 60–85 (hills), 55–75 (coast), 40–60 (desert/volcanic/deep water), 30–50 (plains), 10–25 (forest), 25–40 (river)
  - Hydro: 85–100 (major river), 65–85 (river), 30–50 (coast adjacent to river), 20–40 (within 2 tiles of river), 0 (desert), 0–5 (other)
  - Geothermal: 75–100 (volcanic), 20–40 (within 2 tiles of volcanic), 5–15 (mountains), 0 (other)

#### Terrain Types (11)
| ID | Name | Color | Dark Color |
|----|------|-------|------------|
| 0 | Deep Water | `#1a3a5c` | `#12304e` |
| 1 | Coast | `#2a6496` | `#1e5580` |
| 2 | Plains | `#4a7c3f` | `#3d6834` |
| 3 | Hills | `#6a8f4e` | `#587840` |
| 4 | Mountains | `#8a8a8a` | `#6e6e6e` |
| 5 | Desert | `#c4a93a` | `#a8912e` |
| 6 | River | `#3488b8` | `#2878a0` |
| 7 | Volcanic | `#8b3a3a` | `#722e2e` |
| 8 | Forest | `#2d5a27` | `#234a1f` |
| 9 | Snow Peak | `#d8dce8` | `#b8bcc8` |
| 10 | The Great Channel | `#2070c0` | `#1860a8` |

Buildable terrain: Plains (2), Forest (8), Desert (5), Hills (3).
Special buildable (energy buildings only): River (6), Major River (10), Volcanic (7).

#### Resource Deposits (4)
| Name | Color | Symbol | Terrain |
|------|-------|--------|---------|
| Coal | `#444` | ◆ | Hills, Mountains |
| Gas | `#66aaff` | ◎ | Plains, Desert |
| Uranium | `#44ff88` | ☢ | Hills, Mountains, Volcanic |
| Iron | `#cc6633` | ▣ | Hills, Mountains |

#### Civilizations (4)
| ID | Name | Color | Quadrant | Player? |
|----|------|-------|----------|---------|
| 0 | Satoshi's Legacy | `#F7931A` | NW | Yes |
| 1 | The Hash Collective | `#00A8FF` | NE | No (AI) |
| 2 | Nakamoto Republic | `#00CC66` | SW | No (AI) |
| 3 | Block Frontier | `#AA44FF` | SE | No (AI) |

Starting treasury: 1000 sats each.

#### Starting Position Algorithm
- Scores every buildable tile in quadrant bounds (inset 2 from edges)
- Requires ≥ 5 buildable tiles within radius 2
- Scoring: proximity to river (+10 per tile closer within 5), solar/wind potential, adjacent buildable count, distance to quadrant center
- Citadel placed at best tile, then spiral outward for other buildings

#### Building System (8 types)
| Type | Name | Energy Out | Energy Cost | Hash | Pop Cap | Workers | Food | Description |
|------|------|-----------|------------|------|---------|---------|------|-------------|
| citadel | Citadel | 0 | 0 | 0 | 0 | 0 | 0 | Central hub |
| house | House | 0 | 0 | 0 | 2 | 0 | 0 | Housing for 2 |
| farm | Farm | 0 | 0 | 0 | 0 | 1 | 4 | Feeds population |
| solar_panel | Solar Panel Array | 8 | 0 | 0 | 0 | 0 | 0 | 10 in desert |
| home_miner | Home Miner | 0 | 2 | 3 | 0 | 1 | 0 | Basic Bitcoin miner |
| hydro_dam | Hydro Dam | 15 | 0 | 0 | 0 | 2 | 0 | 18 in SW, 20 on major river |
| wind_turbine | Wind Turbine | 6 | 0 | 0 | 0 | 0 | 0 | 8 in SE quadrant |
| geothermal_plant | Geothermal Plant | 12 | 0 | 0 | 0 | 2 | 0 | 15 on volcanic |

**Terrain bonuses**:
- Solar Panel: 8 → 10 on Desert
- Hydro Dam: 15 → 18 in SW quadrant, 15 → 20 on Major River
- Wind Turbine: 6 → 8 in SE quadrant
- Geothermal Plant: 12 → 15 on Volcanic

**Starting buildings per civ**:
- All: Citadel, 2× House, Farm, Home Miner, Solar Panel
- NE (desert): +1 extra Solar Panel
- SW (rivers): +1 Hydro Dam (on nearest river within 12 tiles)
- SE (mountains): +1 Wind Turbine (on nearest hill within 12 tiles)
- NW (balanced): Solar Panel only

#### Economy System
- `population = min(maxPopulation, foodProduced)` (1 food per pop, simplified)
- Miners activate only if sufficient energy available (greedy: first-come allocation)
- **Block reward**: starts at 50 sats
- **Halving**: every 100 turns, reward halves (minimum 1)
- **Mining distribution**: `earned = blockReward × (civHash / totalNetworkHash)`, rounded to 2 decimal places
- Treasury accumulates per turn

#### Turn System
- Triggered by Space key or "Next Turn" button
- Each turn: increment counter → check halving → recalculate all civ stats → distribute block reward → show toast summary → update HUD

#### Rendering (Canvas 2D)
- **Map**: 80×80 tiles, isometric projection
  - `TILE_W = 64, TILE_H = 32` (diamond aspect ratio 2:1)
  - `toIso(tx, ty) = ((tx - ty) × 32, (tx + ty) × 16)`
  - Tile elevation creates 3D depth sides (darkColor for sides)
  - Color variation via `noise_simple()` hash (±8 brightness)
  - Frustum culling per tile
  - Back-to-front rendering (y then x loop)
- **Terrain decorations**:
  - Mountains/Snow: triangle peak overlay
  - Forest: 3 small triangles (trees)
  - Volcanic: pulsing red glow (animated `sin(Date.now())`)
  - River: animated shimmer curve
  - Major River: dual animated shimmer curves (deeper effect)
  - Desert: subtle sand dune curve
  - Coast/Deep Water: animated floating circle
- **Building rendering**: 8 distinct procedural sprites drawn with Canvas primitives (no image assets)
  - Citadel: diamond base + spire + crenellations + radial glow
  - House: rectangular walls + triangular colored roof + door
  - Farm: diamond field + crop lines + small barn
  - Solar Panel: angled parallelogram + grid lines + support pole + shine
  - Home Miner: dark box + ventilation lines + blinking orange LED with glow
  - Hydro Dam: curved arc wall + water pool + animated water flow
  - Wind Turbine: pole + rotating 3-blade + base + colored hub
  - Geothermal Plant: building + pipes + chimney + animated steam + heat glow
- **Deposit markers**: colored symbols at zoom > 0.5

#### Camera
- Pan: WASD / Arrow keys (speed 400px/s, scaled by dt and zoom)
- Drag: mouse down → move → calculates offset
- Zoom: scroll wheel (0.3–3.0 range), zooms toward cursor position
- Initial position: centered on player's citadel
- Minimap click: jump to location

#### Tile Selection & Info Panel
- Click (< 5px drag threshold) selects tile
- Info panel shows: coordinates, terrain name, elevation (as meters), terrain bonuses, deposit badge, building info (with actual energy output including bonuses), energy potential bars (solar/wind/hydro/geothermal with colored fill bars)

#### Civilization Overview Panel
- Toggle with `C` key
- Shows all 4 civs: name, color swatch, treasury, hash power, population/max, energy net/produced
- Player marked as "(You)", others as "(AI)"

#### Minimap (200×200 canvas)
- Top-down grid rendering (terrain colors, deposit overlay, building dots)
- Quadrant dividers (white lines at 50%)
- Quadrant color tints (6% opacity)
- Selected tile marker
- Viewport rectangle
- Click to jump camera

#### Seeded PRNG
- **mulberry32** algorithm
- Default seed: 12345
- Persistence: `localStorage.getItem/setItem('btcCivMapSeed')`
- "New Map" button: generates random seed, saves, regenerates everything

#### Other
- `requestAnimationFrame` game loop with delta-time capping (max 32ms)
- Hover coordinates displayed in top bar
- Terrain legend panel (bottom-left)
- Controls hint bar (bottom-center)
- Toast notification for turn summaries (3s fade)
- Full keyboard/mouse input handling with drag detection

---

### What's Missing (for "Actual Game")

- **No building placement UI** — player cannot construct buildings; only starting buildings exist
- **No AI behavior** — AI civs are completely static after initial placement
- **No tech tree** — all buildings available from start, no progression
- **No combat / hash wars** — no way to attack or disrupt other civs
- **No trade / diplomacy** — no inter-civ interaction at all
- **No fog of war** — entire map visible from turn 1
- **No sound** — completely silent
- **No save/load** — only the map seed persists (via localStorage); game state is lost on refresh
- **No population growth** — population is purely a function of buildings, no organic growth
- **No happiness system** — no morale, pollution, or civic satisfaction
- **No win conditions** — game runs indefinitely
- **No unit movement** — no movable units or armies
- **No territory expansion** — no concept of owned territory beyond building locations
- **No main menu** — game starts immediately
- **No difficulty settings** — all civs are identical in capability
- **No building costs** — starting buildings are free; no sats spent on construction

---

### What to Preserve (Port Faithfully)

- **All map generation logic** — noise, elevation/moisture/heat layers, island falloff, quadrant biases, terrain classification thresholds
- **Quadrant terrain distribution targets** and enforcement algorithm
- **Terrain clustering algorithm** (flood fill, frontier growth, affinity scoring)
- **Mountain range consolidation** (single range per quadrant, hole filling, adjacency rules)
- **River generation** — major river path + per-quadrant tributaries
- **Deposit placement** rules and quadrant validation minimums
- **Energy potential calculation** formulas and ranges
- **Economy balance numbers** — building stats, block reward (50), halving interval (100), population formula
- **Civilization definitions** — names, colors, quadrants, starting treasury (1000)
- **Building types and terrain bonuses** — exact output values and bonus conditions
- **Starting position scoring algorithm** — river proximity, buildable adjacency, solar/wind potential, center distance
- **Starting building placement** — quadrant-specific energy building selection, spiral outward placement
- **Visual identity** — color palette, Bitcoin orange (#F7931A), dark UI theme, terrain colors

### What to Rewrite

- **Rendering** — Godot TileMapLayer or custom `_draw()` replaces Canvas 2D
- **Input handling** — Godot's `_input()` / `_unhandled_input()` / InputMap replaces DOM events
- **UI** — Godot Control nodes replace HTML/CSS panels
- **Game loop** — Godot's `_process(delta)` and signals replace `requestAnimationFrame`
- **Building sprites** — replace procedural Canvas drawing with Godot Sprite2D or custom `_draw()`
- **Animation** — Godot AnimationPlayer / tweens replace `Date.now()` + `sin()` hacks

---

## 2. Proposed Godot Folder Structure

```
bitcoin-civilizations-godot/
├── project.godot
├── icon.svg
├── assets/
│   ├── tiles/                  # Tile sprites/textures (or generated via _draw)
│   ├── buildings/              # Building sprites
│   ├── ui/                     # UI theme, fonts, icons
│   └── audio/                  # Sound effects, music (Phase 5)
├── scenes/
│   ├── main.tscn               # Root scene
│   ├── game_world.tscn         # Map + buildings + units
│   ├── hud.tscn                # Top bar HUD
│   ├── tile_info.tscn          # Tile info panel
│   ├── civ_panel.tscn          # Civilization overview
│   ├── minimap.tscn            # Minimap
│   ├── build_menu.tscn         # Building placement UI (NEW)
│   └── main_menu.tscn          # Start screen (NEW)
├── scripts/
│   ├── autoload/
│   │   ├── game_data.gd        # Global constants: terrain defs, building defs, civ defs
│   │   └── game_state.gd       # Global game state singleton (current map, civs, buildings, turn)
│   ├── map/
│   │   ├── map_generator.gd    # Procedural generation orchestrator
│   │   ├── noise.gd            # Perlin noise (port of JS Noise class)
│   │   ├── terrain_rules.gd    # Quadrant enforcement, clustering, mountain consolidation
│   │   └── river_generator.gd  # River carving (tributaries + Great Channel)
│   ├── world/
│   │   ├── game_world.gd       # Main world node: orchestrates map + buildings
│   │   ├── tile_map_iso.gd     # Isometric tile rendering (TileMapLayer or custom)
│   │   ├── building_manager.gd # Building placement, rendering, querying
│   │   └── camera_controller.gd # Pan (WASD/drag), zoom (scroll), edge scroll
│   ├── economy/
│   │   ├── economy_engine.gd   # Energy → hash → Bitcoin calculation
│   │   ├── turn_manager.gd     # Turn processing, halving, block rewards
│   │   └── civ_manager.gd      # Civilization state, starting positions, stat recalculation
│   ├── ui/
│   │   ├── hud.gd              # Top bar (turn, treasury, hash, energy, pop)
│   │   ├── tile_info_panel.gd  # Tile selection info display
│   │   ├── civ_panel.gd        # Civilization overview
│   │   ├── minimap.gd          # Minimap rendering
│   │   └── build_menu.gd       # Building placement UI (NEW)
│   └── ai/
│       └── ai_controller.gd    # AI opponent behavior (placeholder → Phase 5)
├── resources/
│   ├── terrain_data.tres       # Terrain type definitions as Resource array
│   ├── building_data.tres      # Building type definitions as Resource array
│   └── civ_data.tres           # Civilization definitions as Resource array
└── themes/
    └── bitcoin_theme.tres      # UI theme (dark bg + orange accents)
```

---

## 3. Node/Scene Tree Plan

```
Main (Node2D)
├── GameWorld (Node2D) [game_world.gd]
│   ├── TileMapLayer (TileMapLayer) [tile_map_iso.gd]
│   ├── BuildingLayer (Node2D) [building_manager.gd]
│   ├── SelectionHighlight (Node2D)
│   └── Camera2D [camera_controller.gd]
├── CanvasLayer (UI)
│   ├── HUD (HBoxContainer) [hud.gd]
│   │   ├── LogoLabel
│   │   ├── TurnLabel
│   │   ├── CivIndicator (ColorRect + Label)
│   │   ├── TreasuryLabel
│   │   ├── HashLabel
│   │   ├── EnergyLabel
│   │   ├── PopLabel
│   │   ├── NextTurnButton (Button)
│   │   └── NewMapButton (Button)
│   ├── TileInfoPanel (PanelContainer) [tile_info_panel.gd]
│   │   ├── VBoxContainer
│   │   │   ├── CoordsRow (HBoxContainer)
│   │   │   ├── TerrainRow (HBoxContainer)
│   │   │   ├── ElevationRow (HBoxContainer)
│   │   │   ├── BonusList (VBoxContainer)
│   │   │   ├── DepositBadge (HBoxContainer)
│   │   │   ├── BuildingInfoBox (PanelContainer)
│   │   │   └── EnergyPotentialSection (VBoxContainer)
│   │   │       ├── SolarBar (ProgressBar + Label)
│   │   │       ├── WindBar (ProgressBar + Label)
│   │   │       ├── HydroBar (ProgressBar + Label)
│   │   │       └── GeoBar (ProgressBar + Label)
│   ├── CivPanel (PanelContainer) [civ_panel.gd]
│   │   └── VBoxContainer
│   │       └── (CivEntry scenes × 4)
│   ├── BuildMenu (PanelContainer) [build_menu.gd]
│   │   └── VBoxContainer
│   │       └── (BuildingButton scenes × N)
│   ├── Minimap (SubViewportContainer) [minimap.gd]
│   │   └── SubViewport
│   │       └── MinimapRenderer (Node2D)
│   ├── ToastContainer (Control)
│   │   └── ToastLabel (Label)
│   ├── CoordsLabel (Label) — hover coordinates
│   └── ControlsHint (Label)
└── AudioManager (Node) [audio_manager.gd]
```

### Key Scene Relationships

| Scene | Instantiated By | Signal Connections |
|-------|----------------|-------------------|
| `main.tscn` | Root | — |
| `game_world.tscn` | main.tscn | `tile_selected(x, y)` → TileInfoPanel, `tile_hovered(x, y)` → CoordsLabel |
| `hud.tscn` | CanvasLayer | `next_turn_pressed` → TurnManager, `new_map_pressed` → GameState |
| `tile_info.tscn` | CanvasLayer | Listens to `tile_selected` |
| `civ_panel.tscn` | CanvasLayer | Listens to `turn_processed`, toggle via `C` key |
| `build_menu.tscn` | CanvasLayer | `building_selected(type)` → BuildingManager |
| `minimap.tscn` | CanvasLayer | `minimap_clicked(world_pos)` → Camera2D |
| `main_menu.tscn` | Separate scene tree root | `start_game(seed)` → loads main.tscn |

---

## 4. Data Model Plan

### TerrainData (Resource)

```gdscript
class_name TerrainData extends Resource

@export var id: int
@export var terrain_name: String
@export var color: Color
@export var dark_color: Color
@export var is_buildable: bool           # Plains, Forest, Desert, Hills
@export var is_special_buildable: bool   # River, Major River, Volcanic (energy buildings only)
@export var is_water: bool               # Deep Water, Coast
@export var solar_range: Vector2i        # (min, max) potential
@export var wind_range: Vector2i
@export var hydro_range: Vector2i
@export var geothermal_range: Vector2i
```

### TileData (per-tile runtime, stored in flat arrays on GameState)

```gdscript
# Stored as parallel arrays indexed by (y * MAP_W + x) for cache efficiency
var terrain_ids: PackedInt32Array       # terrain type id
var elevations: PackedFloat32Array
var moistures: PackedFloat32Array
var heats: PackedFloat32Array
var deposits: Array[StringName]         # "", "coal", "gas", "uranium", "iron"
var solar_potentials: PackedInt32Array
var wind_potentials: PackedInt32Array
var hydro_potentials: PackedInt32Array
var geothermal_potentials: PackedInt32Array
var owner_civs: PackedInt32Array        # -1 = unclaimed
```

### BuildingData (Resource)

```gdscript
class_name BuildingData extends Resource

@export var id: StringName              # "citadel", "house", "farm", etc.
@export var display_name: String
@export var cost: int                   # Sats to build (NEW — prototype has no costs)
@export var energy_output: int          # Base energy production
@export var energy_cost: int            # Energy consumed per turn
@export var hash_power: int             # Hash rate contribution
@export var pop_capacity: int           # Housing slots provided
@export var pop_cost: int               # Workers required
@export var food_output: int            # Food produced per turn
@export var required_terrain: Array[int] # Terrain IDs where this can be built
@export var description: String

# Terrain bonus overrides (terrain_id → energy_output)
@export var terrain_bonuses: Dictionary  # { 5: 10, 10: 20 } etc.
```

### CivState (runtime)

```gdscript
class_name CivState extends RefCounted

var id: int
var civ_name: String
var color: Color
var quadrant: String                    # "NW", "NE", "SW", "SE"
var is_player: bool

# Economy
var treasury: float = 1000.0
var hash_power: int = 0
var energy_produced: int = 0
var energy_consumed: int = 0
var population: int = 0
var max_population: int = 0
var food_produced: int = 0
```

### BuildingInstance (runtime)

```gdscript
class_name BuildingInstance extends RefCounted

var type: StringName                    # Key into BuildingData
var owner: int                          # Civ ID
var x: int
var y: int
var active: bool = true
```

### TurnSummary

```gdscript
class_name TurnSummary extends RefCounted

var turn_number: int
var block_reward: float
var total_network_hash: int
var civ_earnings: Dictionary            # { civ_id: sats_earned }
var halving_occurred: bool
```

### GameConstants (in game_data.gd autoload)

```gdscript
const MAP_W: int = 80
const MAP_H: int = 80
const TILE_W: int = 64
const TILE_H: int = 32
const DEFAULT_SEED: int = 12345
const STARTING_TREASURY: float = 1000.0
const STARTING_BLOCK_REWARD: float = 50.0
const HALVING_INTERVAL: int = 100
const BTC_ORANGE: Color = Color("#F7931A")
```

---

## 5. Step-by-Step Migration Plan

### Phase 1: Project Skeleton & Map

**Goal**: See the procedurally generated isometric map in Godot with camera controls.

1. **Create Godot 4 project** with the folder structure from §2
2. **Set up autoloads**: `game_data.gd` (constants, terrain/building/civ definitions), `game_state.gd` (runtime state)
3. **Port `Noise` class** to GDScript (`noise.gd`)
   - Permutation table generation from seed
   - `fade()`, `lerp()`, `grad()`, `get(x, y)`, `fbm(x, y, octaves)`
   - Validate: same seed must produce same noise values as JS version
4. **Port `generateMap()`** to `map_generator.gd`
   - Three noise layers (elevation, moisture, heat) with same scales/octaves
   - Island falloff formula
   - Quadrant biome biases (NE heat+, SW moisture+, SE elevation+)
   - Terrain classification from thresholds
   - Volcanic placement (random on mountains, 10–12%)
5. **Port terrain enforcement** to `terrain_rules.gd`
   - `QUAD_TARGETS` distribution table
   - `enforceQuadrantDistribution()` — 5-pass redistribution
   - Hard rules (desert→NE only, volcanic→SE only)
   - `clusterTerrain()` — flood fill, frontier growth, affinity scoring
   - Mountain consolidation — single range per quadrant, hole filling, volcanic adjacency
6. **Port river generation** to `river_generator.gd`
   - Major River (Great Channel): noise-based path through NW/SW, variable width
   - Per-quadrant tributaries: downhill carving with seeded randomness
7. **Port deposit placement and energy potential calculation**
   - Probabilistic deposits per terrain type
   - Quadrant deposit validation (minimums)
   - Energy potential formulas (solar/wind/hydro/geothermal per terrain + proximity)
8. **Render map** using Godot's `TileMapLayer` (isometric mode)
   - Option A: Programmatic tile atlas — generate colored diamond textures at runtime
   - Option B: Custom `_draw()` on a Node2D (closer to prototype's approach)
   - Recommendation: **Option A** (TileMapLayer) for better performance; create a tile atlas with terrain-colored diamonds and assign tiles programmatically
   - Elevation depth sides can be rendered via a custom draw overlay or second TileMapLayer
   - Terrain decorations (trees, peaks, etc.) rendered as Sprite2D children or custom draw
9. **Camera controller** (`camera_controller.gd`)
   - WASD / Arrow key panning (speed 400/s, delta-scaled, zoom-adjusted)
   - Mouse drag panning
   - Scroll wheel zoom (0.3–3.0 range, zoom toward cursor)
   - Edge scrolling (optional, not in prototype)
10. **Tile selection** (`game_world.gd`)
    - `_unhandled_input()` for mouse clicks
    - Screen-to-tile coordinate conversion (inverse isometric transform)
    - Emit `tile_selected(x, y)` signal
    - Selection highlight (orange diamond outline)
    - Hover detection for coordinates display

**Milestone**: Can generate a map, see it rendered isometrically, pan/zoom around, click tiles.

### Phase 2: Game State & Economy

**Goal**: Economy ticks, buildings produce energy/hash/food, Bitcoin is mined.

1. **Port civilization definitions** to `civ_manager.gd`
   - 4 civs with name, color, quadrant, isPlayer flag
   - `CivState` instances in `game_state.gd`
2. **Port starting position selection** algorithm
   - Quadrant bounds (inset 2 from edges)
   - Scoring: river proximity, buildable adjacency, solar/wind, center distance
   - Pick highest-scoring tile for citadel
3. **Port starting building placement**
   - Spiral outward from citadel for base buildings
   - Quadrant-specific energy buildings (Hydro Dam on river for SW, Wind Turbine on hill for SE, etc.)
   - `findNearestTileOfType()` helper
4. **Port economy engine** (`economy_engine.gd`)
   - `recalculateCivStats()`: iterate buildings, sum energy output (with terrain bonuses), pop capacity, food
   - Population = min(maxPop, food)
   - Miner activation: greedy energy allocation, hash power accumulation
5. **Port turn processing** (`turn_manager.gd`)
   - Halving check: `turn % 100 == 0` → reward / 2 (min 1)
   - Total network hash → proportional reward distribution
   - Treasury accumulation
   - Emit `turn_processed(TurnSummary)` signal
6. **Recalculate on turn and on building change**

**Milestone**: Press "Next Turn", see civs earn Bitcoin proportional to hash power.

### Phase 3: UI

**Goal**: Full HUD and info panels matching prototype's functionality.

1. **HUD** (`hud.tscn` + `hud.gd`)
   - Top bar: logo, turn counter, civ indicator (color + name), treasury (₿), hash power (⛏), energy (⚡ net/produced), population (👥 current/max)
   - "Next Turn" button + "New Map" button
   - Dark theme with `bitcoin_theme.tres` (bg: `#14141e`, border: orange 30%, text: `#e0e0e0`)
2. **Tile info panel** (`tile_info.tscn` + `tile_info_panel.gd`)
   - Coordinates, terrain name (highlighted), elevation
   - Terrain bonuses list (contextual)
   - Deposit badge
   - Building info box (name, owner, energy output with bonus, hash, housing, workers, food, description)
   - Energy potential section (4 colored progress bars)
3. **Civilization overview panel** (`civ_panel.tscn` + `civ_panel.gd`)
   - Toggle with `C` key
   - 4 civ entries: color swatch, name, (You)/(AI), treasury, hash, pop, energy
4. **Minimap** (`minimap.tscn` + `minimap.gd`)
   - SubViewport rendering at 200×200
   - Terrain colors, deposit overlay, building dots (citadels larger)
   - Quadrant lines + tints
   - Selected tile marker
   - Viewport rectangle
   - Click to jump camera
5. **Toast notifications**
   - Turn summary: "Block N Mined", reward, per-civ earnings
   - 3-second fade out
   - Use Tween for animation
6. **Terrain legend** (optional — may drop for cleaner UI in Godot)
7. **Hover coordinates** label in HUD area

**Milestone**: Full visual parity with prototype UI.

### Phase 4: Building Placement (NEW — Not in Prototype)

**Goal**: Player can spend sats to construct buildings.

1. **Build menu UI** (`build_menu.tscn` + `build_menu.gd`)
   - Panel showing available building types with costs, stats, descriptions
   - Grayed out if player can't afford or no valid placement exists
   - Toggle with `B` key or button
2. **Valid placement highlighting**
   - When building type selected, highlight all valid tiles in green
   - Invalid tiles dimmed
   - Terrain requirements per building type
   - Can't build on occupied tiles
3. **Click to place**
   - Deduct cost from player treasury
   - Instantiate building, add to game state
   - Recalculate civ stats immediately
   - Play placement SFX (when audio exists)
4. **Construction constraints**
   - Terrain type matching (solar anywhere buildable, hydro on river, wind on hills, geothermal on volcanic)
   - Must be in player's quadrant (initially) or owned territory (later)
   - Building costs (define sensible defaults):
     - House: 50 sats
     - Farm: 30 sats
     - Solar Panel: 100 sats
     - Home Miner: 150 sats
     - Hydro Dam: 200 sats
     - Wind Turbine: 120 sats
     - Geothermal Plant: 250 sats

**Milestone**: Player can build structures, spend sats, grow their economy.

### Phase 5: AI & Polish

**Goal**: AI opponents play the game; save/load works; main menu exists.

1. **Basic AI controller** (`ai_controller.gd`)
   - Per-civ decision-making each turn
   - Priority: energy first → housing → food → miners
   - Evaluate best building to place based on available terrain and resources
   - Difficulty scaling via decision quality (random noise on scoring)
2. **Save/load** system
   - Serialize `game_state` to JSON or Godot Resource
   - Save: map seed, turn number, all building instances, civ treasuries, block reward
   - Map regeneration from seed (deterministic) — don't save full map data
   - Load: regenerate map from seed, restore buildings and state
3. **Main menu** (`main_menu.tscn`)
   - New Game (optional seed input)
   - Load Game
   - Settings (volume, controls)
4. **Audio placeholder hooks**
   - `AudioManager` singleton with play functions
   - Stub sound categories: UI click, building placed, turn processed, halving event, ambient

**Milestone**: Complete playable game loop with AI opponents.

---

## 6. Playable MVP Definition

The MVP is complete when **all of the following** are true:

- [ ] Player can start a new game and see a procedurally generated isometric map
- [ ] Map generation is deterministic (same seed = same map, matching JS prototype output)
- [ ] 4 civilizations spawn with correct starting buildings in their quadrants
- [ ] Player can pan (WASD + mouse drag) and zoom (scroll wheel)
- [ ] Player can click tiles to select them
- [ ] Tile info panel shows: terrain, elevation, deposits, energy potentials, building info with bonuses
- [ ] Player can open build menu and place buildings on valid tiles (costs sats from treasury)
- [ ] Invalid placements are prevented (wrong terrain, insufficient funds, occupied tile)
- [ ] "Next Turn" button advances the economy:
  - Energy recalculated with terrain bonuses
  - Population = min(housing, food)
  - Miners activate if energy available
  - Block reward distributed proportional to hash share
  - Halving every 100 turns
- [ ] HUD displays: turn, civ name/color, treasury, hash power, energy, population
- [ ] Minimap renders and supports click-to-jump
- [ ] Civ overview panel shows all 4 civilizations' stats (toggle with C)
- [ ] Turn summary toast appears after each turn
- [ ] "New Map" regenerates everything with a new random seed
- [ ] UI follows dark theme with Bitcoin orange accents

**Not required for MVP**: AI behavior, save/load, main menu, sound, fog of war, tech tree, combat, diplomacy, territory.

---

## 7. Phase 2 Backlog (Post-MVP)

### Economy & Growth
- Population growth over turns (needs food surplus + housing)
- Happiness system (pollution from coal/gas power, overcrowding penalty, prosperity bonus)
- Building maintenance costs (energy upkeep, worker wages)
- Building upgrades (Solar Panel → Solar Farm, Home Miner → Mining Rig → ASIC Facility)
- Resource consumption (coal/gas/uranium as fuel for power plants — not just terrain bonuses)

### Tech Tree
- Research system (spend sats + turns to unlock)
- Progression: basic buildings → advanced energy → industrial mining → network infrastructure
- Unique techs per quadrant advantage (NE: solar mastery, SW: hydro mastery, SE: geothermal mastery, NW: balanced)

### AI & Competition
- AI opponents that actually build and expand each turn
- AI personalities: aggressive miner, balanced builder, tech rusher, expansionist
- Difficulty levels (AI decision quality, starting bonus)
- Hash wars (redirect hash power to attack other civs' infrastructure)
- Sabotage / espionage actions

### Territory & Expansion
- Territory control (tiles owned by civs, expanding from buildings)
- Influence borders (culture/economic pressure)
- Contested tiles and border conflicts
- Military units for territory capture
- Fog of war (only see own territory + scouted areas)

### Diplomacy & Trade
- Trade routes between civs
- Lightning Network channels (fast payment lanes for trade bonuses)
- Diplomatic actions: alliance, trade agreement, non-aggression pact, embargo
- Resource trading (iron for uranium, etc.)

### Bitcoin Mechanics
- Difficulty adjustment every N blocks (scales with total network hash)
- Mempool and transaction fees as secondary income
- Mining pools (combine hash with allied civs)
- 51% attack victory condition
- Lightning Network as late-game infrastructure

### Win Conditions
- **Hash Dominance**: control > 51% of network hash for N consecutive turns
- **Economic Victory**: accumulate X Bitcoin
- **Network Victory**: build N Lightning channels connecting all quadrants
- **Cultural Victory**: highest happiness + population
- **Survival**: last civ standing after hash wars

### Polish & Content
- Sound effects (UI, building, mining, ambient, music)
- Proper tile art (replace colored diamonds with actual isometric sprites)
- Building construction animations
- Mining particle effects (orange sparkles)
- Weather system (visual only or gameplay impact)
- Day/night cycle (visual)
- Proper save/load with multiple slots
- Settings menu (audio, controls, display)
- Tutorial / guided first game
- Statistics screen (graphs of treasury, hash, population over time)

### Platform
- Multiplayer (long-term: P2P or server-based)
- Mobile export (touch controls)
- Web export (HTML5 via Godot's web build)

---

## Appendix A: Seeded PRNG Reference

The prototype uses **mulberry32**. For Godot, either:

1. **Port mulberry32 to GDScript** (recommended for identical output):
```gdscript
class_name SeededRNG extends RefCounted

var state: int

func _init(seed: int) -> void:
    state = seed

func next_float() -> float:
    state = (state + 0x6D2B79F5) & 0xFFFFFFFF
    var t: int = ((state ^ (state >> 15)) * (1 | state)) & 0xFFFFFFFF
    t = ((t + ((t ^ (t >> 7)) * (61 | t)) & 0xFFFFFFFF) ^ t) & 0xFFFFFFFF
    return float((t ^ (t >> 14)) & 0x7FFFFFFF) / 2147483648.0
```

2. **Use Godot's RandomNumberGenerator** (simpler but different output):
```gdscript
var rng = RandomNumberGenerator.new()
rng.seed = my_seed
```

**Note**: If pixel-perfect map parity with the JS prototype is required for testing, use option 1. Otherwise, option 2 is fine since the map just needs to be *good*, not *identical*.

## Appendix B: Coordinate Transform Reference

```gdscript
# Tile → Isometric screen position
func to_iso(tx: int, ty: int) -> Vector2:
    return Vector2(
        (tx - ty) * HALF_W,
        (tx + ty) * HALF_H
    )

# Screen → Tile (accounting for camera)
func from_screen(screen_pos: Vector2, viewport_size: Vector2, cam_pos: Vector2, zoom: float) -> Vector2i:
    var wx: float = (screen_pos.x - viewport_size.x / 2.0 + cam_pos.x) / zoom
    var wy: float = (screen_pos.y - viewport_size.y / 2.0 + cam_pos.y) / zoom
    var tx: float = (wx / HALF_W + wy / HALF_H) / 2.0
    var ty: float = (wy / HALF_H - wx / HALF_W) / 2.0
    return Vector2i(int(tx), int(ty))
```

If using Godot's built-in TileMapLayer with isometric mode, the engine handles coordinate transforms via `local_to_map()` and `map_to_local()`. Custom transforms only needed for custom `_draw()` rendering.

## Appendix C: Building Cost Proposal

The prototype has no building costs. Proposed costs for MVP (balance TBD through playtesting):

| Building | Cost (sats) | Rationale |
|----------|-------------|-----------|
| House | 50 | Cheap, needed early for workers |
| Farm | 30 | Cheapest — food is foundational |
| Solar Panel | 100 | Moderate — universal energy source |
| Wind Turbine | 120 | Slightly more — terrain-restricted |
| Home Miner | 150 | Core income generator |
| Hydro Dam | 200 | Strong output, terrain-restricted |
| Geothermal Plant | 250 | Strongest base output, very restricted |

Starting treasury of 1000 sats allows roughly: 2 Houses (100) + 1 Farm (30) + 1 Solar (100) + 1 Miner (150) = 380 sats spent on first turn, with 620 remaining for growth. This feels about right — enough to expand but requires earning.
