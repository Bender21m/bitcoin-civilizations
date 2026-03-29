class_name TileMapIso
extends Node2D
## Custom isometric tile rendering using _draw().
## Renders terrain diamonds, elevation depth sides, terrain decorations,
## selection/hover highlights, deposit markers, and buildings.

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if GameState.terrain.is_empty():
		return

	var cam: Camera2D = get_viewport().get_camera_2d()
	if not cam:
		return

	var zoom: float = cam.zoom.x
	var cam_pos: Vector2 = cam.get_screen_center_position()
	var vp_size: Vector2 = get_viewport_rect().size

	var half_vp_w: float = vp_size.x / 2.0
	var half_vp_h: float = vp_size.y / 2.0

	var W: int = GameData.MAP_W
	var H: int = GameData.MAP_H

	# Build building lookup
	var building_map: Dictionary = {}
	for b: Dictionary in GameState.buildings:
		building_map["%d,%d" % [b["x"], b["y"]]] = b

	# Render back to front
	for y in range(H):
		for x in range(W):
			var iso: Vector2 = _to_iso(x, y)
			# Frustum cull (in world space, check vs camera view)
			var screen_x: float = (iso.x - cam_pos.x) * zoom + half_vp_w
			var screen_y: float = (iso.y - cam_pos.y) * zoom + half_vp_h
			var w: float = GameData.HALF_W * zoom
			var h: float = GameData.HALF_H * zoom

			if screen_x + w < -20 or screen_x - w > vp_size.x + 20:
				continue
			if screen_y + h < -20 or screen_y - h > vp_size.y + 80:
				continue

			_draw_tile(x, y, iso)

			var bkey: String = "%d,%d" % [x, y]
			if building_map.has(bkey):
				_draw_building(building_map[bkey], iso)


func _to_iso(tx: int, ty: int) -> Vector2:
	return Vector2(
		(tx - ty) * GameData.HALF_W,
		(tx + ty) * GameData.HALF_H
	)


func _noise_simple(x: float, y: float) -> float:
	var n: float = sin(x * 12.9898 + y * 78.233) * 43758.5453
	return n - floor(n)


func _adjust_color(base_color: Color, amount: float) -> Color:
	var adj: float = amount / 255.0
	return Color(
		clampf(base_color.r + adj, 0.0, 1.0),
		clampf(base_color.g + adj, 0.0, 1.0),
		clampf(base_color.b + adj, 0.0, 1.0),
		base_color.a
	)


func _draw_tile(x: int, y: int, iso: Vector2) -> void:
	var t: int = GameState.terrain[y][x]
	var t_def: Dictionary = GameData.TERRAIN_DEFS[t]
	var base_color: Color = t_def["color"]
	var dark_color: Color = t_def["dark_color"]

	var hw: float = GameData.HALF_W
	var hh: float = GameData.HALF_H

	var elev: float = GameState.elevation[y][x]
	var tile_height: float = maxf(0.0, (elev - 0.25) * 18.0)

	var is_selected: bool = GameState.selected_tile.x == x and GameState.selected_tile.y == y
	var is_hovered: bool = GameState.hovered_tile.x == x and GameState.hovered_tile.y == y

	# Tile depth sides
	if tile_height > 1.0:
		var side_points: PackedVector2Array = PackedVector2Array([
			iso + Vector2(-hw, 0),
			iso + Vector2(-hw, tile_height),
			iso + Vector2(0, hh + tile_height),
			iso + Vector2(hw, tile_height),
			iso + Vector2(hw, 0),
			iso + Vector2(0, hh),
		])
		draw_colored_polygon(side_points, dark_color)

	# Top diamond
	var top: PackedVector2Array = PackedVector2Array([
		iso + Vector2(0, -hh),
		iso + Vector2(hw, 0),
		iso + Vector2(0, hh),
		iso + Vector2(-hw, 0),
	])

	var variation: float = floor(_noise_simple(x * 7.3, y * 7.3) * 8.0)
	var tile_color: Color = _adjust_color(base_color, variation)
	draw_colored_polygon(top, tile_color)

	# Grid outline
	draw_polyline(PackedVector2Array([
		iso + Vector2(0, -hh),
		iso + Vector2(hw, 0),
		iso + Vector2(0, hh),
		iso + Vector2(-hw, 0),
		iso + Vector2(0, -hh),
	]), Color(0, 0, 0, 0.15), 0.5)

	# Selection highlight
	if is_selected:
		draw_polyline(PackedVector2Array([
			iso + Vector2(0, -hh),
			iso + Vector2(hw, 0),
			iso + Vector2(0, hh),
			iso + Vector2(-hw, 0),
			iso + Vector2(0, -hh),
		]), GameData.BTC_ORANGE, 2.5)
		draw_colored_polygon(top, Color(0.97, 0.58, 0.10, 0.15))
	elif is_hovered:
		draw_polyline(PackedVector2Array([
			iso + Vector2(0, -hh),
			iso + Vector2(hw, 0),
			iso + Vector2(0, hh),
			iso + Vector2(-hw, 0),
			iso + Vector2(0, -hh),
		]), Color(0.97, 0.58, 0.10, 0.5), 1.5)

	# ── Terrain decorations ──
	if t == GameData.T_MOUNTAINS or t == GameData.T_SNOW:
		var peak_color: Color = Color.WHITE if t == GameData.T_SNOW else Color(0.67, 0.67, 0.67)
		var peak: PackedVector2Array = PackedVector2Array([
			iso + Vector2(-4, 2),
			iso + Vector2(0, -6),
			iso + Vector2(4, 2),
		])
		draw_colored_polygon(peak, Color(peak_color, 0.6))

	elif t == GameData.T_FOREST:
		for i in range(-1, 2):
			var tx2: float = iso.x + i * 5.0
			var ty2: float = iso.y - 1.0 + absf(i) * 2.0
			var tree: PackedVector2Array = PackedVector2Array([
				Vector2(tx2 - 2.5, ty2 + 2.0),
				Vector2(tx2, ty2 - 3.0),
				Vector2(tx2 + 2.5, ty2 + 2.0),
			])
			draw_colored_polygon(tree, Color(0.1, 0.29, 0.08, 0.7))

	elif t == GameData.T_VOLCANIC:
		var glow_alpha: float = 0.4 + sin(_time * 3.0 + x * 5.0) * 0.15
		draw_circle(iso, 3.0, Color(1.0, 0.27, 0.13, glow_alpha))

	elif t == GameData.T_RIVER:
		var shimmer: float = sin(_time * 2.0 + x * 3.0 + y * 2.0) * 2.0
		draw_line(
			iso + Vector2(-6.0, shimmer),
			iso + Vector2(6.0, shimmer),
			Color(0.39, 0.71, 1.0, 0.5), 2.0
		)

	elif t == GameData.T_MAJOR_RIVER:
		var shimmer: float = sin(_time * 1.5 + x * 2.0 + y * 1.5) * 2.5
		draw_line(
			iso + Vector2(-8.0, shimmer),
			iso + Vector2(8.0, shimmer),
			Color(0.31, 0.63, 1.0, 0.6), 3.0
		)
		var shimmer2: float = sin(_time * 2.0 + x * 4.0 + y * 3.0) * 1.5
		draw_line(
			iso + Vector2(-5.0, shimmer2 + 2.0),
			iso + Vector2(5.0, shimmer2 + 2.0),
			Color(0.47, 0.78, 1.0, 0.35), 1.5
		)

	elif t == GameData.T_DESERT:
		draw_line(
			iso + Vector2(-6.0, 1.0),
			iso + Vector2(2.0, 1.0),
			Color(0.78, 0.71, 0.31, 0.3), 1.0
		)

	elif t == GameData.T_COAST or t == GameData.T_DEEP_WATER:
		var phase: float = _time + x + y * 1.3
		var cx: float = iso.x + sin(phase) * 3.0
		var cy: float = iso.y + cos(phase) * 1.5
		draw_circle(Vector2(cx, cy), 2.0, Color(0.39, 0.67, 1.0, 0.15))

	# ── Deposit markers ──
	var dep: String = GameState.deposits[y][x]
	if dep != "":
		var dep_def: Dictionary = GameData.DEPOSITS[dep]
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 10
		draw_string(font, iso + Vector2(-4, 4), dep_def["symbol"], HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, dep_def["color"])


# ── Building Drawing ──────────────────────────────────────────
func _draw_building(building: Dictionary, iso: Vector2) -> void:
	var civ: Dictionary = GameState.civs[building["owner"]]
	var col: Color = civ["color"]

	match building["type"]:
		"citadel":
			_draw_citadel(iso, col)
		"house":
			_draw_house(iso, col)
		"farm":
			_draw_farm(iso, col)
		"solar_panel":
			_draw_solar_panel(iso, col)
		"home_miner":
			_draw_home_miner(iso, col)
		"hydro_dam":
			_draw_hydro_dam(iso, col)
		"wind_turbine":
			_draw_wind_turbine(iso, col)
		"geothermal_plant":
			_draw_geothermal_plant(iso, col)


func _draw_citadel(iso: Vector2, color: Color) -> void:
	var s: float = 12.0

	# Base platform
	var base: PackedVector2Array = PackedVector2Array([
		iso + Vector2(0, -s * 1.8),
		iso + Vector2(s, -s * 0.6),
		iso + Vector2(0, s * 0.2),
		iso + Vector2(-s, -s * 0.6),
	])
	draw_colored_polygon(base, Color(color, 0.9))
	draw_polyline(PackedVector2Array([
		iso + Vector2(0, -s * 1.8),
		iso + Vector2(s, -s * 0.6),
		iso + Vector2(0, s * 0.2),
		iso + Vector2(-s, -s * 0.6),
		iso + Vector2(0, -s * 1.8),
	]), Color(1, 1, 1, 0.5), 1.5)

	# Tower spire
	var spire: PackedVector2Array = PackedVector2Array([
		iso + Vector2(0, -s * 2.6),
		iso + Vector2(s * 0.4, -s * 1.4),
		iso + Vector2(-s * 0.4, -s * 1.4),
	])
	draw_colored_polygon(spire, color)

	# Crenellations
	for i in range(-2, 3):
		draw_rect(Rect2(
			iso.x + i * s * 0.3 - 1, iso.y - s * 1.8 - 2,
			2, 3
		), Color(1, 1, 1, 0.6))

	# Glow
	draw_circle(iso + Vector2(0, -s), s * 0.6, Color(color, 0.15))


func _draw_house(iso: Vector2, color: Color) -> void:
	var s: float = 6.0

	# Walls
	draw_rect(Rect2(iso.x - s, iso.y - s * 0.6, s * 2, s * 1.4), Color(0.78, 0.72, 0.6, 0.9))

	# Roof
	var roof: PackedVector2Array = PackedVector2Array([
		iso + Vector2(-s * 1.3, -s * 0.6),
		iso + Vector2(0, -s * 2.0),
		iso + Vector2(s * 1.3, -s * 0.6),
	])
	draw_colored_polygon(roof, Color(color, 0.85))

	# Door
	draw_rect(Rect2(iso.x - 1.5, iso.y + s * 0.1, 3, s * 0.7), Color(0.35, 0.23, 0.1, 0.9))


func _draw_farm(iso: Vector2, color: Color) -> void:
	var s: float = 7.0

	# Field
	var field: PackedVector2Array = PackedVector2Array([
		iso + Vector2(0, -s * 0.6),
		iso + Vector2(s, 0),
		iso + Vector2(0, s * 0.6),
		iso + Vector2(-s, 0),
	])
	draw_colored_polygon(field, Color(0.35, 0.6, 0.23, 0.8))

	# Crop lines
	for i in range(-2, 3):
		draw_line(
			iso + Vector2(i * s * 0.25 - s * 0.3, -s * 0.2 + i),
			iso + Vector2(i * s * 0.25 + s * 0.3, s * 0.2 + i),
			Color(0.23, 0.48, 0.1, 0.6), 1.0
		)

	# Barn
	draw_rect(Rect2(iso.x - 2, iso.y - s * 0.9, 4, 4), Color(0.55, 0.27, 0.08, 0.85))


func _draw_solar_panel(iso: Vector2, color: Color) -> void:
	var s: float = 7.0

	# Panel
	var panel: PackedVector2Array = PackedVector2Array([
		iso + Vector2(-s * 0.7, -s * 0.8),
		iso + Vector2(s * 0.7, -s * 0.8),
		iso + Vector2(s * 0.5, s * 0.2),
		iso + Vector2(-s * 0.5, s * 0.2),
	])
	draw_colored_polygon(panel, Color(0.1, 0.27, 0.53, 0.9))

	# Grid lines
	for i in range(3):
		var fy: float = iso.y - s * 0.7 + i * s * 0.35
		draw_line(
			Vector2(iso.x - s * 0.6, fy),
			Vector2(iso.x + s * 0.6, fy),
			Color(0.27, 0.53, 0.8, 0.7), 0.6
		)
	for i in range(-1, 2):
		draw_line(
			iso + Vector2(i * s * 0.35, -s * 0.8),
			iso + Vector2(i * s * 0.28, s * 0.2),
			Color(0.27, 0.53, 0.8, 0.7), 0.6
		)

	# Support pole
	draw_rect(Rect2(iso.x - 1, iso.y + s * 0.2, 2, s * 0.4), Color(0.53, 0.53, 0.53, 0.8))

	# Shine
	draw_circle(iso + Vector2(s * 0.2, -s * 0.5), 2.0, Color(0.78, 0.9, 1.0, 0.4))


func _draw_home_miner(iso: Vector2, color: Color) -> void:
	var s: float = 5.0

	# Box
	draw_rect(Rect2(iso.x - s, iso.y - s * 0.8, s * 2, s * 1.4), Color(0.2, 0.2, 0.2, 0.9))
	draw_rect(Rect2(iso.x - s * 0.8, iso.y - s * 0.6, s * 1.6, s * 1.0), Color(0.13, 0.13, 0.13, 0.9))

	# Ventilation lines
	for i in range(3):
		draw_line(
			iso + Vector2(-s * 0.6, -s * 0.3 + i * s * 0.3),
			iso + Vector2(s * 0.6, -s * 0.3 + i * s * 0.3),
			Color(0.27, 0.27, 0.27), 0.5
		)

	# Blinking LED
	var blink: bool = sin(_time * 5.0 + iso.x * 0.1) > 0
	if blink:
		draw_circle(iso + Vector2(s * 0.5, -s * 0.5), 2.0, Color(0.97, 0.58, 0.10))
		draw_circle(iso + Vector2(s * 0.5, -s * 0.5), 4.0, Color(0.97, 0.58, 0.10, 0.2))
	else:
		draw_circle(iso + Vector2(s * 0.5, -s * 0.5), 1.5, Color(0.4, 0.27, 0.0))


func _draw_hydro_dam(iso: Vector2, color: Color) -> void:
	var s: float = 8.0

	# Dam wall (simplified arc)
	var dam: PackedVector2Array = PackedVector2Array([
		iso + Vector2(-s, s * 0.3),
		iso + Vector2(-s * 0.3, -s * 0.4),
		iso + Vector2(s * 0.3, -s * 0.4),
		iso + Vector2(s, s * 0.3),
		iso + Vector2(s, s * 0.7),
		iso + Vector2(s * 0.3, s * 0.1),
		iso + Vector2(-s * 0.3, s * 0.1),
		iso + Vector2(-s, s * 0.7),
	])
	draw_colored_polygon(dam, Color(0.53, 0.53, 0.53, 0.9))

	# Water behind dam
	draw_circle(iso + Vector2(0, -s * 0.3), s * 0.4, Color(0.2, 0.53, 0.72, 0.6))

	# Water flow below
	var shimmer: float = sin(_time * 4.0) * 2.0
	draw_line(
		iso + Vector2(-s * 0.2, s * 0.7),
		iso + Vector2(s * 0.2, s * 0.7 + shimmer),
		Color(0.35, 0.78, 1.0, 0.7), 2.0
	)

	# Color accent
	draw_rect(Rect2(iso.x - s * 0.15, iso.y - s * 0.1, s * 0.3, s * 0.2), Color(color, 0.8))


func _draw_wind_turbine(iso: Vector2, color: Color) -> void:
	var s: float = 7.0

	# Tower pole
	draw_rect(Rect2(iso.x - 1, iso.y - s * 1.5, 2, s * 2), Color(0.8, 0.8, 0.8, 0.9))

	# Hub
	draw_circle(iso + Vector2(0, -s * 1.5), 2.0, Color(0.87, 0.87, 0.87))

	# Blades (rotating)
	var angle: float = fmod(_time * 2.0, TAU)
	for i in range(3):
		var a: float = angle + i * TAU / 3.0
		draw_line(
			iso + Vector2(0, -s * 1.5),
			iso + Vector2(cos(a) * s * 0.9, -s * 1.5 + sin(a) * s * 0.9),
			Color(0.93, 0.93, 0.93), 1.5
		)

	# Base
	var base: PackedVector2Array = PackedVector2Array([
		iso + Vector2(-s * 0.4, s * 0.5),
		iso + Vector2(0, s * 0.2),
		iso + Vector2(s * 0.4, s * 0.5),
	])
	draw_colored_polygon(base, Color(0.6, 0.6, 0.6, 0.8))

	# Color hub
	draw_circle(iso + Vector2(0, -s * 1.5), 1.5, Color(color, 0.9))


func _draw_geothermal_plant(iso: Vector2, color: Color) -> void:
	var s: float = 7.0

	# Main building
	draw_rect(Rect2(iso.x - s * 0.6, iso.y - s * 0.4, s * 1.2, s * 0.9), Color(0.33, 0.33, 0.33, 0.9))

	# Pipes
	draw_rect(Rect2(iso.x - s * 0.8, iso.y + s * 0.1, s * 0.3, s * 0.3), Color(0.47, 0.47, 0.47))
	draw_rect(Rect2(iso.x + s * 0.5, iso.y + s * 0.1, s * 0.3, s * 0.3), Color(0.47, 0.47, 0.47))

	# Chimney
	draw_rect(Rect2(iso.x - s * 0.15, iso.y - s * 1.0, s * 0.3, s * 0.6), Color(0.4, 0.4, 0.4))

	# Steam
	var steam_phase: float = _time * 3.0
	var steam_alpha: float = 0.3 + sin(steam_phase) * 0.1
	draw_circle(
		iso + Vector2(0, -s * 1.2 - sin(steam_phase) * s * 0.2),
		s * 0.25, Color(0.87, 0.87, 0.87, steam_alpha)
	)
	draw_circle(
		iso + Vector2(s * 0.15, -s * 1.5 - sin(steam_phase + 1) * s * 0.15),
		s * 0.18, Color(0.87, 0.87, 0.87, steam_alpha)
	)

	# Heat glow
	var glow_alpha: float = 0.4 + sin(steam_phase * 0.5) * 0.15
	draw_circle(iso + Vector2(0, s * 0.3), s * 0.4, Color(1.0, 0.31, 0.08, glow_alpha))

	# Color accent
	draw_rect(Rect2(iso.x - s * 0.4, iso.y - s * 0.3, s * 0.8, s * 0.15), Color(color, 0.8))


# ── Input: tile selection via click ──────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var tile: Vector2i = _screen_to_tile(mb.position)
			if GameState.is_valid_tile(tile.x, tile.y):
				GameState.select_tile(tile.x, tile.y)
			else:
				GameState.deselect_tile()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var tile: Vector2i = _screen_to_tile(mm.position)
		if GameState.is_valid_tile(tile.x, tile.y):
			GameState.hovered_tile = tile
		else:
			GameState.hovered_tile = Vector2i(-1, -1)


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if not cam:
		return Vector2i(-1, -1)

	var vp_size: Vector2 = get_viewport_rect().size
	var cam_pos: Vector2 = cam.get_screen_center_position()
	var zoom: float = cam.zoom.x

	var wx: float = (screen_pos.x - vp_size.x / 2.0) / zoom + cam_pos.x
	var wy: float = (screen_pos.y - vp_size.y / 2.0) / zoom + cam_pos.y

	var tx: float = (wx / GameData.HALF_W + wy / GameData.HALF_H) / 2.0
	var ty: float = (wy / GameData.HALF_H - wx / GameData.HALF_W) / 2.0

	return Vector2i(int(floor(tx)), int(floor(ty)))
