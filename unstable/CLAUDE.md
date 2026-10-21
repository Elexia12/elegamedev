# UNSTABLE — instructions for Claude

Online co-op physics salvage game, Godot 4.7.2 (Jolt physics, GDScript, ENet). The owner is a solo developer.
This folder (`unstable/`) is the Godot project. The repo root also holds an unrelated project, `puddle-slide-3.0/`
(and the `editor-scenes` branch is PuddleSlide's, not UNSTABLE's).

Read first, as needed:
- `PROGRESS.md`: where things stand and what's next.
- `ARCHITECTURE.md`: how the code is organised and why. Follow these decisions.
- `README.md`: how to play each mission, controls, and each level's scene tree.

## Design rules (from the owner)
- North star: *the environment is the enemy, physics is the puzzle, cooperation is the solution — until cooperation
  becomes the problem.* Judge every change against it. Problems are solved physically, not with scripted toggles.
- Keep on-screen and in-world text minimal. Instructions go in the aim prompt. Labels are short and only show up close.
- When a design spec includes a drawing, build its layout and connections faithfully. If the drawing and the text
  disagree, ask which to follow.
- Express systems as editor-visible nodes and scenes, with tuning as `@export`s (doc-commented with `##`) and reactions
  as signal connections in the scene. Don't build structure in code.
- Physics must feel smooth. Collision shapes must match the visible meshes. The trolley's feel is settled: don't make it
  copy R.E.P.O.'s cart.
- Explain player-facing behaviour in plain words. The owner checks feel by playing, so say what changed in play.

## Commands (PowerShell; the Bash tool can't run Godot's quoted path)
```
$g = "C:\Program Files\Godot\Godot.exe"
& $g --headless --path . --editor --quit-after 150      # build the class cache (needed in a fresh checkout/worktree)
& $g --headless --path . --fixed-fps 60 -s res://tests/blackwater_test.gd   # Blackwater acceptance run (111 checks)
& $g --headless --path . --fixed-fps 60 -s res://tests/smoke_test.gd        # Flooded Reactor (29 checks)
```
Network tests run two processes in real time (no `--fixed-fps`, or the host finishes before the client joins): start `-s res://tests/blackwater_net_test.gd -- --role=host` with `Start-Process`,
then the same with `--role=client`. Compare the `[host]` / `[client]` lines; they must agree. `net_test.gd` covers the
reactor. Run all four before committing gameplay changes.

Sounds are placeholders synthesised by `tools/make_sfx.py` into `audio/sfx/` (`python tools/make_sfx.py`). Files named
`*_loop.wav` need `edit/loop_mode=2` in their `.import`. Headless runs can't be listened to: check `playing` instead.

To check visuals, run a windowed script (`--path . --windowed -s <script>`) that saves
`get_viewport().get_texture().get_image()` to a PNG, then look at it. Set `debug_collisions_hint = true` to see
collision shapes. Delete such temporary scripts (and their `.uid`) afterwards.

## Conventions
- GDScript with tabs, typed (`:=`), `class_name` on reusable scripts, `##` doc comments explaining the *why*.
  Match the surrounding code.
- Commit messages: `[+]` for new things, `[*]` for changes. A short subject, then a body explaining the why.
  End with the Co-Authored-By line.
- `main` is the integration branch: the owner tests from it in `C:\Users\XPC\Documents\Godot\elegamedev`. Work on a
  branch, then fast-forward `main` when the work is done and tested.
- Tests drive the game through `Mission.request()` (the same path player input uses). `CrewMember.bot_input` drives
  movement headless, because headless Godot can't capture the mouse. Autoloads (`Net`) aren't visible as identifiers
  in `-s` scripts: use `root.get_node("Net")`.
- Edit `.tscn` files directly. They were first written by a throwaway generator that no longer exists.
