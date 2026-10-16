class_name Tremors
extends Node3D
## How the collapse reaches the crew. Every so often (more often as the
## facility destabilises) the building shudders. Cameras shake, loose objects
## get shoved, supports take a hit, and some ceiling Rubble breaks loose and
## falls (rubble is any dormant Prop in the "rubble" group). Dust pours from
## the DustEmitter children and the lights flicker and redden.
## `shake` is replicated so every player feels the same tremor.

## Seconds between tremors at zero / full instability (randomised ±30%).
@export var calm_interval := 45.0
@export var unstable_interval := 9.0
## Chance per tremor (at full strength) that each piece of rubble falls.
@export var rubble_chance := 0.3
## Support health lost per tremor at full strength.
@export var support_damage := 5.0
@export var sun: DirectionalLight3D

## 0..1 current shaking, decays over time. Read by cameras, supports, dust.
var shake := 0.0
var mission: Mission
var _next := 25.0
var _sun_energy := 1.0


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	if sun:
		_sun_energy = sun.light_energy


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and mission.running():
		_next -= delta
		if _next <= 0.0:
			var inst := mission.clock.instability()
			tremor(lerpf(0.3, 1.0, inst))
			_next = lerpf(calm_interval, unstable_interval, inst) * randf_range(0.7, 1.3)
	shake = move_toward(shake, 0.0, delta * 0.5)
	_update_effects()


## Host: a full tremor. Strength 0..1.
func tremor(strength: float) -> void:
	shake = maxf(shake, strength)
	for p in mission.props():
		if p.freeze:
			continue
		var kick := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
		p.sleeping = false
		p.apply_central_impulse((kick * 0.8 + Vector3.UP * 0.6) * p.mass * strength)
	for s: Support in get_tree().get_nodes_in_group("supports"):
		if mission.is_ancestor_of(s):
			s.damage(support_damage * strength * randf_range(0.5, 1.5))
	for r in get_tree().get_nodes_in_group("rubble"):
		if r is Prop and r.dormant and mission.is_ancestor_of(r) and randf() < rubble_chance * strength:
			r.wake()


## Host: a local jolt (something heavy landed or snapped). Just shakes.
func jolt(strength: float) -> void:
	shake = maxf(shake, strength)


func _update_effects() -> void:
	for c in get_children():
		if c is CPUParticles3D:
			c.emitting = shake > 0.25
	var inst := mission.clock.instability() if mission.clock else 0.0
	var tint := Color(1, 1, 1).lerp(Color(1.0, 0.55, 0.4), inst)
	if sun:
		sun.light_energy = _sun_energy * lerpf(1.0, 0.6, inst)
		sun.light_color = tint
	for l in get_tree().get_nodes_in_group("facility_lights"):
		if not l is Light3D or not mission.is_ancestor_of(l):
			continue
		if not l.has_meta("base_energy"):
			l.set_meta("base_energy", l.light_energy)
			l.set_meta("base_color", l.light_color)
		var flicker := randf_range(0.15, 1.0) if shake > 0.35 and randf() < 0.5 else 1.0
		l.light_energy = l.get_meta("base_energy") * flicker
		l.light_color = (l.get_meta("base_color") as Color) * tint


func net_get() -> Array:
	return [shake]


func net_set(s: Array) -> void:
	shake = maxf(shake, s[0])
