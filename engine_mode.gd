extends Node

signal mode_changed(is_project_mode: bool)

var project_mode: bool = false

func set_project_mode(value: bool) -> void:
	if project_mode == value:
		return
	project_mode = value
	mode_changed.emit(project_mode)

func is_project_mode() -> bool:
	return project_mode