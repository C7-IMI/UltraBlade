extends SceneTree

## Headless self-test / benchmark and windowed capture harness for SkaterModel.
##
## Self-test + benchmark (headless, exit code 0 = pass):
##   godot --headless --path game -s res://tools/skater_preview.gd
## Windowed capture, writes artifacts/skater/*.png:
##   godot --path game -s res://tools/skater_preview.gd -- --capture
##
## The self-test also proves: 20-clip shared AnimationLibrary, root motion stripped,
## loops configured, 71-bone rig, ~1.9 m height with feet at y=0, rig facing -Z,
## BoneAttachment3D armour following the animated skeleton, contract states mapping
## to the expected clips, speed_ratio scaling, carrying/boost toggles and burst VFX
## lifetime.

const BLUE := Color(0.129, 0.902, 1.0)
const RED := Color(1.0, 0.176, 0.435)
const PREVIEW_FONT := "res://assets/fonts/Rajdhani-SemiBold.ttf"
const CAPTURE_DIR := "../artifacts/skater/"

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	var user_args := OS.get_cmdline_user_args()
	print("SKATER_PREVIEW_START args=", user_args)
	var world := Node3D.new()
	world.name = "PreviewWorld"
	get_root().add_child(world)
	await process_frame
	await process_frame
	if "--capture" in user_args:
		await _run_capture(world)
	elif "--scene-check" in user_args:
		await _run_scene_check(world)
	else:
		await _run_selftest(world)

# =============================================================================
# Self-test + benchmark
# =============================================================================

func _run_selftest(world: Node3D) -> void:
	print("=== ULTRABLADE SKATER SELF-TEST ===")

	# --- 1. Shared AnimationLibrary (cold build once, cached afterwards) ------
	var started := Time.get_ticks_usec()
	var library := SkaterModel.ensure_library()
	var cold_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_check(library != null, "AnimationLibrary built")
	var clip_names := library.get_animation_list()
	_check(clip_names.size() == 20, "20 clips in shared library (got " + str(clip_names.size()) + ")")
	var root_position_tracks := 0
	for clip_name in clip_names:
		var anim := library.get_animation(clip_name)
		var expect_loop: bool = SkaterModel.LOOP_CLIPS.has(String(clip_name))
		var expected_mode := Animation.LOOP_LINEAR if expect_loop else Animation.LOOP_NONE
		_check(anim.loop_mode == expected_mode, "loop mode " + String(clip_name))
		for track_idx in range(anim.get_track_count()):
			if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
				continue
			if anim.track_get_path(track_idx).get_concatenated_subnames() == "root":
				root_position_tracks += 1
	_check(root_position_tracks == 0, "root position tracks stripped (found " + str(root_position_tracks) + ")")
	var motion_report := SkaterModel.get_root_motion_report()
	var sprint_travel := 0.0
	if motion_report.has("sprint"):
		var sprint_entry: Dictionary = motion_report["sprint"]
		var travel: Vector3 = sprint_entry["travel"]
		sprint_travel = travel.z
	_check(absf(sprint_travel - 5.5) < 0.01, "sprint root travel recorded (z=" + str(snappedf(sprint_travel, 0.001)) + ")")
	var cached_started := Time.get_ticks_usec()
	var library_again := SkaterModel.ensure_library()
	var cached_ms := float(Time.get_ticks_usec() - cached_started) / 1000.0
	_check(library_again == library, "library cached on second call")
	print("SKATER_LIBRARY_CLIPS=" + str(clip_names.size()))
	print("SKATER_LIBRARY_COLD_MS=" + str(snappedf(cold_ms, 0.01)))
	print("SKATER_LIBRARY_REPORTED_MS=" + str(snappedf(SkaterModel.library_build_ms(), 0.01)))
	print("SKATER_LIBRARY_CACHED_MS=" + str(snappedf(cached_ms, 0.001)))
	print("SKATER_ROOT_MOTION_CLIPS=" + str(motion_report.size()))

	# --- 2. One skater per role ----------------------------------------------
	var roles := ["striker", "enforcer", "runner", "anchor", "goalie"]
	var models: Array[SkaterModel] = []
	var build_times: Array[float] = []
	for i in range(roles.size()):
		var model := SkaterModel.new()
		var team := BLUE if i % 2 == 0 else RED
		model.setup(team, roles[i], i == 4)
		world.add_child(model)
		model.position = Vector3(float(i - 2) * 1.2, 0.0, 0.0)
		models.append(model)
		build_times.append(model.get_build_ms())
	await process_frame
	await process_frame
	_check(models.size() == 5, "five role models built")
	var max_build_ms := 0.0
	for value in build_times:
		max_build_ms = maxf(max_build_ms, value)
	_check(max_build_ms < 600.0, "per-model build under 600 ms (max " + str(snappedf(max_build_ms, 0.01)) + " ms)")
	print("SKATER_MODEL_BUILD_MS_MIN=" + str(snappedf(_array_min(build_times), 0.01)))
	print("SKATER_MODEL_BUILD_MS_MEAN=" + str(snappedf(_array_mean(build_times), 0.01)))
	print("SKATER_MODEL_BUILD_MS_MAX=" + str(snappedf(max_build_ms, 0.01)))

	var reference := models[0]
	var skeleton := reference.get_skeleton()
	_check(skeleton != null, "skeleton found")
	if skeleton != null:
		_check(skeleton.get_bone_count() == 71, "71 bones (got " + str(skeleton.get_bone_count()) + ")")
	var animation_player := reference.get_animation_player()
	_check(animation_player != null, "AnimationPlayer present")
	if animation_player != null:
		_check(animation_player.get_animation_list().size() == 20, "AnimationPlayer has 20 animations")

	# --- 3. Structure, height, feet, draw calls -------------------------------
	for model in models:
		var bounds := _model_bounds(model)
		_check(absf(bounds.size.y - 1.9) < 0.05, model.get_role() + " height ~1.9 m (got " + str(snappedf(bounds.size.y, 0.001)) + ")")
		_check(absf(bounds.position.y) < 0.03, model.get_role() + " root at feet y=" + str(snappedf(bounds.position.y, 0.001)))
		_check(model.get_renderable_count() <= 32, model.get_role() + " renderables=" + str(model.get_renderable_count()))
		_check(model.get_attachment_points().size() >= 8, model.get_role() + " bone attachments=" + str(model.get_attachment_points().size()))
	print("SKATER_RENDERABLES_PER_MODEL=" + str(reference.get_renderable_count()))

	# --- 4. Facing: rig is yawed 180 deg so toes point at Godot -Z ------------
	if skeleton != null:
		var foot_idx := skeleton.find_bone("foot_l")
		var ball_idx := skeleton.find_bone("ball_l")
		var skeleton_xform := skeleton.global_transform
		var foot_pos := skeleton_xform * skeleton.get_bone_global_rest(foot_idx).origin
		var ball_pos := skeleton_xform * skeleton.get_bone_global_rest(ball_idx).origin
		_check(ball_pos.z < foot_pos.z - 0.05, "faces Godot -Z (toe z=" + str(snappedf(ball_pos.z, 0.001)) + " ankle z=" + str(snappedf(foot_pos.z, 0.001)) + ")")

	# --- 5. Animation drives skeleton; root motion stays stripped -------------
	if skeleton != null and animation_player != null:
		reference.play("sprint", 1.0)
		animation_player.advance(0.25)
		var head_idx := skeleton.find_bone("Head")
		var head_rest := skeleton.get_bone_global_rest(head_idx).origin
		var head_posed := skeleton.get_bone_global_pose(head_idx).origin
		_check((head_posed - head_rest).length() > 0.01, "sprint deforms skeleton (delta " + str(snappedf((head_posed - head_rest).length(), 0.001)) + " m)")
		var root_pose := skeleton.get_bone_global_pose(0).origin
		_check(root_pose.length() < 0.01, "root bone stays in place after strip (len " + str(snappedf(root_pose.length(), 0.0001)) + ")")

	# --- 6. BoneAttachment3D armour follows the animated bone -----------------
	var head_attachment: BoneAttachment3D = null
	for node in reference.find_children("*", "BoneAttachment3D", true, false):
		if (node as BoneAttachment3D).bone_name == "Head":
			head_attachment = node
	_check(head_attachment != null, "Head BoneAttachment3D present")
	if head_attachment != null and skeleton != null and animation_player != null:
		var head_idx2 := skeleton.find_bone("Head")
		var expected := skeleton.global_transform * skeleton.get_bone_global_pose(head_idx2)
		var helmet_pos := head_attachment.global_transform.origin
		_check(helmet_pos.distance_to(expected.origin) < 0.6, "helmet follows head bone (d=" + str(snappedf(helmet_pos.distance_to(expected.origin), 0.001)) + " m)")
		var before := head_attachment.global_transform.origin
		animation_player.advance(0.2)
		await process_frame
		var after := head_attachment.global_transform.origin
		_check(before.distance_to(after) > 0.002, "attachment tracks animation (moved " + str(snappedf(before.distance_to(after), 0.001)) + " m)")

	# --- 7. Contract states map to clips --------------------------------------
	if animation_player != null:
		var expected_states := {
			"idle": "sword_idle",
			"skate": "jog_fwd",
			"sprint": "sprint",
			"slash": "sword_regular_a",
			"heavy": "sword_attack",
			"hit": "hit_chest",
			"down": "death01",
			"celebrate": "sword_regular_combo",
			"goalie": "sword_idle",
		}
		for state in expected_states.keys():
			reference.play(String(state), 0.6)
			var expected_clip: String = expected_states[state]
			var actual_clip := String(animation_player.current_animation)
			_check(actual_clip == expected_clip, "state " + String(state) + " -> " + expected_clip + " (got " + actual_clip + ")")
			_check(reference.get_state() == String(state), "state getter " + String(state))
		reference.play("skate", 0.05)
		_check(String(animation_player.current_animation) == "walk", "low speed skate uses walk clip")
		reference.play("skate", 0.95)
		var fast_speed := animation_player.get_playing_speed()
		reference.play("skate", 0.15)
		var slow_speed := animation_player.get_playing_speed()
		_check(fast_speed > slow_speed + 0.1, "speed_ratio scales cycle speed (" + str(snappedf(slow_speed, 0.01)) + " -> " + str(snappedf(fast_speed, 0.01)) + ")")

		# one-shot retrigger + auto-return to locomotion
		reference.play("skate", 0.8)
		reference.play("slash", 0.0)
		reference.play("slash", 0.0)
		_check(String(animation_player.current_animation) == "sword_regular_a", "slash retrigger safe")
		reference.play("hit", 0.0)
		animation_player.advance(0.6)
		await process_frame
		_check(reference.get_state() == "skate", "hit auto-returns to locomotion (got " + reference.get_state() + ")")

	# --- 8. Carrying / boost / burst -----------------------------------------
	reference.set_carrying(true)
	_check(reference.is_carrying(), "set_carrying(true)")
	reference.set_carrying(false)
	_check(not reference.is_carrying(), "set_carrying(false)")
	reference.set_boost(true)
	_check(reference.is_boosting(), "set_boost(true)")
	reference.set_boost(false)
	_check(not reference.is_boosting(), "set_boost(false)")
	var children_before := reference.get_child_count()
	for kind in ["slash", "heavy", "hit", "boost", "goal", "killball", "spawn"]:
		reference.burst(String(kind))
	await process_frame
	_check(reference.get_child_count() > children_before, "burst spawns VFX (" + str(reference.get_child_count() - children_before) + " nodes)")
	reference.burst("hit", Vector3(0.0, 1.0, 0.0))
	await create_timer(1.0).timeout
	_check(reference.get_child_count() <= children_before, "burst VFX free themselves (children=" + str(reference.get_child_count()) + ")")

	# --- 9. Repeated playback (Lead calls play() on every speed change) ------
	if animation_player != null:
		reference.play("sprint", 1.0)
		animation_player.advance(0.30)
		var phase_before := animation_player.current_animation_position
		reference.play("sprint", 1.0)
		var phase_after := animation_player.current_animation_position
		_check(phase_after >= phase_before - 0.02, "repeat play same clip keeps phase (" + str(snappedf(phase_before, 0.01)) + " -> " + str(snappedf(phase_after, 0.01)) + ")")
		var speed_before := animation_player.get_playing_speed()
		reference.play("sprint", 0.2)
		var speed_after := animation_player.get_playing_speed()
		_check(speed_after < speed_before - 0.05, "same-clip speed update applies (" + str(snappedf(speed_before, 0.01)) + " -> " + str(snappedf(speed_after, 0.01)) + ")")

	# --- 10. Lead integration order: add_child() first, setup() second -------
	var ordered := SkaterModel.new()
	world.add_child(ordered)
	ordered.setup(RED, "enforcer", true)
	await process_frame
	_check(ordered.get_role() == "enforcer", "late setup applies role after add_child (got " + ordered.get_role() + ")")
	_check(ordered.get_team_color() == RED, "late setup applies team colour after add_child")
	_check(String(ordered.get_animation_player().current_animation) == "sword_idle", "late setup keeps an animation playing")
	_check(absf(_model_bounds(ordered).size.y - 1.9) < 0.05, "late setup height ~1.9 m")
	ordered.queue_free()

	# --- 11. Six-skater squad benchmark --------------------------------------
	var squad_started := Time.get_ticks_usec()
	var squad: Array[SkaterModel] = []
	for i in range(6):
		var member := SkaterModel.new()
		var team := BLUE if i % 2 == 0 else RED
		member.setup(team, roles[i % roles.size()], i == 0)
		world.add_child(member)
		member.position = Vector3(float(i - 3) * 1.15, 0.0, 2.4)
		squad.append(member)
	var squad_ms := float(Time.get_ticks_usec() - squad_started) / 1000.0
	await process_frame
	await process_frame
	_check(squad.size() == 6, "six-skater squad built")
	_check(squad_ms < 2500.0, "six-skater build under 2.5 s (" + str(snappedf(squad_ms, 0.01)) + " ms)")
	for member in squad:
		member.play("sprint", 0.8)
	await process_frame
	print("SKATER_SQUAD_BUILD_MS=" + str(snappedf(squad_ms, 0.01)))
	print("SKATER_SQUAD_RENDERABLES=" + str(_squad_renderables(squad)))

	# --- summary -------------------------------------------------------------
	for model in squad:
		model.queue_free()
	if _failures.is_empty():
		print("SKATER_SELFTEST_PASS checks=" + str(_checks))
		quit(0)
	else:
		for failure in _failures:
			print("FAIL: " + failure)
		print("SKATER_SELFTEST_FAIL failed=" + str(_failures.size()) + " checks=" + str(_checks))
		quit(1)

# =============================================================================
# Standalone preview-scene check (res://tools/skater_preview.tscn)
# =============================================================================

func _run_scene_check(world: Node3D) -> void:
	print("=== SKATER PREVIEW SCENE CHECK ===")
	var packed := load("res://tools/skater_preview.tscn") as PackedScene
	_check(packed != null, "preview scene loads")
	if packed == null:
		print("SKATER_SCENE_CHECK_FAIL failed=1")
		quit(1)
		return
	var scene := packed.instantiate()
	world.add_child(scene)
	await process_frame
	await process_frame
	var skaters: Array[SkaterModel] = []
	for node in scene.find_children("*", "Node3D", true, false):
		if node is SkaterModel:
			skaters.append(node)
	_check(skaters.size() == 5, "preview scene has 5 skaters (got " + str(skaters.size()) + ")")
	var role_set := {}
	var all_height_ok := true
	for skater in skaters:
		role_set[skater.get_role()] = true
		_check(skater.is_built(), skater.get_role() + " built in preview scene")
		var height := _model_bounds(skater).size.y
		if absf(height - 1.9) > 0.05:
			all_height_ok = false
	_check(all_height_ok, "preview scene skaters ~1.9 m")
	for expected_role in ["striker", "enforcer", "runner", "anchor", "goalie"]:
		_check(role_set.has(expected_role), "preview scene contains " + expected_role)
	var camera := scene.find_child("Camera3D", true, false) as Camera3D
	_check(camera != null, "preview scene has a camera")
	if camera != null:
		var forward := -camera.global_transform.basis.z
		_check(forward.z > 0.5, "preview camera looks at skater fronts (forward=" + str(forward) + ")")
	print("SKATER_SCENE_SKATERS=" + str(skaters.size()))
	if _failures.is_empty():
		print("SKATER_SCENE_CHECK_PASS checks=" + str(_checks))
		quit(0)
	else:
		for failure in _failures:
			print("FAIL: " + failure)
		print("SKATER_SCENE_CHECK_FAIL failed=" + str(_failures.size()) + " checks=" + str(_checks))
		quit(1)

# =============================================================================
# Capture mode
# =============================================================================

func _run_capture(world: Node3D) -> void:
	print("=== ULTRABLADE SKATER CAPTURE ===")
	if DisplayServer.get_name() == "headless":
		print("CAPTURE_SKIPPED=headless display server")
		quit(0)
		return
	var camera := _build_stage(world)
	var roles := ["striker", "enforcer", "runner", "anchor", "goalie"]
	var lineup: Array[SkaterModel] = []
	var labels: Array[Label3D] = []
	for i in range(roles.size()):
		var model := SkaterModel.new()
		var team := BLUE if i % 2 == 0 else RED
		model.setup(team, roles[i], i == 4)
		world.add_child(model)
		model.position = Vector3(float(2 - i) * 1.42, 0.0, 0.0)
		lineup.append(model)
		labels.append(_add_label(world, roles[i].to_upper(), Vector3(float(2 - i) * 1.42, 2.18, 0.0), team))

	# Shot 1: role lineup, front view.
	await _wait_frames(45)
	await _save_viewport("lineup_front.png")
	print("CAPTURE_HEIGHTS=" + _capture_heights(lineup))

	# Shot 2: duel action pose (striker slash vs enforcer heavy).
	for i in range(lineup.size()):
		lineup[i].visible = i == 0 or i == 1
		labels[i].visible = false
	lineup[0].position = Vector3(-0.55, 0.0, 0.25)
	lineup[1].position = Vector3(0.80, 0.0, 0.0)
	lineup[0].play("slash", 0.0)
	lineup[0].get_animation_player().advance(0.24)
	lineup[1].play("heavy", 0.0)
	lineup[1].get_animation_player().advance(0.62)
	lineup[0].get_animation_player().speed_scale = 0.0
	lineup[1].get_animation_player().speed_scale = 0.0
	lineup[1].set_boost(true)
	lineup[1].burst("slash")
	camera.global_position = Vector3(0.30, 1.42, -4.10)
	camera.look_at(Vector3(0.05, 1.05, 0.15), Vector3.UP)
	camera.fov = 38.0
	await _wait_frames(10)
	await _save_viewport("duel_action.png")

	# Shot 3: star goalie closeup, carrying the rok and boosting.
	for i in range(lineup.size()):
		lineup[i].visible = false
	var star := lineup[4]
	star.visible = true
	star.position = Vector3(0.0, 0.0, 0.0)
	star.play("goalie", 0.0)
	star.get_animation_player().advance(0.9)
	star.get_animation_player().speed_scale = 0.2
	star.set_carrying(true)
	star.set_boost(true)
	camera.global_position = Vector3(0.10, 1.30, -2.80)
	camera.look_at(Vector3(0.0, 1.12, 0.05), Vector3.UP)
	camera.fov = 44.0
	await _wait_frames(30)
	await _save_viewport("star_goalie_closeup.png")
	print("CAPTURE_DONE")
	await _wait_frames(2)
	quit(0)

func _build_stage(world: Node3D) -> Camera3D:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.008, 0.012, 0.030)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.16, 0.24, 0.40)
	environment.ambient_light_energy = 0.45
	environment.glow_enabled = true
	environment.glow_intensity = 1.15
	environment.glow_bloom = 0.18
	environment.glow_hdr_threshold = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(0.78, 0.90, 1.0)
	key_light.light_energy = 1.7
	key_light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	key_light.shadow_enabled = true
	world.add_child(key_light)

	var blue_light := OmniLight3D.new()
	blue_light.light_color = BLUE
	blue_light.light_energy = 5.0
	blue_light.omni_range = 8.0
	blue_light.position = Vector3(-2.6, 1.2, -2.1)
	world.add_child(blue_light)

	var red_light := OmniLight3D.new()
	red_light.light_color = RED
	red_light.light_energy = 5.0
	red_light.omni_range = 9.0
	red_light.position = Vector3(2.6, 1.6, 2.2)
	world.add_child(red_light)

	var rim_light := OmniLight3D.new()
	rim_light.light_color = Color(0.45, 0.65, 1.0)
	rim_light.light_energy = 4.0
	rim_light.omni_range = 9.0
	rim_light.position = Vector3(0.0, 3.2, 2.6)
	world.add_child(rim_light)

	var floor_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(26.0, 26.0)
	floor_instance.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.014, 0.024, 0.045)
	floor_material.metallic = 0.65
	floor_material.roughness = 0.20
	floor_instance.material_override = floor_material
	world.add_child(floor_instance)

	var camera := Camera3D.new()
	camera.fov = 42.0
	world.add_child(camera)
	camera.global_position = Vector3(0.0, 1.62, -5.6)
	camera.look_at(Vector3(0.0, 1.02, 0.0), Vector3.UP)
	camera.current = true
	return camera

func _add_label(world: Node3D, text: String, position: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 56
	label.pixel_size = 0.0034
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = position
	var font := load(PREVIEW_FONT) as FontFile
	if font != null:
		label.font = font
	world.add_child(label)
	return label

func _wait_frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _save_viewport(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var directory := ProjectSettings.globalize_path("res://").path_join(CAPTURE_DIR).simplify_path()
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(file_name)
	var error := image.save_png(path)
	if error == OK:
		print("CAPTURE_SAVED=" + path + " " + str(image.get_width()) + "x" + str(image.get_height()))
	else:
		print("CAPTURE_FAILED=" + path + " err=" + str(error))

func _capture_heights(models: Array[SkaterModel]) -> String:
	var parts: Array[String] = []
	for model in models:
		parts.append(model.get_role() + ":" + str(snappedf(_model_bounds(model).size.y, 0.01)))
	return " ".join(parts)

# =============================================================================
# Helpers
# =============================================================================

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

func _model_bounds(model: SkaterModel) -> AABB:
	var inverse := model.global_transform.affine_inverse()
	var merged := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var world_box: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		var local_box: AABB = inverse * world_box
		if first:
			merged = local_box
			first = false
		else:
			merged = merged.merge(local_box)
	return merged

func _squad_renderables(squad: Array[SkaterModel]) -> int:
	var total := 0
	for member in squad:
		total += member.get_renderable_count()
	return total

func _array_min(values: Array[float]) -> float:
	var result := INF
	for value in values:
		result = minf(result, value)
	return result

func _array_mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())
