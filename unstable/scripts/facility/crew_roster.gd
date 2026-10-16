class_name CrewRoster
extends Node3D
## Host: adds one CrewMember under Members for each connected peer. The
## PlayerSpawner child replicates them to everyone, including late joiners.
## SpawnPoints children are where crew start and respawn.

@export var player_scene: PackedScene

var mission: Mission

@onready var members_root: Node3D = $Members
@onready var spawn_points: Node3D = $SpawnPoints


func _ready() -> void:
	mission = Mission.of(self)
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(add_member)
		multiplayer.peer_disconnected.connect(remove_member)
		add_member.call_deferred(1)
		for id in multiplayer.get_peers():
			add_member.call_deferred(id)


func add_member(peer_id: int) -> void:
	if members_root.has_node(str(peer_id)):
		return
	var p := player_scene.instantiate()
	p.name = str(peer_id)
	members_root.add_child(p, true)
	if peer_id != 1:
		mission.incident_log.broadcast("%s joined the crew" % p.display_name, "info")


func remove_member(peer_id: int) -> void:
	var p := members_root.get_node_or_null(str(peer_id)) as CrewMember
	if p:
		mission.incident_log.incident("%s disconnected" % p.display_name)
		p.queue_free()


func member(peer_id: int) -> CrewMember:
	return members_root.get_node_or_null(str(peer_id)) as CrewMember


func local_member() -> CrewMember:
	return member(multiplayer.get_unique_id())


func members() -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for c in members_root.get_children():
		if c is CrewMember and not c.is_queued_for_deletion():
			out.append(c)
	return out


## The host uses the first spawn point; other peers share the rest.
func spawn_position(peer_id: int) -> Vector3:
	var markers := spawn_points.get_children()
	var i := 0 if peer_id == 1 else 1 + peer_id % (markers.size() - 1)
	return markers[i].global_position
