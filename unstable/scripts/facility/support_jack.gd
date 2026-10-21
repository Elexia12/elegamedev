class_name SupportJack
extends Prop
## Portable support jack. Carry it ([E]), stand it upright ([R] while
## carrying) inside a JackPoint, let go, then [E] on it to extend the Ram up
## to the structure. Installed, it's fixed in place and holds the structure
## up. [E] again retracts it. A big impact on what it holds can make it slip:
## it springs loose and falls over.

## The jack must stand within this angle of vertical to extend (radians).
@export var max_tilt := 0.5

var installed := false

@onready var ram: Node3D = $Ram


func _ready() -> void:
	super._ready()
	# Jolt areas don't see static-frozen bodies: freeze kinematic so the
	# JackPoint (and the corridor) still see an installed jack.
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


## The JackPoint this jack is standing in, if any.
func jack_point_here() -> JackPoint:
	for jp in get_tree().get_nodes_in_group("jack_points"):
		if jp is JackPoint and mission.is_ancestor_of(jp) and jp.overlaps_body(self):
			return jp
	return null


func is_upright() -> bool:
	return global_basis.y.angle_to(Vector3.UP) < max_tilt


func is_grabbable() -> bool:
	return super.is_grabbable() and not installed


## What [E] does to this jack ("" = just grab it).
func use_prompt(_crew: CrewMember) -> String:
	if installed:
		return "[E] retract the support jack (it's holding the corridor up)"
	if jack_point_here() and is_upright() and linear_velocity.length() < 0.5:
		return "[E] extend the support jack"
	return ""


func use(_player: CrewMember, _target: Node) -> String:
	if installed:
		installed = false
		freeze = false
		sleeping = false
		return "Jack retracted"
	var jp := jack_point_here()
	if jp == null or not is_upright():
		return "Stand the jack upright on a jack point first ([R] while carrying turns it upright)"
	installed = true
	freeze = true
	# Square it up on the point so the ram meets the structure.
	global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), Vector3(jp.global_position.x, global_position.y, jp.global_position.z))
	mission.incident_log.incident("Support jack installed")
	return "Jack extended — it's holding the structure up"


## Host: knocked loose by an impact.
func slip() -> void:
	if not installed:
		return
	installed = false
	freeze = false
	sleeping = false
	apply_impulse(Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1)).normalized() * mass * 2.5, global_basis.y * 0.5)
	mission.incident_log.incident("The support jack slipped")


func _process(delta: float) -> void:
	super._process(delta)
	var jp := jack_point_here() if installed else null
	var reach := jp.ram_height if jp else 0.05
	ram.scale.y = lerpf(ram.scale.y, maxf(reach, 0.05), 1.0 - exp(-6.0 * delta))
	ram.position.y = height / 2.0 + ram.scale.y / 2.0
	if installed:
		note = "EXTENDED · holding the corridor"
	elif jack_point_here():
		note = "on the jack point · %s" % ("[E] extend" if is_upright() else "stand it upright ([R] while carrying)")
	else:
		note = "stand it on a jack point"


func net_get() -> Array:
	return super.net_get() + [installed]


func net_set(s: Array) -> void:
	super.net_set(s)
	installed = s[s.size() - 1]
