class_name Mission
extends Node3D
## One run of the facility (root of the level scene).
##
## Host-authoritative: the host simulates the pressure network, flooding,
## extraction and timers, resolves every player request, and packs all
## facility state into `net_state`, which one MultiplayerSynchronizer
## replicates. Clients only render that snapshot and send requests.

signal message(text: String, kind: String)
signal client_event(kind: String, text: String)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PHASES := ["ASSESS", "RECOVERY", "ESCALATION", "COLLAPSE IMMINENT"]

@export_group("Timing")
## Seconds until the facility collapses (GDD target run: 15–20 min; shorter here).
@export var collapse_time := 720.0
@export var extraction_delay := 8.0
@export_group("Pressure network")
@export var start_pressure := 40.0
## Pressure gained per second at zero / full instability.
@export var pressure_rise := 0.12
@export var pressure_rise_unstable := 0.55
## Seconds at 100% before the line bursts.
@export var burst_time := 3.0
@export var burst_duration := 25.0
## Lower-facility water added per second while the burst line gushes.
@export var burst_flow := 0.02
## Pressure spent per second by the drain pump at 100%.
@export var drain_pressure_cost := 1.4
@export_group("Flooding")
## Bonus-chamber water pumped out per second at 100% drain.
@export var drain_rate := 0.035
## Share of pumped water that ends up in the lower facility.
@export var drain_to_lower := 0.6
@export var bonus_inflow := 0.002
@export var bonus_inflow_unstable := 0.011
@export var lower_sump := 0.0015
@export_group("Crew")
@export var team_braces := 3

enum State { RUNNING, ENDED }

var state := State.RUNNING
var elapsed := 0.0
var pressure := 40.0
var braces_left := 3
var extract_timer := -1.0
var burst_timer := 0.0
var incidents: Array[String] = []
## Replicated snapshot (host -> clients). See _collect().
var net_state: Array = []

var _phase := 0
var _overpressure := 0.0
var _pressure_warned := false
var _net_nodes: Array[Node] = []

@onready var players_root: Node3D = $Players
@onready var extraction: ExtractionZone = $ExtractionZone
@onready var spawn_points: Node3D = $SpawnPoints
@onready var lower_flood: FloodZone = $LowerFlood
@onready var bonus_flood: FloodZone = $BonusFlood
@onready var burst_vent: CPUParticles3D = $BurstVent
@onready var overview_camera: Camera3D = $OverviewCamera


static func of(n: Node) -> Mission:
	var p := n
	while p and not p is Mission:
		p = p.get_parent()
	return p as Mission


func _ready() -> void:
	add_to_group("mission")
	process_physics_priority = 100
	pressure = start_pressure
	braces_left = team_braces
	_net_nodes.assign(get_tree().get_nodes_in_group("net").filter(func(n: Node) -> bool: return is_ancestor_of(n)))
	_net_nodes.sort_custom(func(a: Node, b: Node) -> bool: return str(get_path_to(a)) < str(get_path_to(b)))
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_add_player)
		multiplayer.peer_disconnected.connect(_remove_player)
		_add_player(1)
		for id in multiplayer.get_peers():
			_add_player(id)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	message.emit.call_deferred("Recover the REACTOR CORE behind the jammed gate. Optional: the bonus container in the flooding storage room.", "info")
	message.emit.call_deferred("Bring cargo onto the green lift pad, then pull the extraction lever.", "info")


func running() -> bool:
	return state == State.RUNNING


func instability() -> float:
	return clampf(elapsed / collapse_time, 0.0, 1.0)


func phase() -> int:
	var i := instability()
	if i < 0.15:
		return 0
	if i < 0.45:
		return 1
	if i < 0.8:
		return 2
	return 3


func time_left() -> float:
	return maxf(0.0, collapse_time - elapsed)


static func clock(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


# --- Players -----------------------------------------------------------------

func _add_player(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	var p := PLAYER_SCENE.instantiate()
	p.name = str(id)
	players_root.add_child(p, true)
	if id != 1:
		broadcast("%s joined the crew" % p.display_name, "info")


func _remove_player(id: int) -> void:
	var p := players_root.get_node_or_null(str(id)) as CrewMember
	if p:
		log_incident("%s disconnected" % p.display_name)
		p.queue_free()


func local_player() -> CrewMember:
	return players_root.get_node_or_null(str(multiplayer.get_unique_id())) as CrewMember


func crew() -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for c in players_root.get_children():
		if c is CrewMember and not c.is_queued_for_deletion():
			out.append(c)
	return out


func spawn_position(peer_id: int) -> Vector3:
	var markers := spawn_points.get_children()
	var i := 0 if peer_id == 1 else 1 + peer_id % (markers.size() - 1)
	return markers[i].global_position


# --- Queries used by everyone ----------------------------------------------

func water_surface_at(p: Vector3) -> float:
	return maxf(lower_flood.surface_at(p), bonus_flood.surface_at(p))


func valve(channel: String) -> Valve:
	for v: Valve in get_tree().get_nodes_in_group("valves"):
		if v.channel == channel and is_ancestor_of(v):
			return v
	return null


func cables() -> Array[Cable]:
	var out: Array[Cable] = []
	for c in get_tree().get_nodes_in_group("cables"):
		if is_ancestor_of(c):
			out.append(c)
	return out


func cable_at(point: Node) -> Cable:
	if point == null:
		return null
	var p := str(get_path_to(point))
	for c in cables():
		if c.uses(p):
			return c
	return null


func props() -> Array[Prop]:
	var out: Array[Prop] = []
	for p in get_tree().get_nodes_in_group("props"):
		if is_ancestor_of(p):
			out.append(p)
	return out


# --- Host simulation ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if state == State.RUNNING:
			_simulate(delta)
		net_state = _collect()
	elif not net_state.is_empty():
		_apply(net_state)
	burst_vent.emitting = burst_timer > 0.0
	overview_camera.current = local_player() == null


func _simulate(delta: float) -> void:
	elapsed += delta
	var inst := instability()
	var ph := phase()
	if ph != _phase:
		_phase = ph
		var hints := [
			"", "Supports are starting to strain.",
			"The facility is failing. Water and pressure are rising faster.",
			"Get out NOW — collapse in %s." % clock(time_left()),
		]
		broadcast("PHASE: %s. %s" % [PHASES[ph], hints[ph]], "phase")

	# Pressure network: pressure builds on its own; the drain pump bleeds it
	# off but dumps the bonus chamber's water into the lower facility.
	pressure += (pressure_rise + pressure_rise_unstable * inst) * delta
	var drain := valve("drain")
	if drain and drain.opening > 0.0 and pressure > 2.0:
		pressure -= drain.opening * drain_pressure_cost * delta
		var moved := minf(bonus_flood.level, drain.opening * drain_rate * delta)
		bonus_flood.add_water(-moved)
		lower_flood.add_water(moved * drain_to_lower + drain.opening * 0.002 * delta)
	if pressure >= 100.0:
		_overpressure += delta
		if _overpressure >= burst_time:
			_burst()
	else:
		_overpressure = 0.0
	pressure = clampf(pressure, 0.0, 100.0)
	if pressure > 85.0 and not _pressure_warned:
		_pressure_warned = true
		broadcast("OVERPRESSURE — open the drain pump or a line will burst", "warn")
	elif pressure < 75.0:
		_pressure_warned = false

	# Flooding.
	bonus_flood.add_water((bonus_inflow + bonus_inflow_unstable * inst) * delta)
	if burst_timer > 0.0:
		burst_timer -= delta
		lower_flood.add_water(burst_flow * delta)
	lower_flood.add_water(-lower_sump * delta)

	# Extraction / collapse.
	if extract_timer >= 0.0:
		extract_timer -= delta
		if extract_timer <= 0.0:
			_end(false)
			return
	if elapsed >= collapse_time:
		_end(true)


func _burst() -> void:
	_overpressure = 0.0
	pressure = 45.0
	burst_timer = burst_duration
	log_incident("Pressure line BURST — the main hall is flooding")


# --- Requests (any peer -> host) ---------------------------------------------

## Client-side helper: ask the host to do something. Paths are mission-relative.
func send(action: String, a := "", b := "", v := Vector3.ZERO, f := 0.0) -> void:
	request.rpc_id(1, action, a, b, v, f)


@rpc("any_peer", "call_local", "reliable")
func request(action: String, a: String, b: String, v: Vector3, f: float) -> void:
	if not multiplayer.is_server() or state != State.RUNNING:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player := players_root.get_node_or_null(str(sender)) as CrewMember
	if player == null:
		return
	match action:
		"hold":
			player.set_hold(a, b, v, f)
		"winch_attach":
			_winch_attach(player, sender, get_node_or_null(a) as InteractPoint, get_node_or_null(b) as InteractPoint)
		"winch_detach":
			var c := cable_at(get_node_or_null(a))
			if c:
				c.detach()
				tell(sender, "Cable detached")
		"brace_place":
			_brace_place(sender, get_node_or_null(a) as InteractPoint)
		"brace_remove":
			var point := get_node_or_null(a) as InteractPoint
			var socket := point.get_parent() as BraceSocket if point else null
			if socket and socket.braced:
				socket.remove()
				braces_left += 1
				tell(sender, "Brace recovered (%d left)" % braces_left)
		"valve":
			var point := get_node_or_null(a) as InteractPoint
			var vl := point.get_parent() as Valve if point else null
			if vl:
				vl.opening = clampf(snappedf(vl.opening + v.x, 0.25), 0.0, 1.0)
				tell(sender, "%s %d%% open" % [vl.display_name, roundi(vl.opening * 100.0)])
		"lever":
			if extract_timer < 0.0:
				extract_timer = extraction_delay
				broadcast("%s called EXTRACTION — lift leaves in %d s. Cargo and crew onto the pad!" % [player.display_name, roundi(extraction_delay)], "phase")
			else:
				extract_timer = -1.0
				broadcast("%s cancelled extraction" % player.display_name, "info")
		"report":
			log_incident(a)


func _winch_attach(player: CrewMember, sender: int, h: InteractPoint, a: InteractPoint) -> void:
	if h == null or a == null or h.kind != "hook" or a.kind != "anchor":
		return
	if cable_at(h):
		tell(sender, "That hook already has a cable")
		return
	if cable_at(a):
		tell(sender, "That anchor is already in use")
		return
	if player.head.global_position.distance_to(a.global_position) > CrewMember.AIM_REACH + 2.0:
		tell(sender, "Too far from the anchor")
		return
	var free: Cable = null
	for c in cables():
		if not c.active:
			free = c
			break
	if free == null:
		tell(sender, "All winch cables are in use — detach one first [R]")
		return
	var dist := h.global_position.distance_to(a.global_position)
	if dist > free.max_length:
		tell(sender, "Cable won't reach (%.0f m, max %.0f m)" % [dist, free.max_length])
		return
	free.attach(h, a)
	tell(sender, "Cable rigged: %s → %s. Hold LMB on either end to reel in." % [h.describe(), a.describe()])


func _brace_place(sender: int, point: InteractPoint) -> void:
	var socket := point.get_parent() as BraceSocket if point else null
	if socket == null:
		return
	var why := socket.block_reason()
	if why != "":
		tell(sender, why)
		return
	if braces_left <= 0:
		tell(sender, "No braces left — recover one with [R]")
		return
	socket.place()
	braces_left -= 1
	tell(sender, "Brace set on %s (%d left)" % [point.describe(), braces_left])


## Host: pressure tool blast (+1) or suction (-1) — bounded push on loose props.
func pressure_blast(origin: Vector3, dir: Vector3, sign_dir: float) -> void:
	for p in props():
		if p.freeze:
			continue
		var to := p.global_position - origin
		var d := to.length()
		if d > 7.0 or d < 0.1 or dir.angle_to(to) > 0.45:
			continue
		if sign_dir < 0.0 and d < 1.4:
			continue
		p.sleeping = false
		p.apply_central_force(to / d * 650.0 * (1.0 - d / 7.0) * sign_dir)


func snap_cables_at(point: InteractPoint, why: String) -> void:
	var c := cable_at(point)
	if c:
		var h := c.hook()
		log_incident("Cable on %s %s" % [h.describe() if h else "?", why])
		c.detach()


# --- Messages ----------------------------------------------------------------

func log_incident(text: String) -> void:
	incidents.append("%s  %s" % [clock(elapsed), text])
	broadcast(text, "alert")


func broadcast(text: String, kind: String) -> void:
	announce.rpc(text, kind)


func tell(peer_id: int, text: String) -> void:
	notify.rpc_id(peer_id, "toast", text)


@rpc("authority", "call_local", "reliable")
func announce(text: String, kind: String) -> void:
	message.emit(text, kind)


@rpc("authority", "call_local", "reliable")
func notify(kind: String, text: String) -> void:
	client_event.emit(kind, text)


# --- End of run --------------------------------------------------------------

func _end(collapsed: bool) -> void:
	if state == State.ENDED:
		return
	state = State.ENDED
	extract_timer = -1.0
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
	for c in crew():
		if collapsed:
			incidents.append("%s  %s was inside when the facility collapsed" % [clock(elapsed), c.display_name])
		elif not extraction.contains(c.global_position):
			incidents.append("%s  %s was left behind" % [clock(elapsed), c.display_name])
	var outcome := "FAILURE"
	if primary and optional:
		outcome = "FULL RECOVERY"
	elif primary:
		outcome = "SUCCESSFUL RECOVERY"
	elif value > 0.0:
		outcome = "PARTIAL RECOVERY"
	var data := {
		"outcome": outcome,
		"collapsed": collapsed,
		"value": roundi(value),
		"primary": primary,
		"optional": optional,
		"duration": elapsed,
		"cargo": cargo_lines,
		"incidents": incidents,
	}
	net_state = _collect()
	get_tree().root.get_node("Main").show_results.rpc(data)


# --- Replication -------------------------------------------------------------

func _collect() -> Array:
	var out: Array = [[elapsed, pressure, braces_left, extract_timer, burst_timer, state]]
	for n in _net_nodes:
		out.append(n.net_get())
	return out


func _apply(s: Array) -> void:
	if s.size() != _net_nodes.size() + 1:
		return
	var head: Array = s[0]
	elapsed = head[0]
	pressure = head[1]
	braces_left = head[2]
	extract_timer = head[3]
	burst_timer = head[4]
	state = head[5]
	for i in _net_nodes.size():
		_net_nodes[i].net_set(s[i + 1])
