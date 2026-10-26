extends SceneTree

## Windowed proof for the elliptical bowl, bank riding and team-selection palette.
## Run: godot --path game -s res://tools/team_bowl_preview.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(8):
		await process_frame
	# Pick a visually distinct home/away matchup (Cobalt Kings vs Solar Kings).
	for i in range(1):
		main._on_team_cycle_requested("home")
	for i in range(3):
		main._on_team_cycle_requested("away")
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://") + "../artifacts/captures"
	DirAccess.make_dir_recursive_absolute(dir)
	var menu_path := dir + "/06-team-select.png"
	var err := root.get_texture().get_image().save_png(menu_path)
	print("TEAM_BOWL_CAPTURE menu=", menu_path, " err=", err, " home=", main.get_team_name(0), " away=", main.get_team_name(1))
	# Put the controlled skater high on the bank and let the chase camera resolve.
	main.start_match()
	main.state = 2
	main.state_timer = 0.0
	for i in range(3):
		await process_frame
	var sk = main.get_controlled_skater()
	if sk == null:
		print("TEAM_BOWL_CAPTURE no skater")
		quit(1)
		return
	sk.global_position = Vector3(12.0, main.get_surface_height(12.0, 0.0), 0.0)
	sk.velocity = Vector3.ZERO
	sk._grounded = true
	main.camera_rig.set_mode("chase")
	main.camera_rig.set_target(sk)
	main.camera_rig.distance = 8.2
	main.camera_rig.pitch = 0.18
	main.camera_rig.yaw = PI * 0.86
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var bank_path := dir + "/07-bank-ride.png"
	var err2 := root.get_texture().get_image().save_png(bank_path)
	print("TEAM_BOWL_CAPTURE bank=", bank_path, " err=", err2, " y=", sk.global_position.y, " surface=", main.get_surface_height(sk.global_position.x, sk.global_position.z))
	# Capture the light-slash swing mid-animation.
	main.camera_rig.distance = 4.4
	main.camera_rig.height = 1.7
	main.camera_rig.pitch = 0.10
	for i in range(6):
		await process_frame
	sk.action_lock = 0.0
	sk.slash_cd = 0.0
	sk.try_slash(false)
	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var slash_path := dir + "/08-slash.png"
	var err3 := root.get_texture().get_image().save_png(slash_path)
	print("TEAM_BOWL_CAPTURE slash=", slash_path, " err=", err3, " state=", sk.model.get_state(), " clip=", sk.model.get_current_clip())
	# Capture the actual in-match skating loop with the player pushing forward.
	main.camera_rig.distance = 7.4
	main.camera_rig.height = 3.0
	main.camera_rig.pitch = 0.24
	main.camera_rig.yaw = PI
	sk.global_position = Vector3(0.0, main.get_surface_height(0.0, 0.0), -2.0)
	sk.velocity = Vector3.ZERO
	sk._grounded = true
	var ev_down := InputEventKey.new()
	ev_down.physical_keycode = KEY_W
	ev_down.keycode = KEY_W
	ev_down.pressed = true
	Input.parse_input_event(ev_down)
	for i in range(32):
		await process_frame
	await RenderingServer.frame_post_draw
	var skate_path := dir + "/09-skate.png"
	var err4 := root.get_texture().get_image().save_png(skate_path)
	var ev_up := InputEventKey.new()
	ev_up.physical_keycode = KEY_W
	ev_up.keycode = KEY_W
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	print("TEAM_BOWL_CAPTURE skate=", skate_path, " err=", err4, " state=", sk.model.get_state(), " clip=", sk.model.get_current_clip(), " speed=", sk.velocity.length())
	# Close-up of the inline-skate cycle and glowing wheels.
	main.camera_rig.distance = 3.2
	main.camera_rig.height = 1.7
	main.camera_rig.pitch = 0.10
	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var close_path := dir + "/10-skate-close.png"
	var err5 := root.get_texture().get_image().save_png(close_path)
	print("TEAM_BOWL_CAPTURE skate_close=", close_path, " err=", err5)
	if main.audio != null:
		main.audio.free()
		main.audio = null
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	main.queue_free()
	for i in range(3):
		await process_frame
	quit(0)
