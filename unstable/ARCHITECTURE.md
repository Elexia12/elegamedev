# UNSTABLE — architecture and decisions

How the code is organised, and the decisions behind it that should hold. Level layouts, controls and scene trees are in
`README.md`; status and next steps are in `PROGRESS.md`.

## Session and levels
- `scenes/main.tscn` + `scripts/main.gd` run the session flow: menu → solo/host/join → mission → results → restart.
  `Main.missions` lists the levels in menu order (Blackwater first). The host instantiates its pick under `World`, and
  `MissionSpawner` replicates it to clients.
- `scripts/net.gd` (autoload `Net`) is a thin ENet wrapper. Solo uses `OfflineMultiplayerPeer` and runs the same code.

## One generic Mission, one Contract per level
- The level root is `Mission` (`scripts/facility/mission.gd`). It only does three things: receive player requests,
  run the ending, and replicate state.
- **Decision:** everything level-specific lives in the `%Contract` child, a subclass of `scripts/facility/contract.gd`:
  `ReactorContract` or `SalvageContract`. It owns the HUD status, objectives/manifest, banner, briefing, controls
  hint, how the run ends, and the results data. The HUD (`scripts/ui/hud.gd`) and the results screen only display
  what the Contract returns. New levels add a Contract; they don't touch Mission.
- Some systems are optional (`%PressureNetwork`, `%Toolkit`, `%ExtractionZone`: reactor only). Code guards for null.
  `Crew.loadout` picks which of the player's tools a level hands out (Blackwater: Wrench only).
- **Decision:** systems are editor-visible nodes, with tuning in `@export`s and reactions as signal connections in the
  `.tscn`. The owner reads the game through the scene tree.

## Networking: host-authoritative physics
- The host simulates all props and machines. Clients keep props frozen (kinematic) and interpolate toward replicated
  poses.
- Any node in group `net` implements `net_get()` / `net_set()`. `Mission` packs them all into one `net_state`
  snapshot, and `StateSync` replicates it **on change (reliable)**. Unreliable mode broke because the snapshot is
  bigger than one packet.
- Exception: each player's own movement is client-authoritative (their `Sync` node in `scenes/player/player.tscn`).
- Effects that every peer must show (damage sparks, the `−N cr` popup) are driven by replicated state (`Prop.hits`),
  not by RPCs.

## Input → effect
1. Owner input calls `Mission.send(action, …)`, an RPC to the host's `Mission.request()`, the single entry point.
2. `"use"`: the aimed node's `use(player, target)`. For an `InteractPoint` (`scripts/facility/interact_point.gd`) that
   is `handler()`, the point itself or its nearest ancestor with `use()`/`prompt_for()`. `prompt_for()` writes the HUD
   prompt. A Prop can offer `use_prompt()` / `use()` too (support jack, swing door, trolley).
3. `"drive"`: the movement keys of whoever holds a machine (group `machines`, e.g. `OverheadHoist`).
4. Held actions (grab, reel, blast, wrench) run on the host every physics frame, using that player's replicated aim
   (`CrewMember.set_hold` → `Hands` or the tool with that `hold_kinds()`).
5. Private feedback goes back through `IncidentLog` (`tell`, `end_hold`, `release_grab`), skipping disconnected peers.

## Props, damage and knock-on effects (`scripts/facility/prop.gd`)
- Salvage value = `value × condition`. An impact is the velocity change over the last 3 physics steps while in contact.
  It costs `(impact − damage_threshold) × fragility` percent.
- Every impact is passed to whatever was hit (`take_hit`): that's how the motor ruptures a `PipeRun` or stresses a
  `BridgeSlab`/`DamagedCorridor`.
- A `DepositZone` secures salvage exactly once (`lock_secured`: frozen, moved onto the truck, value locked).

## Physics rules learned the hard way
- **Size a force's gain by the body it's applied to.** Cargo is a separate rigid body, so a force on the 70 kg trolley
  scaled by trolley + 450 kg motor overshoots every step and jitters. Use the body's own mass/inertia, the pair's
  reduced mass for forces between two bodies, or "body + rigidly attached cargo". Keep `gain × dt` well under 1.
  Torques likewise: turn things as an angular acceleration times the body's real inertia tensor (`Hands._world_inertia`),
  never "× mass", or slim shapes (the jack's cylinder) spin up about their long axis.
- **Apply contact-like forces where the contact is** (deck friction at deck height, not at the cargo's centre).
- **Collision shapes match the visible mesh.** No invisible boxes (motor = cylinder on feet; trolley handle = posts +
  bar, with a separate aim-only `InteractPoint`). Held props ignore their holder's body (`Hands._sync_collision_exception`),
  and the trolley leaves held or hoisted cargo alone (`Trolley._lifted`).
- **Jolt solver settings** (`project.godot`): `penetration_slop` 0.002, `position_steps` 6, `velocity_steps` 15. With
  the defaults (2 cm slop, 2 position steps) the loaded trolley's wheels sank 3–5 cm into the floor while rolling,
  caught the side of the next floor piece (corridor slabs) and stopped dead, flinging the motor off.
- Pieces that fall into a gap must be able to: a collapsing `DamagedCorridor` shortens its slabs by `crumble` (shape and
  mesh), or they wedge between each other and the floor edges like an arch.
- Jolt areas don't detect **static**-frozen bodies: anything an Area must still see while frozen uses
  `FREEZE_MODE_KINEMATIC` (`support_jack.gd`).

## Machines and handling
- **Overhead hoist** (`overhead_hoist.gd`): the carriage accelerates gently and brakes hard, so stops swing the load.
  Its controls (the `Pendant` node) can sit anywhere; [E] on the hook still needs you next to it, so in Blackwater (booth
  far above the pit) hooking and unhooking takes a teammate.
  The chain is a one-sided spring whose damping acts on the stretch rate *minus* the payout rate, so lowering at a
  steady speed isn't resisted. You can only unhook a load that's resting on something.
- **Trolley** (`trolley.gd`) handles like a shopping cart:
  - While held, a capped controller holds its position *along its length* and its heading to the pusher's. It is never
    shoved sideways.
  - The pusher is tethered one-way (`CrewMember._tether_to`): you're stopped and lined up, never dragged after it, and
    your yaw is kept within 12° of the cart's heading. Those corrections are wall-checked moves (`_shift`), never
    teleports through walls. Two pushers hold the handle `grip_spread` either side of its middle (bodies are 0.7 m wide).
  - Wheel forces only act while a wheel touches something (`_on_wheels`): a trolley hanging from a hoist doesn't "grip".
  - Fixed wheels at the handle end, casters at the far end.
  - **Cargo sticks** via a `Generic6DOFJoint3D` (static friction, no contact jitter). It breaks loose when the deck's
    acceleration exceeds `deck_friction × g`, or when the hoist or hands lift it. Loose cargo slides with kinetic
    friction and re-sticks once settled. Only bodies touching the deck's top, centred over it, count as cargo
    (`Trolley._resting_on_deck`): cargo that fell off and got rolled onto is never glued back on.
- **Wrench** (`wrench_tool.gd`) works `Mounting`s (unbolting, faster with two people, slips in tremors) and cranks valves.

## Sound
- **Decision:** every sound is driven by replicated state, on every peer, the same way the visuals are. Nothing is sent
  as an RPC. Impacts use a replicated counter (`Prop.bumps` + `bump_strength`; the `ImpactSound` / `DamageSound`
  children play when it changes). Machines and hazards derive their sound from state they already replicate
  (hoist `vx`/`input`/`tension`, mounting `progress`, valve `opening`, pipe `ruptured`, corridor `stress`, `shake`).
- `LoopSound` (`scripts/audio/loop_sound.gd`) is a looping 3D player whose loudness and pitch follow a 0..1 `level`
  set by its owner each frame (or `constant_level` for room tone). Sound nodes live in the scenes, tuned in the Inspector.
- The Master bus has a light reverb (`default_bus_layout.tres`): concrete rooms.
- Sound files are slots with stable names (`audio/sfx/<slot>.wav`, or `<slot>.tres` = an `AudioStreamRandomizer` of
  variations). Scenes reference slots, so swapping or rebuilding a sound never touches a scene. All import uncompressed.

## Presentation
- Text is minimal by design: `ProximityLabel`, the `label_range` / `show_within` exports, a briefing that hides once you
  enter the station (`SalvageContract.briefing()`), and instructions in aim prompts.
- Each level's HUD controls line comes from `Contract.controls_hint()`.
