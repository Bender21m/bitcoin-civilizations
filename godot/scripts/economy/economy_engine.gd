class_name EconomyEngine
extends RefCounted
## Economy engine: recalculates all civilization stats from buildings.
## Faithful port of the JS recalculateCivStats() function.


func recalculate_civ_stats() -> void:
	# Reset all stats
	for civ: Dictionary in GameState.civs:
		civ["energy_produced"] = 0
		civ["energy_consumed"] = 0
		civ["hash_power"] = 0
		civ["population"] = 0
		civ["max_population"] = 0
		civ["food_produced"] = 0

	# First pass: energy production, pop capacity, food
	for b: Dictionary in GameState.buildings:
		if not b["active"]:
			continue
		var bt: Dictionary = GameData.BUILDING_TYPES[b["type"]]
		var civ: Dictionary = GameState.civs[b["owner"]]

		# Calculate energy output with terrain bonuses
		var energy_out: int = bt["energy_output"]
		if energy_out > 0 and b["x"] >= 0 and b["y"] >= 0:
			var tile_terrain: int = GameState.terrain[b["y"]][b["x"]]
			var tile_quad: String = GameData.get_quadrant_name(b["x"], b["y"])

			if b["type"] == "solar_panel" and tile_terrain == GameData.T_DESERT:
				energy_out = 10  # Desert solar bonus
			elif b["type"] == "hydro_dam" and tile_terrain == GameData.T_MAJOR_RIVER:
				energy_out = 20  # Major river hydro bonus — strongest
			elif b["type"] == "hydro_dam" and tile_quad == "SW":
				energy_out = 18  # River quadrant hydro bonus
			elif b["type"] == "wind_turbine" and tile_quad == "SE":
				energy_out = 8   # Mountain quadrant wind bonus
			elif b["type"] == "geothermal_plant" and tile_terrain == GameData.T_VOLCANIC:
				energy_out = 15  # Volcanic geothermal bonus

		civ["energy_produced"] += energy_out
		civ["max_population"] += bt["pop_capacity"]
		civ["food_produced"] += bt["food_output"]

	# Population = min(max_pop, food)
	for civ: Dictionary in GameState.civs:
		civ["population"] = mini(civ["max_population"], civ["food_produced"])

	# Second pass: miners (energy consumers, hash producers)
	for b: Dictionary in GameState.buildings:
		if not b["active"]:
			continue
		var bt: Dictionary = GameData.BUILDING_TYPES[b["type"]]
		var civ: Dictionary = GameState.civs[b["owner"]]

		if bt["hash_power"] > 0:
			var energy_needed: int = bt["energy"]
			var available_energy: int = civ["energy_produced"] - civ["energy_consumed"]
			if available_energy >= energy_needed:
				civ["energy_consumed"] += energy_needed
				civ["hash_power"] += bt["hash_power"]


## Get the actual energy output of a building considering terrain bonuses.
func get_building_energy_output(building: Dictionary) -> int:
	var bt: Dictionary = GameData.BUILDING_TYPES[building["type"]]
	var energy_out: int = bt["energy_output"]

	if energy_out > 0 and building["x"] >= 0 and building["y"] >= 0:
		var tile_terrain: int = GameState.terrain[building["y"]][building["x"]]
		var tile_quad: String = GameData.get_quadrant_name(building["x"], building["y"])

		if building["type"] == "solar_panel" and tile_terrain == GameData.T_DESERT:
			energy_out = 10
		elif building["type"] == "hydro_dam" and tile_terrain == GameData.T_MAJOR_RIVER:
			energy_out = 20
		elif building["type"] == "hydro_dam" and tile_quad == "SW":
			energy_out = 18
		elif building["type"] == "wind_turbine" and tile_quad == "SE":
			energy_out = 8
		elif building["type"] == "geothermal_plant" and tile_terrain == GameData.T_VOLCANIC:
			energy_out = 15

	return energy_out
