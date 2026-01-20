extends PhysicalBone3D

@export var damage :=1
@export var body_part := "body" # "head", "arm", "leg"

signal body_part_hit(damage, body_part)

func take_damage():
	emit_signal("body_part_hit", damage, body_part)
