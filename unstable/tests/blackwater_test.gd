extends SceneTree
## Headless acceptance test for Blackwater Station (solo, host-authoritative):
##   godot --headless --path . --fixed-fps 60 -s res://tests/blackwater_test.gd
## Drives Mission.request() (the same entry point player input uses) through a
## whole salvage run, then a second run for the hazards. The checks follow the
## acceptance tests in the prototype spec.

const HOIST := "PumpHall/OverheadHoist"

var main: Node
var m: Mission
var p: CrewMember
var p2: CrewMember
var frame := 0
var fails := 0
var steps: Array = []
## Per-frame controllers set by steps (a player walking, the operator steering).
var walkers := {}
var tick := Callable()
var mark := Vector3.ZERO
var mark_f := 0.0
var mark_g := 0.0
var swing := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	steps = [
		[0.05, func() -> void: main.start_solo()],
		[0.3, _check_spawn],

		# --- Wrench: unbolting the VFD module -------------------------------------
		[0.05, func() -> void:
			_place(p, Vector3(-13.5, 0.05, -14.0), PI / 2.0, -0.42)
			_req("hold", "wrench", "ControlRoom/VfdMounting/Point", Vector3(-1, 0, 0))],
		[0.1, func() -> void:
			_check(m.contract.briefing() == "", "the briefing disappears once you walk into the station")
			_check(p.prompt().contains("unbolt"), "aiming at the cabinet bolts says what the wrench does (\"%s\")" % p.prompt().get_slice("·", 1).strip_edges())],
		[1.9, func() -> void:
			var mt := _n("ControlRoom/VfdMounting") as Mounting
			_check(mt.progress > 0.4 and mt.progress < 0.6, "one wrench: half done after 2 of 4 s (%d%%)" % roundi(mt.progress * 100.0))
			_check((_n("ControlRoom/VfdModule") as Prop).dormant, "the module stays bolted in until it's done")
			m.crew.add_member(99)
			p2 = m.crew.member(99)
			_place(p2, Vector3(-13.5, 0.05, -13.4), PI / 2.0, -0.39)
			p2.set_hold("wrench", "ControlRoom/VfdMounting/Point", Vector3(-1, 0, 0), 0.0)],
		[1.1, func() -> void:
			var mt := _n("ControlRoom/VfdMounting") as Mounting
			_check(mt.released, "a second wrench finishes the job early (done at ~3 s instead of 4)")
			_check(not (_n("ControlRoom/VfdModule") as Prop).dormant, "the VFD module is loose")
			_req("hold", "")
			p2.set_hold("", "", Vector3.ZERO, 0.0)
			_place(p2, Vector3(-3.0, 0.05, -27.0), 0.0, 0.0)],

		# --- Carrying fragile salvage ------------------------------------------------
		[0.3, func() -> void:
			_place(p, Vector3(-13.8, 0.05, -14.0), PI / 2.0, 0.0)
			_req("hold", "grab", "ControlRoom/VfdModule", Vector3.ZERO, 1.4)],
		[1.0, func() -> void:
			var vfd := _n("ControlRoom/VfdModule") as Prop
			_check(vfd.global_position.y > 1.2 and p.hands.can_lift(vfd), "one crew member lifts the 38 kg module (y=%.2f)" % vfd.global_position.y)
			walkers[p] = Vector3(1.0, 0, 0)
			mark_f = vfd.condition],
		[2.0, func() -> void:
			walkers.erase(p)
			var vfd := _n("ControlRoom/VfdModule") as Prop
			_check(vfd.global_position.x > -14.3, "it comes along when you walk (x=%.1f)" % vfd.global_position.x)
			_check(vfd.condition >= mark_f - 0.01, "careful carrying costs nothing (%d%%)" % roundi(vfd.condition))
			# Look down so it's held near the floor, then let go: a gentle set-down.
			p.head.rotation.x = -1.0],
		[1.0, func() -> void: _req("hold", "")],
		[1.0, func() -> void:
			var vfd := _n("ControlRoom/VfdModule") as Prop
			_check(vfd.condition >= mark_f - 0.01 and vfd.hits == 0, "setting it down gently (looking down) does no damage (%d%%)" % roundi(vfd.condition))
			p.head.rotation.x = 0.0
			_req("hold", "grab", "ControlRoom/VfdModule", Vector3.ZERO, 1.4)],
		[1.2, func() -> void: _req("hold", "")],
		[1.0, func() -> void:
			var vfd := _n("ControlRoom/VfdModule") as Prop
			_check(vfd.condition < mark_f - 5.0 and vfd.hits > 0, "dropping it from chest height damages it (%d%%, −%s)" % [roundi(vfd.condition), m.money(vfd.last_loss)])
			mark_f = vfd.condition],

		# --- Deposit secures value, exactly once --------------------------------------
		[0.1, func() -> void:
			_place(p, Vector3(-3.0, 0.05, -27.5), 0.0, 0.0)
			var vfd := _n("ControlRoom/VfdModule") as Prop
			vfd.global_transform = Transform3D(Basis(), Vector3(-1.0, 0.32, -23.0))
			vfd.linear_velocity = Vector3.ZERO
			vfd.angular_velocity = Vector3.ZERO],
		[0.5, func() -> void:
			_check(not (_n("ControlRoom/VfdModule") as Prop).secured, "not secured the moment it lands (it has to sit for a second)")],
		[1.0, func() -> void:
			var vfd := _n("ControlRoom/VfdModule") as Prop
			var c := m.contract as SalvageContract
			_check(vfd.secured and vfd.is_locked(), "left in the deposit zone, the module is secured")
			_check(vfd.global_position.x > 6.0 and vfd.global_position.y > 0.9, "and loaded onto the truck bed (%s)" % vfd.global_position)
			_check(absf(c.secured_value() - vfd.current_value) < 0.5, "secured value = its value at that condition (%s)" % c.money(c.secured_value()))
			mark_g = c.secured_value()],
		[1.0, func() -> void:
			var c := m.contract as SalvageContract
			_check(absf(c.secured_value() - mark_g) < 0.5, "and it's counted exactly once (%s)" % c.money(c.secured_value()))
			_check(not (_n("ControlRoom/VfdModule") as Prop).is_grabbable(), "secured salvage can't be picked up again")],

		# --- A tremor knocks the wrench off; bonus sensors ------------------------------
		[0.1, func() -> void:
			_place(p, Vector3(-6.0, -2.95, 5.6), PI, -0.3)
			_req("hold", "wrench", "Pit/Transmitter1Mounting/Point", Vector3(-1, 0, 0))],
		[0.6, func() -> void:
			mark_f = (_n("Pit/Transmitter1Mounting") as Mounting).progress
			m.tremors.shake = 0.7],
		[0.1, func() -> void:
			var mt := _n("Pit/Transmitter1Mounting") as Mounting
			_check(mt.progress < mark_f and not p.is_holding_button(), "a tremor knocks the wrench off the bolts (%d%% → %d%%)" % [roundi(mark_f * 100.0), roundi(mt.progress * 100.0)])
			m.tremors.shake = 0.0],
		[0.5, func() -> void:
			m.tremors.shake = 0.0
			_req("hold", "wrench", "Pit/Transmitter1Mounting/Point", Vector3(-1, 0, 0))],
		[1.7, func() -> void:
			_check((_n("Pit/Transmitter1Mounting") as Mounting).released, "sensor clamps come off quickly (1.5 s)")
			_req("hold", "")],

		# --- Inlet valve: crank it with the wrench -------------------------------------
		[0.1, func() -> void:
			_place(p, Vector3(4.0, -2.95, 5.6), PI, -0.4)
			mark_f = (_n("Pit/InletValve") as Valve).opening
			mark_g = (_n("Water/WaterMain") as WaterMain).flow()
			_req("hold", "wrench", "Pit/InletValve/Point", Vector3(-1, 0, 0))],
		[0.1, func() -> void:
			_check(p.prompt().contains("crank"), "aiming the wrench at the inlet valve explains it (\"%s\")" % p.prompt().left(60))],
		[2.9, func() -> void:
			var v := _n("Pit/InletValve") as Valve
			var f := (_n("Water/WaterMain") as WaterMain).flow()
			_check(v.opening < mark_f - 0.25 and f < mark_g, "holding LMB cranks the inlet valve shut (%d%% → %d%%), slowing the flooding" % [roundi(mark_f * 100.0), roundi(v.opening * 100.0)])
			_req("hold", "")],

		# --- The hoist: controls, braking, swing ---------------------------------------
		[0.1, func() -> void:
			_place(p, Vector3(6.0, 0.05, -15.3), 0.0, -0.45)],
		[0.1, func() -> void:
			_check(p.prompt().contains("take the controls"), "the pendant says what [E] does (\"%s\")" % p.prompt())
			_req("use", HOIST + "/Pendant/Point")],
		[0.1, func() -> void:
			var h := _hoist()
			_check(h.operator == 1 and p.operated_machine() == h, "[E] on the pendant takes the hoist controls")
			_check(p.prompt().contains("HOIST CONTROLS"), "and the HUD shows the hoist controls")
			_drive(Vector3(-1, 0, 0))],
		[2.0, func() -> void:
			var h := _hoist()
			_check(h.x < -2.0 and h.vx < -1.0, "A/D runs the carriage along the rail with limited acceleration (x=%.2f, v=%.2f)" % [h.x, h.vx])
			_drive(Vector3.ZERO)],
		[0.6, func() -> void:
			_check(_hoist().vx == 0.0, "letting go brakes it hard (stopped within 0.6 s)")
			_hoist().x = 4.0
			mark_f = _hoist().length
			_drive(Vector3(0, -1, 0))],
		[3.4, func() -> void:
			var h := _hoist()
			_drive(Vector3.ZERO)
			_check(h.length > mark_f + 2.0, "S lowers the hook (%.1f → %.1f m)" % [mark_f, h.length])
			_check(h.eye_in_reach() != null, "the hook is now next to the motor's lifting eye")
			_req("use", HOIST + "/Hook/Point")],
		[0.1, func() -> void:
			_check(_hoist().load_path == "PumpHall/PumpMotor", "[E] on the hook hooks the motor")
			_place(p2, Vector3(12.0, 0.05, -10.4), 0.0, -0.6)
			p2.set_hold("wrench", "PumpHall/MotorMounting/Point", Vector3(-1, 0, 0), 0.0)],
		[6.1, func() -> void:
			_check(not (_n("PumpHall/PumpMotor") as Prop).dormant, "a teammate unbolts the motor while the operator holds it on the hook")
			p2.set_hold("", "", Vector3.ZERO, 0.0)
			_place(p2, Vector3(10.0, 0.05, -5.0), 0.0, 0.0)
			_drive(Vector3(0, 1, 0))],
		[3.0, func() -> void:
			var h := _hoist()
			var motor := _n("PumpHall/PumpMotor") as Prop
			_drive(Vector3.ZERO)
			_check(motor.global_position.y > 1.8, "W raises it off its base (y=%.2f)" % motor.global_position.y)
			_check(absf(h.tension - motor.mass * 9.8) < motor.mass * 9.8 * 0.35, "the chain carries its weight (%.1f kN)" % (h.tension / 1000.0))
			_req("use", HOIST + "/Hook/Point")],
		[0.1, func() -> void:
			_check(_hoist().load_path != "", "unhooking a hanging load is refused")
			_drive(Vector3(-1, 0, 0))],
		[2.4, func() -> void:
			_drive(Vector3.ZERO)
			swing = 0.0
			tick = func() -> void:
				var off := (_n("PumpHall/PumpMotor") as Prop).global_position.x - _hoist().anchor_position().x
				swing = maxf(swing, absf(off))],
		[2.0, func() -> void:
			var motor := _n("PumpHall/PumpMotor") as Prop
			_check(swing > 0.25, "stopping abruptly sets the load swinging (%.2f m)" % swing)
			_check(motor.global_position.y > 1.5 and motor.global_position.y < 5.0, "without flying off (y=%.2f)" % motor.global_position.y)
			mark_f = swing],
		[4.0, func() -> void: swing = 0.0],
		[2.0, func() -> void:
			tick = Callable()
			_check(swing < 0.35 and swing < mark_f * 0.5, "and the swing dies down again (%.2f → %.2f m)" % [mark_f, swing])
			mark_f = (_n("PumpHall/PumpMotor") as Prop).condition
			# Too low to clear the water main at head height: drive into it.
			_drive(Vector3(0, -1, 0))],
		[1.4, func() -> void: _drive(Vector3(-1, 0, 0))],
		[2.6, func() -> void:
			var pipe := _n("PumpHall/WaterMainPipe") as PipeRun
			var motor := _n("PumpHall/PumpMotor") as Prop
			_drive(Vector3.ZERO)
			_check(pipe.ruptured, "swinging the motor into the water main ruptures it")
			_check((_n("Water/WaterMain") as WaterMain).flow() > mark_g * 0.5, "the burst pipe pours more water into the station")
			_check(motor.condition > mark_f - 3.0, "a slow glancing swing breaks the pipe, not the motor (%d%%)" % roundi(motor.condition))
			_drive(Vector3(0, 1, 0))],
		[2.5, func() -> void:
			(_n("PumpHall/Trolley") as Prop).global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(3.0, 0.45, -12.0))
			_drive(Vector3.ZERO)
			_seek_x(-5.0)],
		[6.0, func() -> void:
			tick = Callable()
			_drive(Vector3.ZERO)
			var h := _hoist()
			_check(absf(h.x + 5.0) < 0.3, "the operator brings the motor over the trolley (x=%.2f)" % h.x)
			mark_f = (_n("PumpHall/PumpMotor") as Prop).condition],
		[3.0, func() -> void: _lower_until_supported()],
		[5.0, func() -> void:
			tick = Callable()
			_drive(Vector3.ZERO)
			var motor := _n("PumpHall/PumpMotor") as Prop
			var trolley := _n("PumpHall/Trolley") as Trolley
			_check(motor in trolley.cargo(), "lowered onto the trolley deck")
			_check(motor.condition >= mark_f - 0.01, "lowering it gently costs nothing (%d%%)" % roundi(motor.condition))
			_req("use", HOIST + "/Hook/Point")],
		[0.1, func() -> void:
			_check(_hoist().load_path == "", "once it rests on the trolley it can be unhooked")
			_req("release_controls")],
		[0.1, func() -> void:
			_check(_hoist().operator == 0 and p.operated_machine() == null, "[E] lets go of the controls")],

		# --- The trolley ------------------------------------------------------------------
		[0.2, func() -> void:
			# Stand behind the handle (it faces +X) and take it.
			_place(p, Vector3(4.75, 0.05, -12.0), PI / 2.0, -0.75)
			mark = (_n("PumpHall/Trolley") as Prop).global_position],
		[0.1, func() -> void:
			_check(p.prompt().contains("push the trolley"), "aiming at the trolley says how to push it (\"%s\")" % p.prompt())
			_req("use", "PumpHall/Trolley")],
		[0.1, func() -> void:
			_check(p.pushing() != null, "[E] takes the handle")
			p.head.rotation.x = 0.0
			mark = (_n("PumpHall/Trolley") as Prop).global_position
			p.bot_input = Vector2(0, -1)],
		[3.0, func() -> void:
			var trolley := _n("PumpHall/Trolley") as Trolley
			var moved := mark.x - trolley.global_position.x
			var drift := absf(trolley.global_position.z - mark.z)
			_check(moved > 2.5, "walking pushes the loaded trolley (moved %.1f m)" % moved)
			_check(drift < 0.5, "it rolls straight on its fixed wheels (drift %.2f m over %.1f m)" % [drift, moved])
			_check(_n("PumpHall/PumpMotor") in trolley.cargo(), "the motor rides along on the deck")
			var stand: Vector3 = trolley.handle_for(p) - (-p.global_basis.z) * trolley.handle_reach
			_check(((p.global_position - stand) * Vector3(1, 0, 1)).length() < 0.45, "the pusher stays at the handle")
			p.bot_input = Vector2.ZERO
			_req("use", "PumpHall/Trolley")],
		[0.1, func() -> void:
			var trolley := _n("PumpHall/Trolley") as Trolley
			_check(p.pushing() == null and trolley.linear_velocity.length() > 0.3, "[E] lets go, and the loaded trolley rolls on (%.1f m/s)" % trolley.linear_velocity.length())],
		[3.0, func() -> void:
			var trolley := _n("PumpHall/Trolley") as Trolley
			_check(trolley.linear_velocity.length() < 0.05, "then rolls to a stop")
			p.bot_input = null],
		[0.5, func() -> void:
			# Reckless: ram the loaded trolley at the 1 m door to the control room.
			var trolley := _n("PumpHall/Trolley") as Trolley
			var motor := _n("PumpHall/PumpMotor") as Prop
			mark = motor.global_position - trolley.global_position
			mark_f = motor.condition
			trolley.linear_velocity = Vector3(-3.5, 0, 0)
			motor.linear_velocity = Vector3(-3.5, 0, 0)],
		[1.2, func() -> void:
			var trolley := _n("PumpHall/Trolley") as Trolley
			var motor := _n("PumpHall/PumpMotor") as Prop
			var slid := ((motor.global_position - trolley.global_position) - mark).length()
			_check(slid > 0.15, "ramming the 1 m door makes the unstrapped motor slide (%.2f m)" % slid)
			_check(trolley.global_position.x > -3.0, "the loaded trolley doesn't fit through the door (x=%.1f)" % trolley.global_position.x)],
		[1.5, func() -> void:
			var motor := _n("PumpHall/PumpMotor") as Prop
			_check(motor.condition < mark_f, "and the crash costs the motor condition (%d%% → %d%%)" % [roundi(mark_f), roundi(motor.condition)])],

		# --- Secure the motor, then leave -----------------------------------------------
		[1.5, func() -> void:
			var motor := _n("PumpHall/PumpMotor") as Prop
			motor.global_transform = Transform3D(Basis(), Vector3(-1.0, 0.52, -23.5))
			motor.linear_velocity = Vector3.ZERO
			motor.angular_velocity = Vector3.ZERO
			mark_f = motor.condition],
		[1.6, func() -> void:
			var motor := _n("PumpHall/PumpMotor") as Prop
			_check(motor.secured and motor.global_position.x > 6.0, "the motor is secured and loaded onto the truck")
			_place(p, Vector3(-3.0, 0.05, -27.5), 0.0, 0.0)
			_place(p2, Vector3(-4.0, 0.05, -27.5), 0.0, 0.0)],
		[0.2, func() -> void:
			(_n("PumpHall/PumpMotor") as Prop).apply_central_impulse(Vector3(0, 3000, 0))
			_place(p, Vector3(4.9, 0.05, -23.8), 0.0, -0.1)],
		[0.1, func() -> void:
			_check(p.prompt().contains("start the truck"), "the ignition says what [E] does (\"%s\")" % p.prompt().left(40))
			_req("use", "Bay/Truck/Ignition")
			_place(p, Vector3(-3.0, 0.05, -27.5), 0.0, 0.0)],
		[0.2, func() -> void:
			_check((_n("Bay/Truck") as TruckDeparture).is_counting(), "[E] on the ignition starts the departure countdown")
			_check(m.contract.banner()[0].contains("TRUCK LEAVES"), "with a banner telling everyone to get to the yard")
			_check((_n("PumpHall/PumpMotor") as Prop).condition >= mark_f - 0.01, "secured salvage can't be damaged any more")],
		[10.5, func() -> void:
			_check(main.results.visible, "the truck leaves and the results screen shows")
			var txt: String = main.results.text.text
			_check(txt.contains("CONTRACT COMPLETE + JACKPOT"), "outcome: CONTRACT COMPLETE + JACKPOT")
			_check(txt.contains("Payout") and txt.contains("cr"), "payout in credits")
			_check(txt.contains("Left in the station"), "unrecovered bonus sensors are listed")
			_check(not txt.contains("Rescue fees"), "no rescue fee: everyone made it to the yard")
			print("--- results ---\n", txt.substr(0, 1200))],

		# --- Second run: hazards ---------------------------------------------------------
		[0.2, func() -> void: main.start_mission()],
		[0.3, func() -> void:
			m = main.mission()
			p = m.crew.local_member()
			_quiet()
			_check(m != null and m.running(), "restart spawns a fresh mission (%s)" % m.name)
			_place(p, Vector3(-4.6, 0.05, -12.2), -PI / 2.0, 0.0)
			mark_f = (_n("ControlRoom/HallDoor") as Prop).rotation.y
			walkers[p] = Vector3(1.0, 0, 0)],
		[1.6, func() -> void:
			walkers.erase(p)
			var turned := rad_to_deg(absf(angle_difference((_n("ControlRoom/HallDoor") as Prop).rotation.y, mark_f)))
			var door := _n("ControlRoom/HallDoor") as Prop
			_check(turned > 15.0, "walking into the control room door swings it open (%.0f°)" % turned)
			_check(door.global_position.distance_to(Vector3(-3, 0, -12.7)) < 0.05, "it stays on its hinge")],
		[2.5, func() -> void:
			_place(p, Vector3(-1.6, 0.05, -12.2), PI / 2.0, -0.1)
			mark_f = (_n("ControlRoom/HallDoor") as Prop).rotation.y],
		[0.1, func() -> void:
			_check(p.prompt().contains("push the door"), "from the hall, the door says how to open it (\"%s\")" % p.prompt())
			_req("use", "ControlRoom/HallDoor")],
		[1.0, func() -> void:
			var turned := rad_to_deg(absf(angle_difference((_n("ControlRoom/HallDoor") as Prop).rotation.y, mark_f)))
			_check(turned > 15.0, "[E] pushes it open (%.0f°)" % turned)],

		# --- Damaged corridor, support jack ----------------------------------------------
		[0.2, func() -> void:
			_place(p, Vector3(-8.0, -2.95, -0.5), 0.0, 0.0)
			var jack := _n("Bay/SupportJack1") as SupportJack
			jack.global_transform = Transform3D(Basis(), Vector3(-8.0, -2.53, -4.0))
			jack.linear_velocity = Vector3.ZERO
			jack.angular_velocity = Vector3.ZERO],
		[0.8, func() -> void:
			var jack := _n("Bay/SupportJack1") as SupportJack
			_check(jack.use_prompt(p).contains("extend"), "standing upright on the jack point, the jack offers to extend")
			_req("use", "Bay/SupportJack1")],
		[0.2, func() -> void:
			var jack := _n("Bay/SupportJack1") as SupportJack
			var cor := _n("DamagedCorridor") as DamagedCorridor
			_check(jack.installed and cor.jacked, "[E] extends it: the corridor is jacked (safe load %d kg)" % roundi(cor.safe_load()))
			_place(p, Vector3(4.0, -2.95, 3.0), 0.0, 0.0)
			var motor := _n("PumpHall/PumpMotor") as Prop
			motor.wake()
			motor.global_transform = Transform3D(Basis(), Vector3(-9.0, 0.52, -4.0))
			motor.linear_velocity = Vector3.ZERO
			mark_f = cor.stress],
		[3.0, func() -> void:
			var cor := _n("DamagedCorridor") as DamagedCorridor
			_check(not cor.is_collapsed and cor.stress < mark_f + 5.0, "jacked, it holds the 450 kg motor (stress %d%%, load %d kg)" % [roundi(cor.stress), roundi(cor.load_kg)])
			cor.slip_chance = 1.0
			var motor := _n("PumpHall/PumpMotor") as Prop
			motor.global_transform = Transform3D(Basis(), Vector3(-9.0, 2.2, -4.0))
			motor.linear_velocity = Vector3(0, -2.0, 0)],
		[0.6, func() -> void:
			var jack := _n("Bay/SupportJack1") as SupportJack
			_check(not jack.installed, "dropping the motor on the deck knocks the jack loose")],
		[2.5, func() -> void:
			var cor := _n("DamagedCorridor") as DamagedCorridor
			_check(cor.is_collapsed, "unjacked and overloaded, the corridor gives way")
			var slab := _n("DamagedCorridor/Slabs/Slab2") as Prop
			_check(not slab.dormant and slab.global_position.y < -0.6, "its slabs fall into the pit (y=%.1f)" % slab.global_position.y)
			_check((_n("PumpHall/PumpMotor") as Prop).global_position.y < -1.0, "taking the motor with them")],

		# --- Station failure ---------------------------------------------------------------
		[0.2, func() -> void:
			mark_f = (_n("Water/StationFlood") as FloodZone).level
			m.clock.elapsed = m.clock.collapse_time - 0.1],
		[1.0, func() -> void:
			_check(m.state == Mission.State.COLLAPSING, "when the clock runs out the station fails")
			_check((_n("Water/StationFlood") as FloodZone).level > mark_f + 0.8, "with a flood surge")],
		[7.5, func() -> void:
			_check(main.results.visible, "then the run ends")
			var txt: String = main.results.text.text
			_check(txt.contains("NOTHING RECOVERED"), "nothing secured: NOTHING RECOVERED")
			_check(txt.contains("station failed") and txt.contains("Rescue fees"), "the crew member still inside costs a rescue fee")],
	]
	var t := 0
	for s in steps:
		t += roundi(s[0] * 60.0)
		s[0] = t


func _check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _n(path: String) -> Node:
	return m.get_node(path)


func _hoist() -> OverheadHoist:
	return _n(HOIST) as OverheadHoist


func _req(action: String, a := "", b := "", v := Vector3.ZERO, f := 0.0, w := Vector3.ZERO) -> void:
	m.request(action, a, b, v, f, w)


func _drive(v: Vector3) -> void:
	_req("drive", HOIST, "", v)


## Operator: run the carriage to `target_x` and stop there.
func _seek_x(target_x: float) -> void:
	tick = func() -> void:
		var d := target_x - _hoist().x
		_drive(Vector3(signf(d) if absf(d) > 0.35 else 0.0, 0, 0))


## Operator: hold S, watching the motor, until it sits on the deck and the
## chain has gone slack.
func _lower_until_supported() -> void:
	tick = func() -> void:
		var h := _hoist()
		var motor := _n("PumpHall/PumpMotor") as Prop
		var resting := motor.global_position.y < 1.15 and motor.linear_velocity.length() < 0.2
		_drive(Vector3.ZERO if resting and h.tension < motor.mass * 9.8 * 0.05 else Vector3(0, -1, 0))


func _quiet() -> void:
	# Keep the scripted test deterministic: no random tremors.
	m.tremors.calm_interval = 9999.0
	m.tremors.unstable_interval = 9999.0
	m.tremors._next = 9999.0


func _check_spawn() -> void:
	m = main.mission()
	_check(m != null and m.contract is SalvageContract, "Blackwater Station is the default mission")
	p = m.crew.local_member()
	_check(p != null and p.tools.size() == 1 and p.tools[0] is WrenchTool, "the crew gets one tool: the WRENCH")
	_check(m.contract.briefing().begins_with("THE JOB"), "a short briefing shows at the start, in the bay")
	_quiet()


## Teleport a crew member, facing `yaw` (0 = -Z), head pitched `pitch`.
func _place(c: CrewMember, at: Vector3, yaw: float, pitch: float) -> void:
	c.global_position = at
	c.velocity = Vector3.ZERO
	c.rotation = Vector3(0, yaw, 0)
	c.head.rotation = Vector3(pitch, 0, 0)


func _physics_process(delta: float) -> bool:
	frame += 1
	for c in walkers:
		if is_instance_valid(c):
			c.global_position += walkers[c] * delta
	if tick.is_valid():
		tick.call()
	for s in steps:
		if s[0] == frame:
			s[1].call()
	if frame > steps[-1][0] + 5:
		print("\n%s — %d failure(s)" % ["ALL PASSED" if fails == 0 else "FAILED", fails])
		quit(1 if fails else 0)
		return true
	return false
