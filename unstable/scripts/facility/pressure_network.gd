class_name PressureNetwork
extends Node
## Facility coolant pressure, 0–100%. It builds up on its own, and faster as
## the facility destabilises. Consumers spend it: the gate jack (Gate) and the
## drain pump (DrainPump). If it is held at 100% for `burst_delay` seconds, a line
## bursts and floods `burst_zone`.

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

var pressure := 40.0
var burst_timer := 0.0
var mission: Mission
var _overpressure := 0.0
var _warned := false


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	pressure = start_pressure


## Take `amount` pressure out of the network (consumers call this).
func spend(amount: float) -> void:
	pressure = maxf(0.0, pressure - amount)


func _physics_process(delta: float) -> void:
	if burst_vent:
		burst_vent.emitting = burst_timer > 0.0
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

	if pressure > warning_level and not _warned:
		_warned = true
		mission.incident_log.broadcast("OVERPRESSURE — open the drain pump or a line will burst", "warn")
	elif pressure < warning_level - 10.0:
		_warned = false

	if burst_timer > 0.0:
		burst_timer -= delta
		if burst_zone:
			burst_zone.add_water(burst_flow * delta)


func _burst() -> void:
	_overpressure = 0.0
	pressure = pressure_after_burst
	burst_timer = burst_duration
	mission.incident_log.incident("Pressure line BURST — the main hall is flooding")


func net_get() -> Array:
	return [pressure, burst_timer]


func net_set(s: Array) -> void:
	pressure = s[0]
	burst_timer = s[1]
