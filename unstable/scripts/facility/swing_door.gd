class_name SwingDoor
extends Prop
## A heavy hinged door (axis locks + a centre of mass on the hinge line keep
## it turning about its hinge). Walk into it
## and it swings away from you; it keeps swinging, so it can clip whoever is
## coming through the other way (and whatever fragile thing they're carrying).
## [E] on it shoves it open, away from you.

## Width of the panel from the hinge (local +X), and how close counts as pushing.
@export var width := 1.4
@export var push_depth := 0.65
@export var push_strength := 14.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if mission == null or not multiplayer.is_server() or freeze:
		return
	for c in mission.crew.members():
		var l := to_local(c.global_position + Vector3.UP)
		if l.x < 0.1 or l.x > width or absf(l.z) > push_depth:
			continue
		# Push the panel away from the side the crew member is on.
		var away := -global_basis.z * signf(l.z)
		var at := to_global(Vector3(l.x, 0.0, 0.0))
		sleeping = false
		apply_force(away * mass * push_strength * (push_depth - absf(l.z)) / push_depth, at - global_position)


## [E] on the door: shove it open, away from you.
func use_prompt(_crew: CrewMember) -> String:
	return "[E] push the door open (or just walk into it)"


func use(player: CrewMember, _target: Node) -> String:
	var l := to_local(player.global_position)
	var away := -global_basis.z * signf(l.z if absf(l.z) > 0.01 else 1.0)
	sleeping = false
	apply_impulse(away * mass * 3.0, to_global(Vector3(width * 0.8, 1.1, 0.0)) - global_position)
	return ""


func _label_text() -> String:
	return ""
