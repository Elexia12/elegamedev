class_name DamagedCorridor
extends Node3D
## The short route: a cracked walkway over the maintenance pit. It's already
## stressed (`start_stress`). Everything standing on it (LoadArea: crew count
## as 80 kg, props by their mass) is its load. While the load is above its
## tolerance, stress climbs fast; heavy load below it creaks slowly; impacts
## on the deck (a dropped motor, a trolley banging over a crack) add stress at
## once. A SupportJack extended at the JackPoint underneath (down in the pit)
## raises the tolerance, but a big impact can make it slip.
## At 100% stress the deck Slabs drop into the pit and the shortcut is gone
## (the wide passage still works). `collapsed` fires.

signal collapsed

@export var display_name := "Damaged corridor"
## Safe load without a jack (kg). Two crew and the VFD module are fine; the
## trolley with the pump motor is not.
@export var tolerance := 280.0
## Extra safe load while a jack holds it up (kg).
@export var jack_bonus := 520.0
@export var start_stress := 30.0
## Stress gained per second (%) at twice the tolerated load.
@export var overload_rate := 55.0
## Slow creak (%/s) while the load is above 75% of the tolerance.
@export var creak_rate := 0.5
## Stress (%) per kg·m/s of impact on the deck.
@export var impact_stress := 0.02
## Impacts above this (kg·m/s) can knock the jack loose, with this chance.
@export var slip_impulse := 350.0
@export_range(0.0, 1.0) var slip_chance := 0.5
## Crew count as this heavy on the deck.
@export var crew_mass := 80.0
## The stress signs only show within this distance (m).
@export var label_range := 12.0
## How much shorter each slab gets when it breaks (m): its ends crumble, so
## the slabs can't wedge against each other and the floor edges like an arch.
@export var crumble := 0.2

var stress := 30.0
var load_kg := 0.0
var jacked := false
var is_collapsed := false
var mission: Mission
var _crumbled := false

@onready var slabs: Node3D = $Slabs
@onready var load_area: Area3D = $LoadArea
@onready var jack_point: JackPoint = $JackPoint
@onready var labels: Array[Node] = $Labels.get_children()
@onready var creak_sound: LoopSound = get_node_or_null("CreakSound")
@onready var collapse_sound: AudioStreamPlayer3D = get_node_or_null("CollapseSound")
var _heard_collapse := false


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	stress = start_stress


func safe_load() -> float:
	return tolerance + (jack_bonus if jacked else 0.0)


func installed_jack() -> SupportJack:
	for b in jack_point.get_overlapping_bodies():
		if b is SupportJack and b.installed:
			return b
	return null


func _physics_process(delta: float) -> void:
	if mission and multiplayer.is_server() and mission.running() and not is_collapsed:
		_simulate(delta)
	_update_visuals()


func _simulate(delta: float) -> void:
	jacked = installed_jack() != null
	load_kg = 0.0
	for b in load_area.get_overlapping_bodies():
		if b is CrewMember:
			load_kg += crew_mass
		elif b is RigidBody3D and not b.freeze:
			load_kg += b.mass
	var ratio := load_kg / safe_load()
	if ratio > 1.0:
		stress += (ratio - 1.0) * overload_rate * delta
	elif ratio > 0.75:
		stress += creak_rate * delta
	if stress >= 100.0:
		collapse()


## Host: something hit the deck (BridgeSlab.take_hit).
func impact(impulse: float) -> void:
	if is_collapsed or not multiplayer.is_server():
		return
	stress += impulse * impact_stress
	var jack := installed_jack()
	if jack and impulse > slip_impulse and randf() < slip_chance:
		jack.slip()
	if stress >= 100.0:
		collapse()


## Host: the deck gives way.
func collapse() -> void:
	if is_collapsed:
		return
	is_collapsed = true
	stress = 100.0
	# Middle slabs drop straight down; the end slabs hinge down off the walls
	# (pushed down at their inner end), so nothing wedges between the walls.
	_crumble()
	var centre := slabs.global_position
	for s in slabs.get_children():
		if s is Prop:
			s.wake()
			var inward: Vector3 = (centre - s.global_position) * Vector3(1, 0, 1)
			if inward.length() > 1.0:
				s.apply_impulse(Vector3.DOWN * s.mass * 2.0, inward.normalized() * 1.6)
			else:
				s.apply_central_impulse(Vector3.DOWN * s.mass * 2.0)
	var jack := installed_jack()
	if jack:
		jack.slip()
	mission.incident_log.incident("The %s collapsed into the pit" % display_name.to_lower())
	mission.tremors.jolt(0.7)
	collapsed.emit()


## Every peer: shorten the broken slabs by `crumble` (their box shapes and
## their meshes alike, so what you see still matches what collides).
func _crumble() -> void:
	if _crumbled:
		return
	_crumbled = true
	for s in slabs.get_children():
		var length := 0.0
		for c in s.get_children():
			if c is CollisionShape3D and c.shape is BoxShape3D:
				var box := c.shape.duplicate() as BoxShape3D
				length = box.size.x
				box.size.x = maxf(0.5, length - crumble)
				c.shape = box
		var mesh := s.get_node_or_null("Mesh") as Node3D
		if mesh and length > 0.0:
			mesh.scale.x = maxf(0.5, length - crumble) / length


func status_line() -> String:
	if is_collapsed:
		return "COLLAPSED"
	return "stress %d%% · load %d / %d kg%s" % [roundi(stress), roundi(load_kg), roundi(safe_load()), " · JACKED" if jacked else ""]


func _update_visuals() -> void:
	# Every peer: the deck groans louder as stress climbs or it's overloaded,
	# and crashes down when it goes.
	if creak_sound:
		var strain := clampf((stress - 35.0) / 55.0, 0.0, 1.0)
		var over := clampf(load_kg / safe_load() - 0.75, 0.0, 0.6)
		creak_sound.level = 0.0 if is_collapsed else clampf(strain + over, 0.0, 1.0)
	if is_collapsed and not _heard_collapse and collapse_sound:
		collapse_sound.play()
	_heard_collapse = is_collapsed
	var c := Color(0.5, 1.0, 0.6).lerp(Color(1.0, 0.3, 0.15), clampf((stress - 30.0) / 60.0, 0.0, 1.0))
	for l in labels:
		l.visible = not is_collapsed and mission.local_distance(l.global_position) <= label_range
		l.modulate = c
		l.text = "WEAK FLOOR %d%%\n%d / %d kg%s" % [roundi(stress), roundi(load_kg), roundi(safe_load()), " · JACKED" if jacked else ""]
	if is_collapsed:
		_crumble()
		return
	# The deck trembles harder as it gets closer to giving way.
	var shake := 0.0 if stress < 60.0 else (stress - 60.0) / 40.0 * 0.03
	for s in slabs.get_children():
		var mesh := s.get_node_or_null("Mesh") as Node3D
		if mesh:
			mesh.position = Vector3(randf_range(-shake, shake), randf_range(-shake, shake), 0.0)


func net_get() -> Array:
	return [stress, load_kg, jacked, is_collapsed]


func net_set(s: Array) -> void:
	stress = s[0]
	load_kg = s[1]
	jacked = s[2]
	is_collapsed = s[3]
