extends Camera3D

## Navegación del menú principal: alterna las dos filas de botones y
## dispara las condiciones de la máquina de estados del AnimationTree,
## que mueve la cámara entre la vista "idle" y cada submenú.
##
## Regla de navegación: los submenús (volume, language, brightness)
## solo se entran desde el home y entre ellos no se pasa directamente:
## dentro de un submenú la fila de opciones queda con los otros tres
## botones desactivados y solo "back" vuelve al home. La máquina de
## estados solo tiene transiciones idle ↔ cada vista, así que la cámara
## solo sigue la navegación si se pasa por el home.

@onready var h_box_container: HBoxContainer = $CanvasLayer/Menu/HBoxContainer
@onready var h_box_container_2: HBoxContainer = $CanvasLayer/Menu/HBoxContainer2
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var main_char: Node3D = $"../mainCharMenu"
@onready var police_char: Node3D = $"../policeCharMenu"
@onready var customization: Control = $CanvasLayer/Menu/CharacterCustomizer

## Segundos que se deja volar la cámara antes de enseñar el editor.
const CUSTOMIZE_DELAY := 1.6

## true en cuanto se pulsa "play": el menú ya no responde mientras
## se carga el nivel (evita dobles pulsaciones que reinicien la escena).
var _leaving := false
## true cuando la cámara está en el home: la única vista desde la que
## se puede entrar en un submenú.
var _at_home := true
## Contador por condición: si se lanza otra vez antes de que venza el
## temporizador, el viejo no apaga la nueva (igual que _hover_seq en
## languages.gd).
var _cond_seq := {}

func _ready() -> void:
	# el personaje que espera tumbado ya lleva el aspecto guardado
	customization.prepare(main_char)
	customization.start_pressed.connect(_on_customization_start)
	customization.back_pressed.connect(_on_customization_back)
	_load_translations()
	_localize_menu()


func _load_translations() -> void:
	for locale in ["en", "es", "ca", "bg", "de", "fr"]:
		var path := "res://translations/translations.%s.translation" % locale
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		if res is Translation:
			TranslationServer.add_translation(res)
	var config := ConfigFile.new()
	var locale := "es"
	if config.load("user://settings.cfg") == OK:
		locale = String(config.get_value("language", "locale", "es"))
	TranslationServer.set_locale(locale)


func _localize_menu() -> void:
	var keys := {
		"play": "MENU_PLAY",
		"options": "MENU_OPTIONS",
		"credits": "MENU_CREDITS",
		"exit": "MENU_EXIT",
		"volume": "MENU_VOLUME",
		"language": "MENU_LANGUAGE",
		"brightness": "MENU_BRIGHTNESS",
		"back": "MENU_BACK",
	}
	var menu := get_node_or_null("CanvasLayer/Menu")
	if menu == null:
		return
	_apply_keys(menu, keys)


func _apply_keys(node: Node, keys: Dictionary) -> void:
	if node is Button and keys.has(node.name):
		var key: String = keys[node.name]
		node.text = tr(key)
	for child in node.get_children():
		_apply_keys(child, keys)

func trigger_anim_condition(condition: String, duration: float = 0.2) -> void:
	_cond_seq[condition] = _cond_seq.get(condition, 0) + 1
	var seq: int = _cond_seq[condition]
	anim_tree.set("parameters/conditions/%s" % condition, true)
	await get_tree().create_timer(duration).timeout
	if _cond_seq.get(condition, 0) == seq:
		anim_tree.set("parameters/conditions/%s" % condition, false)


## Desactiva los menús que se manipulan con el ratón salvo el indicado y
## devuelve el bloqueo de ratón al menú: solo la vista de idiomas lo
## desactiva (mouse_filter=IGNORE) para que los libros reciban el ratón.
func refresh_interactive_menus(keep: String = "") -> void:
	$CanvasLayer/Menu.mouse_filter = Control.MOUSE_FILTER_STOP
	for path in ["../menuItems/volume_menu", "../menuItems/brightness_menu"]:
		var menu := get_node_or_null(path)
		if menu and menu.has_method("set_active"):
			menu.set_active(path == keep)


## En un submenú los otros submenús quedan desactivados: solo "back"
## sigue vivo para volver al home y desde allí entrar en el otro.
func _refresh_submenu_buttons() -> void:
	for btn_name in ["volume", "language", "brightness"]:
		var button := h_box_container_2.get_node_or_null(
			"VBoxContainer/%s" % btn_name) as Button
		if button:
			button.disabled = not _at_home


func _on_play_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	# el menú desaparece en cuanto se arranca el juego: mientras la
	# cámara vuela no queda nada pulsable
	h_box_container.visible = false
	h_box_container_2.visible = false
	refresh_interactive_menus()
	# el personaje secundario no participa en la creación del personaje
	police_char.visible = false
	trigger_anim_condition("new_game")
	await get_tree().create_timer(CUSTOMIZE_DELAY).timeout
	if not _leaving:
		# se ha vuelto al menú antes de que apareciera el editor
		return
	customization.open(main_char)

## El jugador ha confirmado el personaje: el perfil ya está guardado por
## el propio editor y aquí solo queda entrar en la partida.
func _on_customization_start() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

## Vuelta al home sin empezar la partida. El personaje vuelve a su idle
## tumbado y la cámara regresa a la órbita del menú.
func _on_customization_back() -> void:
	customization.close()
	police_char.visible = true
	_leaving = false
	_at_home = true
	_refresh_submenu_buttons()
	refresh_interactive_menus()
	h_box_container.visible = true
	h_box_container_2.visible = false
	trigger_anim_condition("back")

func _on_options_pressed() -> void:
	refresh_interactive_menus()
	h_box_container.visible = false
	h_box_container_2.visible = true
	_refresh_submenu_buttons()

func _on_credits_pressed() -> void:
	_at_home = false
	_refresh_submenu_buttons()
	refresh_interactive_menus()
	trigger_anim_condition("credits")

func _on_volume_pressed() -> void:
	_at_home = false
	_refresh_submenu_buttons()
	refresh_interactive_menus("../menuItems/volume_menu")
	trigger_anim_condition("volume")

func _on_language_pressed() -> void:
	_at_home = false
	_refresh_submenu_buttons()
	refresh_interactive_menus()
	$CanvasLayer/Menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_localize_menu()
	trigger_anim_condition("language")

func _on_brightness_pressed() -> void:
	_at_home = false
	_refresh_submenu_buttons()
	refresh_interactive_menus("../menuItems/brightness_menu")
	trigger_anim_condition("brightness")

func _on_back_pressed() -> void:
	_at_home = true
	_refresh_submenu_buttons()
	refresh_interactive_menus()
	_localize_menu()
	h_box_container.visible = true
	h_box_container_2.visible = false
	trigger_anim_condition("back")

func _on_exit_pressed() -> void:
	get_tree().quit()
