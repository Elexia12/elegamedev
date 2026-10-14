extends Node2D
## Game root: wires the level's player to the HUD and tracks dew, time and the win state.

@onready var level: Level = $Level
@onready var hud: Hud = $HUD
var player: Droplet


func _ready() -> void:
	add_to_group("game")
	player = level.player
	hud.dew_total = level.dew_count
	hud.max_hp = player.max_hp
	hud.hp = player.hp
	player.hp_changed.connect(_on_hp_changed)
	player.form_changed.connect(func(f): hud.form = f)
	player.meter_changed.connect(func(r): hud.meter = r)


func _on_hp_changed(hp: int, max_hp: int) -> void:
	hud.hp = hp
	hud.max_hp = max_hp


func _process(delta: float) -> void:
	if not hud.won:
		hud.elapsed += delta
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()


func on_dew_collected() -> void:
	hud.dew += 1


func on_goal_reached() -> void:
	hud.won = true
	player.frozen = true
