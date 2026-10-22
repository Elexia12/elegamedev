# Sound credits

Every recording here is **CC0** (public domain): free to use, modify and ship, no attribution required. Credited anyway.
`tools/build_sfx.py` turns the packs below into these files (trimmed, loudness-matched, loops crossfaded).

| Pack | Author | Link | Used for |
|---|---|---|---|
| Impact Sounds | Kenney | https://kenney.nl/assets/impact-sounds | metal, wood impacts; the brake's plate clunk |
| RPG Audio | Kenney | https://kenney.nl/assets/rpg-audio | creaks (the deck settling), metal latch/click (bolts, ratchet) |
| Sci-fi Sounds | Kenney | https://kenney.nl/assets/sci-fi-sounds | low engine (truck), low-frequency explosion (collapse) |
| 75 CC0 breaking / falling / hit sfx | rubberduck | https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx | concrete hits, cracks, damage crunch, collapse |
| 100 CC0 SFX | rubberduck | https://opengameart.org/content/100-cc0-sfx | the pipe burst's slam |
| 100 CC0 SFX #2 | rubberduck | https://opengameart.org/content/100-cc0-sfx-2 | hoist motor, hall hum, inlet water, grit stones |
| 30 CC0 SFX loops | rubberduck | https://opengameart.org/content/30-cc0-sfx-loops | trolley rolling, spray, control-room tone |
| 40 CC0 water / splash / slime SFX | rubberduck | https://opengameart.org/content/40-cc0-water-splash-slime-sfx | pit water |
| Chain winch sounds | (OpenGameArt, CC0) | https://opengameart.org/content/chain-winch-sounds | hoist chain |
| Steam release sounds | (OpenGameArt, CC0) | https://opengameart.org/content/steam-release-sounds | the burst pipe's hiss |
| Tree Creaking | (OpenGameArt, CC0) | https://opengameart.org/content/tree-creaking | the deck creaking under load |
| Dripping water loop | (OpenGameArt, CC0) | https://opengameart.org/content/dripping-water-loop | tunnel drips |
| rumble fx | (OpenGameArt, CC0) | https://opengameart.org/content/rumble-fx | tremors |

To swap a sound: replace its `.wav` (same name), or change the source in `tools/build_sfx.py` and rebuild.

## Rebuilding: where `tools/build_sfx.py` expects the packs
Unzip each into one folder (`<packs>`), then `python tools/build_sfx.py <packs>`:

| Put it at | Download |
|---|---|
| `kenney_impact-sounds/` | https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip |
| `kenney_rpg-audio/` | https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip |
| `kenney_sci-fi-sounds/` | https://kenney.nl/media/pages/assets/sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip |
| `oga/sfx_breaking_and_falling/` | https://opengameart.org/sites/default/files/sfx_breaking_and_falling.zip |
| `oga/100-CC0-SFX_0/` | https://opengameart.org/sites/default/files/100-CC0-SFX_0.zip |
| `oga/sfx_100_v2/` | https://opengameart.org/sites/default/files/sfx_100_v2.zip |
| `oga/sfx_loops/` | https://opengameart.org/sites/default/files/sfx_loops.zip |
| `oga/water-splash-slime-sfx/` | https://opengameart.org/sites/default/files/water-splash-slime-sfx.zip |
| `oga/winch/` | https://opengameart.org/sites/default/files/winch.zip |
| `oga/steam_hisses/` | https://opengameart.org/sites/default/files/steam_hisses.zip |
| `oga/tree_creak.ogg` | https://opengameart.org/sites/default/files/tree_creak.ogg |
| `oga/atmo.mp3` | https://opengameart.org/sites/default/files/atmo.mp3 |
| `oga/rumble.wav` | https://opengameart.org/sites/default/files/rumble.wav |

The packs hold many more sounds than are used (e.g. 11 machine loops, footsteps, splashes): good alternatives.
