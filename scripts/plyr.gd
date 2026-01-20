extends CharacterBody3D

@export var walk_speed := 4.0
@export var run_speed := 7.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.2
@onready var gun_anim: AnimationPlayer = $Camera3D/gun/AnimationPlayer

var HIT_STAGGER = 8.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func hit(dir):
	velocity += dir * HIT_STAGGER
	$Camera3D/CanvasLayer/ColorRect.visible = true
	await get_tree().create_timer(0.2).timeout
	$Camera3D/CanvasLayer/ColorRect.visible = false


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotation_degrees.y -= event.relative.x * mouse_sensitivity
		$Camera3D.rotation_degrees.x -= event.relative.y * mouse_sensitivity
		$Camera3D.rotation_degrees.x = clamp(
			$Camera3D.rotation_degrees.x,
			-80.0,
			80.0
		)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float):
	# Gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Salto
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Movimiento
	var speed = run_speed if Input.is_action_pressed("run") else walk_speed
	var input_dir = Input.get_vector("move_right","move_left","move_back","move_forward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
	
	if Input.is_action_just_pressed("shoot"):
		shoot_bullet()
	
	
func shoot_bullet():
	if !gun_anim.is_playing():
		gun_anim.play("shoot")
		const BULLET_3D = preload("res://scenes/bullet.tscn")
		var new_bullet = BULLET_3D.instantiate()
		%Marker3D.add_child(new_bullet)
		new_bullet.global_transform = %Marker3D.global_transform
