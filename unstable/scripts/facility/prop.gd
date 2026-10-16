class_name Prop
extends RigidBody3D
## Networked physics object: cargo, debris, rubble, braces, support columns.
## Simulated on the host only; clients hold a frozen copy that interpolates
## toward the replicated pose. Water floats it and drags it. Anything moving
## fast enough knocks over the crew member it hits (falling rubble, a
## toppling column, a crate a teammate threw at you).

@export var display_name := "Crate"
@export var value := 0
@export_enum("salvage", "primary", "optional", "debris") var role := "salvage"
## Fraction of its weight the water carries when fully submerged.
@export var buoyancy := 0.6
## Body height, for the submerged fraction.
@export var height := 1.0
@export var water_drag := 1.5
## Starts frozen in place until woken (by a tremor, a failing support…).
@export var dormant := false
## Value lost per second while mostly submerged (floored at 25%).
@export var water_damage := 0.0
## Speed above which hitting a crew member knocks them back.
@export var hit_speed := 3.5

var current_value := 0.0
var submerged := 0.0
var secured := false
var mission: Mission
var _home: Transform3D
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _has_net := false
var _hit_cooldown := 0.0
## Velocity before this step resolved contacts (impacts read this, not the bounce).
var _last_velocity := Vector3.ZERO

@onready var label: Label3D = get_node_or_null("Label")


func _ready() -> void:
	add_to_group("net")
	add_to_group("props")
	mission = Mission.of(self)
	current_value = value
	_home = transform
	if label:
		label.top_level = true
	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		return
	freeze = dormant
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func is_grabbable() -> bool:
	return not dormant


## Release a dormant prop into the simulation.
func wake() -> void:
	dormant = false
	if multiplayer.is_server():
		freeze = false
		sleeping = false


func point_velocity(at: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(at - global_position)


func _on_body_entered(body: Node) -> void:
	if body is CrewMember and _hit_cooldown <= 0.0:
		var speed := maxf(linear_velocity.length(), _last_velocity.length())
		if speed < hit_speed:
			return
		_hit_cooldown = 0.5
		var away: Vector3 = (body.global_position - global_position) * Vector3(1, 0, 1)
		var push := (_last_velocity.normalized() + away.normalized()).normalized()
		var energy := mass * speed
		body.knock(push * minf(energy / 60.0, 10.0) + Vector3.UP * 2.5, clampf(energy / 450.0, 0.3, 3.0))


func _physics_process(delta: float) -> void:
	if mission == null or not multiplayer.is_server():
		return
	_hit_cooldown -= delta
	if global_position.y < -20.0:
		transform = _home
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	var surface := mission.water_surface_at(global_position)
	var bottom := global_position.y - height / 2.0
	submerged = clampf((surface - bottom) / height, 0.0, 1.0) if surface > -1e9 else 0.0
	if not freeze:
		if submerged > 0.0:
			apply_central_force(Vector3.UP * mass * 9.8 * buoyancy * submerged)
			apply_central_force(-linear_velocity * mass * water_drag * submerged)
		var jet := mission.pressure_network.jet_push_at(global_position)
		if jet != Vector3.ZERO:
			sleeping = false
			apply_central_force(jet * mass)
	_last_velocity = linear_velocity
	if water_damage > 0.0 and submerged > 0.5 and mission.running():
		current_value = maxf(value * 0.25, current_value - water_damage * delta)
	secured = mission.extraction.contains(global_position)


func _process(delta: float) -> void:
	if _has_net and not multiplayer.is_server():
		var t := 1.0 - exp(-18.0 * delta)
		position = position.lerp(_net_pos, t)
		quaternion = quaternion.slerp(_net_rot, t)
	if label:
		label.global_position = global_position + Vector3.UP * (height / 2.0 + 0.6)
		var lines := "%s\n$%d" % [display_name.to_upper(), roundi(current_value)]
		if secured:
			lines += "  ✔ ON LIFT"
		elif submerged > 0.5 and water_damage > 0.0:
			lines += "  ⚠ WATER DAMAGE"
		label.text = lines


func net_get() -> Array:
	return [position, quaternion, dormant, current_value, secured, submerged]


func net_set(s: Array) -> void:
	_net_pos = s[0]
	_net_rot = s[1]
	dormant = s[2]
	current_value = s[3]
	secured = s[4]
	submerged = s[5]
	if not _has_net or position.distance_to(_net_pos) > 4.0:
		position = _net_pos
		quaternion = _net_rot
	_has_net = true
