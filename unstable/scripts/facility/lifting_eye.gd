class_name LiftingEye
extends InteractPoint
## A designated lifting point on a heavy prop (put it where the hoist should
## pick the prop up: on top, over its centre of mass, so it hangs level).
## [E] on it hooks the nearest OverheadHoist on, if its hook is close enough.


func _ready() -> void:
	kind = "eye"
	super._ready()
	add_to_group("lifting_eyes")


func _hoist() -> OverheadHoist:
	var best: OverheadHoist = null
	var best_d := INF
	for m in Mission.of(self).machines():
		if m is OverheadHoist:
			var d: float = m.hook_position().distance_to(global_position)
			if d < best_d:
				best = m
				best_d = d
	return best


func use(player: CrewMember, _target: Node) -> String:
	var h := _hoist()
	return h.use(player, self) if h else ""


func prompt_for(crew: CrewMember, _target: Node) -> String:
	var h := _hoist()
	return h.prompt_for(crew, self) if h else "Lifting eye"
