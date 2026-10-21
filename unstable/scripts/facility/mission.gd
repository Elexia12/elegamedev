class_name Mission
extends Node3D
## Root of the level, and the coordinator for one run.
##
## The simulation lives in child nodes, each doing one job. Every level has:
##   %Contract         the level's rules: HUD text, how it ends, results
##   %MissionClock     time, instability, phases, collapse deadline
##   %Tremors          shakes the facility: camera shake, shoves, falling rubble
##   %IncidentLog      incident list (+ the few messages that must be text)
##   %Crew             spawns crew members per connected peer
## Some levels also have (all optional):
##   %PressureNetwork  coolant pressure, overpressure burst + water jet
##   %Toolkit          the team's winch cables
##   %ExtractionZone   the Flooded Reactor's lift
## Facility parts (gates, supports, hoists, flood zones, cargo, rubble)
## simulate themselves.
##
## This node does three things:
##   1. request(): the single entry point for player actions (any peer -> host).
##      Facility nodes handle their own: "use" calls use(player) on the node at
##      the given path, "drive" calls drive(player, input).
##   2. Runs the end of the run: the crew leaving, or the final physical
##      collapse, then the results screen (built by the Contract).
##   3. Replication: every node in group "net" exposes net_get()/net_set().
##      The host packs them into `net_state` and StateSync replicates it.

enum State { RUNNING, COLLAPSING, ENDED }

## How long the final collapse plays out before the run fails (seconds).
@export var collapse_duration := 7.0

var state := State.RUNNING
## Replicated snapshot (host -> clients). See _collect().
var net_state: Array = []
var _net_nodes: Array[Node] = []
var _collapse_timer := 0.0
var _collapse_pulse := 0.0

@onready var contract: Contract = %Contract
@onready var clock: MissionClock = %MissionClock
@onready var tremors: Tremors = %Tremors
@onready var incident_log: IncidentLog = %IncidentLog
@onready var crew: CrewRoster = %Crew
@onready var overview_camera: Camera3D = %OverviewCamera
@onready var pressure_network: PressureNetwork = get_node_or_null("%PressureNetwork")
@onready var toolkit: Toolkit = get_node_or_null("%Toolkit")
@onready var extraction: ExtractionZone = get_node_or_null("%ExtractionZone")


## The Mission a node belongs to (walks up the tree).
static func of(n: Node) -> Mission:
	var p := n
	while p and not p is Mission:
		p = p.get_parent()
	return p as Mission


func _ready() -> void:
	process_physics_priority = 100
	_net_nodes.assign(get_tree().get_nodes_in_group("net").filter(func(n: Node) -> bool: return is_ancestor_of(n)))
	_net_nodes.sort_custom(func(a: Node, b: Node) -> bool: return str(get_path_to(a)) < str(get_path_to(b)))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## True while the world is still simulating (including the final collapse).
func running() -> bool:
	return state != State.ENDED


## Highest water surface over `p` from any flood zone (or -INF if dry).
func water_surface_at(p: Vector3) -> float:
	var y := -INF
	for z: FloodZone in get_tree().get_nodes_in_group("floods"):
		if is_ancestor_of(z):
			y = maxf(y, z.surface_at(p))
	return y


## Push from a burst water jet at `p` (zero if this level has none).
func jet_push_at(p: Vector3) -> Vector3:
	return pressure_network.jet_push_at(p) if pressure_network else Vector3.ZERO


func money(amount: float) -> String:
	return contract.money(amount)


func props() -> Array[Prop]:
	var out: Array[Prop] = []
	for p in get_tree().get_nodes_in_group("props"):
		if is_ancestor_of(p):
			out.append(p)
	return out


## Machines a crew member can take the controls of (group "machines").
func machines() -> Array[Node]:
	return get_tree().get_nodes_in_group("machines").filter(func(n: Node) -> bool: return is_ancestor_of(n))


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if state == State.COLLAPSING:
			_run_collapse(delta)
		net_state = _collect()
	elif not net_state.is_empty():
		_apply(net_state)
	overview_camera.current = crew.local_member() == null


# --- Player requests (any peer -> host) -------------------------------------

## Client-side helper: ask the host to do something. Paths are mission-relative.
func send(action: String, a := "", b := "", v := Vector3.ZERO, f := 0.0, w := Vector3.ZERO) -> void:
	request.rpc_id(1, action, a, b, v, f, w)


@rpc("any_peer", "call_local", "reliable")
func request(action: String, a: String, b: String, v: Vector3, f: float, w: Vector3) -> void:
	if not multiplayer.is_server() or not running():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player := crew.member(sender)
	if player == null:
		return
	var point := get_node_or_null(a) as InteractPoint
	var reply := ""
	match action:
		"hold":
			player.set_hold(a, b, v, f)
		"throw":
			player.hands.host_throw()
		"align":
			player.hands.host_align(int(f))
		"use":
			# The node (or the InteractPoint's owner) handles it.
			var target := get_node_or_null(a)
			var n: Node = target.handler() if target is InteractPoint else target
			if n and n.has_method("use") and _in_reach(player, target):
				reply = n.use(player, target)
		"drive":
			var machine := get_node_or_null(a)
			if machine and machine.has_method("drive") and machine.operator_id() == sender:
				machine.drive(player, v)
		"release_controls":
			for m in machines():
				if m.operator_id() == sender:
					reply = m.release(player)
		"winch_attach":
			# a/v = first end (path, local), b/w = second end.
			if toolkit:
				reply = toolkit.attach_cable(a, v, b, w, player.head.global_position, CrewMember.AIM_REACH + 2.0)
		"winch_detach":
			if toolkit:
				reply = toolkit.detach_cable(point)
		"valve":
			var valve := point.get_parent() as Valve if point else null
			if valve:
				valve.turn(v.x)
				reply = "%s %d%% open" % [valve.display_name, roundi(valve.opening * 100.0)]
		"lever":
			if extraction:
				extraction.toggle(player.display_name)
		"report":
			incident_log.incident(a)
	incident_log.tell(sender, reply)


## Host-side sanity check: players can only use things near them.
func _in_reach(player: CrewMember, n: Node) -> bool:
	if not n is Node3D:
		return true
	return player.head.global_position.distance_to((n as Node3D).global_position) < CrewMember.AIM_REACH + 3.0


# --- Signals wired in the level scene ----------------------------------------

## Each new phase starts with a big tremor instead of a message.
func _on_phase_changed(phase: int, _phase_name: String) -> void:
	tremors.tremor(0.5 + 0.15 * phase)


## The crew left (the lift reached the top, the truck drove off).
func _on_departed() -> void:
	_end(false)


func _on_lift_departed() -> void:
	_on_departed()


func _on_facility_collapsed() -> void:
	if state != State.RUNNING:
		return
	state = State.COLLAPSING
	_collapse_timer = collapse_duration
	incident_log.incident("The facility collapsed")
	for s: Support in get_tree().get_nodes_in_group("supports"):
		if is_ancestor_of(s):
			s.damage(1000.0)
	contract.on_collapse()


## Host: the last seconds. Everything comes down around the crew.
func _run_collapse(delta: float) -> void:
	_collapse_timer -= delta
	_collapse_pulse -= delta
	if _collapse_pulse <= 0.0:
		_collapse_pulse = 0.8
		tremors.rubble_chance = 1.0
		tremors.tremor(1.0)
	if _collapse_timer <= 0.0 and not contract.departing():
		_end(true)


# --- End of run --------------------------------------------------------------

func _end(collapsed: bool) -> void:
	if state == State.ENDED:
		return
	state = State.ENDED
	clock.running = false
	var data := contract.results(collapsed)
	net_state = _collect()
	get_tree().root.get_node("Main").show_results.rpc(data)


# --- Replication -------------------------------------------------------------

func _collect() -> Array:
	var out: Array = [state]
	for n in _net_nodes:
		out.append(n.net_get())
	return out


func _apply(s: Array) -> void:
	if s.size() != _net_nodes.size() + 1:
		return
	state = s[0]
	for i in _net_nodes.size():
		_net_nodes[i].net_set(s[i + 1])
