extends Node
## Thin wrapper over Godot's high-level multiplayer (autoload "Net").
## Host-authoritative: peer 1 simulates the mission, every peer owns only its
## own crew member. Solo play runs the same code on an OfflineMultiplayerPeer.

signal session_started
signal session_ended(reason: String)

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4


func _ready() -> void:
	multiplayer.connected_to_server.connect(func() -> void: session_started.emit())
	multiplayer.connection_failed.connect(func() -> void: _drop("Could not reach the host."))
	multiplayer.server_disconnected.connect(func() -> void: _drop("The host left the session."))


func host(port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	session_started.emit()
	return OK


func join(address: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func solo() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	session_started.emit()


func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func _drop(reason: String) -> void:
	leave()
	session_ended.emit(reason)
