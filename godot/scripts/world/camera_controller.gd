class_name CameraController
extends Camera2D
## Camera controller: WASD/arrow pan, mouse drag pan, scroll zoom toward cursor.

const PAN_SPEED: float = 400.0
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 0.1
const SMOOTH_FACTOR: float = 8.0

var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _camera_start: Vector2 = Vector2.ZERO
var _target_zoom: float = 0.7
var _target_position: Vector2 = Vector2.ZERO
var _drag_moved: float = 0.0

func _ready() -> void:
	zoom = Vector2(_target_zoom, _target_zoom)
	_target_position = position


func _process(delta: float) -> void:
	# Keyboard panning
	var pan_dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan_dir.x += 1.0

	if pan_dir != Vector2.ZERO:
		var speed: float = PAN_SPEED * delta / zoom.x
		_target_position += pan_dir.normalized() * speed

	# Smooth camera
	position = position.lerp(_target_position, minf(1.0, SMOOTH_FACTOR * delta))
	zoom = zoom.lerp(Vector2(_target_zoom, _target_zoom), minf(1.0, SMOOTH_FACTOR * delta))

	# Clamp to map bounds
	var map_min: Vector2 = Vector2(-GameData.MAP_H * GameData.HALF_W, 0)
	var map_max: Vector2 = Vector2(GameData.MAP_W * GameData.HALF_W, (GameData.MAP_W + GameData.MAP_H) * GameData.HALF_H)
	position.x = clampf(position.x, map_min.x - 200, map_max.x + 200)
	position.y = clampf(position.y, map_min.y - 200, map_max.y + 200)
	_target_position = position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		# Zoom
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_toward_cursor(mb.position, 1.1)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_toward_cursor(mb.position, 0.9)
			get_viewport().set_input_as_handled()

		# Drag pan
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging = true
				_drag_start = mb.position
				_camera_start = _target_position
				_drag_moved = 0.0
			else:
				_is_dragging = false

		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_dragging = true
				_drag_start = mb.position
				_camera_start = _target_position
				_drag_moved = 0.0
			else:
				_is_dragging = false

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _is_dragging:
			var delta: Vector2 = mm.position - _drag_start
			_drag_moved += delta.length()
			if _drag_moved > 5.0:
				_target_position = _camera_start - delta / zoom.x
				position = _target_position
				# Consume the event so tile selection doesn't trigger
				get_viewport().set_input_as_handled()


func _zoom_toward_cursor(cursor_pos: Vector2, factor: float) -> void:
	var new_zoom: float = clampf(_target_zoom * factor, ZOOM_MIN, ZOOM_MAX)

	var vp_size: Vector2 = get_viewport_rect().size
	var mx: float = cursor_pos.x - vp_size.x / 2.0
	var my: float = cursor_pos.y - vp_size.y / 2.0

	_target_position.x = (_target_position.x + mx / zoom.x) - mx / new_zoom
	_target_position.y = (_target_position.y + my / zoom.y) - my / new_zoom

	_target_zoom = new_zoom
