extends SceneTree
## Two-process network smoke test over ENet on localhost. Run the host first:
##   godot --headless --path . -s res://tests/net_test.gd -- --role=host
##   godot --headless --path . -s res://tests/net_test.gd -- --role=client
## The host winches the core; the client opens the drain valve by request.
## Each side prints what it sees so the two views can be compared.

const RUN_SECONDS := 16.0

var main: Node
var role := "host"
var t := 0.0
var _did_client_request := false
var _did_host_winch := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	if t > 0.2 and t - delta <= 0.2:
		if role == "host":
			main.select_mission(1)  # The Flooded Reactor
			main.start_host()
		else:
			main.start_join("127.0.0.1")
	var m: Mission = main.mission()
	if m == null:
		return t > RUN_SECONDS
	if role == "host" and not _did_host_winch and root.multiplayer.get_peers().size() > 0 and t > 5.0:
		_did_host_winch = true
		var me := m.crew.local_member()
		me.global_position = Vector3(-13.5, 0.05, -8.0)
		m.tremors._next = 9999.0
		m.request("winch_attach", "Cargo/ReactorCore", "", Vector3(-0.8, 0.0, -0.8), 0.0, Vector3(-15.9, 1.0, -6.5))
		var c := m.toolkit.cables()[0]
		if c.active:
			c.reel = 1
		print("[host] winch attached: ", c.active)
	if role == "client" and not _did_client_request and t > 4.0 and m.crew.local_member() != null:
		_did_client_request = true
		m.send("valve", "Manifold/DrainValve/Point", "", Vector3(0.5, 0, 0))
		print("[client] sent drain valve request")
	if t > RUN_SECONDS + (3.0 if role == "host" else 0.0):
		var core := m.get_node("Cargo/ReactorCore") as Prop
		var cable := m.toolkit.cables()[0].active
		print("[%s] peers=%d crew=%d core=(%.2f, %.2f, %.2f) drain=%.2f cable=%s pressure=%.1f elapsed=%.1f" % [
			role, root.multiplayer.get_peers().size(), m.crew.members().size(),
			core.global_position.x, core.global_position.y, core.global_position.z,
			(m.get_node("Manifold/DrainValve") as Valve).opening, cable, m.pressure_network.pressure, m.clock.elapsed])
		root.get_node("Net").leave()
		return true
	return false
