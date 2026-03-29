class_name TerrainRules
extends RefCounted
## Post-generation terrain rules: deposits, energy potentials, quadrant validation.

var rng_state: int

func rng() -> float:
	rng_state = (rng_state + 0x6D2B79F5) & 0xFFFFFFFF
	var t: int = rng_state
	var t_u: int = t if t >= 0 else t + 0x100000000
	t = ((t ^ _ushr(t_u, 15)) * (1 | t)) & 0xFFFFFFFF
	var t2: int = t if t >= 0 else t + 0x100000000
	t = ((t + (((t ^ _ushr(t2, 7)) * (61 | t)) & 0xFFFFFFFF)) ^ t) & 0xFFFFFFFF
	var t3: int = t if t >= 0 else t + 0x100000000
	var result: int = (t ^ _ushr(t3, 14)) & 0x7FFFFFFF
	return float(result) / 2147483648.0

static func _ushr(val: int, bits: int) -> int:
	if val >= 0:
		return val >> bits
	return ((val + 0x100000000) >> bits) & 0xFFFFFFFF

func rng_range(lo: int, hi: int) -> int:
	return int(round(float(lo) + rng() * float(hi - lo)))


# ── Deposit Placement ─────────────────────────────────────────
func place_deposits() -> void:
	for y in range(GameData.MAP_H):
		for x in range(GameData.MAP_W):
			var t: int = GameState.terrain[y][x]
			if t == GameData.T_HILLS or t == GameData.T_MOUNTAINS:
				if rng() < 0.1:
					GameState.deposits[y][x] = "coal"
				elif rng() < 0.06:
					GameState.deposits[y][x] = "iron"
				elif rng() < 0.03:
					GameState.deposits[y][x] = "uranium"
			if t == GameData.T_PLAINS or t == GameData.T_DESERT:
				if rng() < 0.05:
					GameState.deposits[y][x] = "gas"
			if t == GameData.T_VOLCANIC and rng() < 0.15:
				GameState.deposits[y][x] = "uranium"


# ── Quadrant Deposit Validation ───────────────────────────────
func validate_quadrant_deposits(quadrants: Array[Dictionary]) -> void:
	var min_reqs: Dictionary = { "coal": 2, "gas": 2, "uranium": 1, "iron": 1 }

	for q: Dictionary in quadrants:
		var dep_counts: Dictionary = { "coal": 0, "gas": 0, "uranium": 0, "iron": 0 }
		for y in range(q["y0"], q["y1"]):
			for x in range(q["x0"], q["x1"]):
				var d: String = GameState.deposits[y][x]
				if dep_counts.has(d):
					dep_counts[d] += 1

		for key: String in min_reqs:
			var deficit: int = min_reqs[key] - dep_counts[key]
			if deficit > 0:
				var valid_tiles: Array[int]
				if key == "coal" or key == "iron":
					valid_tiles = [GameData.T_HILLS, GameData.T_MOUNTAINS, GameData.T_PLAINS]
				elif key == "gas":
					valid_tiles = [GameData.T_PLAINS, GameData.T_DESERT, GameData.T_HILLS]
				else:  # uranium
					valid_tiles = [GameData.T_HILLS, GameData.T_MOUNTAINS, GameData.T_VOLCANIC, GameData.T_DESERT]
				_find_and_place(q, key, valid_tiles, deficit)


func _find_and_place(q: Dictionary, deposit_type: String, valid_terrains: Array[int], count: int) -> void:
	var placed: int = 0
	for _attempt in range(2000):
		if placed >= count:
			break
		var x: int = q["x0"] + int(rng() * (q["x1"] - q["x0"]))
		var y: int = q["y0"] + int(rng() * (q["y1"] - q["y0"]))
		if x >= q["x1"]:
			x = q["x1"] - 1
		if y >= q["y1"]:
			y = q["y1"] - 1
		if GameState.terrain[y][x] in valid_terrains and GameState.deposits[y][x] == "":
			GameState.deposits[y][x] = deposit_type
			placed += 1


# ── Energy Potential Calculation ──────────────────────────────
func calculate_energy_potentials() -> void:
	# Build river and volcanic tile sets for proximity checks
	var all_river_tiles: Dictionary = {}
	var all_volcanic_tiles: Dictionary = {}

	for y in range(GameData.MAP_H):
		for x in range(GameData.MAP_W):
			var t: int = GameState.terrain[y][x]
			if t == GameData.T_RIVER or t == GameData.T_MAJOR_RIVER:
				all_river_tiles["%d,%d" % [x, y]] = true
			if t == GameData.T_VOLCANIC:
				all_volcanic_tiles["%d,%d" % [x, y]] = true

	for y in range(GameData.MAP_H):
		for x in range(GameData.MAP_W):
			var t: int = GameState.terrain[y][x]
			var is_major_river: bool = t == GameData.T_MAJOR_RIVER
			var is_river: bool = t == GameData.T_RIVER
			var dist_river: int = _dist_to_nearest_in_set(x, y, all_river_tiles, 3)
			var dist_volcanic: int = _dist_to_nearest_in_set(x, y, all_volcanic_tiles, 3)
			var is_near_river: bool = dist_river <= 2

			# Solar
			var solar: int = 0
			if t == GameData.T_DESERT:
				solar = rng_range(80, 100)
			elif t == GameData.T_PLAINS:
				solar = rng_range(40, 60)
			elif t == GameData.T_HILLS:
				solar = rng_range(35, 55)
			elif t == GameData.T_FOREST:
				solar = rng_range(15, 30)
			elif t == GameData.T_MOUNTAINS or t == GameData.T_SNOW:
				solar = rng_range(20, 40)
			elif is_river or is_major_river or t == GameData.T_COAST or t == GameData.T_DEEP_WATER:
				solar = rng_range(30, 50)
			elif t == GameData.T_VOLCANIC:
				solar = rng_range(25, 45)
			if t == GameData.T_SNOW:
				solar = rng_range(30, 50)

			# Wind
			var wind: int = 0
			if t == GameData.T_HILLS:
				wind = rng_range(60, 85)
			elif t == GameData.T_MOUNTAINS or t == GameData.T_SNOW:
				wind = rng_range(70, 90)
			elif t == GameData.T_COAST:
				wind = rng_range(55, 75)
			elif t == GameData.T_PLAINS:
				wind = rng_range(30, 50)
			elif t == GameData.T_DESERT:
				wind = rng_range(40, 60)
			elif t == GameData.T_FOREST:
				wind = rng_range(10, 25)
			elif is_river or is_major_river:
				wind = rng_range(25, 40)
			elif t == GameData.T_VOLCANIC:
				wind = rng_range(40, 60)
			elif t == GameData.T_DEEP_WATER:
				wind = rng_range(40, 60)

			# Hydro
			var hydro: int = 0
			if is_major_river:
				hydro = rng_range(85, 100)
			elif is_river:
				hydro = rng_range(65, 85)
			elif t == GameData.T_COAST and dist_river <= 1:
				hydro = rng_range(30, 50)
			elif is_near_river:
				hydro = rng_range(20, 40)
			elif t == GameData.T_DESERT:
				hydro = 0
			elif t == GameData.T_MOUNTAINS or t == GameData.T_HILLS:
				hydro = rng_range(0, 5)
			else:
				hydro = rng_range(0, 5)

			# Geothermal
			var geothermal: int = 0
			if t == GameData.T_VOLCANIC:
				geothermal = rng_range(75, 100)
			elif dist_volcanic <= 2:
				geothermal = rng_range(20, 40)
			elif t == GameData.T_MOUNTAINS:
				geothermal = rng_range(5, 15)
			else:
				geothermal = 0

			GameState.resource_data[y][x] = {
				"solar": solar, "wind": wind, "hydro": hydro, "geothermal": geothermal
			}


func _dist_to_nearest_in_set(x: int, y: int, tile_set: Dictionary, max_range: int) -> int:
	for r in range(max_range + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue  # only check perimeter
				if tile_set.has("%d,%d" % [x + dx, y + dy]):
					return r
	return max_range + 1
