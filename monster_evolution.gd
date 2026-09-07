extends Resource
class_name MonsterEvolution

@export var target_species_id: String = "species_id"
@export var target_species_name: String = "New Species"
@export_enum("Level", "Item", "Trade", "Friendship", "Condition") var method: String = "Level"
@export_range(1, 100) var minimum_level: int = 16
@export var required_item: String = ""
@export_multiline var condition: String = ""
