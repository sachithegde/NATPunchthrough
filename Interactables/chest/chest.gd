extends Node2D


@export var chest_locked : Sprite2D
@export var chest_unlocked : Sprite2D
@export var is_locked = true

func _on_interactable_interacted():
	if not multiplayer.is_server():
		return
	if not is_locked:
		return
	is_locked = false
	update_chest_state()

func update_chest_state():
	chest_locked.visible = is_locked
	chest_unlocked.visible = !is_locked
	


func _on_multiplayer_synchronizer_delta_synchronized():
	update_chest_state()
