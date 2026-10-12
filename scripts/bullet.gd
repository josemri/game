extends Area3D

const SPEED = 60.0
const RANGE = 40.0

@export var damage := 1

var travelled_distance = 0.0

func _physics_process(delta: float):
	position += -transform.basis.z * SPEED * delta
	travelled_distance += SPEED * delta
	if travelled_distance > RANGE:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if is_instance_valid(body) and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
