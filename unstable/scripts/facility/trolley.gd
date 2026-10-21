class_name Trolley
extends Prop
## Wheeled transport trolley: grab the Handle ([E]) and push. A controlled
## rolling approximation rather than simulated wheels: the body slides on
## frictionless wheel spheres, the fixed axle at the far end (FrontAxle)
## grips sideways like real fixed wheels, and the handle end swivels, so you
## steer by swinging the handle.
## Cargo on the deck (CargoArea) is held by deck friction, applied here: push
## or turn harder than `deck_friction` × g and the motor slides, or tips off.
## Not strapped down (straps are a later tool).

## Sideways grip of the fixed axle (1/s). Higher = tracks straighter.
@export var grip := 7.0
## Rolling resistance (1/s of speed).
@export var rolling_resistance := 0.35
## Friction coefficient between the deck and cargo.
@export var deck_friction := 0.45

@onready var cargo_area: Area3D = $CargoArea
@onready var front_axle: Marker3D = $FrontAxle


func cargo() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for b in cargo_area.get_overlapping_bodies():
		if b is RigidBody3D and b != self and not b.freeze:
			out.append(b)
	return out


func cargo_mass() -> float:
	var m := 0.0
	for b in cargo():
		m += b.mass
	return m


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if mission == null or not multiplayer.is_server() or freeze:
		return
	var total := mass + cargo_mass()
	# Fixed axle: kill sideways slip at the far end.
	var axle := front_axle.global_position
	var side := global_basis.x
	var slip := point_velocity(axle).dot(side)
	apply_force(-side * slip * total * grip, axle - global_position)
	# Rolling resistance (horizontal only).
	var v := linear_velocity * Vector3(1, 0, 1)
	apply_central_force(-v * total * rolling_resistance)
	# Deck friction on cargo, and its reaction on the trolley.
	for b in cargo():
		var rel := (b.linear_velocity - point_velocity(b.global_position)) * Vector3(1, 0, 1)
		var f := (-rel * b.mass * 10.0).limit_length(deck_friction * b.mass * 9.8)
		b.apply_central_force(f)
		apply_force(-f, b.global_position - global_position)


func _label_text() -> String:
	var names: Array[String] = []
	for b in cargo_area.get_overlapping_bodies():
		if b is Prop and b != self and b.is_salvage():
			names.append(b.display_name)
	return "TROLLEY" + ("\ncarrying: " + ", ".join(names) if not names.is_empty() else "\n[E] grab the handle and push")
