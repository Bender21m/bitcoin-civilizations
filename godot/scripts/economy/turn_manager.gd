class_name TurnManager
extends RefCounted
## Turn processing: halving, stat recalc, block reward distribution.
## Faithful port of the JS processTurn() function.


func next_turn() -> Dictionary:
	GameState.turn += 1

	# Halving check
	if GameState.turn > 0 and GameState.turn % GameState.halving_interval == 0:
		GameState.block_reward = maxf(1.0, floor(GameState.block_reward / 2.0))

	# Recalculate stats
	var econ: EconomyEngine = EconomyEngine.new()
	econ.recalculate_civ_stats()

	# Calculate total network hash
	var total_hash: int = 0
	for civ: Dictionary in GameState.civs:
		total_hash += civ["hash_power"]

	# Distribute block reward proportionally
	var earnings: Array[Dictionary] = []
	for civ: Dictionary in GameState.civs:
		var earned: float = 0.0
		if total_hash > 0 and civ["hash_power"] > 0:
			earned = snappedf(GameState.block_reward * (float(civ["hash_power"]) / float(total_hash)), 0.01)
		civ["treasury"] += earned
		civ["treasury"] = snappedf(civ["treasury"], 0.01)
		earnings.append({
			"name": civ["name"],
			"color": civ["color"],
			"earned": earned,
		})

	var summary: Dictionary = {
		"turn": GameState.turn,
		"block_reward": GameState.block_reward,
		"total_hash": total_hash,
		"earnings": earnings,
		"halving_occurred": GameState.turn > 0 and GameState.turn % GameState.halving_interval == 0,
	}

	GameState.turn_advanced.emit(GameState.turn)

	return summary
