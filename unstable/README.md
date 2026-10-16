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

## Code map

```
scripts/net.gd                    autoload: host / join / solo / leave
scripts/main.gd                   menu, mission (re)spawn, results, pause
scripts/facility/mission.gd       host simulation, request handling, replication snapshot
scripts/facility/*.gd             gate, support, brace_socket, cable, anchor, valve, flood_zone, prop, …
scripts/player/crew_member.gd     first-person movement, aiming, tool input, host-side holds
scripts/ui/hud.gd                 HUD
scenes/facility/flooded_reactor.tscn   the level (CSG greybox; move things in the editor)
scenes/components/, scenes/props/      reusable pieces with tuning exposed as @export vars
```

**Networking model:** host-authoritative (GDD §11). Each peer moves its own crew member (MultiplayerSynchronizer). Tool
use and grabs are RPC *requests* to the host (`Mission.request`). The host alone simulates physics props, the gate,
supports, water and pressure. It packs all of that into one `net_state` snapshot replicated at 20 Hz. Clients render it
with frozen, interpolated props. Players joining late get the current state. If a client disconnects it's logged as an
incident. If the host leaves, everyone returns to the menu.

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
