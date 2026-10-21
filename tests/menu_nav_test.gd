extends SceneTree
## Test de regresión de la navegación del menú principal (scripts/menu_cam.gd):
## filas de botones, bloqueo de submenús, bloqueo de ratón y guardas de play.
##
## Regla de navegación: los submenús (volume, language, brightness) solo se
## entran desde el home; dentro de un submenú los otros tres botones quedan
## desactivados y solo "back" vuelve al home. La máquina de estados de la
## cámara solo tiene transiciones idle ↔ cada vista, así que la navegación
## directa entre submenús dejaba la cámara congelada.
##
## Ejecutar:  godot --headless --path . -s res://tests/menu_nav_test.gd

const SCENE := "res://scenes/mainmenu.tscn"

var checks := 0
var failures := 0

func _check(label: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var scene: Node3D = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(scene)
	await process_frame

	var cam: Object = scene.get_node("Camera3D")
	var menu: Control = scene.get_node("Camera3D/CanvasLayer/Menu")
	var row1: Control = scene.get_node("Camera3D/CanvasLayer/Menu/HBoxContainer")
	var row2: Control = scene.get_node("Camera3D/CanvasLayer/Menu/HBoxContainer2")
	var vol: Button = row2.get_node("VBoxContainer/volume")
	var lang: Button = row2.get_node("VBoxContainer/language")
	var bright: Button = row2.get_node("VBoxContainer/brightness")
	var back: Button = row2.get_node("VBoxContainer/back")
	var at: AnimationTree = cam.get("anim_tree")

	# 1) arranque: fila de home visible, fila de opciones oculta
	_check("1) home: fila principal visible", row1.visible)
	_check("1) home: fila de opciones oculta", not row2.visible)
	_check("1) home: menú con bloqueo de ratón",
		menu.mouse_filter == Control.MOUSE_FILTER_STOP)

	# 2) options abre la fila de submenús con todo habilitado
	cam._on_options_pressed()
	await process_frame
	_check("2) options oculta la fila principal", not row1.visible)
	_check("2) options muestra la fila de opciones", row2.visible)
	_check("2) en home los tres submenús están habilitados",
		not vol.disabled and not lang.disabled and not bright.disabled)
	_check("2) back habilitado", not back.disabled)

	# 3) entrar en volumen bloquea los otros submenús y mueve la cámara
	cam._on_volume_pressed()
	_check("3) en volumen los tres submenús quedan bloqueados",
		vol.disabled and lang.disabled and bright.disabled)
	_check("3) back sigue vivo", not back.disabled)
	_check("3) dispara la condición volume del árbol de animación",
		at.get("parameters/conditions/volume") == true)
	await create_timer(0.35).timeout
	_check("3) la condición se apaga sola tras el impulso",
		at.get("parameters/conditions/volume") == false)

	# 4) language desactiva el bloqueo de ratón de la capa del menú
	cam._on_language_pressed()
	_check("4) en idiomas el menú deja pasar el ratón a los libros",
		menu.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("4) en idiomas los otros submenús siguen bloqueados",
		vol.disabled and lang.disabled and bright.disabled)

	# 5) back vuelve al home y reactiva todo
	cam._on_back_pressed()
	await process_frame
	_check("5) back muestra la fila principal", row1.visible)
	_check("5) back oculta la fila de opciones", not row2.visible)
	_check("5) back restaura el bloqueo de ratón",
		menu.mouse_filter == Control.MOUSE_FILTER_STOP)
	_check("5) en home los submenús se reactivan",
		not vol.disabled and not lang.disabled and not bright.disabled)

	# 6) desde créditos tampoco se entra en un submenú sin pasar por home
	cam._on_credits_pressed()
	cam._on_options_pressed()
	_check("6) en créditos los submenús están bloqueados",
		vol.disabled and lang.disabled and bright.disabled)
	cam._on_back_pressed()
	_check("6) back de créditos vuelve al home con todo activo",
		row1.visible and not row2.visible
		and not vol.disabled and not lang.disabled and not bright.disabled)

	# 7) play guarda contra doble pulsación (la segunda no reinicia)
	cam._on_play_pressed()
	cam._on_play_pressed()
	_check("7) la segunda pulsación de play no se procesa",
		cam.get("_cond_seq").get("new_game") == 1)
	_check("7) play oculta las dos filas", not row1.visible and not row2.visible)

	print("")
	print("%d comprobaciones, %d fallos" % [checks, failures])
	quit(1 if failures > 0 else 0)
