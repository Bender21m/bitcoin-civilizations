class_name HUD
extends CanvasLayer
## Top bar HUD: turn counter, civ indicator, treasury, hash, energy, population.
## Next Turn and New Map buttons.

var _turn_label: Label
var _civ_color: ColorRect
var _civ_name: Label
var _sats_label: Label
var _hash_label: Label
var _energy_label: Label
var _pop_label: Label
var _coords_label: Label
var _next_turn_btn: Button
var _new_map_btn: Button
var _toast_label: Label
var _toast_timer: float = 0.0

var _turn_mgr: TurnManager = TurnManager.new()


func _ready() -> void:
	# Build the HUD UI programmatically
	_build_hud()
	_update_hud()

	# Connect signals
	GameState.turn_advanced.connect(_on_turn_advanced)
	GameState.map_generated.connect(_on_map_generated)


func _process(delta: float) -> void:
	# Update hover coords
	if _coords_label and GameState.hovered_tile.x >= 0:
		var t: int = GameState.terrain[GameState.hovered_tile.y][GameState.hovered_tile.x]
		var t_name: String = GameData.TERRAIN_DEFS[t]["name"]
		_coords_label.text = "(%d, %d) — %s" % [GameState.hovered_tile.x, GameState.hovered_tile.y, t_name]
	elif _coords_label:
		_coords_label.text = "—"

	# Toast fade
	if _toast_timer > 0:
		_toast_timer -= delta
		if _toast_label:
			_toast_label.modulate.a = clampf(_toast_timer / 0.5, 0.0, 1.0) if _toast_timer < 0.5 else 1.0
			_toast_label.visible = _toast_timer > 0


func _build_hud() -> void:
	# Top bar panel
	var top_bar: PanelContainer = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 48)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	sb.border_color = Color(0.97, 0.58, 0.10, 0.3)
	sb.border_width_bottom = 1
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	top_bar.add_theme_stylebox_override("panel", sb)
	add_child(top_bar)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	top_bar.add_child(hbox)

	# Logo
	var logo: Label = Label.new()
	logo.text = "₿ITCOIN CIVILIZATIONS"
	logo.add_theme_color_override("font_color", GameData.BTC_ORANGE)
	logo.add_theme_font_size_override("font_size", 16)
	hbox.add_child(logo)

	_add_separator(hbox)

	# Turn
	var turn_container: HBoxContainer = HBoxContainer.new()
	turn_container.add_theme_constant_override("separation", 4)
	hbox.add_child(turn_container)
	var turn_lbl: Label = _make_label("Turn ", Color(0.67, 0.67, 0.67), 12)
	turn_container.add_child(turn_lbl)
	_turn_label = _make_label("0", Color.WHITE, 13)
	turn_container.add_child(_turn_label)

	_add_separator(hbox)

	# Civ indicator
	_civ_color = ColorRect.new()
	_civ_color.custom_minimum_size = Vector2(10, 10)
	hbox.add_child(_civ_color)
	_civ_name = _make_label("—", Color(0.87, 0.87, 0.87), 12)
	hbox.add_child(_civ_name)

	_add_separator(hbox)

	# Treasury
	var sats_container: HBoxContainer = HBoxContainer.new()
	sats_container.add_theme_constant_override("separation", 4)
	hbox.add_child(sats_container)
	sats_container.add_child(_make_label("₿ ", Color(0.67, 0.67, 0.67), 12))
	_sats_label = _make_label("0", GameData.BTC_ORANGE, 13)
	sats_container.add_child(_sats_label)

	_add_separator(hbox)

	# Hash
	var hash_container: HBoxContainer = HBoxContainer.new()
	hash_container.add_theme_constant_override("separation", 4)
	hbox.add_child(hash_container)
	hash_container.add_child(_make_label("⛏ ", Color(0.67, 0.67, 0.67), 12))
	_hash_label = _make_label("0", Color(0.0, 0.66, 1.0), 13)
	hash_container.add_child(_hash_label)
	hash_container.add_child(_make_label(" H/s", Color(0.4, 0.4, 0.4), 12))

	_add_separator(hbox)

	# Energy
	var energy_container: HBoxContainer = HBoxContainer.new()
	energy_container.add_theme_constant_override("separation", 4)
	hbox.add_child(energy_container)
	energy_container.add_child(_make_label("⚡ ", Color(0.67, 0.67, 0.67), 12))
	_energy_label = _make_label("0/0", Color(0.27, 0.87, 0.4), 13)
	energy_container.add_child(_energy_label)

	_add_separator(hbox)

	# Population
	var pop_container: HBoxContainer = HBoxContainer.new()
	pop_container.add_theme_constant_override("separation", 4)
	hbox.add_child(pop_container)
	pop_container.add_child(_make_label("👥 ", Color(0.67, 0.67, 0.67), 12))
	_pop_label = _make_label("0/0", Color(0.8, 0.53, 1.0), 13)
	pop_container.add_child(_pop_label)

	_add_separator(hbox)

	# New Map button
	_new_map_btn = Button.new()
	_new_map_btn.text = "🗺 New Map"
	_new_map_btn.add_theme_font_size_override("font_size", 12)
	_new_map_btn.pressed.connect(_on_new_map)
	hbox.add_child(_new_map_btn)

	# Spacer
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Coords
	_coords_label = _make_label("—", Color(0.53, 0.53, 0.53), 13)
	hbox.add_child(_coords_label)

	# Next Turn button (bottom center)
	_next_turn_btn = Button.new()
	_next_turn_btn.text = "⏭ NEXT TURN [Space]"
	_next_turn_btn.add_theme_font_size_override("font_size", 15)
	var btn_sb: StyleBoxFlat = StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.97, 0.58, 0.10)
	btn_sb.corner_radius_top_left = 10
	btn_sb.corner_radius_top_right = 10
	btn_sb.corner_radius_bottom_left = 10
	btn_sb.corner_radius_bottom_right = 10
	btn_sb.content_margin_left = 32
	btn_sb.content_margin_right = 32
	btn_sb.content_margin_top = 10
	btn_sb.content_margin_bottom = 10
	_next_turn_btn.add_theme_stylebox_override("normal", btn_sb)
	_next_turn_btn.add_theme_color_override("font_color", Color.WHITE)
	_next_turn_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_next_turn_btn.position = Vector2(-100, -70)
	_next_turn_btn.pressed.connect(_on_next_turn)
	add_child(_next_turn_btn)

	# Toast notification
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.position = Vector2(-180, 60)
	_toast_label.custom_minimum_size = Vector2(360, 0)
	_toast_label.add_theme_color_override("font_color", Color(0.87, 0.87, 0.87))
	_toast_label.add_theme_font_size_override("font_size", 13)
	_toast_label.visible = false
	add_child(_toast_label)

	# Controls hint
	var controls: Label = _make_label("WASD/Arrows pan · Scroll zoom · Click select · Space next turn · C civ panel", Color(0.33, 0.33, 0.33), 11)
	controls.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	controls.position = Vector2(-300, -12)
	controls.custom_minimum_size = Vector2(600, 0)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(controls)


func _make_label(text: String, color: Color, size: int) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	return lbl


func _add_separator(parent: HBoxContainer) -> void:
	var sep: VSeparator = VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 28)
	sep.modulate = Color(1, 1, 1, 0.1)
	parent.add_child(sep)


func _update_hud() -> void:
	if GameState.civs.is_empty():
		return
	var player: Dictionary = GameState.civs[0]
	_turn_label.text = str(GameState.turn)
	_civ_name.text = player["name"]
	_civ_color.color = player["color"]
	_sats_label.text = str(int(player["treasury"]))
	_hash_label.text = str(player["hash_power"])
	var net_energy: int = player["energy_produced"] - player["energy_consumed"]
	_energy_label.text = "%d/%d" % [net_energy, player["energy_produced"]]
	_pop_label.text = "%d/%d" % [player["population"], player["max_population"]]


func _on_next_turn() -> void:
	var summary: Dictionary = _turn_mgr.next_turn()
	_update_hud()
	_show_toast(summary)


func _on_new_map() -> void:
	var game_world: GameWorld = get_tree().get_first_node_in_group("game_world") as GameWorld
	if game_world:
		game_world.new_map()
	_update_hud()


func _on_turn_advanced(_turn: int) -> void:
	_update_hud()


func _on_map_generated() -> void:
	_update_hud()


func _show_toast(summary: Dictionary) -> void:
	if not _toast_label:
		return
	var text: String = "⛏ Block %d Mined\nReward: %s sats · Network: %d H/s\n" % [
		summary["turn"], str(summary["block_reward"]), summary["total_hash"]
	]
	for e: Dictionary in summary["earnings"]:
		if e["earned"] > 0:
			text += "%s: +%s sats\n" % [e["name"], str(e["earned"])]
	_toast_label.text = text
	_toast_label.visible = true
	_toast_timer = 3.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_SPACE:
				_on_next_turn()
				get_viewport().set_input_as_handled()
