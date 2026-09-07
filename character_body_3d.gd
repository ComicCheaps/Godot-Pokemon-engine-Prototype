extends CharacterBody3D


@export var grid_size: float = 0.5  # Size of each grid tile
@export var move_duration: float = 0.18  # Time to move one tile (seconds)
@export var sprint_duration: float = 0.09  # Time to move one tile while sprinting
@export var standing_height: float = 1.176  # Character root height on the map's base surface

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var debug_box: MeshInstance3D

var last_direction: Vector2 = Vector2.DOWN  # Track last facing direction
var last_input_vector: Vector2 = Vector2.ZERO  # Track previous frame input for tap detection
var last_animation_state: bool = false  # Track if we were walking last frame
var movement_just_started: bool = false  # Track if movement started this frame
var in_battle: bool = false  # Track if player is currently in battle
var current_opponent: Node3D = null  # Reference to current opponent NPC
var was_in_dialogue: bool = false  # Track if dialogue was open last frame
var reserved_position: Vector3  # Next cell we're moving to
var start_position: Vector3  # Where we started this movement
var elapsed_time: float = 0.0  # Time spent moving
var current_move_duration: float = 0.0  # Current move duration based on sprint
var is_moving: bool = false  # Currently in movement phase
var current_input: Vector2 = Vector2.ZERO  # Store current input for buffering
var ground_height: float = 0.0
func _ready() -> void:
	add_to_group("player")
	_configure_depth_occlusion()
	global_position.y = standing_height
	snap_to_grid()
	ground_height = standing_height
	reserved_position = global_position
	start_position = global_position
	create_debug_box()

func _configure_depth_occlusion() -> void:
	if animated_sprite == null:
		return
	# Hard alpha cut writes depth for visible pixels in the main pass and prevents grass bleed-through.
	animated_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	animated_sprite.alpha_scissor_threshold = 0.05
	animated_sprite.no_depth_test = false
	animated_sprite.render_priority = 16

func _physics_process(delta: float) -> void:
	var dialogue_manager = get_tree().get_first_node_in_group("dialogue_manager")
	var is_dialogue_open = dialogue_manager != null and dialogue_manager.has_method("is_dialogue_open") and dialogue_manager.is_dialogue_open()
	
	# Reset battle state when dialogue ends
	if was_in_dialogue and not is_dialogue_open:
		in_battle = false
		current_opponent = null
	
	was_in_dialogue = is_dialogue_open
	
	if is_dialogue_open:
		update_animation(last_direction, false, false)
		last_animation_state = false
		return
	
	if in_battle:
		update_animation(last_direction, false, false)
		last_animation_state = false
		return

	if is_moving:
		# PHASE 3: Smoothly move player
		move_to_reserved_position(delta)
		# On first frame of movement, use fast animation; after, use slower speed
		update_animation(last_direction, true, movement_just_started)
		last_animation_state = true
		movement_just_started = false  # Only true on the first frame
	else:
		# PHASE 1: Input-Check
		var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var input_pressed := false  # Track if input just started this frame
		
		if input_vector.length() > 0.01 and last_input_vector.length() <= 0.01:
			input_pressed = true  # Input transitioned from no-input to input
		
		if input_vector.length() > 0.01:
			# Remove diagonal movement - only allow cardinal directions.
			# Using the actual input direction keeps one-axis movement aligned to the grid.
			var abs_x: float = abs(input_vector.x)
			var abs_y: float = abs(input_vector.y)
			
			if abs_x > abs_y:
				input_vector = Vector2(sign(input_vector.x), 0.0)
			else:
				input_vector = Vector2(0.0, sign(input_vector.y))
			
			if input_vector != last_direction:
				# Face a new direction first; movement starts on the next input frame.
				last_direction = input_vector
				update_animation(last_direction, false, false)
				last_animation_state = false
			else:
				# PHASE 2: Check next grid cell and PHASE 3: Reserve cell
				if check_and_reserve_next_cell(input_vector):
					# Cell is valid, start moving
					start_position = global_position
					is_moving = true
					movement_just_started = true  # Mark that movement started this frame
					elapsed_time = 0.0
					current_move_duration = sprint_duration if Input.is_key_pressed(KEY_SHIFT) else move_duration
					
					update_animation(input_vector, true, true)
					last_animation_state = true
				else:
					# Cell is blocked but update animation to face direction
					# Show walk animation briefly even if blocked, to give feedback
					update_animation(input_vector, input_pressed, false)
					last_animation_state = input_pressed
		else:
			# No input - show idle animation
			update_animation(last_direction, false, false)
			last_animation_state = false
		
		last_input_vector = input_vector


func create_debug_box() -> void:
	debug_box = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(grid_size * 0.4, 0.3, grid_size * 0.4)
	debug_box.mesh = box_mesh
	debug_box.material_override = StandardMaterial3D.new()
	debug_box.material_override.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
	debug_box.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(debug_box)
	debug_box.position = Vector3(0, 0.1, 0)

func snap_to_grid() -> void:
	var snapped_pos := Vector3(
		round(global_position.x / grid_size) * grid_size,
		global_position.y,
		round(global_position.z / grid_size) * grid_size
	)
	global_position = snapped_pos

func check_and_reserve_next_cell(direction: Vector2) -> bool:
	# PHASE 2: Check next grid cell
	var next_cell := global_position + Vector3(direction.x * grid_size, 0, direction.y * grid_size)
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null and terrain_map.has_method("get_walkable_height"):
		var walkable_height: float = terrain_map.get_walkable_height(global_position, next_cell, ground_height)
		if is_nan(walkable_height):
			return false
		next_cell.y = walkable_height
	
	if is_cell_blocked(next_cell):
		return false
	
	# PHASE 3: Reserve cell
	reserved_position = next_cell
	return true

func is_cell_blocked(cell_position: Vector3) -> bool:
	var space_state = get_world_3d().direct_space_state
	if space_state == null:
		return false

	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	var player_box := collision_shape.shape as BoxShape3D
	var collider_height := player_box.size.y if player_box != null else 0.865
	box.size = Vector3(grid_size * 0.4, collider_height, grid_size * 0.4)
	query.shape = box
	query.transform = Transform3D(Basis(), cell_position + collision_shape.position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 2
	query.exclude = [self]

	var results = space_state.intersect_shape(query, 16)
	return not results.is_empty()


func move_to_reserved_position(delta: float) -> void:
	# PHASE 3: Smoothly move player
	elapsed_time += delta
	var progress: float = min(elapsed_time / current_move_duration, 1.0)
	
	global_position = start_position.lerp(reserved_position, progress)
	
	if progress >= 1.0:
		# PHASE 4: Accept next input (movement complete)
		global_position = reserved_position
		is_moving = false
		elapsed_time = 0.0


func update_animation(direction: Vector2, is_walking: bool, is_fresh_input: bool = false) -> void:
	# Determine which animation to play based on direction
	# Using absolute values to determine primary direction
	var abs_x = abs(direction.x)
	var abs_y = abs(direction.y)
	
	if abs_y > abs_x:
		# Moving primarily up or down
		if direction.y < 0:
			# Moving up
			animated_sprite.animation = &"WalkUp" if is_walking else &"IdleUp"
		else:
			# Moving down (front view)
			animated_sprite.animation = &"WalkFront" if is_walking else &"IdleFront"
	else:
		# Moving primarily left or right (side view)
		animated_sprite.animation = &"WalkSides" if is_walking else &"IdleSides"
		
		# Mirror the sprite for left/right movement (flipped)
		if direction.x < 0:
			animated_sprite.flip_h = false
		else:
			animated_sprite.flip_h = true
	
	# Adjust animation speed based on whether this is a fresh key press or continuous hold
	if is_walking:
		if is_fresh_input:
			# On key tap, play animation faster to complete during short movement
			animated_sprite.speed_scale = 1.8
		else:
			# On continuous hold, play slower for smoother movement feedback
			animated_sprite.speed_scale = 0.8
		
		# Only restart animation if transitioning to walking
		if not last_animation_state:
			animated_sprite.stop()
			animated_sprite.frame = 0
			animated_sprite.play()
		elif not animated_sprite.is_playing():
			animated_sprite.play()
	else:
		# For idle, use normal speed
		animated_sprite.speed_scale = 1.0
		if not animated_sprite.is_playing():
			animated_sprite.play()
