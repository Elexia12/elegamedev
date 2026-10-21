class_name DepositZone
extends Node3D
## Where salvage is handed over. Leave a piece of salvage (role salvage,
## primary or optional) inside the zone, nearly still, for `settle_time`
## seconds and it's secured, exactly once: its value at that moment is locked
## in, it can't be damaged any more, and it's loaded onto the truck bed (the
## next TruckBed marker). Depositing secures value; only departing ends the run.

signal secured(prop: Prop)

## Footprint (X, Z) centred on this node, and how high above it counts.
@export var size := Vector3(6.0, 3.0, 7.0)
@export var settle_time := 1.0
## Faster than this (m/s) doesn't count as "left here".
@export var max_speed := 0.6
## Markers on the truck bed where secured salvage is loaded, in order.
@export var truck_bed: Node3D

## Host: seconds each prop has been sitting in the zone.
var _timers := {}
var _loaded := 0
## Replicated: what's being loaded right now, and how far along.
var loading_name := ""
var loading := 0.0
var mission: Mission

@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)


func contains(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= size.x / 2.0 and absf(l.z) <= size.z / 2.0 and l.y >= -0.5 and l.y <= size.y


func _physics_process(delta: float) -> void:
	if mission and multiplayer.is_server() and mission.running():
		_simulate(delta)
	if loading_name != "":
		label.text = "DEPOSIT ZONE\nLOADING %s… %d%%" % [loading_name.to_upper(), roundi(loading * 100.0)]
	else:
		label.text = "DEPOSIT ZONE\nleave salvage here · it goes on the truck"


func _simulate(delta: float) -> void:
	loading_name = ""
	loading = 0.0
	for p in mission.props():
		if not p.is_salvage() or p.is_locked() or p.dormant:
			continue
		if contains(p.global_position) and p.linear_velocity.length() < max_speed:
			_timers[p] = _timers.get(p, 0.0) + delta
			if _timers[p] > loading:
				loading = _timers[p] / settle_time
				loading_name = p.display_name
			if _timers[p] >= settle_time:
				_timers.erase(p)
				_secure(p)
		else:
			_timers.erase(p)


func _secure(p: Prop) -> void:
	var where := Transform3D(Basis(), global_position + Vector3.UP * 2.0)
	if truck_bed and truck_bed.get_child_count() > 0:
		var markers := truck_bed.get_children()
		var m := markers[mini(_loaded, markers.size() - 1)] as Node3D
		var stack := maxi(0, _loaded - markers.size() + 1)
		where = Transform3D(m.global_basis, m.global_position + Vector3.UP * (p.height / 2.0 + stack * 0.8))
	_loaded += 1
	p.lock_secured(where)
	secured.emit(p)


func net_get() -> Array:
	return [loading_name, loading]


func net_set(s: Array) -> void:
	loading_name = s[0]
	loading = s[1]
