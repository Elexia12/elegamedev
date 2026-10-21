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

**The layout follows the spec's blockout** (north at the top):
```
+------------- A  EXTRACTION BAY -------------+   truck, deposit zone, support jacks
+--opening--+---------------1 m door---------+
| B CONTROL |  C PUMP HALL                    |
|   ROOM   1 m door   hoist rail over the motor|
|  (VFD)    |  trolley        water main pipe |
+--opening--+                                 |
| D DAMAGED CORRIDOR  -> into the hall        |
+--ramp-----+---------------ramp--------------+
| E LOWER MAINTENANCE PIT (floods first)      |
+---------------------------------------------+
```
The loaded trolley fits neither 1 m door, so the motor goes out one of two ways:
- **Short:** hall → across the corridor's cracked deck → control room → bay. The deck only holds ~280 kg unless a support
  jack holds it up from the pit below.
- **Long:** hall → ramp down into the pit → across → ramp up to the corridor's solid end → control room → bay. The ramps
  need two people to push the loaded trolley up, and the pit floods as time goes on.

| Salvage | Where | Value | The problem |
|---|---|---|---|
| **VFD power module** (contract) | control room, bolted in its drive cabinet | 1,000 cr | Fragile: knocks and water ruin it. One person can carry it, slowly. |
| **Pump motor** (jackpot) | pump hall, bolted to its pump base | 1,800 cr | 450 kg: too heavy to carry. Hoist it onto the trolley, push the trolley out. |
| **Pressure transmitters** ×4 (bonus) | the maintenance pit | 150 cr each | Easy to carry, but the pit floods first. |

### Controls

| Input | Action |
|---|---|
| WASD / Shift / Space | Move / sprint / jump (hold Space to swim up) |
| E | Grab / let go (light things are carried, heavy things dragged). Use things: the hoist pendant, the hook, a support jack, a door, the truck |
| LMB while holding | Throw it |
| R while holding | Turn it: free → upright → flat (stand a support jack up) |
| **Wrench [1]** | Hold LMB on bolts to unbolt (stay on them). On a valve wheel: hold LMB to crank it shut, RMB to crank it open |
| Hoist pendant | [E] takes the controls. Then A/D run the carriage along the rail, W raises, S lowers, [E] lets go |
| Tab | Salvage manifest (condition, value, where each item is) |
| Esc | Menu (the station keeps running) |

### How the run works

- **Unbolting.** Salvage starts bolted in place (a `Mounting`). Hold the wrench on the bolts: 4 s for the VFD, 6 s for the
  motor, 1.5 s for a sensor. Two wrenches work twice as fast. A tremor knocks the wrench off and undoes some progress.
- **Condition.** Every piece of salvage has a condition, and its value is base × condition. A hard impact costs
  (impact speed − threshold) × fragility percent. You see sparks, a floating `−120 cr` and the new value on its label.
  Gentle handling costs nothing. The VFD also loses value fast underwater. When you carry something fragile, look down
  before letting go: then it's set down instead of dropped.
- **The hoist.** A fixed overhead hoist runs on a rail over the motor. One crew member takes the pendant controls. Lower the
  hook next to the motor's orange lifting eye and [E] to hook it. Anyone can hook or unhook it, but you can only unhook a
  load that's resting on something. The carriage accelerates gently and brakes hard, so stopping makes the load swing.
  Teammates can grab the motor to steady it. The **water main** crosses the hall at head height: lift the motor high enough
  to clear it, or swing the motor into it and burst it.
- **The trolley.** Grab its yellow handle and push. The far end has fixed wheels and the handle end swivels, so you steer by
  swinging the handle. Nothing is strapped down: slam it into something, or turn too hard, and the motor slides or falls off.
- **The damaged corridor.** Its cracked deck spans a void over the pit. Its signs show stress and load. It holds about
  280 kg: two crew are fine; the trolley with the motor is not. Extend a **support jack** (two in the bay) at the **jack
  point** in the void under it (walk in from the pit), and it holds 800 kg. A big impact on the deck can make the jack slip.
  At 100% stress the deck falls into the pit.
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

### How it's built: read the scene tree

**`scenes/facility/blackwater_station.tscn`**
```
BlackwaterStation (Mission)
├─ Contract (SalvageContract)  the rules: briefing_text, HUD text, manifest, departure banner, results and payout
├─ MissionClock           15 min to station failure; instability raises seepage and tremors
├─ Tremors                shakes cameras, shoves props, knocks wrenches off bolts, drops Rubble
├─ IncidentLog, Crew (loadout = Wrench), StateSync, HUD, Environment
├─ Geometry               CSG greybox: bay, control room, hall, corridor, pit + two ramps; signs (ProximityLabel)
├─ Water
│  ├─ StationFlood        one FloodZone (base = pit floor) with Pit / Corridor / Hall / Control volumes
│  ├─ WaterMain           inlet_flow through InletValve + leak_flow per burst PipeRun
│  └─ PitGauge, HallGauge FloodGauge signs (DRY → CRITICAL)
├─ PumpHall
│  ├─ OverheadHoist       rail, Carriage, Chain, Hook (+ Point), Pendant (+ Point): move the Pendant anywhere
│  ├─ PumpMotor           450 kg Prop with a LiftingEye        MotorMounting (bolts, item = PumpMotor)
│  ├─ Trolley             FrontAxle (fixed wheels), CargoArea (deck friction)
│  └─ WaterMainPipe       PipeRun: ruptures on a heavy hit
├─ ControlRoom            VfdModule + VfdMounting, HallDoor (SwingDoor: 1 m, turns about its hinge)
├─ DamagedCorridor        Slabs (BridgeSlab ×3), LoadArea, JackPoint, Labels
├─ Pit                    InletValve, InletGush, Transmitter1-4 + their Mountings
├─ Bay                    DepositZone (truck_bed = Truck/TruckBed), Truck (TruckDeparture: Ignition, yard = the bay,
│                         departed → Mission), SupportJack1-2
└─ Rubble
```
Tune it in the Inspector:
- Corridor: `tolerance`, `jack_bonus`, `slip_chance`.
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

## Shared architecture

Every system is a node with one job. Its tuning is in the Inspector, and the reactions between nodes are signal
connections you can see in the **Node → Signals** dock.

**`scenes/main.tscn`**: session flow (`scripts/main.gd`). `missions` lists the playable levels in menu order; the host's
pick is spawned under `World` and replicated by `MissionSpawner`.

**The level root is a generic `Mission`.** It does three things: it receives player requests, runs the ending, and
replicates state. Everything level-specific lives in its **`%Contract`** child (`Contract` subclasses):
- the HUD status, the objectives/manifest and the banner
- how the run ends and what the results screen shows
- the controls hint

`%PressureNetwork`, `%Toolkit` and `%ExtractionZone` are optional (only the reactor has them). The crew's tools come
from `Crew.loadout`.

**`scenes/player/player.tscn`**: one crew member. `Tools` holds Winch, Pressure and Wrench (the level's loadout picks
which). `Hands` does grab/carry/drag/throw, `Vitals` handles breath and knockouts, and `Sync` replicates the player.

**How a click becomes an effect:**
1. Input calls `Mission.send(action, …)`. That RPC reaches the host's `Mission.request()`.
2. `"use"` calls `use(player, target)` on the aimed node. For an `InteractPoint` (pendant, hook, lifting eye, ignition…),
   that's the point's handler, the nearest ancestor that implements `use()`. Its `prompt_for()` writes the HUD prompt.
3. `"drive"` sends the movement keys of whoever holds a machine's controls (group `machines`).
4. Held actions (grab, reel, blast, wrench) run on the host every physics frame, using that player's replicated aim.

**Damage and knock-on effects:** every `Prop` measures impacts from its change in velocity over the last few physics
steps. It applies its own condition damage and passes the blow to whatever it hit (`take_hit`): that's how a motor ruptures
a pipe or cracks the corridor. Damage feedback (sparks, the `−N cr` popup) is driven by a replicated hit counter, so every
peer sees it.

**Replication:**
- Any node in group `net` implements `net_get()` / `net_set()`. The host packs them all into `Mission.net_state`, and
  StateSync sends it at 20 Hz in on-change (reliable) mode.
- Clients apply it, and their props stay frozen and interpolate.
- Player movement is the exception: each player's own `Sync` node sends it from their machine.

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
- the hoist: controls, hard braking, the swing and how it dies down, unhooking only when supported, a burst pipe, a gentle
  set-down on the trolley
- pushing the trolley, and cargo sliding in a crash
- departure and the payout
- the swing door, the jack holding the corridor and slipping on impact, the corridor collapsing, and station failure with
  a rescue fee

`smoke_test.gd` covers the Flooded Reactor.

```
godot --headless --path . -s res://tests/blackwater_net_test.gd -- --role=host   # then, in a second terminal:
godot --headless --path . -s res://tests/blackwater_net_test.gd -- --role=client
```
These check over real ENet sockets that a remote player can unbolt salvage, take the hoist pendant and drive it, and that
both machines see the same hoist position and the same salvage condition. `net_test.gd` does the same for the reactor.

## Not yet / next steps
- Playtest Blackwater with 2-4 people on separate machines (only localhost so far) and tune the feel: hoist braking and
  swing, trolley grip, the corridor tolerance, fragility.
- Ratchet straps for the trolley (the spec's deferred fourth tool), and an emergency drain pump.
- Audio: metallic impacts, groaning steel, the hoist motor, rushing water. Nothing makes sound yet.
- Proper low-poly art and a lighting pass.
