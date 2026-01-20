extends CharacterBody3D

var player = null
var state_machine
var SPEED = 3
const ATTACK_RANGE = 2.5
var health = 6
var attack_states = ["attack", "bite"]

@export var player_path : NodePath
@onready var nav_agent = $NavigationAgent3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var skeleton: Skeleton3D = $Armature/Skeleton3D
@onready var mesh_instance: MeshInstance3D = $Armature/Skeleton3D/mesh

var is_dead := false

func _ready() -> void:
	player = get_node(player_path)
	state_machine = anim_tree.get("parameters/playback")

func _process(delta: float) -> void:
	velocity = Vector3.ZERO

	if _target_in_range() && !attack_states.any(func(a): return anim_tree["parameters/conditions/" + a]):
		anim_tree["parameters/conditions/" + _choose_random_attack()] = true
	else:
		for attack in attack_states:
			anim_tree["parameters/conditions/" + attack] = false
		anim_tree["parameters/conditions/run"] = true
	match state_machine.get_current_node():
		"zombie_run":
			nav_agent.set_target_position(player.global_transform.origin)
			var next_nav_pint = nav_agent.get_next_path_position()
			velocity = (next_nav_pint - global_transform.origin).normalized() * SPEED
			rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), delta*5.0)
		"zombie_attack", "zombie_bite":
			look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
			# state_machine.travel("zombie_run")
	move_and_slide()


func _choose_random_attack() -> String:
	return attack_states[randi() % attack_states.size()]

func _target_in_range():
	return global_position.distance_to(player.global_position) < ATTACK_RANGE

func _hit_finished():
	if global_position.distance_to(player.global_position) < ATTACK_RANGE + 1.0:
		var dir = global_position.direction_to(player.global_position)
		player.hit(dir)

func _on_body_part_hit(damage, body_part) -> void:
	health -= damage
	print("Body part:", body_part, ", Damage:", damage)
	
	if health <= 0 and not is_dead:
		is_dead = true
		velocity = Vector3.ZERO
		set_physics_process(false)
		set_process(false)

		if body_part == "head":
			anim_tree.set("parameters/conditions/die_headshot", true)
		else:
			anim_tree.set("parameters/conditions/die", true)
		await get_tree().create_timer(10.0).timeout
		spawn_baked_corpse()
		queue_free()

	else:
		if body_part == "head":
			anim_tree.set("parameters/conditions/hit_headshot", true)
			await get_tree().create_timer(0.5).timeout
			anim_tree.set("parameters/conditions/hit_headshot", false)
		else:
			anim_tree.set("parameters/conditions/hit", true)
			await get_tree().create_timer(0.5).timeout
			anim_tree.set("parameters/conditions/hit", false)

func spawn_baked_corpse():
	var baked_mesh: ArrayMesh = mesh_instance.bake_mesh_from_current_skeleton_pose()
	var corpse_mesh := MeshInstance3D.new()
	corpse_mesh.mesh = baked_mesh
	corpse_mesh.global_transform = mesh_instance.global_transform
	for i in baked_mesh.get_surface_count():
		corpse_mesh.set_surface_override_material( i, mesh_instance.get_active_material(i) )
	get_tree().current_scene.add_child(corpse_mesh)
