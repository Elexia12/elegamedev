class_name DamagedCorridor
extends Node3D
## The short route: a cracked walkway over the maintenance pit. It's already
## stressed (`start_stress`). Everything standing on it (LoadArea: crew count
## as 80 kg, props by their mass) is its load. While the load is above its
## tolerance, stress climbs fast; heavy load below it creaks slowly; impacts
## on the deck (a dropped motor, a trolley banging over a crack) add stress at
## once. A SupportJack extended at the JackPoint underneath (down in the pit)
## raises the tolerance, but a big impact can make it slip.
## It warns you without words, louder the closer the load is to its limit:
## weight coming on makes it groan, it creaks under load, near the limit it
## cracks (a snap and a puff of dust); overloaded it cracks fast, grit pours
## from the seams and the slabs tremble. The cracks in the slabs widen and
## multiply as stress builds, and stay.
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
## Stress gained per second (%) at twice the tolerated load. Slow enough
## that a team that hears it give and backs off can still save it.
@export var overload_rate := 18.0
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
@export_group("Warning signs")
## Load (× the safe load) where it starts to creak and groans as weight comes
## on. One crew member is ~0.29: stepping on makes it groan softly.
@export var warn_from := 0.25
## Cracks per second when badly overloaded. None below 60% of the safe load.
@export var max_crack_rate := 3.0

var stress := 30.0
var load_kg := 0.0
var jacked := false
var is_collapsed := false
var mission: Mission
var _crumbled := false
## Replicated warning events: cracks (and which slab), groans as weight comes on.
var cracks := 0
var crack_slab := 0
var groans := 0
var groan_slab := 1
var _last_load := 0.0
var _on_deck := {}
var _heard_cracks := 0
var _heard_groans := 0
var _synced := false
## Per slab: how far its mesh is still dipping from a crack (m). And the crack
## meshes' rest scales.
var _dip := {}
var _crack_scale := {}

@onready var slabs: Node3D = $Slabs
@onready var load_area: Area3D = $LoadArea
@onready var jack_point: JackPoint = $JackPoint
@onready var labels: Array[Node] = $Labels.get_children()
@onready var creak_sound: LoopSound = get_node_or_null("CreakSound")
@onready var collapse_sound: AudioStreamPlayer3D = get_node_or_null("CollapseSound")
@onready var groan_sound: AudioStreamPlayer3D = get_node_or_null("GroanSound")
@onready var crack_sound: AudioStreamPlayer3D = get_node_or_null("CrackSound")
@onready var grit_sound: LoopSound = get_node_or_null("GritSound")
@onready var crack_dust: CPUParticles3D = get_node_or_null("CrackDust")
@onready var seam_dust: Array[Node] = [get_node_or_null("SeamDust1"), get_node_or_null("SeamDust2")]
var _heard_collapse := false


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	stress = start_stress
	for s in slabs.get_children():
		for crack_name in ["Crack", "Crack2", "Crack3"]:
			var c := s.get_node_or_null("Mesh/" + crack_name) as Node3D
			if c:
				_crack_scale[c] = c.scale


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
	var arriving: Node3D = null
	var on_now := {}
	for b in load_area.get_overlapping_bodies():
		var kg := 0.0
		if b is CrewMember:
			kg = crew_mass
		elif b is RigidBody3D and not b.freeze:
			kg = b.mass
		if kg <= 0.0:
			continue
		load_kg += kg
		on_now[b] = true
		if not _on_deck.has(b) and (arriving == null or kg > _mass_of(arriving)):
			arriving = b
	_on_deck = on_now
	var ratio := load_kg / safe_load()
	if ratio > 1.0:
		stress += (ratio - 1.0) * overload_rate * delta
	elif ratio > 0.75:
		stress += creak_rate * delta
	# Warning signs (every peer plays them from these replicated counters).
	# Weight coming on makes the deck settle under it, at the slab it's on.
	if load_kg > _last_load + 40.0 and ratio > warn_from:
		groans += 1
		if arriving:
			groan_slab = _slab_index_at(arriving.global_position)
	_last_load = load_kg
	if randf() < crack_rate(ratio) * delta:
		cracks += 1
		# Mostly the middle slab: it spans furthest.
		crack_slab = 1 if randf() < 0.5 else (0 if randf() < 0.5 else 2)
	if stress >= 100.0:
		collapse()


func _mass_of(b: Node) -> float:
	return crew_mass if b is CrewMember else (b as RigidBody3D).mass


## Which slab is under `p` (nearest along the corridor).
func _slab_index_at(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	var i := 0
	for s in slabs.get_children():
		var d := absf(slabs.to_local(p).x - (s as Node3D).position.x)
		if d < best_d:
			best = i
			best_d = d
		i += 1
	return best


## Cracks per second at this load ratio (and how worn the deck already is).
func crack_rate(ratio: float) -> float:
	var r := 0.0 if ratio < 0.6 else max_crack_rate * pow(clampf((ratio - 0.6) / 0.9, 0.0, 1.0), 1.5)
	if stress > 70.0 and ratio > 0.2:
		r += (stress - 70.0) / 30.0 * 0.6
	return r


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
	# Every peer: the deck creaks louder the more it carries and the more
	# stressed it is, and crashes down when it goes.
	var ratio := load_kg / safe_load()
	var strain := clampf((stress - 35.0) / 55.0, 0.0, 1.0)
	# Any real weight on it creaks audibly; it gets louder toward the limit.
	var weight := 0.0 if ratio < warn_from else 0.3 + 0.7 * clampf((ratio - warn_from) / (1.1 - warn_from), 0.0, 1.0)
	var pouring := 0.0 if is_collapsed else clampf(maxf((ratio - 0.85) / 0.6, (stress - 75.0) / 25.0), 0.0, 1.0)
	if creak_sound:
		creak_sound.level = 0.0 if is_collapsed else clampf(strain * 0.6 + weight, 0.0, 1.0)
	if grit_sound:
		grit_sound.level = pouring
	for d in seam_dust:
		if d:
			d.emitting = pouring > 0.15
	if groans != _heard_groans:
		_heard_groans = groans
		if groan_sound and not is_collapsed:
			# It settles under the new weight: a creak, a small crunch, dust
			# shaken out from that slab.
			var slab := slabs.get_child(clampi(groan_slab, 0, slabs.get_child_count() - 1)) as Node3D
			groan_sound.global_position = slab.global_position
			groan_sound.volume_db = linear_to_db(0.5 + 0.5 * weight)
			groan_sound.pitch_scale = randf_range(0.95, 1.05) * (1.1 - 0.25 * clampf(ratio, 0.0, 1.5) / 1.5)
			groan_sound.play()
			if crack_sound and not crack_sound.playing:
				crack_sound.global_position = slab.global_position
				crack_sound.volume_db = linear_to_db(0.25 + 0.35 * weight)
				crack_sound.pitch_scale = randf_range(1.2, 1.5)
				crack_sound.play()
			if crack_dust:
				crack_dust.global_position = slab.global_position + Vector3.UP * 0.2
				crack_dust.restart()
			_dip[slab] = 0.01
	if cracks != _heard_cracks:
		_heard_cracks = cracks
		if not is_collapsed:
			_crack_at(slabs.get_child(clampi(crack_slab, 0, slabs.get_child_count() - 1)) as Node3D, ratio)
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
	# The deck trembles harder as it gets closer to giving way, or while it
	# carries more than it can; a slab that just cracked dips for a moment.
	var shake := 0.0 if stress < 60.0 else (stress - 60.0) / 40.0 * 0.03
	shake = maxf(shake, clampf((ratio - 0.9) / 0.6, 0.0, 1.0) * 0.02)
	var widen := 1.0 + clampf((stress - 30.0) / 70.0, 0.0, 1.0) * 3.0
	var dt := get_physics_process_delta_time()
	for s in slabs.get_children():
		var mesh := s.get_node_or_null("Mesh") as Node3D
		if mesh:
			var dip: float = _dip.get(s, 0.0)
			_dip[s] = move_toward(dip, 0.0, dt * 0.15)
			mesh.position = Vector3(randf_range(-shake, shake), randf_range(-shake, shake) - dip, 0.0)
		# Its cracks widen and multiply as stress builds (and stay).
		for crack_name in ["Crack", "Crack2", "Crack3"]:
			var crack := s.get_node_or_null("Mesh/" + crack_name) as Node3D
			if crack:
				var rest: Vector3 = _crack_scale.get(crack, Vector3.ONE)
				crack.scale = Vector3(rest.x * widen, rest.y, rest.z)
				crack.visible = crack_name == "Crack" or (crack_name == "Crack2" and stress > 50.0) or (crack_name == "Crack3" and stress > 70.0)


## Every peer: a crack goes off in `slab`: a snap, a puff of dust, a dip.
func _crack_at(slab: Node3D, ratio: float) -> void:
	_dip[slab] = 0.025
	if crack_sound:
		crack_sound.global_position = slab.global_position
		crack_sound.volume_db = linear_to_db(clampf(0.4 + 0.5 * ratio, 0.4, 1.0))
		crack_sound.pitch_scale = randf_range(0.85, 1.2)
		crack_sound.play()
	if crack_dust:
		crack_dust.global_position = slab.global_position + Vector3.UP * 0.2
		crack_dust.restart()


func net_get() -> Array:
	return [stress, load_kg, jacked, is_collapsed, cracks, crack_slab, groans, groan_slab]


func net_set(s: Array) -> void:
	stress = s[0]
	load_kg = s[1]
	jacked = s[2]
	is_collapsed = s[3]
	crack_slab = s[5]
	groan_slab = s[7]
	if not _synced:
		# Joining mid-run: don't replay old cracks and groans.
		_heard_cracks = s[4]
		_heard_groans = s[6]
		_heard_collapse = is_collapsed
		_synced = true
	cracks = s[4]
	groans = s[6]
