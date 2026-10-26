extends Node3D

## ULTRABLADE match director.
## Owns the drome, teams, puck, rules, broadcast camera, HUD, audio and the headless evidence modes.

enum {
    MENU,
    COUNTDOWN,
    PLAYING,
    GOAL,
    PERIOD_BREAK,
    GAME_OVER,
    PAUSED,
}

const PERIODS = 3
const PERIOD_SECONDS = 90.0
const OVERTIME_SECONDS = 45.0
const COUNTDOWN_SECONDS = 3.2
const GOAL_SEQUENCE_SECONDS = 1.25
const PERIOD_BREAK_SECONDS = 2.8
const BLUE = 0
const RED = 1
const BLUE_COLOR = Color(0.08, 0.82, 1.0)
const RED_COLOR = Color(1.0, 0.16, 0.38)
const AMBER = Color(1.0, 0.62, 0.08)
const CYAN = Color(0.13, 0.9, 1.0)
const DROME_HALF_WIDTH = 16.0
const DROME_HALF_LENGTH = 30.0
const KILLBALL_CHARGER = Vector3(8.0, 0.0, 0.0)
const DEFAULT_CAMERA_YAW = PI

var state = MENU
var state_timer = 0.0
var period = 1
var clock = PERIOD_SECONDS
var overtime = false
var score_blue = 0
var score_red = 0
var goal_scorer: Node = null
var last_goal_team = -1
var annihilation = false
var annihilation_team = -1
var match_reason = ""

var arena_root: Node3D
var arena_data: Dictionary = {}
var entities_root: Node3D
var puck: Node3D
var players: Array = []
var all_skaters: Array = []
var blue_team: Array = []
var red_team: Array = []
var controlled_skater: Node = null
var camera_rig: Node
var hud: CanvasLayer
var audio: Node

var skater_script: Script
var puck_script: Script
var hud_script: Script
var camera_script: Script
var audio_script: Script

var demo_mode = false
var demo_seconds := 12.0
var selftest_mode = false
var capture_mode = false
var demo_start_ms = 0
var demo_saw_pickup = false
var demo_saw_shot = false
var demo_saw_hit = false
var demo_saw_goal = false
var demo_frames = 0
var normal_time_scale = 1.0
var _capture_times: Array = []
var _capture_done = 0
var _capture_index = 0
var _last_countdown_mark = -1
var _state_before_pause = PLAYING
var _goalie_clear_cd = {}
var _pad_cd = {}
var _charger_cd = 0.0
var _killball_msg_shown = false
var _elapsed = 0.0
var _wall_spark_cd = 0.0
var match_shots = 0
var match_hits = 0
var match_kills = 0
var match_goals = 0
var master_volume = 0.8
var music_volume = 1.0
var sfx_volume = 1.0
var audio_muted = true
var _st_checks = 0
var _st_failures: Array = []

const TEAM_NAMES = ["ICE SAINTS", "REDLINE SYNDICATE"]
const ROLE_NAMES = ["striker", "enforcer", "runner", "anchor"]
const SETTINGS_PATH = "user://settings.cfg"

func _ready() -> void:
    randomize()
    _parse_args()
    _load_scripts()
    _build_arena()
    _build_environment()
    _build_entities()
    _build_camera()
    _build_hud()
    _build_audio()
    _load_audio_settings()
    hud.show_menu()
    hud.set_hud_visible(false)
    _set_mouse_captured(false)
    if selftest_mode:
        call_deferred("_run_selftest")
        return
    if demo_mode:
        normal_time_scale = 4.0
        Engine.time_scale = normal_time_scale
        call_deferred("_start_demo")
        return
    if capture_mode:
        _capture_times = [0.7, 1.6, 2.7, 3.5]
        call_deferred("_start_capture_setup")

func _parse_args() -> void:
    var args = OS.get_cmdline_user_args()
    demo_mode = "--demo" in args
    selftest_mode = "--selftest" in args
    capture_mode = "--capture" in args
    for i in range(args.size()):
        if args[i] == "--demo-seconds" and i + 1 < args.size():
            demo_seconds = clampf(float(args[i + 1]), 2.0, 120.0)

func _load_scripts() -> void:
    skater_script = load("res://scripts/skater.gd")
    puck_script = load("res://scripts/puck.gd")
    hud_script = load("res://scripts/hud.gd")
    camera_script = load("res://scripts/chase_camera.gd")
    if ResourceLoader.exists("res://scripts/audio_director.gd"):
        audio_script = load("res://scripts/audio_director.gd")

func _build_environment() -> void:
    # The arena owns its lighting/environment when its builder is present; only add
    # the fallback atmosphere when nothing else supplied one.
    for existing in find_children("*", "WorldEnvironment", true, false):
        return
    var we = WorldEnvironment.new()
    we.name = "DromeAtmosphere"
    var env = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.004, 0.008, 0.016)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.12, 0.24, 0.42)
    env.ambient_light_energy = 0.42
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.tonemap_exposure = 1.05
    env.glow_enabled = true
    env.glow_intensity = 1.0
    env.glow_strength = 1.0
    env.glow_bloom = 0.12
    env.glow_hdr_threshold = 0.82
    env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
    env.ssao_enabled = true
    env.ssao_radius = 2.0
    env.ssao_intensity = 1.4
    env.adjustment_enabled = true
    env.adjustment_contrast = 1.08
    env.adjustment_saturation = 1.12
    env.fog_enabled = true
    env.fog_light_color = Color(0.03, 0.07, 0.13)
    env.fog_density = 0.004
    env.fog_sky_affect = 0.3
    we.environment = env
    add_child(we)

    var key = DirectionalLight3D.new()
    key.name = "KeyLight"
    key.light_color = Color(0.55, 0.72, 1.0)
    key.light_energy = 0.75
    key.rotation_degrees = Vector3(-52, -38, 0)
    key.shadow_enabled = true
    key.directional_shadow_max_distance = 70.0
    add_child(key)

    var fill = DirectionalLight3D.new()
    fill.name = "RimLight"
    fill.light_color = Color(0.9, 0.18, 0.42)
    fill.light_energy = 0.22
    fill.rotation_degrees = Vector3(-24, 142, 0)
    add_child(fill)

func _build_arena() -> void:
    arena_root = Node3D.new()
    arena_root.name = "Arena"
    add_child(arena_root)
    var built = false
    var builder_script: Script = null
    if ResourceLoader.exists("res://scripts/arena_builder.gd"):
        builder_script = load("res://scripts/arena_builder.gd")
    if builder_script != null:
        var builder = builder_script.new()
        if builder != null:
            if builder.has_method("build"):
                arena_data = builder.build(arena_root)
                built = true
            elif builder.has_method("_build"):
                arena_data = builder.call("_build", arena_root)
                built = true
    if not built or arena_data.is_empty():
        print("ArenaBuilder unavailable; using fallback drome.")
        _build_fallback_arena()
    _ensure_goal_positions()
    _build_floor_collider()

func _build_fallback_arena() -> void:
    arena_data = {
        "player_goal": Vector3(0, 0, -DROME_HALF_LENGTH),
        "enemy_goal": Vector3(0, 0, DROME_HALF_LENGTH),
        "boost_pads": [Vector3(0, 0, -8), Vector3(0, 0, 8)],
        "hazards": [],
        "killball_charger": KILLBALL_CHARGER,
        "bounds": {"half_width": DROME_HALF_WIDTH, "half_length": DROME_HALF_LENGTH},
    }
    var drome = Node3D.new()
    drome.name = "FallbackDrome"
    arena_root.add_child(drome)

    var ice_mat = StandardMaterial3D.new()
    ice_mat.albedo_color = Color(0.018, 0.035, 0.065)
    ice_mat.metallic = 0.55
    ice_mat.roughness = 0.17
    var floor = MeshInstance3D.new()
    var pm = PlaneMesh.new()
    pm.size = Vector2(34, 64)
    floor.mesh = pm
    floor.material_override = ice_mat
    drome.add_child(floor)

    var line_mat = StandardMaterial3D.new()
    line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    line_mat.albedo_color = Color(0.1, 0.9, 1.0, 0.35)
    line_mat.emission_enabled = true
    line_mat.emission = Color(0.1, 0.8, 1.0)
    line_mat.emission_energy_multiplier = 2.2
    line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    var center_line = MeshInstance3D.new()
    var clm = BoxMesh.new()
    clm.size = Vector3(32.0, 0.02, 0.12)
    center_line.mesh = clm
    center_line.material_override = line_mat
    center_line.position.y = 0.012
    drome.add_child(center_line)

    var circle = MeshInstance3D.new()
    var torus = TorusMesh.new()
    torus.inner_radius = 4.7
    torus.outer_radius = 4.85
    torus.rings = 64
    torus.ring_segments = 4
    circle.mesh = torus
    circle.material_override = line_mat
    circle.position.y = 0.014
    circle.scale = Vector3(1.0, 1.0, 1.0)
    drome.add_child(circle)

    # team end zones
    _add_zone_plane(drome, Vector3(0, 0.008, -22.5), Color(0.04, 0.35, 0.9, 0.15), Vector2(25, 11))
    _add_zone_plane(drome, Vector3(0, 0.008, 22.5), Color(0.9, 0.04, 0.2, 0.15), Vector2(25, 11))
    _add_zone_plane(drome, Vector3(0, 0.009, 0), Color(0.1, 0.8, 1.0, 0.08), Vector2(8, 8))

    # goals
    _add_goal_frame(drome, 30.5, RED_COLOR)
    _add_goal_frame(drome, -30.5, BLUE_COLOR)

    # boards: a segmented elliptical rail with transparent energy glass
    var rail_mat = StandardMaterial3D.new()
    rail_mat.albedo_color = Color(0.03, 0.08, 0.12)
    rail_mat.metallic = 0.9
    rail_mat.roughness = 0.2
    rail_mat.emission_enabled = true
    rail_mat.emission = Color(0.05, 0.45, 0.7)
    rail_mat.emission_energy_multiplier = 0.8
    var glass_mat = StandardMaterial3D.new()
    glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glass_mat.albedo_color = Color(0.08, 0.85, 1.0, 0.06)
    glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass_mat.emission_enabled = true
    glass_mat.emission = Color(0.06, 0.55, 0.9)
    glass_mat.emission_energy_multiplier = 0.5
    var segments = 36
    for i in range(segments):
        var a0 = TAU * float(i) / float(segments)
        var a1 = TAU * float(i + 1) / float(segments)
        var p0 = Vector3(cos(a0) * 17.0, 0.0, sin(a0) * 32.0)
        var p1 = Vector3(cos(a1) * 17.0, 0.0, sin(a1) * 32.0)
        var mid = (p0 + p1) * 0.5
        var dir = (p1 - p0).normalized()
        var seg_len = p0.distance_to(p1) * 0.98
        var rail = MeshInstance3D.new()
        var bm = BoxMesh.new()
        bm.size = Vector3(seg_len, 1.15, 0.38)
        rail.mesh = bm
        rail.material_override = rail_mat
        rail.position = mid + Vector3(0, 0.575, 0)
        rail.rotation.y = atan2(dir.z, dir.x)
        drome.add_child(rail)
        var glow = MeshInstance3D.new()
        var bg = BoxMesh.new()
        bg.size = Vector3(seg_len, 0.045, 0.42)
        glow.mesh = bg
        glow.material_override = line_mat
        glow.position = mid + Vector3(0, 1.1, 0)
        glow.rotation.y = rail.rotation.y
        drome.add_child(glow)
        if i % 3 == 0:
            var glass = MeshInstance3D.new()
            var gm = BoxMesh.new()
            gm.size = Vector3(seg_len, 3.8, 0.04)
            glass.mesh = gm
            glass.material_override = glass_mat
            glass.position = mid + Vector3(0, 3.1, 0)
            glass.rotation.y = rail.rotation.y
            drome.add_child(glass)

    # crowd silhouettes and pylon lights
    var crowd_mat = StandardMaterial3D.new()
    crowd_mat.albedo_color = Color(0.015, 0.03, 0.06)
    crowd_mat.metallic = 0.2
    crowd_mat.roughness = 0.8
    var eye_mat = StandardMaterial3D.new()
    eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    eye_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.5)
    eye_mat.emission_enabled = true
    eye_mat.emission = Color(0.2, 0.6, 1.0)
    eye_mat.emission_energy_multiplier = 3.0
    for tier in range(3):
        var rr = 19.0 + tier * 2.6
        var count = 28 + tier * 8
        for i in range(count):
            var a = TAU * float(i) / float(count)
            var p = Vector3(cos(a) * rr, 1.6 + tier * 1.25, sin(a) * (33.0 + tier * 2.2))
            var crowd = MeshInstance3D.new()
            var cb = BoxMesh.new()
            cb.size = Vector3(1.4, 1.0, 0.6)
            crowd.mesh = cb
            crowd.material_override = crowd_mat
            crowd.position = p
            crowd.rotation.y = -a
            drome.add_child(crowd)
            if (i + tier * 3) % 4 == 0:
                var eye = MeshInstance3D.new()
                var em = BoxMesh.new()
                em.size = Vector3(0.25, 0.08, 0.03)
                eye.mesh = em
                eye.material_override = eye_mat
                eye.position = p + Vector3(0, 0.25, 0)
                eye.rotation.y = -a
                drome.add_child(eye)

    var pylon_colors = [Color(0.1, 0.8, 1.0), Color(1.0, 0.12, 0.3), Color(1.0, 0.6, 0.08)]
    for i in range(6):
        var a = TAU * float(i) / 6.0
        var p = Vector3(cos(a) * 21.0, 4.0, sin(a) * 35.0)
        var pylon = MeshInstance3D.new()
        var bm3 = BoxMesh.new()
        bm3.size = Vector3(0.35, 8.0, 0.35)
        pylon.mesh = bm3
        pylon.material_override = rail_mat
        pylon.position = p
        drome.add_child(pylon)
        var light = OmniLight3D.new()
        light.light_color = pylon_colors[i % 3]
        light.light_energy = 1.8
        light.omni_range = 18.0
        light.position = p + Vector3(0, 2.0, 0)
        drome.add_child(light)

    # killball charger
    var charger = Node3D.new()
    charger.name = "KillballCharger"
    charger.position = KILLBALL_CHARGER
    drome.add_child(charger)
    var pad = MeshInstance3D.new()
    var cm = CylinderMesh.new()
    cm.top_radius = 2.3
    cm.bottom_radius = 2.6
    cm.height = 0.16
    pad.mesh = cm
    var pad_mat = StandardMaterial3D.new()
    pad_mat.albedo_color = Color(0.2, 0.08, 0.01)
    pad_mat.metallic = 0.9
    pad_mat.emission_enabled = true
    pad_mat.emission = AMBER
    pad_mat.emission_energy_multiplier = 2.2
    pad.material_override = pad_mat
    charger.add_child(pad)
    for i in range(3):
        var ring = MeshInstance3D.new()
        var tr = TorusMesh.new()
        tr.inner_radius = 1.4 + i * 0.28
        tr.outer_radius = 1.48 + i * 0.28
        tr.rings = 48
        ring.mesh = tr
        var rm = StandardMaterial3D.new()
        rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        rm.albedo_color = AMBER
        rm.emission_enabled = true
        rm.emission = AMBER
        rm.emission_energy_multiplier = 4.0
        ring.material_override = rm
        ring.position.y = 0.3 + i * 0.35
        charger.add_child(ring)

func _add_zone_plane(parent: Node3D, pos: Vector3, color: Color, sz: Vector2) -> void:
    var mi = MeshInstance3D.new()
    var pm = PlaneMesh.new()
    pm.size = sz
    mi.mesh = pm
    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = color
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.emission_enabled = true
    mat.emission = Color(color.r, color.g, color.b)
    mat.emission_energy_multiplier = 0.25
    mi.material_override = mat
    mi.position = pos
    parent.add_child(mi)

func _add_goal_frame(parent: Node3D, z: float, color: Color) -> void:
    var frame_mat = StandardMaterial3D.new()
    frame_mat.albedo_color = Color(0.04, 0.07, 0.1)
    frame_mat.metallic = 1.0
    frame_mat.roughness = 0.22
    frame_mat.emission_enabled = true
    frame_mat.emission = color
    frame_mat.emission_energy_multiplier = 1.8
    var back = MeshInstance3D.new()
    var bm = BoxMesh.new()
    bm.size = Vector3(9.8, 4.6, 0.25)
    back.mesh = bm
    back.material_override = frame_mat
    back.position = Vector3(0, 2.3, z + (0.9 if z > 0 else -0.9))
    parent.add_child(back)
    for sx in [-4.9, 4.9]:
        var post = MeshInstance3D.new()
        var pb = BoxMesh.new()
        pb.size = Vector3(0.28, 4.6, 0.4)
        post.mesh = pb
        post.material_override = frame_mat
        post.position = Vector3(sx, 2.3, z)
        parent.add_child(post)
    var bar = MeshInstance3D.new()
    var bb = BoxMesh.new()
    bb.size = Vector3(10.0, 0.3, 0.4)
    bar.mesh = bb
    bar.material_override = frame_mat
    bar.position = Vector3(0, 4.55, z)
    parent.add_child(bar)

func _ensure_goal_positions() -> void:
    if not arena_data.has("bounds"):
        arena_data["bounds"] = {"half_width": DROME_HALF_WIDTH, "half_length": DROME_HALF_LENGTH}
    var b = arena_data.get("bounds", {})
    b["half_width"] = float(b.get("half_width", DROME_HALF_WIDTH))
    b["half_length"] = float(b.get("half_length", DROME_HALF_LENGTH))
    arena_data["bounds"] = b

func _build_floor_collider() -> void:
    var body = StaticBody3D.new()
    body.name = "IceSurface"
    body.collision_layer = 1
    body.collision_mask = 0
    var shape = BoxShape3D.new()
    shape.size = Vector3(40.0, 1.0, 80.0)
    var col = CollisionShape3D.new()
    col.shape = shape
    col.position.y = -0.5
    body.add_child(col)
    add_child(body)

func _build_entities() -> void:
    entities_root = Node3D.new()
    entities_root.name = "Entities"
    add_child(entities_root)
    puck = puck_script.new()
    puck.name = "Rok"
    entities_root.add_child(puck)
    puck.setup(self)
    puck.picked_up.connect(_on_puck_picked_up)
    puck.shot.connect(_on_puck_shot)
    puck.goal_scored.connect(_on_puck_goal_signal)
    _spawn_teams()
    _reset_round()

func _spawn_teams() -> void:
    all_skaters.clear()
    blue_team.clear()
    red_team.clear()
    var blue_spawns = _get_spawn_points("spawn_blue", BLUE)
    var red_spawns = _get_spawn_points("spawn_red", RED)
    # Player star
    var star = _make_skater(BLUE, "striker", false, true, 0)
    _place_skater(star, blue_spawns[0])
    blue_team.append(star)
    # Blue AI teammate
    var mate = _make_skater(BLUE, "enforcer", false, false, 1)
    _place_skater(mate, blue_spawns[1])
    blue_team.append(mate)
    # Blue goalie
    var blue_goal = _make_skater(BLUE, "goalie", true, false, 2)
    _place_skater(blue_goal, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -27.2)))
    blue_team.append(blue_goal)
    # Red outfielders
    for i in range(2):
        var r = _make_skater(RED, ROLE_NAMES[i], false, false, i)
        _place_skater(r, red_spawns[i])
        red_team.append(r)
    var red_goal = _make_skater(RED, "goalie", true, false, 2)
    _place_skater(red_goal, Transform3D(Basis.IDENTITY, Vector3(0, 0, 27.2)))
    red_team.append(red_goal)
    controlled_skater = blue_team[0]
    all_skaters = blue_team + red_team
    for s in all_skaters:
        if s.died.is_connected(_on_skater_died):
            pass
        s.died.connect(_on_skater_died)
        s.damaged.connect(_on_skater_damaged)
        s.hit_landed.connect(_on_hit_landed)

func _make_skater(team: int, role: String, goalie: bool, player: bool, idx: int) -> Node:
    var sk = skater_script.new()
    sk.name = ("Blue" if team == BLUE else "Red") + "_" + role + "_" + str(idx)
    entities_root.add_child(sk)
    sk.setup(self, team, role, goalie, player, idx)
    return sk

func _place_skater(sk: Node, t: Transform3D) -> void:
    sk.set_spawn_transform(t)
    sk.global_transform = t

func _get_spawn_points(key: String, team: int) -> Array:
    var out: Array = []
    if arena_data.has(key):
        var arr = arena_data[key]
        if arr is Array:
            for t in arr:
                if t is Transform3D:
                    out.append(t)
                elif t is Vector3:
                    out.append(Transform3D(Basis(Vector3.UP, PI if team == BLUE else 0.0), t))
    while out.size() < 2:
        if team == BLUE:
            out.append(Transform3D(Basis(Vector3.UP, PI), Vector3(-7.0 + out.size() * 14.0, 0, -18.0)))
        else:
            out.append(Transform3D(Basis.IDENTITY, Vector3(-7.0 + out.size() * 14.0, 0, 18.0)))
    return out

func _build_camera() -> void:
    if camera_script == null:
        return
    camera_rig = camera_script.new()
    camera_rig.name = "BroadcastCamera"
    add_child(camera_rig)
    camera_rig.set_mode("menu")
    camera_rig.set_target(null)

func _build_hud() -> void:
    if hud_script == null:
        push_error("HUD script missing")
        return
    hud = hud_script.new()
    hud.name = "BroadcastHUD"
    add_child(hud)
    hud.setup(self)
    hud.start_requested.connect(_on_hud_start)
    hud.resume_requested.connect(_on_hud_resume)
    hud.restart_requested.connect(_on_hud_restart)
    hud.quit_requested.connect(_on_hud_quit)
    hud.volume_changed.connect(_on_volume_changed)

func _build_audio() -> void:
    if audio_script == null or not audio_script.can_instantiate():
        return
    audio = audio_script.new()
    audio.name = "AudioDirector"
    add_child(audio)
    if audio.has_method("play_music"):
        audio.play_music("match")
    if audio.has_method("set_crowd"):
        audio.set_crowd(0.22)

func _load_audio_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) == OK:
        master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
        music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
        sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
        audio_muted = bool(cfg.get_value("audio", "muted", audio_muted))
    _apply_audio_settings()
    _sync_hud_audio()

func _save_audio_settings() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("audio", "master", master_volume)
    cfg.set_value("audio", "music", music_volume)
    cfg.set_value("audio", "sfx", sfx_volume)
    cfg.set_value("audio", "muted", audio_muted)
    cfg.save(SETTINGS_PATH)

func _apply_audio_settings() -> void:
    if audio == null:
        return
    if audio.has_method("set_volume"):
        audio.set_volume("master", master_volume)
        audio.set_volume("music", music_volume)
        audio.set_volume("sfx", sfx_volume)
    if audio.has_method("set_muted"):
        audio.set_muted(audio_muted)

func _sync_hud_audio() -> void:
    if hud and hud.has_method("set_audio_settings"):
        hud.set_audio_settings(master_volume, music_volume, sfx_volume, audio_muted)

func _toggle_mute() -> void:
    audio_muted = not audio_muted
    _apply_audio_settings()
    _save_audio_settings()
    _sync_hud_audio()
    _hud_announce("MUTED" if audio_muted else "AUDIO ON", "PRESS M TO TOGGLE", AMBER if audio_muted else CYAN, 0.6)

func _change_master_volume(delta: float) -> void:
    master_volume = clampf(master_volume + delta, 0.0, 1.0)
    if master_volume > 0.0:
        audio_muted = false
    _apply_audio_settings()
    _save_audio_settings()
    _sync_hud_audio()
    _hud_announce("MASTER VOLUME", str(int(round(master_volume * 100.0))) + "%", CYAN, 0.45)

func _on_volume_changed(channel: String, value: float) -> void:
    match channel:
        "master":
            master_volume = clampf(value, 0.0, 1.0)
        "music":
            music_volume = clampf(value, 0.0, 1.0)
        "sfx":
            sfx_volume = clampf(value, 0.0, 1.0)
        _:
            return
    if value > 0.0:
        audio_muted = false
    _apply_audio_settings()
    _save_audio_settings()
    _sync_hud_audio()

func _process(delta: float) -> void:
    _elapsed += delta
    _wall_spark_cd = maxf(0.0, _wall_spark_cd - delta)
    _charger_cd = maxf(0.0, _charger_cd - delta)
    if capture_mode:
        _process_capture(delta)
        return
    if demo_mode:
        _process_demo(delta)
        return
    match state:
        MENU, GAME_OVER:
            if camera_rig:
                camera_rig.set_mode("menu" if state == MENU else "goal")
            return
        PAUSED:
            return
        COUNTDOWN:
            _tick_countdown(delta)
        PLAYING:
            _tick_playing(delta)
        GOAL:
            _tick_goal(delta)
        PERIOD_BREAK:
            _tick_period_break(delta)
    _check_killball_charger()
    _check_boost_pads()
    _check_goalie_clear()
    _update_camera_target()
    _check_control_switch()

func _tick_countdown(delta: float) -> void:
    state_timer -= delta
    var mark = int(ceil(state_timer))
    if mark != _last_countdown_mark and mark > 0:
        _last_countdown_mark = mark
        _hud_announce(str(mark), "FEED GOING LIVE", Color(0.9, 0.97, 1.0), 0.55)
        _sfx("countdown", -6.0)
    if state_timer <= 0.0:
        state = PLAYING
        _last_countdown_mark = -1
        _hud_announce("LIVE", "PLAY", Color(0.2, 0.95, 1.0), 0.8)
        _sfx("countdown_go", -8.0)
        _music("match")

func _tick_playing(delta: float) -> void:
    if overtime:
        clock = maxf(0.0, clock - delta)
    else:
        clock = maxf(0.0, clock - delta)
        if clock <= 0.0:
            _end_period()
            return
    if puck != null and puck.carrier == null:
        if puck.pickup_lock <= 0.0:
            for s in all_skaters:
                if s == null or s.downed:
                    continue
                if s.global_position.distance_to(puck.global_position) < 1.45:
                    try_pickup(s)
                    break
    if camera_rig:
        camera_rig.set_mode("chase")

func _check_control_switch() -> void:
    if controlled_skater != null and not controlled_skater.downed:
        return
    for s in blue_team:
        if s != null and not s.downed and not s.is_goalie:
            _set_controlled(s)
            return
    _set_controlled(null)

func _set_controlled(sk: Node) -> void:
    if controlled_skater == sk:
        return
    if controlled_skater != null and is_instance_valid(controlled_skater):
        controlled_skater.set_controlled(false)
    controlled_skater = sk
    if sk != null:
        sk.set_controlled(true)
        if camera_rig:
            camera_rig.set_target(sk)
            camera_rig.set_mode("chase")
        _set_mouse_captured(true)
    else:
        if camera_rig:
            camera_rig.set_mode("goal")

func _update_camera_target() -> void:
    if camera_rig == null:
        return
    var t = controlled_skater
    if t == null and puck != null:
        camera_rig.goal_view(puck.global_position, 1.0)
        return
    if t != null:
        camera_rig.set_target(t)

func _on_skater_died(sk: Node) -> void:
    if state != PLAYING and state != GOAL:
        return
    var victim_name: String = sk.display_name
    var team: int = sk.team_id
    var col = BLUE_COLOR if team == BLUE else RED_COLOR
    _hud_feed("ELIMINATED  //  " + victim_name, col)
    _hud_announce("DOWN", victim_name + " IS OUT OF THE DROME", col, 1.0)
    _screen_flash(col, 0.16)
    _sfx("death", -4.0)
    if sk == controlled_skater or (controlled_skater != null and controlled_skater.downed):
        _check_control_switch()

func _on_skater_damaged(sk: Node, amount: float, source_position: Vector3, heavy: bool) -> void:
    if hud and hud.has_method("damage_indicator"):
        pass
    if sk.is_controlled:
        if camera_rig:
            camera_rig.add_shake(0.16 if heavy else 0.07)
        _screen_flash(Color(1.0, 0.1, 0.2), 0.11 if heavy else 0.06)

func _on_hit_landed(attacker: Node, victim: Node, heavy: bool) -> void:
    match_hits += 1
    if camera_rig:
        camera_rig.add_shake(0.08 if heavy else 0.045)
    _sfx("heavy_hit" if heavy else "slash", -3.0, randf_range(0.9, 1.08))

func _on_puck_picked_up(by: Node) -> void:
    if by.is_controlled:
        _hud_announce("ROK", "POSSESSION", BLUE_COLOR, 0.45)
        _sfx("pickup", -8.0)
    if demo_mode:
        demo_saw_pickup = true

func _on_puck_shot(by: Node, power: float, charged: bool) -> void:
    match_shots += 1
    if by.is_controlled:
        camera_rig.add_shake(0.06)
        _hud_flash(0.08)
    _sfx("shot", -4.0, randf_range(0.92, 1.06))
    if charged:
        _hud_announce("KILLBALL", "LIVE PROJECTILE", AMBER, 0.8)
    if demo_mode:
        demo_saw_shot = true

func _on_puck_goal_signal(team: int) -> void:
    pass

func _on_hud_start() -> void:
    if state == MENU or state == GAME_OVER:
        start_match()

func _on_hud_resume() -> void:
    resume_match()

func _on_hud_restart() -> void:
    start_match()

func _on_hud_quit() -> void:
    get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        var key = event.physical_keycode
        if key == KEY_ESCAPE:
            if state == PAUSED:
                resume_match()
            elif state == PLAYING or state == COUNTDOWN or state == GOAL or state == PERIOD_BREAK:
                pause_match()
            elif state == GAME_OVER:
                _show_menu()
            get_viewport().set_input_as_handled()
            return
        if key == KEY_ENTER or key == KEY_KP_ENTER:
            if state == MENU:
                start_match()
            elif state == GAME_OVER:
                start_match()
            get_viewport().set_input_as_handled()
            return
        if key == KEY_R:
            if state == GAME_OVER or state == PAUSED:
                start_match()
            return
        if key == KEY_M:
            _toggle_mute()
            return
        if key == KEY_BRACKETLEFT or key == KEY_MINUS:
            _change_master_volume(-0.1)
            return
        if key == KEY_BRACKETRIGHT or key == KEY_EQUAL:
            _change_master_volume(0.1)
            return
    if event is InputEventMouseMotion:
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera_rig != null:
            camera_rig.rotate_view(event.relative.x, event.relative.y)

func start_match() -> void:
    Engine.time_scale = normal_time_scale
    score_blue = 0
    score_red = 0
    period = 1
    overtime = false
    clock = PERIOD_SECONDS
    annihilation = false
    annihilation_team = -1
    match_reason = ""
    match_shots = 0
    match_hits = 0
    match_kills = 0
    match_goals = 0
    _goalie_clear_cd.clear()
    _pad_cd.clear()
    _killball_msg_shown = false
    if hud:
        hud.hide_menu()
        hud.hide_end()
        hud.set_paused(false)
        hud.set_hud_visible(true)
        hud.set_goal_visible(true)
    _reset_round()
    _set_controlled(blue_team[0] if blue_team.size() > 0 else null)
    if camera_rig:
        camera_rig.set_mode("chase")
        camera_rig.set_target(controlled_skater)
    _set_mouse_captured(true)
    state = COUNTDOWN
    state_timer = COUNTDOWN_SECONDS
    _last_countdown_mark = -1
    _hud_announce("PERIOD 1", "ICE SAINTS  VS  REDLINE SYNDICATE", Color(0.85, 0.95, 1.0), 1.2)
    _sfx("crowd_swell", -8.0)
    _music("match")
    if audio and audio.has_method("set_crowd"):
        audio.set_crowd(0.65)

func _show_menu() -> void:
    state = MENU
    Engine.time_scale = 1.0
    if hud:
        hud.hide_end()
        hud.set_paused(false)
        hud.show_menu()
    if camera_rig:
        camera_rig.set_mode("menu")
        camera_rig.set_target(null)
    _set_mouse_captured(false)

func pause_match() -> void:
    if state == PAUSED:
        return
    _state_before_pause = state
    state = PAUSED
    Engine.time_scale = 0.0
    if hud:
        hud.set_paused(true)
    _set_mouse_captured(false)

func resume_match() -> void:
    if state != PAUSED:
        return
    state = _state_before_pause
    Engine.time_scale = normal_time_scale
    if hud:
        hud.set_paused(false)
    _set_mouse_captured(true)

func _reset_round() -> void:
    if puck == null:
        return
    puck.set_physics_process(true)
    puck.reset_to(Vector3(0, 0.34, 0))
    if puck.charged:
        puck.set_charged(false)
    var blue_spawns = _get_spawn_points("spawn_blue", BLUE)
    var red_spawns = _get_spawn_points("spawn_red", RED)
    for i in range(blue_team.size()):
        var s = blue_team[i]
        if s == null:
            continue
        if s.is_goalie:
            s.reset_round(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -27.2)))
        else:
            s.reset_round(blue_spawns[i % blue_spawns.size()])
    for i in range(red_team.size()):
        var s = red_team[i]
        if s == null:
            continue
        if s.is_goalie:
            s.reset_round(Transform3D(Basis.IDENTITY, Vector3(0, 0, 27.2)))
        else:
            s.reset_round(red_spawns[i % red_spawns.size()])
    var new_control = null
    for s in blue_team:
        if s != null and not s.is_goalie and not s.downed:
            new_control = s
            break
    _set_controlled(new_control)
    if hud:
        hud.set_goal_visible(true)
        hud.hide_end()

func on_goal(team: int, scorer: Node, charged: bool) -> void:
    if state != PLAYING:
        return
    if team == BLUE:
        score_blue += 1
    else:
        score_red += 1
    match_goals += 1
    last_goal_team = team
    goal_scorer = scorer
    if demo_mode:
        demo_saw_goal = true
    state = GOAL
    state_timer = GOAL_SEQUENCE_SECONDS
    Engine.time_scale = 0.35
    _music("goal")
    _sfx("goal_horn", -2.0)
    _sfx("crowd_swell", -1.0)
    if audio and audio.has_method("set_crowd"):
        audio.set_crowd(1.0)
    if puck:
        puck.set_physics_process(false)
        puck.velocity = Vector3.ZERO
    var goal_pos = Vector3(0, 0, DROME_HALF_LENGTH if team == BLUE else -DROME_HALF_LENGTH)
    FX.goal_flash(self, goal_pos, BLUE_COLOR if team == BLUE else RED_COLOR)
    if camera_rig:
        camera_rig.goal_view(goal_pos, 1.0 if team == BLUE else -1.0)
        camera_rig.add_shake(0.5)
    if hud:
        var scorer_name = "OWN GOAL" if scorer == null else scorer.display_name
        hud.show_goal(team, scorer_name)
        hud.screen_flash(BLUE_COLOR if team == BLUE else RED_COLOR, 0.42)
    if scorer != null and is_instance_valid(scorer):
        scorer.celebrate()
    # Annihilation rule: scoring while both enemy forwards are already down ends the match.
    var enemy_team = red_team if team == BLUE else blue_team
    var down_count = 0
    for s in enemy_team:
        if s != null and not s.is_goalie and s.downed:
            down_count += 1
    if down_count >= 2:
        annihilation = true
        annihilation_team = team
    if hud:
        var scorer_display = "LOOSE ROK" if scorer == null else scorer.display_name
        hud.add_kill_feed("GOAL  //  " + scorer_display, BLUE_COLOR if team == BLUE else RED_COLOR)

func _tick_goal(delta: float) -> void:
    state_timer -= delta
    if state_timer <= 0.0:
        Engine.time_scale = normal_time_scale
        if annihilation:
            _end_match("ANNIHILATION")
        elif overtime:
            _end_match("SUDDEN DEATH")
        else:
            state = COUNTDOWN
            state_timer = 2.4
            _last_countdown_mark = -1
            _reset_round()
            if audio and audio.has_method("set_crowd"):
                audio.set_crowd(0.65)
            if hud:
                hud.set_goal_visible(true)
            _hud_announce("FACE OFF", "RESERVES DEPLOYED", Color(0.8, 0.9, 1.0), 1.0)

func _end_period() -> void:
    if period < PERIODS:
        state = PERIOD_BREAK
        state_timer = PERIOD_BREAK_SECONDS
        _music("break")
        _hud_announce("END OF PERIOD " + str(period), "ICE CREW // RESERVES RESET", Color(0.9, 0.95, 1.0), 1.5)
        _sfx("countdown_go", -5.0)
        if puck:
            puck.set_physics_process(false)
        for s in all_skaters:
            if s != null:
                s.move_input = Vector3.ZERO
                s.want_boost = false
    else:
        if score_blue == score_red:
            _begin_overtime()
        else:
            _end_match("FINAL HORN")

func _tick_period_break(delta: float) -> void:
    state_timer -= delta
    if state_timer <= 0.0:
        period += 1
        clock = PERIOD_SECONDS
        _reset_round()
        state = COUNTDOWN
        state_timer = COUNTDOWN_SECONDS
        _last_countdown_mark = -1
        _set_controlled(blue_team[0] if blue_team.size() > 0 else null)
        if camera_rig:
            camera_rig.set_mode("chase")
        _hud_announce("PERIOD " + str(period), "ICE SAINTS  VS  REDLINE SYNDICATE", Color(0.85, 0.95, 1.0), 1.2)
        _sfx("crowd_swell", -8.0)

func _begin_overtime() -> void:
    overtime = true
    period = 4
    clock = OVERTIME_SECONDS
    _reset_round()
    state = COUNTDOWN
    state_timer = COUNTDOWN_SECONDS
    _last_countdown_mark = -1
    if camera_rig:
        camera_rig.set_mode("chase")
    _hud_announce("OVERTIME", "SUDDEN DEATH // NEXT GOAL WINS", AMBER, 1.6)
    _sfx("crowd_swell", -7.0)

func _end_match(reason: String) -> void:
    state = GAME_OVER
    match_reason = reason
    Engine.time_scale = 1.0
    if puck:
        puck.set_physics_process(false)
    for s in all_skaters:
        if s != null:
            s.move_input = Vector3.ZERO
    var winner = 0 if score_blue > score_red else (1 if score_red > score_blue else 0)
    if annihilation and annihilation_team in [0, 1]:
        winner = annihilation_team
    elif overtime and last_goal_team in [0, 1]:
        winner = last_goal_team
    var victory = winner == 0
    if hud:
        var title_sub = ("ICE SAINTS WIN // " + reason) if victory else ("REDLINE SYNDICATE WINS // " + reason)
        hud.show_end(victory, "%d  —  %d" % [score_blue, score_red], title_sub)
        hud.hide_menu()
    _music("victory" if victory else "defeat")
    if audio and audio.has_method("set_crowd"):
        audio.set_crowd(0.75)
    _set_mouse_captured(false)
    if camera_rig:
        camera_rig.set_mode("goal")
        camera_rig.goal_view(Vector3(0, 1.5, 0), 1.0)
    _sfx("victory" if victory else "death", -2.0)

func _check_killball_charger() -> void:
    if not is_match_active() or puck == null or puck.carrier == null:
        return
    if puck.charged or _charger_cd > 0.0:
        return
    var charger = arena_data.get("killball_charger", KILLBALL_CHARGER)
    var pos = KILLBALL_CHARGER
    if charger is Node3D and is_instance_valid(charger):
        pos = charger.global_position
    elif charger is Vector3:
        pos = charger
    if puck.carrier.global_position.distance_to(pos) < 2.4:
        puck.set_charged(true)
        _charger_cd = 2.5
        _hud_announce("KILLBALL ARMED", "Q  THROW  //  LMB  SHOOT", AMBER, 1.2)
        _sfx("killball_charge", -3.0)
        if camera_rig:
            camera_rig.add_shake(0.12)

func _check_boost_pads() -> void:
    if not is_match_active():
        return
    var pads = arena_data.get("boost_pads", [])
    if not (pads is Array):
        return
    for pad in pads:
        if pad == null:
            continue
        var pos = Vector3.ZERO
        if pad is Node3D and is_instance_valid(pad):
            pos = pad.global_position
        elif pad is Vector3:
            pos = pad
        else:
            continue
        for s in all_skaters:
            if s == null or s.downed:
                continue
            var key = int(s.get_instance_id())
            if _pad_cd.get(key, 0.0) > 0.0:
                continue
            if s.global_position.distance_to(pos) < 1.9:
                s.stamina = minf(100.0, s.stamina + 45.0)
                _pad_cd[key] = 1.2
                _sfx("ui_click", -12.0, randf_range(0.95, 1.08))
                FX.burst(self, pos + Vector3.UP * 0.3, CYAN, 12, 4.0, 0.12, 0.35)

func _check_goalie_clear() -> void:
    if not is_match_active() or puck == null:
        return
    for s in all_skaters:
        if s != null and s.is_goalie and not s.downed:
            goalie_clear(s)

func goalie_clear(sk) -> void:
    if not is_match_active() or puck == null or sk == null or not sk.is_goalie:
        return
    var key = int(sk.get_instance_id())
    if _goalie_clear_cd.get(key, 0.0) > 0.0:
        return
    if puck.carrier == sk:
        var mate = get_teammate(sk)
        if mate != null:
            request_pass(sk)
        else:
            request_shot(sk, 0.4)
        sk.shoot_lock = 1.2
        _goalie_clear_cd[key] = 1.2
        return
    if puck.carrier == null and sk.global_position.distance_to(puck.global_position) < 3.0 and puck.pickup_lock <= 0.0:
        var mate = get_teammate(sk)
        var target = mate.global_position if mate != null else Vector3(0, 0, 0)
        var dir = (target - puck.global_position)
        dir.y = 0.0
        if dir.length() < 0.1:
            dir = Vector3(0, 0, 1)
        var vel = dir.normalized() * 21.0
        puck.detach(puck.global_position, vel, sk)
        _goalie_clear_cd[key] = 1.5
        _sfx("body_check", -4.0)
        if camera_rig:
            camera_rig.add_shake(0.05)

func _tick_timers(delta: float) -> void:
    pass

func _check_control_switch_tick() -> void:
    pass

func is_puck_charged() -> bool:
    return puck != null and puck.charged

func is_match_active() -> bool:
    return state == PLAYING

func get_state_name() -> String:
    match state:
        MENU: return "menu"
        COUNTDOWN: return "countdown"
        PLAYING: return "playing"
        GOAL: return "goal"
        PERIOD_BREAK: return "period_break"
        GAME_OVER: return "game_over"
        PAUSED: return "paused"
    return "menu"

func get_camera_flat_basis() -> Basis:
    if camera_rig:
        return camera_rig.get_flat_basis()
    return Basis.IDENTITY

func get_player_aim_direction() -> Vector3:
    var aim = Vector3(0, 0, 1)
    if camera_rig:
        aim = camera_rig.get_aim_direction()
    aim.y = 0.0
    if aim.length() < 0.05:
        aim = get_camera_flat_basis().z * -1.0
    aim = aim.normalized()
    if controlled_skater != null:
        var goal = get_enemy_goal_position(controlled_skater)
        var to_goal = goal - controlled_skater.global_position
        to_goal.y = 0.0
        if to_goal.length() > 0.1:
            to_goal = to_goal.normalized()
            var d = aim.dot(to_goal)
            if d > 0.72:
                aim = aim.lerp(to_goal, clampf((d - 0.72) / 0.28, 0.0, 1.0) * 0.8).normalized()
    return Vector3(aim.x, 0.025, aim.z).normalized()

func get_puck():
    return puck

func get_carrier():
    if puck == null:
        return null
    return puck.carrier

func get_skaters() -> Array:
    return all_skaters

func get_controlled_skater():
    return controlled_skater

func get_team_score(team: int) -> int:
    return score_blue if team == BLUE else score_red

func get_match_clock() -> float:
    return clock

func get_period() -> int:
    return period

func is_overtime() -> bool:
    return overtime

func get_drome_bounds() -> Dictionary:
    return arena_data.get("bounds", {"half_width": DROME_HALF_WIDTH, "half_length": DROME_HALF_LENGTH})

func get_own_goal_position(sk):
    var z = -DROME_HALF_LENGTH if sk.team_id == BLUE else DROME_HALF_LENGTH
    return Vector3(0, 0, z)

func get_enemy_goal_position(sk):
    var z = DROME_HALF_LENGTH if sk.team_id == BLUE else -DROME_HALF_LENGTH
    return Vector3(0, 0, z)

func get_opponents(sk) -> Array:
    if sk.team_id == BLUE:
        return red_team
    return blue_team

func get_teammate(sk):
    var team = blue_team if sk.team_id == BLUE else red_team
    for s in team:
        if s != sk and s != null and not s.downed and not s.is_goalie:
            return s
    return null

func get_nearest_opponent(sk):
    var best = null
    var best_d = INF
    for s in get_opponents(sk):
        if s == null or s.downed or s.is_goalie:
            continue
        var d: float = sk.global_position.distance_to(s.global_position)
        if d < best_d:
            best_d = d
            best = s
    return best

func try_pickup(sk) -> bool:
    if not is_match_active() or puck == null or sk == null or sk.downed:
        return false
    if puck.carrier != null or puck.pickup_lock > 0.0:
        return false
    if sk.global_position.distance_to(puck.global_position) > 1.7:
        return false
    if puck.visible == false:
        return false
    if sk.is_goalie and puck.velocity.length() > 18.0:
        return false
    puck.attach_to(sk)
    return true

func drop_puck(sk, impulse_scale: float = 1.0) -> void:
    if puck == null or puck.carrier != sk:
        return
    var dir = -sk.facing
    if dir.length() < 0.1:
        dir = Vector3.BACK
    var vel = dir.normalized() * 4.5 * impulse_scale + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5))
    puck.detach(sk.get_puck_anchor(), vel, null, false)
    _sfx("metal_hit", -7.0)
    if sk.is_controlled:
        camera_rig.add_shake(0.06)

func request_shot(sk, charge: float) -> void:
    if not is_match_active() or puck == null or sk == null or not sk.carrying or puck.carrier != sk:
        return
    var strength = clampf(charge, 0.0, 1.0)
    var aim = sk.aim_dir
    if sk.is_controlled:
        aim = get_player_aim_direction()
    else:
        var goal = get_enemy_goal_position(sk)
        aim = (goal + Vector3(0, 0.6, 0) - sk.get_puck_anchor())
    var goal = get_enemy_goal_position(sk)
    var to_goal = goal - sk.global_position
    to_goal.y = 0.0
    if to_goal.length() > 0.1:
        to_goal = to_goal.normalized()
    var aim_flat = Vector3(aim.x, 0.0, aim.z).normalized()
    if aim_flat.dot(to_goal) > 0.84:
        aim = aim_flat.lerp(to_goal, 0.45).normalized() + Vector3(0, 0.03, 0)
    var power = lerpf(21.0, 55.0, strength)
    if sk.carrying and puck.charged:
        power = lerpf(28.0, 61.0, strength)
    var was_charged: bool = puck.charged
    var origin: Vector3 = sk.get_puck_anchor()
    puck.shoot_from(sk, origin, aim.normalized(), power, was_charged)
    sk.carrying = false
    sk.shoot_lock = 0.25
    if sk == controlled_skater:
        _hud_announce("SHOT FIRED", "CHARGE %d%%" % int(strength * 100.0), BLUE_COLOR, 0.35)
    if was_charged:
        _hud_announce("KILLBALL LAUNCHED", "TRACK THE IMPACT", AMBER, 0.9)

func request_pass(sk) -> void:
    if not is_match_active() or puck == null or sk == null or not sk.carrying:
        return
    if puck.carrier != sk:
        return
    var mate = get_teammate(sk)
    var aim = sk.facing
    if mate != null:
        var target = mate.global_position + mate.velocity * 0.16 - sk.global_position
        target.y = 0.0
        aim = target.normalized()
        if sk.is_controlled:
            _hud_announce("PASS", mate.display_name, BLUE_COLOR, 0.5)
    else:
        aim = get_enemy_goal_position(sk) - sk.global_position
        aim.y = 0.0
        aim = aim.normalized()
    var was_charged: bool = puck.charged
    puck.shoot_from(sk, sk.get_puck_anchor(), aim, 29.0, was_charged)
    sk.carrying = false
    sk.shoot_lock = 0.3
    _sfx("puck_pickup", -5.0)

func request_killball_throw(sk) -> void:
    if not is_match_active() or puck == null or sk == null or not sk.carrying:
        return
    if not puck.charged:
        _hud_announce("KILLBALL NOT ARMED", "FIND THE AMBER CHARGER", AMBER, 0.8)
        return
    var target = get_nearest_opponent(sk)
    var aim = sk.facing
    if target != null:
        aim = (target.get_center() - sk.get_puck_anchor()).normalized()
        aim.y = 0.08
    puck.shoot_from(sk, sk.get_puck_anchor(), aim.normalized(), 44.0, true)
    sk.carrying = false
    sk.shoot_lock = 0.45
    _hud_announce("KILLBALL RELEASED", "GET CLEAR", AMBER, 1.2)
    _sfx("killball_zap", -3.0)
    if target != null:
        _hud_feed("KILLBALL  //  " + (target.display_name), AMBER)
    if camera_rig:
        camera_rig.add_shake(0.12)

func on_goalie_save(sk, pos: Vector3, speed: float) -> void:
    _sfx("body_check", -2.0, randf_range(0.92, 1.08))
    if camera_rig and sk != null and sk.is_controlled:
        camera_rig.add_shake(0.05)
    if hud:
        var name = "NETMINDER" if sk == null else sk.display_name
        hud.add_kill_feed("SAVE  //  " + name, Color(1.0, 0.7, 0.2))
    FX.sparks(self, pos, Color(1.0, 0.7, 0.2), 10)

func on_puck_hit(sk, charged: bool, pos: Vector3) -> void:
    if demo_mode:
        demo_saw_hit = true
    if camera_rig:
        camera_rig.add_shake(0.18 if charged else 0.08)
    if hud:
        hud.screen_flash(AMBER if charged else Color(0.8, 0.95, 1.0), 0.12 if charged else 0.06)
    _sfx("heavy_hit", -2.0, randf_range(0.9, 1.1))

func spawn_hit_fx(pos: Vector3, color: Color, heavy: bool) -> void:
    FX.sparks(self, pos, color, 18 if heavy else 10)
    if heavy:
        FX.shockwave(self, pos, color, 2.2)

func spawn_slash_fx(pos: Vector3, color: Color, heavy: bool, direction: Vector3 = Vector3.FORWARD) -> void:
    FX.slash_arc(self, pos, direction, color)
    _sfx("slash_whoosh", -8.0, randf_range(0.9, 1.2))

func play_body_check_sfx() -> void:
    _sfx("body_check", -3.0, randf_range(0.92, 1.06))
    if camera_rig:
        camera_rig.add_shake(0.08)

func spawn_wall_spark(pos: Vector3, velocity: Vector3) -> void:
    if _wall_spark_cd > 0.0:
        return
    _wall_spark_cd = 0.05
    FX.wall_spark(self, pos, velocity)

func _hud_announce(text: String, sub: String = "", color: Color = Color.WHITE, duration: float = 1.0) -> void:
    if hud:
        hud.announce(text, sub, color, duration)

func _hud_feed(text: String, color: Color) -> void:
    if hud:
        hud.add_kill_feed(text, color)

func _hud_flash(strength: float) -> void:
    pass

func _screen_flash(color: Color, strength: float) -> void:
    if hud:
        hud.screen_flash(color, strength)

func _sfx(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
    if audio and audio.has_method("play_sfx"):
        audio.play_sfx(name, volume_db, pitch)

func _music(mode: String) -> void:
    if not audio:
        return
    if mode == "match" and audio.has_method("play_music"):
        audio.play_music("match")
    elif mode in ["victory", "defeat"] and audio.has_method("stop_music"):
        audio.stop_music()
    # Goal and period-break cues keep the match bed under the horn; no extra track.

func _exit_tree() -> void:
    Engine.time_scale = 1.0
    if audio:
        if audio.has_method("stop_all_sfx"):
            audio.stop_all_sfx()
        for player in audio.find_children("*", "AudioStreamPlayer", true, false):
            if player is AudioStreamPlayer:
                player.stop()

func _set_mouse_captured(captured: bool) -> void:
    if DisplayServer.get_name() == "headless":
        return
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

func get_context_hint() -> String:
    if controlled_skater == null:
        return ""
    if not controlled_skater.carrying:
        return ""
    if puck != null and puck.charged:
        return "KILLBALL ARMED  //  Q  THROW AT TARGET  //  HOLD LMB  SHOOT"
    if puck != null and puck.carrier == controlled_skater and controlled_skater.shoot_charge > 0.05:
        return "RELEASE LMB  //  FIRE"
    return ""

# --- evidence modes -------------------------------------------------------------------------

func _start_demo() -> void:
    start_match()
    for s in all_skaters:
        if s != null and s == controlled_skater:
            s.set_controlled(false)
            s.ai_enabled = true
    if camera_rig:
        camera_rig.set_target(blue_team[0])
    demo_start_ms = Time.get_ticks_msec()
    print("ULTRABLADE_DEMO_START skaters=", all_skaters.size(), " puck=", puck != null, " muted=", audio_muted)

func _process_demo(delta: float) -> void:
    demo_frames += 1
    if state == GOAL:
        pass
    var elapsed = Time.get_ticks_msec() - demo_start_ms
    if elapsed > int(demo_seconds * 1000.0) or state == GAME_OVER:
        _finish_demo()
        return
    _check_killball_charger()
    _check_boost_pads()
    _check_goalie_clear()
    _update_camera_target()
    if state == PLAYING:
        clock = maxf(0.0, clock - delta)
        if clock <= 0.0:
            clock = PERIOD_SECONDS
    elif state == COUNTDOWN:
        state_timer -= delta
        if state_timer <= 0.0:
            state = PLAYING
    elif state == GOAL:
        state_timer -= delta
        if state_timer <= 0.0:
            Engine.time_scale = normal_time_scale
            state = COUNTDOWN
            state_timer = 0.1
            _reset_round()
    elif state == PERIOD_BREAK:
        state_timer -= delta
        if state_timer <= 0.0:
            period += 1
            clock = PERIOD_SECONDS
            _reset_round()
            state = COUNTDOWN
            state_timer = 0.1

func _finish_demo() -> void:
    var carrier = puck.carrier if puck != null else null
    print("ULTRABLADE_DEMO_OK frames=", demo_frames, " state=", get_state_name(), " score=", score_blue, "-", score_red, " carrier=", carrier != null, " saw_pickup=", demo_saw_pickup, " saw_shot=", demo_saw_shot, " saw_hit=", demo_saw_hit, " saw_goal=", demo_saw_goal)
    _quit_after_cleanup(0)

func _quit_after_cleanup(code: int) -> void:
    Engine.time_scale = 1.0
    var tree = get_tree()
    if tree == null:
        return
    var timer = tree.create_timer(0.3, true, false, true)
    timer.timeout.connect(tree.quit.bind(code))
    queue_free()

func _start_capture_setup() -> void:
    _capture_index = 0
    print("ULTRABLADE_CAPTURE_START")
    # Leave the menu visible for the first capture.

func _process_capture(delta: float) -> void:
    _elapsed += delta
    if _capture_index >= _capture_times.size():
        return
    if _elapsed >= _capture_times[_capture_index]:
        _capture_index += 1
        match _capture_index:
            1:
                _shot("01-menu")
            2:
                start_match()
                state = PLAYING
                Engine.time_scale = 1.0
                _stage_capture_game()
                _shot("02-gameplay")
            3:
                _trigger_capture_goal()
                _shot("03-goal")
            4:
                _shot("04-broadcast")
                get_tree().quit(0)
    _check_killball_charger()
    _check_boost_pads()
    _check_goalie_clear()
    _update_camera_target()

func _stage_capture_game() -> void:
    if controlled_skater != null:
        controlled_skater.global_position = Vector3(-5, 0, -8)
        controlled_skater.rotation.y = PI
        controlled_skater.facing = Vector3.BACK
    if blue_team.size() > 1:
        blue_team[1].global_position = Vector3(5, 0, -4)
    if red_team.size() > 0:
        red_team[0].global_position = Vector3(0, 0, 4)
        red_team[1].global_position = Vector3(-6, 0, 8)
    if puck:
        puck.reset_to(controlled_skater.global_position + controlled_skater.facing * 1.0)
        puck.attach_to(controlled_skater)
        puck.set_charged(true)
    if camera_rig:
        camera_rig.set_mode("chase")
        camera_rig.set_target(controlled_skater)
        camera_rig.yaw = PI
        camera_rig.pitch = 0.2
    if hud:
        hud.set_goal_visible(true)

func _trigger_capture_goal() -> void:
    if hud:
        hud.show_goal(0, controlled_skater.display_name if controlled_skater else "KAI VOSS")
        hud.screen_flash(CYAN, 0.35)
    if camera_rig:
        camera_rig.goal_view(Vector3(0, 0, DROME_HALF_LENGTH), 1.0)
        camera_rig.add_shake(0.3)
    FX.goal_flash(self, Vector3(0, 0, DROME_HALF_LENGTH), CYAN)

func _shot(label: String) -> void:
    _capture_async(label)

func _capture_async(label: String) -> void:
    await RenderingServer.frame_post_draw
    var img = get_viewport().get_texture().get_image()
    if img == null:
        print("ULTRABLADE_CAPTURE_FAIL image_null ", label)
        return
    var dir = ProjectSettings.globalize_path("res://") + "../artifacts/captures"
    DirAccess.make_dir_recursive_absolute(dir)
    var path = dir + "/" + label + ".png"
    var err = img.save_png(path)
    print("ULTRABLADE_CAPTURE ", label, " -> ", path, " err=", err)

func _st_check(ok: bool, name: String) -> void:
    _st_checks += 1
    if not ok:
        _st_failures.append(name)
        print("SELFTEST_FAIL ", name)
    else:
        print("SELFTEST_OK ", name)

func _run_selftest() -> void:
    # Audio has its own 121-check suite; drop the live player so logic tests quit clean.
    if audio != null:
        audio.free()
        audio = null
    _st_checks = 0
    _st_failures = []
    _st_check(all_skaters.size() == 6, "six_skaters")
    _st_check(blue_team.size() == 3 and red_team.size() == 3, "team_structure")
    _st_check(controlled_skater == blue_team[0], "player_control")
    _st_check(puck != null, "puck_exists")
    _st_check(get_drome_bounds().has("half_width"), "bounds")
    state = PLAYING
    clock = 90.0
    Engine.time_scale = 1.0
    _reset_round()
    _set_controlled(blue_team[0])
    # Pickup
    puck.global_position = controlled_skater.get_puck_anchor() + controlled_skater.facing * 0.5
    puck.pickup_lock = 0.0
    var picked: bool = try_pickup(controlled_skater)
    _st_check(picked, "pickup")
    _st_check(controlled_skater.carrying, "carrying_state")
    # Shot
    var carrier_before = puck.carrier
    request_shot(controlled_skater, 1.0)
    _st_check(carrier_before != null and puck.carrier == null, "shot_release")
    _st_check(puck.velocity.length() > 20.0, "shot_velocity")
    # Slash + health
    state = PLAYING
    var enemy = red_team[0]
    enemy.downed = false
    enemy.hp = 100.0
    enemy.invuln = 0.0
    enemy.global_position = controlled_skater.global_position + controlled_skater.facing * 1.4
    controlled_skater.facing = Vector3(0, 0, 1)
    controlled_skater.slash_cd = 0.0
    controlled_skater.action_lock = 0.0
    controlled_skater.try_slash(false)
    _st_check(enemy.hp < 100.0, "slash_damage")
    # Heavy kill
    enemy.hp = 1.0
    enemy.invuln = 0.0
    enemy.take_damage(999.0, controlled_skater.global_position, true)
    _st_check(enemy.downed, "knockout")
    # Goal
    state = PLAYING
    score_blue = 0
    score_red = 0
    on_goal(BLUE, controlled_skater, false)
    _st_check(score_blue == 1, "goal_score")
    _st_check(state == GOAL, "goal_state")
    _st_check(Engine.time_scale < 1.0, "goal_slowmo")
    Engine.time_scale = 1.0
    # Killball
    state = PLAYING
    _reset_round()
    controlled_skater = blue_team[0]
    controlled_skater.downed = false
    puck.reset_to(controlled_skater.get_puck_anchor())
    puck.pickup_lock = 0.0
    try_pickup(controlled_skater)
    puck.set_charged(true)
    _st_check(puck.is_charged(), "killball_charge")
    request_killball_throw(controlled_skater)
    _st_check(puck.carrier == null and puck.velocity.length() > 30.0, "killball_throw")
    # Clock / rules
    state = PLAYING
    clock = 89.5
    period = 1
    _st_check(is_match_active(), "match_active")
    _st_check(get_period() == 1 and get_team_score(0) == 1, "state_getters")
    print("ULTRABLADE_SELFTEST_", "OK" if _st_failures.is_empty() else "FAIL", " checks=", _st_checks, " failures=", _st_failures)
    Engine.time_scale = 1.0
    _quit_after_cleanup(0 if _st_failures.is_empty() else 1)
