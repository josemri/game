extends Node3D

## Menú de brillo integrado en las cortinas de la ventana del salón.
##
## Poniendo el ratón sobre las cortinas y girando la rueda se abren o
## se cierran: al abrir entra más luz desde fuera (una luz situada
## detrás de la ventana) y la sala se aclara; al cerrar, la entrada de
## luz se reduce y todo el ambiente se oscurece. Sin texto: la propia
## luz indica el nivel. El valor se guarda en `settings_path`.

const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "display"
const CONFIG_KEY := "brightness"

## Apertura de las cortinas: 1.0 = abiertas, 0.0 = cerradas.
const OPEN_MIN := 0.0
const OPEN_MAX := 1.0
## Salto de la rueda del ratón, en tantos por uno de apertura.
const OPEN_STEP := 0.25
## Velocidad de la animación, en aperturas por segundo.
const OPEN_SPEED := 1.0

## Escala que queda en un panel cuando está recogido a un lado.
const SCRUNCH := 0.35

## Energía de la luz exterior con las cortinas cerradas y abiertas.
const LIGHT_OUT_MIN := 0.0
const LIGHT_OUT_MAX := 0.75
## Energía del derrame junto a la ventana (luz rebotada que entra).
const LIGHT_SPILL_MIN := 0.0
const LIGHT_SPILL_MAX := 0.25
## Energía del relleno de la sala (rebote general de la habitación).
const LIGHT_FILL_MIN := 0.0
const LIGHT_FILL_MAX := 0.12
## Energía de la mancha de luz del suelo con ellas cerradas y abiertas.
const LIGHT_FLOOR_MIN := 0.05
const LIGHT_FLOOR_MAX := 0.3
## El ambiente del entorno apuntaba al color de fondo
## (ambient_light_source=AMBIENT_SOURCE_BG), que ignora `ambient_light_energy`: la sala entera quedaba a oscuras
## para el control y unos pocos meshes respondían a las luces del menú.
## Se pasa a COLOR para que el brillo alcance todos los meshes por igual.
const AMBIENT_COLOR := Color(0.30, 0.32, 0.36)
## Energía de la luz ambiente de la sala con cortinas cerradas y abiertas.
const AMBIENT_MIN := 0.03
const AMBIENT_MAX := 0.15
## Margen (en píxeles) del área de ratón sobre las cortinas.
const HOVER_MARGIN := 12.0

@export var left_curtain: NodePath = ^"../Curtain_01_014"
@export var right_curtain: NodePath = ^"../../menu/Curtain_01_013"
@export var floor_light: NodePath = ^"../../lights/SpotLight3D"
@export var world_environment: NodePath = ^"../../WorldEnvironment"
@export var window_glass: NodePath = ^"../../menu/Mesh_02_001"
@export var settings_path: String = CONFIG_PATH

@onready var _outside_light: SpotLight3D = $outside_light
@onready var _spill_light: OmniLight3D = $spill_light
@onready var _fill_light: OmniLight3D = $fill_light

var _active := false
var _hover := false
var _open := 1.0
var _open_target := 1.0

var _panels := {}        # "left"/"right" -> MeshInstance3D
var _base := {}          # idem -> Transform3D global inicial
var _aabb := {}          # idem -> AABB local del mesh
var _pivot := {}         # idem -> Vector3 (borde exterior, local)
var _slide := {}         # idem -> float (delta en X mundial al cerrar)
var _floor_light: Light3D
var _env: Environment

func _ready() -> void:
	_panels["left"] = get_node_or_null(left_curtain) as MeshInstance3D
	_panels["right"] = get_node_or_null(right_curtain) as MeshInstance3D
	_floor_light = get_node_or_null(floor_light) as Light3D
	var world_env := get_node_or_null(world_environment) as WorldEnvironment
	if world_env:
		_env = world_env.environment
	if _env:
		# con BG la energía del ambiente no ilumina nada; con COLOR sí
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	for side in ["left", "right"]:
		var panel: MeshInstance3D = _panels.get(side)
		if panel == null or panel.mesh == null:
			continue
		var aabb: AABB = panel.mesh.get_aabb()
		_base[side] = panel.global_transform
		_aabb[side] = aabb
		# el borde exterior del panel es el pivote al recogerlo:
		# el izquierdo se junta a la izquierda, el derecho a la derecha
		var edge_x: float = aabb.position.x if side == "left" else aabb.position.x + aabb.size.x
		_pivot[side] = Vector3(edge_x, aabb.position.y + aabb.size.y * 0.5,
			aabb.position.z + aabb.size.z * 0.5)
	_compute_slide()
	_aim_outside_light()
	_block_glass_shadow()
	load_settings()
	_apply_all()
	set_active(false)

## El cristal de la ventana ocupa todo el hueco: si proyecta sombra se
## comporta como un muro opaco y no entra nada de luz. Se le quita la
## proyección para que el haz solo lo modele el marco y las cortinas.
func _block_glass_shadow() -> void:
	var glass := get_node_or_null(window_glass) as MeshInstance3D
	if glass:
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func set_active(on: bool) -> void:
	_active = on
	_set_hover(false)

func get_brightness() -> float:
	return _open_target

func set_brightness(value: float) -> void:
	_open_target = clampf(value, OPEN_MIN, OPEN_MAX)
	_open = _open_target
	_apply_all()
	save_settings()

func _process(delta: float) -> void:
	if _active:
		_update_hover()
	if not is_equal_approx(_open, _open_target):
		_open = move_toward(_open, _open_target, OPEN_SPEED * delta)
		_apply_all()

func _input(event: InputEvent) -> void:
	if not _active or not _hover:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
	var down := mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
	if not up and not down:
		return
	_open_target = clampf(_open_target + (OPEN_STEP if up else -OPEN_STEP),
		OPEN_MIN, OPEN_MAX)
	save_settings()
	get_viewport().set_input_as_handled()

## Los paneles se cruzan en el hueco entre los dos, a medio camino
## entre sus bordes libres, para que al cerrarse no queden rendijas.
func _compute_slide() -> void:
	if not _base.has("left") or not _base.has("right"):
		return
	var left_box: AABB = _base["left"] * _aabb["left"]
	var right_box: AABB = _base["right"] * _aabb["right"]
	var left_inner: float = left_box.position.x + left_box.size.x
	var right_inner: float = right_box.position.x
	var meet := (left_inner + right_inner) * 0.5
	_slide["left"] = meet - left_inner
	_slide["right"] = meet - right_inner

## Apunta la luz exterior desde fuera de la casa hacia el centro de la
## ventana, para que se vea claramente de dónde entra la luz.
func _aim_outside_light() -> void:
	if _outside_light == null:
		return
	var target := Vector3(0.42, 0.15, 2.1)
	if _base.has("left") and _base.has("right"):
		var left_box: AABB = _base["left"] * _aabb["left"]
		var right_box: AABB = _base["right"] * _aabb["right"]
		var center := (left_box.get_center() + right_box.get_center()) * 0.5
		target = Vector3(center.x, 0.15, center.z - 0.4)
	if _outside_light.global_position.distance_squared_to(target) > 0.0001:
		_outside_light.look_at(target)

func _update_hover() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_set_hover(false)
		return
	_set_hover(_screen_rect(cam).grow(HOVER_MARGIN).has_point(
		get_viewport().get_mouse_position()))

func _screen_rect(cam: Camera3D) -> Rect2:
	var rect := Rect2()
	var first := true
	for side in ["left", "right"]:
		var panel: MeshInstance3D = _panels.get(side)
		if panel == null or not _aabb.has(side):
			continue
		var aabb: AABB = _aabb[side]
		for i in 8:
			var world: Vector3 = panel.global_transform * aabb.get_endpoint(i)
			if cam.is_position_behind(world):
				# detrás de la cámara la proyección no sirve: sin área
				return Rect2(Vector2(1e6, 1e6), Vector2.ZERO)
			var sp := cam.unproject_position(world)
			if first:
				rect = Rect2(sp, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(sp)
	return rect

func _set_hover(on: bool) -> void:
	# el hover solo habilita la rueda del ratón; la luz no depende de él
	_hover = on

func _apply_all() -> void:
	_apply_panels()
	_apply_lights()

func _apply_panels() -> void:
	for side in ["left", "right"]:
		var panel: MeshInstance3D = _panels.get(side)
		if panel == null or not _base.has(side):
			continue
		var base: Transform3D = _base[side]
		var pivot: Vector3 = _pivot[side]
		# se escala el ancho en el eje mundial X sin tocar la altura,
		# como si el paño se recogiera; el borde exterior no se mueve
		var scale_x := lerpf(1.0, SCRUNCH, _open)
		var new_basis: Basis = Basis.from_scale(Vector3(scale_x, 1.0, 1.0)) * base.basis
		var pivot_world: Vector3 = base * pivot
		var moved: Vector3 = pivot_world + Vector3(
			_slide[side] * (1.0 - _open), 0.0, 0.0)
		panel.global_transform = Transform3D(new_basis, moved - new_basis * _pivot[side])

func _apply_lights() -> void:
	if _outside_light:
		_outside_light.light_energy = lerpf(LIGHT_OUT_MIN, LIGHT_OUT_MAX, _open)
	if _spill_light:
		_spill_light.light_energy = lerpf(LIGHT_SPILL_MIN, LIGHT_SPILL_MAX, _open)
	if _fill_light:
		_fill_light.light_energy = lerpf(LIGHT_FILL_MIN, LIGHT_FILL_MAX, _open)
	if _floor_light:
		_floor_light.light_energy = lerpf(LIGHT_FLOOR_MIN, LIGHT_FLOOR_MAX, _open)
	if _env:
		_env.ambient_light_color = AMBIENT_COLOR
		_env.ambient_light_energy = lerpf(AMBIENT_MIN, AMBIENT_MAX, _open)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	if cfg.has_section_key(CONFIG_SECTION, CONFIG_KEY):
		_open = clampf(float(cfg.get_value(CONFIG_SECTION, CONFIG_KEY)), OPEN_MIN, OPEN_MAX)
		_open_target = _open

func save_settings() -> void:
	var cfg := ConfigFile.new()
	# si ya existía, esto conserva el resto de claves del archivo
	cfg.load(settings_path)
	cfg.set_value(CONFIG_SECTION, CONFIG_KEY, _open_target)
	cfg.save(settings_path)
