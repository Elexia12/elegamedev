class_name FloodVolume
extends Node3D
## Footprint (X by Z, centred on this node) of one area a FloodZone fills.

@export var size := Vector2(4.0, 4.0)


func covers(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= size.x / 2.0 and absf(l.z) <= size.y / 2.0
