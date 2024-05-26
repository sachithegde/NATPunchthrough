extends Area2D

signal interacted()

@rpc("any_peer", "reliable", "call_local")
func interact():
	if not multiplayer.is_server():
		return
	interacted.emit()
