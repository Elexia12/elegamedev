# UNSTABLE — prototype

Greybox prototype of **The Flooded Reactor** (GDD v0.1 §8), built in Godot 4.7 (Jolt).

> The environment is the enemy, physics is the puzzle, and cooperation is the solution — until cooperation becomes the problem.

Everything in the facility is a physical object. You solve problems by pushing, pulling, wedging and throwing things,
and the collapse happens *to* you: the floor shakes, the ceiling falls, and columns topple.

## Run

- Open `unstable/` in Godot 4.7 and press F5. Choose **Play solo**, **Host**, or **Join** (IP, port 24565).
- Command-line shortcuts: `-- --solo`, `-- --host`, `-- --join=192.168.1.20`.
- Two-machine test: one player hosts (forward UDP 24565 if not on LAN), the other joins by IP.

## Controls

| Input | Action |
|---|---|
| WASD / Shift / Space | Move / sprint / jump (hold Space to swim up) |
| E | Grab / let go of an object, pull the extraction lever |
| LMB while holding | Throw it |
| R while holding | Turn it: free → upright → flat (stand a brace post up) |
| 1 2, Q, wheel | Winch / Pressure tool |
| LMB / RMB | Tool primary / secondary (see below) |
| R on a cable end | Detach the cable |
| Esc | Menu (the facility keeps running) |

Input actions live in Project Settings → Input Map.

## The mission

Get the **reactor core** (300 kg, primary) out from behind the jammed gate and onto the green **lift**, then pull the
**extraction lever**. After an 8 s countdown the lift physically rises out of the shaft, carrying whatever and whoever is
standing on it. Optional: the **bonus container** in the flooding storage room, which loses value while submerged. At
12:00 the facility collapses around you and anything still inside is lost.

**Handling things.** One crew member can grab with at most 950 N. That's enough to carry crates and brace posts and drag
the bonus container, but the core needs two people pulling together (or a winch). Light things can be thrown, and a
thrown crate knocks over whoever it hits.

**Winch (1): hook it anywhere.** There are no anchor points. LMB any surface (a corner of the core, the gate, a column, a
bare wall), then LMB a second surface, and a cable runs between the exact points you picked.
- **Where you hook matters.** Off-centre pulls tip and spin cargo. A cable that ends up pulling the wrong way will hold
  things down.
- **Hooking a support's structure strains it.** That includes its column, the header beam over the gate and the gantry
  beam.
- **Reeling.** Hold LMB/RMB on a cable end to reel in or out. The motor stalls at 3.8 kN.
- **Snapping.** Above 5.2 kN the cable snaps and whips anyone standing next to it. The team has 3 cables.

**Pressure tool (2).** LMB/RMB a valve to open/close it 25%. Anywhere else, hold LMB to blast or RMB to pull loose objects.

**Brace posts.** Three 35 kg steel posts lie in the bay. Carry one and stand it upright ([R]):
- Under the raised gate, it physically holds the gate up.
- On a support's orange floor pad, it props that support up.

Load wears a brace down from orange to red until it buckles.

**The facility**
- **The gate** is a real 300 kg body on rails. It starts **jammed** and only breaks free when the lift on it beats its weight
  plus the jam. One winch can't do it alone; two winches can, or a winch plus jack pressure. Once free it slides under real
  forces, and it falls on whatever is underneath it.
- **Pressure** builds on its own. The *Gate jack* valve uses it to lift the gate. The *Drain pump* bleeds it off and empties
  the storage room, but floods the main hall. As pressure climbs, the pipe rattles and the vent spits steam. If it's held at
  100%, the line bursts: a water jet blasts crew and cargo across the hall, and the hall floods.
- **Supports** (Gate frame, Gantry strut) go Stable → Strained → Critical → Failed with time, tremors and cable load,
  shuddering harder as they weaken. When one fails, its column topples and what it held comes down. The gate frame drops
  its header beam and cuts the jack. The gantry drops a 180 kg beam across the hall.
- **Tremors** come more often as the run goes on. The camera shakes, loose things get shoved, dust pours, the lights flicker
  and redden, and ceiling **rubble** breaks loose onto whoever is below. Getting hit knocks you back, and a heavy hit knocks
  you out.
- **Flooding** uses per-zone water levels. Water slows crew, drowns them if they stay under, and floats or drags cargo.
- **The collapse** at 12:00 isn't a message. The whole ceiling comes down and every support fails, and *then* the run fails.
- **Results**: Full / Successful / Partial / Failure, cargo value, objectives, duration and an incident log. Text messages are
  kept to a minimum; you see what happens instead.

## How it's built: read the scene tree

Every system is a node with one job. Its tuning is in the Inspector, and the
reactions between nodes are signal connections you can see in the **Node → Signals** dock.

**`scenes/main.tscn`**: session flow (`scripts/main.gd`)
```
Main                      menu → solo/host/join → mission → results → restart
├─ World                  the running mission is added here
├─ MissionSpawner         replicates the mission to clients
└─ UI
   ├─ MainMenu            scenes/ui/main_menu.tscn   (signals → Main.start_solo/host/join)
   ├─ ResultsScreen       scenes/ui/results_screen.tscn
   └─ PauseMenu           scenes/ui/pause_menu.tscn
```

**`scenes/facility/flooded_reactor.tscn`**: the level. The root `Mission` only handles player requests, the ending and replication.
```
FloodedReactor (Mission)
├─ MissionClock           time → instability (0→1) → phases (each opens with a big tremor); emits collapsed
├─ Tremors                shakes cameras, shoves props, damages supports, drops Rubble; Dust children; flickers facility_lights
├─ PressureNetwork        pressure rises by itself; rattles the pipe; held at 100% it bursts → water jet + floods burst_zone
├─ DrainPump              valve + network: moves water source → target, spends pressure
├─ IncidentLog            incident list for results (+ the few text messages: lift called, crew joined)  → HUD
├─ Toolkit                the team's winch cables: Cable1-3 (add children for more)
├─ Crew (CrewRoster)      spawns a player per peer: Members, PlayerSpawner, SpawnPoints
├─ StateSync              replicates Mission.net_state (snapshot of every "net" node)
├─ HUD                    scenes/ui/hud.tscn
├─ Environment            sky, sun, OverviewCamera, Lights (work lamps that flicker)
├─ Geometry, Piping       CSG greybox incl. ceiling with the lift shaft open; JackLine pipe + BurstVent
├─ Gate                   300 kg RigidBody on rails; jack_valve + pressure_network wired in the Inspector
├─ Supports
│  ├─ SupportGateFrame    Column + FrameHeader   failed → Gate.frame_failed, FrameHeader.wake
│  └─ SupportGantry       Column + GantryBeam    failed → GantryBeam.wake
├─ Bollards               solid tie-off posts (optional: the winch hooks anywhere)
├─ Manifold               JackValve, DrainValve
├─ Cargo                  ReactorCore (primary), BonusContainer (optional), salvage crates
├─ Equipment              Brace1-3 (physical brace posts), SkidSled (low-friction skid)
├─ Rubble                 dormant ceiling chunks (group "rubble") that tremors shake loose
├─ Water                  LowerFlood, BonusFlood (FloodZones; their FloodVolume children preview in the editor)
└─ Extraction             ExtractionZone + Platform (a moving body that rises; departed → Mission), ExtractionLever
```
Change `level` on a FloodZone in the editor to see the water. Move Rubble to decide where danger falls. Retune a run
with `collapse_time` on MissionClock, the intervals on Tremors, or a support's decay rates.

**`scenes/player/player.tscn`**: one crew member (`scripts/player/`)
```
Player (CrewMember)       movement, mouse look, aiming, input routing, knock()/stun, camera shake
├─ Head/Camera3D
│  ├─ InteractRay         finds cable ends / valves / the lever (6 m, interact layer)
│  └─ GrabRay             finds the surface you look at (6 m): props, walls, columns, the gate
├─ Head/ToolModel         the box in your hand, coloured by the current tool
├─ Tools                  child order = hotkeys 1-2
│  ├─ Winch (WinchTool)   hook any surface → any surface, reel in/out  (+ PendingMarker)
│  └─ Pressure (PressureTool)  turn valves, blast / pull props
├─ Hands                  E grab, LMB throw, R turn upright/flat; grab_force decides what one person can move
├─ Vitals                 breath & knockouts  (knocked_out/recovered → CrewMember)
└─ Sync                   replicates position, rotation, aim, tool, Vitals.knocked
```

**Components** (`scenes/components/`, `scenes/props/`): Gate, Support, Cable, Valve, Bollard,
ExtractionLever, InteractPoint (the generous aim sphere for cable ends/valves/lever), FloodVolume, and the
Prop scenes: core, container, salvage, gantry beam, frame header, rubble, brace (Brace extends Prop), skid sled.
Every Prop knocks back a crew member it hits at speed.

**How a click becomes an effect:** the player's tool calls `Mission.send(action, …)`. That RPC
reaches the host's `Mission.request()`, which hands it to the node that owns the behaviour
(Toolkit, Valve, ExtractionZone…). For held actions (grab, reel, blast), the host runs the matching player child
(Hands / WinchTool / PressureTool) every physics frame using that player's replicated aim.

**Replication:** any node in group `net` implements `net_get()` / `net_set()`. The host packs
them all into `Mission.net_state` 60 times a second, and StateSync sends it at 20 Hz. It uses on-change (reliable) mode because
the snapshot is bigger than one unreliable packet; the network test catches that if it regresses. Clients
apply it, and their props stay frozen and interpolate. Player movement is the exception: each player's
own `Sync` node sends it from their machine.

## Tests

```
godot --headless --path . --fixed-fps 60 -s res://tests/smoke_test.gd
```
These check, among other things:
- the solo drag limit and two-crew drag, and throwing
- winching between any two surfaces, and off-centre tipping
- the jammed gate (one winch fails; winch + jack frees it)
- header strain, a wedged brace holding the gate
- toppling columns, rubble knockback, the burst water jet
- the lift carrying cargo and crew up, and the physical collapse → FAILURE (28 checks).

```
godot --headless --path . -s res://tests/net_test.gd -- --role=host   # then, in a second terminal:
godot --headless --path . -s res://tests/net_test.gd -- --role=client
```
This checks over real ENet sockets that the client sees the host's winched core and that the host applies the client's
valve request.

## Not yet / next steps
- Audio (GDD §10: cable tension, groaning steel, hissing valves, alarms). Sound would sell the collapse more than anything else left; there is none yet.
- Physical valves (turn the wheel by dragging) and a rope that wraps around corners instead of passing through them.
- Real two-machine and 4-player playtests (only localhost has been tested). Remote-player interpolation.
- Proper low-poly art and a lighting pass. Secondary route for the core. Hazard variation between runs.
