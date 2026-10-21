class_name Prop
extends RigidBody3D
## Networked physics object: cargo, debris, rubble, braces, equipment.
## Simulated on the host only; clients hold a frozen copy that interpolates
## toward the replicated pose. Water floats it and drags it. Anything moving
## fast enough knocks over the crew member it hits (falling rubble, a
## toppling column, a crate a teammate threw at you).
##
## Salvage has a condition (100% = intact). Its value is value × condition.
## Hard impacts cost condition: (impact speed − damage_threshold) × fragility
## percent, so a gently lowered motor keeps its value and a slammed one
## doesn't. Every impact is also passed on to whatever it hit (take_hit), so a
## swinging motor can rupture a pipe or crack a damaged floor.

@export var display_name := "Crate"
@export var value := 0
@export_enum("salvage", "primary", "optional", "debris", "equipment") var role := "salvage"
## Fraction of its weight the water carries when fully submerged.
@export var buoyancy := 0.6
## Body height, for the submerged fraction.
@export var height := 1.0
@export var water_drag := 1.5
## Starts frozen in place until woken (by a tremor, a failing support, a
## wrench undoing its bolts…).
@export var dormant := false
## Value lost per second while mostly submerged (condition floored at 25%).
@export var water_damage := 0.0
## Speed above which hitting a crew member knocks them back.
@export var hit_speed := 3.5
## The floating label only shows within this distance (m) of your crew member.
@export var label_range := 7.0
@export_group("Impact damage")
## Condition lost (%) per m/s of impact speed above damage_threshold. 0 = sturdy.
@export var fragility := 0.0
## Impacts slower than this (m/s change in velocity) do no damage.
@export var damage_threshold := 2.0

var condition := 100.0
var current_value := 0.0
var submerged := 0.0
var secured := false
## Shown on the label under the name (set every frame by e.g. a Mounting).
var note := ""
var mission: Mission
## Replicated impact counter + the value the last one cost (drives the
## "−120 cr" popup and sparks on every peer).
var hits := 0
var last_loss := 0.0
var _home: Transform3D
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _has_net := false
var _hit_cooldown := 0.0
var _impact_cooldown := 0.0
## Secured for good (handed over at a deposit zone): never moves again.
var _locked := false
var _shown_hits := 0
## Velocity before this step resolved contacts (impacts read this, not the bounce).
var _last_velocity := Vector3.ZERO
## Velocities of the last few steps: a hit on something round or soft spreads
## over 2-3 steps, so impact severity is the change across this window.
var _velocity_history: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]

@onready var label: Label3D = get_node_or_null("Label")
@onready var sparks: CPUParticles3D = get_node_or_null("Sparks")


func _ready() -> void:
	add_to_group("net")
	add_to_group("props")
	mission = Mission.of(self)
	current_value = value
	_home = transform
	if label:
		label.top_level = true
	if sparks:
		sparks.top_level = true
		sparks.emitting = false
		sparks.one_shot = true
	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		return
	freeze = dormant
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func is_salvage() -> bool:
	return role in ["salvage", "primary", "optional"]


func is_grabbable() -> bool:
	return not dormant and not _locked


## Release a dormant prop into the simulation.
func wake() -> void:
	dormant = false
	if multiplayer.is_server():
		freeze = false
		sleeping = false


## Host: hand this over for good (a deposit zone). It's moved to `where`,
## frozen, and its value is locked in.
func lock_secured(where: Transform3D) -> void:
	_locked = true
	secured = true
	dormant = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = where


func is_locked() -> bool:
	return _locked


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
	_impact_cooldown -= delta
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
		var jet := mission.jet_push_at(global_position)
		if jet != Vector3.ZERO:
			sleeping = false
			apply_central_force(jet * mass)
		_check_impact()
	_last_velocity = linear_velocity
	_velocity_history.pop_front()
	_velocity_history.append(linear_velocity)
	if not _locked and mission.running():
		if water_damage > 0.0 and value > 0 and submerged > 0.5:
			condition = maxf(minf(condition, 25.0), condition - water_damage / value * 100.0 * delta)
		if mission.extraction:
			secured = mission.extraction.contains(global_position)
	current_value = value * condition / 100.0


## Host: a sudden change in velocity while touching something is an impact.
func _check_impact() -> void:
	if _impact_cooldown > 0.0 or get_contact_count() == 0:
		return
	var dv := (linear_velocity - _velocity_history[0]).length()
	if dv < 0.6:
		return
	_impact_cooldown = 0.25
	for b in get_colliding_bodies():
		if b.has_method("take_hit"):
			b.take_hit(self, dv * mass)
	if fragility <= 0.0 or _locked or value <= 0:
		return
	var loss := minf(condition, maxf(0.0, dv - damage_threshold) * fragility)
	if loss < 0.5:
		return
	condition -= loss
	hits += 1
	last_loss = value * loss / 100.0
	if loss >= 8.0:
		mission.incident_log.incident("%s took a hard hit (−%s)" % [display_name, mission.money(last_loss)])


func _process(delta: float) -> void:
	if _has_net and not multiplayer.is_server():
		var t := 1.0 - exp(-18.0 * delta)
		position = position.lerp(_net_pos, t)
		quaternion = quaternion.slerp(_net_rot, t)
	if hits != _shown_hits:
		_shown_hits = hits
		_show_damage()
	if label:
		label.visible = mission.local_distance(global_position) <= label_range
		if label.visible:
			label.global_position = global_position + Vector3.UP * (height / 2.0 + 0.6)
			label.text = _label_text()


func _label_text() -> String:
	var lines := display_name.to_upper()
	if value > 0:
		lines += "\n%s" % mission.money(current_value)
		if fragility > 0.0 or condition < 99.5:
			lines += " · %d%%" % ceili(condition)
	if secured:
		lines += "  ✔ %s" % mission.contract.secured_tag()
	elif submerged > 0.5 and water_damage > 0.0:
		lines += "  ⚠ WATER DAMAGE"
	elif dormant and note != "":
		lines += "\nBOLTED"
	return lines


## Every peer: sparks and a floating "−120 cr" where it got hit.
func _show_damage() -> void:
	if sparks:
		sparks.global_position = global_position
		sparks.restart()
	var pop := Label3D.new()
	pop.text = "−%s" % mission.money(last_loss)
	pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pop.modulate = Color(1.0, 0.35, 0.25)
	pop.font_size = 56
	pop.outline_size = 12
	pop.no_depth_test = true
	mission.add_child(pop)
	pop.global_position = global_position + Vector3.UP * (height / 2.0 + 1.1)
	var tw := pop.create_tween()
	tw.set_parallel()
	tw.tween_property(pop, "global_position:y", pop.global_position.y + 1.2, 1.4)
	tw.tween_property(pop, "modulate:a", 0.0, 1.4).set_delay(0.4)
	tw.chain().tween_callback(pop.queue_free)


func net_get() -> Array:
	return [position, quaternion, dormant, condition, secured, submerged, hits, last_loss]


func net_set(s: Array) -> void:
	_net_pos = s[0]
	_net_rot = s[1]
	dormant = s[2]
	condition = s[3]
	current_value = value * condition / 100.0
	secured = s[4]
	submerged = s[5]
	hits = s[6]
	last_loss = s[7]
	if not _has_net or position.distance_to(_net_pos) > 4.0:
		position = _net_pos
		quaternion = _net_rot
	_has_net = true
