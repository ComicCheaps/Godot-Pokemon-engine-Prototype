extends Node
class_name MonsterParty

signal party_changed
signal capture_succeeded(monster: Monster)
signal capture_failed(monster: Monster)

@export_range(1, 6) var maximum_size: int = 6
@export_range(0, 5) var active_index: int = 0

var members: Array[Monster] = []

func is_full() -> bool:
	return members.size() >= maximum_size

func is_empty() -> bool:
	return members.is_empty()

func add_monster(monster: Monster) -> bool:
	if monster == null or is_full() or members.has(monster):
		return false

	members.append(monster)
	if monster.get_parent() == null:
		add_child(monster)
	else:
		monster.reparent(self, false)
	monster.visible = false
	monster.process_mode = Node.PROCESS_MODE_DISABLED
	if members.size() == 1:
		active_index = 0
	party_changed.emit()
	return true

func try_capture(monster: Monster, catch_multiplier: float = 1.0) -> bool:
	if monster == null or monster.profile == null or is_full():
		capture_failed.emit(monster)
		return false

	var catch_chance := clampf(
		float(monster.profile.catch_rate) * maxf(catch_multiplier, 0.0) / 255.0,
		0.05,
		0.95
	)
	if randf() > catch_chance:
		capture_failed.emit(monster)
		return false

	if add_monster(monster):
		capture_succeeded.emit(monster)
		return true

	capture_failed.emit(monster)
	return false

func get_active_monster() -> Monster:
	if members.is_empty():
		return null
	active_index = clampi(active_index, 0, members.size() - 1)
	return members[active_index]

func restore_all_health() -> void:
	for member in members:
		if member == null:
			continue
		member.ensure_full_health_if_uninitialized()
		member.current_hp = member.get_max_hp()

func set_active_index(new_index: int) -> bool:
	if new_index < 0 or new_index >= members.size():
		return false
	active_index = new_index
	party_changed.emit()
	return true

func swap_members(first_index: int, second_index: int) -> bool:
	if first_index < 0 or first_index >= members.size():
		return false
	if second_index < 0 or second_index >= members.size():
		return false
	if first_index == second_index:
		return true

	var temporary := members[first_index]
	members[first_index] = members[second_index]
	members[second_index] = temporary
	party_changed.emit()
	return true

func release_monster(index: int) -> Monster:
	if index < 0 or index >= members.size():
		return null

	var released := members[index]
	members.remove_at(index)
	if released != null:
		released.reparent(get_tree().current_scene, true)
		released.visible = true
		released.process_mode = Node.PROCESS_MODE_INHERIT
	active_index = clampi(active_index, 0, maxi(members.size() - 1, 0))
	party_changed.emit()
	return released
