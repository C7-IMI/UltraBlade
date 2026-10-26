class_name SkaterModel
extends Node3D

## ULTRABLADE skater.
##
## Wraps the ActionForge CC0 mannequin rig (71 bones) plus 20 CC0 clips and dresses
## the rig as a hockey gladiator with procedural armour, helmet + visor, skates, an
## oversized left-hand jak and a team glow. The root sits at the skater's feet
## (ice contact), the skater reads ~1.9 m tall and faces Godot -Z.
##
## Contract (docs/CONTRACTS.md):
##   setup(team_color, role, is_star)
##   play(state, speed_ratio)
##   set_carrying(on)
##   set_boost(on)
##   burst(kind, at)
##
## Asset notes (do not modify the imported GLBs):
##   * rig  : game/assets/actionforge/rig/rig-human.glb
##            root Node3D "rig-human" -> Armature -> Skeleton3D (71 bones) -> Mannequin
##   * clips: game/assets/actionforge/animations/*.glb, one AnimationPlayer each,
##            track paths are "Armature/Skeleton3D:<bone>", animation names differ from
##            file names for the loop clips (idle_loop.glb -> "idle", walk_loop.glb ->
##            "walk", jog_fwd_loop.glb -> "jog_fwd", sprint_loop.glb -> "sprint",
##            slide_loop.glb -> "slide", jump_loop.glb -> "jump").
##   * attribution: ActionForge CC0 library, clips by Quaternius.
##     See game/assets/actionforge/NOTICE.md.
##
## ROOT MOTION: the source clips animate the "root" bone forward (walk 1.3 m,
## jog_fwd 5.0 m, sprint 5.5 m, slide 9.0 m, sword_attack 1.5 m, hit_knockback -3.0 m
## per clip). The Lead's CharacterBody3D owns translation, so SkaterModel strips the
## root bone position track once while building the shared AnimationLibrary. The
## removed ranges are kept in get_root_motion_report() as evidence.
##
## Threading/loading: the AnimationLibrary is built lazily and shared by every
## SkaterModel instance in the process (20 GLB loads once). Model construction after
## that is geometry + materials only.

signal state_changed(state: String)
signal action_finished(state: String)

const RIG_SCENE_PATH := "res://assets/actionforge/rig/rig-human.glb"
const CLIP_DIR := "res://assets/actionforge/animations/"
const TARGET_HEIGHT := 1.90
const RIG_YAW_FIX := PI
const DEFAULT_TEAM := Color(0.129, 0.902, 1.0)
const STAR_GOLD := Color(1.0, 0.78, 0.25)
const ROLES := ["striker", "enforcer", "runner", "anchor", "goalie"]

## clip key -> source GLB file (the animation inside keeps its own name, see _clip_for_state)
const CLIP_FILES := {
	"idle": "idle_loop",
	"walk": "walk_loop",
	"jog_fwd": "jog_fwd_loop",
	"sprint": "sprint_loop",
	"slide": "slide_loop",
	"jump": "jump_loop",
	"jump_start": "jump_start",
	"jump_land": "jump_land",
	"sword_idle": "sword_idle",
	"sword_attack": "sword_attack",
	"sword_regular_a": "sword_regular_a",
	"sword_regular_b": "sword_regular_b",
	"sword_regular_combo": "sword_regular_combo",
	"hit_chest": "hit_chest",
	"hit_head": "hit_head",
	"hit_knockback": "hit_knockback",
	"death01": "death01",
	"punch_jab": "punch_jab",
	"melee_hook": "melee_hook",
	"overhandthrow": "overhandthrow",
}

## Clips that loop; everything else is a one-shot (LOOP_NONE).
const LOOP_CLIPS := ["idle", "walk", "jog_fwd", "sprint", "slide", "jump", "sword_idle"]

## Contract state -> clip key. Extra aliases are provided for the Lead's convenience.
const STATE_CLIP := {
	"idle": "idle",
	"walk": "walk",
	"skate": "jog_fwd",
	"sprint": "sprint",
	"slide": "slide",
	"slash": "sword_regular_a",
	"heavy": "sword_attack",
	"hit": "hit_chest",
	"down": "death01",
	"celebrate": "sword_regular_combo",
	"goalie": "sword_idle",
	# aliases (not required by the contract, safe to use)
	"stance": "sword_idle",
	"jump": "jump_start",
	"air": "jump",
	"land": "jump_land",
	"shoot": "overhandthrow",
	"throw": "overhandthrow",
	"punch": "punch_jab",
	"hook": "melee_hook",
	"attack": "sword_regular_b",
	"flourish": "sword_regular_combo",
	"hit_head": "hit_head",
	"knockback": "hit_knockback",
}

## States that are grounded locomotion (used as the auto-return target).
const LOCOMOTION_STATES := ["idle", "walk", "skate", "sprint", "slide", "goalie", "air"]

## One-shot states that automatically return to the last locomotion state when they end.
const ACTION_RETURN_STATES := [
	"slash", "heavy", "attack", "punch", "hook",
	"hit", "hit_head", "knockback", "shoot", "throw",
]

## Per-role procedural armour styling. padScale = shoulder bulk, etc.
const ROLE_STYLE := {
	"striker": {"pad": 1.0, "chest": 1.0, "glove": 1.0, "thigh": 1.0, "shin": 1.0, "cage": false, "blade": 0.95, "crest": 1.0, "goal_pads": false},
	"enforcer": {"pad": 1.28, "chest": 1.12, "glove": 1.15, "thigh": 1.16, "shin": 1.14, "cage": true, "blade": 1.08, "crest": 1.55, "goal_pads": false},
	"runner": {"pad": 0.82, "chest": 0.92, "glove": 0.88, "thigh": 0.82, "shin": 0.85, "cage": false, "blade": 0.78, "crest": 0.70, "goal_pads": false},
	"anchor": {"pad": 1.16, "chest": 1.08, "glove": 1.02, "thigh": 1.10, "shin": 1.10, "cage": true, "blade": 0.92, "crest": 1.20, "goal_pads": false},
	"goalie": {"pad": 1.12, "chest": 1.20, "glove": 1.42, "thigh": 1.0, "shin": 1.0, "cage": true, "blade": 0.72, "crest": 1.10, "goal_pads": true},
}

# --- shared, process-wide animation data ---------------------------------------
static var _shared_library: AnimationLibrary = null
static var _clip_meta: Dictionary = {}
static var _root_motion_report: Dictionary = {}
static var _library_build_ms: float = -1.0
static var _library_error: String = ""

@export var team_color: Color = DEFAULT_TEAM
@export_enum("striker", "enforcer", "runner", "anchor", "goalie") var role: String = "striker"
@export var is_star: bool = false
@export var auto_idle: bool = true

var _configured := false
var _built := false
var _team_color := DEFAULT_TEAM
var _role := "striker"
var _is_star := false

var _visual: Node3D
var _rig: Node3D
var _skeleton: Skeleton3D
var _mannequin: MeshInstance3D
var _anim: AnimationPlayer
var _attach_points: Dictionary = {}
var _mats: Dictionary = {}

var _state := ""
var _current_clip := ""
var _locomotion_state := "idle"
var _locomotion_speed := 0.0
var _pending_state := ""
var _pending_speed := 0.0

var _carrying := false
var _boosting := false
var _glow: MeshInstance3D
var _boost_streak: MeshInstance3D
var _carry_prop: MeshInstance3D

var _design_top := 0.0
var _design_bottom := 0.0
var _visual_scale := 1.0
var _measured_height := 0.0
var _build_ms := 0.0

# =============================================================================
# Shared AnimationLibrary
# =============================================================================

## Builds (once per process) the shared AnimationLibrary from the 20 clip GLBs.
## Track paths are already "Armature/Skeleton3D:bone", so adding the library to an
## AnimationPlayer whose root is the rig root resolves every track.
static func ensure_library() -> AnimationLibrary:
	if _shared_library != null:
		return _shared_library
	var started := Time.get_ticks_usec()
	var lib := AnimationLibrary.new()
	for clip_key in CLIP_FILES.keys():
		var clip_name := String(clip_key)
		var file_name := String(CLIP_FILES[clip_key])
		var scene_path := CLIP_DIR + file_name + ".glb"
		var packed := load(scene_path) as PackedScene
		if packed == null:
			_library_error = "missing clip GLB: " + scene_path
			push_error("SkaterModel: " + _library_error)
			continue
		var instance := packed.instantiate()
		var source_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if source_player == null:
			instance.free()
			_library_error = "clip has no AnimationPlayer: " + scene_path
			push_error("SkaterModel: " + _library_error)
			continue
		var source_names := source_player.get_animation_list()
		if source_names.is_empty():
			instance.free()
			_library_error = "clip has no animations: " + scene_path
			push_error("SkaterModel: " + _library_error)
			continue
		var source_anim_name := String(source_names[0])
		var source_anim := source_player.get_animation(source_names[0])
		var anim := source_anim.duplicate(true) as Animation
		var stripped := _strip_root_motion(anim)
		anim.loop_mode = Animation.LOOP_LINEAR if LOOP_CLIPS.has(clip_name) else Animation.LOOP_NONE
		lib.add_animation(clip_name, anim)
		_clip_meta[clip_name] = {
			"file": file_name,
			"source_animation": source_anim_name,
			"length": anim.length,
			"loop": LOOP_CLIPS.has(clip_name),
			"tracks": anim.get_track_count(),
			"root_motion_stripped": stripped,
		}
		if not stripped.is_empty():
			_root_motion_report[clip_name] = stripped
		instance.free()
	if lib.get_animation_list().is_empty():
		_library_error = "no animations could be built"
		push_error("SkaterModel: " + _library_error)
	_shared_library = lib
	_library_build_ms = (Time.get_ticks_usec() - started) / 1000.0
	return lib

## Removes the root bone position track (root motion) from a clip, reporting the
## travel that was removed. Returns an empty Dictionary when the clip is in place.
static func _strip_root_motion(anim: Animation) -> Dictionary:
	var report := {}
	for track_idx in range(anim.get_track_count() - 1, -1, -1):
		var track_path := anim.track_get_path(track_idx)
		if track_path.get_concatenated_subnames() != "root":
			continue
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		var key_count := anim.track_get_key_count(track_idx)
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		for key_idx in range(key_count):
			var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			low = low.min(value)
			high = high.max(value)
		report["track"] = String(track_path)
		report["keys"] = key_count
		report["min"] = low
		report["max"] = high
		report["travel"] = high - low
		anim.remove_track(track_idx)
	return report

static func library_build_ms() -> float:
	return _library_build_ms

static func clip_meta() -> Dictionary:
	return _clip_meta

static func get_root_motion_report() -> Dictionary:
	return _root_motion_report

static func get_library_error() -> String:
	return _library_error

static func get_animation_library() -> AnimationLibrary:
	return ensure_library()

static func get_state_clip_map() -> Dictionary:
	return STATE_CLIP.duplicate()

static func get_clip_names() -> Array:
	return ensure_library().get_animation_list()

# =============================================================================
# Lifecycle / public API
# =============================================================================

func _ready() -> void:
	_ensure_configured()
	_build()
	if not _built:
		return
	if not _pending_state.is_empty():
		_apply_state(_pending_state, _pending_speed)
	elif auto_idle:
		play("idle")

## Contract: configure colour/role/star. Safe before or after add_child().
func setup(p_team_color: Color, p_role: String, p_is_star: bool) -> void:
	_team_color = p_team_color
	_role = p_role if ROLES.has(p_role) else "striker"
	_is_star = p_is_star
	_configured = true
	if is_inside_tree():
		if _built:
			_rebuild()
		else:
			_build()

## Contract: play a named state. speed_ratio is 0..1 of the skater's top speed and
## scales cycle playback for locomotion states.
func play(p_state: String, speed_ratio: float = 0.0) -> void:
	_pending_state = p_state
	_pending_speed = speed_ratio
	if not _built:
		if is_inside_tree():
			_build()
		if not _built:
			return
	_apply_state(p_state, speed_ratio)

## Contract: show the carried rok in the right hand.
func set_carrying(on: bool) -> void:
	_carrying = on
	if _carry_prop != null:
		_carry_prop.visible = on

## Contract: toggle boost visuals (underglow + speed streak).
func set_boost(on: bool) -> void:
	_boosting = on
	if not _built:
		return
	if _boost_streak != null:
		_boost_streak.visible = on
	var glow_material := _mats.get("glow") as StandardMaterial3D
	if glow_material != null:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(glow_material, "emission_energy_multiplier", 2.4 if on else 1.0, 0.16)
		tween.tween_property(glow_material, "albedo_color:a", 0.52 if on else 0.24, 0.16)
	if _glow != null:
		var target := Vector3(1.18, 1.0, 1.55) if on else Vector3(1.0, 1.0, 1.32)
		var tween2 := create_tween()
		tween2.tween_property(_glow, "scale", target, 0.16)

## Contract: one-shot VFX. kind in
##   slash | heavy | hit | boost | goal | killball | spawn
## at == Vector3.ZERO anchors the effect on the model; otherwise it is a world position.
func burst(kind: String, at: Vector3 = Vector3.ZERO) -> void:
	if not _built:
		return
	var base := at
	if at == Vector3.ZERO:
		base = _burst_anchor(kind)
	else:
		base = to_local(at)
	var accent := _team_color
	match kind:
		"slash":
			_flash_sphere(base + Vector3(-0.30, 1.28, -0.30), accent, 0.42, 0.16)
			_flash_streak(base + Vector3(-0.34, 1.28, -0.32), accent, Basis(Vector3(0, 0, 1), 0.9).scaled(Vector3(1.0, 0.18, 2.2)), 0.18)
		"heavy":
			_flash_sphere(base + Vector3(-0.22, 1.34, -0.42), accent, 0.62, 0.24)
			_flash_ring(base + Vector3(-0.18, 1.30, -0.42), accent, 0.52, 0.30, false)
		"hit", "impact":
			_flash_sphere(base + Vector3(0.0, 1.34, -0.22), Color(1.0, 0.95, 0.9), 0.46, 0.18)
			_flash_ring(base + Vector3(0.0, 1.30, -0.18), accent, 0.42, 0.24, false)
		"boost":
			_flash_ring(base + Vector3(0.0, 0.05, 0.42), accent, 0.72, 0.30, true)
		"goal":
			_flash_ring(base + Vector3(0.0, 0.06, 0.0), accent, 1.05, 0.55, true)
			_flash_streak(base + Vector3(0.0, 0.95, 0.0), accent, Basis.IDENTITY.scaled(Vector3(0.30, 2.4, 0.30)), 0.45)
		"killball", "electric":
			_flash_sphere(base + Vector3(-0.28, 1.36, -0.32), Color(1.0, 0.69, 0.125), 0.55, 0.22)
			_flash_ring(base + Vector3(0.0, 0.06, 0.0), Color(1.0, 0.69, 0.125), 0.66, 0.28, true)
		"spawn":
			_flash_ring(base + Vector3(0.0, 0.06, 0.0), accent, 0.90, 0.40, true)
		_:
			_flash_sphere(base + Vector3(0.0, 1.20, 0.0), accent, 0.30, 0.18)

func get_state() -> String:
	return _state

func get_current_clip() -> String:
	return _current_clip

func get_role() -> String:
	return _role

func get_team_color() -> Color:
	return _team_color

func is_star_player() -> bool:
	return _is_star

func is_built() -> bool:
	return _built

func is_carrying() -> bool:
	return _carrying

func is_boosting() -> bool:
	return _boosting

func get_visual_height() -> float:
	return _measured_height

func get_visual_scale() -> float:
	return _visual_scale

func get_build_ms() -> float:
	return _build_ms

func get_skeleton() -> Skeleton3D:
	return _skeleton

func get_animation_player() -> AnimationPlayer:
	return _anim

func get_visual_root() -> Node3D:
	return _visual

func get_attachment_points() -> Dictionary:
	return _attach_points.duplicate()

func get_renderable_count() -> int:
	var count := 0
	for mesh_instance in find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			count += 1
	return count

# =============================================================================
# Build
# =============================================================================

func _ensure_configured() -> void:
	if _configured:
		return
	_configured = true
	_team_color = team_color
	_role = role if ROLES.has(role) else "striker"
	_is_star = is_star

func _rebuild() -> void:
	if _anim != null:
		_anim.stop()
	_attach_points.clear()
	_mats.clear()
	_carry_prop = null
	_glow = null
	_boost_streak = null
	_anim = null
	_skeleton = null
	_mannequin = null
	_rig = null
	_built = false
	if _visual != null:
		remove_child(_visual)
		_visual.queue_free()
		_visual = null
	_build()
	if not _built:
		return
	if not _pending_state.is_empty():
		_apply_state(_pending_state, _pending_speed)
	elif auto_idle:
		play("idle")

func _build() -> void:
	if _built or not is_inside_tree():
		return
	_ensure_configured()
	var started := Time.get_ticks_usec()
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var packed := load(RIG_SCENE_PATH) as PackedScene
	if packed == null:
		_build_fallback()
		_built = true
		_build_ms = (Time.get_ticks_usec() - started) / 1000.0
		push_error("SkaterModel: rig missing at " + RIG_SCENE_PATH + " (fallback capsule used)")
		return

	_rig = packed.instantiate() as Node3D
	_rig.name = "Rig"
	_rig.rotation.y = RIG_YAW_FIX
	_visual.add_child(_rig)

	_skeleton = _rig.find_child("Skeleton3D", true, false) as Skeleton3D
	_mannequin = _rig.find_child("Mannequin", true, false) as MeshInstance3D
	if _mannequin != null and _mannequin.mesh != null:
		var bind_aabb := _mannequin.get_aabb()
		_design_top = bind_aabb.end.y
		_design_bottom = bind_aabb.position.y

	_anim = AnimationPlayer.new()
	_anim.name = "AnimPlayer"
	_anim.root_node = NodePath("..")
	_rig.add_child(_anim)
	var library := SkaterModel.ensure_library()
	if library.get_animation_list().size() > 0:
		_anim.add_animation_library("", library)
	_anim.animation_finished.connect(_on_animation_finished)

	_build_materials()
	_tint_mannequin()
	_build_armour()
	_build_glow_and_props()
	_fit_height()
	_built = true
	_build_ms = (Time.get_ticks_usec() - started) / 1000.0

func _build_fallback() -> void:
	var body := MeshInstance3D.new()
	body.name = "FallbackBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.30
	capsule.height = 1.55
	body.mesh = capsule
	body.position.y = 0.80
	var material := StandardMaterial3D.new()
	material.albedo_color = _team_color
	body.material_override = material
	_visual.add_child(body)
	_design_top = 1.90
	_design_bottom = 0.0
	_fit_height()

func _fit_height() -> void:
	var height := _design_top - _design_bottom
	if height < 0.10:
		height = TARGET_HEIGHT
		_design_top = TARGET_HEIGHT
		_design_bottom = 0.0
	_visual_scale = TARGET_HEIGHT / height
	_visual.scale = Vector3.ONE * _visual_scale
	_visual.position.y = -_design_bottom * _visual_scale
	_measured_height = height * _visual_scale

# =============================================================================
# Materials
# =============================================================================

func _build_materials() -> void:
	var team := _team_color
	var trim_color := STAR_GOLD if _is_star else team
	var steel := Color(0.16, 0.19, 0.24)
	var dark := Color(0.07, 0.085, 0.11)
	_mats["armour"] = _make_solid(steel.lerp(team, 0.32), 0.62, 0.34, team, 0.20)
	_mats["armour_dark"] = _make_solid(dark.lerp(team, 0.20), 0.55, 0.42, team, 0.10)
	_mats["trim"] = _make_unshaded(trim_color, trim_color, 2.2)
	_mats["visor"] = _make_visor(team)
	_mats["blade"] = _make_unshaded(team.darkened(0.10), team, 1.9)
	(_mats["blade"] as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["metal"] = _make_solid(Color(0.26, 0.29, 0.34), 0.85, 0.28, Color.BLACK, 0.0)
	_mats["gold"] = _make_unshaded(STAR_GOLD, STAR_GOLD, 2.6)
	_mats["glow"] = _make_glow(team)
	_mats["amber"] = _make_unshaded(Color(1.0, 0.69, 0.125), Color(1.0, 0.55, 0.08), 3.0)

func _make_solid(albedo: Color, metallic: float, roughness: float, emissive: Color, emissive_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.metallic = metallic
	material.roughness = roughness
	material.rim_enabled = true
	material.rim = 0.45
	material.rim_tint = 0.6
	if emissive_energy > 0.0:
		material.emission_enabled = true
		material.emission = emissive
		material.emission_energy_multiplier = emissive_energy
	return material

func _make_unshaded(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material

func _make_visor(team: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(team.r, team.g, team.b, 0.55)
	material.emission_enabled = true
	material.emission = team
	material.emission_energy_multiplier = 1.7
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _make_glow(team: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(team.r, team.g, team.b, 0.24)
	material.emission_enabled = true
	material.emission = team
	material.emission_energy_multiplier = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _make_flash(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, 1.0)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _tint_mannequin() -> void:
	if _mannequin == null or _mannequin.mesh == null:
		return
	for surface_idx in range(_mannequin.mesh.get_surface_count()):
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		if surface_idx == 0:
			material.albedo_color = Color(0.055, 0.065, 0.085).lerp(_team_color, 0.36)
			material.emission = _team_color
			material.emission_energy_multiplier = 0.12
		else:
			material.albedo_color = Color(0.03, 0.035, 0.045).lerp(_team_color, 0.16)
			material.emission = _team_color
			material.emission_energy_multiplier = 0.06
		material.metallic = 0.35
		material.roughness = 0.42
		material.rim_enabled = true
		material.rim = 0.5
		material.rim_tint = 0.7
		_mannequin.set_surface_override_material(surface_idx, material)

# =============================================================================
# Procedural armour
# =============================================================================

func _build_armour() -> void:
	var style := ROLE_STYLE.get(_role, ROLE_STYLE["striker"]) as Dictionary
	_build_helmet(style)
	_build_chest(style)
	_build_pelvis(style)
	_build_shoulders(style)
	_build_forearms(style)
	_build_gloves(style)
	_build_legs(style)
	_build_jak(style)

func _build_helmet(style: Dictionary) -> void:
	var design := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.697, -0.005))
	var crest: float = style["crest"]
	var helmet_parts := [
		_part(_sphere(0.100, 0.285), Vector3.ZERO, Basis.from_scale(Vector3(1.10, 1.02, 1.30))),
		_part(_box(Vector3(0.030, 0.095 * crest, 0.210 * crest)), Vector3(0.0, 0.125 * crest, -0.045)),
		_part(_box(Vector3(0.026, 0.060, 0.090)), Vector3(0.0, 0.070, 0.090)),
	]
	_add_merged_piece("Head", helmet_parts, _mats["armour"], design)

	var trim_parts := [
		_part(_box(Vector3(0.240, 0.028, 0.035)), Vector3(0.0, 0.062, 0.112)),
		_part(_box(Vector3(0.035, 0.075, 0.140)), Vector3(0.115, 0.0, -0.020)),
		_part(_box(Vector3(0.035, 0.075, 0.140)), Vector3(-0.115, 0.0, -0.020)),
	]
	_add_merged_piece("Head", trim_parts, _mats["trim"], design)

	var visor_parts := [
		_part(_sphere(0.078, 0.100), Vector3(0.0, 0.0, 0.105), Basis.from_scale(Vector3(1.55, 0.90, 0.55))),
	]
	_add_merged_piece("Head", visor_parts, _mats["visor"], design)

	if bool(style["cage"]):
		var cage_parts := [
			_part(_box(Vector3(0.190, 0.012, 0.020)), Vector3(0.0, -0.050, 0.135)),
			_part(_box(Vector3(0.190, 0.012, 0.020)), Vector3(0.0, 0.000, 0.140)),
			_part(_box(Vector3(0.190, 0.012, 0.020)), Vector3(0.0, 0.050, 0.135)),
			_part(_box(Vector3(0.012, 0.110, 0.020)), Vector3(0.045, 0.0, 0.138)),
			_part(_box(Vector3(0.012, 0.110, 0.020)), Vector3(-0.045, 0.0, 0.138)),
		]
		_add_merged_piece("Head", cage_parts, _mats["metal"], design)

	if _is_star:
		_add_piece("Head", _star_mesh(0.062), _mats["gold"], design, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.055, 0.142)))

func _build_chest(style: Dictionary) -> void:
	var design := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.360, 0.0))
	var chest: float = style["chest"]
	var parts := [
		_part(_box(Vector3(0.420, 0.300, 0.280) * chest), Vector3.ZERO),
		_part(_box(Vector3(0.460, 0.090, 0.300) * chest), Vector3(0.0, 0.090, 0.010)),
		_part(_box(Vector3(0.260, 0.220, 0.085)), Vector3(0.0, -0.020, -0.160)),
		_part(_box(Vector3(0.130, 0.160, 0.070)), Vector3(0.150, -0.030, -0.130)),
		_part(_box(Vector3(0.130, 0.160, 0.070)), Vector3(-0.150, -0.030, -0.130)),
	]
	_add_merged_piece("spine_03", parts, _mats["armour"], design)

	var trim_parts := [
		_part(_box(Vector3(0.300, 0.032, 0.020)), Vector3(0.0, 0.015, 0.146)),
		_part(_box(Vector3(0.032, 0.190, 0.020)), Vector3(0.148, 0.0, 0.132)),
		_part(_box(Vector3(0.032, 0.190, 0.020)), Vector3(-0.148, 0.0, 0.132)),
	]
	_add_merged_piece("spine_03", trim_parts, _mats["trim"], design)

	if _is_star:
		_add_piece("spine_03", _star_mesh(0.058), _mats["gold"], design, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.060, 0.150)))

func _build_pelvis(style: Dictionary) -> void:
	var design := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.900, 0.0))
	var parts := [
		_part(_box(Vector3(0.380, 0.180, 0.320)), Vector3.ZERO),
		_part(_box(Vector3(0.070, 0.150, 0.260)), Vector3(0.185, -0.020, 0.0)),
		_part(_box(Vector3(0.070, 0.150, 0.260)), Vector3(-0.185, -0.020, 0.0)),
		_part(_box(Vector3(0.300, 0.160, 0.060)), Vector3(0.0, -0.020, -0.145)),
	]
	_add_merged_piece("pelvis", parts, _mats["armour"], design)

func _build_shoulders(style: Dictionary) -> void:
	var pad: float = style["pad"]
	for side in [1.0, -1.0]:
		var bone := "upperarm_l" if side > 0.0 else "upperarm_r"
		var design := Transform3D(Basis.IDENTITY, Vector3(0.235 * side, 1.455, -0.055))
		var parts := [
			_part(_sphere(0.105, 0.210), Vector3(0.0, 0.020 * pad, 0.0), Basis.from_scale(Vector3(1.30, 1.0, 1.40) * pad)),
			_part(_box(Vector3(0.200, 0.050, 0.240) * pad), Vector3(0.0, 0.105 * pad, -0.010)),
		]
		_add_merged_piece(bone, parts, _mats["armour"], design)

func _build_forearms(style: Dictionary) -> void:
	var guard: float = style["shin"]
	for side in [1.0, -1.0]:
		var bone := "lowerarm_l" if side > 0.0 else "lowerarm_r"
		var design := Transform3D(Basis.IDENTITY, Vector3(0.600 * side, 1.441, -0.065))
		var parts := [
			_part(_box(Vector3(0.240, 0.115, 0.145) * guard), Vector3.ZERO),
			_part(_box(Vector3(0.055, 0.150, 0.160)), Vector3(0.100 * side, 0.0, 0.0)),
			_part(_box(Vector3(0.140, 0.050, 0.170)), Vector3(0.0, 0.060, 0.0)),
		]
		_add_merged_piece(bone, parts, _mats["armour_dark"], design)

func _build_gloves(style: Dictionary) -> void:
	var glove: float = style["glove"]
	for side in [1.0, -1.0]:
		var bone := "hand_l" if side > 0.0 else "hand_r"
		var design := Transform3D(Basis.IDENTITY, Vector3(0.800 * side, 1.441, -0.065))
		var parts := [
			_part(_box(Vector3(0.180, 0.115, 0.150) * glove), Vector3.ZERO),
			_part(_box(Vector3(0.100, 0.045, 0.160) * glove), Vector3(0.020 * side, 0.055, 0.010)),
			_part(_box(Vector3(0.055, 0.160, 0.170) * glove), Vector3(-0.080 * side, 0.0, 0.0)),
		]
		if bool(style["goal_pads"]):
			parts.append(_part(_box(Vector3(0.160, 0.170, 0.060) * glove), Vector3(0.020 * side, 0.0, 0.100)))
		_add_merged_piece(bone, parts, _mats["armour_dark"], design)

func _build_legs(style: Dictionary) -> void:
	var thigh_scale: float = style["thigh"]
	var shin_scale: float = style["shin"]
	for side in [1.0, -1.0]:
		var thigh_bone := "thigh_l" if side > 0.0 else "thigh_r"
		var calf_bone := "calf_l" if side > 0.0 else "calf_r"
		var foot_bone := "foot_l" if side > 0.0 else "foot_r"
		var thigh_parts := [
			_part(_box(Vector3(0.170, 0.300, 0.220) * thigh_scale), Vector3.ZERO),
			_part(_box(Vector3(0.180, 0.070, 0.240) * thigh_scale), Vector3(0.0, -0.120, 0.0)),
		]
		_add_merged_piece(thigh_bone, thigh_parts, _mats["armour_dark"], Transform3D(Basis.IDENTITY, Vector3(0.089 * side, 0.720, 0.015)))

		var shin_parts := [
			_part(_box(Vector3(0.160, 0.300, 0.190) * shin_scale), Vector3.ZERO),
			_part(_box(Vector3(0.170, 0.070, 0.200) * shin_scale), Vector3(0.0, 0.120, 0.010)),
		]
		_add_merged_piece(calf_bone, shin_parts, _mats["armour_dark"], Transform3D(Basis.IDENTITY, Vector3(0.089 * side, 0.300, -0.005)))

		if bool(style["goal_pads"]):
			var pad_parts := [
				_part(_box(Vector3(0.210, 0.460, 0.170)), Vector3(0.0, -0.060, 0.055)),
			]
			_add_merged_piece(calf_bone, pad_parts, _mats["armour"], Transform3D(Basis.IDENTITY, Vector3(0.089 * side, 0.300, -0.005)))

		# Skate boot + holder on the foot bone.
		var boot_parts := [
			_part(_box(Vector3(0.150, 0.180, 0.320)), Vector3.ZERO),
			_part(_box(Vector3(0.055, 0.040, 0.160)), Vector3(0.0, -0.095, 0.010)),
			_part(_box(Vector3(0.120, 0.090, 0.140)), Vector3(0.0, 0.135, -0.060)),
		]
		_add_merged_piece(foot_bone, boot_parts, _mats["armour_dark"], Transform3D(Basis.IDENTITY, Vector3(0.089 * side, 0.100, 0.045)))
		var blade_parts := [
			_part(_box(Vector3(0.026, 0.050, 0.380)), Vector3(0.0, -0.115, 0.010)),
		]
		_add_merged_piece(foot_bone, blade_parts, _mats["blade"], Transform3D(Basis.IDENTITY, Vector3(0.089 * side, 0.100, 0.045)))

func _build_jak(style: Dictionary) -> void:
	var design := Transform3D(Basis.IDENTITY, Vector3(0.800, 1.442, -0.060))
	var grip_parts := [
		_part(_cyl(0.026, 0.026, 0.240), Vector3.ZERO, Basis(Vector3(1.0, 0.0, 0.0), PI * 0.5)),
		_part(_box(Vector3(0.150, 0.120, 0.025)), Vector3(0.0, 0.0, 0.100)),
		_part(_box(Vector3(0.100, 0.090, 0.020)), Vector3(0.0, 0.0, -0.120)),
	]
	_add_merged_piece("hand_l", grip_parts, _mats["armour_dark"], design)
	var blade_length: float = 0.88 * float(style["blade"])
	var blade_tilt := Transform3D(Basis(Vector3(1.0, 0.0, 0.0), 0.30), Vector3.ZERO)
	_add_piece("hand_l", _blade_mesh(blade_length), _mats["blade"], design, blade_tilt)

func _build_glow_and_props() -> void:
	# Team light pool under the skater (flat, never animates with bones).
	_glow = MeshInstance3D.new()
	_glow.name = "TeamGlow"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.52
	disc.bottom_radius = 0.52
	disc.height = 0.014
	disc.radial_segments = 24
	_glow.mesh = disc
	_glow.material_override = _mats["glow"]
	_glow.position = Vector3(0.0, 0.014, 0.0)
	_glow.scale = Vector3(1.0, 1.0, 1.32)
	_visual.add_child(_glow)

	# Boost speed streak, behind the skater (+Z in wrapper space).
	_boost_streak = MeshInstance3D.new()
	_boost_streak.name = "BoostStreak"
	var streak := BoxMesh.new()
	streak.size = Vector3(0.52, 0.020, 1.70)
	_boost_streak.mesh = streak
	_boost_streak.material_override = _mats["glow"]
	_boost_streak.position = Vector3(0.0, 0.070, 1.00)
	_boost_streak.visible = false
	_visual.add_child(_boost_streak)

	# Carried rok in the right hand.
	_carry_prop = MeshInstance3D.new()
	_carry_prop.name = "CarriedRok"
	var rok := SphereMesh.new()
	rok.radius = 0.075
	rok.height = 0.150
	rok.radial_segments = 12
	rok.rings = 6
	_carry_prop.mesh = rok
	_carry_prop.material_override = _mats["amber"]
	_carry_prop.visible = false
	var hand_design := Transform3D(Basis.IDENTITY, Vector3(-0.790, 1.452, 0.030))
	var hand_bone := "hand_r"
	_attach_mesh(hand_bone, _carry_prop, hand_design)

# --- geometry helpers ---------------------------------------------------------

func _add_piece(bone_name: String, mesh: Mesh, material: Material, design: Transform3D, extra_local := Transform3D.IDENTITY) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	if material != null:
		mesh_instance.material_override = material
	mesh_instance.transform = extra_local
	if not _attach_mesh(bone_name, mesh_instance, design):
		return null
	return mesh_instance

func _add_merged_piece(bone_name: String, parts: Array, material: Material, design: Transform3D) -> MeshInstance3D:
	var merged := _merge_parts(parts)
	if merged == null:
		return null
	return _add_piece(bone_name, merged, material, design)

func _attach_mesh(bone_name: String, node: Node3D, design: Transform3D) -> bool:
	var attachment := _attachment_for(bone_name)
	if attachment == null:
		return false
	var bone_idx := _skeleton.find_bone(bone_name)
	var bone_rest := _skeleton.get_bone_global_rest(bone_idx)
	var extra := node.transform
	node.transform = bone_rest.affine_inverse() * design * extra
	attachment.add_child(node)
	_grow_design_bounds(design * extra, node)
	return true

func _grow_design_bounds(design: Transform3D, node: Node3D) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var local_aabb := mesh_instance.mesh.get_aabb()
	var design_aabb := design * local_aabb
	if design_aabb.size.y <= 0.0:
		return
	_design_top = maxf(_design_top, design_aabb.end.y)
	_design_bottom = minf(_design_bottom, design_aabb.position.y)

func _attachment_for(bone_name: String) -> BoneAttachment3D:
	if _attach_points.has(bone_name):
		return _attach_points[bone_name] as BoneAttachment3D
	if _skeleton == null or _skeleton.find_bone(bone_name) < 0:
		push_warning("SkaterModel: missing bone " + bone_name)
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "Attach_" + bone_name
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	_attach_points[bone_name] = attachment
	return attachment

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh

func _cyl(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 2
	return mesh

func _part(mesh: Mesh, position := Vector3.ZERO, basis := Basis.IDENTITY) -> Dictionary:
	return {"mesh": mesh, "xf": Transform3D(basis, position)}

func _merge_parts(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var primitive := (part as Dictionary)["mesh"] as Mesh
		var xf := (part as Dictionary)["xf"] as Transform3D
		if primitive == null:
			continue
		st.append_from(primitive, 0, xf)
	return st.commit()

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

func _blade_mesh(length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_z := 0.100
	var mid_z := base_z + length * 0.72
	var tip_z := base_z + length
	var base_w := 0.052
	var base_t := 0.014
	var mid_w := 0.042
	var mid_t := 0.010
	var b0 := Vector3(-base_w, -base_t, base_z)
	var b1 := Vector3(base_w, -base_t, base_z)
	var b2 := Vector3(base_w, base_t, base_z)
	var b3 := Vector3(-base_w, base_t, base_z)
	var m0 := Vector3(-mid_w, -mid_t, mid_z)
	var m1 := Vector3(mid_w, -mid_t, mid_z)
	var m2 := Vector3(mid_w, mid_t, mid_z)
	var m3 := Vector3(-mid_w, mid_t, mid_z)
	var tip := Vector3(0.0, 0.0, tip_z)
	_add_quad(st, b0, b1, b2, b3)
	_add_quad(st, b0, b1, m1, m0)
	_add_quad(st, b3, b2, m2, m3)
	_add_quad(st, b1, b2, m2, m1)
	_add_quad(st, b3, b0, m0, m3)
	st.add_vertex(m0)
	st.add_vertex(m1)
	st.add_vertex(tip)
	st.add_vertex(m1)
	st.add_vertex(m2)
	st.add_vertex(tip)
	st.add_vertex(m2)
	st.add_vertex(m3)
	st.add_vertex(tip)
	st.add_vertex(m3)
	st.add_vertex(m0)
	st.add_vertex(tip)
	st.generate_normals()
	return st.commit()

func _star_mesh(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	for i in range(10):
		var angle := -PI * 0.5 + float(i) * PI / 5.0
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(Vector3(cos(angle) * r, sin(angle) * r, 0.0))
	for i in range(10):
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(points[i])
		st.add_vertex(points[(i + 1) % 10])
	st.generate_normals()
	return st.commit()

# =============================================================================
# State machine
# =============================================================================

func _apply_state(p_state: String, speed_ratio: float) -> void:
	if _anim == null:
		return
	var clip_name := _resolve_clip(p_state, speed_ratio)
	if clip_name.is_empty():
		push_warning("SkaterModel: unknown state '" + p_state + "'")
		return
	if not _anim.has_animation(clip_name):
		push_warning("SkaterModel: clip missing for state '" + p_state + "' -> " + clip_name)
		return
	var loops: bool = LOOP_CLIPS.has(clip_name)
	var speed := _speed_for_state(p_state, speed_ratio)
	var blend := 0.18 if loops else 0.10
	if p_state == "down":
		blend = 0.12
	elif p_state in ["slash", "heavy", "punch", "hook", "attack"]:
		blend = 0.06
	var retrigger := (p_state == _state) and (not loops) and _anim.is_playing()
	if retrigger:
		_anim.seek(0.0, true)
	else:
		_anim.play(clip_name, blend, speed)
	_state = p_state
	_current_clip = clip_name
	if LOCOMOTION_STATES.has(p_state) and p_state != "walk":
		_locomotion_state = p_state
		_locomotion_speed = speed_ratio
	state_changed.emit(p_state)

func _resolve_clip(p_state: String, speed_ratio: float) -> String:
	if p_state == "skate":
		if speed_ratio < 0.28:
			return "walk"
		return "jog_fwd"
	return STATE_CLIP.get(p_state, "")

func _clip_for_state(p_state: String) -> String:
	return STATE_CLIP.get(p_state, "")

func _speed_for_state(p_state: String, speed_ratio: float) -> float:
	var ratio := clampf(speed_ratio, 0.0, 1.0)
	match p_state:
		"idle":
			return 1.0 + ratio * 0.05
		"walk":
			return lerpf(0.85, 1.35, ratio)
		"skate":
			return lerpf(0.85, 1.65, ratio)
		"sprint":
			return lerpf(0.95, 1.45, ratio)
		"goalie":
			return 1.0
		"slide":
			return lerpf(0.85, 1.25, ratio)
		"celebrate":
			return 0.9
		"jump":
			return 1.1
		"air":
			return 1.0
		"land":
			return 1.2
		"hit":
			return 1.15
		_:
			return 1.0

func _on_animation_finished(anim_name: StringName) -> void:
	if not _built:
		return
	var finished_state := _state
	var finished_clip := _current_clip
	if String(anim_name) != finished_clip:
		return
	var return_state := ""
	if ACTION_RETURN_STATES.has(finished_state):
		return_state = _locomotion_state
	elif finished_state == "celebrate":
		return_state = "idle"
	if not return_state.is_empty() and return_state == finished_state:
		return_state = "idle"
	if return_state == "walk":
		return_state = "skate"
	action_finished.emit(finished_state)
	if not return_state.is_empty() and _state == finished_state:
		play(return_state, _locomotion_speed)

# =============================================================================
# One-shot VFX
# =============================================================================

func _burst_anchor(kind: String) -> Vector3:
	match kind:
		"slash", "heavy", "attack", "killball", "electric":
			return Vector3(-0.45, 1.05, -0.30)
		"hit", "impact":
			return Vector3(0.0, 1.20, -0.10)
		"boost":
			return Vector3(0.0, 0.06, 0.30)
		_:
			return Vector3(0.0, 0.0, 0.0)

func _flash_sphere(position: Vector3, color: Color, radius: float, life: float) -> void:
	var mesh := _sphere(radius, radius * 2.0)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var material := _make_flash(color)
	mesh_instance.material_override = material
	mesh_instance.position = position
	mesh_instance.scale = Vector3.ONE * 0.55
	add_child(mesh_instance)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3.ONE * 2.6, life)
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.chain().tween_callback(mesh_instance.queue_free)

func _flash_ring(position: Vector3, color: Color, radius: float, life: float, flat: bool) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.80
	torus.outer_radius = radius
	torus.rings = 10
	torus.ring_segments = 18
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = torus
	var material := _make_flash(color)
	mesh_instance.material_override = material
	mesh_instance.position = position
	mesh_instance.scale = Vector3.ONE * 0.45
	if not flat:
		mesh_instance.rotation.x = PI * 0.5
	mesh_instance.rotation.y = randf() * TAU
	add_child(mesh_instance)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3.ONE * 2.3, life)
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.chain().tween_callback(mesh_instance.queue_free)

func _flash_streak(position: Vector3, color: Color, basis: Basis, life: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.05, 0.9)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var material := _make_flash(color)
	mesh_instance.material_override = material
	mesh_instance.position = position
	mesh_instance.basis = basis
	mesh_instance.scale = Vector3.ONE * 0.6
	add_child(mesh_instance)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3.ONE * 1.9, life)
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.chain().tween_callback(mesh_instance.queue_free)
