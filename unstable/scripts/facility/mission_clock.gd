class_name MissionClock
extends Node
## Mission timer and escalation. Instability rises from 0 to 1 over
## `collapse_time` and every hazard scales with it. Phases are named bands of
## instability. When time runs out the facility collapses.

signal phase_changed(phase: int, phase_name: String)
signal collapsed

const PHASE_NAMES := ["ASSESS", "RECOVERY", "ESCALATION", "COLLAPSE IMMINENT"]

## Seconds until the facility collapses (GDD target run: 15–20 min; shorter here).
@export var collapse_time := 720.0
## Instability at which RECOVERY, ESCALATION and COLLAPSE IMMINENT begin.
@export var phase_starts := PackedFloat32Array([0.15, 0.45, 0.8])

var elapsed := 0.0
var running := true
var _phase := 0


func _ready() -> void:
	add_to_group("net")
	# Tick before everything that reads instability this frame.
	process_physics_priority = -10


func instability() -> float:
	return clampf(elapsed / collapse_time, 0.0, 1.0)


func phase() -> int:
	var p := 0
	for start in phase_starts:
		if instability() >= start:
			p += 1
	return p


func phase_name() -> String:
	return PHASE_NAMES[phase()]


func time_left() -> float:
	return maxf(0.0, collapse_time - elapsed)


## "mm:ss"
static func format(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


func stamp() -> String:
	return format(elapsed)


func _physics_process(delta: float) -> void:
	if not running or not multiplayer.is_server():
		return
	elapsed += delta
	var p := phase()
	if p != _phase:
		_phase = p
		phase_changed.emit(p, PHASE_NAMES[p])
	if elapsed >= collapse_time:
		running = false
		collapsed.emit()


func net_get() -> Array:
	return [elapsed, running]


func net_set(s: Array) -> void:
	elapsed = s[0]
	running = s[1]
