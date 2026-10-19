extends SceneTree
## Test de regresión del menú de volumen de la radio (scripts/volume_menu.gd),
## que vive en scenes/volume_menu.tscn y se instancia en el menú principal.
##
## Comprueba: buses de audio, detección de las dos ruedas con el ratón,
## el giro con la rueda del ratón, los límites 0 % / 100 %, el cambio de bus,
## el guardado/carga de la configuración y que ninguna rueda se queda "colgada".
##
## Ejecutar:  godot --headless --path . -s res://tests/volume_menu_test.gd

const SCENE := "res://scenes/mainmenu.tscn"
const TEST_CFG := "user://test_volume_menu.cfg"

## Pose final de la cámara en la vista de volumen (animación "volume").
const VOLUME_CAM_POS := Vector3(-2.3501253, 0.16436806, -0.87025166)
const VOLUME_CAM_QUAT := Quaternion(-0.097588554, 0.7655626, 0.08976738, 0.6295492)

var checks := 0
var failures := 0
var vm: Node3D
var cam: Camera3D

func _check(label: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)

func _close(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_to(b.origin) > 0.001:
		return false
	var q := a.basis.get_rotation_quaternion().inverse() * b.basis.get_rotation_quaternion()
	return absf(q.w) > 0.9999

func _wheel(button: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev

## Simula el ratón sobre una rueda y una muesca de la rueda del ratón.
func _scroll(which: String, button: int) -> void:
	vm._set_hover(which)
	vm._input(_wheel(button))

## Deja que las ruedas terminen su giro/salida (sin ceder el paso al bucle real).
func _settle() -> void:
	for i in 20:
		vm._animate(0.05)

func _db(bus: int) -> float:
	return AudioServer.get_bus_volume_db(bus)

func _clear_cfg() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	_clear_cfg()
	var scene: Node3D = (load(SCENE) as PackedScene).instantiate()
	# ruta de configuración de prueba: no tocamos el settings real del jugador
	(scene.get_node("menuItems/volume_menu") as Node3D).settings_path = TEST_CFG
	get_root().add_child(scene)
	await process_frame
	vm = scene.get_node("menuItems/volume_menu")
	cam = scene.get_node("Camera3D")
	cam.get_node("AnimationTree").active = false
	cam.transform = Transform3D(Basis(VOLUME_CAM_QUAT), VOLUME_CAM_POS)
	await process_frame
	vm.set_active(true)

	# --- 1) Buses de audio del proyecto ---
	_check("1) hay 4 buses", AudioServer.get_bus_count() == 4)
	_check("1) Master/Music/SFX/Voice",
		AudioServer.get_bus_name(0) == "Master"
		and AudioServer.get_bus_name(1) == "Music"
		and AudioServer.get_bus_name(2) == "SFX"
		and AudioServer.get_bus_name(3) == "Voice")

	# --- 2) Etiquetas: sólo visibles en la vista de volumen ---
	vm.set_active(false)
	_check("2) etiquetas ocultas fuera de la vista",
		not vm._select_label.visible and not vm._value_label.visible)
	vm.set_active(true)
	_check("2) etiquetas visibles en la vista",
		vm._select_label.visible and vm._value_label.visible)
	_check("2) arranca en MASTER al 100%",
		vm._select_label.text == "MASTER" and vm._value_label.text == "100%")

	# --- 3) Detección de las ruedas en pantalla ---
	var c_value: Vector2 = cam.unproject_position(vm._center["value"])
	var c_sel: Vector2 = cam.unproject_position(vm._center["selector"])
	_check("3) ruedas delante de la cámara",
		not cam.is_position_behind(vm._center["value"])
		and not cam.is_position_behind(vm._center["selector"]))
	_check("3) se acierta la rueda de valor", vm._knob_at(cam, c_value) == "value")
	_check("3) se acierta la rueda selectora", vm._knob_at(cam, c_sel) == "selector")
	_check("3) entre las dos ruedas no se acierta",
		vm._knob_at(cam, (c_value + c_sel) * 0.5) == "")
	_check("3) fuera de pantalla no se acierta", vm._knob_at(cam, Vector2(2, 2)) == "")
	_check("3) etiquetas delante de la cámara",
		not cam.is_position_behind(vm._select_label.global_position)
		and not cam.is_position_behind(vm._value_label.global_position))
	var to_cam: Vector3 = (cam.global_position - vm._select_label.global_position).normalized()
	_check("3) la etiqueta mira a la cámara",
		vm._select_label.global_transform.basis.z.normalized().dot(to_cam) > 0.9)

	# --- 4) Rueda de valor: sube/baja el volumen del bus elegido ---
	_scroll("value", MOUSE_BUTTON_WHEEL_UP)
	_check("4) Master al tope", is_equal_approx(float(vm._volumes["Master"]), 1.0))
	_scroll("value", MOUSE_BUTTON_WHEEL_DOWN)
	_scroll("value", MOUSE_BUTTON_WHEEL_DOWN)
	_check("4) Master al 90 %", is_equal_approx(float(vm._volumes["Master"]), 0.9))
	_check("4) etiqueta al 90 %", vm._value_label.text == "90%")
	_check("4) volumen aplicado al bus", absf(_db(0) - linear_to_db(0.9)) < 0.01)
	_check("4) el bus Music no se toca", absf(_db(1) - linear_to_db(1.0)) < 0.01)
	_check("4) la rueda de valor gira",
		absf(vm._angle["value"] - vm._angle_target["value"]) > 0.01)
	_settle()
	_check("4) la rueda acaba en su sitio",
		is_equal_approx(vm._angle["value"], vm._angle_target["value"]))
	_check("4) la rueda selectora no se mueve",
		is_equal_approx(vm._angle["selector"], vm._angle_target["selector"]))

	# --- 5) Límites 0 % y 100 % ---
	for i in 25:
		_scroll("value", MOUSE_BUTTON_WHEEL_DOWN)
	_settle()
	_check("5) no baja de 0 %", is_equal_approx(float(vm._volumes["Master"]), 0.0))
	_check("5) etiqueta 0 %", vm._value_label.text == "0%")
	_check("5) bus silenciado al 0 %", AudioServer.is_bus_mute(0))
	_scroll("value", MOUSE_BUTTON_WHEEL_DOWN)
	_check("5) aún en 0 % tras otra muesca", is_equal_approx(float(vm._volumes["Master"]), 0.0))
	_scroll("value", MOUSE_BUTTON_WHEEL_UP)
	_check("5) sube a 5 %", is_equal_approx(float(vm._volumes["Master"]), 0.05))
	_check("5) bus ya no silenciado", not AudioServer.is_bus_mute(0))

	# --- 6) Rueda selectora: cambia el bus elegido ---
	_scroll("selector", MOUSE_BUTTON_WHEEL_DOWN)
	_check("6) ahora en MUSIC", vm._select_label.text == "MUSIC")
	_check("6) la rueda de valor salta a Music (100 %)",
		vm._value_label.text == "100%"
		and is_equal_approx(vm._angle["value"], -135.0 + 1.0 * 270.0))
	_check("6) Master sigue al 5 %", is_equal_approx(float(vm._volumes["Master"]), 0.05))
	_settle()
	_check("6) la rueda selectora gira",
		absf(vm._angle["selector"] - vm._angle_target["selector"]) < 0.01)
	_check("6) giró una muesca", is_equal_approx(vm._angle["selector"], 90.0))

	_scroll("selector", MOUSE_BUTTON_WHEEL_DOWN)
	_check("6) ahora en SFX", vm._select_label.text == "SFX")
	_scroll("selector", MOUSE_BUTTON_WHEEL_DOWN)
	_check("6) ahora en VOICE", vm._select_label.text == "VOICE")
	_scroll("selector", MOUSE_BUTTON_WHEEL_DOWN)
	_check("6) vuelve a MASTER", vm._select_label.text == "MASTER")
	_check("6) la rueda de valor vuelve a Master (5 %)", vm._value_label.text == "5%")
	_scroll("selector", MOUSE_BUTTON_WHEEL_UP)
	_check("6) la rueda selectora también sube", vm._select_label.text == "VOICE")

	# --- 7) Cambiar de bus no arrastra el volumen de los demás ---
	_scroll("selector", MOUSE_BUTTON_WHEEL_DOWN) # VOICE -> MASTER
	_check("7) MASTER seleccionado otra vez", vm._select_label.text == "MASTER")
	_check("7) Music sigue al 100 %", absf(_db(1) - linear_to_db(1.0)) < 0.01)
	_check("7) SFX sigue al 100 %", absf(_db(2) - linear_to_db(1.0)) < 0.01)
	_check("7) Voice sigue al 100 %", absf(_db(3) - linear_to_db(1.0)) < 0.01)

	# --- 8) La rueda de ratón fuera de la vista de volumen no hace nada ---
	var before_m: float = float(vm._volumes["Master"])
	var before_sel: String = vm._select_label.text
	vm.set_active(false)
	vm._set_hover("value")
	vm._input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	_check("8) sin efecto fuera de la vista",
		is_equal_approx(float(vm._volumes["Master"]), before_m)
		and vm._select_label.text == before_sel)

	# --- 9) Guardado y carga de la configuración ---
	var cfg := ConfigFile.new()
	_check("9) el archivo se guarda", cfg.load(TEST_CFG) == OK)
	_check("9) guarda todos los buses",
		cfg.has_section_key("audio", "Master")
		and cfg.has_section_key("audio", "Music")
		and cfg.has_section_key("audio", "SFX")
		and cfg.has_section_key("audio", "Voice"))
	var saved_master: float = float(cfg.get_value("audio", "Master"))
	_check("9) guarda el valor de Master",
		is_equal_approx(saved_master, float(vm._volumes["Master"])))
	# Cambios en memoria sin tocar el archivo: la carga debe volver a lo guardado.
	vm._volumes["Master"] = 0.5
	vm.apply_to_audio_server()
	_check("9) cambio en memoria", is_equal_approx(float(vm._volumes["Master"]), 0.5))
	vm.load_settings()
	_check("9) carga lo guardado",
		is_equal_approx(float(vm._volumes["Master"]), saved_master))

	# --- 10) Ninguna rueda se queda a medias ni fuera de la radio ---
	vm.set_active(true)
	_scroll("value", MOUSE_BUTTON_WHEEL_DOWN) # la rueda de valor empieza a girar
	_check("10) la rueda de valor queda a medias",
		absf(vm._angle["value"] - vm._angle_target["value"]) > 0.01)
	vm._set_hover("")
	vm.set_active(false) # el jugador se va sin esperar a que acabe
	_settle()
	_check("10) la rueda de valor termina su giro",
		is_equal_approx(vm._angle["value"], vm._angle_target["value"]))
	_check("10) la rueda selectora termina su giro",
		is_equal_approx(vm._angle["selector"], vm._angle_target["selector"]))
	_check("10) ninguna rueda sobresale de la radio",
		is_equal_approx(vm._pop["value"], 0.0) and is_equal_approx(vm._pop["selector"], 0.0))
	_check("10) la rueda de valor no se desplaza",
		vm._value_mesh.transform.origin.distance_to(vm._base["value"].origin) < 0.0001)
	_check("10) la rueda selectora no se desplaza",
		vm._selector_mesh.transform.origin.distance_to(vm._base["selector"].origin) < 0.0001)

	# --- 11) Los botones del menú principal activan/desactivan las ruedas ---
	var menu_cam: Object = scene.get_node("Camera3D")
	menu_cam._on_volume_pressed()
	_check("11) el botón de volumen activa las ruedas", vm._active)
	menu_cam._on_back_pressed()
	_check("11) el botón atrás desactiva las ruedas", not vm._active)
	menu_cam._on_volume_pressed()
	menu_cam._on_language_pressed()
	_check("11) el botón de idiomas desactiva las ruedas", not vm._active)
	menu_cam._on_volume_pressed()
	menu_cam._on_options_pressed()
	_check("11) volver a opciones desactiva las ruedas", not vm._active)

	_clear_cfg()
	print("")
	print("%d comprobaciones, %d fallos" % [checks, failures])
	quit(1 if failures > 0 else 0)
