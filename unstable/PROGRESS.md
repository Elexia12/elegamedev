# UNSTABLE — progress

_Last updated 2026-10-21 (see `git log` on `main` for the latest change)._

## Where things stand
Two playable greybox missions (the main menu's Mission picker; details in `README.md`):
- **Blackwater Station** (default, "prototype 01"). Built from the Blackwater Station spec's blockout, then re-laid out
  by the owner: bay / control room / pump hall + hoist booth / damaged corridor / maintenance pit / service tunnel.
  - The wrench unbolts salvage and cranks valves.
  - The 450 kg motor starts down in the pit. The overhead hoist, driven from a raised booth with a window, lifts it out
    through a gap in the pit railing onto a shopping-cart-style trolley in the hall.
  - Two routes out: the short corridor (needs a support jack from the pit), or, if it collapses, the hard way: back down
    into the pit and out through the service tunnel (tight turn, debris, floods, a ramp that needs two pushers).
  - Second chance: if the corridor collapses under the motor, the corridor hoist (rail under the corridor ceiling, void
    -> hall) lifts the motor, and the trolley by its deck lug, back out of the wreck.
  - Rising water and a rupturable water main, condition-based salvage value, partial extraction, truck departure,
    station failure at 15 min.
- **The Flooded Reactor** (first prototype, GDD §8): winch / pressure tool, jammed gate, lift extraction.

Tests, all passing on `main`:
- `tests/blackwater_test.gd`: 117 checks.
- `tests/smoke_test.gd`: 29 checks.
- `tests/blackwater_net_test.gd` and `tests/net_test.gd`: host and client agree, over localhost ENet.

## Recently settled (don't reopen without the owner)
- Blackwater layout: the owner's revision of the spec drawing (motor in the pit, hoist booth over the hall, service tunnel
  as the fallback route). Both doors into the pump hall stay 1 m, so the loaded trolley must take the corridor or the
  tunnel. The old pit-to-corridor west ramp is gone.
- Minimal text: briefing hides on entering the station, labels only up close, instructions in aim prompts.
- The trolley's feel is final:
  - held rigidly like a shopping cart, steered with the mouse or A/D (A/D turns, it doesn't side-step)
  - cargo sticks to the deck
  - `deck_friction` 0.85, `push_torque` 1400
  - it must not copy R.E.P.O.'s cart
- Collision shapes match the meshes (motor, trolley handle, support jack).

## Blockers / risks
- No hard blockers.
- Never tested on two real machines or with 3–4 players (localhost only). Remote-player smoothing is untested.
- Sound is synthesised placeholder audio (`tools/make_sfx.py`): it covers everything that matters, but should be
  replaced with real recordings eventually. Not yet: footsteps, the swing door, the support jack, the reactor's
  pressure network.

## Next steps (owner's call on order)
1. Playtest Blackwater (ideally online) and tune from feel:
   - the new layout: hoisting from the booth, the tunnel route's difficulty (debris, ramp, flooding)
   - hoist braking and swing
   - corridor tolerance
   - fragility and damage thresholds
   - flood rates
2. Network readiness: a lag/packet-loss test, and a player disconnecting mid-run.
3. The spec's deferred tool: ratchet straps for the trolley. Also an emergency drain pump.
4. Low-poly art and a lighting pass.

## Sources
- GDD v0.1: `C:\Users\XPC\Downloads\UNSTABLE_Game_Design_Document.pdf`.
- Codecks backlog pack: `C:\Users\XPC\Downloads\UNSTABLE_Codecks_Import_Pack\`.
- Blackwater Station spec: the owner's ChatGPT conversation
  `https://chatgpt.com/share/6ad802e0-2b30-83e8-8fbd-deff1d1689fe`. WebFetch only shows the page title. Download the
  HTML and JSON-decode the `enqueue("…")` stream to read it.
