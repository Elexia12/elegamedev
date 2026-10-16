class_name Toolkit
extends Node3D
## The team's shared equipment: a fixed pool of winch cables (the Cable child
## nodes; add or remove children to change how many) and a stock of braces.

@export var team_braces := 3

var braces_left := 3
var mission: Mission


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	braces_left = team_braces


func cables() -> Array[Cable]:
	var out: Array[Cable] = []
	for c in get_children():
		if c is Cable:
			out.append(c)
	return out


func active_cable_count() -> int:
	return cables().filter(func(c: Cable) -> bool: return c.active).size()


## The cable using this hook or anchor point, if any.
func cable_at(point: Node) -> Cable:
	if point == null:
		return null
	var p := str(mission.get_path_to(point))
	for c in cables():
		if c.uses(p):
			return c
	return null


## Host: rig a cable between a hook and an anchor. Returns a message for the player.
func attach_cable(h: InteractPoint, a: InteractPoint, from_position: Vector3, reach: float) -> String:
	if h == null or a == null or h.kind != "hook" or a.kind != "anchor":
		return ""
	if cable_at(h):
		return "That hook already has a cable"
	if cable_at(a):
		return "That anchor is already in use"
	if from_position.distance_to(a.global_position) > reach:
		return "Too far from the anchor"
	var free: Cable = null
	for c in cables():
		if not c.active:
			free = c
			break
	if free == null:
		return "All winch cables are in use — detach one first [R]"
	var dist := h.global_position.distance_to(a.global_position)
	if dist > free.max_length:
		return "Cable won't reach (%.0f m, max %.0f m)" % [dist, free.max_length]
	free.attach(h, a)
	return "Cable rigged: %s → %s. Hold LMB on either end to reel in." % [h.describe(), a.describe()]


## Host: detach whatever cable uses this point.
func detach_cable(point: Node) -> String:
	var c := cable_at(point)
	if c == null:
		return ""
	c.detach()
	return "Cable detached"


## Host: snap a cable because something failed (logged as an incident).
func snap_cable(point: Node, why: String) -> void:
	var c := cable_at(point)
	if c:
		var h := c.hook()
		mission.incident_log.incident("Cable on %s %s" % [h.describe() if h else "?", why])
		c.detach()


## Host: put a brace in a socket. Returns a message for the player.
func place_brace(socket: BraceSocket) -> String:
	if socket == null:
		return ""
	var why := socket.block_reason()
	if why != "":
		return why
	if braces_left <= 0:
		return "No braces left — recover one with [R]"
	socket.place()
	braces_left -= 1
	return "Brace set on %s (%d left)" % [socket.point.describe(), braces_left]


## Host: take a brace back out of a socket.
func recover_brace(socket: BraceSocket) -> String:
	if socket == null or not socket.braced:
		return ""
	socket.remove()
	braces_left += 1
	return "Brace recovered (%d left)" % braces_left


func net_get() -> Array:
	return [braces_left]


func net_set(s: Array) -> void:
	braces_left = s[0]
