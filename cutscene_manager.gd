extends Node

var is_playing := false

func play(sequence: Resource, context: Node) -> void:
	if is_playing or sequence == null:
		return
	is_playing = true
	var steps: Array = sequence.get("steps")
	for step: Dictionary in steps:
		await _run_step(step, context)
	is_playing = false

func _run_step(step: Dictionary, context: Node) -> void:
	match str(step.get("type", "")):
		"dialogue":
			var resource_path := str(step.get("dialogue_path", ""))
			var dialogue := load(resource_path) as DialogueResource if not resource_path.is_empty() else null
			var dialogue_manager := get_tree().get_first_node_in_group("dialogue_manager")
			if dialogue != null and dialogue_manager != null and dialogue_manager.has_method("show_dialogue"):
				var speaker_name := dialogue.speaker_name
				if speaker_name.is_empty() and context is NPC:
					speaker_name = context.npc_name
				dialogue_manager.show_dialogue(speaker_name, dialogue.lines)
				if dialogue_manager.has_signal("dialogue_closed"):
					await dialogue_manager.dialogue_closed
		"wait":
			await get_tree().create_timer(maxf(0.0, float(step.get("seconds", 0.0)))).timeout
		"face_player":
			if context != null and context.has_method("face_player"):
				context.face_player()
		"interaction":
			if context != null and context.has_method("run_interaction_behavior"):
				context.run_interaction_behavior("")