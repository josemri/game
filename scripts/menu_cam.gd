extends Camera3D

@onready var h_box_container: HBoxContainer = $CanvasLayer/Menu/HBoxContainer
@onready var h_box_container_2: HBoxContainer = $CanvasLayer/Menu/HBoxContainer2

func _ready():
	pass

func _process(_delta):
	pass

@onready var anim_tree: AnimationTree = $AnimationTree

func trigger_anim_condition(condition: String, duration: float = 0.2) -> void:
	anim_tree.set("parameters/conditions/%s" % condition, true)
	await get_tree().create_timer(duration).timeout
	anim_tree.set("parameters/conditions/%s" % condition, false)


## Desactiva los menús que se manipulan con el ratón salvo el indicado.
func refresh_interactive_menus(keep: String = "") -> void:
	for path in ["../menuItems/volume_menu", "../menuItems/brightness_menu"]:
		var menu := get_node_or_null(path)
		if menu and menu.has_method("set_active"):
			menu.set_active(path == keep)


func _on_play_pressed() -> void:
	refresh_interactive_menus()
	trigger_anim_condition("new_game")
	#temporal just to test
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_options_pressed() -> void:
	refresh_interactive_menus()
	h_box_container.visible = false
	h_box_container_2.visible = true

func _on_credits_pressed() -> void:
	refresh_interactive_menus()
	trigger_anim_condition("credits")
	
func _on_volume_pressed() -> void:
	refresh_interactive_menus("../menuItems/volume_menu")
	trigger_anim_condition("volume")

func _on_language_pressed() -> void:
	refresh_interactive_menus()
	$CanvasLayer/Menu.mouse_filter = 2
	trigger_anim_condition("language")

func _on_brightness_pressed() -> void:
	refresh_interactive_menus("../menuItems/brightness_menu")
	trigger_anim_condition("brightness")
	
func _on_back_pressed() -> void:
	refresh_interactive_menus()
	h_box_container.visible = true
	h_box_container_2.visible = false
	trigger_anim_condition("back")

func _on_exit_pressed() -> void:
	pass
