class_name FX
extends RefCounted

## Procedural combat and broadcast effects. No textures, no external assets.

static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 18, speed: float = 5.0, size: float = 0.16, lifetime: float = 0.55) -> void:
    if parent == null:
        return
    var p := CPUParticles3D.new()
    p.amount = maxi(4, amount)
    p.lifetime = lifetime
    p.one_shot = true
    p.emitting = true
    p.explosiveness = 0.92
    p.randomness = 0.7
    p.local_coords = false
    p.direction = Vector3(0, 1, 0)
    p.spread = 180.0
    p.gravity = Vector3(0, -7.0, 0)
    p.initial_velocity_min = speed * 0.35
    p.initial_velocity_max = speed
    p.scale_amount_min = size * 0.25
    p.scale_amount_max = size
    p.color = color
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = color
    mat.emission_enabled = true
    mat.emission = color
    mat.emission_energy_multiplier = 4.0
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.vertex_color_use_as_albedo = true
    var quad := QuadMesh.new()
    quad.size = Vector2(size, size)
    quad.material = mat
    p.mesh = quad
    p.position = pos
    parent.add_child(p)
    _free_later(p, lifetime + 0.4)

static func sparks(parent: Node, pos: Vector3, color: Color, amount: int = 12) -> void:
    burst(parent, pos, color, amount, 8.0, 0.07, 0.3)

static func slash_arc(parent: Node, pos: Vector3, dir: Vector3, color: Color) -> void:
    if parent == null:
        return
    var mi := MeshInstance3D.new()
    var torus := TorusMesh.new()
    torus.inner_radius = 0.95
    torus.outer_radius = 1.32
    torus.rings = 32
    torus.ring_segments = 5
    mi.mesh = torus
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(color.r, color.g, color.b, 0.7)
    mat.emission_enabled = true
    mat.emission = color
    mat.emission_energy_multiplier = 5.0
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mi.material_override = mat
    parent.add_child(mi)
    mi.global_position = pos
    mi.rotation.x = deg_to_rad(90.0)
    var flat_dir := Vector3(dir.x, 0.0, dir.z)
    if flat_dir.length() < 0.01:
        flat_dir = Vector3.FORWARD
    var look_up := Vector3.UP if absf(flat_dir.normalized().dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
    mi.look_at(mi.global_position + flat_dir.normalized(), look_up)
    mi.rotate_object_local(Vector3.FORWARD, deg_to_rad(90.0))
    mi.scale = Vector3(0.7, 0.7, 0.7)
    var tw := mi.create_tween()
    tw.set_parallel(true)
    tw.tween_property(mi, "scale", Vector3(1.4, 1.4, 1.4), 0.18)
    tw.tween_property(mi, "transparency", 1.0, 0.18)
    tw.chain().tween_callback(mi.queue_free)

static func shockwave(parent: Node, pos: Vector3, color: Color, max_radius: float = 8.0) -> void:
    if parent == null:
        return
    var mi := MeshInstance3D.new()
    var torus := TorusMesh.new()
    torus.inner_radius = 0.82
    torus.outer_radius = 1.0
    torus.rings = 48
    torus.ring_segments = 6
    mi.mesh = torus
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
    mat.emission_enabled = true
    mat.emission = color
    mat.emission_energy_multiplier = 6.0
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mi.material_override = mat
    parent.add_child(mi)
    mi.global_position = pos + Vector3.UP * 0.1
    mi.scale = Vector3.ONE * 0.2
    var tw := mi.create_tween()
    tw.set_parallel(true)
    tw.tween_property(mi, "scale", Vector3.ONE * (max_radius / 1.0), 0.85).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
    tw.tween_property(mi, "transparency", 1.0, 0.85)
    tw.chain().tween_callback(mi.queue_free)

static func goal_flash(parent: Node, pos: Vector3, color: Color) -> void:
    if parent == null:
        return
    var light := OmniLight3D.new()
    light.light_color = color
    light.light_energy = 16.0
    light.omni_range = 28.0
    light.shadow_enabled = false
    parent.add_child(light)
    light.global_position = pos + Vector3.UP * 3.0
    var tw := light.create_tween()
    tw.tween_property(light, "light_energy", 0.0, 1.0)
    tw.tween_callback(light.queue_free)
    burst(parent, pos + Vector3.UP * 1.5, color, 60, 14.0, 0.35, 1.2)
    burst(parent, pos + Vector3.UP * 2.0, Color(1, 0.95, 0.8), 34, 8.0, 0.18, 0.8)
    shockwave(parent, pos, color, 9.0)

static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color) -> void:
    if parent == null:
        return
    var l := Label3D.new()
    l.text = "-" + str(int(round(amount)))
    l.font_size = 52
    l.pixel_size = 0.0038
    l.modulate = color
    l.outline_size = 10
    l.outline_modulate = Color(0, 0, 0, 0.85)
    l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    l.no_depth_test = true
    l.position = pos + Vector3.UP * 1.6
    parent.add_child(l)
    var start := l.position + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
    l.position = start
    var tw := l.create_tween()
    tw.set_parallel(true)
    tw.tween_property(l, "position", start + Vector3(0, 1.8, 0), 0.75)
    tw.tween_property(l, "modulate:a", 0.0, 0.75).set_delay(0.25)
    tw.chain().tween_callback(l.queue_free)

static func wall_spark(parent: Node, pos: Vector3, direction: Vector3, color: Color = Color(0.3, 0.9, 1.0)) -> void:
    sparks(parent, pos, color, 8)

static func _free_later(node: Node, seconds: float) -> void:
    if node == null:
        return
    var tree := node.get_tree()
    if tree == null:
        return
    var timer := tree.create_timer(seconds, true, false, true)
    timer.timeout.connect(func():
        if is_instance_valid(node):
            node.queue_free()
    )
