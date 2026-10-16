class_name PressureNetwork
extends Node
## Facility coolant pressure, 0–100%. It builds up on its own, and faster as
## the facility destabilises. Consumers spend it: the gate jack (Gate) and the
## drain pump (DrainPump). You can see and feel it climbing: above
## `warning_level` the pipes rattle and the vent spits steam. Held at 100%, the
## line BURSTS. A water jet blasts out of the vent and knocks crew and cargo
## across the hall while `burst_zone` floods.

@export var start_pressure := 40.0
## Pressure gained per second at zero / full instability.
@export var rise := 0.12
@export var rise_unstable := 0.55
@export var warning_level := 85.0
@export_group("Burst")
@export var burst_delay := 3.0
@export var pressure_after_burst := 45.0
@export var burst_duration := 25.0
## Water level added to `burst_zone` per second while the line gushes.
@export var burst_flow := 0.02
@export var burst_zone: FloodZone
@export var burst_vent: CPUParticles3D
## Pipes that rattle as pressure climbs.
@export var rattle: Node3D
@export_group("Water jet")
## Push (m/s² of acceleration) at the vent, fading to zero at `jet_length`.
@export var jet_strength := 35.0
@export var jet_length := 10.0
@export var jet_radius := 1.8

var pressure := 40.0
var burst_timer := 0.0
var mission: Mission
var _overpressure := 0.0
var _rattle_home := Vector3.ZERO


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	pressure = start_pressure
	if rattle:
		_rattle_home = rattle.position


## Take `amount` pressure out of the network (consumers call this).
func spend(amount: float) -> void:
	pressure = maxf(0.0, pressure - amount)


## Acceleration the burst jet applies at `p` (zero when not bursting).
func jet_push_at(p: Vector3) -> Vector3:
	if burst_timer <= 0.0 or burst_vent == null:
		return Vector3.ZERO
	var origin := burst_vent.global_position
	var dir := (burst_vent.global_basis * burst_vent.direction).normalized()
	var t := (p - origin).dot(dir)
	if t < 0.0 or t > jet_length:
		return Vector3.ZERO
	if (p - (origin + dir * t)).length() > jet_radius:
		return Vector3.ZERO
	return dir * jet_strength * (1.0 - t / jet_length)


func _physics_process(delta: float) -> void:
	_update_effects()
	if not multiplayer.is_server() or not mission.running():
		return
	pressure += (rise + rise_unstable * mission.clock.instability()) * delta
	if pressure >= 100.0:
		_overpressure += delta
		if _overpressure >= burst_delay:
			_burst()
	else:
		_overpressure = 0.0
	pressure = clampf(pressure, 0.0, 100.0)
	if burst_timer > 0.0:
		burst_timer -= delta
		if burst_zone:
			burst_zone.add_water(burst_flow * delta)


func _burst() -> void:
	_overpressure = 0.0
	pressure = pressure_after_burst
	burst_timer = burst_duration
	mission.incident_log.incident("Pressure line burst")
	mission.tremors.jolt(0.7)


func _update_effects() -> void:
	var over := clampf((pressure - warning_level) / (100.0 - warning_level), 0.0, 1.0)
	if burst_vent:
		burst_vent.emitting = burst_timer > 0.0 or over > 0.0
		burst_vent.initial_velocity_min = 6.0 if burst_timer > 0.0 else 1.0
		burst_vent.initial_velocity_max = 10.0 if burst_timer > 0.0 else 2.5
	if rattle:
		var r := over * 0.04 + (0.03 if burst_timer > 0.0 else 0.0)
		rattle.position = _rattle_home + Vector3(randf_range(-r, r), randf_range(-r, r), randf_range(-r, r))


func net_get() -> Array:
	return [pressure, burst_timer]


func net_set(s: Array) -> void:
	pressure = s[0]
	burst_timer = s[1]
