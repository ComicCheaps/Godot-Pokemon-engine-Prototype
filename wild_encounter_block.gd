@tool
extends Area3D
class_name WildEncounterBlock

const WildEncounterEntryResource = preload("res://wild_encounter_entry.gd")

@export_category("Wild Encounter")
@export var encounter_entries: Array[Resource] = []
@export_range(1, 100) var default_minimum_level: int = 2
@export_range(1, 100) var default_maximum_level: int = 5
@export_range(0.0, 100.0, 0.1) var encounter_rate_percent: float = 20.0
@export_range(0, 20) var minimum_steps_before_checks: int = 0
@export_range(1, 20) var step_check_interval: int = 1
@export var trigger_once: bool = false

@onready var encounter_visual: MeshInstance3D = $EncounterVisual

var triggered: bool = false
var player_in_block: Node3D = null
var player_overlapping: bool = false
var tracked_player_cell: Vector3 = Vector3.ZERO
var has_tracked_player_cell: bool = false
var steps_in_block: int = 0

func _ready() -> void:
	if encounter_visual != null:
		encounter_visual.visible = Engine.is_editor_hint()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var is_overlapping := player != null and _contains_player(player)
	if is_overlapping and not player_overlapping:
		player_in_block = player
		player_overlapping = true
		steps_in_block = 0
		tracked_player_cell = _get_player_cell(player)
		has_tracked_player_cell = true
		print("WildEncounterBlock: player entered by position at ", global_position)
	elif is_overlapping and player_overlapping and player_in_block != null:
		var current_cell := _get_player_cell(player_in_block)
		if not has_tracked_player_cell:
			tracked_player_cell = current_cell
			has_tracked_player_cell = true
		elif current_cell != tracked_player_cell:
			tracked_player_cell = current_cell
			steps_in_block += 1
			_try_step_encounter_roll()
	elif not is_overlapping:
		player_in_block = null
		player_overlapping = false
		has_tracked_player_cell = false
		steps_in_block = 0

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_block = body
	player_overlapping = true
	steps_in_block = 0
	tracked_player_cell = _get_player_cell(body)
	has_tracked_player_cell = true
	print("WildEncounterBlock: player entered by Area3D signal at ", global_position)

func _on_body_exited(body: Node3D) -> void:
	if body != player_in_block:
		return
	player_in_block = null
	player_overlapping = false
	has_tracked_player_cell = false
	steps_in_block = 0

func _try_step_encounter_roll() -> void:
	if triggered or player_in_block == null:
		return
	if encounter_rate_percent <= 0.0:
		return
	if steps_in_block < minimum_steps_before_checks:
		return
	if step_check_interval > 1 and ((steps_in_block - minimum_steps_before_checks) % step_check_interval) != 0:
		return
	if randf_range(0.0, 100.0) > encounter_rate_percent:
		return
	_start_wild_battle()

func _get_player_cell(player: Node3D) -> Vector3:
	var grid_size := 0.5
	if player != null:
		var value = player.get("grid_size")
		if value is float and value > 0.0:
			grid_size = value
	return Vector3(
		round(player.global_position.x / grid_size),
		0.0,
		round(player.global_position.z / grid_size)
	)

func _contains_player(player: Node3D) -> bool:
	var local_position := to_local(player.global_position)
	return abs(local_position.x) <= 0.5 and abs(local_position.z) <= 0.5

func _start_wild_battle() -> void:
	if triggered or player_in_block == null:
		return
	var entry: Resource = _choose_encounter()
	var profile: MonsterProfile = _entry_profile(entry)
	if profile == null:
		print("WildEncounterBlock: player detected, but no valid encounter profile is configured.")
		return

	var battle_manager := get_tree().get_first_node_in_group("battle_manager")
	if battle_manager == null or not battle_manager.has_method("queue_wild_battle"):
		print("WildEncounterBlock: player detected, but no battle manager was found.")
		return

	triggered = true
	var wild_monster := Monster.new()
	wild_monster.profile = profile
	var minimum_level: int = _entry_level(entry, "minimum_level", default_minimum_level)
	var maximum_level: int = _entry_level(entry, "maximum_level", default_maximum_level)
	wild_monster.level = randi_range(minimum_level, maxi(minimum_level, maximum_level))
	var started: bool = battle_manager.queue_wild_battle(player_in_block, wild_monster)
	if not started:
		triggered = false
		wild_monster.queue_free()
		print("WildEncounterBlock: battle manager rejected the wild battle.")
		return

	if not trigger_once and battle_manager.has_signal("battle_ended"):
		battle_manager.battle_ended.connect(_on_battle_ended, CONNECT_ONE_SHOT)

func _choose_encounter() -> Resource:
	var total_rate := 0.0
	for entry in encounter_entries:
		var profile: MonsterProfile = _entry_profile(entry)
		var spawn_rate: float = _entry_spawn_rate(entry)
		if profile != null and spawn_rate > 0.0:
			total_rate += spawn_rate
	if total_rate <= 0.0:
		return null

	var roll := randf_range(0.0, total_rate)
	for entry in encounter_entries:
		var profile: MonsterProfile = _entry_profile(entry)
		var spawn_rate: float = _entry_spawn_rate(entry)
		if profile == null or spawn_rate <= 0.0:
			continue
		roll -= spawn_rate
		if roll <= 0.0:
			return entry
	return encounter_entries.back()

func _entry_profile(entry: Resource) -> MonsterProfile:
	if entry == null:
		return null
	if entry.get("species_id") != null and entry.get("species_name") != null:
		return entry as MonsterProfile
	var profile = entry.get("monster_profile")
	if profile is MonsterProfile:
		return profile
	return null

func _entry_spawn_rate(entry: Resource) -> float:
	if _entry_profile(entry) != null and entry.get("spawn_rate") == null:
		return 1.0
	if entry == null or entry.get("spawn_rate") == null:
		return 0.0
	return entry.get("spawn_rate")

func _entry_level(entry: Resource, property_name: String, fallback: int) -> int:
	if _entry_profile(entry) != null and entry.get(property_name) == null:
		return fallback
	if entry == null or entry.get(property_name) == null:
		return fallback
	return int(entry.get(property_name))

func _on_battle_ended() -> void:
	triggered = false
