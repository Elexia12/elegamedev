extends SceneTree
## Two-process network test for Blackwater Station over ENet on localhost.
## Run the host first:
##   godot --headless --path . -s res://tests/blackwater_net_test.gd -- --role=host
##   godot --headless --path . -s res://tests/blackwater_net_test.gd -- --role=client
## The client unbolts the VFD module with its wrench, takes the hoist pendant
## and drives the carriage, then lets go. The host drops the module to damage
## it. Each side prints what it sees so the two views can be compared.

const RUN_SECONDS := 20.0
const HOIST := "PumpHall/OverheadHoist"

var main: Node
var role := "host"
var t := 0.0
var _done := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _once(key: String, at: float) -> bool:
	if t >= at and not _done.has(key):
		_done[key] = true
		return true
	return false


func _process(delta: float) -> bool:
	t += delta
	if _once("start", 0.2):
		if role == "host":
			main.start_host()
		else:
			main.start_join("127.0.0.1")
	var m: Mission = main.mission()
	if m == null:
		return t > RUN_SECONDS
	var me := m.crew.local_member()
	if role == "host" and _once("quiet", 1.0):
		m.tremors._next = 9999.0
	if role == "client" and me:
		if _once("go_vfd", 4.0):
			me.global_position = Vector3(-13.5, 0.05, -14.0)
			me.rotation = Vector3(0, PI / 2.0, 0)
		if _once("wrench", 4.5):
			m.send("hold", "wrench", "ControlRoom/VfdMounting/Point", Vector3(-1, 0, 0))
			print("[client] wrenching the VFD bolts")
		if _once("go_pendant", 9.0):
			m.send("hold", "")
			# Up in the hoist booth, at the console.
			me.global_position = Vector3(14.6, 3.65, -15.0)
			me.rotation = Vector3(0, PI / 2.0, 0)
		if _once("pendant", 9.5):
			m.send("use", HOIST + "/Pendant/Point")
		if _once("drive", 10.0):
			print("[client] operating hoist: ", me.operated_machine() != null)
			m.send("drive", HOIST, "", Vector3(-1, 0, 0))
		if _once("stop", 11.5):
			m.send("drive", HOIST, "", Vector3.ZERO)
		if _once("let_go", 12.5):
			m.send("release_controls")
		if _once("go_trolley", 13.0):
			# Behind the trolley's handle (it faces +X), facing along it.
			me.global_position = Vector3(15.75, 0.05, -8.5)
			me.rotation = Vector3(0, PI / 2.0, 0)
		if _once("take_trolley", 13.5):
			m.send("use", "PumpHall/Trolley")
		if _once("push", 14.0):
			print("[client] pushing the trolley: ", me.pushing() != null)
			me.bot_input = Vector2(0, -1)
		if _once("stop_push", 16.0):
			me.bot_input = Vector2.ZERO
			m.send("use", "PumpHall/Trolley")
	if role == "host" and _once("drop", 13.0):
		var vfd := m.get_node("ControlRoom/VfdModule") as Prop
		print("[host] VFD loose before the drop: ", not vfd.dormant)
		vfd.global_position = Vector3(-12.0, 2.5, -14.0)
		vfd.linear_velocity = Vector3.ZERO
	if t > RUN_SECONDS + (3.0 if role == "host" else 0.0):
		var h := m.get_node(HOIST) as OverheadHoist
		var vfd := m.get_node("ControlRoom/VfdModule") as Prop
		print("[%s] peers=%d crew=%d hoist_x=%.2f operator=%d vfd_loose=%s vfd_condition=%.1f vfd_hits=%d vfd_pos=(%.1f, %.1f, %.1f)" % [
			role, root.multiplayer.get_peers().size(), m.crew.members().size(), h.x, h.operator,
			not vfd.dormant, vfd.condition, vfd.hits, vfd.global_position.x, vfd.global_position.y, vfd.global_position.z])
		var trolley := m.get_node("PumpHall/Trolley") as Trolley
		print("[%s] trolley=(%.1f, %.1f) pushers=%s" % [role, trolley.global_position.x, trolley.global_position.z, trolley.pushers])
		print("[%s] vfd_bumps=%d" % [role, vfd.bumps])
		print("[%s] %s" % [role, m.contract.status_text().replace("\n", " | ")])
		root.get_node("Net").leave()
		return true
	return false
