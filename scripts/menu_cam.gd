extends Camera3D

@onready var h_box_container: HBoxContainer = $CanvasLayer/Menu/HBoxContainer
@onready var h_box_container_2: HBoxContainer = $CanvasLayer/Menu/HBoxContainer2

func _ready():
	pass

func _process(delta):
	pass

@onready var anim_tree: AnimationTree = $AnimationTree


func _on_play_pressed() -> void:
	anim_tree.set("parameters/conditions/new_game", true)
	await get_tree().create_timer(2.9).timeout
	anim_tree.set("parameters/conditions/new_game", false)

func _on_options_pressed() -> void:
	h_box_container.visible = false
	h_box_container_2.visible = true

func _on_credits_pressed() -> void:
	anim_tree.set("parameters/conditions/credits", true)
	await get_tree().create_timer(2.9).timeout
	anim_tree.set("parameters/conditions/credits", false)

func _on_volume_pressed() -> void:
	anim_tree.set("parameters/conditions/volume", true)
	await get_tree().create_timer(2.9).timeout
	anim_tree.set("parameters/conditions/volume", false)

func _on_language_pressed() -> void:
	anim_tree.set("parameters/conditions/language", true)
	await get_tree().create_timer(2.9).timeout
	anim_tree.set("parameters/conditions/language", false)

func _on_brightness_pressed() -> void:
	anim_tree.set("parameters/conditions/brightness", true)
	await get_tree().create_timer(2.9).timeout
	anim_tree.set("parameters/conditions/brightness", false)

func _on_back_pressed() -> void:
	h_box_container.visible = true
	h_box_container_2.visible = false
	anim_tree.set("parameters/conditions/back", true)
	await get_tree().create_timer(2.9).timeout
	anim_tree.set("parameters/conditions/back", false)

func _on_exit_pressed() -> void:
	pass # Replace with function body.
