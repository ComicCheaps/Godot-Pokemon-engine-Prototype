extends NPCBehavior
class_name TrainerBehavior

func setup(_npc: NPC) -> void:
    pass

func get_lines(_npc: NPC) -> Array[String]:
    return []

func on_interact(npc: NPC, line: String) -> Variant:
    var battle_manager = npc.get_tree().get_first_node_in_group("battle_manager")
    if battle_manager != null and battle_manager.has_method("queue_battle_after_dialogue"):
        var flags: Dictionary = npc.get_battle_flags() if npc.has_method("get_battle_flags") else {}
        battle_manager.queue_battle_after_dialogue(npc.player, npc, flags)
    
    npc.set_direction(Vector2.RIGHT)
    return line
