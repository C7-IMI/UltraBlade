extends SceneTree

## ULTRABLADE -- headless audio self-test.
##
## Verifies that the original procedural audio assets import and load through
## AudioDirector, that the documented contract API is callable, that looping
## assets are flagged, and that the game never fails when asked for unknown sounds.
##
## Run (Windows, from the repo root):
##   godot_console.exe --headless --path game -s res://tools/audio_preview.gd
##
## Exit code 0 = PASS, 1 = FAIL. Prints UB_AUDIO_PREVIEW_OK on success.

const DIRECTOR_SCRIPT := "res://scripts/audio_director.gd"
const AUDIO_DIR := "res://assets/audio/"
const EXPECTED_SFX = [
	"skate_loop", "slash", "metal_hit", "heavy_hit", "body_check", "puck_pickup", "shot",
	"goal_horn", "horn_short", "crowd_goal", "crowd_swell", "crowd_loop", "turnstile_hum",
	"ui_click", "ui_hover", "ui_back",
	"killball_charge", "killball_zap", "killball_throw",
	"countdown_beep", "countdown_go",
	"victory", "defeat", "death", "down",
	"boost_pad", "save", "hit_rok", "pass", "slash_hit",
]
const EXPECTED_MUSIC = ["match"]
const LOOPING_SFX = ["skate_loop", "crowd_loop", "turnstile_hum"]

var _checks: int = 0
var _fails: int = 0
var _errors: PackedStringArray = PackedStringArray()
var _elapsed: float = 0.0
var _finished: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _finished and _elapsed > 25.0:
		print("UB_AUDIO_PREVIEW_TIMEOUT after %.1f s (see errors above)" % _elapsed)
		quit(1)
		return true
	return false


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("PASS  %-44s %s" % [label, detail])
	else:
		_fails += 1
		_errors.append(label)
		print("FAIL  %-44s %s" % [label, detail])


func _run() -> void:
	print("[AUDIO_PREVIEW] ULTRABLADE audio headless self-test")
	var script: Script = load(DIRECTOR_SCRIPT) as Script
	_ok("audio_director.gd loads", script != null, DIRECTOR_SCRIPT)
	if script == null:
		_finish()
		return

	var director: Variant = script.new()
	_ok("AudioDirector instantiates", director != null)
	if director == null:
		_finish()
		return
	root.add_child(director)
	await process_frame
	await process_frame

	_check_buses()
	_check_assets(director)
	_check_voices(director)
	await _check_api(director)
	_check_files()
	director.queue_free()
	await process_frame
	_finish()


func _check_buses() -> void:
	var sfx_index := AudioServer.get_bus_index("SFX")
	var music_index := AudioServer.get_bus_index("Music")
	_ok("SFX bus exists", sfx_index >= 0, "bus index %d" % sfx_index)
	_ok("Music bus exists", music_index >= 0, "bus index %d" % music_index)


func _check_assets(director: Variant) -> void:
	var missing: PackedStringArray = director.get_missing_assets()
	_ok("no missing audio assets", missing.is_empty(), ", ".join(missing))
	var loaded := 0
	for sfx_name in EXPECTED_SFX:
		var stream: AudioStream = director.get_sfx_stream(sfx_name)
		var label: String = "sfx %s" % sfx_name
		_ok(label + " loads", stream != null)
		if stream == null:
			continue
		loaded += 1
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			var is_16bit := wav.format == AudioStreamWAV.FORMAT_16_BITS
			_ok(label + " 44.1k/16-bit", wav.mix_rate == 44100 and is_16bit,
				"%d Hz, fmt=%d, stereo=%s" % [wav.mix_rate, wav.format, str(wav.stereo)])
			_ok(label + " duration", wav.get_length() > 0.05, "%.3f s" % wav.get_length())
			if LOOPING_SFX.has(sfx_name):
				_ok(label + " loop mode", wav.loop_mode == AudioStreamWAV.LOOP_FORWARD,
					"loop_mode=%d end=%d" % [wav.loop_mode, wav.loop_end])
		else:
			_ok(label + " is AudioStreamWAV", false, stream.get_class())
	_ok("all expected SFX present", loaded == EXPECTED_SFX.size(), "%d/%d" % [loaded, EXPECTED_SFX.size()])
	for mode in EXPECTED_MUSIC:
		var music: AudioStream = director.get_music_stream(mode)
		var label: String = "music %s" % mode
		_ok(label + " loads", music != null)
		if music == null:
			continue
		if music is AudioStreamWAV:
			var wav := music as AudioStreamWAV
			_ok(label + " 44.1k/16-bit/stereo", wav.mix_rate == 44100
				and wav.format == AudioStreamWAV.FORMAT_16_BITS and wav.stereo,
				"%d Hz, fmt=%d, stereo=%s" % [wav.mix_rate, wav.format, str(wav.stereo)])
			_ok(label + " ~40 s", wav.get_length() > 39.0 and wav.get_length() < 41.0,
				"%.3f s" % wav.get_length())
			_ok(label + " loop mode", wav.loop_mode == AudioStreamWAV.LOOP_FORWARD,
				"loop_mode=%d end=%d" % [wav.loop_mode, wav.loop_end])
		else:
			_ok(label + " is AudioStreamWAV", false, music.get_class())


func _check_voices(director: Variant) -> void:
	_ok("sfx voice pool", int(director.get_sfx_voice_count()) > 0, "%d voices" % int(director.get_sfx_voice_count()))
	_ok("music voice pool", int(director.get_music_voice_count()) >= 2, "%d voices" % int(director.get_music_voice_count()))


func _check_api(director: Variant) -> void:
	for sfx_name in EXPECTED_SFX:
		director.play_sfx(sfx_name, 0.0, 1.0)
	_ok("play_sfx every asset", true, "%d calls" % EXPECTED_SFX.size())
	director.play_sfx("slash", -6.0, 1.25)
	director.play_sfx("horn", 0.0, 1.0)
	director.play_sfx("skate", -20.0, 1.0)
	director.play_sfx("does_not_exist_sfx")
	_ok("play_sfx alias + unknown safe", true, "alias and unknown names ignored without error")

	director.goal_horn("blue")
	director.goal_horn("red")
	director.goal_horn("unknown")
	_ok("goal_horn(blue/red/unknown)", true, "all three calls returned")

	director.set_crowd(0.0)
	await process_frame
	director.set_crowd(0.5)
	await process_frame
	director.set_crowd(1.0)
	await process_frame
	_ok("set_crowd(0.0/0.5/1.0)", true, "intensity accepted")

	director.play_music("match")
	await process_frame
	_ok("play_music(match)", director.is_music_playing(), "current=%s" % str(director.get_current_music()))
	director.play_music("match")
	_ok("play_music(match) idempotent", director.is_music_playing(), "still playing")
	director.play_music("goal")
	_ok("play_music(goal) re-tunes loop", director.is_music_playing(), "current=%s" % str(director.get_current_music()))
	director.play_music("break")
	_ok("play_music(break) re-tunes loop", director.is_music_playing(), "current=%s" % str(director.get_current_music()))
	director.play_music("victory")
	director.play_music("defeat")
	_ok("play_music(victory/defeat)", director.is_music_playing(), "current=%s" % str(director.get_current_music()))
	director.play_music("menu")
	await process_frame
	_ok("play_music(menu) falls back", director.is_music_playing(), "current=%s" % str(director.get_current_music()))
	director.toggle_mute()
	var muted_after_first := bool(director.is_muted())
	director.toggle_mute()
	_ok("toggle_mute()", muted_after_first and not bool(director.is_muted()), "muted then unmuted")
	director.stop_music()
	await create_timer(1.2).timeout
	_ok("stop_music()", not director.is_music_playing(), "silence after fade")
	director.stop_all_sfx()
	_ok("stop_all_sfx()", true, "voices cleared")


func _check_files() -> void:
	var files := DirAccess.get_files_at(AUDIO_DIR)
	var wavs: PackedStringArray = PackedStringArray()
	var total_bytes := 0
	for file_name in files:
		if not file_name.ends_with(".wav"):
			continue
		wavs.append(file_name)
		var access := FileAccess.open(AUDIO_DIR + file_name, FileAccess.READ)
		if access != null:
			total_bytes += access.get_length()
			access.close()
	wavs.sort()
	_ok("wav file count", wavs.size() == 31, "%d files" % wavs.size())
	var budget := 25 * 1024 * 1024
	_ok("wav total under 25 MB", total_bytes < budget, "%.2f MB" % (float(total_bytes) / (1024.0 * 1024.0)))
	var expected_missing: PackedStringArray = PackedStringArray()
	for sfx_name in EXPECTED_SFX:
		if not wavs.has(sfx_name + ".wav"):
			expected_missing.append(sfx_name + ".wav")
	for mode in EXPECTED_MUSIC:
		if not wavs.has("music_" + mode + ".wav"):
			expected_missing.append("music_" + mode + ".wav")
	_ok("expected wav files present", expected_missing.is_empty(), ", ".join(expected_missing))


func _finish() -> void:
	_finished = true
	print("[AUDIO_PREVIEW] checks=%d fails=%d" % [_checks, _fails])
	if _fails == 0:
		print("UB_AUDIO_PREVIEW_OK")
		quit(0)
	else:
		print("UB_AUDIO_PREVIEW_FAILED: %s" % ", ".join(_errors))
		quit(1)
