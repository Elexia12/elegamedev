class_name Toolkit
extends Node3D
## The team's shared winch cables: the Cable child nodes. Add or remove
## children to change how many the team has. (Braces aren't counted here any
## more; they're physical posts you carry.)

var mission: Mission


func _ready() -> void:
	mission = Mission.of(self)


func cables() -> Array[Cable]:
	var out: Array[Cable] = []
	for c in get_children():
		if c is Cable:
			out.append(c)
	return out


func active_cable_count() -> int:
	return cables().filter(func(c: Cable) -> bool: return c.active).size()


## The cable whose end marker this is, if any.
func cable_at(point: Node) -> Cable:
	if point is InteractPoint and point.kind == "cable":
		var c := point.get_parent() as Cable
		return c if c and c.active else null
	return null


## Total tension on cables with an end on `support`'s structure.
func load_on(support: Support) -> float:
	var total := 0.0
	for c in cables():
		if c.active and (c.end_support(0) == support or c.end_support(1) == support):
			total += c.tension
	return total


## Host: rig a free cable between two points. Each point is a mission-relative
## body path ("" for static world) plus a local (or world) position.
## Returns a message for the player.
func attach_cable(path_a: String, local_a: Vector3, path_b: String, local_b: Vector3,
		from_position: Vector3, reach: float) -> String:
	var free: Cable = null
	for c in cables():
		if not c.active:
			free = c
			break
	if free == null:
		return "All %d winch cables are in use — detach one first [R]" % cables().size()
	free.attach(path_a, local_a, path_b, local_b)
	var a := free.end_position(0)
	var b := free.end_position(1)
	if from_position.distance_to(b) > reach and from_position.distance_to(a) > reach:
		free.detach()
		return "Too far away to rig that"
	if a.distance_to(b) > free.max_length:
		free.detach()
		return "Cable won't reach (%.0f m, max %.0f m)" % [a.distance_to(b), free.max_length]
	return ""


## Host: detach whatever cable this end marker belongs to.
func detach_cable(point: Node) -> String:
	var c := cable_at(point)
	if c:
		c.detach()
	return ""


## Host: snap every cable touching `support` (it just failed).
func snap_cables_on(support: Support) -> void:
	for c in cables():
		if c.active and (c.end_support(0) == support or c.end_support(1) == support):
			c._snap("torn loose")
