extends Resource
class_name WildEncounterEntry

@export var monster_profile: MonsterProfile
@export_range(1, 100) var minimum_level: int = 2
@export_range(1, 100) var maximum_level: int = 5
@export_range(0.0, 100.0, 0.1) var spawn_rate: float = 1.0