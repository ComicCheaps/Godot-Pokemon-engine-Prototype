extends Resource
class_name WorldObjectResource

@export var display_name: String = "World Object"
@export var object_type: String = "prop"
@export var asset_id: String = ""
@export var asset_path: String = ""
@export var tags: PackedStringArray = []
@export var properties: Dictionary = {}

func to_dictionary() -> Dictionary:
	return {
		"display_name": display_name,
		"object_type": object_type,
		"asset_id": asset_id,
		"asset_path": asset_path,
		"tags": Array(tags),
		"properties": properties.duplicate(true)
	}

static func from_dictionary(data: Dictionary) -> WorldObjectResource:
	var resource := WorldObjectResource.new()
	resource.display_name = str(data.get("display_name", "World Object"))
	resource.object_type = str(data.get("object_type", "prop"))
	resource.asset_id = str(data.get("asset_id", ""))
	resource.asset_path = str(data.get("asset_path", ""))
	var saved_tags = data.get("tags", [])
	if saved_tags is Array:
		resource.tags = PackedStringArray(saved_tags)
	var saved_properties = data.get("properties", {})
	if saved_properties is Dictionary:
		resource.properties = saved_properties.duplicate(true)
	return resource
