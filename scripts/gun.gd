extends Node3D

func _on_bullet_shot() -> void:
	visible = true
	await get_tree().create_timer(0.1).timeout
	visible = false
