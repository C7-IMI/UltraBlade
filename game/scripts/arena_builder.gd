class_name ArenaBuilder
extends RefCounted

## ULTRABLADE â€” "THE VAULT" drome builder.
## Contract (docs/CONTRACTS.md): static func build(parent: Node3D) -> Dictionary
## Builds the complete drome under parent. Calling again clears the old "Drome".
## Floor collision is intentionally NOT created here; the match layer owns the ice collider.

const BOUNDS_HALF_W = 16.0
const BOUNDS_HALF_L = 30.0
const ARENA_HALF_W = 16.3
const ARENA_HALF_L = 31.3
const CORNER_R = 2.0
const BOARD_H = 0.9
const BOARD_THICK = 0.4
const GOAL_HALF_W = 4.5
const GOAL_HEIGHT = 2.45
const GOAL_BACK_Z = 33.0

const COL_CYAN = Color(0.129, 0.902, 1.0)
const COL_MAGENTA = Color(1.0, 0.176, 0.435)
const COL_AMBER = Color(1.0, 0.690, 0.125)
const COL_BONE = Color(0.918, 0.965, 1.0)

const DROME_SHAPE = preload("res://scripts/drome_shape.gd")
const SH_ICE = preload("res://shaders/arena_ice.gdshader")
const SH_BOARDS = preload("res://shaders/arena_boards.gdshader")
const SH_GLOW = preload("res://shaders/arena_glow.gdshader")
const SH_CROWD = preload("res://shaders/arena_crowd.gdshader")
const SH_HOLO = preload("res://shaders/arena_holo.gdshader")
const SH_GOAL = preload("res://shaders/arena_goal_energy.gdshader")
const SH_JUMBO = preload("res://shaders/arena_jumbotron.gdshader")
const SH_BOOST = preload("res://shaders/arena_boost.gdshader")
const SH_LASER = preload("res://shaders/arena_laser.gdshader")
const SH_HAZARD_RING = preload("res://shaders/arena_hazard_ring.gdshader")


static func build(parent: Node3D) -> Dictionary:
	if parent == null:
		push_error("ArenaBuilder.build(parent): parent is null")
		return {}
	var stale: Array[Node] = []
	for child in parent.get_children():
		if child.name == "Drome":
			stale.append(child)
	for child in stale:
		parent.remove_child(child)
		child.queue_free()
	var builder = _DromeBuilder.new()
	return builder.run(parent)


# ---------------------------------------------------------------------------
# Runtime behaviour: hazards own their damage, pads expose their values.
# ---------------------------------------------------------------------------

class Turnstile extends Node3D:
	var arm_pivot: Node3D
	var spin_speed = 1.9
	var damage = 10.0
	var reach = 2.35
	var hit_cooldown = 0.9
	var _cooldowns = {}

	func _physics_process(delta: float) -> void:
		if arm_pivot != null:
			arm_pivot.rotate_y(spin_speed * delta)
		for id in _cooldowns.keys():
			var left: float = float(_cooldowns[id]) - delta
			if left <= 0.0:
				_cooldowns.erase(id)
			else:
				_cooldowns[id] = left
		var skaters = get_tree().get_nodes_in_group("skater")
		if skaters.is_empty():
			return
		for body in skaters:
			var bnode = body as Node3D
			if bnode == null:
				continue
			var id: int = bnode.get_instance_id()
			if _cooldowns.has(id):
				continue
			var pos = bnode.global_position
			if pos.y > 1.7:
				continue
			var dx = pos.x - global_position.x
			var dz = pos.z - global_position.z
			var dist = sqrt(dx * dx + dz * dz)
			if dist < 0.45 or dist > reach:
				continue
			var body_ang = atan2(-dz, dx)
			var arm_ang = arm_pivot.rotation.y if arm_pivot != null else 0.0
			var hit = false
			for i in 3:
				var da = wrapf(body_ang - (arm_ang + TAU * float(i) / 3.0), -PI, PI)
				if absf(sin(da)) * dist < 0.34 and absf(cos(da)) > 0.25:
					hit = true
					break
			if hit:
				_cooldowns[id] = hit_cooldown
				if bnode.has_method("take_damage"):
					bnode.call("take_damage", damage, global_position)


class LaserStrip extends Node3D:
	var beam: MeshInstance3D
	var material: ShaderMaterial
	var half_span = 12.6
	var damage = 8.0
	var off_time = 1.05
	var warn_time = 0.35
	var on_time = 1.55
	var phase = 0.0
	var hit_cooldown = 0.85
	var _t = 0.0
	var _cooldowns = {}

	func _physics_process(delta: float) -> void:
		_t += delta
		for id in _cooldowns.keys():
			var left: float = float(_cooldowns[id]) - delta
			if left <= 0.0:
				_cooldowns.erase(id)
			else:
				_cooldowns[id] = left
		var cycle = off_time + warn_time + on_time
		var t = fmod(_t + phase, cycle)
		var level = 0.0
		var hot = false
		if t < off_time:
			level = 0.0
		elif t < off_time + warn_time:
			level = 0.35
		else:
			level = 1.0
			hot = true
		if material != null:
			material.set_shader_parameter("active", level)
		if not hot:
			return
		var skaters = get_tree().get_nodes_in_group("skater")
		for body in skaters:
			var bnode = body as Node3D
			if bnode == null:
				continue
			var id: int = bnode.get_instance_id()
			if _cooldowns.has(id):
				continue
			var pos = bnode.global_position
			if pos.y > 0.85:
				continue
			if absf(pos.z - global_position.z) > 0.6:
				continue
			if absf(pos.x) > half_span:
				continue
			_cooldowns[id] = hit_cooldown
			if bnode.has_method("take_damage"):
				bnode.call("take_damage", damage, global_position)


class BoostPad extends Area3D:
	var team = "blue"
	var boost_amount = 0.45

	func get_team() -> String:
		return team

	func get_boost_amount() -> float:
		return boost_amount


class Drone extends Node3D:
	var base_y = 9.2
	var bob_amp = 0.32
	var bob_speed = 1.15
	var phase = 0.0
	var spin = 0.22

	func _physics_process(delta: float) -> void:
		var t = Time.get_ticks_msec() * 0.001
		position.y = base_y + sin(t * bob_speed + phase) * bob_amp
		rotate_y(spin * delta)


class RingSpin extends Node3D:
	var speed = 0.8

	func _physics_process(delta: float) -> void:
		rotate_y(speed * delta)


# ---------------------------------------------------------------------------
# Build state
# ---------------------------------------------------------------------------

class _DromeBuilder extends RefCounted:
	var _parent: Node3D
	var _root: Node3D
	var _rng = RandomNumberGenerator.new()
	var _mats = {}
	var _outline = PackedVector3Array()
	var _outline_normals = PackedVector3Array()
	var _outline_u = PackedFloat32Array()
	var _crowd_outline = PackedVector3Array()
	var _crowd_normals = PackedVector3Array()
	var _structure_st: SurfaceTool
	var _boards_st: SurfaceTool
	var _glow_st: SurfaceTool
	var _holo_st: SurfaceTool
	var _energy_st: SurfaceTool
	var _boost_st: SurfaceTool
	var _player_goal: Area3D
	var _enemy_goal: Area3D
	var _killball_charger: Area3D
	var _spawn_blue: Array[Transform3D] = []
	var _spawn_red: Array[Transform3D] = []
	var _center_spawn = Transform3D.IDENTITY
	var _boost_pads: Array[Node3D] = []
	var _hazards: Array[Node3D] = []

	func run(parent: Node3D) -> Dictionary:
		_parent = parent
		_rng.seed = 20991
		_init_materials()
		_root = Node3D.new()
		_root.name = "Drome"
		_make_rings()
		_structure_st = _new_st()
		_boards_st = _new_st()
		_glow_st = _new_st()
		_holo_st = _new_st()
		_energy_st = _new_st()
		_boost_st = _new_st()
		_build_floor()
		_build_boards()
		_build_board_colliders()
		_build_stands()
		_build_roof()
		_build_crowd()
		_build_jumbotron()
		_build_holo_banners()
		_build_goals()
		_build_boost_pads()
		_build_hazards()
		_build_charger()
		_build_drones()
		_build_particles()
		_build_spawns()
		_build_lighting()
		_commit_all()
		_parent.add_child(_root)
		return {
			"root": _root,
			"player_goal": _player_goal,
			"enemy_goal": _enemy_goal,
			"spawn_blue": _spawn_blue,
			"spawn_red": _spawn_red,
			"center_spawn": _center_spawn,
			"boost_pads": _boost_pads,
			"hazards": _hazards,
			"killball_charger": _killball_charger,
			"bounds": {"half_width": BOUNDS_HALF_W, "half_length": BOUNDS_HALF_L},
		}

	func _init_materials() -> void:
		var ice = ShaderMaterial.new()
		ice.shader = SH_ICE
		ice.set_shader_parameter("emit_scale", 0.55)
		_mats["ice"] = ice
		var boards = ShaderMaterial.new()
		boards.shader = SH_BOARDS
		boards.set_shader_parameter("emissive_scale", 0.65)
		_mats["boards"] = boards
		var glow = ShaderMaterial.new()
		glow.shader = SH_GLOW
		glow.set_shader_parameter("intensity", 1.25)
		_mats["glow"] = glow
		var crowd = ShaderMaterial.new()
		crowd.shader = SH_CROWD
		crowd.set_shader_parameter("intensity", 1.0)
		_mats["crowd"] = crowd
		var holo = ShaderMaterial.new()
		holo.shader = SH_HOLO
		holo.set_shader_parameter("intensity", 0.9)
		_mats["holo"] = holo
		var goal = ShaderMaterial.new()
		goal.shader = SH_GOAL
		goal.set_shader_parameter("intensity", 1.2)
		_mats["goal_energy"] = goal
		var jumbo = ShaderMaterial.new()
		jumbo.shader = SH_JUMBO
		jumbo.set_shader_parameter("intensity", 0.9)
		_mats["jumbo"] = jumbo
		var boost = ShaderMaterial.new()
		boost.shader = SH_BOOST
		boost.set_shader_parameter("intensity", 1.1)
		_mats["boost"] = boost
		var laser = ShaderMaterial.new()
		laser.shader = SH_LASER
		_mats["laser"] = laser
		var hazard_ring = ShaderMaterial.new()
		hazard_ring.shader = SH_HAZARD_RING
		hazard_ring.set_shader_parameter("intensity", 1.0)
		_mats["hazard_ring"] = hazard_ring
		var structure = StandardMaterial3D.new()
		structure.albedo_color = Color(0.070, 0.090, 0.120)
		structure.metallic = 0.40
		structure.roughness = 0.48
		structure.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["structure"] = structure

	func _new_st() -> SurfaceTool:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		return st

	func _commit_st(st: SurfaceTool, node_name: String, material: Material, shadows: bool) -> MeshInstance3D:
		if st == null:
			return null
		var mesh = st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			return null
		var mi = MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = mesh
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)
		return mi

	func _commit_all() -> void:
		_commit_st(_boards_st, "Boards", _mats["boards"], true)
		_commit_st(_structure_st, "DromeStructure", _mats["structure"], true)
		_commit_st(_glow_st, "NeonTrim", _mats["glow"], false)
		_commit_st(_holo_st, "HoloBanners", _mats["holo"], false)
		_commit_st(_energy_st, "GoalEnergy", _mats["goal_energy"], false)
		_commit_st(_boost_st, "BoostStripVisuals", _mats["boost"], false)


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

	func _lin(c: Color) -> Color:
		return c.srgb_to_linear()

	func _team_for_z(z: float) -> Color:
		var zone = smoothstep(-4.0, 4.0, z)
		return _lin(COL_CYAN.lerp(COL_MAGENTA, zone))

	func _team_color(side: float) -> Color:
		return _lin(COL_CYAN if side < 0.0 else COL_MAGENTA)

	func _in_goal_opening(p: Vector3) -> bool:
		return absf(p.z) > ARENA_HALF_L - 1.0 and absf(p.x) < GOAL_HALF_W + 0.24

	func _make_rings() -> void:
		var main: Dictionary = _ring_arrays(0.9)
		_outline = main["points"]
		_outline_normals = main["normals"]
		_outline_u = main["u"]
		var crowd: Dictionary = _ring_arrays(0.58)
		_crowd_outline = crowd["points"]
		_crowd_normals = crowd["normals"]

	func _ring_arrays(spacing: float) -> Dictionary:
		# A true ellipse, not a rounded rectangle: the long sides and ends are one
		# continuous curve, which is the shape that drives the whole bowl.
		var pts = PackedVector3Array()
		var nrm = PackedVector3Array()
		var a = ARENA_HALF_W
		var b = ARENA_HALF_L
		var count := maxi(48, int(round((a + b) * PI / spacing)))
		var dists := PackedFloat32Array()
		var total := 0.0
		for i in count:
			var theta := TAU * float(i) / float(count)
			var p := Vector3(cos(theta) * a, 0.0, sin(theta) * b)
			pts.append(p)
			nrm.append(Vector3(cos(theta) / a, 0.0, sin(theta) / b).normalized())
		for i in count:
			dists.append(total)
			total += pts[i].distance_to(pts[(i + 1) % count])
		var u := PackedFloat32Array()
		for i in count:
			u.append(dists[i] / maxf(total, 0.0001))
		return {"points": pts, "normals": nrm, "u": u, "length": total}

	func _line_points(from2: Vector2, to2: Vector2, normal2: Vector2, spacing: float) -> Dictionary:
		var pts = PackedVector3Array()
		var nrm = PackedVector3Array()
		var count = maxi(1, int(round(from2.distance_to(to2) / spacing)))
		var n3 = Vector3(normal2.x, 0.0, normal2.y).normalized()
		for i in count:
			var p2 = from2.lerp(to2, float(i) / float(count))
			pts.append(Vector3(p2.x, 0.0, p2.y))
			nrm.append(n3)
		return {"p": pts, "n": nrm}

	func _arc_points(center2: Vector2, radius: float, start: float, sweep: float, spacing: float) -> Dictionary:
		var pts = PackedVector3Array()
		var nrm = PackedVector3Array()
		var count = maxi(2, int(round(radius * sweep / spacing)))
		for i in count:
			var theta = start + sweep * float(i) / float(count)
			var dir = Vector2(cos(theta), sin(theta))
			pts.append(Vector3(center2.x + dir.x * radius, 0.0, center2.y + dir.y * radius))
			nrm.append(Vector3(dir.x, 0.0, dir.y))
		return {"p": pts, "n": nrm}

	func _offset_ring(offset: float, height: float) -> PackedVector3Array:
		var out = PackedVector3Array()
		for i in _outline.size():
			out.append(_outline[i] + _outline_normals[i] * offset + Vector3(0.0, height, 0.0))
		return out


# ---------------------------------------------------------------------------
# Raw geometry helpers
# ---------------------------------------------------------------------------

	func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, normal: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2) -> void:
		st.set_normal(normal)
		st.set_color(col)
		st.set_uv(uva)
		st.add_vertex(a)
		st.set_normal(normal)
		st.set_color(col)
		st.set_uv(uvb)
		st.add_vertex(b)
		st.set_normal(normal)
		st.set_color(col)
		st.set_uv(uvc)
		st.add_vertex(c)

	func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2) -> void:
		var n = (b - a).cross(c - a)
		if n.length_squared() > 0.0000001:
			n = n.normalized()
		else:
			n = Vector3.UP
		_tri(st, a, b, c, col, n, uva, uvb, uvc)
		_tri(st, a, c, d, col, n, uva, uvc, uvd)

	func _prism(st: SurfaceTool, a: Vector3, b: Vector3, half_w: float, half_h: float, col: Color) -> void:
		var d = b - a
		if d.length_squared() < 0.000001:
			return
		d = d.normalized()
		var ref = Vector3.UP
		if absf(d.dot(Vector3.UP)) > 0.94:
			ref = Vector3.RIGHT
		var right = d.cross(ref).normalized()
		var up = right.cross(d).normalized()
		var a0 = a - right * half_w - up * half_h
		var a1 = a + right * half_w - up * half_h
		var a2 = a + right * half_w + up * half_h
		var a3 = a - right * half_w + up * half_h
		var b0 = b - right * half_w - up * half_h
		var b1 = b + right * half_w - up * half_h
		var b2 = b + right * half_w + up * half_h
		var b3 = b - right * half_w + up * half_h
		var z = Vector2.ZERO
		_quad(st, a0, a1, b1, b0, col, z, z, z, z)
		_quad(st, a1, a2, b2, b1, col, z, z, z, z)
		_quad(st, a2, a3, b3, b2, col, z, z, z, z)
		_quad(st, a3, a0, b0, b3, col, z, z, z, z)
		_quad(st, a0, a3, a2, a1, col, z, z, z, z)
		_quad(st, b0, b1, b2, b3, col, z, z, z, z)

	func _box(st: SurfaceTool, center: Vector3, half: Vector3, col: Color) -> void:
		var hx = half.x
		var hy = half.y
		var hz = half.z
		var z = Vector2.ZERO
		_quad(st, center + Vector3(-hx, -hy, hz), center + Vector3(hx, -hy, hz), center + Vector3(hx, hy, hz), center + Vector3(-hx, hy, hz), col, z, z, z, z)
		_quad(st, center + Vector3(hx, -hy, -hz), center + Vector3(-hx, -hy, -hz), center + Vector3(-hx, hy, -hz), center + Vector3(hx, hy, -hz), col, z, z, z, z)
		_quad(st, center + Vector3(hx, -hy, hz), center + Vector3(hx, -hy, -hz), center + Vector3(hx, hy, -hz), center + Vector3(hx, hy, hz), col, z, z, z, z)
		_quad(st, center + Vector3(-hx, -hy, -hz), center + Vector3(-hx, -hy, hz), center + Vector3(-hx, hy, hz), center + Vector3(-hx, hy, -hz), col, z, z, z, z)
		_quad(st, center + Vector3(-hx, hy, hz), center + Vector3(hx, hy, hz), center + Vector3(hx, hy, -hz), center + Vector3(-hx, hy, -hz), col, z, z, z, z)
		_quad(st, center + Vector3(-hx, -hy, -hz), center + Vector3(hx, -hy, -hz), center + Vector3(hx, -hy, hz), center + Vector3(-hx, -hy, hz), col, z, z, z, z)

	func _box_uv(st: SurfaceTool, center: Vector3, half: Vector3, col: Color) -> void:
		var hx = half.x
		var hy = half.y
		var hz = half.z
		var faces = [
			[Vector3(-hx, -hy, hz), Vector3(2.0 * hx, 0.0, 0.0), Vector3(0.0, 2.0 * hy, 0.0)],
			[Vector3(hx, -hy, -hz), Vector3(-2.0 * hx, 0.0, 0.0), Vector3(0.0, 2.0 * hy, 0.0)],
			[Vector3(hx, -hy, hz), Vector3(0.0, 0.0, -2.0 * hz), Vector3(0.0, 2.0 * hy, 0.0)],
			[Vector3(-hx, -hy, -hz), Vector3(0.0, 0.0, 2.0 * hz), Vector3(0.0, 2.0 * hy, 0.0)],
			[Vector3(-hx, hy, hz), Vector3(2.0 * hx, 0.0, 0.0), Vector3(0.0, 0.0, -2.0 * hz)],
			[Vector3(-hx, -hy, -hz), Vector3(2.0 * hx, 0.0, 0.0), Vector3(0.0, 0.0, 2.0 * hz)],
		]
		for face in faces:
			var origin: Vector3 = center + face[0]
			var du: Vector3 = face[1]
			var dv: Vector3 = face[2]
			_quad(st, origin, origin + du, origin + du + dv, origin + dv, col, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))

	func _annulus(st: SurfaceTool, center: Vector3, r_in: float, r_out: float, sides: int, col: Color, polar_uv: bool) -> void:
		for i in sides:
			var a0 = TAU * float(i) / float(sides)
			var a1 = TAU * float(i + 1) / float(sides)
			var d0 = Vector3(cos(a0), 0.0, sin(a0))
			var d1 = Vector3(cos(a1), 0.0, sin(a1))
			var u0 = Vector2(float(i) / float(sides), 0.0) if polar_uv else Vector2.ZERO
			var u1 = Vector2(float(i + 1) / float(sides), 0.0) if polar_uv else Vector2.ZERO
			var u0o = Vector2(float(i) / float(sides), 1.0) if polar_uv else Vector2.ZERO
			var u1o = Vector2(float(i + 1) / float(sides), 1.0) if polar_uv else Vector2.ZERO
			var p0 = center + d0 * r_in
			var p1 = center + d0 * r_out
			var p2 = center + d1 * r_out
			var p3 = center + d1 * r_in
			_tri(st, p0, p1, p2, col, Vector3.UP, u0, u0o, u1o)
			_tri(st, p0, p2, p3, col, Vector3.UP, u0, u1o, u1)


# ---------------------------------------------------------------------------
# Ice floor + boards + colliders
# ---------------------------------------------------------------------------

	func _build_floor() -> void:
		# Radial elliptical grid. The flat goal lane and the curved banks are one
		# continuous mesh so the drome reads as a bowl rather than a plane.
		var st = _new_st()
		var rings := 30
		var segs := 120
		var white = Color.WHITE
		var uvz = Vector2.ZERO
		var center := Vector3(0.0, DROME_SHAPE.height(0.0, 0.0), 0.0)
		for i in segs:
			var theta0 := TAU * float(i) / float(segs)
			var theta1 := TAU * float(i + 1) / float(segs)
			var p0 := _floor_point(theta0, 1.0 / float(rings))
			var p1 := _floor_point(theta1, 1.0 / float(rings))
			var n := DROME_SHAPE.normal((p0.x + p1.x) * 0.5, (p0.z + p1.z) * 0.5)
			_tri(st, center, p0, p1, white, n, uvz, uvz, uvz)
		for r in range(1, rings):
			var r0 := float(r) / float(rings)
			var r1 := float(r + 1) / float(rings)
			for i in segs:
				var theta0 := TAU * float(i) / float(segs)
				var theta1 := TAU * float(i + 1) / float(segs)
				var a := _floor_point(theta0, r0)
				var b := _floor_point(theta1, r0)
				var c := _floor_point(theta1, r1)
				var d := _floor_point(theta0, r1)
				var n := DROME_SHAPE.normal((a.x + c.x) * 0.5, (a.z + c.z) * 0.5)
				_tri(st, a, b, c, white, n, uvz, uvz, uvz)
				_tri(st, a, c, d, white, n, uvz, uvz, uvz)
		# Flat goal-mouth floors beyond the elliptical rim.
		for side in [-1.0, 1.0]:
			var z0: float = side * ARENA_HALF_L
			var z1: float = side * GOAL_BACK_Z
			_quad(st, Vector3(-GOAL_HALF_W, 0.0, z0), Vector3(GOAL_HALF_W, 0.0, z0), Vector3(GOAL_HALF_W, 0.0, z1), Vector3(-GOAL_HALF_W, 0.0, z1), white, uvz, uvz, uvz, uvz)
		var mi := MeshInstance3D.new()
		mi.name = "IceFloor"
		mi.mesh = st.commit()
		mi.material_override = _mats["ice"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)

	func _floor_point(theta: float, radius: float) -> Vector3:
		var x := cos(theta) * ARENA_HALF_W * radius
		var z := sin(theta) * ARENA_HALF_L * radius
		return Vector3(x, DROME_SHAPE.height(x, z), z)

	func _build_boards() -> void:
		var n = _outline.size()
		for i in n:
			var a = _outline[i]
			var b = _outline[(i + 1) % n]
			if _in_goal_opening(a) and _in_goal_opening(b):
				continue
			var ha := DROME_SHAPE.height(a.x, a.z)
			var hb := DROME_SHAPE.height(b.x, b.z)
			var col = _team_for_z(a.z)
			var u0 = _outline_u[i]
			var u1 = _outline_u[(i + 1) % n]
			if maxf(ha, hb) > 0.20:
				# The ice itself forms the wall here: cap the bank with an energy rail.
				var aa := Vector3(a.x, ha + 0.055, a.z)
				var bb := Vector3(b.x, hb + 0.055, b.z)
				_prism(_glow_st, aa, bb, 0.085, 0.035, col * 0.72)
				var aa2 := Vector3(a.x, ha + 0.22, a.z)
				var bb2 := Vector3(b.x, hb + 0.22, b.z)
				_prism(_glow_st, aa2, bb2, 0.025, 0.020, col * 0.34)
			else:
				_quad(_boards_st, a, b, b + Vector3.UP * BOARD_H, a + Vector3.UP * BOARD_H, col, Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0))
				_prism(_glow_st, a + Vector3.UP * (BOARD_H + 0.035), b + Vector3.UP * (BOARD_H + 0.035), 0.09, 0.035, col * 0.7)
				_prism(_glow_st, a + Vector3.UP * 0.045, b + Vector3.UP * 0.045, 0.045, 0.028, col * 0.38)
		for side in [-1.0, 1.0]:
			var z = side * ARENA_HALF_L
			var col = _team_color(side)
			for sx in [-1.0, 1.0]:
				_box_uv(_boards_st, Vector3(sx * 4.75, 2.3, z), Vector3(0.28, 2.3, 0.34), col)
			_box_uv(_boards_st, Vector3(0.0, 3.55, z), Vector3(5.03, 1.0, 0.3), col)
			_prism(_glow_st, Vector3(-5.0, 2.55, z), Vector3(5.0, 2.55, z), 0.06, 0.06, col)
			_prism(_glow_st, Vector3(-5.0, 4.55, z), Vector3(5.0, 4.55, z), 0.07, 0.05, col)

	func _add_box_collider(body: StaticBody3D, center: Vector3, size: Vector3, yaw: float) -> void:
		var cs = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = center
		if absf(yaw) > 0.0001:
			cs.rotation = Vector3(0.0, yaw, 0.0)
		body.add_child(cs)

	func _build_board_colliders() -> void:
		var body = StaticBody3D.new()
		body.name = "BoardColliders"
		body.collision_layer = 1
		var z_len = 2.0 * (ARENA_HALF_L - CORNER_R)
		for sx in [-1.0, 1.0]:
			_add_box_collider(body, Vector3(sx * (ARENA_HALF_W + BOARD_THICK * 0.5), BOARD_H * 0.5, 0.0), Vector3(BOARD_THICK, BOARD_H, z_len), 0.0)
		var hx = ARENA_HALF_W - CORNER_R
		for sz in [-1.0, 1.0]:
			for sx in [-1.0, 1.0]:
				var x0 = 5.0 if sx > 0.0 else -hx
				var x1 = hx if sx > 0.0 else -5.0
				_add_box_collider(body, Vector3((x0 + x1) * 0.5, BOARD_H * 0.5, sz * (ARENA_HALF_L + BOARD_THICK * 0.5)), Vector3(x1 - x0, BOARD_H, BOARD_THICK), 0.0)
		var hz = ARENA_HALF_L - CORNER_R
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var cx = sx * hx
				var cz = sz * hz
				var start = 0.0
				if sx > 0.0 and sz > 0.0:
					start = 0.0
				elif sx < 0.0 and sz > 0.0:
					start = PI * 0.5
				elif sx < 0.0 and sz < 0.0:
					start = PI
				else:
					start = PI * 1.5
				for k in 4:
					var a0 = start + PI * 0.5 * float(k) / 4.0
					var a1 = start + PI * 0.5 * float(k + 1) / 4.0
					var mid = (a0 + a1) * 0.5
					var dir = Vector2(cos(mid), sin(mid))
					var pos = Vector3(cx + dir.x * (CORNER_R + BOARD_THICK * 0.5), BOARD_H * 0.5, cz + dir.y * (CORNER_R + BOARD_THICK * 0.5))
					var chord = 2.0 * CORNER_R * sin((a1 - a0) * 0.5) + 0.08
					var tangent = Vector2(-sin(mid), cos(mid))
					_add_box_collider(body, pos, Vector3(BOARD_THICK, BOARD_H, chord), atan2(tangent.x, tangent.y))
		_root.add_child(body)


# ---------------------------------------------------------------------------
# Stadium bowl (stands) + roof trusses
# ---------------------------------------------------------------------------

	func _bowl_profile() -> Array:
		return [
			Vector2(0.55, 0.9), Vector2(1.45, 0.9),
			Vector2(1.45, 1.55), Vector2(2.65, 1.55),
			Vector2(2.65, 2.2), Vector2(3.85, 2.2),
			Vector2(3.85, 2.85), Vector2(5.05, 2.85),
			Vector2(5.05, 3.5), Vector2(6.25, 3.5),
			Vector2(6.25, 4.15), Vector2(7.45, 4.15),
			Vector2(8.6, 4.15), Vector2(9.6, 6.6),
			Vector2(11.6, 10.6),
		]

	func _build_stands() -> void:
		var prof = _bowl_profile()
		var n = _outline.size()
		var uvz = Vector2.ZERO
		for k in prof.size() - 1:
			var p0: Vector2 = prof[k]
			var p1: Vector2 = prof[k + 1]
			var ra = _offset_ring(p0.x, p0.y)
			var rb = _offset_ring(p1.x, p1.y)
			for i in n:
				var j = (i + 1) % n
				_quad(_structure_st, ra[i], ra[j], rb[j], rb[i], Color.WHITE, uvz, uvz, uvz, uvz)
			if is_equal_approx(p0.y, p1.y) and p1.x > p0.x:
				var nose = _offset_ring(p1.x + 0.02, p0.y + 0.055)
				for i in range(0, n, 2):
					var j = (i + 2) % n
					_prism(_glow_st, nose[i], nose[j], 0.075, 0.03, _team_for_z(nose[i].z) * 0.42)
		var rim = _offset_ring(11.6, 10.6)
		for i in range(0, n, 2):
			var j = (i + 2) % n
			_prism(_glow_st, rim[i], rim[j], 0.13, 0.055, _team_for_z(rim[i].z) * 0.55)
		var rim2 = _offset_ring(11.35, 10.45)
		for i in range(0, n, 3):
			var j = (i + 3) % n
			_prism(_glow_st, rim2[i], rim2[j], 0.04, 0.03, _team_for_z(rim2[i].z) * 0.4)

	func _build_roof() -> void:
		for z in [-26.0, -13.0, 0.0, 13.0, 26.0]:
			var pts: Array[Vector3] = []
			for i in 13:
				var t = float(i) / 12.0
				pts.append(Vector3(-25.5 + 51.0 * t, 8.4 + 8.2 * sin(PI * t), z))
			var team = _team_for_z(z)
			for i in 12:
				_prism(_structure_st, pts[i], pts[i + 1], 0.18, 0.18, Color.WHITE)
				_prism(_glow_st, pts[i] + Vector3(0.0, -0.28, 0.0), pts[i + 1] + Vector3(0.0, -0.28, 0.0), 0.055, 0.04, team * 0.40)
		for x in [-13.0, 0.0, 13.0]:
			var y = 8.4 + 8.2 * sin(PI * (x + 25.5) / 51.0)
			var a = Vector3(x, y, -26.0)
			var b = Vector3(x, y, 26.0)
			_prism(_structure_st, a, b, 0.2, 0.2, Color.WHITE)
			_prism(_glow_st, a + Vector3(0.0, -0.3, 0.0), b + Vector3(0.0, -0.3, 0.0), 0.06, 0.045, _team_for_z(0.0) * 0.50)


# ---------------------------------------------------------------------------
# Infinite-seat holographic crowd (one MultiMesh = one draw call)
# ---------------------------------------------------------------------------

	func _build_crowd() -> void:
		var rows = [
			[0.95, 0.9], [2.0, 1.55], [3.2, 2.2], [4.4, 2.85], [5.6, 3.5], [6.8, 4.15],
		]
		var transforms: Array[Transform3D] = []
		var customs: Array[Color] = []
		var n = _crowd_outline.size()
		for row in rows:
			var offset: float = row[0]
			var y: float = row[1]
			for i in n:
				var p = _crowd_outline[i] + _crowd_normals[i] * offset + Vector3(0.0, y + 0.39, 0.0)
				if _in_goal_opening(p):
					continue
				var basis = Basis.looking_at(_crowd_normals[i], Vector3.UP)
				basis = Basis(Vector3.UP, _rng.randf_range(-0.16, 0.16)) * basis
				transforms.append(Transform3D(basis, p))
				var roll = _rng.randf()
				var team = COL_CYAN if p.z < 0.0 else COL_MAGENTA
				var col = team
				if roll < 0.10:
					col = COL_BONE
				elif roll < 0.18:
					col = COL_AMBER
				var lin = col.srgb_to_linear()
				var bright = _rng.randf_range(0.35, 1.0)
				customs.append(Color(lin.r * bright, lin.g * bright, lin.b * bright, _rng.randf()))
		var quad = QuadMesh.new()
		quad.size = Vector2(0.50, 0.78)
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
			mm.set_instance_custom_data(i, customs[i])
		var mmi = MultiMeshInstance3D.new()
		mmi.name = "Crowd"
		mmi.multimesh = mm
		mmi.material_override = _mats["crowd"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.set_meta("crowd_instances", transforms.size())
		_root.add_child(mmi)


# ---------------------------------------------------------------------------
# Jumbotron + holographic banners + labels
# ---------------------------------------------------------------------------

	func _build_jumbotron() -> void:
		var cy = 13.6
		var hx = 4.6
		var hy = 1.7
		var hz = 3.4
		_box(_structure_st, Vector3(0.0, cy, 0.0), Vector3(hx, hy, hz), Color.WHITE)
		_box(_structure_st, Vector3(0.0, cy + hy + 0.35, 0.0), Vector3(1.1, 0.32, 1.1), Color.WHITE)
		var sy = 1.36
		var sxw = 4.2
		var szw = 3.0
		var st = _new_st()
		var uv0 = Vector2(0.0, 1.0)
		var uv1 = Vector2(1.0, 1.0)
		var uv2 = Vector2(1.0, 0.0)
		var uv3 = Vector2(0.0, 0.0)
		var zf = hz + 0.02
		_quad(st, Vector3(-sxw, cy - sy, zf), Vector3(sxw, cy - sy, zf), Vector3(sxw, cy + sy, zf), Vector3(-sxw, cy + sy, zf), Color.WHITE, uv0, uv1, uv2, uv3)
		_quad(st, Vector3(sxw, cy - sy, -zf), Vector3(-sxw, cy - sy, -zf), Vector3(-sxw, cy + sy, -zf), Vector3(sxw, cy + sy, -zf), Color.WHITE, uv1, uv0, uv3, uv2)
		_quad(st, Vector3(hx + 0.02, cy - sy, szw), Vector3(hx + 0.02, cy - sy, -szw), Vector3(hx + 0.02, cy + sy, -szw), Vector3(hx + 0.02, cy + sy, szw), Color.WHITE, uv0, uv1, uv2, uv3)
		_quad(st, Vector3(-hx - 0.02, cy - sy, -szw), Vector3(-hx - 0.02, cy - sy, szw), Vector3(-hx - 0.02, cy + sy, szw), Vector3(-hx - 0.02, cy + sy, -szw), Color.WHITE, uv0, uv1, uv2, uv3)
		_commit_st(st, "JumbotronScreens", _mats["jumbo"], false)
		var trim = COL_BONE.srgb_to_linear() * 0.8
		for face_z in [-1.0, 1.0]:
			_prism(_glow_st, Vector3(-sxw, cy + sy + 0.03, face_z * (hz + 0.05)), Vector3(sxw, cy + sy + 0.03, face_z * (hz + 0.05)), 0.045, 0.045, trim)
			_prism(_glow_st, Vector3(-sxw, cy - sy - 0.03, face_z * (hz + 0.05)), Vector3(sxw, cy - sy - 0.03, face_z * (hz + 0.05)), 0.045, 0.045, trim)
		for face_x in [-1.0, 1.0]:
			_prism(_glow_st, Vector3(face_x * (hx + 0.05), cy + sy + 0.03, -szw), Vector3(face_x * (hx + 0.05), cy + sy + 0.03, szw), 0.045, 0.045, trim)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_prism(_structure_st, Vector3(sx * 3.9, cy + hy + 0.1, sz * 2.7), Vector3(sx * 0.8, 16.8, sz * 1.2), 0.05, 0.05, Color.WHITE)

	func _build_holo_banners() -> void:
		for sx in [-1.0, 1.0]:
			for z in [-18.0, 0.0, 18.0]:
				var pos = Vector3(sx * (ARENA_HALF_W + 10.05), 7.55, z)
				var inward = Vector3(-sx, 0.0, 0.0)
				var team = COL_CYAN if z < 0.0 else COL_MAGENTA
				_banner_quad(pos + inward * 0.10, Vector3(0.0, 0.0, 1.0), 5.2, 1.5, _lin(team))
		for sz in [-1.0, 1.0]:
			var pos = Vector3(0.0, 8.4, sz * (ARENA_HALF_L + 9.6))
			var inward = Vector3(0.0, 0.0, -sz)
			var team = COL_MAGENTA if sz > 0.0 else COL_CYAN
			_banner_quad(pos + inward * 0.10, Vector3(1.0, 0.0, 0.0), 7.4, 2.0, _lin(team))

	func _banner_quad(center: Vector3, right_dir: Vector3, width: float, height: float, col: Color) -> void:
		var r = right_dir.normalized() * (width * 0.5)
		var up = Vector3.UP * (height * 0.5)
		_quad(_holo_st, center - r - up, center + r - up, center + r + up, center - r + up, col, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))

	func _label(text: String, pos: Vector3, yaw: float, pixel: float, col: Color, outline: int) -> Label3D:
		var l = Label3D.new()
		l.text = text
		l.font_size = 96
		l.pixel_size = pixel
		l.modulate = col
		l.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
		l.outline_size = outline
		l.shaded = false
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.double_sided = false
		l.position = pos
		l.rotation = Vector3(0.0, yaw, 0.0)
		_root.add_child(l)
		return l


# ---------------------------------------------------------------------------
# Goals: hard-light nets, glowing frames, Area3D sensors, post colliders
# ---------------------------------------------------------------------------

	func _build_goals() -> void:
		_build_goal_areas()
		_build_goal_colliders()
		var uv0 = Vector2(0.0, 0.0)
		var uv1 = Vector2(1.0, 0.0)
		var uv2 = Vector2(1.0, 1.0)
		var uv3 = Vector2(0.0, 1.0)
		for side in [-1.0, 1.0]:
			var frame = _team_color(side)
			var z_line = side * ARENA_HALF_L
			var z_back = side * GOAL_BACK_Z
			_quad(_energy_st, Vector3(-GOAL_HALF_W, 0.0, z_back), Vector3(GOAL_HALF_W, 0.0, z_back), Vector3(GOAL_HALF_W, GOAL_HEIGHT, z_back), Vector3(-GOAL_HALF_W, GOAL_HEIGHT, z_back), frame, uv0, uv1, uv2, uv3)
			for sx in [-1.0, 1.0]:
				_quad(_energy_st, Vector3(sx * GOAL_HALF_W, 0.0, z_line), Vector3(sx * GOAL_HALF_W, 0.0, z_back), Vector3(sx * GOAL_HALF_W, GOAL_HEIGHT, z_back), Vector3(sx * GOAL_HALF_W, GOAL_HEIGHT, z_line), frame, uv0, uv1, uv2, uv3)
				_prism(_glow_st, Vector3(sx * GOAL_HALF_W, 0.0, z_line), Vector3(sx * GOAL_HALF_W, GOAL_HEIGHT, z_line), 0.075, 0.075, frame)
				_prism(_glow_st, Vector3(sx * GOAL_HALF_W, 0.0, z_back), Vector3(sx * GOAL_HALF_W, GOAL_HEIGHT, z_back), 0.06, 0.06, frame * 0.6)
				_prism(_glow_st, Vector3(sx * GOAL_HALF_W, GOAL_HEIGHT, z_line), Vector3(sx * GOAL_HALF_W, GOAL_HEIGHT, z_back), 0.05, 0.05, frame * 0.55)
			_prism(_glow_st, Vector3(-GOAL_HALF_W, GOAL_HEIGHT, z_line), Vector3(GOAL_HALF_W, GOAL_HEIGHT, z_line), 0.075, 0.075, frame)
			_prism(_glow_st, Vector3(-GOAL_HALF_W, GOAL_HEIGHT, z_back), Vector3(GOAL_HALF_W, GOAL_HEIGHT, z_back), 0.06, 0.06, frame * 0.6)
			_quad(_energy_st, Vector3(-GOAL_HALF_W, GOAL_HEIGHT, z_line), Vector3(GOAL_HALF_W, GOAL_HEIGHT, z_line), Vector3(GOAL_HALF_W, GOAL_HEIGHT, z_back), Vector3(-GOAL_HALF_W, GOAL_HEIGHT, z_back), frame, uv0, uv1, uv2, uv3)
		_label("ICE SAINTS", Vector3(0.0, 3.55, -ARENA_HALF_L + 0.36), 0.0, 0.0072, COL_BONE, 12)
		_label("REDLINE SYNDICATE", Vector3(0.0, 3.55, ARENA_HALF_L - 0.36), PI, 0.0058, COL_BONE, 12)
		_label("THE VAULT", Vector3(0.0, 8.5, -(ARENA_HALF_L + 9.3)), 0.0, 0.011, COL_BONE, 16)
		_label("THE VAULT", Vector3(0.0, 8.5, ARENA_HALF_L + 9.3), PI, 0.011, COL_BONE, 16)

	func _build_goal_areas() -> void:
		for side in [-1.0, 1.0]:
			var area = Area3D.new()
			area.name = "GoalBlue" if side < 0.0 else "GoalRed"
			area.position = Vector3(0.0, 0.0, side * 30.5)
			area.collision_layer = 1
			area.collision_mask = 0xFFFFF
			area.monitoring = true
			area.monitorable = true
			area.add_to_group("goal_blue" if side < 0.0 else "goal_red")
			area.set_meta("team", "blue" if side < 0.0 else "red")
			area.set_meta("goal_line_z", side * ARENA_HALF_L)
			area.set_meta("goal_back_z", side * GOAL_BACK_Z)
			var cs = CollisionShape3D.new()
			var box = BoxShape3D.new()
			box.size = Vector3(GOAL_HALF_W * 2.0, 2.6, 3.0)
			cs.shape = box
			cs.position = Vector3(0.0, 1.3, side * 1.0)
			area.add_child(cs)
			_root.add_child(area)
			if side < 0.0:
				_player_goal = area
			else:
				_enemy_goal = area

	func _build_goal_colliders() -> void:
		for side in [-1.0, 1.0]:
			var body = StaticBody3D.new()
			body.name = "GoalCollidersBlue" if side < 0.0 else "GoalCollidersRed"
			body.collision_layer = 1
			var z = side * ARENA_HALF_L
			for sx in [-1.0, 1.0]:
				_add_box_collider(body, Vector3(sx * 4.75, 2.3, z), Vector3(0.56, 4.6, 0.68), 0.0)
				_add_box_collider(body, Vector3(sx * GOAL_HALF_W, GOAL_HEIGHT * 0.5, z), Vector3(0.16, GOAL_HEIGHT, 0.16), 0.0)
			_add_box_collider(body, Vector3(0.0, GOAL_HEIGHT, z), Vector3(GOAL_HALF_W * 2.0 + 0.2, 0.16, 0.16), 0.0)
			_add_box_collider(body, Vector3(0.0, 1.3, side * GOAL_BACK_Z), Vector3(GOAL_HALF_W * 2.0 + 0.2, 2.6, 0.18), 0.0)
			for sx in [-1.0, 1.0]:
				_add_box_collider(body, Vector3(sx * GOAL_HALF_W, 1.3, side * (ARENA_HALF_L + GOAL_BACK_Z) * 0.5), Vector3(0.14, 2.6, GOAL_BACK_Z - ARENA_HALF_L), 0.0)
			_root.add_child(body)


# ---------------------------------------------------------------------------
# Boost strips, hazards (turnstiles + laser hurdles), killball charger
# ---------------------------------------------------------------------------

	func _build_boost_pads() -> void:
		var specs = [
			[-5.4, -14.0, 1.0, "blue"],
			[5.4, -14.0, 1.0, "blue"],
			[-5.4, 14.0, -1.0, "red"],
			[5.4, 14.0, -1.0, "red"],
		]
		for spec in specs:
			var x: float = spec[0]
			var z: float = spec[1]
			var dir: float = spec[2]
			var team_name: String = spec[3]
			var col = _lin(COL_CYAN if team_name == "blue" else COL_MAGENTA)
			var z0 = z - dir * 2.2
			var z1 = z + dir * 2.2
			_quad(_boost_st, Vector3(x - 1.3, 0.03, z0), Vector3(x + 1.3, 0.03, z0), Vector3(x + 1.3, 0.03, z1), Vector3(x - 1.3, 0.03, z1), col, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))
			var pad = BoostPad.new()
			pad.name = "BoostPad%s%d" % [team_name.capitalize(), _boost_pads.size()]
			pad.position = Vector3(x, 0.7, z)
			pad.team = team_name
			pad.boost_amount = 0.45
			pad.collision_layer = 1
			pad.collision_mask = 0xFFFFF
			pad.monitoring = true
			pad.monitorable = true
			var cs = CollisionShape3D.new()
			var box = BoxShape3D.new()
			box.size = Vector3(2.8, 1.4, 4.6)
			cs.shape = box
			pad.add_child(cs)
			pad.add_to_group("boost_pad")
			pad.set_meta("team", team_name)
			pad.set_meta("boost_amount", 0.45)
			_root.add_child(pad)
			_boost_pads.append(pad)

	func _build_hazards() -> void:
		var amber = _lin(COL_AMBER)
		for i in 2:
			var sx = -1.0 if i == 0 else 1.0
			var turnstile = Turnstile.new()
			turnstile.name = "TurnstileLeft" if sx < 0.0 else "TurnstileRight"
			var turn_y := DROME_SHAPE.height(sx * 7.5, 0.0)
			turnstile.position = Vector3(sx * 7.5, turn_y, 0.0)
			turnstile.spin_speed = 1.9 if sx < 0.0 else -1.9
			var arms = _new_st()
			for k in 3:
				var ang = TAU * float(k) / 3.0
				var dir = Vector3(cos(ang), 0.0, -sin(ang))
				var inner = dir * 0.42 + Vector3(0.0, 0.82, 0.0)
				var outer = dir * 2.2 + Vector3(0.0, 0.82, 0.0)
				_prism(arms, inner, outer, 0.07, 0.07, amber)
				_box(arms, outer, Vector3(0.13, 0.13, 0.13), amber)
			var pivot = Node3D.new()
			pivot.name = "Arms"
			var arm_mi = MeshInstance3D.new()
			arm_mi.mesh = arms.commit()
			arm_mi.material_override = _mats["glow"]
			arm_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(arm_mi)
			turnstile.add_child(pivot)
			turnstile.arm_pivot = pivot
			var ring_st = _new_st()
			_annulus(ring_st, Vector3(0.0, 0.04, 0.0), 2.45, 2.8, 40, Color.WHITE, true)
			var ring_mi = MeshInstance3D.new()
			ring_mi.name = "DangerRing"
			ring_mi.mesh = ring_st.commit()
			ring_mi.material_override = _mats["hazard_ring"]
			ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			turnstile.add_child(ring_mi)
			_prism(_glow_st, Vector3(sx * 7.5, 0.0, 0.0), Vector3(sx * 7.5, 1.25, 0.0), 0.16, 0.16, amber)
			var body = StaticBody3D.new()
			body.name = "Pylon"
			body.collision_layer = 1
			var cs = CollisionShape3D.new()
			var cyl = CylinderShape3D.new()
			cyl.radius = 0.32
			cyl.height = 1.3
			cs.shape = cyl
			cs.position = Vector3(0.0, 0.65, 0.0)
			body.add_child(cs)
			turnstile.add_child(body)
			_root.add_child(turnstile)
			_hazards.append(turnstile)
		for idx in 2:
			var lz = -9.0 if idx == 0 else 9.0
			var laser = LaserStrip.new()
			laser.name = "LaserStrip%d" % idx
			laser.position = Vector3(0.0, 0.0, lz)
			laser.phase = float(idx) * 1.7
			var mat = _mats["laser"].duplicate() as ShaderMaterial
			laser.material = mat
			var beam_st = _new_st()
			_quad(beam_st, Vector3(-5.8, 0.045, -0.36), Vector3(5.8, 0.045, -0.36), Vector3(5.8, 0.045, 0.36), Vector3(-5.8, 0.045, 0.36), Color.WHITE, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))
			_quad(beam_st, Vector3(-5.8, 0.16, 0.0), Vector3(5.8, 0.16, 0.0), Vector3(5.8, 0.92, 0.0), Vector3(-5.8, 0.92, 0.0), Color.WHITE, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))
			var beam_mi = MeshInstance3D.new()
			beam_mi.name = "Beam"
			beam_mi.mesh = beam_st.commit()
			beam_mi.material_override = mat
			beam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			laser.add_child(beam_mi)
			laser.beam = beam_mi
			for sx in [-1.0, 1.0]:
				_prism(_glow_st, Vector3(sx * 6.3, 0.05, lz), Vector3(sx * 6.3, 1.0, lz), 0.09, 0.09, amber)
				var emitter = StaticBody3D.new()
				emitter.name = "Emitter"
				emitter.collision_layer = 1
				var ecs = CollisionShape3D.new()
				var ebox = BoxShape3D.new()
				ebox.size = Vector3(0.24, 1.0, 0.24)
				ecs.shape = ebox
				ecs.position = Vector3(sx * 6.3, 0.5, 0.0)
				emitter.add_child(ecs)
				laser.add_child(emitter)
			_root.add_child(laser)
			_hazards.append(laser)

	func _build_charger() -> void:
		var area = Area3D.new()
		area.name = "KillballCharger"
		area.position = Vector3(0.0, 1.1, 0.0)
		area.collision_layer = 1
		area.collision_mask = 0xFFFFF
		area.monitoring = true
		area.monitorable = true
		area.add_to_group("killball_charger")
		area.set_meta("team", "neutral")
		area.set_meta("charge_time", 0.8)
		var cs = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(3.4, 2.2, 3.4)
		cs.shape = box
		area.add_child(cs)
		_root.add_child(area)
		_killball_charger = area
		var amber = _lin(COL_AMBER)
		for k in 3:
			var ang = TAU * float(k) / 3.0 + 0.3
			var pos = Vector3(cos(ang) * 2.35, 0.0, sin(ang) * 2.35)
			_prism(_glow_st, pos, pos + Vector3(0.0, 1.5, 0.0), 0.09, 0.09, amber * 0.85)
			_prism(_glow_st, pos + Vector3(0.0, 1.5, 0.0), pos + Vector3(0.0, 1.62, 0.0), 0.16, 0.16, amber)
		for i in 2:
			var ring_st = _new_st()
			_annulus(ring_st, Vector3.ZERO, 1.45 if i == 0 else 1.0, 1.62 if i == 0 else 1.12, 40, Color.WHITE, true)
			var ring_mi = MeshInstance3D.new()
			ring_mi.name = "ChargerRingMesh"
			ring_mi.mesh = ring_st.commit()
			ring_mi.material_override = _mats["hazard_ring"]
			ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var spin = RingSpin.new()
			spin.name = "ChargerRing%d" % i
			spin.speed = 0.8 if i == 0 else -1.1
			spin.position = Vector3(0.0, 0.95 if i == 0 else 1.62, 0.0)
			spin.add_child(ring_mi)
			_root.add_child(spin)


# ---------------------------------------------------------------------------
# Banner drones, ice mist, spawns, lighting + environment
# ---------------------------------------------------------------------------

	func _build_drones() -> void:
		var spots = [
			[Vector3(-19.0, 9.2, -19.0), COL_CYAN],
			[Vector3(19.0, 9.2, -19.0), COL_CYAN],
			[Vector3(-19.0, 9.2, 19.0), COL_MAGENTA],
			[Vector3(19.0, 9.2, 19.0), COL_MAGENTA],
		]
		for i in spots.size():
			var spec: Array = spots[i]
			var pos: Vector3 = spec[0]
			var team: Color = spec[1]
			var drone = Drone.new()
			drone.name = "BannerDrone%d" % i
			drone.position = pos
			drone.base_y = pos.y
			drone.phase = float(i) * 1.7
			var ring_st = _new_st()
			_annulus(ring_st, Vector3.ZERO, 0.52, 0.62, 32, _lin(team), false)
			var ring_mi = MeshInstance3D.new()
			ring_mi.mesh = ring_st.commit()
			ring_mi.material_override = _mats["glow"]
			ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			drone.add_child(ring_mi)
			var banner_st = _new_st()
			_quad(banner_st, Vector3(-1.1, -1.1, 0.0), Vector3(1.1, -1.1, 0.0), Vector3(1.1, -0.45, 0.0), Vector3(-1.1, -0.45, 0.0), _lin(COL_BONE), Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))
			var banner_mi = MeshInstance3D.new()
			banner_mi.mesh = banner_st.commit()
			banner_mi.material_override = _mats["holo"]
			banner_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			drone.add_child(banner_mi)
			_root.add_child(drone)

	func _build_particles() -> void:
		_root.add_child(_particle_system("IceMist", 28, Vector3(0.0, 0.35, 0.0), Vector3(15.0, 0.2, 29.0), Color(0.25, 0.60, 0.85, 0.12), 9.0, 0.05))
		_root.add_child(_particle_system("ChargerMotes", 14, Vector3(0.0, 0.4, 0.0), Vector3(2.4, 0.2, 2.4), Color(1.0, 0.66, 0.15, 0.30), 4.5, 0.14))

	func _particle_system(node_name: String, amount: int, pos: Vector3, extents: Vector3, tint: Color, lifetime: float, rise: float) -> GPUParticles3D:
		var p = GPUParticles3D.new()
		p.name = node_name
		p.amount = amount
		p.lifetime = lifetime
		p.preprocess = 3.0
		p.position = pos
		p.visibility_aabb = AABB(Vector3(-22.0, -2.0, -36.0), Vector3(44.0, 8.0, 72.0))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm = ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = extents
		pm.direction = Vector3(0.0, 1.0, 0.0)
		pm.spread = 35.0
		pm.initial_velocity_min = 0.02
		pm.initial_velocity_max = rise
		pm.gravity = Vector3(0.0, 0.01, 0.0)
		pm.scale_min = 0.35
		pm.scale_max = 1.25
		pm.color = tint
		p.process_material = pm
		var quad = QuadMesh.new()
		quad.size = Vector2(1.5, 1.5)
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = _soft_disc_texture()
		mat.disable_receive_shadows = true
		quad.material = mat
		p.draw_pass_1 = quad
		return p

	func _soft_disc_texture() -> Texture2D:
		var grad = Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		var tex = GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		return tex

	func _build_spawns() -> void:
		var blue_basis = Basis(Vector3.UP, PI)
		var red_basis = Basis.IDENTITY
		for p in [Vector3(0.0, 0.0, -19.0), Vector3(-7.5, 0.0, -16.5), Vector3(7.5, 0.0, -16.5)]:
			_spawn_blue.append(Transform3D(blue_basis, p))
		_spawn_blue.append(Transform3D(blue_basis, Vector3(0.0, 0.0, -27.0)))
		for p in [Vector3(0.0, 0.0, 19.0), Vector3(-7.5, 0.0, 16.5), Vector3(7.5, 0.0, 16.5)]:
			_spawn_red.append(Transform3D(red_basis, p))
		_spawn_red.append(Transform3D(red_basis, Vector3(0.0, 0.0, 27.0)))
		_center_spawn = Transform3D(red_basis, Vector3.ZERO)

	func _build_lighting() -> void:
		if not _has_environment(_parent):
			var we = WorldEnvironment.new()
			we.name = "ArenaEnvironment"
			we.environment = _make_environment()
			_root.add_child(we)
		var key = DirectionalLight3D.new()
		key.name = "KeyLight"
		key.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
		key.light_color = Color(0.82, 0.90, 1.0)
		key.light_energy = 1.45
		key.shadow_enabled = true
		key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		key.directional_shadow_max_distance = 90.0
		_root.add_child(key)
		var pools = [
			[Vector3(-8.5, 7.5, -19.0), COL_CYAN, 2.1, 26.0],
			[Vector3(8.5, 7.5, -19.0), COL_CYAN, 1.7, 24.0],
			[Vector3(-8.5, 7.5, 19.0), COL_MAGENTA, 2.1, 26.0],
			[Vector3(8.5, 7.5, 19.0), COL_MAGENTA, 1.7, 24.0],
			[Vector3(0.0, 5.0, 0.0), COL_AMBER, 2.6, 15.0],
		]
		for pool in pools:
			var omni = OmniLight3D.new()
			omni.position = pool[0]
			omni.light_color = pool[1]
			omni.light_energy = pool[2]
			omni.omni_range = pool[3]
			omni.shadow_enabled = false
			omni.light_specular = 0.5
			_root.add_child(omni)
		for side in [-1.0, 1.0]:
			var spot = SpotLight3D.new()
			spot.name = "GoalSpotBlue" if side < 0.0 else "GoalSpotRed"
			spot.position = Vector3(0.0, 8.5, side * 24.0)
			spot.basis = Basis.looking_at(Vector3(0.0, 0.5, side * ARENA_HALF_L) - spot.position, Vector3.UP)
			spot.light_color = COL_CYAN if side < 0.0 else COL_MAGENTA
			spot.light_energy = 5.5
			spot.spot_range = 26.0
			spot.spot_angle = 38.0
			spot.spot_angle_attenuation = 1.2
			spot.shadow_enabled = false
			_root.add_child(spot)
		var rim_left = OmniLight3D.new()
		rim_left.position = Vector3(-23.0, 8.0, 0.0)
		rim_left.light_color = COL_CYAN
		rim_left.light_energy = 1.6
		rim_left.omni_range = 34.0
		rim_left.shadow_enabled = false
		_root.add_child(rim_left)
		var rim_right = OmniLight3D.new()
		rim_right.position = Vector3(23.0, 8.0, 0.0)
		rim_right.light_color = COL_MAGENTA
		rim_right.light_energy = 1.6
		rim_right.omni_range = 34.0
		rim_right.shadow_enabled = false
		_root.add_child(rim_right)

	func _has_environment(node: Node) -> bool:
		var current: Node = node
		while current != null:
			for child in current.get_children():
				if child is WorldEnvironment:
					return true
			current = current.get_parent()
		return false

	func _make_environment() -> Environment:
		var env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.004, 0.006, 0.014)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.17, 0.24, 0.34)
		env.ambient_light_energy = 0.55
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.05
		env.tonemap_white = 6.0
		env.glow_enabled = true
		env.glow_intensity = 0.85
		env.glow_strength = 1.05
		env.glow_bloom = 0.18
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_hdr_threshold = 1.05
		env.glow_hdr_scale = 1.30
		env.fog_enabled = true
		env.fog_light_color = Color(0.015, 0.03, 0.06)
		env.fog_light_energy = 0.6
		env.fog_density = 0.004
		env.fog_sun_scatter = 0.0
		env.fog_height = 0.6
		env.fog_height_density = 0.15
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.06
		env.adjustment_saturation = 1.15
		return env
