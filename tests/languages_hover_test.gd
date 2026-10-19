extends SceneTree
## Test de regresión del selector de idiomas (scenes/languages.tscn).
## Simula las señales de ratón a mano y comprueba que ningún libro se queda
## nunca congelado a mitad de camino.
##
## Ejecutar:  godot --headless --path . -s res://tests/languages_hover_test.gd

const SCENE := "res://scenes/languages.tscn"

var langs: Node3D
var base := {}
var out_pose := {}
var checks := 0
var failures := 0

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _initialize() -> void:
	_run()

func _book(i: int) -> Node3D:
	return langs.get_node("language%d" % i)

func _enter(i: int) -> void:
	langs._on_area_3d_mouse_entered(i)

func _exit(i: int) -> void:
	langs._on_area_3d_mouse_exited(i)

func _close(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_to(b.origin) > 0.01:
		return false
	var q := a.basis.get_rotation_quaternion().inverse() * b.basis.get_rotation_quaternion()
	return absf(q.w) > 0.9999

func _check(label: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)

func _check_at_base(label: String, i: int) -> void:
	_check(label + ": language%d en su sitio" % i, _close(_book(i).transform, base[i]))

func _check_out(label: String, i: int) -> void:
	_check(label + ": language%d fuera" % i, _close(_book(i).transform, out_pose[i]))

func _check_all_at_base(label: String) -> void:
	for i in range(1, 7):
		_check_at_base(label, i)

func _run() -> void:
	await process_frame
	langs = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(langs)

	var ap: AnimationPlayer = langs.get_node("AnimationPlayer")
	for i in range(1, 7):
		base[i] = _book(i).transform
		var a: Animation = ap.get_animation("selected%d" % i)
		var pos: Vector3 = base[i].origin
		var quat: Quaternion = base[i].basis.get_rotation_quaternion()
		for t in a.get_track_count():
			var last := a.track_get_key_count(t) - 1
			match a.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					pos = a.track_get_key_value(t, last)
				Animation.TYPE_ROTATION_3D:
					quat = a.track_get_key_value(t, last)
		out_pose[i] = Transform3D(Basis(quat), pos)

	# --- 1) El bug original: salir de un select antes de que termine la espera ---
	_enter(1)
	await _wait(0.2)
	_exit(1)
	_enter(2)
	await _wait(1.3)
	_check_out("1) cambio antes del retardo", 2)
	_check_at_base("1) cambio antes del retardo", 1)
	_exit(2)
	await _wait(0.8)
	_check_all_at_base("1) tras salir")

	# --- 2) Cambiar de select con el libro ya fuera ---
	_enter(1)
	await _wait(1.0)
	_check_out("2) libro 1 seleccionado", 1)
	_exit(1)
	_enter(2)
	await _wait(1.3)
	_check_at_base("2) libro 1 devuelto", 1)
	_check_out("2) libro 2 seleccionado", 2)
	_exit(2)
	await _wait(0.8)
	_check_all_at_base("2) tras salir")

	# --- 3) Tantear varios selects dentro del retardo ---
	_enter(1)
	await _wait(0.25)
	_exit(1)
	_enter(2)
	await _wait(0.25)
	_exit(2)
	_enter(3)
	await _wait(1.3)
	_check_out("3) libro 3 seleccionado", 3)
	_check_at_base("3) libro 1 sin animar", 1)
	_check_at_base("3) libro 2 sin animar", 2)
	_exit(3)
	await _wait(0.8)
	_check_all_at_base("3) tras salir")

	# --- 4) Solapamiento: entro en 3 sin salir de 2 (los bounding boxes se pisan) ---
	_enter(2)
	await _wait(0.1)
	_enter(3)
	await _wait(0.1)
	_exit(2)
	await _wait(1.3)
	_check_out("4) libro 3 sigue seleccionado", 3)
	_check_at_base("4) libro 2 devuelto", 2)
	_exit(3)
	await _wait(0.8)
	_check_all_at_base("4) tras salir")

	# --- 5) Salir con la animación a mitad de camino (típico libro congelado) ---
	_enter(4)
	await _wait(0.55) # la animación acaba de empezar
	_exit(4)
	await _wait(0.8)
	_check_all_at_base("5) salida a mitad de animación")

	# --- 6) Cadena rápida: fuera -> libro 2 a mitad -> libro 3 ---
	_enter(1)
	await _wait(0.6)
	_exit(1)
	_enter(2)
	await _wait(0.55) # el libro 2 está saliendo
	_exit(2)
	_enter(3)
	await _wait(1.4)
	_check_at_base("6) libro 1 devuelto", 1)
	_check_at_base("6) libro 2 devuelto a mitad", 2)
	_check_out("6) libro 3 seleccionado", 3)
	_exit(3)
	await _wait(0.8)
	_check_all_at_base("6) tras salir")

	# --- 7) Barrido rápido por los seis selects y reposo en el último ---
	for i in range(1, 6):
		_enter(i)
		await _wait(0.05)
		_exit(i)
	_enter(6)
	await _wait(1.3)
	_check_out("7) libro 6 seleccionado", 6)
	for i in range(1, 6):
		_check_at_base("7) libro %d sin animar" % i, i)
	_exit(6)
	await _wait(0.8)
	_check_all_at_base("7) todos en su sitio")

	print("")
	print("%d comprobaciones, %d fallos" % [checks, failures])
	quit(1 if failures > 0 else 0)
