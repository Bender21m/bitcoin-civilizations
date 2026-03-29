class_name GameWorld
extends Node2D
## Main game world — orchestrates map generation, civilization init, and world nodes.

@onready var tile_map: TileMapIso = $TileMapIso
@onready var camera: CameraController = $Camera2D

var _initialized: bool = false


func _ready() -> void:
	new_game(GameState.current_seed)


func new_game(seed_val: int) -> void:
	GameState.current_seed = seed_val
	GameState.reset_game()

	# Generate map
	var gen: MapGenerator = MapGenerator.new()
	gen.generate(seed_val)

	# Initialize civilizations
	var civ_mgr: CivManager = CivManager.new()
	civ_mgr.init_civilizations()

	# Recalculate stats
	var econ: EconomyEngine = EconomyEngine.new()
	econ.recalculate_civ_stats()

	# Center camera on player citadel
	_center_camera_on_player()

	# Redraw the map
	if tile_map:
		tile_map.queue_redraw()

	_initialized = true


func new_map() -> void:
	var new_seed: int = randi() % 1000000
	new_game(new_seed)


func _center_camera_on_player() -> void:
	if not camera:
		return
	# Find player citadel
	for b: Dictionary in GameState.buildings:
		if b["owner"] == 0 and b["type"] == "citadel":
			var iso: Vector2 = _to_iso(b["x"], b["y"])
			camera.position = iso
			return
	# Fallback: center of map
	var cx: int = GameData.MAP_W / 2
	var cy: int = GameData.MAP_H / 2
	camera.position = _to_iso(cx, cy)


func _to_iso(tx: int, ty: int) -> Vector2:
	return Vector2(
		(tx - ty) * GameData.HALF_W,
		(tx + ty) * GameData.HALF_H
	)
