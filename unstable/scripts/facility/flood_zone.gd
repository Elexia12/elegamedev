class_name FloodZone
extends Node3D
## Controlled flooding (no fluid sim): one water level shared by its
## FloodVolume children. The Mission moves water in and out of zones.

@export var display_name := "Flood zone"
@export var max_level := 2.0
@export var level := 0.0
@export var water_color := Color(0.12, 0.42, 0.7, 0.55)

var _volumes: Array[FloodVolume] = []
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("net")
	add_to_group("floods")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = water_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.2
	var box := BoxMesh.new()
	for child in get_children():
		if child is FloodVolume:
			var mi := MeshInstance3D.new()
			mi.mesh = box
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			child.add_child(mi)
			_volumes.append(child)
			_meshes.append(mi)


func add_water(amount: float) -> void:
	level = clampf(level + amount, 0.0, max_level)


func covers(p: Vector3) -> bool:
	for v in _volumes:
		if v.covers(p):
			return true
	return false


## World Y of the surface above `p`, or -INF if this zone isn't wet there.
func surface_at(p: Vector3) -> float:
	if level > 0.01 and covers(p):
		return global_position.y + level
	return -INF


func _process(_delta: float) -> void:
	for i in _meshes.size():
		var mi := _meshes[i]
		mi.visible = level > 0.01
		mi.scale = Vector3(_volumes[i].size.x, maxf(level, 0.01), _volumes[i].size.y)
		mi.position.y = level / 2.0


func net_get() -> Array:
	return [level]


func net_set(s: Array) -> void:
	level = s[0]
