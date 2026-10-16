# UNSTABLE — prototype

Greybox prototype of **The Flooded Reactor** (GDD v0.1 §8), built in Godot 4.7 (Jolt).
It covers the GDD's immediate prototype sequence (§19 A–E) in one small facility:
heavy cargo + winch, a two-person task, legible environmental consequences,
host/join over ENet, and start → extraction → results → restart.

## Run

- Open `unstable/` in Godot 4.7 and press F5. Choose **Play solo**, **Host**, or **Join** (IP, port 24565).
- Command-line shortcuts: `-- --solo`, `-- --host`, `-- --join=192.168.1.20`.
- Two-machine test: one player hosts (forward UDP 24565 if not on LAN), the other joins by IP.

## Controls

| Input | Action |
|---|---|
| WASD / Shift / Space | Move / sprint / jump (hold Space to swim up) |
| E | Grab/drag props (toggle), pull the extraction lever |
| 1 2 3, Q, wheel | Winch / Brace / Pressure tool |
| LMB / RMB | Tool primary / secondary (see below) |
| R | Detach a cable / recover a brace |
| Esc | Menu (the facility keeps running) |

Input actions live in Project Settings → Input Map.

## The mission

Pull the **reactor core** (300 kg, primary) out from behind the jammed gate and onto the green **lift pad**, then pull the
**extraction lever** (8 s countdown, cancellable). Optional: the **bonus container** in the flooding storage room. It
loses value while submerged. The facility collapses at 12:00; anything not extracted by then is lost.

**Tools**
- **Winch**: LMB a yellow hook (on the core, the container, the gate, the beam), then LMB a yellow anchor to rig a cable.
  Hold LMB/RMB on either end to reel in/out. Cables stall at 3.8 kN and snap above 5.2 kN. 3 cables per team.
- **Brace**: LMB an orange brace plate. Bracing a support slows its decay and slowly heals it. Bracing the gate holds it
  open. Braces wear under load and snap. 3 braces per team.
- **Pressure**: LMB/RMB a valve to open/close it 25%. Otherwise LMB blasts and RMB pulls loose props.

**Systems (all host-simulated)**
- **Pressure network** builds up over time. The *Gate jack* valve lifts the gate with that pressure. The *Drain pump*
  bleeds pressure and empties the storage room, but dumps the water into the main hall. At 100% for 3 s a line bursts and
  floods the hall.
- **Flooding**: per-zone water levels (no fluid sim). Water slows crew, can drown them (knocked out, then respawn), and
  adds buoyancy/drag to cargo.
- **Structural instability**: *Gate frame* and *Gantry strut* go Stable → Strained → Critical → Failed with time and with
  cable tension on anchors bolted to them. Using the tempting gate-ceiling or gantry anchors is a trade-off. Gate frame
  failure kills the jack, so the gate drops unless braced. Gantry failure drops a 180 kg beam across the hall.
- **Co-op weight**: one crew member grabs with at most 950 N, so the core needs two people (or the winch). The container
  can be dragged solo.
- **Results**: Full / Successful / Partial / Failure, cargo value, objectives, duration, incident log.

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

**`scenes/facility/flooded_reactor.tscn`**: the level. The root `Mission` only handles player requests, the outcome and replication.
```
FloodedReactor (Mission)
├─ MissionClock           time → instability (0→1) → phases; emits collapsed
├─ PressureNetwork        pressure rises by itself; held at 100% it bursts → floods burst_zone
├─ DrainPump              valve + network: moves water source → target, spends pressure
├─ IncidentLog            broadcasts / toasts / incident list  (signals → HUD)
├─ Toolkit                team equipment: Cable1-3 (add children for more) + team_braces
├─ Crew (CrewRoster)      spawns a player per peer
│  ├─ Members             players live here
│  ├─ PlayerSpawner       replicates them
│  └─ SpawnPoints         where they (re)spawn
├─ StateSync              replicates Mission.net_state (snapshot of every "net" node)
├─ HUD                    scenes/ui/hud.tscn
├─ Environment, Geometry, Piping (CSG greybox, signs, burst steam)
├─ Gate                   jack_valve + pressure_network wired in Inspector
├─ Supports
│  ├─ SupportGateFrame    failed → Gate.frame_failed
│  └─ SupportGantry       failed → GantryBeam.wake
├─ GantryBeam             dormant debris (+ AnchorGantry bolted to SupportGantry)
├─ Anchors                cable end points (support_path = which support they strain)
├─ Manifold               JackValve, DrainValve
├─ Cargo                  ReactorCore (primary), BonusContainer (optional), salvage
├─ Water                  LowerFlood, BonusFlood (FloodZones; their FloodVolume children preview in the editor)
└─ Extraction             ExtractionZone (departed → Mission), ExtractionLever
```
Change `level` on a FloodZone in the editor to see the water. Change `collapse_time` on
MissionClock, or a support's decay rates, to retune a run.

**`scenes/player/player.tscn`**: one crew member (`scripts/player/`)
```
Player (CrewMember)       movement, mouse look, aiming, input routing
├─ Head/Camera3D
│  ├─ InteractRay         finds hooks/anchors/valves/levers (6 m, interact layer)
│  └─ GrabRay             finds props and walls (4 m)
├─ Head/ToolModel         the box in your hand, coloured by the current tool
├─ Tools                  child order = hotkeys 1-3
│  ├─ Winch (WinchTool)   hook → anchor, reel in/out
│  ├─ Brace (BraceTool)   place / recover braces
│  └─ Pressure (PressureTool)  turn valves, blast / pull props
├─ Hands                  E to grab; grab_force decides what one person can move
├─ Vitals                 breath & knockout  (knocked_out/recovered → CrewMember)
└─ Sync                   replicates position, rotation, aim, tool, Vitals.knocked
```

**Components** (`scenes/components/`, `scenes/props/`): Gate, Support, BraceSocket, Anchor,
Cable, Valve, ExtractionLever, InteractPoint (the generous aim sphere tools look for),
FloodVolume, and the Prop scenes (core, container, salvage, beam).

**How a click becomes an effect:** the player's tool calls `Mission.send(action, …)`. That RPC
reaches the host's `Mission.request()`, which hands it to the node that owns the behaviour
(Toolkit, Valve, ExtractionZone…). For held actions (grab, reel, blast), the host runs the matching player child
(Hands / WinchTool / PressureTool) every physics frame using that player's replicated aim.

**Replication:** any node in group `net` implements `net_get()` / `net_set()`. The host packs
them all into `Mission.net_state` 60 times a second, and StateSync sends it at 20 Hz. Clients
apply it, and their props stay frozen and interpolate. Player movement is the exception: each player's
own `Sync` node sends it from their machine.

## Tests

```
godot --headless --path . --fixed-fps 60 -s res://tests/smoke_test.gd
```
These check the solo drag limit, two-crew drag, jack/gate/brace, winching the core out, gantry collapse, overpressure
burst, drain, extraction → FULL RECOVERY, and restart.

```
godot --headless --path . -s res://tests/net_test.gd -- --role=host   # then, in a second terminal:
godot --headless --path . -s res://tests/net_test.gd -- --role=client
```
This checks over real ENet sockets that the client sees the host's winched core and that the host applies the client's
valve request.

## Not yet / next steps
- Audio (GDD §10: cable tension, groaning steel, hissing valves, alarms). There is no sound yet.
- Real two-machine and 4-player playtests (only localhost has been tested). Remote-player interpolation.
- Proper low-poly art, a ceiling and lighting pass. Secondary route for the core. Hazard variation between runs.
