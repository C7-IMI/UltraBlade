extends Node3D

## ULTRABLADE arena preview + self-test.
## Headless self-test:
##   godot --headless --path game res://tools/arena_preview.tscn -- --selftest
## Windowed captures (writes PNGs then quits):
##   godot --path game res://tools/arena_preview.tscn -- --capture <absolute dir>
## Windowed free look: run the scene with no arguments.

var _arena: Dictionary = {}
var _camera: Camera3D
var _orbit_time := 0.0
var _orbit := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var selftest := "--selftest" in args
	var capture_dir := ""
	for i in args.size():
		if args[i] == "--capture" and i + 1 < args.size():
			capture_dir = args[i + 1]
	_arena = ArenaBuilder.build(self)
	if selftest:
		var ok := _run_selftest()
		print("ARENA_SELFTEST_" + ("OK" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
		return
	_setup_camera()
	if capture_dir != "":
		await _capture(capture_dir)
	else:
		_orbit = true

func _process(delta: float) -> void:
	if not _orbit or _camera == null:
		return
	_orbit_time += delta
	var a := _orbit_time * 0.18
	_camera.global_position = Vector3(sin(a) * 17.0, 6.5 + sin(a * 0.7) * 1.5, cos(a) * 26.0)
	_camera.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = 72.0
	_camera.near = 0.1
	_camera.far = 240.0
	add_child(_camera)
	_camera.current = true

func _run_selftest() -> bool:
	var failures: Array[String] = []
	var checks := {"total": 0}
	var keys := ["root", "player_goal", "enemy_goal", "spawn_blue", "spawn_red", "center_spawn", "boost_pads", "hazards", "killball_charger", "bounds"]
	for key in keys:
		_check(_arena.has(key), "contract key '%s'" % key, failures, checks)
	if _arena.is_empty():
		print("ARENA_SELFTEST_FAIL empty dictionary")
		return false
	var root: Node3D = _arena["root"]
	var player_goal: Area3D = _arena["player_goal"]
	var enemy_goal: Area3D = _arena["enemy_goal"]
	var spawn_blue: Array = _arena["spawn_blue"]
	var spawn_red: Array = _arena["spawn_red"]
	var boost_pads: Array = _arena["boost_pads"]
	var hazards: Array = _arena["hazards"]
	var charger: Area3D = _arena["killball_charger"]
	var bounds: Dictionary = _arena["bounds"]
	_check(root is Node3D and root.name == "Drome", "root is Node3D named Drome", failures, checks)
	_check(root.get_parent() == self, "root parented to build parent", failures, checks)
	_check(player_goal is Area3D and player_goal.is_in_group("goal_blue"), "player_goal Area3D in group goal_blue", failures, checks)
	_check(enemy_goal is Area3D and enemy_goal.is_in_group("goal_red"), "enemy_goal Area3D in group goal_red", failures, checks)
	_check(absf(player_goal.position.z + 30.5) < 0.01, "player_goal at z=-30.5", failures, checks)
	_check(absf(enemy_goal.position.z - 30.5) < 0.01, "enemy_goal at z=+30.5", failures, checks)
	_check(spawn_blue.size() >= 3 and _all_transforms(spawn_blue), "spawn_blue >=3 Transform3D", failures, checks)
	_check(spawn_red.size() >= 3 and _all_transforms(spawn_red), "spawn_red >=3 Transform3D", failures, checks)
	_check(_has_outfield_and_goalie(spawn_blue, -1.0), "spawn_blue 2 outfield + goalie on blue side", failures, checks)
	_check(_has_outfield_and_goalie(spawn_red, 1.0), "spawn_red 2 outfield + goalie on red side", failures, checks)
	_check(_arena["center_spawn"] is Transform3D, "center_spawn is Transform3D", failures, checks)
	_check(boost_pads.size() == 4, "4 boost pads", failures, checks)
	var pads_ok := true
	for pad in boost_pads:
		if not (pad is Node3D) or not pad.has_method("get_team"):
			pads_ok = false
	_check(pads_ok, "boost pads are Node3D with get_team()", failures, checks)
	_check(hazards.size() == 4, "4 hazards (2 turnstiles + 2 laser strips)", failures, checks)
	var hazards_ok := true
	for hazard in hazards:
		if not (hazard is Node3D):
			hazards_ok = false
	_check(hazards_ok, "hazards are Node3D", failures, checks)
	_check(charger is Area3D and charger.is_in_group("killball_charger"), "killball_charger Area3D in group killball_charger", failures, checks)
	_check(bounds.get("half_width", 0.0) == 16.0 and bounds.get("half_length", 0.0) == 30.0, "bounds 16.0 x 30.0", failures, checks)
	# rebuild must clear the previous drome
	var second: Dictionary = ArenaBuilder.build(self)
	var drome_children := 0
	for child in get_children():
		if child.name == "Drome":
			drome_children += 1
	_check(drome_children == 1, "rebuild leaves exactly one Drome (clears old)", failures, checks)
	root = second.get("root", null)
	# collider + floor contract
	var collider_stats := {"static_bodies": 0, "shapes": 0, "floor_bodies": 0}
	_collect_colliders(root, collider_stats)
	_check(collider_stats["static_bodies"] >= 3, "static collider bodies present (boards + goals + obstacles)", failures, checks)
	_check(collider_stats["shapes"] >= 10, "collision shapes >= 10", failures, checks)
	_check(collider_stats["floor_bodies"] == 0, "no floor collision body (owned by match layer)", failures, checks)
	var mesh_stats := {"draws": 0, "tris": 0, "lights": 0, "multimesh_instances": 0}
	_collect_stats(root, mesh_stats)
	_check(mesh_stats["draws"] < 400, "draw calls < 400 (got %d)" % mesh_stats["draws"], failures, checks)
	_check(mesh_stats["tris"] < 60000, "triangles < 60k (got %d)" % mesh_stats["tris"], failures, checks)
	_check(mesh_stats["lights"] >= 1, "at least one light", failures, checks)
	_check(mesh_stats["multimesh_instances"] > 500, "crowd MultiMesh > 500 instances (got %d)" % mesh_stats["multimesh_instances"], failures, checks)
	print("ARENA_STATS draws=%d tris=%d lights=%d crowd=%d static_bodies=%d shapes=%d" % [mesh_stats["draws"], mesh_stats["tris"], mesh_stats["lights"], mesh_stats["multimesh_instances"], collider_stats["static_bodies"], collider_stats["shapes"]])
	print("ARENA_SPAWNS blue=%d red=%d boost=%d hazards=%d player_goal_z=%.1f enemy_goal_z=%.1f" % [spawn_blue.size(), spawn_red.size(), boost_pads.size(), hazards.size(), -30.5, 30.5])
	print("ARENA_CHECKS passed=%d failed=%d" % [int(checks["total"]) - failures.size(), failures.size()])
	return failures.is_empty()

func _check(cond: bool, label: String, failures: Array[String], checks: Dictionary) -> void:
	checks["total"] = int(checks["total"]) + 1
	if cond:
		print("CHECK OK   " + label)
	else:
		print("CHECK FAIL " + label)
		failures.append(label)

func _all_transforms(list: Array) -> bool:
	for item in list:
		if not (item is Transform3D):
			return false
	return true

func _has_outfield_and_goalie(spawns: Array, side: float) -> bool:
	var outfield := 0
	var goalie := 0
	for t in spawns:
		if not (t is Transform3D):
			return false
		var p: Vector3 = t.origin
		if p.z * side <= 0.0:
			return false
		if absf(p.z) >= 24.0:
			goalie += 1
		elif absf(p.z) <= 22.0:
			outfield += 1
	return outfield >= 2 and goalie >= 1

func _collect_colliders(node: Node, stats: Dictionary) -> void:
	if node is StaticBody3D:
		stats["static_bodies"] = int(stats["static_bodies"]) + 1
		if node.name.to_lower().contains("floor"):
			stats["floor_bodies"] = int(stats["floor_bodies"]) + 1
	if node is CollisionShape3D:
		stats["shapes"] = int(stats["shapes"]) + 1
	for child in node.get_children():
		_collect_colliders(child, stats)

func _collect_stats(node: Node, stats: Dictionary) -> void:
	var counted := false
	if node is MultiMeshInstance3D:
		stats["draws"] = int(stats["draws"]) + 1
		var mm: MultiMesh = node.multimesh
		if mm != null and mm.mesh != null:
			stats["tris"] = int(stats["tris"]) + int(mm.mesh.get_faces().size() / 3) * mm.instance_count
			stats["multimesh_instances"] = int(stats["multimesh_instances"]) + mm.instance_count
		counted = true
	elif node is MeshInstance3D:
		stats["draws"] = int(stats["draws"]) + 1
		var mesh: Mesh = node.mesh
		if mesh != null:
			stats["tris"] = int(stats["tris"]) + int(mesh.get_faces().size() / 3)
		counted = true
	elif node is Label3D:
		stats["draws"] = int(stats["draws"]) + 1
		counted = true
	elif node is GPUParticles3D:
		stats["draws"] = int(stats["draws"]) + 1
		counted = true
	if node is Light3D:
		stats["lights"] = int(stats["lights"]) + 1
	for child in node.get_children():
		_collect_stats(child, stats)

func _capture(dir: String) -> void:
	var abs_dir := ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir
	DirAccess.make_dir_recursive_absolute(abs_dir)
	_setup_camera()
	var shots := [
		{"name": "arena_hero", "pos": Vector3(8.5, 4.6, -28.5), "look": Vector3(0.0, 1.2, 2.0), "fov": 72.0},
		{"name": "arena_center", "pos": Vector3(0.0, 3.3, -14.5), "look": Vector3(0.0, 1.0, 3.0), "fov": 74.0},
		{"name": "arena_goal", "pos": Vector3(0.0, 3.4, 21.5), "look": Vector3(0.0, 1.3, 31.3), "fov": 68.0},
		{"name": "arena_overview", "pos": Vector3(0.0, 27.0, -47.0), "look": Vector3(0.0, 1.5, 2.0), "fov": 58.0},
		{"name": "arena_jumbo", "pos": Vector3(0.0, 7.5, -16.0), "look": Vector3(0.0, 13.6, 0.0), "fov": 66.0},
	]
	_camera.current = true
	for i in 20:
		await get_tree().process_frame
	for shot in shots:
		_camera.fov = shot["fov"]
		_camera.global_position = shot["pos"]
		_camera.look_at(shot["look"], Vector3.UP)
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := abs_dir.path_join(shot["name"] + ".png")
		var err := img.save_png(path)
		print("ARENA_CAPTURE name=%s err=%d size=%dx%d path=%s" % [shot["name"], err, img.get_width(), img.get_height(), path])
	await get_tree().process_frame
	get_tree().quit(0)
