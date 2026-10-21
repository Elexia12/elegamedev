class_name PipeRun
extends StaticBody3D
## A run of water-main pipe. Solid, and fragile: a heavy prop hitting it hard
## enough (impact impulse above `rupture_impulse`, e.g. a swinging pump motor)
## ruptures it where it was hit. A ruptured pipe sprays water (Spray) and the
## WaterMain that feeds it pours `leak_flow` into its flood zone, until the
## main's valve is shut.

@export var display_name := "Water main"
## kg·m/s. The 450 kg motor swinging into it at ~0.8 m/s is enough.
@export var rupture_impulse := 350.0
## Extra flood level per second while ruptured and fed at 100%.
@export var leak_flow := 0.006

var ruptured := false
## Fed share (0..1), set by the WaterMain each frame.
var pressure := 1.0
var mission: Mission
var _spray_at := Vector3.ZERO

@onready var spray: CPUParticles3D = $Spray
@onready var mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group("net")
	add_to_group("water_pipes")
	mission = Mission.of(self)
	spray.emitting = false
	spray.top_level = true


## Called by a Prop that hit this pipe.
func take_hit(by: Prop, impulse: float) -> void:
	if ruptured or impulse < rupture_impulse or not multiplayer.is_server():
		return
	ruptured = true
	_spray_at = by.global_position
	mission.incident_log.incident("The %s hit the %s and ruptured it" % [by.display_name.to_lower(), display_name.to_lower()])
	mission.incident_log.broadcast("A water main burst in the pump hall! The inlet valve in the pit shuts it off.", "alert")
	mission.tremors.jolt(0.3)


func _process(_delta: float) -> void:
	if not ruptured:
		return
	# Spray from the point on the pipe closest to where it was hit.
	var local := to_local(_spray_at)
	var axis_len := (mesh.mesh as CylinderMesh).height if mesh.mesh is CylinderMesh else 0.0
	local = Vector3(0.0, clampf(local.y, -axis_len / 2.0, axis_len / 2.0), 0.0) if axis_len > 0.0 else Vector3.ZERO
	spray.global_position = to_global(local)
	spray.emitting = pressure > 0.05
	spray.initial_velocity_max = 2.0 + pressure * 7.0


func net_get() -> Array:
	return [ruptured, _spray_at, pressure]


func net_set(s: Array) -> void:
	ruptured = s[0]
	_spray_at = s[1]
	pressure = s[2]
