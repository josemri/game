extends Node3D
@onready var anim: AnimationPlayer = $AnimationPlayer

var hover_active := false
var hover_name := ""
var last_executed := ""

func _on_area_3d_mouse_entered(name: int) -> void:
	hover_active = true
	hover_name = str(name)
	# Espera 1 segundo antes de disparar la animación
	await get_tree().create_timer(0.5).timeout
	if hover_active:
		# Si el ratón sigue dentro, ejecuta la animación
		anim.play("selected" + hover_name)
		last_executed = hover_name

func _on_area_3d_mouse_exited(name: int) -> void:
	# Si el ratón salió antes de que pasara 1 segundo, cancelamos
	hover_active = false
	if (last_executed == str(name)):
		anim.play_backwards("selected" + str(name))

func _on_area_3d_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	pass
