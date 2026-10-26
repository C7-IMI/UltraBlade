class_name Skater
extends CharacterBody3D

## A drome athlete: physics, jak combat, AI and goalie behavior.
## The match director (main.gd) owns rules, possession and scoring.

signal died(skater)
signal damaged(skater, amount: float, source_position: Vector3, heavy: bool)
signal hit_landed(attacker, victim, heavy: bool)
signal slashed(skater, heavy: bool)
signal jumped(skater)
signal boost_started(skater)
signal state_changed(skater)

const TEAM_BLUE = 0
const TEAM_RED = 1

const BASE_SPEED = 11.5
const BOOST_MULT = 1.62
const ACCELERATION = 30.0
const TURN_RATE = 12.0
const GRAVITY = 24.0
const JUMP_SPEED = 8.2
const MAX_HP = 100.0
const MAX_STAMINA = 100.0
const SLASH_COOLDOWN = 0.42
const HEAVY_COOLDOWN = 0.95
const SLASH_RANGE = 2.55
const HEAVY_RANGE = 2.9
const SLASH_DAMAGE = 11.0
const HEAVY_DAMAGE = 25.0
const SHOT_DAMAGE = 14.0
const KILLBALL_DAMAGE = 34.0

var main: Node
var team_id = TEAM_BLUE
var role = "striker"
var display_name = "SKATER"
var is_goalie = false
var is_player = false
var is_controlled = false
var ai_enabled = true

var hp = MAX_HP
var stamina = MAX_STAMINA
var downed = false
var carrying = false

var facing = Vector3.FORWARD
var aim_dir = Vector3.FORWARD
var move_input = Vector3.ZERO
var want_boost = false
var jump_requested = false
var shoot_charge = 0.0
var charging = false
var shoot_lock = 0.0
var slash_cd = 0.0
var heavy_cd = 0.0
var action_lock = 0.0
var hit_flash = 0.0
var invuln = 0.0
var boost_fx = 0.0
var body_check_cd = 0.0
var _grounded := true

var ai_timer = 0.0
var ai_decision = 0.11
var ai_wander = 0.0
var rng = RandomNumberGenerator.new()
var team_color = Color(0.15, 0.9, 1.0)
var team_color_override := Color.TRANSPARENT
var role_color = Color(0.7, 0.9, 1.0)
var home_z = -27.5

var model: Node3D
var _model_script: Script
var _collision: CollisionShape3D
var _name_tag: Label3D
var _hp_bg: MeshInstance3D
var _hp_fill: MeshInstance3D
var _player_ring: MeshInstance3D
var _shadow: MeshInstance3D
var _fallback_body: Node3D
var _anim_state = ""
var _anim_speed = 0.0
var _trail_timer = 0.0
var _spawn_transform = Transform3D.IDENTITY

func setup(p_main: Node, p_team: int, p_role: String, p_goalie: bool, p_player: bool, idx: int) -> void:
    main = p_main
    team_id = p_team
    role = p_role
    is_goalie = p_goalie
    is_player = p_player
    is_controlled = p_player
    display_name = _name_for_role(role, idx)
    if team_color_override.a > 0.01:
        team_color = team_color_override
    else:
        team_color = Color(0.1, 0.85, 1.0) if team_id == TEAM_BLUE else Color(1.0, 0.16, 0.38)
    role_color = _role_color(role)
    rng.seed = 3341 + idx * 97 + team_id * 31
    ai_decision = 0.10 + rng.randf() * 0.05
    if is_goalie:
        ai_decision = 0.045
    add_to_group("skater")
    add_to_group("team_blue" if team_id == TEAM_BLUE else "team_red")
    collision_layer = 2
    collision_mask = 1 | 4
    floor_snap_length = 0.3
    _spawn_transform = transform

    var capsule = CapsuleShape3D.new()
    capsule.radius = 0.52
    capsule.height = 1.7
    var col = CollisionShape3D.new()
    col.shape = capsule
    col.position.y = 0.86
    _collision = col
    add_child(col)

    _build_visual()
    _build_health_bar()
    _build_player_ring()

func set_team_color(new_color: Color) -> void:
    team_color = new_color
    if model and model.has_method("set_team_color"):
        model.set_team_color(team_color)
    elif model and model.has_method("setup"):
        model.setup(team_color, role, is_player)
    if _hp_fill and _hp_fill.material_override is StandardMaterial3D:
        var hp_mat := _hp_fill.material_override as StandardMaterial3D
        hp_mat.albedo_color = team_color
        hp_mat.emission = team_color
    if _name_tag:
        _name_tag.modulate = team_color

func _ready() -> void:
    _spawn_transform = transform

func _name_for_role(r: String, idx: int) -> String:
    var pool = ["KAI VOSS", "RIVA TAL", "JAX MERCER", "NOVA KANE", "DRAKE SOL", "ASH VENN",
        "ORIN BLAZE", "SABLE RHEE", "TALON IX", "MIRA KOV", "RASK HALE", "VEX ARDEN"]
    var p = pool[(idx + (0 if team_id == TEAM_BLUE else 6)) % pool.size()]
    if r == "goalie":
        return p + " // NET"
    return p

func _role_color(r: String) -> Color:
    match r:
        "enforcer": return Color(1.0, 0.45, 0.1)
        "runner": return Color(0.2, 1.0, 0.65)
        "anchor": return Color(0.45, 0.5, 1.0)
        "goalie": return Color(1.0, 0.75, 0.2)
        _: return Color(0.75, 0.95, 1.0)

func _build_visual() -> void:
    if ResourceLoader.exists("res://scripts/skater_model.gd"):
        _model_script = load("res://scripts/skater_model.gd")
    if _model_script != null and _model_script.can_instantiate():
        model = _model_script.new()
        if model:
            add_child(model)
            if model.has_method("setup"):
                model.setup(team_color, role, is_player)
                return
    _build_fallback_visual()

func _build_fallback_visual() -> void:
    _fallback_body = Node3D.new()
    _fallback_body.name = "FallbackSkater"
    add_child(_fallback_body)
    var mat = StandardMaterial3D.new()
    mat.albedo_color = team_color.darkened(0.25)
    mat.metallic = 0.7
    mat.roughness = 0.3
    mat.emission_enabled = true
    mat.emission = team_color
    mat.emission_energy_multiplier = 0.7
    var torso = MeshInstance3D.new()
    var tm = CapsuleMesh.new()
    tm.radius = 0.34
    tm.height = 1.15
    torso.mesh = tm
    torso.material_override = mat
    torso.position.y = 1.0
    _fallback_body.add_child(torso)
    var head = MeshInstance3D.new()
    var hm = SphereMesh.new()
    hm.radius = 0.24
    hm.height = 0.48
    head.mesh = hm
    head.material_override = mat
    head.position.y = 1.75
    _fallback_body.add_child(head)
    var jak = MeshInstance3D.new()
    var bm = BoxMesh.new()
    bm.size = Vector3(0.08, 0.06, 0.85)
    jak.mesh = bm
    var jak_mat = StandardMaterial3D.new()
    jak_mat.albedo_color = Color(0.8, 0.95, 1.0)
    jak_mat.emission_enabled = true
    jak_mat.emission = team_color
    jak_mat.emission_energy_multiplier = 2.0
    jak.material_override = jak_mat
    jak.position = Vector3(-0.45, 0.95, -0.35)
    jak.rotation.x = -0.45
    _fallback_body.add_child(jak)

func _build_health_bar() -> void:
    if is_goalie:
        return
    _hp_bg = MeshInstance3D.new()
    var q = QuadMesh.new()
    q.size = Vector2(1.5, 0.075)
    _hp_bg.mesh = q
    var bg = StandardMaterial3D.new()
    bg.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    bg.albedo_color = Color(0.02, 0.04, 0.07, 0.85)
    bg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    bg.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    bg.no_depth_test = true
    _hp_bg.material_override = bg
    _hp_bg.position.y = 2.4
    add_child(_hp_bg)
    _hp_fill = MeshInstance3D.new()
    var q2 = QuadMesh.new()
    q2.size = Vector2(1.46, 0.045)
    _hp_fill.mesh = q2
    var fm = StandardMaterial3D.new()
    fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    fm.albedo_color = team_color
    fm.emission_enabled = true
    fm.emission = team_color
    fm.emission_energy_multiplier = 2.5
    fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    fm.no_depth_test = true
    _hp_fill.material_override = fm
    _hp_fill.position = Vector3(0, 2.4, 0.008)
    add_child(_hp_fill)

func _build_player_ring() -> void:
    if not is_player:
        return
    _player_ring = MeshInstance3D.new()
    var torus = TorusMesh.new()
    torus.inner_radius = 0.88
    torus.outer_radius = 0.98
    torus.rings = 40
    torus.ring_segments = 8
    _player_ring.mesh = torus
    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(1.0, 0.88, 0.2)
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.72, 0.08)
    mat.emission_energy_multiplier = 4.0
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color.a = 0.8
    _player_ring.material_override = mat
    _player_ring.position.y = 0.035
    add_child(_player_ring)

func set_spawn_transform(t: Transform3D) -> void:
    _spawn_transform = t
    global_transform = t

func set_controlled(v: bool) -> void:
    is_controlled = v
    if v:
        is_player = true
        if _player_ring:
            _player_ring.visible = true
    else:
        if _player_ring:
            _player_ring.visible = false
    if model and model.has_method("play"):
        model.play("idle", 0.0)

func is_alive() -> bool:
    return not downed

func can_act() -> bool:
    return not downed and action_lock <= 0.0 and main != null and main.is_match_active()

func get_forward() -> Vector3:
    return facing.normalized()

func get_puck_anchor() -> Vector3:
    return global_position + facing.normalized() * 0.92 + Vector3.UP * 0.82

func get_center() -> Vector3:
    return global_position + Vector3.UP * 0.9

func _physics_process(delta: float) -> void:
    if main == null:
        return
    _tick_timers(delta)
    if downed:
        return
    if main.is_match_active():
        if is_controlled and not is_goalie:
            _read_player_input(delta)
        elif ai_enabled:
            _ai_update(delta)
        else:
            move_input = Vector3.ZERO
    else:
        move_input = Vector3.ZERO
        want_boost = false
        charging = false
        shoot_charge = 0.0
    if main.is_match_active():
        _check_body_check()
    _apply_movement(delta)
    _update_visual_state(delta)
    _update_health_bar()

func _tick_timers(delta: float) -> void:
    slash_cd = max(0.0, slash_cd - delta)
    heavy_cd = max(0.0, heavy_cd - delta)
    shoot_lock = max(0.0, shoot_lock - delta)
    action_lock = max(0.0, action_lock - delta)
    hit_flash = max(0.0, hit_flash - delta)
    invuln = max(0.0, invuln - delta)
    boost_fx = max(0.0, boost_fx - delta)
    body_check_cd = max(0.0, body_check_cd - delta)
    if want_boost and stamina > 0.0 and not charging:
        stamina = max(0.0, stamina - 32.0 * delta)
    elif not want_boost:
        stamina = min(MAX_STAMINA, stamina + 22.0 * delta)
    if not want_boost and stamina <= 0.5:
        want_boost = false

func _read_player_input(delta: float) -> void:
    var basis: Basis = main.get_camera_flat_basis()
    var fwd = -basis.z
    var right = basis.x
    var inp = Vector2.ZERO
    if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        inp.y += 1.0
    if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        inp.y -= 1.0
    if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        inp.x += 1.0
    if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        inp.x -= 1.0
    if inp.length() > 1.0:
        inp = inp.normalized()
    move_input = (right * inp.x + fwd * inp.y).normalized()
    aim_dir = main.get_player_aim_direction()
    if move_input.length() < 0.01 and carrying:
        facing = aim_dir
    want_boost = (Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SHIFT)) and stamina > 3.0
    if want_boost and boost_fx <= 0.0:
        boost_fx = 0.2
        boost_started.emit(self)
    if (Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE)) and _grounded:
        jump_requested = true
    if (Input.is_physical_key_pressed(KEY_E) or Input.is_key_pressed(KEY_E)):
        if carrying and shoot_lock <= 0.0:
            main.request_pass(self)
    if (Input.is_physical_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_Q)):
        if carrying:
            main.request_killball_throw(self)

    var lmb = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    var rmb = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
    if rmb and heavy_cd <= 0.0 and not charging:
        try_slash(true)
    if carrying:
        if lmb:
            if not charging:
                charging = true
                shoot_charge = 0.0
            shoot_charge = min(1.0, shoot_charge + delta * 1.15)
        elif charging:
            var c = max(0.18, shoot_charge)
            charging = false
            shoot_charge = 0.0
            main.request_shot(self, c)
            shoot_lock = 0.36
    else:
        if inp.length() < 0.01:
            var aim_flat = aim_dir
            aim_flat.y = 0.0
            if aim_flat.length() > 0.01:
                facing = aim_flat.normalized()
                rotation.y = atan2(-facing.x, -facing.z)
        if lmb and slash_cd <= 0.0:
            try_slash(false)

func _ai_update(delta: float) -> void:
    ai_timer -= delta
    if ai_timer > 0.0:
        return
    ai_timer = ai_decision * (0.7 + rng.randf() * 0.6)
    if main == null:
        return
    var puck = main.get_puck()
    if puck == null:
        return
    var carrier = main.get_carrier()
    var enemy_goal: Vector3 = main.get_enemy_goal_position(self)
    var own_goal: Vector3 = main.get_own_goal_position(self)
    var puck_pos: Vector3 = puck.global_position
    var dist_puck = global_position.distance_to(puck_pos)
    var bucket_x = puck_pos.x

    if is_goalie:
        var guard_x = clampf(bucket_x * 0.62, -5.6, 5.6)
        var guard_z = own_goal.z + (1.7 if team_id == TEAM_BLUE else -1.7)
        var guard = Vector3(guard_x, 0.0, guard_z)
        move_input = (guard - global_position)
        move_input.y = 0.0
        if move_input.length() < 0.7:
            move_input = Vector3.ZERO
        else:
            move_input = move_input.normalized()
        facing = (puck_pos - global_position)
        facing.y = 0.0
        if facing.length() > 0.01:
            facing = facing.normalized()
        want_boost = global_position.distance_to(guard) > 3.0 and stamina > 25.0
        if carrier == self:
            main.goalie_clear(self)
        if carrier != null and carrier.team_id != team_id and global_position.distance_to(carrier.global_position) < 2.6:
            try_slash(false)
        elif dist_puck < 2.0:
            main.goalie_clear(self)
        return

    var target = puck_pos
    var speed_need = 8.0
    var nearest_enemy = main.get_nearest_opponent(self)
    var threat_dist = 999.0
    if nearest_enemy != null:
        threat_dist = global_position.distance_to(nearest_enemy.global_position)

    if carrier == self:
        var to_goal = enemy_goal - global_position
        to_goal.y = 0.0
        var goal_dist = to_goal.length()
        target = enemy_goal + Vector3(3.5 * sin(ai_wander), 0.0, 0.0)
        speed_need = 10.0
        # Shoot when the goal is in range and reasonably aligned.
        if goal_dist < 19.0 and absf(global_position.x) < 7.5 and shoot_lock <= 0.0 and not charging:
            var c = clampf(1.0 - goal_dist / 28.0, 0.28, 0.92)
            aim_dir = (enemy_goal + Vector3(0, 0.8, 0) - get_puck_anchor()).normalized()
            main.request_shot(self, c)
            shoot_lock = 0.65
        # Pass out of a double-team.
        if threat_dist < 2.2 and rng.randf() < 0.45:
            var mate = main.get_teammate(self)
            if mate != null and mate.global_position.distance_to(global_position) > 5.0:
                main.request_pass(self)
                shoot_lock = 0.5
        # Throw a charged killball at a nearby victim instead of the net.
        if main.is_puck_charged() and threat_dist < 12.0 and nearest_enemy != null and rng.randf() < 0.8:
            main.request_killball_throw(self)
            shoot_lock = 0.7
    elif carrier == null:
        target = puck_pos
        speed_need = 11.0
        if dist_puck < 1.4:
            main.try_pickup(self)
    elif carrier.team_id == team_id:
        var mate: Skater = carrier
        var support = enemy_goal - mate.global_position
        support.y = 0.0
        if support.length() > 0.1:
            support = support.normalized() * 7.0
        var side = Vector3(4.0 * (-1.0 if team_id == TEAM_BLUE else 1.0), 0.0, 0.0)
        target = mate.global_position + support + side
        speed_need = 8.5
    else:
        target = carrier.global_position
        speed_need = 11.5
        if threat_dist < 2.55:
            var to: Vector3 = carrier.global_position - global_position
            to.y = 0.0
            if to.length() > 0.01:
                facing = to.normalized()
            if rng.randf() < 0.72:
                try_slash(false)
            elif rng.randf() < 0.18:
                try_slash(true)
        elif threat_dist < 4.0 and rng.randf() < 0.2:
            try_slash(true)

    ai_wander += delta * (0.7 + rng.randf() * 0.3)
    var delta_v = target - global_position
    delta_v.y = 0.0
    var dist_target = delta_v.length()
    if dist_target < 0.7:
        move_input = Vector3.ZERO
    else:
        move_input = delta_v.normalized()
        facing = move_input
    want_boost = dist_target > 6.0 and stamina > 22.0 and (carrier == self or carrier == null or carrier.team_id != team_id)
    if carrying:
        facing = (enemy_goal - global_position).normalized()

func _check_body_check() -> void:
    if body_check_cd > 0.0 or not want_boost or is_goalie:
        return
    if Vector2(velocity.x, velocity.z).length() < 13.0:
        return
    for e in main.get_opponents(self):
        if e == null or e.downed or e.is_goalie:
            continue
        var flat = e.global_position - global_position
        flat.y = 0.0
        if flat.length() < 1.35:
            var dir = flat.normalized() if flat.length() > 0.01 else facing
            e.velocity += dir * 7.0
            e.take_damage(7.0, global_position, false)
            body_check_cd = 0.85
            hit_landed.emit(self, e, false)
            main.spawn_hit_fx(e.get_center(), team_color, false)
            if main and main.has_method("play_body_check_sfx"):
                main.play_body_check_sfx()
            break

func _apply_movement(delta: float) -> void:
    var desired_speed = BASE_SPEED
    if carrying:
        desired_speed *= 0.94
    if want_boost and stamina > 0.0:
        desired_speed *= BOOST_MULT
    if action_lock > 0.0:
        desired_speed *= 0.55
    if charging:
        desired_speed *= 0.72
    var target_velocity = move_input.normalized() * desired_speed
    var hv = Vector3(velocity.x, 0.0, velocity.z)
    var accel = ACCELERATION if move_input.length() > 0.05 else ACCELERATION * 0.8
    hv = hv.move_toward(target_velocity, accel * delta)
    velocity.x = hv.x
    velocity.z = hv.z
    if jump_requested and _grounded:
        velocity.y = JUMP_SPEED
        _grounded = false
        jumped.emit(self)
    elif _grounded:
        velocity.y = 0.0
    else:
        velocity.y -= GRAVITY * delta
    move_and_slide()
    jump_requested = false
    # The bowl is a height field, not a flat plane. Snap to the curved surface;
    # airborne skaters land on whichever bank/lane is beneath them.
    _clamp_to_drome()
    var surface_y := 0.0
    if main and main.has_method("get_surface_height"):
        surface_y = float(main.get_surface_height(global_position.x, global_position.z))
    if _grounded:
        global_position.y = surface_y
        velocity.y = 0.0
    elif velocity.y <= 0.0 and global_position.y <= surface_y + 0.12:
        global_position.y = surface_y
        velocity.y = 0.0
        _grounded = true
    if global_position.y < -2.0:
        global_position.y = surface_y
        velocity.y = 0.0
        _grounded = true
    if model and model.has_method("set_surface_normal"):
        if _grounded and main and main.has_method("get_surface_normal"):
            model.set_surface_normal(main.get_surface_normal(global_position.x, global_position.z))
        else:
            model.set_surface_normal(Vector3.UP)
    if move_input.length() > 0.15:
        var desired_yaw = atan2(-move_input.x, -move_input.z)
        rotation.y = lerp_angle(rotation.y, desired_yaw, minf(1.0, TURN_RATE * delta))
    elif carrying:
        var d = aim_dir
        d.y = 0.0
        if d.length() > 0.01:
            rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), minf(1.0, 10.0 * delta))
    facing = Vector3(-sin(rotation.y), 0.0, -cos(rotation.y)).normalized()

func _clamp_to_drome() -> void:
    var b = main.get_drome_bounds() if main and main.has_method("get_drome_bounds") else {}
    if not b.has("half_width"):
        return
    var hw: float = float(b.half_width) - 0.55
    var hl: float = float(b.half_length) - 0.9
    if hl <= 0.0 or hw <= 0.0:
        return
    var nx = global_position.x / hw
    var nz = global_position.z / hl
    var d = nx * nx + nz * nz
    if d > 1.0:
        var s = 1.0 / sqrt(d)
        var px = global_position.x * s
        var pz = global_position.z * s
        global_position.x = clampf(px, -hw, hw)
        global_position.z = clampf(pz, -hl, hl)
        velocity.x *= 0.2
        velocity.z *= 0.2

func _update_visual_state(delta: float) -> void:
    var speed = Vector2(velocity.x, velocity.z).length()
    var st = "idle"
    if downed:
        st = "down"
    elif action_lock > 0.25:
        st = "slash" if heavy_cd <= 0.0 else "heavy"
    elif not _grounded:
        st = "jump"
    elif speed > 16.0:
        st = "sprint"
    elif speed > 2.0:
        st = "skate"
    if st != _anim_state or absf(speed - _anim_speed) > 3.0:
        _anim_state = st
        _anim_speed = speed
        if model and model.has_method("play"):
            model.play(st, clampf(speed / (BASE_SPEED * BOOST_MULT), 0.0, 1.0))
    if model and model.has_method("set_carrying"):
        model.set_carrying(carrying)
    if model and model.has_method("set_boost"):
        model.set_boost(want_boost and speed > 8.0)
    if _player_ring:
        _player_ring.rotation.y += delta * 1.6
        if main != null and main.get_controlled_skater() != self:
            _player_ring.visible = false
        else:
            _player_ring.visible = true
    if _hp_fill:
        _hp_fill.scale.x = maxf(0.02, hp / MAX_HP)
        _hp_fill.position.x = -0.73 * (1.0 - hp / MAX_HP)
        var mat = _hp_fill.material_override as StandardMaterial3D
        if mat:
            mat.albedo_color = team_color.lerp(Color(1, 0.14, 0.1), 1.0 - hp / MAX_HP)
            mat.emission = mat.albedo_color

func _update_health_bar() -> void:
    if _name_tag == null:
        _name_tag = Label3D.new()
        _name_tag.text = display_name
        _name_tag.font_size = 26
        _name_tag.pixel_size = 0.004
        _name_tag.modulate = team_color
        _name_tag.outline_size = 8
        _name_tag.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
        _name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        _name_tag.no_depth_test = true
        _name_tag.position.y = 2.7
        add_child(_name_tag)

func try_slash(heavy: bool) -> void:
    if not can_act():
        return
    if is_controlled and main != null:
        # Soft target assist: only snap to the closest opponent already in front of
        # the player's aim. Never spin the player around for a target behind them.
        var reach = HEAVY_RANGE if heavy else SLASH_RANGE
        var best_target = null
        var best_dist = reach + 1.0
        for candidate in main.get_opponents(self):
            if candidate == null or candidate.downed:
                continue
            var t = candidate.global_position - global_position
            t.y = 0.0
            var d = t.length()
            if d > best_dist or d < 0.01:
                continue
            if t.normalized().dot(facing) < 0.2:
                continue
            best_dist = d
            best_target = candidate
        if best_target != null:
            var snap = best_target.global_position - global_position
            snap.y = 0.0
            facing = snap.normalized()
            rotation.y = atan2(-facing.x, -facing.z)
    if heavy:
        if heavy_cd > 0.0:
            return
        heavy_cd = HEAVY_COOLDOWN
        action_lock = 0.38
    else:
        if slash_cd > 0.0:
            return
        slash_cd = SLASH_COOLDOWN
        action_lock = 0.22
    if carrying:
        main.drop_puck(self, 1.0)
    slashed.emit(self, heavy)
    var range_sq = HEAVY_RANGE if heavy else SLASH_RANGE
    var any = false
    var opponents: Array = main.get_opponents(self)
    for e in opponents:
        if e == null or e.downed:
            continue
        var to: Vector3 = e.global_position - global_position
        to.y = 0.0
        var dist = to.length()
        if dist > range_sq:
            continue
        var dir = to.normalized() if dist > 0.01 else facing
        if dir.dot(facing) < 0.12:
            continue
        var dmg = HEAVY_DAMAGE if heavy else SLASH_DAMAGE
        var hit_pos: Vector3 = e.global_position + Vector3.UP * 1.1
        e.take_damage(dmg, global_position, heavy)
        any = true
        hit_landed.emit(self, e, heavy)
        main.spawn_hit_fx(hit_pos, team_color, heavy)
        if e.carrying:
            main.drop_puck(e, 2.5)
    if not any:
        main.spawn_slash_fx(global_position + facing * 1.15 + Vector3.UP * 1.0, team_color, heavy, facing)
    if any and model and model.has_method("burst"):
        model.burst("slash", get_center())

func take_damage(amount: float, source_position: Vector3, heavy: bool = false) -> void:
    if downed or main == null or not main.is_match_active():
        return
    if is_goalie:
        if main:
            main.spawn_hit_fx(get_center(), Color(1.0, 0.7, 0.2), false)
        return
    if invuln > 0.0:
        return
    invuln = 0.08
    hp -= amount
    hit_flash = 0.28
    action_lock = maxf(action_lock, 0.32 if heavy else 0.16)
    if carrying:
        main.drop_puck(self, 2.0)
    var away = global_position - source_position
    away.y = 0.0
    if away.length() > 0.01:
        velocity += away.normalized() * (9.0 if heavy else 4.0)
    damaged.emit(self, amount, source_position, heavy)
    if hp <= 0.0:
        _die()
    elif model and model.has_method("play"):
        model.play("hit", 0.0)

func _die() -> void:
    if downed:
        return
    downed = true
    hp = 0.0
    carrying = false
    charging = false
    shoot_charge = 0.0
    move_input = Vector3.ZERO
    velocity = Vector3.ZERO
    if model and model.has_method("play"):
        model.play("down", 0.0)
    if _hp_bg:
        _hp_bg.visible = false
    if _hp_fill:
        _hp_fill.visible = false
    if _collision:
        _collision.disabled = true
    died.emit(self)
    state_changed.emit(self)

func respawn(at: Transform3D) -> void:
    downed = false
    hp = MAX_HP
    stamina = MAX_STAMINA
    velocity = Vector3.ZERO
    global_transform = at
    invuln = 1.2
    action_lock = 0.0
    carrying = false
    charging = false
    shoot_charge = 0.0
    want_boost = false
    visible = true
    _grounded = true
    if _collision:
        _collision.disabled = false
    set_collision_layer_value(2, true)
    set_collision_mask_value(1, true)
    if _hp_bg:
        _hp_bg.visible = true
    if _hp_fill:
        _hp_fill.visible = true
    if model and model.has_method("play"):
        model.play("idle", 0.0)
    _anim_state = ""
    state_changed.emit(self)

func celebrate() -> void:
    if downed:
        return
    if model and model.has_method("play"):
        model.play("celebrate", 0.0)

func reset_round(at: Transform3D) -> void:
    var was_down = downed
    if was_down:
        hp = MAX_HP
        downed = false
        visible = true
        if _collision:
            _collision.disabled = false
        if _hp_bg:
            _hp_bg.visible = true
        if _hp_fill:
            _hp_fill.visible = true
    global_transform = at
    velocity = Vector3.ZERO
    stamina = MAX_STAMINA
    carrying = false
    charging = false
    shoot_charge = 0.0
    action_lock = 0.2
    invuln = 0.8
    _grounded = true
    if model and model.has_method("play"):
        model.play("idle", 0.0)
    _anim_state = ""

func face_towards(p: Vector3) -> void:
    var d = p - global_position
    d.y = 0.0
    if d.length() > 0.01:
        facing = d.normalized()
        rotation.y = atan2(-facing.x, -facing.z)

func get_role_name() -> String:
    return role.capitalize()
