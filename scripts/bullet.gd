extends Area3D

## Bala con barrido por rayo: en cada tick de física lanza un rayo entre
## la posición anterior y la nueva. Con solo mover la bala (60 u/s ≈ 1
## u/tick) los huesos finos del zombi se atravesaban y el impacto se
## perdía; el rayo recorre el tramo entero y acierta cualquier hueso de
## la línea de disparo, devolviendo además el hueso concreto (y con él
## su zona y su daño).

const SPEED = 60.0
const RANGE = 40.0

@export var damage := 1

var travelled_distance = 0.0

func _physics_process(delta: float) -> void:
	var step := -global_transform.basis.z * SPEED * delta
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + step, collision_mask)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if is_instance_valid(collider) and collider.has_method("take_damage"):
			collider.take_damage(damage)
		queue_free()
		return
	global_position += step
	travelled_distance += SPEED * delta
	if travelled_distance > RANGE:
		queue_free()
