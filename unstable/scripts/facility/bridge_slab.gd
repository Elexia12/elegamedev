class_name BridgeSlab
extends Prop
## One deck slab of a DamagedCorridor. Dormant (solid, walkable) until the
## corridor collapses. Anything that hits it passes the blow on to the corridor.


func take_hit(_by: Prop, impulse: float) -> void:
	var c := get_parent().get_parent() as DamagedCorridor
	if c:
		c.impact(impulse)
