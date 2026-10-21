class_name Mounting
extends Node3D
## Bolts holding a piece of salvage in place. The `item` stays dormant (frozen
## in its rack, on its pump base…) until a crew member holds a wrench on the
## Point for `unbolt_time` seconds. Up to `max_workers` wrenches can work it
## at once, so two people get it off twice as fast. A tremor makes the wrench
## slip and undo some of the progress. The Bolts children disappear as they
## come out.

@export var item: Prop
@export var display_name := "Mounting bolts"
## Seconds of wrench work for one person.
@export var unbolt_time := 4.0
@export var max_workers := 2
## Progress lost when a tremor knocks the wrench off.
@export var slip_loss := 0.2
## Half-size of the bolt pattern (the 4 Bolts sit at the corners, in this
## node's XY plane, heads facing +Z), and the aim radius of the Point.
@export var bolt_spread := Vector2(0.3, 0.2)
@export var point_radius := 0.45

var progress := 0.0
var released := false
var mission: Mission
var _work_frame := -1
var _workers := 0

@onready var point: InteractPoint = $Point
@onready var bolts: Node3D = get_node_or_null("Bolts")
@onready var ratchet_sound: LoopSound = get_node_or_null("RatchetSound")
@onready var bolt_sound: AudioStreamPlayer3D = get_node_or_null("BoltSound")
var _heard_progress := 0.0
var _ratchet_hold := 0.0
var _heard_released := false


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	var shape := point.get_node("Shape") as CollisionShape3D
	shape.shape = shape.shape.duplicate()
	(shape.shape as SphereShape3D).radius = point_radius
	if bolts:
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for i in mini(bolts.get_child_count(), 4):
			var b := bolts.get_child(i) as Node3D
			b.position = Vector3(corners[i].x * bolt_spread.x, corners[i].y * bolt_spread.y, b.position.z)


## Host: one crew member's wrench works the bolts for `delta` seconds.
## Returns false if the wrench slipped (the caller lets go).
func work(delta: float) -> bool:
	if released:
		return false
	if mission.tremors.shake > 0.45:
		progress = maxf(0.0, progress - slip_loss)
		return false
	var frame := Engine.get_physics_frames()
	if frame != _work_frame:
		_work_frame = frame
		_workers = 0
	_workers += 1
	if _workers > max_workers:
		return true
	progress = minf(1.0, progress + delta / unbolt_time)
	if progress >= 1.0:
		_release()
	return true


func _release() -> void:
	released = true
	if item:
		item.wake()
		mission.incident_log.incident("%s unbolted" % item.display_name)


func _process(delta: float) -> void:
	_update_sound(delta)
	point.visible = not released
	point.active = not released
	if item and not item.is_locked():
		item.note = "" if released else "BOLTED · hold LMB with the WRENCH (%d%%)" % roundi(progress * 100.0)
	if bolts:
		var n := bolts.get_child_count()
		for i in n:
			bolts.get_child(i).visible = not released and progress < float(i + 1) / n


## Every peer: the wrench ratchets while progress is being made (replicated
## progress arrives in steps, so it holds on briefly), and the item clanks
## free when the last bolt comes out.
func _update_sound(delta: float) -> void:
	if progress > _heard_progress + 0.0001:
		_ratchet_hold = 0.25
	_heard_progress = progress
	_ratchet_hold -= delta
	if ratchet_sound:
		ratchet_sound.level = 1.0 if _ratchet_hold > 0.0 and not released else 0.0
	if released and not _heard_released and bolt_sound:
		bolt_sound.play()
	_heard_released = released


func net_get() -> Array:
	return [progress, released]


func net_set(s: Array) -> void:
	progress = s[0]
	released = s[1]
