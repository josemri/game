extends CharacterBody3D

## IA del zombi: persigue al jugador por la malla de navegación, ataca
## en rango y reacciona a los impactos por zonas del cuerpo.
##
## La máquina de estados del AnimationTree se maneja con condiciones
## (todas las transiciones son ADVANCE_MODE_AUTO; las de retorno a run
## esperan al final de la animación con switch_mode AT_END):
##   - "run" solo está encendido mientras persigue; se apaga al entrar
##     en un ataque y se vuelve a encender cuando el temporizador del
##     ataque expira. Así la transición attack -> run no queda armada
##     antes de tiempo y el golpe se reproduce entero.
##   - "attack"/"bite" se apagan con un temporizador igual a la duración
##     de la animación: el ataque se reproduce entero y el retorno a la
##     persecución es el previsto por la máquina de estados.
##   - "hit"/"hit_headshot" son pulsos de HIT_PULSE_TIME; se apagan a
##     mitad del retroceso para no reencadenarlo en bucle.
##   - La muerte tiene transición desde todos los estados (incluidos los
##     retrocesos y la entrada), así que matar en pleno impacto funciona.

const ATTACK_RANGE = 2.5
const ATTACK_COOLDOWN := 0.8   # pausa entre ataques: deja ventana para huir
const HIT_PULSE_TIME := 0.5
const REPATH_INTERVAL := 0.25
const TURN_SPEED := 5.0
const ATTACK_TURN_SPEED := 8.0
const ATTACK_STATES = ["attack", "bite"]

@export var player_path: NodePath
@export var speed := 3.0
@export var health := 6

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var skeleton: Skeleton3D = $Armature/Skeleton3D
@onready var mesh_instance: MeshInstance3D = $Armature/Skeleton3D/mesh

# Dinámico a propósito: el jugador real (plyr.gd) expone hit(dir), que
# no existe en Node3D y no compilaría con variable tipada.
var player
var state_machine: AnimationNodeStateMachinePlayback
var is_dead := false
var rng := RandomNumberGenerator.new()

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _attack_timer := 0.0
var _attack_cooldown := 0.0
var _repath_timer := 0.0
var _hit_timer := -1.0

func _ready() -> void:
	rng.randomize()
	player = get_node_or_null(player_path)
	state_machine = anim_tree.get("parameters/playback")

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if is_dead or not is_instance_valid(player):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	match state_machine.get_current_node():
		"zombie_run":
			_chase(delta)
		"zombie_attack", "zombie_bite":
			_face_player(delta, ATTACK_TURN_SPEED)
			velocity.x = 0.0
			velocity.z = 0.0
		_:
			velocity.x = 0.0
			velocity.z = 0.0
	move_and_slide()

func _chase(delta: float) -> void:
	# La condición "run" debe estar encendida mientras se persigue: es
	# la que arma la transición attack -> run al final del golpe.
	anim_tree["parameters/conditions/run"] = true
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		nav_agent.target_position = player.global_position
		_repath_timer = REPATH_INTERVAL

	if _target_in_range():
		velocity.x = 0.0
		velocity.z = 0.0
		_face_player(delta, ATTACK_TURN_SPEED)
		if _attack_timer <= 0.0 and _attack_cooldown <= 0.0:
			_start_attack()
		return

	var dir := nav_agent.get_next_path_position() - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var flat := dir.normalized() * speed
	velocity.x = flat.x
	velocity.z = flat.z
	rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), delta * TURN_SPEED)

func _start_attack() -> void:
	var which: String = ATTACK_STATES[rng.randi_range(0, ATTACK_STATES.size() - 1)]
	# "run" se apaga al entrar al ataque: la transición attack -> run
	# (condición "run", switch AT_END) no debe estar armada durante el
	# golpe, solo al final de la animación.
	anim_tree["parameters/conditions/run"] = false
	anim_tree["parameters/conditions/" + which] = true
	_attack_timer = _anim_length(which)

func _end_attack() -> void:
	anim_tree["parameters/conditions/attack"] = false
	anim_tree["parameters/conditions/bite"] = false
	_attack_cooldown = ATTACK_COOLDOWN
	# Solo reactiva "run" si seguimos dentro del ataque; si una bala nos
	# sacó de él, el retorno lo hace la transición AT_END de take_hit.
	var node := String(state_machine.get_current_node())
	if node == "zombie_attack" or node == "zombie_bite":
		anim_tree["parameters/conditions/run"] = true

func _tick_timers(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = 0.0
			_end_attack()
	if _hit_timer > 0.0:
		_hit_timer -= delta
		if _hit_timer <= 0.0:
			_hit_timer = 0.0
			anim_tree["parameters/conditions/hit"] = false
			anim_tree["parameters/conditions/hit_headshot"] = false

func _face_player(delta: float, turn_speed: float) -> void:
	# Tipado explícito: player es Variant (método hit() ajeno a Node3D).
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-to_player.x, -to_player.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * turn_speed, 0.0, 1.0))

func _anim_length(key: String) -> float:
	var library := anim_player.get_animation_library("zombie")
	if library.has_animation(key):
		return library.get_animation(key).length
	return 1.0

func _target_in_range() -> bool:
	return global_position.distance_to(player.global_position) < ATTACK_RANGE

func _hit_finished():
	if not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) < ATTACK_RANGE + 1.0:
		var dir = global_position.direction_to(player.global_position)
		player.hit(dir)

func _on_body_part_hit(damage: int, body_part: String) -> void:
	if is_dead:
		return
	health -= damage
	print("[Zombi] Impacto en %s | daño %d | vida restante %d" % [body_part, damage, health])
	if health <= 0:
		_die(body_part == "head")
		return
	# Un retroceso en curso no se reencadena: el daño ya se ha aplicado
	# y el print anterior lo refleja.
	if _hit_timer > 0.0:
		return
	var cond := "hit_headshot" if body_part == "head" else "hit"
	anim_tree["parameters/conditions/" + cond] = true
	_hit_timer = HIT_PULSE_TIME

func _die(is_headshot: bool) -> void:
	is_dead = true
	velocity.x = 0.0
	velocity.z = 0.0
	_attack_timer = 0.0
	# Limpia todas las condiciones para que la muerte no dependa del
	# estado desde el que se dispare.
	for key in ["attack", "bite", "hit", "hit_headshot", "run"]:
		anim_tree["parameters/conditions/" + key] = false
	anim_tree["parameters/conditions/" + ("die_headshot" if is_headshot else "die")] = true
	await get_tree().create_timer(10.0).timeout
	spawn_baked_corpse()
	queue_free()

func spawn_baked_corpse():
	var baked_mesh: ArrayMesh = mesh_instance.bake_mesh_from_current_skeleton_pose()
	var corpse_mesh := MeshInstance3D.new()
	corpse_mesh.mesh = baked_mesh
	corpse_mesh.global_transform = mesh_instance.global_transform
	for i in baked_mesh.get_surface_count():
		corpse_mesh.set_surface_override_material( i, mesh_instance.get_active_material(i) )
	get_tree().current_scene.add_child(corpse_mesh)
