class_name ExtractionZone
extends Node3D
## Box volume (centred on X/Z, from the node's origin upwards) that counts as
## "on the lift". Cargo and crew inside when the lift leaves are extracted.

@export var size := Vector3(10.0, 3.0, 5.0)


func contains(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= size.x / 2.0 and absf(l.z) <= size.z / 2.0 and l.y >= -0.5 and l.y <= size.y
