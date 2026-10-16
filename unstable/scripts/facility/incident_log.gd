class_name IncidentLog
extends Node
## Everything players hear about. Broadcasts reach every peer, toasts reach one
## player, and incidents are kept for the results screen. The HUD listens to the
## signals.

## Shown to every player (kinds: info, warn, alert, phase).
signal message(text: String, kind: String)
## Private to this peer (kinds: toast, release).
signal client_event(kind: String, text: String)

## Host only: "mm:ss  what happened" lines for the results screen.
var incidents: Array[String] = []
var mission: Mission


func _ready() -> void:
	mission = Mission.of(self)


## Host: record a major incident and tell everyone.
func incident(text: String) -> void:
	incidents.append("%s  %s" % [mission.clock.stamp(), text])
	broadcast(text, "alert")


## Host: message every player.
func broadcast(text: String, kind: String) -> void:
	_announce.rpc(text, kind)


## Host: private message to one player.
func tell(peer_id: int, text: String) -> void:
	_notify.rpc_id(peer_id, "toast", text)


## Host: tell a player their grab was dropped.
func release_grab(peer_id: int, text: String) -> void:
	_notify.rpc_id(peer_id, "release", text)


## Local-only toast (no network).
func local_toast(text: String) -> void:
	client_event.emit("toast", text)


@rpc("authority", "call_local", "reliable")
func _announce(text: String, kind: String) -> void:
	message.emit(text, kind)


@rpc("authority", "call_local", "reliable")
func _notify(kind: String, text: String) -> void:
	client_event.emit(kind, text)
