class_name RiverGenerator
extends RefCounted
## River generation — faithful port of the JS river code.
## Generates the Major River ("The Great Channel") and per-quadrant tributaries.

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

const DIRS8: Array[Vector2i] = [
	Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
	Vector2i(-1,0),                  Vector2i(1,0),
	Vector2i(-1,1),  Vector2i(0,1),  Vector2i(1,1)
]


func generate_major_river(seed_val: int) -> void:
	var major_river_noise: NoiseGen = NoiseGen.new(seed_val + 500)
	var W: int = GameData.MAP_W
	var H: int = GameData.MAP_H

	var start_x: int = int(floor(W * 0.25))
	var end_x: int = int(floor(W * 0.3))

	var path_points: Array[Dictionary] = []
	for row in range(H):
		var t: float = float(row) / float(H - 1)
		var base_x: float = float(start_x) + float(end_x - start_x) * t
		var meander: float = major_river_noise.fbm(row * 0.08, 0.5, 3) * 10.0
		var px: int = int(round(maxf(2.0, minf(float(W) / 2.0 - 3.0, base_x + meander))))
		path_points.append({ "x": px, "y": row })

	for pt: Dictionary in path_points:
		var px: int = pt["x"]
		var py: int = pt["y"]
		var width_noise: float = major_river_noise.get_value(px * 0.2, py * 0.2)
		var hw: int = 1 if width_noise > 0 else 0

		for dx in range(-hw, hw + 2):
			var nx: int = px + dx
			if nx < 0 or nx >= W:
				continue
			var current_terrain: int = GameState.terrain[py][nx]
			if current_terrain == GameData.T_MOUNTAINS or current_terrain == GameData.T_SNOW or current_terrain == GameData.T_VOLCANIC:
				continue

			GameState.terrain[py][nx] = GameData.T_MAJOR_RIVER
			GameState.major_river_tiles["%d,%d" % [nx, py]] = true


func carve_river(sx: int, sy: int) -> void:
	var cx: int = sx
	var cy: int = sy
	var visited: Dictionary = {}

	for _step in range(160):
		var key: String = "%d,%d" % [cx, cy]
		if visited.has(key):
			break
		visited[key] = true

		var ct: int = GameState.terrain[cy][cx]
		if ct == GameData.T_DEEP_WATER or ct == GameData.T_COAST:
			break
		if ct == GameData.T_MAJOR_RIVER:
			break
		if ct != GameData.T_MOUNTAINS and ct != GameData.T_SNOW and ct != GameData.T_VOLCANIC:
			GameState.terrain[cy][cx] = GameData.T_RIVER

		var best_e: float = GameState.elevation[cy][cx]
		var best_x: int = cx
		var best_y: int = cy

		# Shuffle directions with seeded randomness
		var dirs_copy: Array[Vector2i] = DIRS8.duplicate()
		for i in range(dirs_copy.size() - 1, 0, -1):
			var j: int = int(rng() * (i + 1))
			if j > i:
				j = i
			var tmp: Vector2i = dirs_copy[i]
			dirs_copy[i] = dirs_copy[j]
			dirs_copy[j] = tmp

		for d: Vector2i in dirs_copy:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx >= 0 and nx < GameData.MAP_W and ny >= 0 and ny < GameData.MAP_H:
				var ne: float = GameState.elevation[ny][nx] + (rng() * 0.03 - 0.015)
				if ne < best_e:
					best_e = ne
					best_x = nx
					best_y = ny

		if best_x == cx and best_y == cy:
			# Stuck — try any unvisited neighbor
			for d: Vector2i in dirs_copy:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if nx >= 0 and nx < GameData.MAP_W and ny >= 0 and ny < GameData.MAP_H:
					if not visited.has("%d,%d" % [nx, ny]):
						best_x = nx
						best_y = ny
						break
			if best_x == cx and best_y == cy:
				break

		cx = best_x
		cy = best_y


func generate_tributary_rivers(quadrants: Array[Dictionary]) -> void:
	for q: Dictionary in quadrants:
		var rivers_per_quad: int
		var min_elevation: float = 0.5

		if q["name"] == "NE":
			rivers_per_quad = 1
		elif q["name"] == "SW":
			rivers_per_quad = 3 + int(floor(rng() * 2))
			min_elevation = 0.35
		else:
			rivers_per_quad = 1 + int(floor(rng() * 2))

		for _r in range(rivers_per_quad):
			var sx: int = 0
			var sy: int = 0
			var attempts: int = 0
			while attempts < 500:
				sx = q["x0"] + int(rng() * (q["x1"] - q["x0"]))
				sy = q["y0"] + int(rng() * (q["y1"] - q["y0"]))
				if GameState.elevation[sy][sx] >= min_elevation:
					break
				attempts += 1
			if attempts < 500:
				carve_river(sx, sy)
