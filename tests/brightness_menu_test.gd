extends SceneTree
## Test de regresión del menú de brillo por cortinas (scripts/brightness_menu.gd),
## que vive en scenes/brightness_menu.tscn y se instancia en el menú principal.
##
## Comprueba: las rutas de las dos cortinas, la luz exterior situada fuera de la
## ventana apuntando hacia dentro, las posiciones de las cortinas abiertas y
## cerradas, el encendido de las luces y del ambiente según la apertura, la
## rueda del ratón con sus límites, la persistencia en el archivo de
## configuración y el cableado de los botones del menú.
##
## Ejecutar:  godot --headless --path . -s res://tests/brightness_menu_test.gd

const SCENE := "res://scenes/mainmenu.tscn"
const TEST_CFG := "user://test_brightness_menu.cfg"

## Pose final de la cámara en la vista de brillo (animación "brightness").
const BRIGHT_CAM_POS := Vector3(-0.031517148, 0.8145069, 1.7343471)
const BRIGHT_CAM_QUAT := Quaternion(-0.004358169, 0.97911125, 0.11135372, -0.17006616)

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

func _wheel(button: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev

## Simula el ratón sobre las cortinas y una muesca de la rueda del ratón.
func _scroll(button: int) -> void:
	vm._set_hover(true)
	vm._input(_wheel(button))

## Deja que las cortinas terminen su animación (sin ceder el paso al bucle real).
func _settle() -> void:
	for i in 30:
		vm._process(0.05)

func _box(side: String) -> AABB:
	var panel: MeshInstance3D = vm._panels[side]
	return panel.global_transform * panel.mesh.get_aabb()

func _base_box(side: String) -> AABB:
	return vm._base[side] * vm._aabb[side]

func _energy_out() -> float:
	return (vm.get_node("outside_light") as SpotLight3D).light_energy

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
	(scene.get_node("menuItems/brightness_menu") as Node3D).settings_path = TEST_CFG
	get_root().add_child(scene)
	await process_frame
	vm = scene.get_node("menuItems/brightness_menu")
	cam = scene.get_node("Camera3D")
	cam.get_node("AnimationTree").active = false
	cam.transform = Transform3D(Basis(BRIGHT_CAM_QUAT), BRIGHT_CAM_POS)
	await process_frame
	vm.set_active(true)

	# --- 1) Estructura: cortinas, luces y ambiente ---
	_check("1) hay brightness_menu con su script",
		vm != null and vm.get_script() != null)
	_check("1) la cortina izquierda se resuelve",
		vm._panels.get("left") != null and is_instance_valid(vm._panels.get("left")))
	_check("1) la cortina derecha se resuelve",
		vm._panels.get("right") != null and is_instance_valid(vm._panels.get("right")))
	_check("1) las dos cortinas son nodos distintos",
		vm._panels["left"] != vm._panels["right"])
	var light := vm.get_node("outside_light") as SpotLight3D
	_check("1) hay luz exterior", light != null)
	var panels_max_z: float = maxf(_base_box("left").end.z, _base_box("right").end.z)
	_check("1) la luz está fuera, detrás de las cortinas",
		light != null and light.global_position.z > panels_max_z + 0.2)
	var fwd: Vector3 = -light.global_transform.basis.z
	_check("1) la luz apunta hacia dentro y hacia abajo",
		fwd.z < -0.3 and fwd.y < -0.3)
	_check("1) la luz de la mancha del suelo se resuelve", vm._floor_light != null)
	_check("1) el derrame de la ventana se resuelve", vm._spill_light != null)
	_check("1) el relleno de la sala se resuelve", vm._fill_light != null)
	_check("1) el ambiente se resuelve", vm._env != null)
	_check("1) arranca con las cortinas abiertas",
		is_equal_approx(vm._open, 1.0) and is_equal_approx(vm._open_target, 1.0))

	# --- 1b) La luz del menú llega a todos los meshes ---
	# El entorno apuntaba a ambient_source=BG, que ignora
	# ambient_light_energy: la mayor parte de la sala no respondía al
	# brillo. Se exige COLOR para que el ambiente ilumine por igual.
	_check("1b) el ambiente usa la fuente COLOR (responde a la energía)",
		vm._env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR)
	_check("1b) el color del ambiente es el del menú",
		vm._env.ambient_light_color.is_equal_approx(vm.AMBIENT_COLOR))
	_check("1b) la luz exterior proyecta sombras (el muro da forma al haz)",
		light != null and light.shadow_enabled)
	var glass := vm.get_node_or_null(vm.window_glass) as MeshInstance3D
	_check("1b) el cristal no proyecta sombra (no tapa el hueco)",
		glass != null
		and glass.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	# --- 2) Cortinas abiertas: recogidas a los lados ---
	_check("2) borde exterior izquierdo fijo",
		absf(_box("left").position.x - _base_box("left").position.x) < 0.001)
	_check("2) borde exterior derecho fijo",
		absf(_box("right").end.x - _base_box("right").end.x) < 0.001)
	_check("2) el paño izquierdo queda recogido",
		absf(_box("left").size.x - _base_box("left").size.x * vm.SCRUNCH) < 0.001)
	_check("2) el paño derecho queda recogido",
		absf(_box("right").size.x - _base_box("right").size.x * vm.SCRUNCH) < 0.001)
	_check("2) la altura no cambia",
		absf(_box("left").size.y - _base_box("left").size.y) < 0.001)
	_check("2) la luz exterior está a plena potencia",
		is_equal_approx(_energy_out(), vm.LIGHT_OUT_MAX))
	_check("2) el derrame está a plena potencia",
		is_equal_approx(vm._spill_light.light_energy, vm.LIGHT_SPILL_MAX))
	_check("2) el relleno está a plena potencia",
		is_equal_approx(vm._fill_light.light_energy, vm.LIGHT_FILL_MAX))
	_check("2) la mancha del suelo está a plena potencia",
		is_equal_approx(vm._floor_light.light_energy, vm.LIGHT_FLOOR_MAX))
	_check("2) el ambiente está a plena potencia",
		is_equal_approx(vm._env.ambient_light_energy, vm.AMBIENT_MAX))

	# --- 3) La rueda solo actúa con el menú activado y el ratón en las cortinas ---
	vm.set_active(false)
	vm._set_hover(true)
	vm._input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	_check("3) inactiva la vista, la rueda no hace nada",
		is_equal_approx(vm._open_target, 1.0))
	vm.set_active(true)
	vm._set_hover(false)
	vm._input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	_check("3) sin hover, la rueda no hace nada",
		is_equal_approx(vm._open_target, 1.0))
	vm._set_hover(true)
	vm.set_active(false)
	_check("3) salir de la vista borra el hover", not vm._hover)

	# --- 4) Cerrar las cortinas con la rueda del ratón ---
	vm.set_active(true)
	_scroll(MOUSE_BUTTON_WHEEL_DOWN)
	_check("4) una muesca baja la apertura un paso",
		is_equal_approx(vm._open_target, 1.0 - vm.OPEN_STEP))
	_check("4) la rueda se da por manejada", vm.get_viewport().is_input_handled())
	_settle()
	_check("4) las cortinas terminan la animación",
		is_equal_approx(vm._open, vm._open_target))
	_check("4) la luz exterior baja proporcional a la apertura",
		absf(_energy_out() - lerpf(vm.LIGHT_OUT_MIN, vm.LIGHT_OUT_MAX, 0.75)) < 0.001)
	for i in 3:
		_scroll(MOUSE_BUTTON_WHEEL_DOWN)
	_check("4) la apertura se queda en 0 (no baja de 0)",
		is_equal_approx(vm._open_target, 0.0))
	_scroll(MOUSE_BUTTON_WHEEL_DOWN)
	_check("4) seguir bajando no pasa de 0",
		is_equal_approx(vm._open_target, 0.0))
	_settle()
	var left_box := _box("left")
	var right_box := _box("right")
	_check("4) al cerrar, los dos paños se cruzan en el centro",
		absf(left_box.end.x - right_box.position.x) < 0.01)
	_check("4) el paño izquierdo vuelve a su ancho completo",
		absf(left_box.size.x - _base_box("left").size.x) < 0.001)
	_check("4) el paño derecho vuelve a su ancho completo",
		absf(right_box.size.x - _base_box("right").size.x) < 0.001)
	_check("4) la altura sigue intacta al cerrar",
		absf(left_box.size.y - _base_box("left").size.y) < 0.001)
	_check("4) la luz exterior se apaga", is_equal_approx(_energy_out(), 0.0))
	_check("4) el derrame se apaga",
		is_equal_approx(vm._spill_light.light_energy, vm.LIGHT_SPILL_MIN))
	_check("4) el relleno se apaga",
		is_equal_approx(vm._fill_light.light_energy, vm.LIGHT_FILL_MIN))
	_check("4) la mancha del suelo queda casi apagada",
		is_equal_approx(vm._floor_light.light_energy, vm.LIGHT_FLOOR_MIN))
	_check("4) el ambiente baja al mínimo",
		is_equal_approx(vm._env.ambient_light_energy, vm.AMBIENT_MIN))

	# --- 5) Abrir las cortinas con la rueda del ratón ---
	for i in 6:
		_scroll(MOUSE_BUTTON_WHEEL_UP)
	_check("5) la apertura sube pero no pasa de 1",
		is_equal_approx(vm._open_target, 1.0))
	_settle()
	_check("5) la luz exterior vuelve a plena potencia",
		is_equal_approx(_energy_out(), vm.LIGHT_OUT_MAX))
	_check("5) el borde exterior izquierdo vuelve a su sitio",
		absf(_box("left").position.x - _base_box("left").position.x) < 0.001)
	_check("5) el borde exterior derecho vuelve a su sitio",
		absf(_box("right").end.x - _base_box("right").end.x) < 0.001)
	_check("5) los paños vuelven a recogerse",
		absf(_box("left").size.x - _base_box("left").size.x * vm.SCRUNCH) < 0.001
		and absf(_box("right").size.x - _base_box("right").size.x * vm.SCRUNCH) < 0.001)

	# --- 6) set_brightness aplica al instante y recorta ---
	vm.set_brightness(0.5)
	_check("6) set_brightness(0.5) aplica sin animación",
		is_equal_approx(vm._open, 0.5) and is_equal_approx(vm._open_target, 0.5))
	_check("6) luz exterior a la mitad",
		absf(_energy_out() - lerpf(vm.LIGHT_OUT_MIN, vm.LIGHT_OUT_MAX, 0.5)) < 0.001)
	_check("6) derrame a la mitad",
		absf(vm._spill_light.light_energy
			- lerpf(vm.LIGHT_SPILL_MIN, vm.LIGHT_SPILL_MAX, 0.5)) < 0.001)
	_check("6) relleno a la mitad",
		absf(vm._fill_light.light_energy
			- lerpf(vm.LIGHT_FILL_MIN, vm.LIGHT_FILL_MAX, 0.5)) < 0.001)
	_check("6) mancha del suelo a la mitad",
		absf(vm._floor_light.light_energy
			- lerpf(vm.LIGHT_FLOOR_MIN, vm.LIGHT_FLOOR_MAX, 0.5)) < 0.001)
	_check("6) ambiente a la mitad",
		absf(vm._env.ambient_light_energy
			- lerpf(vm.AMBIENT_MIN, vm.AMBIENT_MAX, 0.5)) < 0.001)
	_check("6) los paños a media escala",
		absf(_box("left").size.x - _base_box("left").size.x * 0.675) < 0.001)
	vm.set_brightness(-3.0)
	_check("6) set_brightness(-3) recorta a 0", is_equal_approx(vm._open_target, 0.0))
	vm.set_brightness(7.0)
	_check("6) set_brightness(7) recorta a 1", is_equal_approx(vm._open_target, 1.0))

	# --- 7) Persistencia en el archivo de configuración ---
	var seed_cfg := ConfigFile.new()
	seed_cfg.set_value("otra_seccion", "clave", 42)
	seed_cfg.save(TEST_CFG)
	vm.set_brightness(0.5)
	var saved := ConfigFile.new()
	_check("7) el archivo se crea", saved.load(TEST_CFG) == OK)
	_check("7) guarda la apertura 0.5",
		saved.has_section_key("display", "brightness")
		and is_equal_approx(float(saved.get_value("display", "brightness")), 0.5))
	_check("7) conserva las demás claves del archivo",
		saved.has_section_key("otra_seccion", "clave")
		and int(saved.get_value("otra_seccion", "clave")) == 42)
	# una escena nueva con el mismo archivo debe arrancar con ese valor
	var scene2: Node3D = (load(SCENE) as PackedScene).instantiate()
	(scene2.get_node("menuItems/brightness_menu") as Node3D).settings_path = TEST_CFG
	get_root().add_child(scene2)
	await process_frame
	var vm2 := scene2.get_node("menuItems/brightness_menu") as Node3D
	_check("7) una escena nueva recarga la apertura guardada",
		is_equal_approx(vm2._open, 0.5) and is_equal_approx(vm2._open_target, 0.5))

	# --- 8) Los botones del menú principal activan/desactivan las cortinas ---
	var menu_cam: Object = scene.get_node("Camera3D")
	menu_cam._on_brightness_pressed()
	_check("8) el botón de brillo activa las cortinas", vm._active)
	menu_cam._on_volume_pressed()
	_check("8) el botón de volumen desactiva las cortinas", not vm._active)
	menu_cam._on_brightness_pressed()
	menu_cam._on_language_pressed()
	_check("8) el botón de idiomas desactiva las cortinas", not vm._active)
	menu_cam._on_brightness_pressed()
	menu_cam._on_options_pressed()
	_check("8) volver a opciones desactiva las cortinas", not vm._active)
	menu_cam._on_brightness_pressed()
	menu_cam._on_back_pressed()
	_check("8) atrás desactiva las cortinas", not vm._active)

	_clear_cfg()
	print("")
	print("%d comprobaciones, %d fallos" % [checks, failures])
	quit(1 if failures > 0 else 0)
