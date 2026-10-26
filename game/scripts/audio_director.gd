class_name AudioDirector
extends Node

## ULTRABLADE -- AudioDirector
##
## Contract: docs/CONTRACTS.md (Audio section, exactly these methods):
##   play_sfx(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void
##   play_music(mode: String = "match") -> void
##   stop_music() -> void
##   goal_horn(team: String) -> void
##   set_crowd(intensity: float) -> void
##
## All WAVs are original procedural assets (game/assets/audio/NOTICE.md) generated
## by tools/generate_audio.py.  The game must boot and play fine when files are
## missing: every load is guarded and a missing asset is a no-op (warning once).
##
## Usage from the Lead's main.gd:
##   var audio := AudioDirector.new()
##   audio.name = "AudioDirector"
##   add_child(audio)
##   audio.play_music("match")
##   audio.play_sfx("slash")
##
## SFX names (stems, no .wav):
##   skate_loop, slash, metal_hit, heavy_hit, body_check, puck_pickup, shot,
##   goal_horn, crowd_swell, crowd_loop, turnstile_hum,
##   ui_click, ui_hover, ui_back, killball_charge, killball_zap,
##   countdown_beep, countdown_go, victory, death
## Common aliases are accepted too (see SFX_ALIASES).
##
## Extras beyond the contract (optional, safe to ignore): stop_sfx(stem),
## stop_all_sfx(), get_sfx_stream(), get_music_stream(), is_music_playing(),
## get_missing_assets(), get_sfx_names(), get_music_modes(), get_current_music().

const AUDIO_DIR := "res://assets/audio/"
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
const SFX_VOICES := 20
const MUSIC_VOICES := 2
const MUSIC_VOLUME_DB := -6.0
const MUSIC_FADE_SEC := 1.0
const STOP_FADE_SEC := 0.6
const CROWD_MIN_DB := -40.0
const CROWD_MAX_DB := -8.0

const SFX_NAMES = [
	"skate_loop", "slash", "metal_hit", "heavy_hit", "body_check", "puck_pickup", "shot",
	"goal_horn", "horn_short", "crowd_goal", "crowd_swell", "crowd_loop", "turnstile_hum",
	"ui_click", "ui_hover", "ui_back",
	"killball_charge", "killball_zap", "killball_throw",
	"countdown_beep", "countdown_go",
	"victory", "defeat", "death", "down",
	"boost_pad", "save", "hit_rok", "pass", "slash_hit",
]

const MUSIC_MODES = ["match"]

## main.gd asks for several music moods; all map onto the single 40 s match loop.
## Same-file modes re-tune the running loop (pitch/volume tween) instead of restarting it.
const MUSIC_VARIANTS = {
	"match": {"file": "match", "pitch": 1.0, "volume_db": -6.0},
	"goal": {"file": "match", "pitch": 0.95, "volume_db": -9.0},
	"break": {"file": "match", "pitch": 0.87, "volume_db": -12.0},
	"victory": {"file": "match", "pitch": 1.05, "volume_db": -7.0},
	"defeat": {"file": "match", "pitch": 0.8, "volume_db": -11.0},
}

const LOOPING_SFX = ["skate_loop", "crowd_loop", "turnstile_hum"]

const BASE_VOLUME_DB = {
	"skate_loop": -8.0,
	"slash": -3.0,
	"metal_hit": -2.0,
	"heavy_hit": -2.0,
	"body_check": -3.0,
	"puck_pickup": 0.0,
	"shot": -2.5,
	"goal_horn": -1.0,
	"horn_short": 0.0,
	"crowd_goal": 0.0,
	"crowd_swell": -4.0,
	"crowd_loop": -10.0,
	"turnstile_hum": -12.0,
	"ui_click": -8.0,
	"ui_hover": -14.0,
	"ui_back": -10.0,
	"killball_charge": -3.0,
	"killball_zap": -1.0,
	"killball_throw": 0.0,
	"countdown_beep": 2.0,
	"countdown_go": 2.0,
	"victory": -1.0,
	"defeat": -1.0,
	"death": -1.0,
	"down": 0.0,
	"boost_pad": 0.0,
	"save": 0.0,
	"hit_rok": 0.0,
	"pass": 0.0,
	"slash_hit": 0.0,
}

const SFX_ALIASES = {
	"slash_whoosh": "slash",
	"whoosh": "slash",
	"swing": "slash",
	"metal": "metal_hit",
	"clash": "metal_hit",
	"jak_hit": "metal_hit",
	"heavy_slash": "heavy_hit",
	"hit": "metal_hit",
	"check": "body_check",
	"pickup": "puck_pickup",
	"rok_pickup": "puck_pickup",
	"shoot": "shot",
	"throw": "shot",
	"horn": "goal_horn",
	"goal": "goal_horn",
	"crowd": "crowd_swell",
	"crowd_start": "crowd_loop",
	"turnstile": "turnstile_hum",
	"skate": "skate_loop",
	"ui": "ui_click",
	"click": "ui_click",
	"hover": "ui_hover",
	"back": "ui_back",
	"killball": "killball_charge",
	"charge": "killball_charge",
	"zap": "killball_zap",
	"countdown": "countdown_beep",
	"go": "countdown_go",
	"victory_stinger": "victory",
	"death_stinger": "death",
	"defeat_stinger": "defeat",
	"slash_light": "slash_hit",
	"jak_hit_light": "slash_hit",
	"goal_crowd": "crowd_goal",
	"period_horn": "horn_short",
	"whistle": "horn_short",
	"knockdown": "down",
	"boost": "boost_pad",
	"glove_save": "save",
	"rok_hit": "hit_rok",
	"flick": "pass",
	"throw_killball": "killball_throw",
}

var _sfx: Dictionary = {}
var _music: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _crowd_player: AudioStreamPlayer = null
var _sfx_cursor: int = 0
var _music_cursor: int = 0
var _current_music: String = ""
var _current_music_file: String = ""
var _crowd_intensity: float = 0.0
var _muted: bool = false
var _missing: PackedStringArray = PackedStringArray()
var _warned: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	_ensure_loaded()


# --------------------------------------------------------------------------
# public contract API
# --------------------------------------------------------------------------


func play_sfx(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_ensure_loaded()
	var key := _resolve_sfx(name)
	if key.is_empty():
		return
	var stream: AudioStream = _sfx.get(key, null)
	if stream == null:
		return
	var player := _find_loop_voice(stream) if LOOPING_SFX.has(key) else null
	if player != null:
		player.volume_db = _sfx_volume(key, volume_db)
		player.pitch_scale = clampf(pitch, 0.05, 4.0)
		if not player.playing:
			player.play()
		return
	player = _take_sfx_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = _sfx_volume(key, volume_db)
	player.pitch_scale = clampf(pitch, 0.05, 4.0)
	player.play()


func play_music(mode: String = "match") -> void:
	_ensure_loaded()
	var mode_key := _normalize_key(mode)
	if mode_key.begins_with("music_"):
		mode_key = mode_key.substr(6)
	var known := MUSIC_VARIANTS.has(mode_key)
	var variant := _music_variant(mode_key)
	var file_key: String = str(variant.get("file", "match"))
	var stream: AudioStream = _music.get(file_key, null)
	if stream == null:
		return
	if not known:
		mode_key = "match"
	if file_key == _current_music_file and is_music_playing():
		_current_music = mode_key
		_tween_music_params(variant)
		return
	# fade every other music voice out, then start the requested loop on a fresh voice
	for other in _music_players:
		if other.playing:
			_fade_out_player(other, MUSIC_FADE_SEC)
	var player: AudioStreamPlayer = _music_players[_music_cursor]
	_music_cursor = (_music_cursor + 1) % _music_players.size()
	player.stream = stream
	player.volume_db = -60.0
	player.pitch_scale = float(variant.get("pitch", 1.0))
	player.play()
	var tween := create_tween()
	tween.tween_property(player, "volume_db", float(variant.get("volume_db", MUSIC_VOLUME_DB)), MUSIC_FADE_SEC)
	_current_music = mode_key
	_current_music_file = file_key


func stop_music() -> void:
	for player in _music_players:
		if player.playing:
			_fade_out_player(player, STOP_FADE_SEC)
	_current_music = ""
	_current_music_file = ""


func goal_horn(team: String) -> void:
	_ensure_loaded()
	var normalized := team.strip_edges().to_lower()
	var pitch := 1.0
	if normalized == "blue" or normalized == "player" or normalized == "hometeam":
		pitch = 1.06
	elif normalized == "red" or normalized == "enemy" or normalized == "away":
		pitch = 0.94
	play_sfx("goal_horn", 0.0, pitch)
	play_sfx("crowd_swell", -2.0, 1.0)


func set_crowd(intensity: float) -> void:
	_ensure_loaded()
	_crowd_intensity = clampf(intensity, 0.0, 1.0)
	var stream: AudioStream = _sfx.get("crowd_loop", null)
	if stream == null or _crowd_player == null:
		return
	if _crowd_intensity <= 0.01:
		if _crowd_player.playing:
			_fade_out_player(_crowd_player, 0.8)
		return
	if not _crowd_player.playing:
		_crowd_player.stream = stream
		_crowd_player.volume_db = -60.0
		_crowd_player.play()
	var target_db := lerpf(CROWD_MIN_DB, CROWD_MAX_DB, _crowd_intensity)
	var tween := create_tween()
	tween.tween_property(_crowd_player, "volume_db", target_db, 0.6)


## main.gd binds a mute key to this (optional extra, not part of the documented contract).
func toggle_mute() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _muted)


func is_muted() -> bool:
	return _muted


# --------------------------------------------------------------------------
# optional extras (not part of the contract; handy for integration/debug)
# --------------------------------------------------------------------------


func stop_sfx(name: String) -> void:
	_ensure_loaded()
	var key := _resolve_sfx(name)
	if key.is_empty():
		return
	var stream: AudioStream = _sfx.get(key, null)
	if stream == null:
		return
	for player in _sfx_players:
		if player.playing and player.stream == stream:
			player.stop()
	if _crowd_player != null and _crowd_player.playing and _crowd_player.stream == stream:
		_crowd_player.stop()


func stop_all_sfx() -> void:
	for player in _sfx_players:
		player.stop()
	if _crowd_player != null:
		_crowd_player.stop()


func get_sfx_stream(name: String) -> AudioStream:
	_ensure_loaded()
	var key := _resolve_sfx(name)
	return _sfx.get(key, null)


func get_music_stream(mode: String) -> AudioStream:
	_ensure_loaded()
	var key := _resolve_music(mode)
	return _music.get(key, null)


func is_music_playing() -> bool:
	for player in _music_players:
		if player.playing and player.stream != null:
			return true
	return false


func get_current_music() -> String:
	return _current_music


func get_missing_assets() -> PackedStringArray:
	_ensure_loaded()
	return _missing.duplicate()


func get_sfx_names() -> PackedStringArray:
	return PackedStringArray(SFX_NAMES)


func get_music_modes() -> PackedStringArray:
	return PackedStringArray(MUSIC_MODES)


func get_sfx_voice_count() -> int:
	return _sfx_players.size()


func get_music_voice_count() -> int:
	return _music_players.size()


func is_loaded() -> bool:
	return _loaded


# --------------------------------------------------------------------------
# loading / voice management
# --------------------------------------------------------------------------


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_build_voice_pools()
	_load_streams()


func _build_voice_pools() -> void:
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "SfxVoice%02d" % i
		player.bus = _bus_name(SFX_BUS)
		add_child(player)
		_sfx_players.append(player)
	for i in MUSIC_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "MusicVoice%02d" % i
		player.bus = _bus_name(MUSIC_BUS)
		add_child(player)
		_music_players.append(player)
	_crowd_player = AudioStreamPlayer.new()
	_crowd_player.name = "CrowdVoice"
	_crowd_player.bus = _bus_name(SFX_BUS)
	add_child(_crowd_player)


func _bus_name(preferred: String) -> StringName:
	if AudioServer.get_bus_index(preferred) >= 0:
		return StringName(preferred)
	return &"Master"


func _load_streams() -> void:
	_missing = PackedStringArray()
	_sfx.clear()
	for sfx_name in SFX_NAMES:
		var path: String = AUDIO_DIR + str(sfx_name) + ".wav"
		var stream := _load_stream(path)
		if stream == null:
			continue
		if LOOPING_SFX.has(sfx_name):
			_enable_loop(stream)
		_sfx[sfx_name] = stream
	_music.clear()
	for mode in MUSIC_MODES:
		var path: String = AUDIO_DIR + "music_" + str(mode) + ".wav"
		var stream := _load_stream(path)
		if stream == null:
			continue
		_enable_loop(stream)
		_music[mode] = stream


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		_missing.append(path)
		_warn_once("missing:" + path, "AudioDirector: missing audio asset %s (game continues silently)" % path)
		return null
	var resource := load(path)
	if resource is AudioStream:
		return resource as AudioStream
	_missing.append(path)
	_warn_once("bad:" + path, "AudioDirector: %s is not an AudioStream (game continues silently)" % path)
	return null


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var frames := int(round(wav.get_length() * float(wav.mix_rate)))
		if frames > 0:
			wav.loop_end = frames


func _resolve_sfx(name: String) -> String:
	var key := _normalize_key(name)
	if SFX_ALIASES.has(key):
		key = SFX_ALIASES[key]
	if _sfx.has(key):
		return key
	_warn_once("unknown_sfx:" + key, "AudioDirector: unknown or unavailable SFX '%s' (ignored)" % name)
	return ""


func _resolve_music(mode: String) -> String:
	var key := _normalize_key(mode)
	if key.begins_with("music_"):
		key = key.substr(6)
	var variant := _music_variant(key)
	var file_key: String = str(variant.get("file", "match"))
	if _music.has(file_key):
		return file_key
	if not _music.is_empty():
		return String(_music.keys()[0])
	_warn_once("no_music", "AudioDirector: no music assets found (game continues silently)")
	return ""


func _music_variant(mode_key: String) -> Dictionary:
	if MUSIC_VARIANTS.has(mode_key):
		return MUSIC_VARIANTS[mode_key]
	_warn_once("unknown_music:" + mode_key, "AudioDirector: unknown music mode '%s', using 'match'" % mode_key)
	return MUSIC_VARIANTS["match"]


func _tween_music_params(variant: Dictionary) -> void:
	var player := _active_music_player()
	if player == null:
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", float(variant.get("volume_db", MUSIC_VOLUME_DB)), 0.4)
	tween.parallel().tween_property(player, "pitch_scale", float(variant.get("pitch", 1.0)), 0.4)


func _active_music_player() -> AudioStreamPlayer:
	for player in _music_players:
		if player.playing and player.stream != null:
			return player
	return null


func _normalize_key(value: String) -> String:
	var key := value.strip_edges().to_lower()
	if key.begins_with("res://"):
		key = key.get_file()
	if key.ends_with(".wav"):
		key = key.trim_suffix(".wav")
	return key


func _sfx_volume(key: String, volume_db: float) -> float:
	var base := float(BASE_VOLUME_DB.get(key, 0.0))
	return clampf(base + volume_db, -80.0, 6.0)


func _find_loop_voice(stream: AudioStream) -> AudioStreamPlayer:
	for player in _sfx_players:
		if player.stream == stream and player.playing:
			return player
	return null


func _take_sfx_player() -> AudioStreamPlayer:
	if _sfx_players.is_empty():
		return null
	for i in _sfx_players.size():
		var index := (_sfx_cursor + i) % _sfx_players.size()
		var player := _sfx_players[index]
		if not player.playing:
			_sfx_cursor = (index + 1) % _sfx_players.size()
			return player
	var fallback := _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	return fallback


func _fade_out_player(player: AudioStreamPlayer, duration: float) -> void:
	if not player.playing:
		player.stop()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -60.0, maxf(duration, 0.05))
	tween.tween_callback(func() -> void: player.stop())


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
