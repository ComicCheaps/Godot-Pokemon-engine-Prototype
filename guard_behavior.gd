extends NPCBehavior
class_name GuardBehavior

func setup(npc: NPC) -> void:
    npc.npc_name = "Guard"

func get_lines(_npc: NPC) -> Array[String]:
    return [
        "No one enters the gym without a badge.",
        "The city is safe while I stand watch."
    ]

func on_interact(npc: NPC, line: String) -> Variant:
    npc.set_direction(Vector2.LEFT)
    return line
