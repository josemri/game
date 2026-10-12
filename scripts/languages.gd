extends Node3D
@onready var anim: AnimationPlayer = $AnimationPlayer

var hover_active := false
var hover_name := ""
var last_executed := ""

func _on_area_3d_mouse_entered(_name: int) -> void:
	hover_active = true
	hover_name = str(_name)
	# Espera 1 segundo antes de disparar la animación
	await get_tree().create_timer(0.5).timeout
	if hover_active:
		# Si el ratón sigue dentro, ejecuta la animación
		var anim_name = "selected" + hover_name
		if anim.has_animation(anim_name):
			anim.play(anim_name)
			last_executed = hover_name

func _on_area_3d_mouse_exited(_name: int) -> void:
	# Si el ratón salió antes de que pasara 1 segundo, cancelamos
	hover_active = false
	if (last_executed == str(_name)):
		var anim_name_back = "selected" + str(_name)
		if anim.has_animation(anim_name_back):
			anim.play_backwards(anim_name_back)

func _on_area_3d_input_event(_camera: Node, _event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	pass
