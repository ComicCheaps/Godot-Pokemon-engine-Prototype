extends Node3D
class_name BattleArena

const BattlePlatformScene = preload("res://BattlePlatBase.glb")
const ResonanceCapsuleTexture = preload("res://assets/Capsules/Resonance Capsule.png")

@export_enum("Default", "Gym", "Grass", "Cave") var area_theme: String = "Default"
@export var platform_scale: Vector3 = Vector3(1.0, 0.1, 1.0)
@export var hybrid_presentation_enabled := true

enum CameraState { WIDE, INTRO, PLAYER_CLOSE, OPPONENT_CLOSE }

@onready var arena_floor: MeshInstance3D = $ArenaFloor
@onready var player_platform: Node3D = $PlayerPlatform
@onready var opponent_platform: Node3D = $OpponentPlatform
@onready var player_sprite: AnimatedSprite3D = $PlayerPokemon
@onready var opponent_sprite: AnimatedSprite3D = $OpponentPokemon
@onready var player_shadow: AnimatedSprite3D = $PlayerPokemonShadow
@onready var opponent_shadow: AnimatedSprite3D = $OpponentPokemonShadow
@onready var arena_camera: Camera3D = $BattleCamera
var previous_camera: Camera3D = null
var camera_state: CameraState = CameraState.WIDE
var camera_base_position := Vector3(0, 7.2, 14.0)
var camera_base_target := Vector3(0, 0.8, 0)
var environment_time := 0.0
var environment_tween: Tween
var player_platform_base_scale := Vector3.ONE
var opponent_platform_base_scale := Vector3.ONE

func _ready() -> void:
	add_to_group("battle_arena")
	_install_battle_platforms()
	visible = false
	arena_camera.current = false
	arena_camera.process_mode = Node.PROCESS_MODE_DISABLED
	_apply_area_theme()
	var battle_settings := get_node_or_null("/root/BattleSettings")
	if battle_settings != null:
		battle_settings.apply_to_arena(self)

func start_battle(player_monster: Monster, opponent_profile: MonsterProfile) -> void:
	_apply_monster_sprite(player_sprite, player_shadow, player_monster.profile if player_monster != null else null)
	_apply_monster_sprite(opponent_sprite, opponent_shadow, opponent_profile)
	player_platform_base_scale = _get_platform_scale(player_monster.profile if player_monster != null else null)
	opponent_platform_base_scale = _get_platform_scale(opponent_profile)
	player_platform.scale = player_platform_base_scale
	opponent_platform.scale = opponent_platform_base_scale
	previous_camera = get_viewport().get_camera_3d()
	_set_wide_camera()
	visible = true
	arena_camera.process_mode = Node.PROCESS_MODE_INHERIT
	arena_camera.current = true
	camera_state = CameraState.INTRO
	_start_environment_loop()

func play_opening(player_monster: Monster, opponent_profile: MonsterProfile) -> void:
	await _play_signature_opening(player_monster, opponent_profile)

func play_wild_encounter_cinematic() -> void:
	var target := Vector3(0.0, 1.0, 0.0)
	var fisheye_position := camera_base_position + Vector3(0.0, 0.35, 0.25)
	var fisheye_transform := Transform3D(Basis(), fisheye_position).looking_at(target, Vector3.UP)
	var fisheye := create_tween().set_parallel(true)
	fisheye.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fisheye.tween_property(arena_camera, "position", fisheye_position, 0.18)
	fisheye.tween_property(arena_camera, "rotation", fisheye_transform.basis.get_euler(), 0.18)
	fisheye.tween_property(arena_camera, "fov", 112.0, 0.18)
	await fisheye.finished

	var zoom_position := Vector3(0.0, 2.25, 3.45)
	var zoom_transform := Transform3D(Basis(), zoom_position).looking_at(target, Vector3.UP)
	var zoom := create_tween().set_parallel(true)
	zoom.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	zoom.tween_property(arena_camera, "position", zoom_position, 0.26)
	zoom.tween_property(arena_camera, "rotation", zoom_transform.basis.get_euler(), 0.26)
	zoom.tween_property(arena_camera, "fov", 42.0, 0.26)
	await zoom.finished

	_set_wide_camera()

func play_trainer_opening(player_monster: Monster, opponent_profile: MonsterProfile) -> void:
	await _play_signature_opening(player_monster, opponent_profile)

func play_between_turn_sway(duration: float = 0.26, amplitude: float = 0.2) -> void:
	if not hybrid_presentation_enabled:
		return
	var base_position := arena_camera.position
	var base_rotation := arena_camera.rotation
	var side := arena_camera.global_basis.x.normalized()
	var sway_target := base_position + side * amplitude
	var sway := create_tween().set_parallel(true)
	sway.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(arena_camera, "position", sway_target, duration * 0.5)
	sway.tween_property(arena_camera, "fov", arena_camera.fov + 1.8, duration * 0.5)
	await sway.finished
	var sway_back := create_tween().set_parallel(true)
	sway_back.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway_back.tween_property(arena_camera, "position", base_position, duration * 0.5)
	sway_back.tween_property(arena_camera, "rotation", base_rotation, duration * 0.5)
	sway_back.tween_property(arena_camera, "fov", 55.0 if camera_state == CameraState.WIDE else arena_camera.fov - 1.8, duration * 0.5)
	await sway_back.finished

func play_attack(player_attacking: bool) -> void:
	var sprite := player_sprite if player_attacking else opponent_sprite
	var origin := sprite.position
	var direction := Vector3(0, 0, -0.45) if player_attacking else Vector3(0, 0, 0.45)
	var attack_tween := create_tween()
	attack_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	attack_tween.tween_property(sprite, "position", origin + direction, 0.1)
	attack_tween.tween_property(sprite, "position", origin, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await attack_tween.finished
	if hybrid_presentation_enabled:
		await _play_hit_particles(opponent_sprite if player_attacking else player_sprite, Color(1.0, 0.82, 0.3, 0.95))

func focus_on_monster(player_focused: bool) -> void:
	if not hybrid_presentation_enabled:
		return
	var target_position := Vector3(-4.8, 2.35, 5.8) if player_focused else Vector3(3.8, 2.5, 4.5)
	var target := Vector3(0.7, 1.0, -0.35) if player_focused else Vector3(-0.6, 1.0, 0.2)
	var close_transform := Transform3D(Basis(), target_position).looking_at(target, Vector3.UP)
	var focus := create_tween().set_parallel(true)
	focus.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	focus.tween_property(arena_camera, "position", target_position, 0.35)
	focus.tween_property(arena_camera, "rotation", close_transform.basis.get_euler(), 0.35)
	focus.tween_property(player_platform, "scale", player_platform_base_scale * (1.08 if player_focused else 0.94), 0.35)
	focus.tween_property(opponent_platform, "scale", opponent_platform_base_scale * (0.94 if player_focused else 1.08), 0.35)
	camera_state = CameraState.PLAYER_CLOSE if player_focused else CameraState.OPPONENT_CLOSE
	await focus.finished

func focus_wide(duration: float = 0.35) -> void:
	var wide_transform := Transform3D(Basis(), camera_base_position).looking_at(camera_base_target, Vector3.UP)
	if not hybrid_presentation_enabled:
		_set_wide_camera()
		return
	var focus := create_tween().set_parallel(true)
	focus.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	focus.tween_property(arena_camera, "position", camera_base_position, duration)
	focus.tween_property(arena_camera, "rotation", wide_transform.basis.get_euler(), duration)
	focus.tween_property(arena_camera, "fov", 55.0, duration)
	focus.tween_property(player_platform, "scale", player_platform_base_scale, duration)
	focus.tween_property(opponent_platform, "scale", opponent_platform_base_scale, duration)
	camera_state = CameraState.WIDE
	await focus.finished

func play_faint(player_fainted: bool) -> void:
	var sprite := player_sprite if player_fainted else opponent_sprite
	var shadow := player_shadow if player_fainted else opponent_shadow
	var fade := create_tween().set_parallel(true)
	fade.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade.tween_property(sprite, "position:y", sprite.position.y - 0.35, 0.35)
	fade.tween_property(sprite, "modulate:a", 0.0, 0.35)
	fade.tween_property(shadow, "modulate:a", 0.0, 0.35)
	await fade.finished

func _set_wide_camera() -> void:
	arena_camera.position = camera_base_position
	arena_camera.look_at(camera_base_target, Vector3.UP)
	arena_camera.fov = 55.0
	player_platform.scale = player_platform_base_scale
	opponent_platform.scale = opponent_platform_base_scale
	camera_state = CameraState.WIDE

func _play_intro_pan() -> void:
	var intro_targets := [Vector3(-2.0, 3.8, 8.0), Vector3(2.0, 3.5, 6.5), camera_base_position]
	var intro_look_at := [Vector3(-1.5, 0.9, 0.5), Vector3(1.5, 0.9, -0.5), camera_base_target]
	for index in intro_targets.size():
		var intro_transform := Transform3D(Basis(), intro_targets[index]).looking_at(intro_look_at[index], Vector3.UP)
		var pan := create_tween().set_parallel(true)
		pan.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		pan.tween_property(arena_camera, "position", intro_targets[index], 0.22)
		pan.tween_property(arena_camera, "rotation", intro_transform.basis.get_euler(), 0.22)
		pan.tween_property(arena_camera, "fov", 48.0 if index < 2 else 55.0, 0.22)
		await pan.finished

func _play_signature_opening(player_monster: Monster, opponent_profile: MonsterProfile) -> void:
	if not hybrid_presentation_enabled:
		await _play_simple_opening(player_monster, opponent_profile)
		return
	player_sprite.visible = false
	opponent_sprite.visible = false
	player_shadow.visible = false
	opponent_shadow.visible = false

	# 1) Camera starts by framing the enemy platform.
	var enemy_focus_position := Vector3(5.0, 2.45, -5.55)
	var enemy_focus_target := Vector3(0.45, 1.0, -0.2)
	var enemy_transform := Transform3D(Basis(), enemy_focus_position).looking_at(enemy_focus_target, Vector3.UP)
	arena_camera.position = enemy_focus_position
	arena_camera.rotation = enemy_transform.basis.get_euler()
	arena_camera.fov = 42.0
	camera_state = CameraState.OPPONENT_CLOSE
	await get_tree().create_timer(0.2).timeout
	await _send_out(opponent_sprite, opponent_shadow, opponent_profile)

	# 2) Zoom out to player trainer frame (placeholder for full battle trainer sprite).
	var trainer_frame_position := Vector3(-6.2, 2.4, 6.3)
	var trainer_frame_target := Vector3(-2.2, 1.2, 1.0)
	var trainer_transform := Transform3D(Basis(), trainer_frame_position).looking_at(trainer_frame_target, Vector3.UP)
	var trainer_frame := create_tween().set_parallel(true)
	trainer_frame.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	trainer_frame.tween_property(arena_camera, "position", trainer_frame_position, 0.55)
	trainer_frame.tween_property(arena_camera, "rotation", trainer_transform.basis.get_euler(), 0.55)
	trainer_frame.tween_property(arena_camera, "fov", 49.0, 0.55)
	await trainer_frame.finished

	# 3) Player throws a resonance capsule onto the platform.
	await _throw_resonance_capsule_to_platform()

	# 4) Player monster appears from the ball, then camera settles behind it.
	await _send_out(player_sprite, player_shadow, player_monster.profile if player_monster != null else null)
	await _zoom_behind_player(0.75)
	camera_state = CameraState.PLAYER_CLOSE


func _throw_resonance_capsule_to_platform() -> void:
	var capsule := Sprite3D.new()
	capsule.texture = ResonanceCapsuleTexture
	capsule.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	capsule.pixel_size = 0.006
	capsule.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(capsule)
	var start := Vector3(-5.6, 1.85, 5.2)
	var apex := Vector3(-2.4, 3.1, 1.9)
	var impact := player_platform.global_position + Vector3(0.2, 1.2, -0.3)
	capsule.global_position = start
	var throw_tween := create_tween()
	throw_tween.tween_method(_update_capsule_arc.bind(capsule, start, apex, impact), 0.0, 1.0, 0.5)
	await throw_tween.finished
	await _play_ball_impact_flash(impact)
	capsule.queue_free()

func _update_capsule_arc(t: float, capsule: Sprite3D, start: Vector3, apex: Vector3, impact: Vector3) -> void:
	if capsule == null or not is_instance_valid(capsule):
		return
	var a := start.lerp(apex, t)
	var b := apex.lerp(impact, t)
	capsule.global_position = a.lerp(b, t)

func _play_ball_impact_flash(position: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.97, 0.8, 1.0)
	flash.light_energy = 3.2
	flash.omni_range = 4.5
	add_child(flash)
	flash.global_position = position
	var fade := create_tween()
	fade.tween_property(flash, "light_energy", 0.0, 0.16)
	await fade.finished
	flash.queue_free()

func _zoom_behind_player(duration: float = 0.65) -> void:
	var close_position := Vector3(-4.8, 2.35, 5.8)
	var target := Vector3(0.7, 1.0, -0.35)
	var close_transform := Transform3D(Basis(), close_position).looking_at(target, Vector3.UP)
	var zoom := create_tween().set_parallel(true)
	zoom.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	zoom.tween_property(arena_camera, "position", close_position, duration)
	zoom.tween_property(arena_camera, "rotation", close_transform.basis.get_euler(), duration)
	await zoom.finished

func _send_out(sprite: AnimatedSprite3D, shadow: AnimatedSprite3D, profile: MonsterProfile) -> void:
	if profile == null or profile.sprite_frames == null:
		return

	sprite.visible = true
	shadow.visible = true
	sprite.scale = Vector3.ONE * 0.35
	sprite.modulate.a = 0.0
	shadow.modulate.a = 0.0
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(sprite, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(sprite, "modulate:a", 1.0, 0.16)
	reveal.tween_property(shadow, "modulate:a", 0.4, 0.16)
	await reveal.finished
	if hybrid_presentation_enabled:
		await _shake_screen(profile.battle_size)

func _shake_screen(size_multiplier: float) -> void:
	var base_position := arena_camera.position
	var duration := 0.24
	var strength := 0.05 * clampf(size_multiplier, 0.25, 5.0)
	var elapsed := 0.0
	while elapsed < duration:
		elapsed += get_process_delta_time()
		arena_camera.position = base_position + Vector3(
			randf_range(-strength, strength),
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)
		await get_tree().process_frame
	arena_camera.position = base_position

func end_battle() -> void:
	if environment_tween != null:
		environment_tween.kill()
	visible = false
	arena_camera.current = false
	arena_camera.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(previous_camera):
		previous_camera.make_current()
	previous_camera = null

func configure_for_area(new_theme: String) -> void:
	area_theme = new_theme
	_apply_area_theme()

func configure_hybrid_presentation(enabled: bool) -> void:
	hybrid_presentation_enabled = enabled
	if not enabled and environment_tween != null:
		environment_tween.kill()

func _apply_area_theme() -> void:
	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	match area_theme:
		"Gym":
			material.albedo_color = Color("4f6678")
		"Grass":
			material.albedo_color = Color("567548")
		"Cave":
			material.albedo_color = Color("4a4055")
		_:
			material.albedo_color = Color("426b72")
	arena_floor.material_override = material

func _install_battle_platforms() -> void:
	for platform_anchor in [player_platform, opponent_platform]:
		for child in platform_anchor.get_children():
			child.queue_free()
		var platform_instance := BattlePlatformScene.instantiate() as Node3D
		if platform_instance == null:
			push_warning("BattlePlatBase.glb must have a Node3D root.")
			continue
		platform_instance.name = "BattlePlatBase"
		platform_instance.scale = platform_scale
		platform_anchor.add_child(platform_instance)

func _get_platform_scale(profile: MonsterProfile) -> Vector3:
	if profile == null or profile.weight_kg <= 0.0:
		return platform_scale
	var weight_multiplier := clampf(1.0 + profile.weight_kg / 250.0, 1.0, 4.0)
	return Vector3(platform_scale.x * weight_multiplier, platform_scale.y, platform_scale.z * weight_multiplier)

func _start_environment_loop() -> void:
	if not hybrid_presentation_enabled:
		return
	if environment_tween != null:
		environment_tween.kill()
	var target := arena_floor.material_override as StandardMaterial3D
	if target == null:
		return
	var base_color := target.albedo_color
	environment_tween = create_tween().set_loops()
	environment_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	environment_tween.tween_property(target, "albedo_color", base_color.lightened(0.08), 2.4)
	environment_tween.tween_property(target, "albedo_color", base_color, 2.4)

func _apply_monster_sprite(sprite: AnimatedSprite3D, shadow: AnimatedSprite3D, profile: MonsterProfile) -> void:
	if profile == null or profile.sprite_frames == null:
		sprite.visible = false
		shadow.visible = false
		return

	sprite.sprite_frames = profile.sprite_frames
	shadow.sprite_frames = profile.sprite_frames
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR if hybrid_presentation_enabled else BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shadow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR if hybrid_presentation_enabled else BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector3.ONE * clampf(profile.battle_size, 0.25, 5.0)
	shadow.scale = Vector3(1.2, 0.14, 0.85) * clampf(profile.battle_size, 0.5, 2.0)
	sprite.visible = true
	shadow.visible = true
	shadow.modulate = Color(0.0, 0.0, 0.0, 0.24)
	var animation_name: String = profile.default_animation
	if not sprite.sprite_frames.has_animation(animation_name):
		var animation_names := sprite.sprite_frames.get_animation_names()
		if animation_names.is_empty():
			sprite.visible = false
			shadow.visible = false
			return
		animation_name = animation_names[0]
	sprite.animation = animation_name
	shadow.animation = animation_name
	sprite.play()
	shadow.play()

func _play_hit_particles(target: AnimatedSprite3D, color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 0.32
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 2.2
	particles.gravity = Vector3(0, -2.5, 0)
	particles.position = target.position + Vector3(0, 0.8, 0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	mesh.material = material
	particles.mesh = mesh
	add_child(particles)
	await get_tree().create_timer(particles.lifetime).timeout
	particles.queue_free()

func _process(_delta: float) -> void:
	if hybrid_presentation_enabled:
		environment_time += _delta
		player_platform.rotation.y = sin(environment_time * 0.35) * 0.025
		opponent_platform.rotation.y = -sin(environment_time * 0.28) * 0.025
	_sync_shadow(player_sprite, player_shadow)
	_sync_shadow(opponent_sprite, opponent_shadow)

func _play_simple_opening(player_monster: Monster, opponent_profile: MonsterProfile) -> void:
	player_sprite.visible = false
	opponent_sprite.visible = false
	player_shadow.visible = false
	opponent_shadow.visible = false
	_set_wide_camera()
	await _send_out(opponent_sprite, opponent_shadow, opponent_profile)
	await get_tree().create_timer(0.1).timeout
	await _send_out(player_sprite, player_shadow, player_monster.profile if player_monster != null else null)

func _sync_shadow(sprite: AnimatedSprite3D, shadow: AnimatedSprite3D) -> void:
	if sprite == null or shadow == null:
		return
	shadow.animation = sprite.animation
	shadow.frame = sprite.frame
	shadow.frame_progress = sprite.frame_progress
