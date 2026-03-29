class_name CivManager
extends RefCounted
## Civilization initialization: starting position selection and building placement.
## Faithful port of the JS findStartingPosition() and placeStartingBuildings().


func init_civilizations() -> void:
	for civ: Dictionary in GameState.civs:
		var pos: Vector2i = _find_starting_position(civ["quadrant"])
		if pos.x >= 0 and pos.y >= 0:
			_place_starting_buildings(civ["id"], pos.x, pos.y)


func _find_starting_position(quadrant: String) -> Vector2i:
	var bounds: Dictionary = GameData.get_quadrant_bounds(quadrant)
	var best_score: float = -INF
	var best_x: int = -1
	var best_y: int = -1

	for y in range(bounds["y0"], bounds["y1"]):
		for x in range(bounds["x0"], bounds["x1"]):
			if not GameData.is_buildable_terrain(GameState.terrain[y][x]):
				continue

			# Count adjacent buildable tiles (radius 2)
			var adj_buildable: int = 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if GameState.is_valid_tile(nx, ny) and GameData.is_buildable_terrain(GameState.terrain[ny][nx]):
						adj_buildable += 1

			if adj_buildable < 5:
				continue

			var river_dist: int = _dist_to_nearest_river(x, y)
			var res: Dictionary = GameState.resource_data[y][x]

			var score: float = 0.0
			# River proximity
			if river_dist <= 5:
				score += (6 - river_dist) * 10.0
			else:
				score -= river_dist * 2.0

			# Solar/wind potential
			score += res["solar"] * 0.3 + res["wind"] * 0.2

			# Adjacent buildable count
			score += adj_buildable * 3.0

			# Distance to quadrant center
			var qcx: float = (bounds["x0"] + bounds["x1"]) / 2.0
			var qcy: float = (bounds["y0"] + bounds["y1"]) / 2.0
			var dist_to_center: float = abs(x - qcx) + abs(y - qcy)
			score -= dist_to_center * 0.5

			if score > best_score:
				best_score = score
				best_x = x
				best_y = y

	return Vector2i(best_x, best_y)


func _dist_to_nearest_river(x: int, y: int) -> int:
	var min_dist: int = 999999
	var search_range: int = 8
	for dy in range(-search_range, search_range + 1):
		for dx in range(-search_range, search_range + 1):
			var nx: int = x + dx
			var ny: int = y + dy
			if GameState.is_valid_tile(nx, ny):
				var t: int = GameState.terrain[ny][nx]
				if t == GameData.T_RIVER or t == GameData.T_MAJOR_RIVER:
					var d: int = abs(dx) + abs(dy)
					if d < min_dist:
						min_dist = d
	return min_dist


func _place_starting_buildings(civ_id: int, cx: int, cy: int) -> void:
	var civ: Dictionary = GameState.civs[civ_id]
	var quad: String = civ["quadrant"]

	# Place citadel
	GameState.buildings.append({
		"type": "citadel", "owner": civ_id,
		"x": cx, "y": cy, "active": true
	})

	# Base buildings
	var needed: Array[String] = ["house", "house", "farm", "home_miner"]

	# Quadrant-specific buildings
	match quad:
		"NE":
			needed.append("solar_panel")
			needed.append("solar_panel")
		"SW":
			needed.append("solar_panel")
		"SE":
			needed.append("solar_panel")
		"NW":
			needed.append("solar_panel")

	# Spiral offsets from citadel
	var offsets: Array[Vector2i] = [
		Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
		Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1),
		Vector2i(2,0), Vector2i(-2,0), Vector2i(0,2), Vector2i(0,-2),
		Vector2i(2,1), Vector2i(2,-1), Vector2i(-2,1), Vector2i(-2,-1),
		Vector2i(1,2), Vector2i(-1,2), Vector2i(1,-2), Vector2i(-1,-2),
		Vector2i(3,0), Vector2i(-3,0), Vector2i(0,3), Vector2i(0,-3),
	]

	var placed: int = 0
	for off: Vector2i in offsets:
		if placed >= needed.size():
			break
		var nx: int = cx + off.x
		var ny: int = cy + off.y
		if GameState.is_valid_tile(nx, ny) and GameData.is_buildable_terrain(GameState.terrain[ny][nx]) and not GameState.tile_has_building(nx, ny):
			GameState.buildings.append({
				"type": needed[placed], "owner": civ_id,
				"x": nx, "y": ny, "active": true
			})
			placed += 1

	# Special quadrant buildings on appropriate terrain
	if quad == "SW":
		var river_tile: Dictionary = _find_nearest_tile_of_type(cx, cy, GameData.T_RIVER, 12)
		if not river_tile.is_empty():
			GameState.buildings.append({
				"type": "hydro_dam", "owner": civ_id,
				"x": river_tile["x"], "y": river_tile["y"], "active": true
			})
	elif quad == "SE":
		var hill_tile: Dictionary = _find_nearest_tile_of_type(cx, cy, GameData.T_HILLS, 12)
		if not hill_tile.is_empty():
			GameState.buildings.append({
				"type": "wind_turbine", "owner": civ_id,
				"x": hill_tile["x"], "y": hill_tile["y"], "active": true
			})


func _find_nearest_tile_of_type(cx: int, cy: int, terrain_id: int, search_range: int) -> Dictionary:
	var best_dist: int = 999999
	var best_x: int = -1
	var best_y: int = -1
	for dy in range(-search_range, search_range + 1):
		for dx in range(-search_range, search_range + 1):
			var nx: int = cx + dx
			var ny: int = cy + dy
			if GameState.is_valid_tile(nx, ny):
				var t: int = GameState.terrain[ny][nx]
				if (t == terrain_id or (terrain_id == GameData.T_RIVER and t == GameData.T_MAJOR_RIVER)) and not GameState.tile_has_building(nx, ny):
					var d: int = abs(dx) + abs(dy)
					if d < best_dist:
						best_dist = d
						best_x = nx
						best_y = ny
	if best_x >= 0:
		return { "x": best_x, "y": best_y }
	return {}
