class_name MapGenerator
extends RefCounted
## Procedural map generation — faithful port of the JS generateMap() function.
## Produces terrain, elevation, moisture, heat layers, then applies
## quadrant distribution enforcement, clustering, mountain consolidation,
## hole filling, volcanic adjacency rules, rivers, deposits, and energy potentials.

var rng_state: int
var _seed: int

# ── Seeded PRNG (mulberry32) ──────────────────────────────────
func _init_rng(seed_val: int) -> void:
	rng_state = seed_val
	_seed = seed_val

func rng() -> float:
	rng_state = (rng_state + 0x6D2B79F5) & 0xFFFFFFFF
	# Emulate unsigned 32-bit right shifts (JS >>> operator)
	var t: int = rng_state
	var t_unsigned: int = t if t >= 0 else t + 0x100000000
	t = ((t ^ _ushr(t_unsigned, 15)) * (1 | t)) & 0xFFFFFFFF
	var t2: int = t if t >= 0 else t + 0x100000000
	t = ((t + (((t ^ _ushr(t2, 7)) * (61 | t)) & 0xFFFFFFFF)) ^ t) & 0xFFFFFFFF
	var t3: int = t if t >= 0 else t + 0x100000000
	var result: int = (t ^ _ushr(t3, 14)) & 0x7FFFFFFF
	return float(result) / 2147483648.0

static func _ushr(val: int, bits: int) -> int:
	## Unsigned right shift for 32-bit values
	if val >= 0:
		return val >> bits
	return ((val + 0x100000000) >> bits) & 0xFFFFFFFF

func rng_range(lo: int, hi: int) -> int:
	return int(round(float(lo) + rng() * float(hi - lo)))

# ── Direction constants ───────────────────────────────────────
const DIRS4: Array[Vector2i] = [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]
const DIRS8: Array[Vector2i] = [
	Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
	Vector2i(-1,0),                  Vector2i(1,0),
	Vector2i(-1,1),  Vector2i(0,1),  Vector2i(1,1)
]

# ── Main generation entry point ───────────────────────────────
func generate(seed_val: int) -> void:
	_init_rng(seed_val)

	var noise1: NoiseGen = NoiseGen.new(seed_val)
	var noise2: NoiseGen = NoiseGen.new(seed_val + 100)
	var noise_heat: NoiseGen = NoiseGen.new(seed_val + 200)

	var W: int = GameData.MAP_W
	var H: int = GameData.MAP_H

	GameState.init_map_arrays()

	# ── Pass 1: Generate elevation, moisture, heat, initial terrain ──
	for y in range(H):
		for x in range(W):
			var dx: float = (float(x) - float(W) / 2.0) / (float(W) / 2.0)
			var dy: float = (float(y) - float(H) / 2.0) / (float(H) / 2.0)
			var dist: float = sqrt(dx * dx + dy * dy)
			var falloff: float = 1.0 - pow(minf(dist * 0.8, 1.0), 2.5)

			var e: float = noise1.fbm(x * 0.06, y * 0.06, 5) * 0.5 + 0.5
			e = e * falloff

			var m: float = noise2.fbm(x * 0.08, y * 0.08, 4) * 0.5 + 0.5
			var h: float = noise_heat.fbm(x * 0.05, y * 0.05, 3) * 0.5 + 0.5

			# Quadrant biome biases
			var quad: String = GameData.get_quadrant_name(x, y)
			if quad == "NE":
				h = minf(1.0, h + 0.25)
				m = maxf(0.0, m - 0.25)
			elif quad == "SW":
				m = minf(1.0, m + 0.2)
			elif quad == "SE":
				if e > 0.22:
					e = minf(1.0, e + 0.12)

			GameState.elevation[y][x] = e
			GameState.moisture[y][x] = m
			GameState.heat[y][x] = h

			# Terrain classification
			var t: int
			if e < 0.18:
				t = GameData.T_DEEP_WATER
			elif e < 0.28:
				t = GameData.T_COAST
			elif e < 0.55:
				if h > 0.65 and m < 0.35:
					t = GameData.T_DESERT
				elif m > 0.55:
					t = GameData.T_FOREST
				else:
					t = GameData.T_PLAINS
			elif e < 0.7:
				t = GameData.T_HILLS
			elif e < 0.85:
				t = GameData.T_MOUNTAINS
			else:
				t = GameData.T_SNOW

			GameState.terrain[y][x] = t

	# ── Pass 2: Volcanic conversion ──
	for y in range(H):
		for x in range(W):
			if GameState.terrain[y][x] == GameData.T_MOUNTAINS:
				var v_quad: String = GameData.get_quadrant_name(x, y)
				var volcanic_chance: float = 0.10 if v_quad == "SE" else 0.12
				if rng() < volcanic_chance:
					GameState.terrain[y][x] = GameData.T_VOLCANIC

	# ── Pass 3: Quadrant terrain distribution enforcement ──
	var quadrants: Array[Dictionary] = GameData.get_quadrant_full_bounds()
	for q: Dictionary in quadrants:
		_enforce_quadrant_distribution(q)

	# ── Pass 4: Hard rules — desert only NE, volcanic only SE ──
	var half_w: int = W / 2
	var half_h: int = H / 2
	for y in range(H):
		for x in range(W):
			var in_ne: bool = x >= half_w and y < half_h
			var in_se: bool = x >= half_w and y >= half_h
			if GameState.terrain[y][x] == GameData.T_DESERT and not in_ne:
				GameState.terrain[y][x] = GameData.T_PLAINS
			if GameState.terrain[y][x] == GameData.T_VOLCANIC and not in_se:
				GameState.terrain[y][x] = GameData.T_MOUNTAINS

	# ── Pass 5: Terrain clustering ──
	_cluster_terrain(quadrants)

	# ── Pass 6: Mountain range consolidation ──
	_consolidate_mountains(quadrants)

	# ── Pass 7: Mountain hole filling ──
	_fill_mountain_holes()

	# ── Pass 8: Volcanic adjacency rule ──
	_enforce_volcanic_adjacency()

	# ── Pass 9: Rivers (via RiverGenerator) ──
	var river_gen: RiverGenerator = RiverGenerator.new()
	river_gen.rng_state = rng_state  # share RNG state
	river_gen.generate_major_river(seed_val)
	river_gen.generate_tributary_rivers(quadrants)
	rng_state = river_gen.rng_state  # restore RNG state

	# ── Pass 10: Deposits ──
	var terrain_rules: TerrainRules = TerrainRules.new()
	terrain_rules.rng_state = rng_state
	terrain_rules.place_deposits()
	terrain_rules.validate_quadrant_deposits(quadrants)
	rng_state = terrain_rules.rng_state

	# ── Pass 11: Guarantee rivers per quadrant ──
	for q: Dictionary in quadrants:
		var river_count: int = 0
		for y in range(q["y0"], q["y1"]):
			for x in range(q["x0"], q["x1"]):
				if GameState.terrain[y][x] == GameData.T_RIVER or GameState.terrain[y][x] == GameData.T_MAJOR_RIVER:
					river_count += 1
		if river_count == 0:
			var sx: int = 0
			var sy: int = 0
			var att: int = 0
			while att < 500:
				sx = q["x0"] + int(rng() * (q["x1"] - q["x0"]))
				sy = q["y0"] + int(rng() * (q["y1"] - q["y0"]))
				if GameState.elevation[sy][sx] >= 0.35:
					break
				att += 1
			if att < 500:
				river_gen.rng_state = rng_state
				river_gen.carve_river(sx, sy)
				rng_state = river_gen.rng_state

	# ── Pass 12: Water/mountain overflow protection ──
	for q: Dictionary in quadrants:
		var water_mountain: int = 0
		var total: int = 0
		for y in range(q["y0"], q["y1"]):
			for x in range(q["x0"], q["x1"]):
				total += 1
				var t: int = GameState.terrain[y][x]
				if t == GameData.T_DEEP_WATER or t == GameData.T_COAST or t == GameData.T_MOUNTAINS or t == GameData.T_SNOW:
					water_mountain += 1
		if float(water_mountain) / float(total) > 0.7:
			for y in range(q["y0"], q["y1"]):
				for x in range(q["x0"], q["x1"]):
					var t: int = GameState.terrain[y][x]
					if (t == GameData.T_MOUNTAINS or t == GameData.T_SNOW) and rng() < 0.4:
						GameState.terrain[y][x] = GameData.T_HILLS if rng() < 0.5 else GameData.T_FOREST
					elif t == GameData.T_DEEP_WATER and GameState.elevation[y][x] > 0.12 and rng() < 0.3:
						GameState.terrain[y][x] = GameData.T_PLAINS

	# ── Pass 13: Energy potentials ──
	terrain_rules.rng_state = rng_state
	terrain_rules.calculate_energy_potentials()
	rng_state = terrain_rules.rng_state

	GameState.map_generated.emit()


# ── Quadrant distribution enforcement ─────────────────────────
func _enforce_quadrant_distribution(q: Dictionary) -> void:
	var targets: Dictionary = GameData.QUAD_TARGETS.get(q["name"], {})
	if targets.is_empty():
		return

	var W: int = GameData.MAP_W
	var EDGE_PROTECT: int = 8

	# Collect land tiles
	var land_tiles: Array[Vector2i] = []
	for y in range(q["y0"], q["y1"]):
		for x in range(q["x0"], q["x1"]):
			var t: int = GameState.terrain[y][x]
			if t == GameData.T_DEEP_WATER or t == GameData.T_COAST:
				continue
			if t == GameData.T_RIVER or t == GameData.T_MAJOR_RIVER:
				continue
			land_tiles.append(Vector2i(x, y))

	var total_land: int = land_tiles.size()
	if total_land == 0:
		return

	# Count land terrain (snow counts as mountains)
	var _count_land_terrain := func() -> Dictionary:
		var counts: Dictionary = {}
		for tile: Vector2i in land_tiles:
			var t: int = GameState.terrain[tile.y][tile.x]
			if t == GameData.T_SNOW:
				counts[GameData.T_MOUNTAINS] = counts.get(GameData.T_MOUNTAINS, 0) + 1
			else:
				counts[t] = counts.get(t, 0) + 1
		return counts

	# 5-pass convergence
	for _pass in range(5):
		var counts: Dictionary = _count_land_terrain.call()

		for target_key: int in targets:
			var bounds: Array = targets[target_key]
			var min_pct: int = bounds[0]
			var max_pct: int = bounds[1]
			var current_count: int = counts.get(target_key, 0)
			var min_count: int = int(floor(float(total_land) * float(min_pct) / 100.0))
			var max_count: int = int(ceil(float(total_land) * float(max_pct) / 100.0))

			if current_count < min_count:
				# Need more — find most over-represented type to convert from
				var most_over_key: int = -1
				var most_over_amount: int = 0
				for o_key: int in targets:
					if o_key == target_key:
						continue
					var o_bounds: Array = targets[o_key]
					var o_max_count: int = int(ceil(float(total_land) * float(o_bounds[1]) / 100.0))
					var o_count: int = counts.get(o_key, 0)
					var over_amount: int = o_count - o_max_count
					if over_amount > most_over_amount:
						most_over_amount = over_amount
						most_over_key = o_key

				# Fallback: most abundant
				if most_over_key == -1:
					var max_c: int = 0
					for o_key: int in targets:
						if o_key == target_key:
							continue
						var o_count: int = counts.get(o_key, 0)
						if o_count > max_c:
							max_c = o_count
							most_over_key = o_key

				if most_over_key == -1:
					continue

				var source_id: int = most_over_key
				var needed: int = min_count - current_count

				var candidates: Array[Vector2i] = []
				for tile: Vector2i in land_tiles:
					var t: int = GameState.terrain[tile.y][tile.x]
					if t == source_id or (source_id == GameData.T_MOUNTAINS and t == GameData.T_SNOW):
						candidates.append(tile)

				# Shuffle candidates
				for i in range(candidates.size() - 1, 0, -1):
					var j: int = int(rng() * (i + 1))
					if j > i:
						j = i
					var tmp: Vector2i = candidates[i]
					candidates[i] = candidates[j]
					candidates[j] = tmp

				var to_convert: int = mini(needed, candidates.size())
				for i in range(to_convert):
					var tile: Vector2i = candidates[i]
					GameState.terrain[tile.y][tile.x] = target_key

			elif current_count > max_count:
				var excess: int = current_count - max_count
				var candidates: Array[Vector2i] = []
				for tile: Vector2i in land_tiles:
					var t: int = GameState.terrain[tile.y][tile.x]
					if t == target_key or (target_key == GameData.T_MOUNTAINS and t == GameData.T_SNOW):
						candidates.append(tile)

				for i in range(candidates.size() - 1, 0, -1):
					var j: int = int(rng() * (i + 1))
					if j > i:
						j = i
					var tmp: Vector2i = candidates[i]
					candidates[i] = candidates[j]
					candidates[j] = tmp

				# Find most under-represented type
				var best_under_key: int = -1
				var best_under_amount: int = 999999
				for o_key: int in targets:
					if o_key == target_key:
						continue
					var o_bounds: Array = targets[o_key]
					var o_min_count: int = int(floor(float(total_land) * float(o_bounds[0]) / 100.0))
					var o_count: int = counts.get(o_key, 0)
					if o_count < o_min_count and o_count < best_under_amount:
						best_under_amount = o_count
						best_under_key = o_key

				# Fallback: first key in targets
				if best_under_key == -1 or best_under_key == target_key:
					for k: int in targets:
						if k != target_key:
							best_under_key = k
							break

				if best_under_key == -1:
					continue

				var dest_id: int = best_under_key
				var to_convert: int = mini(excess, candidates.size())
				for i in range(to_convert):
					var tile: Vector2i = candidates[i]
					GameState.terrain[tile.y][tile.x] = dest_id


# ── Terrain clustering ────────────────────────────────────────
func _cluster_terrain(quadrants: Array[Dictionary]) -> void:
	var CLUSTER_ORDER: Array[int] = [
		GameData.T_MOUNTAINS, GameData.T_VOLCANIC, GameData.T_DESERT,
		GameData.T_FOREST, GameData.T_HILLS
	]
	var PROTECTED: Array[int] = [
		GameData.T_DEEP_WATER, GameData.T_COAST,
		GameData.T_RIVER, GameData.T_MAJOR_RIVER
	]

	for q: Dictionary in quadrants:
		for target_id: int in CLUSTER_ORDER:
			var match_ids: Array[int]
			if target_id == GameData.T_MOUNTAINS:
				match_ids = [GameData.T_MOUNTAINS, GameData.T_SNOW]
			else:
				match_ids = [target_id]

			var components: Array = _find_components(match_ids, q)
			if components.size() <= 1:
				continue

			# Find largest component
			var main_comp: Array = components[0]
			for c: Array in components:
				if c.size() > main_comp.size():
					main_comp = c

			var cluster_set: Dictionary = {}
			for tile: Vector2i in main_comp:
				cluster_set[tile.y * GameData.MAP_W + tile.x] = true

			# Collect scattered tiles
			var scattered: Array[Vector2i] = []
			for comp: Array in components:
				for tile: Vector2i in comp:
					var key: int = tile.y * GameData.MAP_W + tile.x
					if not cluster_set.has(key):
						scattered.append(tile)

			if scattered.is_empty():
				continue

			# Sort by distance to cluster centroid
			var cent_x: float = 0.0
			var cent_y: float = 0.0
			for tile: Vector2i in main_comp:
				cent_x += tile.x
				cent_y += tile.y
			cent_x /= main_comp.size()
			cent_y /= main_comp.size()

			scattered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var da: float = (a.x - cent_x) * (a.x - cent_x) + (a.y - cent_y) * (a.y - cent_y)
				var db: float = (b.x - cent_x) * (b.x - cent_x) + (b.y - cent_y) * (b.y - cent_y)
				return da < db
			)

			var avoid_river: bool = target_id == GameData.T_DESERT

			for tile: Vector2i in scattered:
				var frontier: Array = _get_growth_frontier(cluster_set, q, avoid_river)
				if frontier.is_empty():
					break

				# Score frontier tiles
				var best_f: Dictionary = frontier[0]
				var best_score: float = -INF
				for f: Dictionary in frontier:
					var s: float = _growth_score(f["x"], f["y"], target_id, cluster_set)
					if s > best_score:
						best_score = s
						best_f = f

				# Swap
				var old_terrain: int = GameState.terrain[tile.y][tile.x]
				GameState.terrain[tile.y][tile.x] = GameData.T_PLAINS
				GameState.terrain[best_f["y"]][best_f["x"]] = old_terrain
				cluster_set[best_f["key"]] = true


func _find_components(match_ids: Array[int], q: Dictionary) -> Array:
	var match_set: Dictionary = {}
	for mid: int in match_ids:
		match_set[mid] = true

	var visited: Dictionary = {}
	var components: Array = []

	for y in range(q["y0"], q["y1"]):
		for x in range(q["x0"], q["x1"]):
			var key: int = y * GameData.MAP_W + x
			if visited.has(key):
				continue
			if not match_set.has(GameState.terrain[y][x]):
				continue

			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			while not stack.is_empty():
				var cur: Vector2i = stack.pop_back()
				var ck: int = cur.y * GameData.MAP_W + cur.x
				if visited.has(ck):
					continue
				if cur.x < q["x0"] or cur.x >= q["x1"] or cur.y < q["y0"] or cur.y >= q["y1"]:
					continue
				if not match_set.has(GameState.terrain[cur.y][cur.x]):
					continue
				visited[ck] = true
				comp.append(cur)
				for d: Vector2i in DIRS4:
					var nx: int = cur.x + d.x
					var ny: int = cur.y + d.y
					if nx >= 0 and nx < GameData.MAP_W and ny >= 0 and ny < GameData.MAP_H:
						stack.append(Vector2i(nx, ny))
			if not comp.is_empty():
				components.append(comp)

	return components


func _get_growth_frontier(cluster_set: Dictionary, q: Dictionary, avoid_river_adjacent: bool) -> Array:
	var frontier: Array = []
	var seen: Dictionary = {}

	for key: int in cluster_set:
		var cx: int = key % GameData.MAP_W
		var cy: int = (key - cx) / GameData.MAP_W
		for d: Vector2i in DIRS4:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or nx >= GameData.MAP_W or ny < 0 or ny >= GameData.MAP_H:
				continue
			if nx < q["x0"] or nx >= q["x1"] or ny < q["y0"] or ny >= q["y1"]:
				continue
			var nkey: int = ny * GameData.MAP_W + nx
			if cluster_set.has(nkey):
				continue
			if seen.has(nkey):
				continue
			seen[nkey] = true
			var t: int = GameState.terrain[ny][nx]
			if t != GameData.T_PLAINS:
				continue

			if avoid_river_adjacent:
				var near_river: bool = false
				for rd: Vector2i in DIRS8:
					var rx: int = nx + rd.x
					var ry: int = ny + rd.y
					if rx >= 0 and rx < GameData.MAP_W and ry >= 0 and ry < GameData.MAP_H:
						var rt: int = GameState.terrain[ry][rx]
						if rt == GameData.T_RIVER or rt == GameData.T_MAJOR_RIVER:
							near_river = true
							break
				if near_river:
					continue

			frontier.append({ "x": nx, "y": ny, "key": nkey })

	return frontier


func _growth_score(fx: int, fy: int, target_terrain_id: int, cluster_set: Dictionary) -> float:
	var score: float = 0.0

	# Prefer tiles with more cluster neighbors
	for d: Vector2i in DIRS8:
		var nx: int = fx + d.x
		var ny: int = fy + d.y
		if nx >= 0 and nx < GameData.MAP_W and ny >= 0 and ny < GameData.MAP_H:
			if cluster_set.has(ny * GameData.MAP_W + nx):
				score += 2.0

	score += rng() * 1.5

	# Terrain affinity
	if target_terrain_id == GameData.T_MOUNTAINS:
		score += GameState.elevation[fy][fx] * 3.0
	elif target_terrain_id == GameData.T_DESERT:
		score += GameState.heat[fy][fx] * 2.0
		score += (1.0 - GameState.moisture[fy][fx]) * 2.0
	elif target_terrain_id == GameData.T_FOREST:
		score += GameState.moisture[fy][fx] * 2.0
	elif target_terrain_id == GameData.T_HILLS:
		score += GameState.elevation[fy][fx] * 2.0
		for d: Vector2i in DIRS8:
			var nx: int = fx + d.x
			var ny: int = fy + d.y
			if nx >= 0 and nx < GameData.MAP_W and ny >= 0 and ny < GameData.MAP_H:
				var nt: int = GameState.terrain[ny][nx]
				if nt == GameData.T_MOUNTAINS or nt == GameData.T_SNOW:
					score += 3.0
	elif target_terrain_id == GameData.T_VOLCANIC:
		for d: Vector2i in DIRS8:
			var nx: int = fx + d.x
			var ny: int = fy + d.y
			if nx >= 0 and nx < GameData.MAP_W and ny >= 0 and ny < GameData.MAP_H:
				var nt: int = GameState.terrain[ny][nx]
				if nt == GameData.T_MOUNTAINS or nt == GameData.T_SNOW:
					score += 4.0

	return score


# ── Mountain consolidation ────────────────────────────────────
func _consolidate_mountains(quadrants: Array[Dictionary]) -> void:
	for q: Dictionary in quadrants:
		# Find all mountain/snow tiles
		var mtn_tiles: Array[Vector2i] = []
		for y in range(q["y0"], q["y1"]):
			for x in range(q["x0"], q["x1"]):
				var t: int = GameState.terrain[y][x]
				if t == GameData.T_MOUNTAINS or t == GameData.T_SNOW:
					mtn_tiles.append(Vector2i(x, y))

		if mtn_tiles.size() < 3:
			for tile: Vector2i in mtn_tiles:
				GameState.terrain[tile.y][tile.x] = GameData.T_HILLS
			continue

		# Flood fill components using 8-connectivity
		var visited: Dictionary = {}
		var components: Array = []
		for tile: Vector2i in mtn_tiles:
			var key: String = "%d,%d" % [tile.x, tile.y]
			if visited.has(key):
				continue
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [tile]
			while not stack.is_empty():
				var cur: Vector2i = stack.pop_back()
				var ck: String = "%d,%d" % [cur.x, cur.y]
				if visited.has(ck):
					continue
				visited[ck] = true
				comp.append(cur)
				for d: Vector2i in DIRS8:
					var nx: int = cur.x + d.x
					var ny: int = cur.y + d.y
					if nx >= q["x0"] and nx < q["x1"] and ny >= q["y0"] and ny < q["y1"]:
						var nk: String = "%d,%d" % [nx, ny]
						if not visited.has(nk):
							var nt: int = GameState.terrain[ny][nx]
							if nt == GameData.T_MOUNTAINS or nt == GameData.T_SNOW:
								stack.append(Vector2i(nx, ny))
			components.append(comp)

		# Sort by size descending — keep largest
		components.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
		var main_cluster: Array = components[0]
		var main_set: Dictionary = {}
		for tile: Vector2i in main_cluster:
			main_set["%d,%d" % [tile.x, tile.y]] = true

		# Merge smaller components into main cluster
		for i in range(1, components.size()):
			for tile: Vector2i in components[i]:
				# Find nearest frontier tile adjacent to main cluster
				var best_dist: int = 999999
				var best_tile: Dictionary = {}
				for mt: Vector2i in main_cluster:
					for d: Vector2i in DIRS8:
						var nx: int = mt.x + d.x
						var ny: int = mt.y + d.y
						var nk: String = "%d,%d" % [nx, ny]
						if nx >= q["x0"] and nx < q["x1"] and ny >= q["y0"] and ny < q["y1"] and not main_set.has(nk):
							var nt: int = GameState.terrain[ny][nx]
							if nt == GameData.T_PLAINS or nt == GameData.T_HILLS:
								var dist_val: int = abs(nx - tile.x) + abs(ny - tile.y)
								if dist_val < best_dist:
									best_dist = dist_val
									best_tile = { "x": nx, "y": ny, "key": nk }

				if not best_tile.is_empty():
					GameState.terrain[tile.y][tile.x] = GameData.T_HILLS
					GameState.terrain[best_tile["y"]][best_tile["x"]] = GameData.T_MOUNTAINS
					main_cluster.append(Vector2i(best_tile["x"], best_tile["y"]))
					main_set[best_tile["key"]] = true
				else:
					GameState.terrain[tile.y][tile.x] = GameData.T_HILLS


# ── Mountain hole filling ─────────────────────────────────────
func _fill_mountain_holes() -> void:
	var changed: bool = true
	var passes: int = 0
	while changed and passes < 10:
		changed = false
		passes += 1
		for y in range(1, GameData.MAP_H - 1):
			for x in range(1, GameData.MAP_W - 1):
				var t: int = GameState.terrain[y][x]
				if t == GameData.T_MOUNTAINS or t == GameData.T_SNOW or t == GameData.T_VOLCANIC:
					continue
				if t == GameData.T_DEEP_WATER or t == GameData.T_COAST or t == GameData.T_RIVER or t == GameData.T_MAJOR_RIVER:
					continue
				var mtn_neighbors: int = 0
				for d: Vector2i in DIRS8:
					var nt: int = GameState.terrain[y + d.y][x + d.x]
					if nt == GameData.T_MOUNTAINS or nt == GameData.T_SNOW or nt == GameData.T_VOLCANIC:
						mtn_neighbors += 1
				if mtn_neighbors >= 5:
					GameState.terrain[y][x] = GameData.T_MOUNTAINS
					changed = true


# ── Volcanic adjacency rule ──────────────────────────────────
func _enforce_volcanic_adjacency() -> void:
	for y in range(GameData.MAP_H):
		for x in range(GameData.MAP_W):
			if GameState.terrain[y][x] != GameData.T_VOLCANIC:
				continue
			var adjacent_to_mountain: bool = false
			for d: Vector2i in DIRS8:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and nx < GameData.MAP_W and ny >= 0 and ny < GameData.MAP_H:
					var nt: int = GameState.terrain[ny][nx]
					if nt == GameData.T_MOUNTAINS or nt == GameData.T_SNOW or nt == GameData.T_VOLCANIC:
						adjacent_to_mountain = true
						break
			if not adjacent_to_mountain:
				GameState.terrain[y][x] = GameData.T_MOUNTAINS
