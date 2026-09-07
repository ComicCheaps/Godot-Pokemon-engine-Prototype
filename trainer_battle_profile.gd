extends Resource
class_name TrainerBattleProfile

@export var display_name: String = "New Trainer Battle"
@export var opponent_profile: MonsterProfile
@export_range(1, 100) var opponent_level: int = 5
@export var roster: Array[Dictionary] = []
@export var battle_flags: PackedStringArray = ["intro_trainer"]