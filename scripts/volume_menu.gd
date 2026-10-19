extends Node3D

## Menú de volumen integrado en la radio (al estilo del menú de idiomas).
##
## La radio tiene dos ruedas:
##   - `../volume_selector`: elige qué bus de audio se va a cambiar.
##   - `../volume`:          sube o baja el volumen del bus elegido.
## Se giran pasando el ratón por encima y usando la rueda del ratón.
## Los valores se guardan en `settings_path` para la próxima partida.

const BUSES := ["Master", "Music", "SFX", "Voice"]

const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "audio"

## Volumen lineal mínimo/máximo y salto por muesca de la rueda.
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
const VOLUME_STEP := 0.05
## Recorrido visual de la rueda de valor, en grados, de 0 a 100 %.
const VALUE_TRAVEL := 270.0
## Giro de la rueda selectora por cada cambio de bus, en grados.
const SELECT_TRAVEL := 90.0

## Radio (en unidades de mundo) alrededor de cada rueda que acepta el ratón.
const HIT_RADIUS := 0.055
## Cuánto sobresale la rueda al pasarle el ratón por encima.
const POP_DISTANCE := 0.012
## Velocidades de animación de las ruedas.
const TURN_SPEED := 900.0     # grados por segundo
const POP_SPEED := 0.12       # unidades por segundo

const COLOR_IDLE := Color(0.62, 0.58, 0.52)
const COLOR_HOVER := Color(1.0, 0.94, 0.78)

@export var value_knob: NodePath = ^"../volume"
@export var selector_knob: NodePath = ^"../volume_selector"
@export var settings_path: String = CONFIG_PATH

@onready var _value_mesh: MeshInstance3D = get_node_or_null(value_knob) as MeshInstance3D
@onready var _selector_mesh: MeshInstance3D = get_node_or_null(selector_knob) as MeshInstance3D
@onready var _select_label: Label3D = $select_label
@onready var _value_label: Label3D = $value_label

var _active := false
var _hover := ""
var _buses: Array[String] = []
var _bus := 0
var _volumes := {}
var _base := {}
var _center := {}
var _angle := {}
var _angle_target := {}
var _pop := {}
var _pop_target := {}

func _ready() -> void:
	_buses = _detect_buses()
	if _buses.is_empty():
		_buses = ["Master"]
	if _value_mesh:
		_base["value"] = _value_mesh.transform
		_center["value"] = _value_mesh.transform * _value_mesh.mesh.get_aabb().get_center()
	if _selector_mesh:
		_base["selector"] = _selector_mesh.transform
		_center["selector"] = _selector_mesh.transform * _selector_mesh.mesh.get_aabb().get_center()
	for which in ["value", "selector"]:
		_angle[which] = 0.0
		_angle_target[which] = 0.0
		_pop[which] = 0.0
		_pop_target[which] = 0.0
	for bus in _buses:
		_volumes[bus] = 1.0
	load_settings()
	apply_to_audio_server()
	_bus = 0
	_angle["selector"] = _selector_angle()
	_angle_target["selector"] = _angle["selector"]
	_angle["value"] = _value_angle()
	_angle_target["value"] = _angle["value"]
	_update_labels()
	set_active(false)
	_apply("value")
	_apply("selector")

func set_active(on: bool) -> void:
	_active = on
	if _select_label:
		_select_label.visible = on
	if _value_label:
		_value_label.visible = on
	_hover = ""
	if not on:
		for which in ["value", "selector"]:
			_pop_target[which] = 0.0

func _process(delta: float) -> void:
	if _active:
		_update_hover()
	_animate(delta)

func _input(event: InputEvent) -> void:
	if not _active or _hover.is_empty():
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
	var down := mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
	if not up and not down:
		return
	if _hover == "selector":
		# rueda abajo: siguiente bus
		_turn_selector(1 if down else -1)
	elif _hover == "value":
		# rueda arriba: subir el volumen
		_turn_value(1 if up else -1)
	get_viewport().set_input_as_handled()

func _detect_buses() -> Array[String]:
	var res: Array[String] = []
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) >= 0:
			res.append(bus)
	return res

func _knob_at(cam: Camera3D, pos: Vector2) -> String:
	var best := ""
	var best_d := 1e18
	for which in ["value", "selector"]:
		if not _center.has(which):
			continue
		var c: Vector3 = _center[which]
		if cam.is_position_behind(c):
			continue
		var sp := cam.unproject_position(c)
		if not get_viewport().get_visible_rect().has_point(sp):
			continue
		var r := _screen_radius(cam, c)
		var d := pos.distance_to(sp)
		if d <= r and d < best_d:
			best = which
			best_d = d
	return best

func _screen_radius(cam: Camera3D, world_center: Vector3) -> float:
	var p0 := cam.unproject_position(world_center)
	var right := cam.global_transform.basis.x.normalized()
	var p1 := cam.unproject_position(world_center + right * HIT_RADIUS)
	return p0.distance_to(p1)

func _update_hover() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_set_hover(_knob_at(cam, get_viewport().get_mouse_position()))

func _set_hover(which: String) -> void:
	if which == _hover:
		return
	_hover = which
	for w in ["value", "selector"]:
		_pop_target[w] = 1.0 if w == which else 0.0
	_update_label_colors()

func _animate(delta: float) -> void:
	for which in ["value", "selector"]:
		if not _angle.has(which):
			continue
		var a: float = _angle[which]
		var at: float = _angle_target.get(which, a)
		var p: float = _pop[which]
		var pt: float = _pop_target.get(which, p)
		var na: float = move_toward(a, at, TURN_SPEED * delta)
		var np: float = move_toward(p, pt, POP_SPEED * delta)
		if not is_equal_approx(na, a) or not is_equal_approx(np, p):
			_angle[which] = na
			_pop[which] = np
			_apply(which)

func _apply(which: String) -> void:
	var mesh: MeshInstance3D = _value_mesh if which == "value" else _selector_mesh
	if mesh == null:
		return
	if not _base.has(which):
		return
	var t: Transform3D = _base[which]
	t = t.rotated_local(Vector3.UP, deg_to_rad(_angle.get(which, 0.0)))
	t = t.translated_local(Vector3(0, -POP_DISTANCE * float(_pop.get(which, 0.0)), 0))
	mesh.transform = t

func _turn_selector(dir: int) -> void:
	_bus = wrapi(_bus + dir, 0, _buses.size())
	_angle_target["selector"] += float(dir) * SELECT_TRAVEL
	_angle["value"] = _value_angle()
	_angle_target["value"] = _angle["value"]
	_update_labels()
	save_settings()

func _turn_value(dir: int) -> void:
	var bus_name := _current_bus_name()
	if bus_name.is_empty():
		return
	var v: float = _volumes.get(bus_name, 1.0)
	v = clampf(v + float(dir) * VOLUME_STEP, VOLUME_MIN, VOLUME_MAX)
	_volumes[bus_name] = v
	# sólo la consigna: la rueda gira hasta ella sola
	_angle_target["value"] = _value_angle()
	apply_to_audio_server()
	_update_labels()
	save_settings()

func _current_bus_name() -> String:
	if _bus < 0 or _bus >= _buses.size():
		return ""
	return _buses[_bus]

func _selector_angle() -> float:
	return float(_bus) * SELECT_TRAVEL

func _value_angle() -> float:
	var v: float = _volumes.get(_current_bus_name(), 1.0)
	return -VALUE_TRAVEL * 0.5 + v * VALUE_TRAVEL

func _update_labels() -> void:
	_select_label.text = _current_bus_name().to_upper()
	var v: float = _volumes.get(_current_bus_name(), 1.0)
	_value_label.text = "%d%%" % roundi(v * 100.0)
	_update_label_colors()

func _update_label_colors() -> void:
	_select_label.modulate = COLOR_HOVER if _hover == "selector" else COLOR_IDLE
	_value_label.modulate = COLOR_HOVER if _hover == "value" else COLOR_IDLE

func apply_to_audio_server() -> void:
	for bus in _buses:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var v: float = _volumes.get(bus, 1.0)
		if v <= 0.0001:
			AudioServer.set_bus_mute(idx, true)
			AudioServer.set_bus_volume_db(idx, -80.0)
		else:
			AudioServer.set_bus_mute(idx, false)
			AudioServer.set_bus_volume_db(idx, linear_to_db(v))

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for bus in _buses:
		if cfg.has_section_key(CONFIG_SECTION, bus):
			var val := float(cfg.get_value(CONFIG_SECTION, bus))
			_volumes[bus] = clampf(val, VOLUME_MIN, VOLUME_MAX)
	# la rueda de valor pasa al volumen recién cargado
	if _angle.has("value"):
		_angle["value"] = _value_angle()
		_angle_target["value"] = _angle["value"]
	_update_labels()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	# si ya existía, esto conserva el resto de claves del archivo
	cfg.load(settings_path)
	for bus in _buses:
		cfg.set_value(CONFIG_SECTION, bus, _volumes[bus])
	cfg.save(settings_path)
