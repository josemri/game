extends SceneTree
## Tests del zombi: cadena de introducción (Start -> wake up -> scream2
## -> run), persecución por la malla de navegación, ataques con retorno,
## retrocesos con fundido, muerte desde cualquier estado y daño por
## zonas del cuerpo (incluido el barrido de bala sin tunneling).
##
## Ejecutar:  godot --headless --path . -s res://tests/zombie_test.gd

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

var checks := 0
var failures := 0

## Jugador de mentira: solo hace falta global_position y hit(dir).
class StubPlayer extends Node3D:
	var hits := 0
	func hit(_dir) -> void:
		hits += 1

func _check(label: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("PASS  " + label)
	else:
		failures += 1
		print("FAIL  " + label)

func _initialize() -> void:
	_run()

func _node_of(z) -> String:
	return String(z.state_machine.get_current_node())

func _spawn(z, pos: Vector3, player) -> Node:
	# Ruta absoluta: dentro de _initialize los nodos aún no tienen árbol
	# y get_path() fallaría.
	z.player_path = NodePath("/root/" + player.name)
	z.position = pos
	root.add_child(z)
	return z

func _run() -> void:
	# -------------------------------------------------- escenario base
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)

	var nav := NavigationMesh.new()
	nav.set_vertices(PackedVector3Array([
		Vector3(-20, 0, -20), Vector3(20, 0, -20),
		Vector3(20, 0, 20), Vector3(-20, 0, 20)]))
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nav
	root.add_child(region)

	var player := StubPlayer.new()
	player.name = "StubPlayer"
	player.position = Vector3(8, 0, 0)
	root.add_child(player)

	# -------------------------------------------------- 1) zonas por hueso
	var zombie = _spawn(ZOMBIE_SCENE.instantiate(), Vector3(0, 0.1, 0), player)
	await create_timer(0.2).timeout
	var sim = zombie.get_node("Armature/Skeleton3D/PhysicalBoneSimulator3D")
	var expected := {
		"mixamorig_Head": ["head", 3],
		"mixamorig_Neck": ["torso", 2],
		"mixamorig_Spine1": ["torso", 2],
		"mixamorig_Hips": ["torso", 2],
		"mixamorig_LeftForeArm": ["arm", 1],
		"mixamorig_RightHandIndex2": ["arm", 1],
		"mixamorig_LeftUpLeg": ["leg", 1],
		"mixamorig_RightToeBase": ["leg", 1],
	}
	var bone_total := 0
	for b in sim.get_children():
		if b is PhysicalBone3D:
			bone_total += 1
	_check("1) los 28 huesos físicos están en la escena", bone_total == 28)
	for bone_name in expected:
		var bone = sim.get_node("Physical Bone " + bone_name)
		var want: Array = expected[bone_name]
		_check("1) %s -> zona %s / daño %d" % [bone_name, want[0], want[1]],
			bone.body_part == want[0] and bone.damage == want[1])

	# -------------------------------------------------- 2) señal por zona
	var lab = _spawn(ZOMBIE_SCENE.instantiate(), Vector3(-8, 0.1, -8), player)
	lab.speed = 0.0
	await create_timer(0.2).timeout
	var lab_sim = lab.get_node("Armature/Skeleton3D/PhysicalBoneSimulator3D")
	lab_sim.get_node("Physical Bone mixamorig_Head").take_damage(1)
	lab_sim.get_node("Physical Bone mixamorig_Spine1").take_damage(1)
	_check("2) la cabeza hace 3 y el torso 2 con bala estándar", lab.health == 1)
	await create_timer(0.1).timeout
	# El golpe de cabeza enciende hit_headshot (el de torso llega con el
	# pulso activo y solo añade daño, sin reencadenar otro retroceso).
	_check("2) el zombi entra en retroceso de cabeza por la señal",
		_node_of(lab) == "zombie_take_hit_headshot")
	lab.queue_free()

	# -------------------------------------------------- 3) intro y navmesh
	_check("3) la intro arranca (wake up tras Start)", _node_of(zombie) == "zombie_wake up")
	await create_timer(3.4).timeout   # t≈3.6: wake up (3.0 s) ya terminó
	_check("3) scream2 espera a que termine wake up (AT_END)",
		_node_of(zombie) == "zombie_scream2")
	# El crossfade solapa animaciones: scream2 arranca antes del final
	# exacto de wake up, así que run aparece sobre t≈4.5 s.
	await create_timer(1.3).timeout   # t≈5.1: scream2 (2.67 s) ya terminó
	_check("3) run espera a que termine scream2 (AT_END)", _node_of(zombie) == "zombie_run")

	var pos_before: Vector3 = zombie.global_position
	await create_timer(1.5).timeout
	_check("3) persigue por la malla (recorre >1 m en 1.5 s)",
		zombie.global_position.distance_to(pos_before) > 1.0)
	_check("3) se acerca al jugador (distancia < 8 m)",
		zombie.global_position.distance_to(player.global_position) < 8.0)

	# -------------------------------------------------- 4) ataque y retorno
	var saw_attack := false
	var saw_return := false
	for i in 80:   # hasta ~8 s
		await create_timer(0.1).timeout
		var n := _node_of(zombie)
		if n == "zombie_attack" or n == "zombie_bite":
			saw_attack = true
		if saw_attack and n == "zombie_run":
			saw_return = true
			break
	_check("4) ataca al jugador en rango (attack/bite)", saw_attack)
	_check("4) el ataque termina y vuelve a perseguir", saw_return)
	await create_timer(0.3).timeout
	_check("4) el golpe del ataque daña al jugador (method track)",
		player.hits >= 1)

	# -------------------------------------------------- 5) retroceso cuerpo
	zombie._on_body_part_hit(2, "torso")
	_check("5) un impacto en torso quita 2 (vida 6 -> 4)", zombie.health == 4)
	_check("5) enciende la condición hit",
		zombie.anim_tree["parameters/conditions/hit"] == true)
	# Entrada con sondeo: un impacto que cae en mitad de un crossfade
	# (≤0.3 s) retrasa la transición y una única lectura a t+0.3 fallaría.
	var flinched := false
	for i in 5:
		if _node_of(zombie) == "zombie_take_hit":
			flinched = true
			break
		await create_timer(0.1).timeout
	_check("5) entra en take_hit (está en %s)" % _node_of(zombie), flinched)
	# El pulso dura 0.5 s desde el golpe: se sondea hasta verlo apagado
	# para no medir justo en el frame límite.
	var pulse_off := false
	for i in 6:
		if zombie.anim_tree["parameters/conditions/hit"] == false:
			pulse_off = true
			break
		await create_timer(0.1).timeout
	_check("5) la condición hit se apaga sola a mitad del retroceso (en %s)"
		% _node_of(zombie),
		pulse_off and _node_of(zombie) == "zombie_take_hit")
	await create_timer(1.1).timeout   # > entrada + take_hit (1.2 s)
	_check("5) el retroceso termina en AT_END (no se queda clavado)",
		_node_of(zombie) != "zombie_take_hit")

	# -------------------------------------------------- 6) retroceso cabeza
	await create_timer(0.3).timeout   # asegura que el pulso anterior expiró
	zombie._on_body_part_hit(3, "head")
	_check("6) un impacto en cabeza quita 3 (vida 4 -> 1)", zombie.health == 1)
	_check("6) enciende hit_headshot en lugar de hit",
		zombie.anim_tree["parameters/conditions/hit_headshot"] == true
		and zombie.anim_tree["parameters/conditions/hit"] == false)
	var head_flinched := false
	for i in 5:
		if _node_of(zombie) == "zombie_take_hit_headshot":
			head_flinched = true
			break
		await create_timer(0.1).timeout
	_check("6) entra en take_hit_headshot (está en %s)" % _node_of(zombie),
		head_flinched)
	await create_timer(1.6).timeout   # > take_hit_headshot (1.53 s)
	_check("6) el retroceso de cabeza termina en AT_END",
		_node_of(zombie) != "zombie_take_hit_headshot")

	# -------------------------------------------------- 7) muerte desde run
	zombie._on_body_part_hit(99, "torso")
	_check("7) la muerte clama la IA (is_dead)", zombie.is_dead == true)
	_check("7) limpia el resto de condiciones",
		zombie.anim_tree["parameters/conditions/hit"] == false
		and zombie.anim_tree["parameters/conditions/run"] == false)
	await create_timer(0.5).timeout
	_check("7) entra en la animación de muerte (está en %s)" % _node_of(zombie),
		_node_of(zombie) == "zombie_die")
	var health_at_death: int = zombie.health
	zombie._on_body_part_hit(5, "head")
	_check("7) los impactos tras la muerte se ignoran", zombie.health == health_at_death)

	# -------------------------------------------------- 8) muerte en retroceso
	var z2 = _spawn(ZOMBIE_SCENE.instantiate(), Vector3(-8, 0.1, 8), player)
	await create_timer(0.8).timeout   # en wake up
	z2._on_body_part_hit(2, "torso")   # retroceso en plena entrada (wake up)
	await create_timer(0.3).timeout
	_check("8) wake up -> take_hit (transición añadida)", _node_of(z2) == "zombie_take_hit")
	z2._on_body_part_hit(99, "head")   # letal en pleno retroceso
	_check("8) la muerte durante el retroceso se registra", z2.is_dead == true)
	_check("8) usa la muerte por headshot", z2.anim_tree["parameters/conditions/die_headshot"] == true)
	await create_timer(0.5).timeout
	_check("8) take_hit -> die_headshot (transición añadida)",
		_node_of(z2) == "zombie_die_headshot")

	# -------------------------------------------------- 9) bala sin tunneling
	# Congela el esqueleto en la pose de reposo (T-pose) antes del primer
	# fotograma y apunta a la mano desde fuera del brazo: hueso fino que
	# el código anterior (solo solapes) perdía al saltárselo de 1 en 1.
	var z3 = ZOMBIE_SCENE.instantiate()
	z3.player_path = player.get_path()
	z3.position = Vector3(8, 0.1, -8)
	root.add_child(z3)
	z3.anim_tree.active = false
	await create_timer(0.3).timeout
	var sim3 = z3.get_node("Armature/Skeleton3D/PhysicalBoneSimulator3D")
	var hand = sim3.get_node("Physical Bone mixamorig_LeftHand")
	var arm_dir: Vector3 = (hand.global_position
		- sim3.get_node("Physical Bone mixamorig_LeftForeArm").global_position).normalized()
	var zone_hits: Array = []
	hand.body_part_hit.connect(func(d, p): zone_hits.append([d, p]))
	var bullet := BULLET_SCENE.instantiate()
	root.add_child(bullet)
	bullet.global_position = hand.global_position + arm_dir * 1.2
	bullet.look_at(hand.global_position, Vector3.UP)   # dirección horizontal: sin colinealidad
	await create_timer(0.5).timeout
	_check("9) la bala acierta al hueso fino sin superposición (sin tunneling)",
		zone_hits == [[1, "arm"]])
	_check("9) la zona del brazo aplica su daño al zombi (vida 6 -> 5)",
		z3.health == 5)

	# -------------------------------------------------- resumen
	print("")
	print("zombie_test: %d comprobaciones, %d fallos" % [checks, failures])
	quit(1 if failures > 0 else 0)
