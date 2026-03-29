class_name TileInfoPanel
extends PanelContainer
## Tile info panel: shows terrain, coordinates, elevation, deposits,
## energy potentials, terrain bonuses, and building info for the selected tile.

var _content: VBoxContainer
var _econ: EconomyEngine = EconomyEngine.new()


func _ready() -> void:
	# Style the panel
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.11, 0.92)
	sb.border_color = Color(0.97, 0.58, 0.10, 0.25)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	add_theme_stylebox_override("panel", sb)

	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-292, 60)
	custom_minimum_size = Vector2(280, 0)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	add_child(_content)

	visible = false

	GameState.tile_selected.connect(_on_tile_selected)
	GameState.tile_deselected.connect(_on_tile_deselected)
	GameState.turn_advanced.connect(func(_t: int) -> void: _refresh())
	GameState.map_generated.connect(func() -> void: visible = false)


func _on_tile_selected(x: int, y: int) -> void:
	visible = true
	_refresh()


func _on_tile_deselected() -> void:
	visible = false


func _refresh() -> void:
	if GameState.selected_tile.x < 0:
		visible = false
		return

	# Clear old content
	for child in _content.get_children():
		child.queue_free()

	var x: int = GameState.selected_tile.x
	var y: int = GameState.selected_tile.y
	var t: int = GameState.terrain[y][x]
	var t_def: Dictionary = GameData.TERRAIN_DEFS[t]
	var elev: float = GameState.elevation[y][x]
	var res: Dictionary = GameState.resource_data[y][x]
	var dep: String = GameState.deposits[y][x]
	var building: Dictionary = GameState.get_building_at(x, y)
	var tile_quad: String = GameData.get_quadrant_name(x, y)

	# Title
	var title: Label = Label.new()
	title.text = "TILE INFO"
	title.add_theme_color_override("font_color", GameData.BTC_ORANGE)
	title.add_theme_font_size_override("font_size", 14)
	_content.add_child(title)

	# Separator
	var sep: HSeparator = HSeparator.new()
	sep.modulate = Color(0.97, 0.58, 0.10, 0.2)
	_content.add_child(sep)

	# Coordinates
	_add_info_row("Coordinates", "(%d, %d)" % [x, y])
	_add_info_row("Terrain", t_def["name"], GameData.BTC_ORANGE)
	_add_info_row("Elevation", "%dm" % int(elev * 100))

	# Terrain bonuses
	if t == GameData.T_DESERT:
		_add_bonus("Desert Solar Bonus: +25%", Color(0.94, 0.75, 0.25))
	if t == GameData.T_RIVER and tile_quad == "SW":
		_add_bonus("River Hydro Bonus: +20%", Color(0.25, 0.56, 0.82))
	if t == GameData.T_RIVER:
		_add_bonus("River: Hydro Dam buildable", Color(0.2, 0.53, 0.72))
	if t == GameData.T_MAJOR_RIVER:
		_add_bonus("The Great Channel: Major Waterway", Color(0.13, 0.44, 0.75))
		_add_bonus("Major River: Hydro Dam buildable", Color(0.13, 0.44, 0.75))
	if t == GameData.T_HILLS and tile_quad == "SE":
		_add_bonus("Mountain Wind Bonus: +33%", Color(0.5, 0.78, 1.0))
	if t == GameData.T_HILLS:
		_add_bonus("Hills: Wind Turbine buildable", Color(0.42, 0.56, 0.31))
	if t == GameData.T_VOLCANIC:
		_add_bonus("Volcanic Geothermal Bonus: +25%", Color(1.0, 0.4, 0.27))

	# Deposit
	if dep != "":
		var dep_def: Dictionary = GameData.DEPOSITS[dep]
		_add_info_row("Deposit", "%s %s" % [dep_def["symbol"], dep_def["name"]], dep_def["color"])

	# Building info
	if not building.is_empty():
		var bt: Dictionary = GameData.BUILDING_TYPES[building["type"]]
		var civ: Dictionary = GameState.civs[building["owner"]]

		var bsep: HSeparator = HSeparator.new()
		bsep.modulate = Color(1, 1, 1, 0.08)
		_content.add_child(bsep)

		var bname: Label = Label.new()
		bname.text = bt["name"]
		bname.add_theme_color_override("font_color", civ["color"])
		bname.add_theme_font_size_override("font_size", 14)
		_content.add_child(bname)

		var owner_lbl: Label = Label.new()
		owner_lbl.text = "Owner: %s" % civ["name"]
		owner_lbl.add_theme_color_override("font_color", Color(0.67, 0.67, 0.67))
		owner_lbl.add_theme_font_size_override("font_size", 12)
		_content.add_child(owner_lbl)

		var actual_energy: int = _econ.get_building_energy_output(building)
		if bt["energy_output"] > 0:
			var bonus_text: String = ""
			if actual_energy > bt["energy_output"]:
				bonus_text = " (+%d bonus)" % (actual_energy - bt["energy_output"])
			_add_info_row("⚡ Energy", "%d%s" % [actual_energy, bonus_text], Color(0.27, 0.87, 0.4))
		if bt["hash_power"] > 0:
			_add_info_row("⛏ Hash", "%d H/s" % bt["hash_power"], Color(0.0, 0.66, 1.0))
		if bt["energy"] > 0:
			_add_info_row("⚡ Cost", str(bt["energy"]))
		if bt["pop_capacity"] > 0:
			_add_info_row("👥 Housing", "+%d" % bt["pop_capacity"])
		if bt["pop_cost"] > 0:
			_add_info_row("👷 Workers", str(bt["pop_cost"]))
		if bt["food_output"] > 0:
			_add_info_row("🌾 Food", str(bt["food_output"]))

		var desc: Label = Label.new()
		desc.text = bt["description"]
		desc.add_theme_color_override("font_color", Color(0.53, 0.53, 0.53))
		desc.add_theme_font_size_override("font_size", 11)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(desc)

	# Energy potentials
	var esep: HSeparator = HSeparator.new()
	esep.modulate = Color(1, 1, 1, 0.08)
	_content.add_child(esep)

	var etitle: Label = Label.new()
	etitle.text = "ENERGY POTENTIAL"
	etitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	etitle.add_theme_font_size_override("font_size", 12)
	_content.add_child(etitle)

	_add_energy_bar("Solar", res["solar"], Color(0.94, 0.75, 0.25))
	_add_energy_bar("Wind", res["wind"], Color(0.5, 0.78, 1.0))
	_add_energy_bar("Hydro", res["hydro"], Color(0.25, 0.56, 0.82))
	_add_energy_bar("Geothermal", res["geothermal"], Color(1.0, 0.4, 0.27))


func _add_info_row(label_text: String, value_text: String, value_color: Color = Color(0.87, 0.87, 0.87)) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", Color(0.53, 0.53, 0.53))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val: Label = Label.new()
	val.text = value_text
	val.add_theme_color_override("font_color", value_color)
	val.add_theme_font_size_override("font_size", 13)
	row.add_child(val)

	_content.add_child(row)


func _add_bonus(text: String, color: Color) -> void:
	var lbl: Label = Label.new()
	lbl.text = "🏷 " + text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 11)
	_content.add_child(lbl)


func _add_energy_bar(label_text: String, value: int, color: Color) -> void:
	var row: HBoxContainer = HBoxContainer.new()

	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", Color(0.53, 0.53, 0.53))
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.custom_minimum_size = Vector2(80, 0)
	row.add_child(lbl)

	var bar_bg: ColorRect = ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.08)
	bar_bg.custom_minimum_size = Vector2(120, 6)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar_bg)

	var bar_fill: ColorRect = ColorRect.new()
	bar_fill.color = color
	bar_fill.custom_minimum_size = Vector2(120.0 * value / 100.0, 6)
	bar_bg.add_child(bar_fill)

	var val: Label = Label.new()
	val.text = "%d%%" % value
	val.add_theme_color_override("font_color", Color(0.87, 0.87, 0.87))
	val.add_theme_font_size_override("font_size", 12)
	val.custom_minimum_size = Vector2(40, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)

	_content.add_child(row)
