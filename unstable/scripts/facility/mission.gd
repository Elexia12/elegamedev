class_name Mission
extends Node3D
## Root of the level, and the coordinator for one run.
##
## The simulation lives in child nodes, each doing one job:
##   %MissionClock     time, instability, phases, collapse
##   %PressureNetwork  coolant pressure, overpressure burst
##   DrainPump         moves water between flood zones using pressure
##   %Toolkit          shared winch cables and braces
##   %IncidentLog      messages to players, incident list
##   %Crew             spawns crew members per connected peer
##   %ExtractionZone   lift pad and departure countdown
## Facility parts (Gate, Supports, flood zones, cargo) simulate themselves.
##
## This node does three things:
##   1. request(): the single entry point for player actions (any peer -> host).
##   2. Decides the outcome when the lift departs or the facility collapses.
##   3. Replication: every node in group "net" exposes net_get()/net_set().
##      The host packs them into `net_state` and the StateSync child
##      replicates it to clients.

@export_multiline var phase_hints: PackedStringArray = [
	"",
	"Supports are starting to strain.",
	"The facility is failing. Water and pressure are rising faster.",
	"Get out NOW — the facility is about to collapse.",
]

var ended := false
## Replicated snapshot (host -> clients). See _collect().
var net_state: Array = []
var _net_nodes: Array[Node] = []

@onready var clock: MissionClock = %MissionClock
@onready var pressure_network: PressureNetwork = %PressureNetwork
@onready var toolkit: Toolkit = %Toolkit
@onready var incident_log: IncidentLog = %IncidentLog
@onready var crew: CrewRoster = %Crew
@onready var extraction: ExtractionZone = %ExtractionZone
@onready var overview_camera: Camera3D = %OverviewCamera


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
	incident_log.message.emit.call_deferred("Recover the REACTOR CORE behind the jammed gate. Optional: the bonus container in the flooding storage room.", "info")
	incident_log.message.emit.call_deferred("Bring cargo onto the green lift pad, then pull the extraction lever.", "info")


func running() -> bool:
	return not ended


## Highest water surface over `p` from any flood zone (or -INF if dry).
func water_surface_at(p: Vector3) -> float:
	var y := -INF
	for z: FloodZone in get_tree().get_nodes_in_group("floods"):
		if is_ancestor_of(z):
			y = maxf(y, z.surface_at(p))
	return y


func props() -> Array[Prop]:
	var out: Array[Prop] = []
	for p in get_tree().get_nodes_in_group("props"):
		if is_ancestor_of(p):
			out.append(p)
	return out


func _physics_process(_delta: float) -> void:
	if multiplayer.is_server():
		net_state = _collect()
	elif not net_state.is_empty():
		_apply(net_state)
	overview_camera.current = crew.local_member() == null


# --- Player requests (any peer -> host) -------------------------------------

## Client-side helper: ask the host to do something. Paths are mission-relative.
func send(action: String, a := "", b := "", v := Vector3.ZERO, f := 0.0) -> void:
	request.rpc_id(1, action, a, b, v, f)


@rpc("any_peer", "call_local", "reliable")
func request(action: String, a: String, b: String, v: Vector3, f: float) -> void:
	if not multiplayer.is_server() or ended:
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
		"winch_attach":
			reply = toolkit.attach_cable(point, get_node_or_null(b) as InteractPoint,
				player.head.global_position, CrewMember.AIM_REACH + 2.0)
		"winch_detach":
			reply = toolkit.detach_cable(point)
		"brace_place":
			reply = toolkit.place_brace(point.get_parent() as BraceSocket if point else null)
		"brace_remove":
			reply = toolkit.recover_brace(point.get_parent() as BraceSocket if point else null)
		"valve":
			var valve := point.get_parent() as Valve if point else null
			if valve:
				valve.turn(v.x)
				reply = "%s %d%% open" % [valve.display_name, roundi(valve.opening * 100.0)]
		"lever":
			extraction.toggle(player.display_name)
		"report":
			incident_log.incident(a)
	if reply != "":
		incident_log.tell(sender, reply)


# --- Signals wired in the level scene ----------------------------------------

func _on_phase_changed(phase: int, phase_name: String) -> void:
	var hint := phase_hints[phase] if phase < phase_hints.size() else ""
	incident_log.broadcast("PHASE: %s. %s" % [phase_name, hint], "phase")


func _on_lift_departed() -> void:
	_end(false)


func _on_facility_collapsed() -> void:
	_end(true)


# --- End of run --------------------------------------------------------------

func _end(collapsed: bool) -> void:
	if ended:
		return
	ended = true
	clock.running = false
	extraction.timer = -1.0
	var stamp := clock.stamp()
	var value := 0.0
	var primary := false
	var optional := false
	var cargo_lines: Array[String] = []
	for p in props():
		if p.role == "debris":
			continue
		var got := p.secured and not collapsed
		if got:
			value += p.current_value
			cargo_lines.append("%s  $%d" % [p.display_name, roundi(p.current_value)])
		if p.role == "primary":
			primary = got
		elif p.role == "optional":
			optional = got
	for c in crew.members():
		if collapsed:
			incident_log.incidents.append("%s  %s was inside when the facility collapsed" % [stamp, c.display_name])
		elif not extraction.contains(c.global_position):
			incident_log.incidents.append("%s  %s was left behind" % [stamp, c.display_name])
	var outcome := "FAILURE"
	if primary and optional:
		outcome = "FULL RECOVERY"
	elif primary:
		outcome = "SUCCESSFUL RECOVERY"
	elif value > 0.0:
		outcome = "PARTIAL RECOVERY"
	net_state = _collect()
	get_tree().root.get_node("Main").show_results.rpc({
		"outcome": outcome,
		"collapsed": collapsed,
		"value": roundi(value),
		"primary": primary,
		"optional": optional,
		"duration": clock.elapsed,
		"cargo": cargo_lines,
		"incidents": incident_log.incidents,
	})


# --- Replication -------------------------------------------------------------

func _collect() -> Array:
	var out: Array = [ended]
	for n in _net_nodes:
		out.append(n.net_get())
	return out


func _apply(s: Array) -> void:
	if s.size() != _net_nodes.size() + 1:
		return
	ended = s[0]
	for i in _net_nodes.size():
		_net_nodes[i].net_set(s[i + 1])
