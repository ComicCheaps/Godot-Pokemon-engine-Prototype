extends Node
class_name ItemBag

signal inventory_changed(items: Dictionary)

## Built-in item definitions shared by every project. Project items.json files contain
## only overrides and custom item definitions, which may inherit via "template".
const DEFAULT_ITEM_DEFINITIONS := {
	"resonance_capsule": {"name": "Resonance Capsule", "category": "Capsules"},
	"potion": {"name": "Potion", "category": "Medicine"},
	"super_potion": {"name": "Super Potion", "category": "Medicine"}
}

@export var items: Dictionary = {
	"resonance_capsule": 10,
	"potion": 3
}

var _definitions: Dictionary = {}
var _project_definitions: Dictionary = {}

func _ready() -> void:
	if items.has("poke_ball"):
		items["resonance_capsule"] = int(items.get("resonance_capsule", 0)) + int(items["poke_ball"])
		items.erase("poke_ball")
	_rebuild_definitions()
	_load_project_definitions()

func define_item(item_id: String, display_name: String, category: String, template_id: String = "", metadata: Dictionary = {}) -> void:
	if item_id.is_empty():
		return
	var definition := metadata.duplicate(true)
	definition["name"] = display_name
	definition["category"] = category
	if not template_id.is_empty():
		definition["template"] = template_id
	_project_definitions[item_id] = definition
	_rebuild_definitions()
	_save_project_definitions()

func define_item_from_template(item_id: String, template_id: String, overrides: Dictionary = {}) -> void:
	if item_id.is_empty() or template_id.is_empty():
		return
	var definition := overrides.duplicate(true)
	definition["template"] = template_id
	_project_definitions[item_id] = definition
	_rebuild_definitions()
	_save_project_definitions()

func get_all_item_definitions() -> Dictionary:
	return _definitions

func _load_project_definitions() -> void:
	var pm := get_node_or_null("/root/ProjectManager")
	if pm == null:
		return
	var dir: String = pm.get_active_content_dir("items")
	if dir.is_empty():
		return
	var path := dir.path_join("items.json")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for item_id in parsed:
			if parsed[item_id] is Dictionary and parsed[item_id] != DEFAULT_ITEM_DEFINITIONS.get(item_id):
				_project_definitions[item_id] = parsed[item_id]
	_rebuild_definitions()

func _save_project_definitions() -> void:
	var pm := get_node_or_null("/root/ProjectManager")
	if pm == null:
		return
	var dir: String = pm.get_active_content_dir("items")
	if dir.is_empty():
		return
	var file := FileAccess.open(dir.path_join("items.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_project_definitions))

func _rebuild_definitions() -> void:
	_definitions.clear()
	var source_definitions := DEFAULT_ITEM_DEFINITIONS.duplicate(true)
	for item_id in _project_definitions:
		source_definitions[item_id] = _project_definitions[item_id]
	for item_id in source_definitions:
		_definitions[item_id] = _resolve_definition(item_id, source_definitions, [])

func _resolve_definition(item_id: String, source_definitions: Dictionary, resolving: Array[String]) -> Dictionary:
	if resolving.has(item_id) or not source_definitions.has(item_id):
		return {}
	var definition: Dictionary = source_definitions[item_id].duplicate(true)
	var template_id := str(definition.get("template", ""))
	definition.erase("template")
	if template_id.is_empty():
		return definition
	resolving.append(item_id)
	var resolved := _resolve_definition(template_id, source_definitions, resolving)
	resolving.pop_back()
	resolved.merge(definition, true)
	return resolved

func get_quantity(item_id: String) -> int:
	return maxi(0, int(items.get(item_id, 0)))

func has_item(item_id: String, quantity: int = 1) -> bool:
	return quantity > 0 and get_quantity(item_id) >= quantity

func add_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false
	items[item_id] = get_quantity(item_id) + quantity
	inventory_changed.emit(items)
	return true

func remove_item(item_id: String, quantity: int = 1) -> bool:
	if not has_item(item_id, quantity):
		return false
	items[item_id] = get_quantity(item_id) - quantity
	inventory_changed.emit(items)
	return true

func get_item_name(item_id: String) -> String:
	var definition: Dictionary = _definitions.get(item_id, {})
	return str(definition.get("name", item_id.capitalize()))

func get_item_category(item_id: String) -> String:
	var definition: Dictionary = _definitions.get(item_id, {})
	return str(definition.get("category", "Other"))

func get_item_ids() -> Array[String]:
	return get_item_ids_in_category("")

func get_item_ids_in_category(category: String) -> Array[String]:
	var result: Array[String] = []
	for item_id in items:
		if get_quantity(item_id) > 0 and (category.is_empty() or get_item_category(str(item_id)) == category):
			result.append(str(item_id))
	return result
