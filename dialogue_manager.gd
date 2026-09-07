extends CanvasLayer

signal dialogue_closed

@onready var panel: PanelContainer = PanelContainer.new()
@onready var text_box: VBoxContainer = VBoxContainer.new()
@onready var name_label: Label = Label.new()
@onready var dialogue_label: Label = Label.new()

var lines: Array[String] = []
var current_line_index: int = 0
var current_npc_name: String = ""
var is_open: bool = false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

    panel.anchor_left = 0.5
    panel.anchor_top = 1.0
    panel.anchor_right = 0.5
    panel.anchor_bottom = 1.0
    panel.offset_left = -320
    panel.offset_top = -140
    panel.offset_right = 320
    panel.offset_bottom = 0
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.visible = false

    name_label.text = ""
    name_label.add_theme_font_size_override("font_size", 18)
    name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

    dialogue_label.text = ""
    dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    dialogue_label.custom_minimum_size = Vector2(560, 0)
    dialogue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

    text_box.add_child(name_label)
    text_box.add_child(dialogue_label)
    panel.add_child(text_box)
    add_child(panel)

func _process(_delta: float) -> void:
    if not panel.visible:
        return

    if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("interact"):
        advance_dialogue()

func show_dialogue(npc_name: String, new_lines: Array[String]) -> void:
    if new_lines.is_empty():
        hide_dialogue()
        return

    if panel.visible and current_npc_name == npc_name:
        return

    current_npc_name = npc_name
    lines = new_lines
    current_line_index = 0
    is_open = true
    panel.visible = true
    update_line()

func hide_dialogue() -> void:
    if not is_open:
        return
    panel.visible = false
    is_open = false
    lines.clear()
    current_line_index = 0
    current_npc_name = ""
    dialogue_closed.emit()

func is_dialogue_open() -> bool:
    return is_open

func advance_dialogue() -> void:
    if lines.is_empty():
        hide_dialogue()
        return

    current_line_index += 1
    if current_line_index >= lines.size():
        hide_dialogue()
        return

    update_line()

    if current_line_index >= lines.size() - 1:
        name_label.text = current_npc_name
        dialogue_label.text = lines[current_line_index]

func update_line() -> void:
    if lines.is_empty():
        hide_dialogue()
        return

    name_label.text = current_npc_name
    dialogue_label.text = lines[current_line_index]
