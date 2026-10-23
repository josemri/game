extends PhysicalBone3D

## Zona del cuerpo del zombi. `damage` es el daño de un impacto estándar
## en esa zona (la cabeza el triple, el torso doble); el daño que recibe
## el zombi es el del proyectil multiplicado por la zona.

signal body_part_hit(damage: int, body_part: String)

@export var damage := 1
@export var body_part := "body"  # "head", "torso", "arm", "leg"

func take_damage(amount: int = 1) -> void:
	body_part_hit.emit(amount * damage, body_part)
