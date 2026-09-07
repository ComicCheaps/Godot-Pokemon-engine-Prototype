extends Node

const BUS_MASTER := &"Master"
const BUS_STAGE := &"Stage"
const BUS_BATTLE := &"Battle"
const BUS_ITEM := &"Item"
const BUS_POKEMON := &"Pokemon"
const BUS_UI := &"UI"
const BUS_AMBIENT := &"Ambient"

const AUDIO_BUSES: PackedStringArray = [BUS_STAGE, BUS_BATTLE, BUS_ITEM, BUS_POKEMON, BUS_UI, BUS_AMBIENT]

var _music_players: Dictionary = {}
var _sfx_players: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for bus_name in AUDIO_BUSES:
		_music_players[bus_name] = _create_player(bus_name)
		_sfx_players[bus_name] = _create_player(bus_name)

func play_music(stream: AudioStream, group: StringName = BUS_STAGE, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := _get_player(_music_players, group)
	if player == null:
		return
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.play()

func stop_music(group: StringName = BUS_STAGE) -> void:
	var player := _get_player(_music_players, group)
	if player != null:
		player.stop()

func play_sfx(stream: AudioStream, group: StringName = BUS_UI, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := _get_player(_sfx_players, group)
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.play()

func set_group_volume(group: StringName, volume_db: float) -> void:
	var bus_index := AudioServer.get_bus_index(group)
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, volume_db)

func set_group_muted(group: StringName, muted: bool) -> void:
	var bus_index := AudioServer.get_bus_index(group)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, muted)

func _ensure_buses() -> void:
	for bus_name in AUDIO_BUSES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var bus_index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
		AudioServer.set_bus_send(bus_index, BUS_MASTER)

func _create_player(bus_name: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	add_child(player)
	return player

func _get_player(players: Dictionary, group: StringName) -> AudioStreamPlayer:
	var resolved_group := group if players.has(group) else BUS_UI
	return players.get(resolved_group) as AudioStreamPlayer
