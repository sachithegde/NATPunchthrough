extends Node

@export var ui : Control
@export var level_container : Node
@export var level_scene : PackedScene
@export var ip_line_edit : LineEdit
@export var status_label : Label
@export var not_connected_hbox : HBoxContainer
@export var host_hbox : HBoxContainer
@export var client_name_line_edit : LineEdit

# Called when the node enters the scene tree for the first time.
func _ready():
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	Punchthrough.lobby_updated.connect(refresh_lobby)
	Punchthrough.session_created.connect(_on_session_completed)
	Punchthrough.process_failed.connect(_on_process_failed)


func _on_host_button_pressed():
	not_connected_hbox.hide()
	host_hbox.show()
	Punchthrough.Start_Punchthrough("ABCD", true, client_name_line_edit.text)
	#Lobby.create_game()

func _on_session_completed():
	if Punchthrough.is_host:
		status_label.text = "Hosting Lobby"
	else:
		status_label.text = "Connected to Lobby"
	
func _on_join_button_pressed():
	Punchthrough.Start_Punchthrough(ip_line_edit.text, false, client_name_line_edit.text)
	#Lobby.join_game(ip_line_edit.text)
	not_connected_hbox.hide()
	status_label.text = "Connecting..."


func _on_start_button_pressed():
	change_level.call_deferred(level_scene)
	hide_menu.rpc()

func change_level(scene : PackedScene):
	for c in level_container.get_children():
		level_container.remove_child(c)
		c.queue_free()
	level_container.add_child(scene.instantiate())

func _on_process_failed(_message):
	host_hbox.hide()
	not_connected_hbox.show()
	status_label.text = _message

func _on_connection_failed():
	not_connected_hbox.show()
	status_label.text = "Connect Failed"

func _on_connected_to_server():
	status_label.text = "Connected"
	
@rpc("authority", "reliable", "call_local")
func hide_menu():
	ui.hide()
	
func refresh_lobby(_client_names : PackedStringArray):
	while $UI/LobbyDisplay.get_child_count() > 0:
		$UI/LobbyDisplay.remove_child($UI/LobbyDisplay.get_child(0))
	for _client in _client_names:
		print(_client)
		var _textBox = Label.new()
		_textBox.text = _client
		$UI/LobbyDisplay.add_child(_textBox)


func _on_p_2p_button_pressed():
	Punchthrough._finalise_lobby()
