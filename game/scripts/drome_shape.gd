class_name DromeShape
extends RefCounted

## ULTRABLADE's elliptical drome cross-section.
##
## The original HyperBlade drome is a curved bowl, not a flat rink. This module is the
## single source of truth for the playable surface: the arena mesh, skaters, puck,
## hazards and the camera all use it. The centre lane stays flat for goals; the sides
## sweep up into steep skateable banks like a half-pipe.

const HALF_WIDTH := 16.0
const HALF_LENGTH := 30.0
const GOAL_LANE_HALF := 4.6
const BANK_START := 6.6
const BANK_END := 15.8
const BANK_HEIGHT := 4.2
const BANK_POWER := 1.0

static func smoothstep01(t: float) -> float:
	var v := clampf(t, 0.0, 1.0)
	return v * v * (3.0 - 2.0 * v)

static func height(x: float, z: float) -> float:
	if absf(x) <= BANK_START:
		return 0.0
	var t := clampf((absf(x) - BANK_START) / maxf(BANK_END - BANK_START, 0.001), 0.0, 1.0)
	# Smooth ramp into a steep wall near the boards.
	var curve := smoothstep01(t)
	return BANK_HEIGHT * pow(curve, BANK_POWER)

static func normal(x: float, z: float) -> Vector3:
	var e := 0.08
	var hx := (height(x + e, z) - height(x - e, z)) / (2.0 * e)
	var hz := (height(x, z + e) - height(x, z - e)) / (2.0 * e)
	return Vector3(-hx, 1.0, -hz).normalized()

static func radius_at(x: float, z: float) -> float:
	var nx := x / HALF_WIDTH
	var nz := z / HALF_LENGTH
	return nx * nx + nz * nz

static func is_inside(x: float, z: float, margin: float = 0.0) -> bool:
	var hw := maxf(HALF_WIDTH - margin, 0.1)
	var hl := maxf(HALF_LENGTH - margin, 0.1)
	var nx := x / hw
	var nz := z / hl
	return nx * nx + nz * nz <= 1.0

static func surface_point(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)

## Bank height at the outer boards, used for rail/rim visuals.
static func edge_height(z: float) -> float:
	return height(HALF_WIDTH, z)
