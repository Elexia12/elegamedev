class_name WaterMain
extends Node
## The station's water supply. Through the open `valve` it pours `inlet_flow`
## into `zone` (the maintenance pit) via the Inlet gush, plus `leak_flow` for
## every ruptured PipeRun (group "water_pipes"). Crank the valve shut and both
## stop; only the zone's own seepage remains.

@export var zone: FloodZone
@export var valve: Valve
## Flood level per second at 100% open.
@export var inlet_flow := 0.004
@export var inlet_gush: CPUParticles3D
## The inlet's rushing water (louder the wider the valve is open).
@export var inlet_sound: LoopSound

var mission: Mission


func _ready() -> void:
	mission = Mission.of(self)


func pipes() -> Array[PipeRun]:
	var out: Array[PipeRun] = []
	for p in get_tree().get_nodes_in_group("water_pipes"):
		if p is PipeRun and mission.is_ancestor_of(p):
			out.append(p)
	return out


## Current inflow (level per second).
func flow() -> float:
	var f := inlet_flow
	for p in pipes():
		if p.ruptured:
			f += p.leak_flow
	return f * valve.opening


func _physics_process(delta: float) -> void:
	var open := valve.opening
	if inlet_gush:
		inlet_gush.emitting = open > 0.03
		inlet_gush.initial_velocity_max = 1.0 + open * 4.0
	if inlet_sound:
		inlet_sound.level = open
	for p in pipes():
		p.pressure = open
	if multiplayer.is_server() and mission.running():
		zone.add_water(flow() * delta)
