extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected
signal p2p_connection_established()

const PORT = 7000
const MAX_CONNECTION = 10

var players = {}
@onready var peer = ENetMultiplayerPeer.new()
var is_host = false

var player_info = {"name": "Name"}

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Punchthrough.punchthrough_completed.connect(_on_punchthrough_completed)

func _on_punchthrough_completed(_self_port, _host_address, _host_port):
	if Punchthrough.is_host:
		create_game(_self_port, MAX_CONNECTION)
	else:
		join_game(_host_address, _host_port)
	

func create_game(_port, _max_connections):
	print ("Creating game on " + Punchthrough.client_name)
	var error = peer.create_server(_port, _max_connections)
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	players[1] = player_info
	player_connected.emit(1, player_info)
	
func join_game(_address, _port):
	print ("Joining game on " + Punchthrough.client_name)
	var error = peer.create_client(_address, _port)
	if error:
		return error
	multiplayer.multiplayer_peer = peer

func _on_player_connected(id):
	_register_player.rpc_id(id, player_info)

@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)

func _on_player_disconnected(id):
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_to_server():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	player_connected.emit(peer_id)
	
func _on_connection_failed():
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
