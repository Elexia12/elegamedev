"""Build UNSTABLE's sound slots (audio/sfx/) from CC0 recordings.

    pip install soundfile numpy
    python tools/build_sfx.py <packs-dir>

<packs-dir> holds the unzipped packs listed in audio/sfx/CREDITS.md (Kenney
and OpenGameArt, all CC0). Each slot keeps the file name the game already
uses, so nothing in the scenes changes when a sound is rebuilt or replaced:
  - one-shots: leading silence trimmed, peak-normalised
  - loops (*_loop): a seamless crossfade, loudness-normalised (per slot: how
    loud it sits under its node's full_db)
  - variations: <slot>_1.wav, <slot>_2.wav… plus <slot>.tres, an
    AudioStreamRandomizer that picks one each time it plays
Everything is written mono, 16-bit, 44.1 kHz. Import settings (uncompressed,
loop mode) live in each file's .import and survive a rebuild.
The old synthesised set is still available: tools/make_sfx.py.
"""
import os
import sys

import numpy as np
import soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "sfx")
PACKS = ""
rng = np.random.default_rng(11)

KENNEY_IMPACT = "kenney_impact-sounds/Audio/"
KENNEY_RPG = "kenney_rpg-audio/Audio/"
KENNEY_SCIFI = "kenney_sci-fi-sounds/Audio/"
BFH = "oga/sfx_breaking_and_falling/"
LOOPS = "oga/sfx_loops/"
V2 = "oga/sfx_100_v2/"
WATER = "oga/water-splash-slime-sfx/"


def load(rel):
    x, sr = sf.read(os.path.join(PACKS, rel), always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        # Band-limited resample in the frequency domain.
        n = int(round(len(x) * SR / sr))
        spec = np.fft.rfft(x)
        keep = min(len(spec), n // 2 + 1)
        out = np.zeros(n // 2 + 1, dtype=complex)
        out[:keep] = spec[:keep]
        x = np.fft.irfft(out, n) * (n / len(x))
    return x


def db(v):
    return 10 ** (v / 20.0)


def trim(x, floor_db=-50.0):
    """Drop leading silence (keep 5 ms before the first sound)."""
    idx = np.where(np.abs(x) > db(floor_db) * (np.max(np.abs(x)) + 1e-9))[0]
    start = max(0, idx[0] - int(0.005 * SR)) if len(idx) else 0
    return x[start:]


def section(x, start, length, fade=0.05):
    a, n = int(start * SR), int(length * SR)
    y = x[a:a + n].copy()
    k = int(fade * SR)
    y[:k] *= np.linspace(0, 1, k)
    y[-k:] *= np.linspace(1, 0, k)
    return y


def fade_out(x, seconds=0.03):
    k = min(len(x), int(seconds * SR))
    x = x.copy()
    x[-k:] *= np.linspace(1, 0, k)
    return x


def mix(*parts):
    """mix((signal, at_seconds, gain_db), ...)"""
    n = max(int(at * SR) + len(s) for s, at, _ in parts)
    out = np.zeros(n)
    for s, at, g in parts:
        i = int(at * SR)
        out[i:i + len(s)] += s * db(g)
    return out


def loop(x, fade=0.4):
    """Seamless loop: fold the last `fade` seconds onto the start."""
    k = int(fade * SR)
    body, tail = x[:-k].copy(), x[-k:]
    r = np.linspace(0, 1, k)
    body[:k] = body[:k] * np.sqrt(r) + tail * np.sqrt(1 - r)
    return body


def norm_peak(x, peak_db=-1.0):
    return x / (np.max(np.abs(x)) + 1e-9) * db(peak_db)


def norm_rms(x, rms_db=-20.0, peak_db=-1.0):
    x = x / (np.sqrt(np.mean(x ** 2)) + 1e-9) * db(rms_db)
    peak = np.max(np.abs(x))
    return x / peak * db(peak_db) if peak > db(peak_db) else x


def write(name, x):
    sf.write(os.path.join(OUT, name + ".wav"), np.clip(x, -1, 1), SR, subtype="PCM_16")
    print("wrote %-24s %.2f s" % (name, len(x) / SR))


def one_shot(name, x, peak_db=-1.0):
    write(name, norm_peak(fade_out(trim(x)), peak_db))


def a_loop(name, x, rms_db=-20.0, fade=0.4):
    write(name, norm_rms(loop(x, fade), rms_db))


def variations(name, clips, peak_db=-1.0):
    """<name>_1..N.wav and <name>.tres (a randomizer over them)."""
    for i, c in enumerate(clips, 1):
        one_shot("%s_%d" % (name, i), c, peak_db)
    lines = ['[gd_resource type="AudioStreamRandomizer" load_steps=%d format=3]' % (len(clips) + 1), ""]
    for i in range(1, len(clips) + 1):
        lines.append('[ext_resource type="AudioStream" path="res://audio/sfx/%s_%d.wav" id="%d"]' % (name, i, i))
    lines += ["", "[resource]", "playback_mode = 0", "random_pitch = 1.0", "random_volume_offset_db = 1.5",
              "streams_count = %d" % len(clips)]
    for i in range(len(clips)):
        lines.append('stream_%d/stream = ExtResource("%d")' % (i, i + 1))
        lines.append("stream_%d/weight = 1.0" % i)
    with open(os.path.join(OUT, name + ".tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %-24s (%d variations)" % (name + ".tres", len(clips)))


def scatter(clips, seconds, count, gain_range=(-18, -6)):
    """Small sounds scattered over a loop-length buffer (wrapping)."""
    n = int(seconds * SR)
    out = np.zeros(n)
    for _ in range(count):
        c = clips[rng.integers(len(clips))] * db(rng.uniform(*gain_range))
        i = int(rng.uniform(0, n))
        first = min(len(c), n - i)
        out[i:i + first] += c[:first]
        out[: len(c) - first] += c[first:]
    return out


def build():
    k = lambda kind: [load(KENNEY_IMPACT + "%s_%03d.ogg" % (kind, i)) for i in range(5)]
    # --- Impacts (5 variations each) ---------------------------------------------
    variations("impact_heavy_metal", k("impactMetal_heavy"))
    variations("impact_light_metal", k("impactMetal_light"))
    variations("impact_crate", k("impactWood_medium"))
    variations("impact_concrete", [load(BFH + f) for f in
                                   ["bfh1_rock_falling_01.ogg", "bfh1_rock_falling_03.ogg", "bfh1_rock_falling_05.ogg",
                                    "bfh1_rock_falling_09.ogg", "bfh1_rock_breaking_01.ogg"]])
    variations("damage_crunch", [load(BFH + f) for f in
                                 ["bfh1_breaking_02.ogg", "bfh1_breaking_03.ogg", "bfh1_metal_hit_02.ogg"]], -3.0)
    variations("crack_snap", [load(BFH + f) for f in
                              ["bfh1_rock_breaking_02.ogg", "bfh1_rock_breaking_03.ogg", "bfh1_rock_falling_04.ogg"]])
    # The deck settling under weight: a strained creak, then a little debris.
    debris = [trim(load(BFH + f)) for f in ["bfh1_rock_falling_07.ogg", "bfh1_rock_falling_08.ogg"]]
    variations("deck_groan", [mix((trim(load(KENNEY_RPG + c)), 0.0, 0.0), (debris[i % 2], 0.32, -9.0))
                              for i, c in enumerate(["creak1.ogg", "creak2.ogg"])])

    # --- One-shots ---------------------------------------------------------------
    one_shot("brake_clunk", mix((trim(load(KENNEY_IMPACT + "impactPlate_heavy_001.ogg")), 0.0, 0.0),
                                (trim(load(KENNEY_RPG + "metalLatch.ogg")), 0.04, -8.0)))
    one_shot("bolt_free", mix((trim(load(KENNEY_RPG + "metalLatch.ogg")), 0.0, 0.0),
                              (trim(load(KENNEY_IMPACT + "impactMetal_light_003.ogg")), 0.12, -4.0)))
    hiss = trim(load("oga/steam_hisses/steam hisses - Marker #4.wav"))
    one_shot("pipe_burst", mix((trim(load("oga/100-CC0-SFX_0/slam_03.ogg")), 0.0, 0.0), (hiss, 0.03, -2.0)))
    rocks = [trim(load(BFH + "bfh1_rock_falling_%02d.ogg" % i)) for i in (1, 3, 5, 6, 9)]
    one_shot("collapse", mix((trim(load(KENNEY_SCIFI + "lowFrequency_explosion_000.ogg")), 0.0, 0.0),
                             (trim(load(BFH + "bfh1_falling_04.ogg")), 0.05, -2.0),
                             (trim(load(BFH + "bfh1_rock_breaking_01.ogg")), 0.15, -1.0),
                             (rocks[0], 0.45, -3.0), (rocks[1], 0.8, -5.0), (rocks[2], 1.1, -6.0),
                             (rocks[3], 1.45, -8.0), (rocks[4], 1.9, -10.0)))
    one_shot("tremor_rumble", section(load("oga/rumble.wav"), 6.4, 4.0, fade=0.6))

    # --- Loops -------------------------------------------------------------------
    a_loop("hoist_motor_loop", load(V2 + "sfx100v2_loop_machine_04.ogg"), -10.0, 0.3)
    a_loop("chain_loop", load("oga/winch/winch - Marker 2.wav"), -18.0, 0.3)
    a_loop("trolley_roll_loop", load(LOOPS + "rolling.ogg"), -15.0, 0.2)
    a_loop("water_gush_loop", load(V2 + "sfx100v2_loop_water_01.ogg"), -15.0, 0.5)
    a_loop("spray_loop", load(LOOPS + "water_flowing.ogg"), -13.0, 0.3)
    a_loop("creak_loop", load("oga/tree_creak.ogg"), -16.0, 0.5)
    a_loop("hum_loop", load(V2 + "sfx100v2_loop_machine_01.ogg"), -10.0, 0.6)
    a_loop("room_tone_loop", load(LOOPS + "ambient_01.ogg"), -10.0, 0.8)
    a_loop("pit_water_loop", load(WATER + "loop_water_02.ogg"), -12.0, 0.6)
    a_loop("drips_loop", load("oga/atmo.mp3"), -14.0, 0.8)
    a_loop("truck_engine_loop", load(KENNEY_SCIFI + "spaceEngineLow_004.ogg"), -10.0, 0.5)
    # Grit trickling out of the cracks: small real stone falls, scattered.
    stones = [trim(load(V2 + "sfx100v2_stones_%02d.ogg" % i)) for i in (1, 2, 3)]
    stones += [trim(load(BFH + "bfh1_rock_falling_%02d.ogg" % i)) for i in (7, 8)]
    a_loop("grit_loop", scatter(stones, 4.0, 14), -18.0, 0.3)
    # The wrench: a real metal click, ratcheting four times a second.
    click = trim(load(KENNEY_RPG + "metalClick.ogg"))
    ratchet = np.zeros(SR)
    for i in range(4):
        c = click * db(rng.uniform(-3, 0))
        j = int(i * SR / 4)
        ratchet[j:j + len(c)] += c[: SR - j]
    write("ratchet_loop", norm_rms(ratchet, -20.0))


if __name__ == "__main__":
    PACKS = sys.argv[1]
    build()
