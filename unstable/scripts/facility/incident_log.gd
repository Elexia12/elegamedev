class_name IncidentLog
extends Node
## Keeps the incident list for the results screen and carries the few
## messages that can't be shown physically (who called the lift, who joined).
## Most events are not announced: you see the column fall, you don't read
## about it. The HUD listens to the signals.

## Shown to every player (kinds: info, warn, alert, phase).
signal message(text: String, kind: String)
## Private to this peer (kinds: toast, release, hold_ended).
signal client_event(kind: String, text: String)

## Host only: "mm:ss  what happened" lines for the results screen.
var incidents: Array[String] = []
var mission: Mission


func _ready() -> void:
	mission = Mission.of(self)


## Host: record a major incident for the results screen (not announced).
func incident(text: String) -> void:
	incidents.append("%s  %s" % [mission.clock.stamp(), text])


## Host: message every player.
func broadcast(text: String, kind: String) -> void:
	_announce.rpc(text, kind)


## Host: private message to one player.
func tell(peer_id: int, text: String) -> void:
	if text != "":
		_private(peer_id, "toast", text)


## Host: tell a player their grab was dropped.
func release_grab(peer_id: int, text: String) -> void:
	_private(peer_id, "release", text)


## Host: tell a player the host stopped their held action (a tool slipped).
func end_hold(peer_id: int, text: String) -> void:
	_private(peer_id, "hold_ended", text)


## Host: send a private event, skipping peers that aren't connected (any more).
func _private(peer_id: int, kind: String, text: String) -> void:
	if peer_id == multiplayer.get_unique_id() or peer_id in multiplayer.get_peers():
		_notify.rpc_id(peer_id, kind, text)


## Local-only toast (no network).
func local_toast(text: String) -> void:
	client_event.emit("toast", text)


@rpc("authority", "call_local", "reliable")
func _announce(text: String, kind: String) -> void:
	message.emit(text, kind)


@rpc("authority", "call_local", "reliable")
func _notify(kind: String, text: String) -> void:
	client_event.emit(kind, text)
