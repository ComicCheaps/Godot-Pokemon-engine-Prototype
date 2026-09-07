extends RefCounted
class_name NPCBehavior

func setup(_npc: NPC) -> void:
    pass

func get_lines(_npc: NPC) -> Array[String]:
    return []

func on_interact(_npc: NPC, line: String) -> Variant:
    return line

func update_behavior(_npc: NPC, _delta: float) -> void:
    pass
