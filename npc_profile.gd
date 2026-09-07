extends Resource
class_name NPCProfile

@export var npc_name: String = "NPC"
@export var dialogue: Array[String] = ["Hello there!"]
@export var dialogue_sequence: DialogueResource
@export var cutscene_sequence: Resource
@export var trainer_battle: Resource
@export var sprite_frames: SpriteFrames
@export var default_direction: Vector2 = Vector2.DOWN
@export var character_script: Script
