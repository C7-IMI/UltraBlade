class_name Puck
extends Node3D

## The rok. A deterministic arcade puck: carried, passed, shot and charged at the killball station.
## Physics are intentionally custom so possession and goal detection are readable and testable.

signal picked_up(by)
signal shot(by, strength: float, charged: bool)
signal goal_scored(scoring_team: int)
signal impacted(by, power: float)

const RADIUS = 0.32
const BASE_Y = 0.34
const MAX_SPEED = 62.0
const GRAVITY = 18.0
const WALL_HALF_W = 16.4
const WALL_HALF_L = 31.3
const GOAL_MOUTH_HALF = 4.6
const GOAL_LINE = 30.35

var main: Node
var carrier: Skater = null
var velocity = Vector3.ZERO
var charged = false
var pickup_lock = 0.0
var shot_lock = 0.0
var last_shooter: Skater = null
var last_team = -1
var hit_cooldowns = {}
var _goal_zone = 0
var _t = 0.0
var _spin = 0.0
var _charge_ratio = 0.0
var _mesh: MeshInstance3D
var _core_mat: StandardMaterial3D
var _ring1: MeshInstance3D
var _ring2: MeshInstance3D
var _light: OmniLight3D
var _trail: CPUParticles3D
var _sparks: CPUParticles3D
var _ghost_timer = 0.0
var _ghosts: Array[Node3D] = []

func setup(p_main: Node) -> void:
    main = p_main
    add_to_group("puck")
    _build_visual()

func _build_visual() -> void:
    var body = Node3D.new()
    body.name = "Rok"
    add_child(body)
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.04, 0.12, 0.16)
    mat.metallic = 1.0
    mat.roughness = 0.18
    mat.emission_enabled = true
    mat.emission = Color(0.1, 0.9, 1.0)
    mat.emission_energy_multiplier = 2.2
    _core_mat = mat
    _mesh = MeshInstance3D.new()
    var sm = SphereMesh.new()
    sm.radius = RADIUS
    sm.height = RADIUS * 1.35
    sm.radial_segments = 24
    sm.rings = 10
    _mesh.mesh = sm
    _mesh.material_override = mat
    _mesh.position.y = BASE_Y
    add_child(_mesh)
    var ring_mat = StandardMaterial3D.new()
    ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    ring_mat.albedo_color = Color(0.2, 1.0, 1.0)
    ring_mat.emission_enabled = true
    ring_mat.emission = Color(0.1, 0.9, 1.0)
    ring_mat.emission_energy_multiplier = 4.0
    _ring1 = MeshInstance3D.new()
    var tm = TorusMesh.new()
    tm.inner_radius = 0.39
    tm.outer_radius = 0.44
    tm.rings = 32
    tm.ring_segments = 6
    _ring1.mesh = tm
    _ring1.material_override = ring_mat
    _ring1.position.y = BASE_Y + 0.04
    _ring1.rotation.x = deg_to_rad(90.0)
    add_child(_ring1)
    _ring2 = MeshInstance3D.new()
    _ring2.mesh = tm
    _ring2.material_override = ring_mat
    _ring2.position.y = BASE_Y - 0.04
    _ring2.rotation.x = deg_to_rad(90.0)
    add_child(_ring2)
    _light = OmniLight3D.new()
    _light.light_color = Color(0.15, 0.9, 1.0)
    _light.light_energy = 1.6
    _light.omni_range = 4.0
    _light.position.y = 0.5
    add_child(_light)
    _trail = _make_particles(Color(0.1, 0.85, 1.0), 26, 0.22, 0.4)
    _trail.position.y = BASE_Y
    add_child(_trail)
    _sparks = _make_particles(Color(1.0, 0.55, 0.1), 30, 0.15, 1.8)
    _sparks.position.y = BASE_Y
    add_child(_sparks)

func _make_particles(color: Color, amount: int, size: float, lifetime: float) -> CPUParticles3D:
    var p = CPUParticles3D.new()
    p.amount = amount
    p.lifetime = lifetime
    p.one_shot = false
    p.emitting = false
    p.explosiveness = 0.0
    p.randomness = 0.5
    p.local_coords = false
    p.direction = Vector3(0, 1, 0)
    p.spread = 180.0
    p.gravity = Vector3(0, -2.0, 0)
    p.initial_velocity_min = 0.2
    p.initial_velocity_max = 1.5
    p.scale_amount_min = size * 0.4
    p.scale_amount_max = size
    var pm = StandardMaterial3D.new()
    pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    pm.albedo_color = color
    pm.emission_enabled = true
    pm.emission = color
    pm.emission_energy_multiplier = 3.0
    pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    pm.albedo_color.a = 0.7
    var quad = QuadMesh.new()
    quad.size = Vector2(size, size)
    quad.material = pm
    p.mesh = quad
    return p

func _physics_process(delta: float) -> void:
    if main == null:
        return
    _t += delta
    pickup_lock = maxf(0.0, pickup_lock - delta)
    shot_lock = maxf(0.0, shot_lock - delta)
    for k in hit_cooldowns.keys():
        hit_cooldowns[k] = maxf(0.0, hit_cooldowns[k] - delta)
    if carrier != null:
        if carrier.downed or not is_instance_valid(carrier):
            carrier = null
        else:
            var a = carrier.get_puck_anchor()
            global_position = global_position.lerp(a, minf(1.0, 18.0 * delta))
            _spin += delta * (9.0 + carrier.velocity.length() * 0.4)
            _mesh.rotation.y = _spin
            _mesh.rotation.x = deg_to_rad(12.0)
            _ring1.rotation.z += delta * 2.2
            _ring2.rotation.z -= delta * 2.8
            _trail.emitting = carrier.velocity.length() > 10.0
            _light.light_energy = 1.6
            _goal_zone = 0
            return
    if not visible:
        return
    # Free movement
    velocity.y -= GRAVITY * delta
    global_position += velocity * delta
    if global_position.y <= BASE_Y:
        global_position.y = BASE_Y
        if velocity.y < -2.0:
            velocity.y *= -0.28
        else:
            velocity.y = 0.0
        velocity.x *= 1.0 - minf(0.85, 1.1 * delta)
        velocity.z *= 1.0 - minf(0.85, 1.1 * delta)
    _spin += delta * (2.0 + velocity.length() * 0.55)
    _mesh.rotation.y = _spin
    _mesh.rotation.x += delta * 0.8
    _ring1.rotation.y += delta * 2.0
    _ring2.rotation.y -= delta * 3.0
    _update_effects()
    _bounce_walls()
    _check_bodies()
    _check_goal()

func _update_effects() -> void:
    var speed = velocity.length()
    _trail.emitting = speed > 5.0
    _trail.amount = clampi(int(6 + speed * 0.7), 8, 30)
    _light.light_energy = 1.2 + clampf(speed / 30.0, 0.0, 1.8)
    if charged:
        _sparks.emitting = true
        _light.light_color = Color(1.0, 0.55, 0.08)
        _core_mat.emission = Color(1.0, 0.35, 0.04)
        _core_mat.emission_energy_multiplier = 4.5 + sin(_t * 12.0) * 1.2
    else:
        _sparks.emitting = false
        _light.light_color = Color(0.15, 0.9, 1.0)
        _core_mat.emission = Color(0.1, 0.85, 1.0)
        _core_mat.emission_energy_multiplier = 2.2 + _charge_ratio * 2.5
    if _ghost_timer > 0.0:
        _ghost_timer -= get_physics_process_delta_time()
        if _ghost_timer <= 0.0:
            _ghost_timer = 0.055

func _bounce_walls() -> void:
    var nx = global_position.x / WALL_HALF_W
    var nz = global_position.z / WALL_HALF_L
    var d = nx * nx + nz * nz
    var end_attack = absf(global_position.z) > (GOAL_LINE - 1.0)
    var in_mouth = absf(global_position.x) < GOAL_MOUTH_HALF and global_position.y < 4.0
    if end_attack and in_mouth:
        # Let the puck cross the goal plane; _check_goal() owns the score so the
        # match director sees exactly one scoring event.
        return
    if d > 1.0:
        var s = 1.0 / sqrt(d)
        global_position.x *= s
        global_position.z *= s
        var n = Vector3(global_position.x / (WALL_HALF_W * WALL_HALF_W), 0.0, global_position.z / (WALL_HALF_L * WALL_HALF_L)).normalized()
        var dot = velocity.dot(n)
        if dot > 0.0:
            velocity -= n * dot * 1.6
            velocity *= 0.82
            impacted.emit(null, velocity.length())
        if absf(velocity.x) > 0.8 or absf(velocity.z) > 0.8:
            if main:
                main.spawn_wall_spark(global_position, velocity)

func _check_bodies() -> void:
    if main == null:
        return
    if carrier != null:
        return
    var speed = velocity.length()
    var skaters: Array = main.get_skaters()
    # Goalies are invulnerable and act as a physical last line: deflect shots.
    for s in skaters:
        if s == null or s.downed or not s.is_goalie:
            continue
        var gflat = s.global_position - global_position
        gflat.y = 0.0
        if gflat.length() < 1.55 and speed > 3.0:
            var attacking_own_goal = (s.team_id == 0 and velocity.z < 0.0) or (s.team_id == 1 and velocity.z > 0.0)
            if attacking_own_goal:
                var clear_dir := 1.0 if s.team_id == 0 else -1.0
                velocity = Vector3(randf_range(-7.0, 7.0), randf_range(2.0, 4.5), clear_dir * randf_range(8.0, 14.0))
                pickup_lock = 0.35
                shot_lock = 0.2
                charged = false
                if main.has_method("on_goalie_save"):
                    main.on_goalie_save(s, global_position, speed)
                return
    for s in skaters:
        if s == null or s.downed or s.is_goalie:
            continue
        var flat = s.global_position - global_position
        flat.y = 0.0
        if flat.length() < 1.15:
            if speed > 11.0 and s != last_shooter and s.team_id != last_team:
                var ck = int(s.get_instance_id())
                if hit_cooldowns.get(ck, 0.0) <= 0.0:
                    hit_cooldowns[ck] = 0.55
                    var dmg = 30.0 if charged else clampf(6.0 + speed * 0.4, 8.0, 20.0)
                    s.take_damage(dmg, global_position, speed > 28.0)
                    main.on_puck_hit(s, charged, global_position)
                    velocity *= 0.35
                    charged = false
                    if main.has_method("spawn_hit_fx"):
                        main.spawn_hit_fx(s.get_center(), Color(1.0, 0.55, 0.1), true)
                    break
            elif speed < 6.0 and pickup_lock <= 0.0:
                main.try_pickup(s)
                break

func _check_goal() -> void:
    if main == null:
        return
    if absf(global_position.z) > GOAL_LINE + 0.4 and absf(global_position.x) < GOAL_MOUTH_HALF and global_position.y < 4.2:
        var scoring_team = 0 if global_position.z > 0.0 else 1
        if _goal_zone != scoring_team + 1:
            _goal_zone = scoring_team + 1
            main.on_goal(scoring_team, last_shooter if is_instance_valid(last_shooter) else null, charged)
    elif absf(global_position.z) < GOAL_LINE - 1.5:
        _goal_zone = 0

func attach_to(skater: Skater) -> void:
    carrier = skater
    skater.carrying = true
    velocity = Vector3.ZERO
    pickup_lock = 0.2
    last_shooter = skater
    last_team = skater.team_id
    charged = false
    _charge_ratio = 0.0
    _goal_zone = 0
    global_position = skater.get_puck_anchor()
    picked_up.emit(skater)

func detach(pos: Vector3, impulse: Vector3, by: Skater = null, keep_charge: bool = false) -> void:
    if carrier != null:
        carrier.carrying = false
    carrier = null
    global_position = pos
    velocity = impulse
    pickup_lock = 0.28
    if by != null:
        last_shooter = by
        last_team = by.team_id
    if not keep_charge:
        charged = false
    _charge_ratio = 0.0
    shot_lock = 0.15

func shoot_from(skater: Skater, origin: Vector3, direction: Vector3, power: float, as_killball: bool = false) -> void:
    var d = direction.normalized()
    if d.length() < 0.01:
        d = skater.get_forward()
    var launch = origin + d * 0.7 + Vector3.UP * 0.55
    var impulse = d * clampf(power, 10.0, MAX_SPEED)
    impulse.y += 1.5 + clampf(power / 55.0, 0.0, 0.6)
    charged = as_killball
    detach(launch, impulse, skater, false)
    charged = as_killball
    last_shooter = skater
    last_team = skater.team_id
    pickup_lock = 0.45
    shot.emit(skater, power, charged)

func set_charged(v: bool) -> void:
    charged = v

func is_charged() -> bool:
    return charged

func set_charge_visual(r: float) -> void:
    _charge_ratio = clampf(r, 0.0, 1.0)

func reset_to(pos: Vector3) -> void:
    if carrier != null:
        carrier.carrying = false
    carrier = null
    charged = false
    velocity = Vector3.ZERO
    global_position = pos
    pickup_lock = 0.3
    last_shooter = null
    last_team = -1
    _goal_zone = 0
    visible = true
    _mesh.visible = true

func set_active(v: bool) -> void:
    visible = v
    process_mode = Node.PROCESS_MODE_INHERIT if v else Node.PROCESS_MODE_DISABLED
