extends Node
## Global game state singleton — holds all runtime data.

# ── Signals ────────────────────────────────────────────────────
signal tile_selected(x: int, y: int)
signal tile_deselected()
signal turn_advanced(turn_number: int)
signal building_placed(building: Dictionary)
signal map_generated()

# ── Map Data (populated by MapGenerator) ──────────────────────
var terrain: Array = []        # 2D array [y][x] of terrain IDs
var elevation: Array = []      # 2D array [y][x] of float 0..1
var moisture: Array = []       # 2D array [y][x] of float 0..1
var heat: Array = []           # 2D array [y][x] of float 0..1
var deposits: Array = []       # 2D array [y][x] of deposit key String or ""
var resource_data: Array = []  # 2D array [y][x] of { solar, wind, hydro, geothermal }
var major_river_tiles: Dictionary = {}  # "x,y" -> true

# ── Game State ─────────────────────────────────────────────────
var turn: int = 0
var block_reward: float = GameData.STARTING_BLOCK_REWARD
var halving_interval: int = GameData.HALVING_INTERVAL
var buildings: Array[Dictionary] = []  # { type, owner, x, y, active }
var civs: Array[Dictionary] = []       # runtime civ state

# ── Selection ──────────────────────────────────────────────────
var selected_tile: Vector2i = Vector2i(-1, -1)
var hovered_tile: Vector2i = Vector2i(-1, -1)

# ── Seed ───────────────────────────────────────────────────────
var current_seed: int = GameData.DEFAULT_SEED

# ── Init ───────────────────────────────────────────────────────
func _ready() -> void:
	reset_civs()

func reset_civs() -> void:
	civs.clear()
	for civ_def: Dictionary in GameData.CIVILIZATIONS:
		civs.append({
			"id": civ_def["id"],
			"name": civ_def["name"],
			"color": civ_def["color"],
			"quadrant": civ_def["quadrant"],
			"is_player": civ_def["is_player"],
			"treasury": GameData.STARTING_TREASURY,
			"hash_power": 0,
			"energy_produced": 0,
			"energy_consumed": 0,
			"population": 0,
			"max_population": 0,
			"food_produced": 0,
		})

func reset_game() -> void:
	turn = 0
	block_reward = GameData.STARTING_BLOCK_REWARD
	buildings.clear()
	selected_tile = Vector2i(-1, -1)
	hovered_tile = Vector2i(-1, -1)
	reset_civs()

func init_map_arrays() -> void:
	terrain.clear()
	elevation.clear()
	moisture.clear()
	heat.clear()
	deposits.clear()
	resource_data.clear()
	major_river_tiles.clear()
	for y in range(GameData.MAP_H):
		terrain.append([])
		elevation.append([])
		moisture.append([])
		heat.append([])
		deposits.append([])
		resource_data.append([])
		for x in range(GameData.MAP_W):
			terrain[y].append(GameData.T_DEEP_WATER)
			elevation[y].append(0.0)
			moisture[y].append(0.0)
			heat[y].append(0.0)
			deposits[y].append("")
			resource_data[y].append({ "solar": 0, "wind": 0, "hydro": 0, "geothermal": 0 })

# ── Tile Queries ───────────────────────────────────────────────
func select_tile(x: int, y: int) -> void:
	selected_tile = Vector2i(x, y)
	tile_selected.emit(x, y)

func deselect_tile() -> void:
	selected_tile = Vector2i(-1, -1)
	tile_deselected.emit()

func tile_has_building(x: int, y: int) -> bool:
	for b: Dictionary in buildings:
		if b["x"] == x and b["y"] == y:
			return true
	return false

func get_building_at(x: int, y: int) -> Dictionary:
	for b: Dictionary in buildings:
		if b["x"] == x and b["y"] == y:
			return b
	return {}

func is_valid_tile(x: int, y: int) -> bool:
	return x >= 0 and x < GameData.MAP_W and y >= 0 and y < GameData.MAP_H
