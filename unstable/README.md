# UNSTABLE — prototype

Greybox prototypes of an online co-op physics salvage game, built in Godot 4.7 (Jolt):

- **Blackwater Station** (prototype 01, the default): an insurance salvage job in a flooding pumping station.
  Built from the *Blackwater Station: Interaction and Implementation Specification*.
- **The Flooded Reactor** (GDD v0.1 §8): the first prototype, still playable from the menu.

> The environment is the enemy, physics is the puzzle, and cooperation is the solution — until cooperation becomes the problem.

Everything in the facility is a physical object. You solve problems by pushing, pulling, lifting and wedging things,
and the collapse happens *to* you: the floor shakes, water rises, and the floor you're standing on gives way.

## Run

- Open `unstable/` in Godot 4.7 and press F5. Pick a **Mission**, then **Play solo**, **Host**, or **Join** (IP, port 24565).
  Clients get whichever mission the host runs.
- Command-line shortcuts: `-- --solo`, `-- --host`, `-- --join=192.168.1.20`, `-- --mission=1` (0 = Blackwater, 1 = Reactor).
- Two-machine test: one player hosts (forward UDP 24565 if not on LAN), the other joins by IP.

---

## Blackwater Station

*Four underqualified salvage workers try to remove expensive industrial equipment from a flooding pumping station.*

A short briefing on screen explains the job; it disappears once you walk into the station ([Tab] shows the manifest any
time). Recover what you can, then leave in the truck. Anything you secure gets paid, at whatever condition it's in when you
secure it. Labels on things only appear when you're close, and the aim prompt tells you what [E] or the wrench will do.

**The layout** (north at the top). It started from the spec's blockout; the owner then moved the motor down into the
pit, put the hoist controls in a booth, and added the service tunnel:
```
+--------------- A  EXTRACTION BAY ----------------+-tunnel exit-+   truck, deposit zone, support jacks
+--opening--+-----------------1 m door--[BOOTH]----+      |      |
| B CONTROL |  C PUMP HALL          hoist   stair  |   F  |      |
|   ROOM   1 m door  trolley          rail     |   |SERVICE      |
|  (VFD)    |   ~~~ water main ~~~~~~~~|~~~~~~~~  |TUNNEL|ramp   |
+--opening--+                          |        |  |      |      |
| D DAMAGED CORRIDOR  -> into the hall |        |  |      |      |
+-----------+---ramp----+--rail--gap---|--------+  |      |      |
| E LOWER MAINTENANCE PIT (floods first)  [MOTOR]  door--annex   |
+----------------------------------------------------------------+
```
The **motor sits on its pump base down in the pit**, under the hoist rail. The rail runs north–south, from over the
motor, through a gap in the pit railing, to over the trolley in the hall. The hoist is driven from the **booth**, a raised
room in the hall's north-east corner up a stair along the east wall; its window looks straight down the rail.

The loaded trolley fits neither 1 m door, so the motor goes out one of two ways:
- **Short:** hall → across the corridor's cracked deck → control room → bay. The deck only holds ~280 kg unless a support
  jack holds it up from the pit below.
- **Hard (if the corridor fails):** hall → ramp down into the pit → east through a doorway into the **service tunnel** →
  a tight turn in its annex → a narrow passage (debris crates to drag aside, and it floods with the pit) → a steep 17°
  ramp up into the bay's east end. One person can't push the loaded trolley up that ramp; two can. Going down the hall
  ramp, one person can't hold it back either.

| Salvage | Where | Value | The problem |
|---|---|---|---|
| **VFD power module** (contract) | control room, bolted in its drive cabinet | 1,000 cr | Fragile: knocks and water ruin it. One person can carry it, slowly. |
| **Pump motor** (jackpot) | the pit, bolted to its pump base under the hoist rail | 1,800 cr | 450 kg: too heavy to carry. Hoist it up onto the trolley, push the trolley out. |
| **Pressure transmitters** ×4 (bonus) | the maintenance pit | 150 cr each | Easy to carry, but the pit floods first. |

### Controls

| Input | Action |
|---|---|
| WASD / Shift / Space | Move / sprint / jump (hold Space to swim up) |
| E | Grab / let go (light things are carried, heavy things dragged). Use things: the hoist controls, the hook, a support jack, a door, the truck |
| LMB while holding | Throw it |
| R while holding | Turn it: free → upright → flat (stand a support jack up) |
| **Wrench [1]** | Hold LMB on bolts to unbolt (stay on them). On a valve wheel: hold LMB to crank it shut, RMB to crank it open |
| Hoist controls (booth) | [E] takes the controls. Then A/D run the carriage along the rail, W raises, S lowers, [E] lets go. Look around freely while you drive |
| Trolley | [E] takes the handle. Walk to push; turn with the mouse or A/D to steer; [E] lets go |
| Tab | Salvage manifest (condition, value, where each item is) |
| Esc | Menu (the station keeps running) |

### How the run works

- **Unbolting.** Salvage starts bolted in place (a `Mounting`). Hold the wrench on the bolts: 4 s for the VFD, 6 s for the
  motor, 1.5 s for a sensor. Two wrenches work twice as fast. A tremor knocks the wrench off and undoes some progress.
- **Condition.** Every piece of salvage has a condition, and its value is base × condition. A hard impact costs
  (impact speed − threshold) × fragility percent. You see sparks, a floating `−120 cr` and the new value on its label.
  Gentle handling costs nothing. The VFD also loses value fast underwater. When you carry something fragile, look down
  before letting go: then it's set down instead of dropped.
- **The hoist.** A fixed overhead hoist runs on a rail from over the motor in the pit to over the trolley in the hall. One
  crew member drives it from the booth, watching through the window. The hook only reaches the motor's orange lifting
  eye down in the pit, so a teammate down there has to hook it ([E] on the hook), and someone on the hall floor unhooks it
  at the trolley: you can only unhook a load that's resting on something. The carriage accelerates gently and brakes hard,
  so stopping makes the load swing. Haul the motor all the way up before moving it: the pit's floor edge and the **water
  main** (head height, across the hall between the pit and the trolley) are in the way. Swing it into the pipe and it bursts.
- **The trolley** starts in the hall under the north end of the hoist rail. It handles like a shopping cart. [E] takes the handle (two people can push together), [E] again lets
  go. While you hold it, it's held rigidly in front of you: walk and it goes where you walk, turn (mouse, or A/D) and it
  turns with you. It can't be shoved sideways: you line up behind it. The fixed wheels are at the handle end, the swivel
  casters at the far end. Your hands only have so much strength, so a loaded trolley is slow to get going, slow to turn
  and slow to stop, and you can't turn faster than it does. Let go and it rolls on a few metres, then stays put. The
  deck is grippy (`deck_friction` 0.85). Cargo resting on it *sticks* (static friction: it's locked to the trolley and
  they move and turn as one, with no jitter); a ram, a dead stop or a corner harder than the grip can hold breaks it
  loose and it slides on, then sticks again once it settles. Lifting it (hoist, hands) unsticks it.
- **The damaged corridor.** Its cracked deck spans a void over the pit. Its signs show stress and load. It holds about
  280 kg: two crew are fine; the trolley with the motor is not. Extend a **support jack** (two in the bay) at the **jack
  point** in the void under it (walk in from the pit), and it holds 800 kg. A big impact on the deck can make the jack slip.
  **It warns you, without words, louder the closer you are to its limit:** weight coming on makes it settle under you
  (a stressed creak, a small crunch, dust shaken out of that slab - even for one person); it keeps creaking under load; near the limit it cracks (a snap, a puff of dust, the slab dips); over the limit it
  groans hard, cracks fast, grit and dust pour from the seams and the slabs tremble. The cracks in the slabs widen and
  multiply as stress builds, and stay. Overloaded, you have a few seconds (a loaded trolley: ~3.5 s) to back off: take
  the weight off in time and it holds, weaker than before. Slam something heavy onto it and it can go at once.
  At 100% stress the deck falls into the pit, and the only way out for the motor is the service tunnel.
- **Second chance: the corridor hoist.** If the deck collapses under the motor, the motor (and maybe the trolley) ends
  up down in the void, in the wreckage. A maintenance hoist runs under the corridor ceiling from over the void out into
  the hall, with its pendant at the corridor mouth. Its hook reaches anywhere in the void; a teammate climbs down over
  the fallen slabs (the void floods first) and hooks the motor. The trolley has a lifting lug in the middle of its deck,
  so the hoist can lift it out too. Set the trolley down in the hall, then the motor on it, and take the service tunnel.
- **Flooding.** One water level for the whole station, measured from the pit floor. It rises with seepage (faster as the
  station destabilises), through the **inlet valve** in the pit (crank it shut with the wrench), and much faster through a
  burst pipe (the inlet valve shuts that off too). The gauges show DRY / SHALLOW / DEEP / CRITICAL for the pit and the hall:
  shallow water slows you, deep water wrecks electronics, critical water is over your head.
- **Doors.** The control room opens straight onto the bay. Its door to the pump hall is a heavy swing door: walk into it
  or [E] to push it open, and it swings back into whoever is on the other side.
- **Securing and leaving.** Leave salvage in the green **deposit zone** for a second, nearly still, and it's secured exactly
  once. It's loaded onto the truck and can't be damaged any more. [E] on the truck's ignition starts a 10 s departure (and
  [E] cancels it). Everyone in the bay leaves; anyone left inside costs a 250 cr rescue fee.
- **Station failure.** After 15 minutes the station fails: the corridor drops, water surges, the ceiling comes down, and
  the run ends with whatever you secured, minus rescue fees for everyone still inside.
- **Results:** CONTRACT COMPLETE + JACKPOT / CONTRACT COMPLETE / PARTIAL SALVAGE / NOTHING RECOVERED, with the payout, each
  item's condition and value lost to damage, what was left behind, and the incident log.

### Sound

Everything you do makes the noise it should, and every player hears the same thing:
- Things that hit something clang, thud or crunch (louder the harder they hit); salvage that loses value crunches.
- The hoist motor whines (deeper under load), its chain rattles as it pays out, and the brake clunks when it stops.
- The trolley's wheels rumble with speed. The wrench ratchets on bolts and valves; a freed item clanks loose.
- Water rushes from the inlet (louder the wider the valve is open); a burst pipe bangs, then hisses.
- The damaged corridor groans when weight comes on, creaks under load, cracks near its limit (grit pours from the
  seams when overloaded), and crashes down when it goes. Tremors rumble. The truck idles,
  then revs as it leaves. The hall and control room hum, the pit laps, the tunnel drips.

The sounds are synthesised placeholders (`tools/make_sfx.py` writes `audio/sfx/`). Replace any `.wav` with a real
recording of the same name. Loudness and pitch are tuned on each sound node (`full_db`, `pitch_low`/`pitch_high` on
`LoopSound`s).

### How it's built: read the scene tree

**`scenes/facility/blackwater_station.tscn`**
```
BlackwaterStation (Mission)
├─ Contract (SalvageContract)  the rules: briefing_text, HUD text, manifest, departure banner, results and payout
├─ MissionClock           15 min to station failure; instability raises seepage and tremors
├─ Tremors                shakes cameras, shoves props, knocks wrenches off bolts, drops Rubble
├─ IncidentLog, Crew (loadout = Wrench), StateSync, HUD, Environment
├─ Geometry               CSG greybox: bay, control room, hall + hoist booth and stair, corridor, pit + hall ramp,
│                         service tunnel (annex, passage, ramp); signs (ProximityLabel)
├─ Water
│  ├─ StationFlood        one FloodZone (base = pit floor) with Pit / Corridor / Hall / Control / Tunnel / Annex volumes
│  ├─ WaterMain           inlet_flow through InletValve + leak_flow per burst PipeRun
│  └─ PitGauge, HallGauge FloodGauge signs (DRY → CRITICAL)
├─ PumpHall
│  ├─ OverheadHoist       rail (north-south, pit -> hall), Carriage, Chain, Hook (+ Point), Pendant (+ Point) = the
│  │                      console in the booth (move it anywhere)
│  ├─ PumpMotor           450 kg Prop with a LiftingEye, down in the pit   MotorMounting (bolts, item = PumpMotor)
│  ├─ Trolley             FixedAxle (fixed wheels, handle end), Grip (aim zone), CargoArea (cargo that sticks),
│  │                      LiftingEye (flat lug mid-deck: a hoist can lift the trolley)
│  └─ WaterMainPipe       PipeRun: ruptures on a heavy hit
├─ ControlRoom            VfdModule + VfdMounting, HallDoor (SwingDoor: 1 m, turns about its hinge)
├─ DamagedCorridor        Slabs (BridgeSlab ×3, they crumble `crumble` m shorter when they fall), LoadArea, JackPoint, Labels
├─ CorridorHoist          OverheadHoist along the corridor (void -> hall), Pendant at the corridor mouth: the second chance
├─ Pit                    InletValve, InletGush, Transmitter1-4 + their Mountings
├─ Tunnel                 Debris1-3 (60 kg crates in the passage: drag them aside)
├─ Bay                    DepositZone (truck_bed = Truck/TruckBed), Truck (TruckDeparture: Ignition, yard = the bay,
│                         departed → Mission), SupportJack1-2
└─ Rubble
```
Tune it in the Inspector:
- Corridor: `tolerance`, `jack_bonus`, `slip_chance`, `overload_rate` (how long you have to back off), and the warning
  signs: `warn_from`, `max_crack_rate`.
- Hoist: `braking` vs `acceleration` (the swing), `sway_damping`.
- Salvage: `fragility` / `damage_threshold` on each prop.
- Water main: `inlet_flow`; the zone's `inflow`.
- Mountings: `unbolt_time`.
- Text: `label_range` on props, `show_within` on ProximityLabel signs, valves and gauges.

---

## The Flooded Reactor

Get the **reactor core** (300 kg, primary) out from behind the jammed gate and onto the green **lift**, then pull the
**extraction lever**. After an 8 s countdown the lift physically rises out of the shaft, carrying whatever and whoever is
standing on it. Optional: the **bonus container** in the flooding storage room, which loses value while submerged. At
12:00 the facility collapses around you and anything still inside is lost.

| Input | Action |
|---|---|
| E | Grab / let go of an object, pull the extraction lever |
| 1 2, Q, wheel | Winch / Pressure tool |
| LMB / RMB | Tool primary / secondary |
| R on a cable end | Detach the cable |

- **Handling.** One crew member can grab with at most 950 N. The core needs two people (or a winch).
- **Winch (1): hook it anywhere.** LMB any surface, then LMB a second surface. Off-centre pulls tip cargo, and hooking a
  support's structure strains it. Hold LMB/RMB on a cable end to reel; the motor stalls at 3.8 kN, and the cable snaps
  above 5.2 kN.
- **Pressure tool (2).** LMB/RMB a valve to open/close it 25%. Anywhere else, hold LMB to blast or RMB to pull loose objects.
- **The gate** starts jammed: it needs ~3.8 kN of lift (one winch pulling *up* to the frame header, plus the Gate jack
  valve). Its label shows the live lift. Brace posts wedged under it hold it up.
- **Pressure** builds on its own; held at 100% the line bursts, and a water jet blasts crew and cargo across the hall.
- **Supports** fail with time, tremors and cable load, and topple what they hold.

Its scene is `scenes/facility/flooded_reactor.tscn` (rules in its `Contract` node, a `ReactorContract`).

---

## How it's built

Both levels share one generic `Mission` with a level-specific `Contract`, host-authoritative physics and a single
replicated snapshot. See `ARCHITECTURE.md` for how input becomes an effect, the networking model, the damage model and
the physics rules the code follows.

## Tests

```
godot --headless --path . --fixed-fps 60 -s res://tests/blackwater_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/smoke_test.gd
```
`blackwater_test.gd` plays a whole Blackwater run through `Mission.request()`, then a second run for the hazards. It
follows the spec's acceptance tests:
- unbolting (solo vs two wrenches, a tremor knocking the wrench off)
- fragile carrying (gentle set-down vs a drop)
- securing exactly once, and cranking the inlet valve
- the hoist: the booth controls, hard braking, hooking the motor down in the pit (from the pit, not the booth), hauling it
  out, the swing and how it dies down, unhooking only when supported, a burst pipe, a gentle set-down on the trolley
- pushing the trolley by its handle (tracking, staying at the handle, coasting after letting go), and cargo sliding in a crash
- departure and the payout
- the corridor's warnings (groans, creaks, cracks, grit and dust when overloaded) and backing off in time saving it
- the swing door, the jack holding the corridor and slipping on impact, the corridor collapsing
- the second chance: the corridor hoist lifts the motor out of the collapsed corridor onto the trolley
- the service tunnel: one pusher can't get the loaded trolley up its ramp, two can
- station failure with a rescue fee

`smoke_test.gd` covers the Flooded Reactor.

```
godot --headless --path . -s res://tests/blackwater_net_test.gd -- --role=host   # then, in a second terminal:
godot --headless --path . -s res://tests/blackwater_net_test.gd -- --role=client
```
These check over real ENet sockets that a remote player can unbolt salvage, take the hoist pendant and drive it, and that
both machines see the same hoist position and the same salvage condition. `net_test.gd` does the same for the reactor.

## Status and next steps

See `PROGRESS.md`.
