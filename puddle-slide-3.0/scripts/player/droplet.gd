class_name Droplet
extends CharacterBody2D
## The player: a water droplet that can freeze (ice), evaporate (vapor) or swell (big).
##
## Liquid physics: momentum + friction, surface adhesion on walls (cling & wall-jump),
## a soft-body rim held together by "surface tension" springs, and gravity sag on the floor.

signal hp_changed(hp: int, max_hp: int)
signal form_changed(form: int)
signal meter_changed(ratio: float)

enum Form { LIQUID, ICE, VAPOR, BIG }

const BASE_RADIUS := 14.0
const MAX_HP := 3
const ICE_DURATION := 15.0
const VAPOR_DURATION := 7.0
const BIG_MASS := 4.0          # mass in "droplets"; radius grows with sqrt(mass)
const MOVE_MASS_COST := 1.0    # each big move spends one droplet of mass
const RIM_POINTS := 32

const TUNING := {
	Form.LIQUID: {"speed": 230.0, "accel": 1500.0, "air_accel": 1000.0, "friction": 1100.0,
			"gravity": 1250.0, "jump": 600.0, "max_fall": 700.0},
	Form.ICE: {"speed": 270.0, "accel": 520.0, "air_accel": 420.0, "friction": 110.0,
			"gravity": 1500.0, "jump": 560.0, "max_fall": 850.0},
	Form.VAPOR: {"speed": 140.0, "accel": 420.0, "air_accel": 420.0, "friction": 260.0,
			"gravity": 0.0, "jump": 0.0, "max_fall": 160.0},
	Form.BIG: {"speed": 175.0, "accel": 900.0, "air_accel": 650.0, "friction": 1300.0,
			"gravity": 1400.0, "jump": 560.0, "max_fall": 900.0},
}

const COLOR_LIQUID := Color(0.35, 0.72, 1.0, 0.85)
const COLOR_BIG := Color(0.12, 0.45, 0.92, 0.85)
const COLOR_ICE := Color(0.78, 0.95, 1.0, 0.95)
const COLOR_VAPOR := Color(0.93, 0.96, 1.0, 0.45)

var form: Form = Form.LIQUID
var hp := MAX_HP
var mass := 1.0
var form_time_left := 0.0
var facing := 1
var radius := BASE_RADIUS
var respawn_point := Vector2.ZERO
var fall_limit := 100000.0
var frozen := false  # input disabled (e.g. after winning)
var camera: Camera2D

var _invuln := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _wall_jump_lock := 0.0
var _last_wall_jump_side := 0
var _wall_side := 0
var _shoot_cooldown := 0.0
var _slamming := false
var _shake := 0.0

var _shape := CollisionShape2D.new()
var _circle := CircleShape2D.new()
var _box := RectangleShape2D.new()

# Soft-body visuals
var _rim := PackedFloat32Array()
var _rim_vel := PackedFloat32Array()
var _squash := Vector2.ONE
var _squash_vel := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = GameConst.LAYER_PLAYER
	floor_snap_length = 6.0
	z_index = 2
	_rim.resize(RIM_POINTS)
	_rim_vel.resize(RIM_POINTS)
	_box.size = Vector2(26, 26)
	_shape.shape = _circle
	add_child(_shape)
	respawn_point = global_position

	camera = Camera2D.new()
	camera.zoom = Vector2(1.6, 1.6)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	add_child(camera)
	camera.make_current()
	_apply_form_physics()


func set_camera_limits(r: Rect2) -> void:
	camera.limit_left = int(r.position.x)
	camera.limit_top = int(r.position.y)
	camera.limit_right = int(r.end.x)
	camera.limit_bottom = int(r.end.y)


# --------------------------------------------------------------------------- forms

func apply_modifier(kind: int) -> void:
	match kind:
		GameConst.Mod.COLD: set_form(Form.ICE)
		GameConst.Mod.HOT: set_form(Form.VAPOR)
		GameConst.Mod.SIZE: set_form(Form.BIG)


func set_form(f: Form) -> void:
	var prev := form
	form = f
	_slamming = false
	mass = BIG_MASS if f == Form.BIG else 1.0
	match f:
		Form.ICE: form_time_left = ICE_DURATION
		Form.VAPOR: form_time_left = VAPOR_DURATION
		_: form_time_left = 0.0
	_apply_form_physics()

	match f:
		Form.ICE: Splash.spawn(get_parent(), global_position, COLOR_ICE, 14, 200.0, TAU)
		Form.VAPOR: Splash.spawn(get_parent(), global_position, COLOR_VAPOR, 18, 120.0, TAU, -PI / 2, -200.0)
		Form.BIG: Splash.spawn(get_parent(), global_position, COLOR_BIG, 24, 320.0)
		Form.LIQUID:
			if prev == Form.VAPOR:  # condense: rain falls out of the cloud
				Splash.spawn(get_parent(), global_position, COLOR_LIQUID, 16, 160.0, PI * 0.6, PI / 2)
			elif prev == Form.ICE:  # melt
				Splash.spawn(get_parent(), global_position + Vector2(0, radius), COLOR_LIQUID, 12, 180.0)
	_squash_vel += Vector2(4, -4)
	form_changed.emit(form)
	_emit_meter()


func _apply_form_physics() -> void:
	var old_r := radius
	match form:
		Form.ICE:
			radius = 13.0
			_shape.shape = _box
		Form.VAPOR:
			radius = 12.0
			_shape.shape = _circle
		Form.BIG:
			radius = BASE_RADIUS * sqrt(mass)
			_shape.shape = _circle
		_:
			radius = BASE_RADIUS
			_shape.shape = _circle
	_circle.radius = radius
	# Vapor is a gas: it drifts through vent meshes that stop liquid and ice.
	collision_mask = GameConst.LAYER_WORLD
	if form != Form.VAPOR:
		collision_mask |= GameConst.LAYER_MESH
	if radius > old_r:
		position.y -= radius - old_r  # grow upwards, not into the floor


func _spend_mass() -> void:
	mass -= MOVE_MASS_COST
	Splash.spawn(get_parent(), global_position, COLOR_BIG, 10, 200.0, TAU)
	if mass <= 1.01:
		set_form(Form.LIQUID)
	else:
		_apply_form_physics()
		_emit_meter()


func _emit_meter() -> void:
	match form:
		Form.ICE: meter_changed.emit(form_time_left / ICE_DURATION)
		Form.VAPOR: meter_changed.emit(form_time_left / VAPOR_DURATION)
		Form.BIG: meter_changed.emit((mass - 1.0) / (BIG_MASS - 1.0))
		_: meter_changed.emit(0.0)


func _can_be_liquid_here() -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = BASE_RADIUS
	q.shape = c
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = GameConst.LAYER_WORLD | GameConst.LAYER_MESH
	q.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


# --------------------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	_t += delta
	_update_timers(delta)

	var p: Dictionary = TUNING[form]
	var dir := 0.0 if frozen else Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		facing = int(signf(dir))

	if form == Form.VAPOR:
		_move_vapor(delta, dir, p)
	else:
		_move_ground(delta, dir, p)

	if not frozen and Input.is_action_just_pressed("attack"):
		_attack()

	var was_on_floor := is_on_floor()
	var pre_vel := velocity
	move_and_slide()
	_after_move(was_on_floor, pre_vel)

	if global_position.y > fall_limit:
		_fell()

	_update_camera(delta)
	_update_softbody(delta)
	queue_redraw()


func _update_timers(delta: float) -> void:
	_invuln = maxf(_invuln - delta, 0.0)
	_coyote -= delta
	_jump_buffer -= delta
	_wall_jump_lock -= delta
	_shoot_cooldown -= delta
	if form == Form.ICE or form == Form.VAPOR:
		form_time_left = maxf(form_time_left - delta, 0.0)
		if form_time_left <= 0.0 and _can_be_liquid_here():
			set_form(Form.LIQUID)
		else:
			_emit_meter()


func _move_ground(delta: float, dir: float, p: Dictionary) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = 0.1
		_last_wall_jump_side = 0
	if not frozen and Input.is_action_just_pressed("jump"):
		_jump_buffer = 0.12

	# Horizontal: accelerate toward target speed; friction decides how much we slide.
	var a: float = p.accel if on_floor else p.air_accel
	if dir == 0.0:
		a = p.friction if on_floor else p.air_accel * 0.3
	if _wall_jump_lock > 0.0:
		a *= 0.25
	if _slamming:
		velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, dir * p.speed, a * delta)

	# Vertical: gravity, with a heavier fall when jump is released (variable jump height).
	var g: float = p.gravity
	if velocity.y < 0.0 and not Input.is_action_pressed("jump"):
		g *= 2.4
	velocity.y = minf(velocity.y + g * delta, 1400.0 if _slamming else p.max_fall)

	# Adhesion: a liquid droplet sticks to walls and slides down slowly.
	_wall_side = 0
	if form == Form.LIQUID and is_on_wall_only():
		_wall_side = -int(signf(get_wall_normal().x))
		if dir != 0.0 and int(signf(dir)) == _wall_side and velocity.y > 0.0:
			velocity.y = minf(velocity.y, 70.0)

	if _jump_buffer > 0.0:
		if _coyote > 0.0:
			velocity.y = -p.jump
			_jump_buffer = 0.0
			_coyote = 0.0
			_squash_vel += Vector2(-3, 4)
		elif _wall_side != 0 and _wall_side != _last_wall_jump_side:
			# Only alternate walls: no climbing a single wall forever.
			velocity = Vector2(-_wall_side * 300.0, -480.0)
			_wall_jump_lock = 0.18
			_last_wall_jump_side = _wall_side
			_jump_buffer = 0.0
			facing = -_wall_side
			_rim_kick(0.0 if _wall_side > 0 else PI, 6.0)


func _move_vapor(delta: float, dir: float, p: Dictionary) -> void:
	# Gas: drifts upward on its own; up/down change how fast it rises or sinks.
	velocity.x = move_toward(velocity.x, dir * p.speed, p.accel * delta)
	velocity.x += sin(_t * 2.3) * 30.0 * delta
	var target_y := -110.0
	if form_time_left <= 0.0:
		target_y = 140.0  # time's up but no room to condense (e.g. under a ceiling): sink
	elif not frozen:
		if Input.is_action_pressed("move_down"):
			target_y = 120.0
		elif Input.is_action_pressed("move_up") or Input.is_action_pressed("jump"):
			target_y = -170.0
	velocity.y = move_toward(velocity.y, target_y, 380.0 * delta)


func _after_move(was_on_floor: bool, pre_vel: Vector2) -> void:
	if is_on_floor() and not was_on_floor:
		var impact := pre_vel.y
		if _slamming:
			_do_slam()
		elif impact > 300.0 and form != Form.VAPOR:
			var col := COLOR_ICE if form == Form.ICE else COLOR_LIQUID
			Splash.spawn(get_parent(), global_position + Vector2(0, radius), col, int(impact / 80.0), impact * 0.3)
		if form != Form.ICE:
			_squash_vel += Vector2(1, -1) * impact / 120.0
			_rim_kick(PI / 2, impact / 90.0)
	if form == Form.LIQUID and is_on_wall() and absf(pre_vel.x) > 150.0:
		_rim_kick(0.0 if pre_vel.x > 0 else PI, absf(pre_vel.x) / 60.0)


func _update_camera(delta: float) -> void:
	_shake = maxf(_shake - 30.0 * delta, 0.0)
	var look := Vector2(facing * 40.0, 0.0)
	var base := camera.offset.lerp(look, 2.0 * delta) if _shake == 0.0 else look
	camera.offset = base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake


# --------------------------------------------------------------------------- attacks

func _attack() -> void:
	match form:
		Form.ICE:
			if _shoot_cooldown <= 0.0:
				_shoot_cooldown = 0.25
				var shard := IceShard.new()
				shard.velocity = Vector2(facing * 560.0 + velocity.x * 0.3, -60.0)
				_spawn(shard, global_position + Vector2(facing * (radius + 6.0), -2.0))
				velocity.x -= facing * 40.0  # recoil
		Form.VAPOR:
			if _can_be_liquid_here():
				set_form(Form.LIQUID)
		Form.BIG:
			if is_on_floor():
				var wave := Wave.new()
				wave.direction = facing
				wave.height = radius * 2.2
				_spawn(wave, global_position + Vector2(facing * (radius + 18.0), radius - 4.0 - wave.height / 2.0))
				velocity.x -= facing * 120.0
				_shake = 5.0
				_spend_mass()
			elif not _slamming:
				_slamming = true
				velocity = Vector2(0, 900)


func _do_slam() -> void:
	_slamming = false
	var center := global_position + Vector2(0, radius)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(center) < 150.0:
			e.die()
	for b in get_tree().get_nodes_in_group("breakable"):
		if b.global_position.distance_to(center) < 120.0:
			b.smash()
	Splash.spawn(get_parent(), center, COLOR_BIG, 30, 450.0, PI * 0.9)
	_shake = 12.0
	_squash_vel += Vector2(6, -6)
	_spend_mass()


func _spawn(node: Node2D, pos: Vector2) -> void:
	get_parent().add_child(node)
	node.global_position = pos


# --------------------------------------------------------------------------- damage

func touch_enemy(e: Node2D) -> void:
	if form == Form.VAPOR:
		return  # a cloud can't be hit
	if form == Form.BIG:
		e.die()  # just roll over them
		_rim_kick(PI / 2, 4.0)
		return
	var from_above := velocity.y > 0.0 and global_position.y + radius * 0.3 < e.global_position.y
	# Ice is hard enough to stomp spiky foes too.
	if from_above and (not e.spiky or form == Form.ICE):
		e.die()
		velocity.y = -460.0 if Input.is_action_pressed("jump") else -340.0
		_squash_vel += Vector2(-3, 4)
	else:
		hurt(e.global_position)


func hit_hazard() -> void:
	if form == Form.VAPOR:
		return
	_invuln = 0.0
	hurt(global_position + Vector2(0, 20))
	if hp > 0:
		_teleport(respawn_point)


func hurt(from_pos: Vector2) -> void:
	if _invuln > 0.0 or form == Form.VAPOR:
		return
	if form == Form.BIG:
		# Big water loses mass instead of health.
		_invuln = 1.0
		_spend_mass()
		velocity = Vector2(signf(global_position.x - from_pos.x) * 260.0, -320.0)
		return
	hp -= 1
	_invuln = 1.3
	_shake = 8.0
	velocity = Vector2(signf(global_position.x - from_pos.x) * 260.0, -320.0)
	Splash.spawn(get_parent(), global_position, COLOR_LIQUID, 12, 220.0, TAU)
	hp_changed.emit(hp, MAX_HP)
	if hp <= 0:
		_respawn()


func _fell() -> void:
	_invuln = 0.0
	hurt(global_position)
	if hp > 0:
		_teleport(respawn_point)


func _respawn() -> void:
	hp = MAX_HP
	set_form(Form.LIQUID)
	_teleport(respawn_point)
	_invuln = 1.5
	hp_changed.emit(hp, MAX_HP)


func _teleport(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	_slamming = false
	camera.reset_smoothing()


# --------------------------------------------------------------------------- visuals

func _rim_kick(angle: float, strength: float) -> void:
	for i in RIM_POINTS:
		var a := TAU * i / RIM_POINTS
		var w := maxf(cos(a - angle), 0.0)
		_rim_vel[i] -= strength * w * w * w * 12.0


func _update_softbody(delta: float) -> void:
	var target := Vector2.ONE
	var stiff := 180.0
	var damp := 10.0
	match form:
		Form.ICE:
			stiff = 600.0
			damp = 30.0
		Form.VAPOR:
			target = Vector2(1.0 + 0.08 * sin(_t * 3.0), 1.0 + 0.08 * cos(_t * 2.6))
		_:
			if is_on_floor():
				# Gravity flattens a resting drop; speed stretches it.
				var s := clampf(absf(velocity.x) / 900.0, 0.0, 0.25)
				target = Vector2(1.16 + s, 0.86 - s * 0.5)
			elif _wall_side != 0 and velocity.y >= 0.0 and velocity.y <= 75.0:
				target = Vector2(0.86, 1.14)
			else:
				var st := clampf(absf(velocity.y) / 1400.0, 0.0, 0.35)
				target = Vector2(1.0 - st * 0.6, 1.0 + st)
	_squash_vel += (target - _squash) * stiff * delta
	_squash_vel *= maxf(0.0, 1.0 - damp * delta)
	_squash = (_squash + _squash_vel * delta).clamp(Vector2(0.55, 0.55), Vector2(1.6, 1.6))

	# Rim springs: each point wobbles; neighbour coupling acts like surface tension.
	for i in RIM_POINTS:
		var idle := sin(_t * 4.0 + i * 0.9) * 0.5 + sin(_t * 2.3 - i * 1.7) * 0.3
		var l := _rim[(i - 1 + RIM_POINTS) % RIM_POINTS]
		var r := _rim[(i + 1) % RIM_POINTS]
		_rim_vel[i] += (idle - _rim[i]) * 200.0 * delta
		_rim_vel[i] += ((l + r) * 0.5 - _rim[i]) * 300.0 * delta
		_rim_vel[i] *= maxf(0.0, 1.0 - 7.0 * delta)
	for i in RIM_POINTS:
		_rim[i] = clampf(_rim[i] + _rim_vel[i] * delta, -radius * 0.4, radius * 0.4)


func _draw() -> void:
	var alpha := 1.0
	if _invuln > 0.0 and int(_t * 16.0) % 2 == 0:
		alpha = 0.35
	match form:
		Form.LIQUID: _draw_blob(COLOR_LIQUID, alpha)
		Form.BIG: _draw_blob(COLOR_BIG, alpha)
		Form.ICE: _draw_ice(alpha)
		Form.VAPOR: _draw_vapor(alpha)


func _draw_blob(fill: Color, alpha: float) -> void:
	var r := radius
	var base_y := r * (1.0 - _squash.y)  # keep the bottom resting on the floor
	var pts := PackedVector2Array()
	var on_floor := is_on_floor()
	for i in RIM_POINTS:
		var a := TAU * i / RIM_POINTS
		var rr := r + _rim[i] * (r / BASE_RADIUS)
		var p := Vector2(cos(a) * rr * _squash.x, sin(a) * rr * _squash.y + base_y)
		if on_floor and p.y > r:
			p.y = r
		pts.append(p)
	var f := fill
	f.a *= alpha
	draw_colored_polygon(pts, f)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0.85, 0.96, 1.0, 0.9 * alpha), 2.0, true)
	# Specular highlights
	var hl := Vector2(-r * 0.38 * _squash.x, -r * 0.4 * _squash.y + base_y)
	draw_circle(hl, r * 0.22, Color(1, 1, 1, 0.8 * alpha))
	draw_circle(hl + Vector2(r * 0.3, -r * 0.12), r * 0.08, Color(1, 1, 1, 0.7 * alpha))
	_draw_eyes(Vector2(0, base_y - r * 0.05 * _squash.y), r, alpha)


func _draw_ice(alpha: float) -> void:
	var s := 13.0
	var rect := Rect2(Vector2(-s * _squash.x, -s * _squash.y + s * (1.0 - _squash.y)), Vector2(2 * s * _squash.x, 2 * s * _squash.y))
	var fill := COLOR_ICE
	fill.a *= alpha
	draw_rect(rect, fill)
	draw_rect(rect, Color(1, 1, 1, alpha), false, 2.0)
	# Facets
	var c := Color(0.55, 0.82, 0.95, 0.8 * alpha)
	draw_line(rect.position + Vector2(4, 4), rect.position + Vector2(rect.size.x * 0.45, rect.size.y * 0.35), c, 1.5)
	draw_line(rect.end - Vector2(4, 4), rect.end - Vector2(rect.size.x * 0.4, rect.size.y * 0.3), c, 1.5)
	draw_rect(Rect2(rect.position + Vector2(4, 4), Vector2(7, 4)), Color(1, 1, 1, 0.9 * alpha))
	_draw_eyes(Vector2(0, -1), s, alpha)


func _draw_vapor(alpha: float) -> void:
	for k in 7:
		var a := _t * 1.3 + k * TAU / 7.0
		var p := Vector2(cos(a) * 8.0, sin(a * 1.3) * 5.0) * _squash
		draw_circle(p, 8.0 + 2.0 * sin(_t * 3.0 + k), Color(COLOR_VAPOR, COLOR_VAPOR.a * alpha))
	draw_circle(Vector2.ZERO, 9.0, Color(1, 1, 1, 0.35 * alpha))
	_draw_eyes(Vector2.ZERO, 12.0, alpha * 0.6)


func _draw_eyes(center: Vector2, r: float, alpha: float) -> void:
	var eye_c := Color(0.05, 0.12, 0.25, alpha)
	var look := Vector2(facing * r * 0.22, 0)
	var blink := 0.25 if fmod(_t, 3.7) < 0.12 else 1.0
	for side in [-1, 1]:
		var p: Vector2 = center + look + Vector2(side * r * 0.22, 0)
		draw_set_transform(p, 0.0, Vector2(1.0, blink))
		draw_circle(Vector2.ZERO, maxf(r * 0.1, 1.6), eye_c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
