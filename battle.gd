extends CanvasLayer
class_name Battle

const BattleArenaResource = preload("res://battle_arena.gd")
const MonsterResource = preload("res://monster.gd")
const BattleRulesResource = preload("res://battle_rules.gd")
const BATTLE_BAG_CATEGORIES := ["Capsules", "Medicine", "Battle Items", "Key Items", "Other"]

signal battle_started(player: Node, opponent: Node)
signal battle_ended

@onready var panel: PanelContainer = $Panel
@onready var hud: Control = $HUD
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var message_label: Label = $Panel/Margin/VBox/Message
@onready var player_name_label: Label = $HUD/PlayerInfo/VBox/Name
@onready var player_level_label: Label = $HUD/PlayerInfo/VBox/Level
@onready var player_hp_bar: ProgressBar = $HUD/PlayerInfo/VBox/HP
@onready var player_exp_bar: ProgressBar = $HUD/PlayerInfo/VBox/EXP
@onready var opponent_name_label: Label = $HUD/OpponentInfo/VBox/Name
@onready var opponent_level_label: Label = $HUD/OpponentInfo/VBox/Level
@onready var opponent_hp_bar: ProgressBar = $HUD/OpponentInfo/VBox/HP
@onready var action_message_label: Label = $HUD/ActionPanel/VBox/ActionMessage
@onready var transition_root: Control = $Transition
@onready var transition: ColorRect = $Transition/ColorRect
@onready var opening_label: Label = $Transition/OpeningLabel
@onready var fight_button: Button = $HUD/ActionPanel/VBox/Buttons/Fight
@onready var bag_button: Button = $HUD/ActionPanel/VBox/Buttons/Bag
@onready var pokemon_button: Button = $HUD/ActionPanel/VBox/Buttons/Pokemon
@onready var run_button: Button = $HUD/ActionPanel/VBox/Buttons/Run
@onready var move_buttons: Array[Button] = [
	$HUD/ActionPanel/VBox/MoveMenu/Move1,
	$HUD/ActionPanel/VBox/MoveMenu/Move2,
	$HUD/ActionPanel/VBox/MoveMenu/Move3,
	$HUD/ActionPanel/VBox/MoveMenu/Move4
]
@onready var back_button: Button = $HUD/ActionPanel/VBox/MoveMenu/Back
@onready var bag_buttons: Array[Button] = [
	$HUD/ActionPanel/VBox/BagMenu/Item1,
	$HUD/ActionPanel/VBox/BagMenu/Item2,
	$HUD/ActionPanel/VBox/BagMenu/Item3
]
@onready var bag_back_button: Button = $HUD/ActionPanel/VBox/BagMenu/Back
@onready var bag_category_buttons: Array[Button] = [
	$HUD/ActionPanel/VBox/BagMenu/Categories/Capsules,
	$HUD/ActionPanel/VBox/BagMenu/Categories/Medicine,
	$HUD/ActionPanel/VBox/BagMenu/Categories/BattleItems,
	$HUD/ActionPanel/VBox/BagMenu/Categories/KeyItems,
	$HUD/ActionPanel/VBox/BagMenu/Categories/Other
]
@onready var switch_buttons: Array[Button] = [
	$HUD/ActionPanel/VBox/SwitchMenu/Switch1,
	$HUD/ActionPanel/VBox/SwitchMenu/Switch2,
	$HUD/ActionPanel/VBox/SwitchMenu/Switch3,
	$HUD/ActionPanel/VBox/SwitchMenu/Switch4,
	$HUD/ActionPanel/VBox/SwitchMenu/Switch5,
	$HUD/ActionPanel/VBox/SwitchMenu/Switch6
]
@onready var switch_back_button: Button = $HUD/ActionPanel/VBox/SwitchMenu/Back

var player: Node = null
var opponent: Node = null
var player_monster: Monster = null
var is_active: bool = false
var waiting_for_dialogue: bool = false
var overworld_visibility: Dictionary = {}
var opponent_monster: Monster = null
var player_hp: int = 0
var opponent_hp: int = 0
var action_locked: bool = true
var showing_moves: bool = false
var forced_switch: bool = false
var combat_hp: Dictionary = {}
var wild_battle: bool = false
var wild_monster_captured: bool = false
var selected_bag_category := "Capsules"
var pending_battle_flags: Dictionary = {}
var pre_battle_transition_active: bool = false
var trainer_roster: Array[Dictionary] = []
var trainer_roster_index := 0

func _ready() -> void:
	add_to_group("battle_manager")
	panel.visible = false
	hud.visible = false
	transition_root.visible = false
	transition.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func queue_battle_after_dialogue(player_node: Node, opponent_node: Node, flags: Dictionary = {}) -> bool:
	if is_active or waiting_for_dialogue:
		return false
	if not _player_has_pokemon(player_node):
		_show_message("You need a Pokemon in your party before battling.")
		return false

	player = player_node
	opponent = opponent_node
	wild_battle = false
	pending_battle_flags = flags.duplicate(true)
	var dialogue_manager := get_tree().get_first_node_in_group("dialogue_manager")
	if dialogue_manager != null and dialogue_manager.has_method("is_dialogue_open") and dialogue_manager.is_dialogue_open() and dialogue_manager.has_signal("dialogue_closed"):
		waiting_for_dialogue = true
		dialogue_manager.dialogue_closed.connect(_on_dialogue_closed, CONNECT_ONE_SHOT)
	else:
		start_battle()
	return true

func queue_wild_battle(player_node: Node, wild_monster: Monster) -> bool:
	if is_active:
		print("Battle: rejected wild battle because a battle is already active.")
		return false
	if waiting_for_dialogue:
		print("Battle: rejected wild battle because dialogue is still open.")
		return false
	if pre_battle_transition_active:
		print("Battle: rejected wild battle because a pre-battle transition is already active.")
		return false
	if wild_monster == null:
		print("Battle: rejected wild battle because the wild monster is null.")
		return false
	if wild_monster.profile == null:
		print("Battle: rejected wild battle because the wild monster has no profile.")
		return false
	if not _player_has_pokemon(player_node):
		print("Battle: rejected wild battle because the player has no usable Pokemon.")
		return false

	player = player_node
	opponent = null
	wild_battle = true
	wild_monster_captured = false
	pending_battle_flags.clear()
	opponent_monster = wild_monster
	_set_player_movement_locked(true)
	pre_battle_transition_active = true
	call_deferred("_run_wild_pre_battle_transition")
	return true

func _run_wild_pre_battle_transition() -> void:
	await _play_wild_pre_battle_transition()
	pre_battle_transition_active = false
	if is_active:
		return
	if opponent_monster == null or not is_instance_valid(opponent_monster):
		_set_player_movement_locked(false)
		return
	if not start_battle():
		_set_player_movement_locked(false)

func _play_wild_pre_battle_transition() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_set_player_movement_locked(false)
		return

	transition_root.visible = true
	transition.visible = true
	opening_label.visible = false

	# 1) White flash over ~0.5 seconds.
	transition.color = Color(1.0, 1.0, 1.0, 1.0)
	transition.modulate.a = 0.0
	var flash := create_tween()
	flash.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	flash.tween_property(transition, "modulate:a", 1.0, 0.08)
	flash.tween_property(transition, "modulate:a", 0.0, 0.42)
	await flash.finished

	# Preserve camera so the overworld state stays correct after the transition.
	var base_position := camera.global_position
	var base_rotation := camera.global_rotation
	var base_fov := camera.fov

	# 2) Fisheye pulse.
	var fisheye := create_tween().set_parallel(true)
	fisheye.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fisheye.tween_property(camera, "fov", clampf(base_fov + 52.0, 40.0, 120.0), 1.35)
	fisheye.tween_property(camera, "global_position", base_position + Vector3(0.0, 0.16, 0.0), 1.35)
	await fisheye.finished

	# 3) Zoom-in rush.
	var forward := -camera.global_basis.z.normalized()
	var zoom_target := base_position + forward * 2.6 + Vector3(0.0, 0.1, 0.0)
	var rush := create_tween().set_parallel(true)
	rush.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	rush.tween_property(camera, "global_position", zoom_target, 1.25)
	rush.tween_property(camera, "fov", 42.0, 1.25)
	await rush.finished

	# 4) Black cut before transport/scene switch into battle.
	transition.color = Color(0.02, 0.02, 0.02, 1.0)
	var blackout := create_tween()
	blackout.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	blackout.tween_property(transition, "modulate:a", 1.0, 0.35)
	await blackout.finished
	await get_tree().create_timer(0.65).timeout

	# Keep screen black and restore camera so post-battle view isn't warped.
	camera.global_position = base_position
	camera.global_rotation = base_rotation
	camera.fov = base_fov

func _on_dialogue_closed() -> void:
	waiting_for_dialogue = false
	start_battle()

func start_battle() -> bool:
	if is_active:
		print("Battle: start rejected because a battle is already active.")
		return false
	if not _player_has_pokemon(player):
		print("Battle: start rejected because the player has no usable Pokemon.")
		return false

	var opponent_profile: MonsterProfile = _get_initial_opponent_profile()
	if opponent_profile == null:
		print("Battle: start rejected because no opponent profile was found.")
		return false
	var party = player.get_node_or_null("Party")
	var active_monster: Monster = party.get_active_monster() if party != null else null
	if active_monster == null:
		print("Battle: start rejected because the player's active Pokemon is null.")
		return false

	is_active = true
	player.in_battle = true
	player.current_opponent = opponent
	player_monster = active_monster
	player_monster.ensure_full_health_if_uninitialized()
	if not wild_battle:
		opponent_monster = MonsterResource.new()
		opponent_monster.profile = opponent_profile
		opponent_monster.level = _get_trainer_opponent_level()
	opponent_monster.ensure_full_health_if_uninitialized()
	combat_hp.clear()
	_hide_overworld()
	panel.visible = true
	hud.visible = false
	_update_battle_hud(opponent_profile)
	action_locked = true
	var arena := get_tree().get_first_node_in_group("battle_arena") as BattleArenaResource
	if arena != null:
		arena.start_battle(player_monster, opponent_profile)
		var intro_mode := _resolve_intro_mode()
		_play_opening(arena, opponent_profile, intro_mode)
	else:
		panel.visible = false
		hud.visible = true
		action_locked = false
		_show_main_actions()
	battle_started.emit(player, opponent)
	return true

func _get_trainer_opponent_level() -> int:
	if not trainer_roster.is_empty() and trainer_roster_index < trainer_roster.size():
		return clampi(int(trainer_roster[trainer_roster_index].get("level", 5)), 1, 100)
	if opponent != null and opponent.profile != null and opponent.profile.trainer_battle != null:
		return clampi(int(opponent.profile.trainer_battle.get("opponent_level")), 1, 100)
	return 5

func _get_initial_opponent_profile() -> MonsterProfile:
	trainer_roster.clear()
	trainer_roster_index = 0
	if wild_battle:
		return opponent_monster.profile if opponent_monster != null else null
	if opponent != null and opponent.profile != null and opponent.profile.trainer_battle != null:
		var configured_roster: Array = opponent.profile.trainer_battle.get("roster")
		for entry: Dictionary in configured_roster:
			var roster_profile := entry.get("profile") as MonsterProfile
			if roster_profile != null:
				trainer_roster.append({"profile": roster_profile, "level": clampi(int(entry.get("level", 5)), 1, 100)})
		if not trainer_roster.is_empty():
			return trainer_roster[0].get("profile") as MonsterProfile
	return opponent.battle_profile if opponent != null else null

func _send_next_trainer_opponent() -> bool:
	if wild_battle or trainer_roster_index + 1 >= trainer_roster.size():
		return false
	trainer_roster_index += 1
	var entry: Dictionary = trainer_roster[trainer_roster_index]
	var next_profile := entry.get("profile") as MonsterProfile
	if next_profile == null:
		return false
	opponent_monster = MonsterResource.new()
	opponent_monster.profile = next_profile
	opponent_monster.level = clampi(int(entry.get("level", 5)), 1, 100)
	opponent_monster.ensure_full_health_if_uninitialized()
	opponent_hp = _max_hp(opponent_monster)
	combat_hp[opponent_monster] = opponent_hp
	opponent_name_label.text = next_profile.species_name
	opponent_level_label.text = "Lv. %d" % opponent_monster.level
	opponent_hp_bar.max_value = opponent_hp
	opponent_hp_bar.value = opponent_hp
	action_message_label.text = "%s sent out %s!" % [opponent.npc_name, next_profile.species_name]
	var arena := get_tree().get_first_node_in_group("battle_arena") as BattleArenaResource
	if arena != null:
		arena.start_battle(player_monster, next_profile)
	await get_tree().create_timer(0.8).timeout
	return true

func _play_opening(arena: BattleArenaResource, opponent_profile: MonsterProfile, intro_mode: String = "trainer") -> void:
	transition_root.visible = true
	transition.visible = true
	opening_label.visible = true
	opening_label.text = "A wild %s appeared!" % opponent_profile.species_name if wild_battle else "%s wants to battle!" % (opponent.npc_name if opponent != null else "Opponent")
	if wild_battle:
		# Pre-battle cinematic already ran and left the screen black.
		transition.color = Color(0.02, 0.02, 0.02, 1.0)
		transition.modulate.a = 1.0
		await get_tree().create_timer(0.65).timeout
		opening_label.visible = false
		var reveal := create_tween()
		reveal.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		reveal.tween_property(transition, "modulate:a", 0.0, 0.28)
		await reveal.finished
		await arena.play_opening(player_monster, opponent_profile)
	elif intro_mode == "standard":
		transition.modulate.a = 0.0
		await arena.play_opening(player_monster, opponent_profile)
	else:
		transition.modulate.a = 0.0
		await arena.play_trainer_opening(player_monster, opponent_profile)
	var fade := create_tween()
	fade.tween_property(transition, "modulate:a", 0.0, 0.3)
	await fade.finished
	transition_root.visible = false
	transition.visible = false
	opening_label.visible = false
	panel.visible = false
	hud.visible = true
	action_locked = false
	_show_main_actions()

func end_battle() -> void:
	if wild_battle and not wild_monster_captured and is_instance_valid(opponent_monster):
		opponent_monster.queue_free()
	if player != null:
		var party = player.get_node_or_null("Party")
		if party != null and party.has_method("restore_all_health"):
			party.restore_all_health()
		player.in_battle = false
		player.current_opponent = null
	var arena := get_tree().get_first_node_in_group("battle_arena") as BattleArenaResource
	if arena != null:
		arena.end_battle()
	is_active = false
	waiting_for_dialogue = false
	panel.visible = false
	hud.visible = false
	transition_root.visible = false
	transition.visible = false
	opening_label.visible = false
	opponent_monster = null
	combat_hp.clear()
	forced_switch = false
	wild_battle = false
	wild_monster_captured = false
	action_locked = true
	pending_battle_flags.clear()
	_set_player_movement_locked(false)
	_restore_overworld()
	battle_ended.emit()

func _set_player_movement_locked(locked: bool) -> void:
	if player == null:
		return
	player.in_battle = locked
	if not locked:
		player.current_opponent = null

func _hide_overworld() -> void:
	overworld_visibility.clear()
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var dialogue_manager := get_tree().get_first_node_in_group("dialogue_manager")
	if dialogue_manager != null and dialogue_manager.has_method("hide_dialogue"):
		dialogue_manager.hide_dialogue()

	for child in scene_root.get_children():
		if child == self or child.is_in_group("battle_arena"):
			continue
		if child is Node3D or child is CanvasItem:
			overworld_visibility[child] = child.visible
			child.visible = false

func _restore_overworld() -> void:
	for node in overworld_visibility:
		if is_instance_valid(node):
			node.visible = overworld_visibility[node]
	overworld_visibility.clear()

func _update_battle_hud(opponent_profile: MonsterProfile) -> void:
	var opponent_name := opponent_profile.species_name if opponent_profile != null else "Opponent Pokemon"
	var opponent_level := opponent_monster.level if opponent_monster != null else 5
	player_hp = clampi(player_monster.current_hp, 0, _max_hp(player_monster))
	opponent_hp = _max_hp(opponent_monster)
	if wild_battle:
		opponent_monster.current_hp = opponent_hp
	combat_hp[player_monster] = player_hp
	combat_hp[opponent_monster] = opponent_hp
	player_name_label.text = player_monster.get_species_name()
	player_level_label.text = "Lv. %d" % player_monster.level
	player_hp_bar.max_value = _max_hp(player_monster)
	player_hp_bar.value = player_hp
	_update_exp_bar()
	opponent_name_label.text = opponent_name
	opponent_level_label.text = "Lv. %d" % opponent_level
	opponent_hp_bar.max_value = _max_hp(opponent_monster)
	opponent_hp_bar.value = opponent_hp
	title_label.text = "Battle"
	message_label.text = "Wild %s appeared!" % opponent_name if wild_battle else "%s sent out %s!" % [
		opponent.npc_name if opponent != null else "Opponent",
		player_monster.get_species_name()
	]
	action_message_label.text = "What will %s do?" % player_monster.get_species_name()

func _on_action_pressed(action_name: String) -> void:
	if not is_active or action_locked:
		return
	match action_name:
		"Fight":
			_show_move_menu()
		"Bag":
			_show_bag_menu()
		"Pokemon":
			_try_switch_pokemon()

func _show_main_actions() -> void:
	showing_moves = false
	fight_button.visible = true
	bag_button.visible = true
	pokemon_button.visible = true
	run_button.visible = true
	for button in move_buttons:
		button.visible = false
	back_button.visible = false
	for button in bag_buttons:
		button.visible = false
	bag_back_button.visible = false
	for button in bag_category_buttons:
		button.visible = false
	for button in switch_buttons:
		button.visible = false
	switch_back_button.visible = false
	bag_button.text = "Bag"
	action_message_label.text = "What will %s do?" % player_monster.get_species_name()

func _show_bag_menu() -> void:
	showing_moves = false
	fight_button.visible = false
	bag_button.visible = false
	pokemon_button.visible = false
	run_button.visible = false
	for button in move_buttons:
		button.visible = false
	back_button.visible = false
	for button in switch_buttons:
		button.visible = false
	switch_back_button.visible = false
	bag_back_button.visible = true
	for index in bag_category_buttons.size():
		var category_button := bag_category_buttons[index]
		category_button.visible = true
		category_button.button_pressed = BATTLE_BAG_CATEGORIES[index] == selected_bag_category
	var bag = player.get_node_or_null("Bag") if player != null else null
	var item_ids: Array[String] = bag.get_item_ids_in_category(selected_bag_category) if bag != null else []
	for index in bag_buttons.size():
		var button := bag_buttons[index]
		var item_id: String = item_ids[index] if index < item_ids.size() else ""
		var quantity = bag.get_quantity(item_id) if bag != null else 0
		button.visible = index < item_ids.size()
		button.text = "%s  x%d" % [bag.get_item_name(item_id) if bag != null else item_id, quantity] if item_id != "" else ""
		button.disabled = item_id == "" or quantity <= 0 or not _is_battle_item_usable(item_id)
		button.tooltip_text = _get_battle_item_reason(item_id, quantity) if item_id != "" else "No item in this section."
	action_message_label.text = "Choose an item."

func _on_bag_category_pressed(category: String) -> void:
	if not is_active or action_locked:
		return
	selected_bag_category = category
	_show_bag_menu()

func _is_battle_item_usable(item_id: String) -> bool:
	match item_id:
		"resonance_capsule":
			return wild_battle
		"super_potion":
			return true
		_:
			return false

func _get_battle_item_reason(item_id: String, quantity: int) -> String:
	if quantity <= 0:
		return "You do not have this item."
	match item_id:
		"resonance_capsule":
			return "Resonance Capsules can only be used against wild creatures." if not wild_battle else "Deploy a Resonance Capsule."
		"super_potion":
			return "Restore up to 50 HP."
		_:
			return "This item cannot be used in battle yet."

func _on_bag_item_pressed(index: int) -> void:
	if not is_active or action_locked or index < 0:
		return
	var bag = player.get_node_or_null("Bag") if player != null else null
	var item_ids: Array[String] = bag.get_item_ids_in_category(selected_bag_category) if bag != null else []
	if index >= item_ids.size():
		return
	var item_id: String = item_ids[index]
	if not _is_battle_item_usable(item_id):
		return
	match item_id:
		"resonance_capsule":
			_try_catch()
		"super_potion":
			_use_battle_super_potion()

func _on_bag_back_pressed() -> void:
	if not is_active or action_locked:
		return
	_show_main_actions()

func _try_catch() -> void:
	if not wild_battle or opponent_monster == null:
		return
	if _get_resonance_capsule_count() <= 0:
		action_message_label.text = "You are out of Resonance Capsules."
		return
	action_locked = true
	var party = player.get_node_or_null("Party")
	_consume_resonance_capsule()
	var captured: bool = party != null and party.try_capture(opponent_monster, _calculate_catch_multiplier())
	if captured:
		opponent_monster.current_hp = opponent_hp
		wild_monster_captured = true
		action_message_label.text = "Gotcha! %s was caught." % opponent_monster.get_species_name()
		await get_tree().create_timer(0.8).timeout
		if is_active:
			end_battle()
	else:
		action_message_label.text = "The wild Pokemon broke free!"
		await get_tree().create_timer(0.6).timeout
		if is_active and opponent_hp > 0:
			await _enemy_turn()
		if is_active and player_hp > 0 and opponent_hp > 0:
			action_locked = false
			_show_main_actions()

func _get_resonance_capsule_count() -> int:
	if player == null:
		return 0
	var bag = player.get_node_or_null("Bag")
	return bag.get_quantity("resonance_capsule") if bag != null else 0

func _consume_resonance_capsule() -> void:
	var bag = player.get_node_or_null("Bag")
	if bag != null:
		bag.remove_item("resonance_capsule")

func _use_battle_super_potion() -> void:
	var bag = player.get_node_or_null("Bag")
	if bag == null or not bag.has_item("super_potion"):
		action_message_label.text = "You are out of Super Potions."
		return
	player_monster.ensure_full_health_if_uninitialized()
	var healed := mini(50, _max_hp(player_monster) - player_hp)
	if healed <= 0:
		action_message_label.text = "%s is already at full health." % player_monster.get_species_name()
		return
	if not bag.remove_item("super_potion"):
		return
	action_locked = true
	player_hp += healed
	player_monster.current_hp = player_hp
	await _animate_hp_bar(player_hp_bar, player_hp)
	combat_hp[player_monster] = player_hp
	action_message_label.text = "%s recovered %d HP." % [player_monster.get_species_name(), healed]
	await get_tree().create_timer(0.5).timeout
	if is_active and opponent_hp > 0:
		await _enemy_turn()
	if is_active and player_hp > 0 and opponent_hp > 0:
		action_locked = false
		_show_main_actions()

func _calculate_catch_multiplier() -> float:
	var maximum_hp := _max_hp(opponent_monster)
	var current_hp := clampi(opponent_hp, 1, maximum_hp)
	var health_factor := (3.0 * maximum_hp - 2.0 * current_hp) / (3.0 * maximum_hp)
	return clampf(health_factor, 0.1, 1.0)

func _show_move_menu() -> void:
	showing_moves = true
	fight_button.visible = false
	bag_button.visible = false
	pokemon_button.visible = false
	run_button.visible = false
	back_button.visible = true
	for button in bag_buttons:
		button.visible = false
	bag_back_button.visible = false
	for button in bag_category_buttons:
		button.visible = false
	var moves := _get_battle_moves(player_monster)
	for index in move_buttons.size():
		var button := move_buttons[index]
		button.visible = index < moves.size()
		if index < moves.size():
			var move: MonsterMove = moves[index]
			button.text = "%s  %d/%d" % [move.move_name, player_monster.get_move_pp(move), move.maximum_pp]
			button.disabled = player_monster.get_move_pp(move) <= 0
		else:
			button.text = ""
			button.disabled = true
	if moves.is_empty():
		action_message_label.text = "No moves learned."
	else:
		action_message_label.text = "Choose a move."

func _on_back_pressed() -> void:
	if not is_active or action_locked:
		return
	_show_main_actions()

func _on_move_pressed(index: int) -> void:
	if not is_active or action_locked:
		return
	var moves := _get_battle_moves(player_monster)
	if index < 0 or index >= moves.size():
		return
	action_locked = true
	var move: MonsterMove = moves[index]
	if not player_monster.consume_move_pp(move):
		action_locked = false
		_show_move_menu()
		return
	var enemy_move := _choose_enemy_move()
	var enemy_first := enemy_move != null and _should_move_first(enemy_move, move)
	var arena := get_tree().get_first_node_in_group("battle_arena") as BattleArenaResource
	if enemy_first:
		await _enemy_turn(enemy_move)
		if opponent_hp > 0 and player_hp > 0:
			if arena != null:
				await arena.play_between_turn_sway()
			await _use_move(player_monster, opponent_monster, move, true)
	else:
		await _use_move(player_monster, opponent_monster, move, true)
		if opponent_hp > 0 and player_hp > 0 and enemy_move != null:
			if arena != null:
				await arena.play_between_turn_sway()
			await _enemy_turn(enemy_move)
	if is_active and player_hp > 0 and opponent_hp > 0:
		await _apply_end_turn_status()
	if is_active and player_hp > 0 and opponent_hp > 0:
		action_locked = false
		_show_main_actions()

func _use_move(attacker: Monster, defender: Monster, move: MonsterMove, player_attacking: bool) -> void:
	if not attacker.can_act_this_turn():
		action_message_label.text = "%s is unable to move!" % attacker.get_species_name()
		await get_tree().create_timer(0.5).timeout
		return
	var arena := get_tree().get_first_node_in_group("battle_arena") as BattleArenaResource
	if arena != null:
		await _apply_move_action_flags(arena, move, player_attacking)
		await arena.play_attack(player_attacking)
	if move.accuracy < 100 and randi_range(1, 100) > move.accuracy:
		action_message_label.text = "%s used %s, but it missed!" % [attacker.get_species_name(), move.move_name]
		await get_tree().create_timer(0.5).timeout
		return

	var damage_multiplier := BattleRulesResource.damage_multiplier(move.type_id, attacker.get_types(), defender.get_types())
	var damage := _calculate_damage(attacker, defender, move, damage_multiplier)
	if player_attacking:
		opponent_hp = maxi(0, opponent_hp - damage)
		await _animate_hp_bar(opponent_hp_bar, opponent_hp)
	else:
		player_hp = maxi(0, player_hp - damage)
		await _animate_hp_bar(player_hp_bar, player_hp)
		player_monster.current_hp = player_hp
		combat_hp[player_monster] = player_hp
	if arena != null and ((player_attacking and opponent_hp <= _max_hp(opponent_monster) * 0.25) or (not player_attacking and player_hp <= _max_hp(player_monster) * 0.25)):
		await arena.focus_on_monster(not player_attacking)
	var effectiveness_message := ""
	var effectiveness := BattleRulesResource.type_effectiveness(move.type_id, defender.get_types())
	if effectiveness == 0.0:
		effectiveness_message = " It had no effect."
	elif effectiveness > 1.0:
		effectiveness_message = " It's super effective!"
	elif effectiveness < 1.0:
		effectiveness_message = " It's not very effective."
	var status_message := _try_apply_move_status(defender, move)
	action_message_label.text = "%s used %s! %d damage.%s%s" % [attacker.get_species_name(), move.move_name, damage, effectiveness_message, status_message]
	await get_tree().create_timer(0.65).timeout
	if opponent_hp <= 0:
		if arena != null:
			await arena.play_faint(false)
		await _grant_battle_experience()
		if await _send_next_trainer_opponent():
			action_locked = false
			_show_main_actions()
		else:
			_finish_battle("%s fainted! You won the battle." % opponent_monster.get_species_name())
	elif player_hp <= 0:
		if arena != null:
			await arena.play_faint(true)
		_handle_player_faint()

func _resolve_intro_mode() -> String:
	if wild_battle:
		return "wild"
	if pending_battle_flags.has("intro_mode"):
		return String(pending_battle_flags.get("intro_mode", "trainer")).to_lower()
	if pending_battle_flags.has("intro_standard"):
		return "standard"
	if pending_battle_flags.has("intro_trainer") or pending_battle_flags.has("intro_gym"):
		return "trainer"
	return "trainer"

func _apply_move_action_flags(arena: BattleArenaResource, move: MonsterMove, player_attacking: bool) -> void:
	if move == null:
		return
	if move.has_action_flag("camera_zoom_enemy"):
		await arena.focus_on_monster(not player_attacking)
	if move.has_action_flag("camera_zoom_self"):
		await arena.focus_on_monster(player_attacking)
	if move.has_action_flag("camera_wide"):
		await arena.focus_wide()

func _enemy_turn(move: MonsterMove = null) -> void:
	if move == null:
		move = _choose_enemy_move()
	if move == null:
		return
	opponent_monster.consume_move_pp(move)
	await _use_move(opponent_monster, player_monster, move, false)

func _choose_enemy_move() -> MonsterMove:
	var moves := _get_usable_battle_moves(opponent_monster)
	if moves.is_empty():
		return _get_battle_moves(opponent_monster)[0]
	if wild_battle:
		return moves[randi_range(0, moves.size() - 1)]
	var best_score := -INF
	var best_moves: Array[MonsterMove] = []
	for move in moves:
		var score := _score_enemy_move(move)
		if score > best_score:
			best_score = score
			best_moves.clear()
			best_moves.append(move)
		elif is_equal_approx(score, best_score):
			best_moves.append(move)
	if not best_moves.is_empty():
		return best_moves[randi_range(0, best_moves.size() - 1)]
	return moves[randi_range(0, moves.size() - 1)]

func _score_enemy_move(move: MonsterMove) -> float:
	var score := float(maxi(move.power, 20))
	if move.category == "Status":
		score = 20.0 if opponent_monster.status_condition == "" and move.status_effect != "None" else 1.0
	else:
		var effectiveness := BattleRulesResource.type_effectiveness(move.type_id, player_monster.get_types())
		var stab := 1.5 if BattleRulesResource.has_stab(move.type_id, opponent_monster.get_types()) else 1.0
		score *= effectiveness * stab
	if move.priority > 0:
		score += move.priority * 30.0
	if player_hp <= _max_hp(player_monster) / 4.0:
		score += 25.0
	return score

func _should_move_first(enemy_move: MonsterMove, player_move: MonsterMove) -> bool:
	if enemy_move.priority != player_move.priority:
		return enemy_move.priority > player_move.priority
	var enemy_speed := _effective_speed(opponent_monster)
	var player_speed := _effective_speed(player_monster)
	if enemy_speed != player_speed:
		return enemy_speed > player_speed
	return randf() < 0.5

func _effective_speed(monster: Monster) -> int:
	var speed := monster.get_calculated_stat("speed")
	if monster.status_condition == "Paralysis":
		speed = floori(speed * 0.25)
	return maxi(1, speed)

func _try_apply_move_status(defender: Monster, move: MonsterMove) -> String:
	if move.status_effect == "None" or move.status_chance <= 0 or randf_range(1.0, 100.0) > move.status_chance:
		return ""
	if defender.apply_status(move.status_effect):
		return " %s was afflicted with %s!" % [defender.get_species_name(), move.status_effect]
	return ""

func _apply_end_turn_status() -> void:
	var player_status_damage := player_monster.end_turn_status_damage()
	var opponent_status_damage := opponent_monster.end_turn_status_damage()
	if player_status_damage > 0:
		player_hp = maxi(0, player_hp - player_status_damage)
		await _animate_hp_bar(player_hp_bar, player_hp)
		combat_hp[player_monster] = player_hp
		action_message_label.text = "%s was hurt by %s." % [player_monster.get_species_name(), player_monster.status_condition]
		await get_tree().create_timer(0.35).timeout
	if opponent_status_damage > 0:
		opponent_hp = maxi(0, opponent_hp - opponent_status_damage)
		await _animate_hp_bar(opponent_hp_bar, opponent_hp)
		action_message_label.text = "%s was hurt by %s." % [opponent_monster.get_species_name(), opponent_monster.status_condition]
		await get_tree().create_timer(0.35).timeout
	if opponent_hp <= 0:
		if await _send_next_trainer_opponent():
			action_locked = false
			_show_main_actions()
		else:
			_finish_battle("%s fainted! You won the battle." % opponent_monster.get_species_name())
	elif player_hp <= 0:
		_handle_player_faint()

func _grant_battle_experience() -> void:
	if player_monster == null or opponent_monster == null or opponent_monster.profile == null:
		return
	var experience_reward := maxi(1, floori(float(opponent_monster.profile.base_experience_yield * opponent_monster.level) / 7.0))
	var previous_level := player_monster.level
	var levels_gained := player_monster.add_experience(experience_reward)
	await _animate_exp_bar(previous_level)
	if levels_gained > 0:
		action_message_label.text = "%s gained %d Exp. Points and reached Lv. %d!" % [player_monster.get_species_name(), experience_reward, player_monster.level]
		await get_tree().create_timer(0.8).timeout
	await _try_evolve_player_monster()

func _try_evolve_player_monster() -> void:
	for evolution in player_monster.get_evolutions():
		if evolution == null or not player_monster.can_evolve(evolution) or evolution.method != "Level":
			continue
		var target_path := "res://monsters/%s.tres" % evolution.target_species_id
		if not ResourceLoader.exists(target_path):
			continue
		var target_profile := load(target_path) as MonsterProfile
		if target_profile == null:
			continue
		var old_name := player_monster.get_species_name()
		player_monster.profile = target_profile
		player_monster._apply_profile_visuals()
		action_message_label.text = "%s evolved into %s!" % [old_name, target_profile.species_name]
		await get_tree().create_timer(1.0).timeout
		return

func _get_battle_moves(monster: Monster) -> Array[MonsterMove]:
	var moves := monster.get_moves_for_level()
	if not moves.is_empty():
		return moves
	var fallback := MonsterMove.new()
	fallback.move_id = "struggle"
	fallback.move_name = "Struggle"
	fallback.power = 40
	fallback.accuracy = 100
	return [fallback]

func _get_usable_battle_moves(monster: Monster) -> Array[MonsterMove]:
	var usable_moves: Array[MonsterMove] = []
	for move in monster.get_moves_for_level():
		if monster.get_move_pp(move) > 0:
			usable_moves.append(move)
	return usable_moves

func _calculate_damage(attacker: Monster, defender: Monster, move: MonsterMove, damage_multiplier: float = 1.0) -> int:
	if damage_multiplier <= 0.0 or move.category == "Status":
		return 0
	var power := maxi(move.power, 20)
	var attack_stat := attacker.get_calculated_stat("special_attack" if move.category == "Special" else "attack")
	var defense_stat := defender.get_calculated_stat("special_defense" if move.category == "Special" else "defense")
	if move.category == "Physical" and attacker.status_condition == "Burn":
		attack_stat = maxi(1, floori(attack_stat * 0.5))
	var level_factor := (2.0 * attacker.level / 5.0) + 2.0
	var raw_damage := (((level_factor * power * attack_stat / defense_stat) / 50.0) + 2.0)
	return maxi(1, roundi(raw_damage * damage_multiplier * randf_range(0.85, 1.0)))

func _max_hp(monster: Monster) -> int:
	return monster.get_max_hp()

func _animate_hp_bar(bar: ProgressBar, target_value: int) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(bar, "value", target_value, 0.35)
	await tween.finished

func _update_exp_bar() -> void:
	if player_monster == null or player_monster.profile == null:
		return
	var current_level_exp := player_monster.profile.get_experience_for_level(player_monster.level)
	var next_level_exp := player_monster.profile.get_experience_for_level(mini(player_monster.level + 1, player_monster.profile.max_level))
	player_exp_bar.max_value = maxi(1, next_level_exp - current_level_exp)
	player_exp_bar.value = clampi(player_monster.experience - current_level_exp, 0, int(player_exp_bar.max_value))

func _animate_exp_bar(previous_level: int) -> void:
	if player_monster == null or player_monster.profile == null:
		return
	var current_level_exp := player_monster.profile.get_experience_for_level(player_monster.level)
	var next_level_exp := player_monster.profile.get_experience_for_level(mini(player_monster.level + 1, player_monster.profile.max_level))
	var target_value := clampi(player_monster.experience - current_level_exp, 0, maxi(1, next_level_exp - current_level_exp))
	if previous_level != player_monster.level:
		player_exp_bar.value = 0
		_update_exp_bar()
		return
	player_exp_bar.max_value = maxi(1, next_level_exp - current_level_exp)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player_exp_bar, "value", target_value, 0.45)
	await tween.finished

func _show_switch_menu(force_switch: bool = false) -> void:
	forced_switch = force_switch
	action_locked = true if force_switch else action_locked
	showing_moves = false
	fight_button.visible = false
	bag_button.visible = false
	pokemon_button.visible = false
	run_button.visible = false
	for button in move_buttons:
		button.visible = false
	for button in bag_buttons:
		button.visible = false
	bag_back_button.visible = false
	for button in bag_category_buttons:
		button.visible = false
	for index in switch_buttons.size():
		var button := switch_buttons[index]
		var party = player.get_node_or_null("Party")
		var member: Monster = party.members[index] if party != null and index < party.members.size() else null
		var usable := member != null and member != player_monster and int(combat_hp.get(member, _max_hp(member))) > 0
		button.visible = member != null
		button.disabled = not usable
		button.text = "%s Lv. %d" % [member.get_species_name(), member.level] if member != null else ""
	switch_back_button.visible = not force_switch
	action_message_label.text = "Choose a Pokemon to send out."

func _on_switch_pressed(index: int) -> void:
	if not is_active:
		return
	var party = player.get_node_or_null("Party")
	if party == null or index < 0 or index >= party.members.size():
		return
	var selected: Monster = party.members[index]
	if selected == player_monster or int(combat_hp.get(selected, _max_hp(selected))) <= 0:
		return
	_switch_to(selected, index)

func _switch_to(selected: Monster, member_index: int) -> void:
	var was_forced_switch := forced_switch
	party_set_active(member_index)
	player_monster = selected
	player_hp = int(combat_hp.get(selected, _max_hp(selected)))
	selected.ensure_full_health_if_uninitialized()
	player_hp = clampi(selected.current_hp, 0, _max_hp(selected)) if combat_hp.has(selected) else selected.current_hp
	player_hp_bar.max_value = _max_hp(player_monster)
	player_hp_bar.value = player_hp
	player_name_label.text = player_monster.get_species_name()
	player_level_label.text = "Lv. %d" % player_monster.level
	action_message_label.text = "Go, %s!" % player_monster.get_species_name()
	forced_switch = false
	await get_tree().create_timer(0.5).timeout
	if not was_forced_switch and is_active and opponent_hp > 0:
		action_locked = true
		await _enemy_turn()
	if is_active and player_hp > 0:
		action_locked = false
		_show_main_actions()

func party_set_active(member_index: int) -> void:
	var party = player.get_node_or_null("Party")
	if party != null:
		party.set_active_index(member_index)

func _handle_player_faint() -> void:
	var party = player.get_node_or_null("Party")
	var has_usable := false
	if party != null:
		for member in party.members:
			if member != player_monster and int(combat_hp.get(member, _max_hp(member))) > 0:
				has_usable = true
				break
	if not has_usable:
		_finish_battle("All of your Pokemon fainted. You lost the battle.")
		return
	_action_message_for_faint()
	_show_switch_menu(true)

func _action_message_for_faint() -> void:
	action_message_label.text = "%s fainted! Choose another Pokemon." % player_monster.get_species_name()

func _on_switch_back_pressed() -> void:
	if not forced_switch and is_active:
		action_locked = false
		_show_main_actions()

func _try_switch_pokemon() -> void:
	_show_switch_menu(false)

func _finish_battle(message: String) -> void:
	action_message_label.text = message
	action_locked = true
	await get_tree().create_timer(1.2).timeout
	if is_active:
		end_battle()

func _unhandled_input(event: InputEvent) -> void:
	if is_active and event.is_action_pressed("ui_cancel"):
		end_battle()

func _player_has_pokemon(player_node: Node) -> bool:
	if player_node == null:
		return false
	var party = player_node.get_node_or_null("Party")
	return party != null and not party.is_empty() and party.get_active_monster() != null

func _show_message(message: String) -> void:
	panel.visible = true
	title_label.text = "Cannot Battle"
	message_label.text = message
	await get_tree().create_timer(2.0).timeout
	if not is_active:
		panel.visible = false
