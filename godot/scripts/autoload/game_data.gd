extends Node
## Global constants and definitions — ported faithfully from the HTML prototype.

# ── Map Constants ──────────────────────────────────────────────
const MAP_W: int = 80
const MAP_H: int = 80
const TILE_W: int = 64
const TILE_H: int = 32
const HALF_W: int = TILE_W / 2  # 32
const HALF_H: int = TILE_H / 2  # 16
const DEFAULT_SEED: int = 12345
const STARTING_TREASURY: float = 1000.0
const STARTING_BLOCK_REWARD: float = 50.0
const HALVING_INTERVAL: int = 100
const BTC_ORANGE: Color = Color("#F7931A")

# ── Terrain IDs ────────────────────────────────────────────────
const T_DEEP_WATER: int = 0
const T_COAST: int = 1
const T_PLAINS: int = 2
const T_HILLS: int = 3
const T_MOUNTAINS: int = 4
const T_DESERT: int = 5
const T_RIVER: int = 6
const T_VOLCANIC: int = 7
const T_FOREST: int = 8
const T_SNOW: int = 9
const T_MAJOR_RIVER: int = 10

# ── Terrain Definitions ───────────────────────────────────────
# Each entry: { id, name, color, dark_color, buildable, special_buildable, is_water }
var TERRAIN_DEFS: Dictionary = {
	T_DEEP_WATER: { "id": T_DEEP_WATER, "name": "Deep Water",        "color": Color("#1a3a5c"), "dark_color": Color("#12304e"), "buildable": false, "special_buildable": false, "is_water": true },
	T_COAST:      { "id": T_COAST,      "name": "Coast",             "color": Color("#2a6496"), "dark_color": Color("#1e5580"), "buildable": false, "special_buildable": false, "is_water": true },
	T_PLAINS:     { "id": T_PLAINS,     "name": "Plains",            "color": Color("#4a7c3f"), "dark_color": Color("#3d6834"), "buildable": true,  "special_buildable": false, "is_water": false },
	T_HILLS:      { "id": T_HILLS,      "name": "Hills",             "color": Color("#6a8f4e"), "dark_color": Color("#587840"), "buildable": true,  "special_buildable": false, "is_water": false },
	T_MOUNTAINS:  { "id": T_MOUNTAINS,  "name": "Mountains",         "color": Color("#8a8a8a"), "dark_color": Color("#6e6e6e"), "buildable": false, "special_buildable": false, "is_water": false },
	T_DESERT:     { "id": T_DESERT,     "name": "Desert",            "color": Color("#c4a93a"), "dark_color": Color("#a8912e"), "buildable": true,  "special_buildable": false, "is_water": false },
	T_RIVER:      { "id": T_RIVER,      "name": "River",             "color": Color("#3488b8"), "dark_color": Color("#2878a0"), "buildable": false, "special_buildable": true,  "is_water": false },
	T_VOLCANIC:   { "id": T_VOLCANIC,   "name": "Volcanic",          "color": Color("#8b3a3a"), "dark_color": Color("#722e2e"), "buildable": false, "special_buildable": true,  "is_water": false },
	T_FOREST:     { "id": T_FOREST,     "name": "Forest",            "color": Color("#2d5a27"), "dark_color": Color("#234a1f"), "buildable": true,  "special_buildable": false, "is_water": false },
	T_SNOW:       { "id": T_SNOW,       "name": "Snow Peak",         "color": Color("#d8dce8"), "dark_color": Color("#b8bcc8"), "buildable": false, "special_buildable": false, "is_water": false },
	T_MAJOR_RIVER:{ "id": T_MAJOR_RIVER,"name": "The Great Channel", "color": Color("#2070c0"), "dark_color": Color("#1860a8"), "buildable": false, "special_buildable": true,  "is_water": false },
}

# Buildable terrain IDs (standard buildings)
const BUILDABLE_TERRAIN: Array[int] = [T_PLAINS, T_FOREST, T_DESERT, T_HILLS]

# ── Deposit Definitions ───────────────────────────────────────
var DEPOSITS: Dictionary = {
	"coal":    { "name": "Coal",    "color": Color("#444444"), "symbol": "◆" },
	"gas":     { "name": "Gas",     "color": Color("#66aaff"), "symbol": "◎" },
	"uranium": { "name": "Uranium", "color": Color("#44ff88"), "symbol": "☢" },
	"iron":    { "name": "Iron",    "color": Color("#cc6633"), "symbol": "▣" },
}

# ── Building Definitions ──────────────────────────────────────
# energy = energy COST for miners, energy_output = energy PRODUCED
var BUILDING_TYPES: Dictionary = {
	"citadel": {
		"name": "Citadel",
		"energy": 0, "hash_power": 0, "pop_capacity": 0, "pop_cost": 0,
		"food_output": 0, "energy_output": 0,
		"description": "Central hub of your civilization",
	},
	"house": {
		"name": "House",
		"energy": 0, "hash_power": 0, "pop_capacity": 2, "pop_cost": 0,
		"food_output": 0, "energy_output": 0,
		"description": "Provides housing for 2 workers",
	},
	"farm": {
		"name": "Farm",
		"energy": 0, "hash_power": 0, "pop_capacity": 0, "pop_cost": 1,
		"food_output": 4, "energy_output": 0,
		"description": "Feeds your population",
	},
	"solar_panel": {
		"name": "Solar Panel Array",
		"energy": 0, "hash_power": 0, "pop_capacity": 0, "pop_cost": 0,
		"food_output": 0, "energy_output": 8,
		"description": "Generates 8 energy (10 in desert)",
	},
	"hydro_dam": {
		"name": "Hydro Dam",
		"energy": 0, "hash_power": 0, "pop_capacity": 0, "pop_cost": 2,
		"food_output": 0, "energy_output": 15,
		"description": "Generates 15 energy on river (18 in river quadrant). Needs 2 workers",
	},
	"wind_turbine": {
		"name": "Wind Turbine",
		"energy": 0, "hash_power": 0, "pop_capacity": 0, "pop_cost": 0,
		"food_output": 0, "energy_output": 6,
		"description": "Generates 6 energy on hills (8 in mountain quadrant)",
	},
	"geothermal_plant": {
		"name": "Geothermal Plant",
		"energy": 0, "hash_power": 0, "pop_capacity": 0, "pop_cost": 2,
		"food_output": 0, "energy_output": 12,
		"description": "Generates 12 energy on volcanic (15 with bonus). Needs 2 workers",
	},
	"home_miner": {
		"name": "Home Miner",
		"energy": 2, "hash_power": 3, "pop_capacity": 0, "pop_cost": 1,
		"food_output": 0, "energy_output": 0,
		"description": "Basic Bitcoin miner: 3 H/s, uses 2⚡ + 1 worker",
	},
}

# Terrain bonuses for energy buildings: { building_type: { condition_key: output } }
# Applied in economy_engine; condition checked at runtime
const TERRAIN_BONUSES: Dictionary = {
	"solar_panel": { "desert": 10 },
	"hydro_dam": { "major_river": 20, "sw_quadrant": 18 },
	"wind_turbine": { "se_quadrant": 8 },
	"geothermal_plant": { "volcanic": 15 },
}

# ── Civilization Definitions ──────────────────────────────────
var CIVILIZATIONS: Array[Dictionary] = [
	{ "id": 0, "name": "Satoshi's Legacy",    "color": Color("#F7931A"), "quadrant": "NW", "is_player": true },
	{ "id": 1, "name": "The Hash Collective", "color": Color("#00A8FF"), "quadrant": "NE", "is_player": false },
	{ "id": 2, "name": "Nakamoto Republic",   "color": Color("#00CC66"), "quadrant": "SW", "is_player": false },
	{ "id": 3, "name": "Block Frontier",      "color": Color("#AA44FF"), "quadrant": "SE", "is_player": false },
]

# ── Quadrant Terrain Distribution Targets ─────────────────────
# Per-quadrant min/max % for each LAND terrain type.
# Water/river/snow untouched. Snow counted as mountains.
var QUAD_TARGETS: Dictionary = {
	"NW": {
		T_PLAINS:    [25, 35],
		T_FOREST:    [25, 30],
		T_HILLS:     [10, 15],
		T_MOUNTAINS: [5, 8],
		T_DESERT:    [0, 0],
		T_VOLCANIC:  [0, 0],
	},
	"NE": {
		T_DESERT:    [30, 45],
		T_PLAINS:    [15, 25],
		T_HILLS:     [8, 12],
		T_MOUNTAINS: [5, 10],
		T_FOREST:    [3, 8],
		T_VOLCANIC:  [0, 0],
	},
	"SW": {
		T_FOREST:    [30, 40],
		T_PLAINS:    [15, 25],
		T_HILLS:     [8, 12],
		T_MOUNTAINS: [3, 6],
		T_VOLCANIC:  [0, 0],
		T_DESERT:    [0, 0],
	},
	"SE": {
		T_HILLS:     [15, 20],
		T_MOUNTAINS: [12, 18],
		T_VOLCANIC:  [3, 5],
		T_PLAINS:    [15, 25],
		T_FOREST:    [5, 10],
		T_DESERT:    [0, 0],
	},
}

# ── Helpers ────────────────────────────────────────────────────

static func get_quadrant_name(x: int, y: int) -> String:
	var half_w: int = MAP_W / 2
	var half_h: int = MAP_H / 2
	if x < half_w and y < half_h:
		return "NW"
	if x >= half_w and y < half_h:
		return "NE"
	if x < half_w and y >= half_h:
		return "SW"
	return "SE"

static func is_buildable_terrain(terrain_id: int) -> bool:
	return terrain_id in BUILDABLE_TERRAIN

static func is_buildable_or_special(terrain_id: int) -> bool:
	return terrain_id in BUILDABLE_TERRAIN or terrain_id == T_RIVER or terrain_id == T_MAJOR_RIVER or terrain_id == T_VOLCANIC

# Quadrant bounds used for starting positions (inset 2 from edges)
static func get_quadrant_bounds(quadrant: String) -> Dictionary:
	var half_w: int = MAP_W / 2
	var half_h: int = MAP_H / 2
	match quadrant:
		"NW": return { "x0": 2, "y0": 2, "x1": half_w - 2, "y1": half_h - 2 }
		"NE": return { "x0": half_w + 2, "y0": 2, "x1": MAP_W - 2, "y1": half_h - 2 }
		"SW": return { "x0": 2, "y0": half_h + 2, "x1": half_w - 2, "y1": MAP_H - 2 }
		"SE": return { "x0": half_w + 2, "y0": half_h + 2, "x1": MAP_W - 2, "y1": MAP_H - 2 }
		_:    return { "x0": 0, "y0": 0, "x1": MAP_W, "y1": MAP_H }

# Full quadrant bounds (no inset) — used in map generation
static func get_quadrant_full_bounds() -> Array[Dictionary]:
	var half_w: int = MAP_W / 2
	var half_h: int = MAP_H / 2
	return [
		{ "name": "NW", "x0": 0, "y0": 0, "x1": half_w, "y1": half_h },
		{ "name": "NE", "x0": half_w, "y0": 0, "x1": MAP_W, "y1": half_h },
		{ "name": "SW", "x0": 0, "y0": half_h, "x1": half_w, "y1": MAP_H },
		{ "name": "SE", "x0": half_w, "y0": half_h, "x1": MAP_W, "y1": MAP_H },
	]
