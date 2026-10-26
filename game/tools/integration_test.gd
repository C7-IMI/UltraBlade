extends SceneTree

## End-to-end integration test: boots the real match scene, drives the player with
## synthetic input, fires a charged shot, verifies an actual puck goal and a goalie save.
## Run: godot --headless --path game -s res://tools/integration_test.gd

var main: Node
var failures: Array = []
var checks := 0

func _init() -> void:
    call_deferred("_run")

func _check(ok: bool, label: String) -> void:
    checks += 1
    if ok:
        print("INTEGRATION_OK ", label)
    else:
        failures.append(label)
        print("INTEGRATION_FAIL ", label)

func _key(code: int, pressed: bool) -> void:
    var ev := InputEventKey.new()
    ev.physical_keycode = code
    ev.keycode = code
    ev.pressed = pressed
    Input.parse_input_event(ev)

func _mouse_left(pressed: bool) -> void:
    var ev := InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_LEFT
    ev.pressed = pressed
    Input.parse_input_event(ev)

func _run() -> void:
    var packed: PackedScene = load("res://scenes/main.tscn")
    _check(packed != null, "main_scene_loads")
    main = packed.instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await physics_frame
    _check(main.all_skaters.size() == 6, "six_skaters_boot")
    _check(main.arena_data.get("bounds", {}).has("half_width"), "arena_contract_present")
    _check(main.get_drome_bounds().get("half_length", 0.0) == 30.0, "arena_bounds_30m")
    # The drome must be a curved elliptical bowl, not a flat rectangle.
    _check(absf(main.get_surface_height(0.0, 0.0)) < 0.02, "bowl_center_flat")
    _check(main.get_surface_height(12.0, 0.0) > 1.0, "bowl_bank_rises")
    _check(main.get_surface_height(0.0, 26.0) < 0.02, "bowl_goal_lane_flat")
    _check(main.get_surface_normal(12.0, 0.0).y > 0.45, "bowl_bank_normal")
    # Team diversity: four squads per side, live recolour and HUD identity.
    _check(main.HOME_TEAMS.size() >= 4 and main.AWAY_TEAMS.size() >= 4, "team_catalog_has_four_per_side")
    var home_before: int = main.home_team_index
    var color_before: Color = main.blue_team[0].team_color
    main._on_team_cycle_requested("home")
    main._on_team_cycle_requested("away")
    await process_frame
    await process_frame
    _check(main.home_team_index != home_before, "home_team_cycles")
    _check(main.blue_team[0].team_color != color_before, "home_team_recolours_skaters")
    _check(main.hud.blue_name_label.text == main.get_team_name(0), "hud_home_team_name")
    _check(main.hud.red_name_label.text == main.get_team_name(1), "hud_away_team_name")
    main.start_match()
    main.state = 2 # PLAYING
    main.state_timer = 0.0
    Engine.time_scale = 1.0
    await physics_frame
    var sk = main.get_controlled_skater()
    _check(sk != null, "controlled_skater")
    _check(sk.model != null, "actionforge_model_attached")
    # Drive with W.
    if sk != null:
        sk.global_position = Vector3(0, 0, -5)
        sk.velocity = Vector3.ZERO
        var start = sk.global_position
        _key(KEY_W, true)
        for i in range(35):
            await physics_frame
        _key(KEY_W, false)
        await physics_frame
        _check(sk.global_position.distance_to(start) > 1.5, "wasd_moves_player")
        var coast_speed := Vector2(sk.velocity.x, sk.velocity.z).length()
        for i in range(20):
            await physics_frame
        _check(Vector2(sk.velocity.x, sk.velocity.z).length() > 6.0, "skates_glide_coast")
        _check(coast_speed > 6.0, "skates_build_speed")
        _check(sk.model != null and sk.model.get_state() == "skate", "player_uses_skate_state")
        _check(sk.model != null and sk.model.get_current_clip() == "skate", "player_uses_skate_cycle")
        # Land a skater on the skateable bank and verify the height-field snap.
        var bank_y: float = main.get_surface_height(11.5, 0.0)
        sk.global_position = Vector3(11.5, bank_y + 1.6, 0.0)
        sk.velocity = Vector3.ZERO
        sk._grounded = false
        for i in range(20):
            await physics_frame
        _check(absf(sk.global_position.y - main.get_surface_height(sk.global_position.x, sk.global_position.z)) < 0.20, "skater_lands_on_bank")
    # Charged shot through the real input path.
    var puck = main.get_puck()
    puck.reset_to(sk.get_puck_anchor())
    puck.attach_to(sk)
    await physics_frame
    _mouse_left(true)
    for i in range(20):
        await physics_frame
    _mouse_left(false)
    await process_frame
    await physics_frame
    await physics_frame
    _check(puck.carrier == null and puck.velocity.length() > 12.0, "charged_shot_fires")
    # Actual puck goal at the enemy end (no forced score).
    main.state = 2
    main.score_blue = 0
    main.score_red = 0
    main.goal_scorer = null
    main.red_team[2].downed = true # isolate goal-plane detection from the keeper
    main.puck.set_physics_process(true)
    main.puck.reset_to(Vector3(0.0, 0.34, 29.0))
    main.puck.velocity = Vector3(0.0, 0.5, 22.0)
    main.puck.last_shooter = sk
    main.puck.last_team = 0
    main.puck.pickup_lock = 1.0
    for i in range(20):
        await physics_frame
    _check(main.score_blue >= 1, "puck_crosses_goal_line")
    _check(main.get_state_name() == "goal", "goal_state_after_actual_goal")
    # Goalie save: reset and drive a puck into the red keeper from in front.
    Engine.time_scale = 1.0
    main.state = 2
    main.score_blue = 0
    main.score_red = 0
    main.red_team[2].downed = false
    main.puck.set_physics_process(true)
    main.puck.reset_to(Vector3(0.0, 0.34, 24.5))
    main.puck.velocity = Vector3(0.0, 0.0, 16.0)
    main.puck.last_shooter = sk
    main.puck.last_team = 0
    main.puck.pickup_lock = 1.0
    var before = main.score_blue
    for i in range(20):
        await physics_frame
    _check(main.score_blue == before, "goalie_prevents_centered_goal")
    # Slash damages an adjacent opponent.
    main.state = 2
    var enemy = main.red_team[0]
    enemy.downed = false
    enemy.hp = 100.0
    enemy.invuln = 0.0
    enemy.global_position = sk.global_position + sk.facing * 1.3
    sk.facing = (enemy.global_position - sk.global_position).normalized()
    sk.slash_cd = 0.0
    sk.action_lock = 0.0
    sk.try_slash(false)
    _check(enemy.hp < 100.0, "slash_hits")
    await physics_frame
    await physics_frame
    _check(sk.model != null and sk.model.get_state() == "slash", "slash_animation_state")
    _check(sk.model != null and sk.model.get_current_clip() == "sword_regular_a", "slash_animation_clip")
    # The same animation must start from the real left-mouse input path.
    sk.action_lock = 0.0
    sk.slash_cd = 0.0
    _mouse_left(true)
    await physics_frame
    await physics_frame
    _check(sk.model != null and sk.model.get_state() == "slash", "lmb_starts_slash_animation")
    _mouse_left(false)
    await physics_frame
    # Hazard: a turnstile must damage a skater standing in it.
    main.state = 2
    sk.hp = 100.0
    sk.downed = false
    sk.invuln = 0.0
    sk.global_position = Vector3(8.6, 0.0, 0.0)
    sk.velocity = Vector3.ZERO
    main.puck.set_physics_process(false)
    for i in range(140):
        await physics_frame
    main.puck.set_physics_process(true)
    _check(sk.hp < 100.0, "turnstile_hazard_damages")
    sk.hp = 100.0
    # Killball charger: carry the rok over the arena's charger.
    main.state = 2
    sk.downed = false
    sk.hp = 100.0
    sk.invuln = 0.4
    sk.velocity = Vector3.ZERO
    sk._grounded = true
    sk.global_position = Vector3(0.0, 0.0, 0.0)
    main.puck.set_physics_process(true)
    main.puck.reset_to(sk.get_puck_anchor())
    main.puck.attach_to(sk)
    for i in range(12):
        await process_frame
        await physics_frame
    main._charger_cd = 0.0
    main._check_killball_charger()
    _check(main.get_puck().is_charged(), "killball_charger_arms")
    # Pause/resume.
    main.pause_match()
    _check(main.get_state_name() == "paused", "pause_enters")
    main.resume_match()
    _check(main.get_state_name() != "paused", "resume_leaves_pause")
    # Annihilation: both enemy forwards down + a goal ends the match.
    main.state = 2
    main.score_blue = 0
    main.score_red = 0
    main.red_team[0].downed = true
    main.red_team[1].downed = true
    main.on_goal(0, sk, false)
    _check(main.annihilation, "annihilation_flagged")
    main._tick_goal(2.0)
    _check(main.get_state_name() == "game_over", "annihilation_ends_match")
    # Volume mix: the pause-screen sliders drive the real audio buses and persist.
    var original_muted = main.audio_muted
    main.pause_match()
    _check(main.hud.volume_sliders.size() == 3, "three_volume_sliders")
    var master_slider = main.hud.volume_sliders.get("master")
    _check(master_slider != null, "master_volume_slider")
    if master_slider != null:
        master_slider.value = 55.0
        await process_frame
        _check(absf(main.master_volume - 0.55) < 0.01, "master_slider_updates_setting")
        if main.audio != null and main.audio.has_method("get_volume"):
            _check(absf(main.audio.get_volume("master") - 0.55) < 0.04, "master_volume_applied_to_bus")
        master_slider.value = 80.0
        await process_frame
    main._on_volume_changed("music", 0.21)
    _check(is_equal_approx(main.music_volume, 0.21), "music_volume_setting")
    if main.audio != null and main.audio.has_method("get_volume"):
        _check(absf(main.audio.get_volume("music") - 0.21) < 0.04, "music_volume_applied_to_bus")
    main._toggle_mute()
    if main.audio != null:
        _check(main.audio.is_muted(), "mute_toggle")
    main._toggle_mute()
    main._on_volume_changed("music", 1.0)
    main.audio_muted = original_muted
    main._apply_audio_settings()
    main._save_audio_settings()
    main._sync_hud_audio()
    print("ULTRABLADE_INTEGRATION_", "OK" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
    Engine.time_scale = 1.0
    # Stop and free audio explicitly before freeing the scene; keeps the headless smoke clean.
    if main.audio != null:
        if main.audio.has_method("stop_all_sfx"):
            main.audio.stop_all_sfx()
        if main.audio.has_method("stop_music"):
            main.audio.stop_music()
        for audio_player in main.audio.find_children("*", "AudioStreamPlayer", true, false):
            if audio_player is AudioStreamPlayer:
                audio_player.stop()
                audio_player.stream = null
        main.audio.free()
        main.audio = null
        for i in range(5):
            await process_frame
    main.queue_free()
    for i in range(5):
        await process_frame
    quit(0 if failures.is_empty() else 1)
