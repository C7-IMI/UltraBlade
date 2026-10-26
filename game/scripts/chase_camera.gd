class_name ChaseCamera
extends Node3D

## Broadcast chase camera with menu orbit, goal cam, FOV kick and shake.

var camera: Camera3D
var target: Node3D
var mode = "menu"
var yaw = PI
var pitch = 0.24
var distance = 7.4
var height = 3.0
var sensitivity = 0.0024
var fov_base = 76.0
var fov_target = 76.0
var _shake = 0.0
var _shake_t = 0.0
var _pos_smooth = Vector3.ZERO
var _look_smooth = Vector3.ZERO
var _goal_focus = Vector3.ZERO
var _goal_side = 1.0
var _menu_t = 0.0
var _initialized = false
var _roll = 0.0
var _height_source: Callable

func _ready() -> void:
    camera = Camera3D.new()
    camera.name = "BroadcastCamera"
    camera.near = 0.08
    camera.far = 220.0
    camera.fov = fov_base
    camera.current = true
    add_child(camera)

func set_target(t: Node3D) -> void:
    target = t

func set_mode(m: String) -> void:
    mode = m
    if m == "menu":
        _menu_t = 0.0

func chase() -> void:
    mode = "chase"

func goal_view(focus: Vector3, side: float) -> void:
    mode = "goal"
    _goal_focus = focus
    _goal_side = side
    _pos_smooth = camera.global_position
    _look_smooth = focus

func rotate_view(dx: float, dy: float) -> void:
    yaw -= dx * sensitivity
    pitch = clampf(pitch + dy * sensitivity, -0.32, 0.88)

func add_shake(amount: float) -> void:
    _shake = maxf(_shake, amount)

func set_height_source(source: Callable) -> void:
    _height_source = source

func _exit_tree() -> void:
    _height_source = Callable()

func get_flat_basis() -> Basis:
    return Basis(Vector3.UP, yaw)

func get_flat_forward() -> Vector3:
    return -get_flat_basis().z

func get_aim_origin() -> Vector3:
    return camera.global_position

func get_aim_direction() -> Vector3:
    return -camera.global_basis.z.normalized()

func _process(delta: float) -> void:
    if camera == null:
        return
    _menu_t += delta
    var desired_pos = camera.global_position
    var desired_look = Vector3.ZERO
    match mode:
        "menu":
            # Hero angle from the player's goal mouth, looking down the drome.
            var a = _menu_t * 0.04
            desired_pos = Vector3(sin(a) * 3.0, 6.6 + sin(_menu_t * 0.17) * 0.25, -30.0 + cos(a) * 0.6)
            desired_look = Vector3(0.0, 1.4, 7.0)
            fov_target = 68.0
        "chase":
            if target != null and is_instance_valid(target):
                var pivot: Vector3 = target.global_position + Vector3.UP * 1.5
                var flat = Vector3(sin(yaw), 0.0, cos(yaw))
                var dist = distance + clampf(target.velocity.length() * 0.035, 0.0, 2.0)
                var pos = pivot + flat * dist + Vector3.UP * height
                pos += flat * -0.8
                desired_pos = pos
                desired_look = pivot + get_flat_forward() * 2.7 + Vector3(0.0, 0.2 + pitch * 1.6, 0.0)
                var boosting = target.get("want_boost")
                fov_target = 90.0 if boosting == true else fov_base
                var want_height = clampf(2.2 + pitch * 3.6 + (0.35 if boosting == true else 0.0), 1.2, 6.0)
                height = lerpf(height, want_height, (3.0 if boosting == true else 2.0) * delta)
        "goal":
            var dist = 10.5
            var side = Vector3(_goal_side, 0, 0)
            var back = Vector3(_goal_side * 7.5, 2.8, -6.5 if _goal_focus.z > 0 else 6.5)
            desired_pos = _goal_focus + back
            desired_look = _goal_focus
            fov_target = 64.0
            _shake = maxf(_shake, 0.1)
        "paused":
            desired_pos = camera.global_position
            desired_look = camera.global_position - camera.global_basis.z * 10.0
            fov_target = 68.0
    if _height_source.is_valid() and (mode == "chase" or mode == "goal"):
        var terrain_y: float = float(_height_source.call(desired_pos.x, desired_pos.z))
        desired_pos.y = maxf(desired_pos.y, terrain_y + 1.35)
    if not _initialized:
        _pos_smooth = desired_pos
        _look_smooth = desired_look
        _initialized = true
    var lerp_speed = 6.0 if mode == "chase" else 3.0
    _pos_smooth = _pos_smooth.lerp(desired_pos, clampf(delta * lerp_speed, 0.0, 1.0))
    _look_smooth = _look_smooth.lerp(desired_look, clampf(delta * (lerp_speed + 2.0), 0.0, 1.0))
    var shake_offset = Vector3.ZERO
    if _shake > 0.001:
        _shake_t += delta * 38.0
        var amp = _shake
        shake_offset = Vector3(randf_range(-amp, amp), randf_range(-amp, amp), randf_range(-amp, amp)) * 0.12
        _shake = maxf(0.0, _shake - delta * 2.4)
    camera.global_position = _pos_smooth + shake_offset
    camera.look_at(_look_smooth + shake_offset * 0.3, Vector3.UP)
    if target != null and is_instance_valid(target) and mode == "chase":
        var lateral = target.velocity.dot(get_flat_basis().x)
        _roll = lerpf(_roll, clampf(-lateral * 0.008, -0.06, 0.06), delta * 4.0)
        camera.rotate_object_local(Vector3.FORWARD, _roll)
    camera.fov = lerpf(camera.fov, fov_target, clampf(delta * 5.0, 0.0, 1.0))
