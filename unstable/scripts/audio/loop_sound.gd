class_name LoopSound
extends AudioStreamPlayer3D
## A looping sound (hoist motor, wheels, water, a groaning floor) whose
## loudness and pitch follow `level` (0 = silent, 1 = full). Its owner sets
## `level` every frame from replicated state, so every player hears the same
## thing. It eases toward the level and stops playing when it fades out.
## The stream must be a looping one (its .import has loop_mode set).

## Volume at level 1 (dB).
@export var full_db := 0.0
## Pitch at level 0 and 1: machines spin up, water rushes harder.
@export var pitch_low := 0.9
@export var pitch_high := 1.1
## How fast it follows `level` (1/s).
@export var response := 6.0
## A fixed level for sounds nobody drives (room ambience). -1 = driven by the owner.
@export_range(-1.0, 1.0) var constant_level := -1.0

var level := 0.0
var _level := 0.0


func _process(delta: float) -> void:
	var want := constant_level if constant_level >= 0.0 else clampf(level, 0.0, 1.0)
	_level = lerpf(_level, want, 1.0 - exp(-response * delta))
	if _level < 0.02:
		if playing:
			stop()
		return
	volume_db = full_db + linear_to_db(_level)
	pitch_scale = lerpf(pitch_low, pitch_high, _level)
	if not playing:
		play(randf() * maxf(0.0, _length() - 0.1))


func _length() -> float:
	return stream.get_length() if stream else 0.0
