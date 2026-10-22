"""Synthesise UNSTABLE's original placeholder sound effects into audio/synth/*.wav.

    python tools/make_sfx.py

Everything here is generated (no samples, no licences). Swap any file for a
real recording with the same name and the game picks it up. Loops (names
ending in _loop) are built to repeat seamlessly; their .import files set
loop_mode so Godot plays them on repeat. Import them uncompressed
(compress/mode=0): Godot's lossy QOA makes noisy sounds grainy.
Bodies ring through their resonant modes (`strike`, `stick_slip`), which
sounds far more natural than pure sine partials.
"""
import os
import wave
import zlib

import numpy as np

SR = 44100
# The game now uses recorded sounds (tools/build_sfx.py). This writes the old
# synthesised set somewhere harmless; copy files over a slot to use one.
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "synth")
rng = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(seconds * SR)) / SR


def noise(seconds):
    return rng.uniform(-1.0, 1.0, int(seconds * SR))


def band(x, lo, hi):
    """Brick-wall band-pass in the frequency domain (fine for noise)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    spec[(f < lo) | (f > hi)] = 0.0
    return np.fft.irfft(spec, len(x))


def lowpass(x, hi):
    return band(x, 0.0, hi)


def decay(seconds, tau):
    return np.exp(-t(seconds) / tau)


def ring(seconds, freqs, taus, amps=None):
    """Inharmonic struck-metal partials."""
    tt = t(seconds)
    out = np.zeros_like(tt)
    amps = amps or [1.0] * len(freqs)
    for f, tau, a in zip(freqs, taus, amps):
        out += a * np.sin(2 * np.pi * f * tt + rng.uniform(0, 6.28)) * np.exp(-tt / tau)
    return out


def convolve(a, b):
    """Linear convolution via FFT (numpy only)."""
    n = len(a) + len(b) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(a, size) * np.fft.rfft(b, size), size)[:n]


def modes_ir(seconds, modes, detune=0.03):
    """Impulse response of a resonant body: (freq, decay tau, amplitude) modes,
    each detuned a little so no two generated sounds are identical."""
    tt = t(seconds)
    out = np.zeros_like(tt)
    for f, tau, a in modes:
        f *= 1.0 + rng.uniform(-detune, detune)
        out += a * np.sin(2 * np.pi * f * tt + rng.uniform(0, 6.28)) * np.exp(-tt / tau)
    return out


def strike(seconds, modes, hardness=6000.0, contact=0.004):
    """A body struck once: a short noise burst ringing its modes."""
    exc = lowpass(noise(contact * 4), hardness) * decay(contact * 4, contact)
    return convolve(exc, modes_ir(seconds, modes))[: int(seconds * SR)]


def stick_slip(seconds, rate0, rate1, modes, jitter=0.25, env=None):
    """A creak: friction sticking and slipping, a train of tiny impulses whose
    rate sweeps rate0 -> rate1 (Hz), ringing the structure's modes."""
    n = int(seconds * SR)
    imp = np.zeros(n)
    pos = 0.0
    while True:
        frac = pos / seconds
        rate = rate0 + (rate1 - rate0) * frac
        rate *= 1.0 + 0.15 * np.sin(2 * np.pi * 3.0 * pos)
        pos += max(0.002, rng.normal(1.0, jitter)) / rate
        if pos >= seconds:
            break
        imp[int(pos * SR)] += rng.uniform(0.4, 1.0)
    shape = np.sin(np.pi * np.linspace(0, 1, n)) ** 0.7 if env is None else env
    return convolve(imp * shape, modes_ir(0.12, modes))[:n]


# The deck: steel and concrete under load.
DECK_MODES = [(160, 0.025, 1.0), (380, 0.018, 0.8), (790, 0.012, 0.6), (1450, 0.008, 0.45), (2600, 0.005, 0.3)]


def thump(seconds, f0, f1, tau):
    """A low body hit: a sine sweeping down from f0 to f1."""
    tt = t(seconds)
    f = f1 + (f0 - f1) * np.exp(-tt / 0.04)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.exp(-tt / tau)


def pad(x, seconds):
    n = int(seconds * SR)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def place(buf, x, at):
    i = int(at * SR)
    j = min(len(buf), i + len(x))
    buf[i:j] += x[: j - i]


def wrap_add(buf, x, at):
    """Add x into a loop buffer, wrapping past the end (for seamless loops)."""
    i = int(at * SR) % len(buf)
    n = len(x)
    first = min(n, len(buf) - i)
    buf[i:i + first] += x[:first]
    if n > first:
        buf[: n - first] += x[first:]


def crossfade_loop(x, fade):
    """Make x loop seamlessly: fold the last `fade` seconds onto the start."""
    k = int(fade * SR)
    body, tail = x[:-k].copy(), x[-k:]
    ramp = np.linspace(0.0, 1.0, k)
    body[:k] = body[:k] * ramp + tail * (1.0 - ramp)
    return body


def normalise(x, peak_db=-1.0):
    peak = np.max(np.abs(x)) or 1.0
    return x / peak * (10 ** (peak_db / 20.0))


def save(name, x, peak_db=-1.0):
    x = normalise(x, peak_db)
    # Fade the very ends of one-shots to avoid clicks.
    if not name.endswith("_loop"):
        k = min(len(x) // 4, int(0.004 * SR))
        x[:k] *= np.linspace(0, 1, k)
        x[-k * 4:] *= np.linspace(1, 0, k * 4)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("wrote", name)


def tick(freq_lo, freq_hi, tau):
    """A short metallic click."""
    s = 0.06
    return band(noise(s), freq_lo, freq_hi) * decay(s, tau)


# --- Impacts -------------------------------------------------------------------------

def impact_heavy_metal():
    """A heavy steel casing: deep body thud, long inharmonic ring, rattle."""
    s = 1.4
    x = 1.0 * thump(s, 130, 46, 0.16)
    x += 1.4 * strike(s, [(118, 0.55, 1.0), (251, 0.42, 0.8), (397, 0.33, 0.7), (611, 0.25, 0.55), (884, 0.18, 0.45),
                          (1213, 0.13, 0.35), (1660, 0.09, 0.25), (2270, 0.06, 0.18), (3050, 0.04, 0.12)], hardness=5000)
    x += 0.35 * band(noise(s), 150, 2500) * decay(s, 0.03)
    return x


def impact_light_metal():
    """A smaller steel part: bright clank, shorter ring."""
    s = 0.8
    x = 0.5 * thump(s, 320, 140, 0.04)
    x += 1.3 * strike(s, [(530, 0.28, 1.0), (1210, 0.2, 0.8), (1990, 0.14, 0.65), (2920, 0.1, 0.5), (3950, 0.07, 0.35),
                          (5300, 0.05, 0.25)], hardness=9000, contact=0.002)
    x += 0.3 * band(noise(s), 2000, 9000) * decay(s, 0.008)
    return x


def impact_crate():
    """Wood: a dull knock with short, heavily damped body modes."""
    s = 0.5
    x = 0.8 * thump(s, 170, 80, 0.06)
    x += 1.2 * strike(s, [(142, 0.05, 1.0), (318, 0.035, 0.8), (531, 0.025, 0.6), (790, 0.018, 0.45), (1120, 0.012, 0.3),
                          (1650, 0.008, 0.2)], hardness=4000, contact=0.003)
    x += 0.4 * band(noise(s), 300, 3000) * decay(s, 0.02)
    return x


def impact_concrete():
    s = 1.4
    grains = np.zeros(int(s * SR))
    for _ in range(40):
        at = abs(rng.normal(0.0, 0.18))
        g = band(noise(0.05), 300, 4000) * decay(0.05, 0.01) * rng.uniform(0.2, 1.0)
        place(grains, g, at)
    x = 1.1 * thump(s, 90, 38, 0.25)
    x += 0.8 * lowpass(noise(s), 900) * decay(s, 0.12)
    x += 0.6 * grains
    return x


def damage_crunch():
    s = 0.6
    tt = t(s)
    squeal_f = 1900 - 1000 * tt / s
    squeal = np.sin(2 * np.pi * np.cumsum(squeal_f) / SR) * np.exp(-tt / 0.2)
    crackle = band(noise(s), 2000, 9000) * (rng.random(len(tt)) < 0.05) * 6
    x = 0.5 * squeal + 0.6 * band(noise(s), 800, 6000) * np.exp(-tt / 0.12) + 0.4 * crackle * np.exp(-tt / 0.25)
    x += 0.6 * thump(s, 200, 70, 0.06)
    return x


# --- Hoist -----------------------------------------------------------------------------

def hoist_motor_loop():
    s = 2.0
    tt = t(s)
    x = np.zeros_like(tt)
    for k in range(1, 18):
        x += np.sin(2 * np.pi * 110 * k * tt) / k ** 1.3
    x += 0.5 * np.sin(2 * np.pi * 880 * tt) + 0.25 * np.sin(2 * np.pi * 1320 * tt)
    x *= 1.0 + 0.08 * np.sin(2 * np.pi * 5 * tt)
    hiss = crossfade_loop(band(noise(s + 0.2), 2000, 8000), 0.2)
    return 0.8 * x + 0.15 * hiss


def chain_loop():
    s = 1.5
    buf = np.zeros(int(s * SR))
    for _ in range(int(s * 18)):
        wrap_add(buf, tick(2500, 7000, 0.006) * rng.uniform(0.3, 1.0), rng.uniform(0, s))
    for _ in range(int(s * 6)):
        wrap_add(buf, 0.5 * ring(0.08, [1800, 2900], [0.02, 0.015]), rng.uniform(0, s))
    return buf


def brake_clunk():
    s = 0.9
    x = 1.0 * thump(s, 160, 60, 0.08)
    x += 0.5 * ring(s, [290, 700, 1240], [0.3, 0.2, 0.12])
    tail = np.zeros(int(s * SR))
    for i in range(10):
        place(tail, tick(2500, 7000, 0.006) * (1.0 - i / 12), 0.05 + i * 0.045 + rng.uniform(0, 0.02))
    return x + 0.6 * tail


# --- Trolley ---------------------------------------------------------------------------

def trolley_roll_loop():
    s = 1.0
    rumble = crossfade_loop(lowpass(noise(s + 0.2), 260), 0.2)
    buf = np.zeros(int(s * SR))
    for i in range(6):
        wrap_add(buf, band(noise(0.04), 300, 2500) * decay(0.04, 0.008), i / 6.0)
    squeak = 0.12 * np.sin(2 * np.pi * 1400 * t(s)) * (0.5 + 0.5 * np.sin(2 * np.pi * 3 * t(s))) ** 4
    return 1.0 * rumble + 0.5 * buf + squeak


# --- Water -----------------------------------------------------------------------------

def water_gush_loop():
    s = 3.0
    x = band(noise(s + 0.4), 250, 3500)
    am = 1.0 + 0.35 * lowpass(noise(s + 0.4), 6) / 0.02
    x = x * np.clip(am, 0.3, 1.8)
    x += 0.4 * lowpass(noise(s + 0.4), 200)
    return crossfade_loop(x, 0.4)


def spray_loop():
    s = 2.0
    x = band(noise(s + 0.3), 1800, 11000) + 0.4 * band(noise(s + 0.3), 300, 1800)
    return crossfade_loop(x, 0.3)


def pipe_burst():
    s = 1.6
    tt = t(s)
    bang = 1.2 * band(noise(s), 60, 6000) * np.exp(-tt / 0.04) + 1.0 * thump(s, 120, 45, 0.15)
    hiss = band(noise(s), 1500, 11000) * np.clip(tt / 0.15, 0, 1) * np.exp(-np.maximum(tt - 0.6, 0) / 0.8)
    return bang + 0.5 * hiss


# --- Structure -------------------------------------------------------------------------

def groan(seconds, f0, f1):
    tt = t(seconds)
    f = np.linspace(f0, f1, len(tt)) * (1.0 + 0.03 * np.sin(2 * np.pi * 7 * tt))
    phase = 2 * np.pi * np.cumsum(f) / SR
    x = sum(np.sin(k * phase) / k for k in range(1, 9))
    rough = 1.0 + 0.6 * band(noise(seconds), 20, 80) / 0.05
    env = np.sin(np.pi * tt / seconds) ** 1.5
    return x * np.clip(rough, 0.2, 2.0) * env


def creak_loop():
    """The deck under load: stressed creaks of different pitch and length,
    small ticks, and a faint low strain underneath."""
    s = 6.0
    buf = np.zeros(int(s * SR))
    for at, length, r0, r1, amp in [(0.2, 1.1, 35, 70, 1.0), (1.7, 0.6, 90, 60, 0.6), (2.6, 1.4, 22, 48, 0.9),
                                   (4.3, 0.8, 55, 110, 0.7), (5.3, 0.5, 70, 40, 0.5)]:
        wrap_add(buf, amp * stick_slip(length, r0, r1, DECK_MODES), at)
    for _ in range(12):
        wrap_add(buf, 0.35 * band(noise(0.03), 900, 6000) * decay(0.03, 0.004), rng.uniform(0, s))
    under = crossfade_loop(lowpass(noise(s + 0.5), 90), 0.5)
    return buf + 0.08 * under / (np.max(np.abs(under)) or 1.0)


def collapse():
    s = 3.5
    buf = np.zeros(int(s * SR))
    for i in range(7):
        hit = impact_concrete() * rng.uniform(0.4, 1.0)
        place(buf, hit, max(0.0, rng.normal(0.3 + i * 0.25, 0.08)))
    tt = t(s)
    buf += 1.4 * lowpass(noise(s), 120) * np.exp(-tt / 1.2) + 0.8 * np.sin(2 * np.pi * 34 * tt) * np.exp(-tt / 1.0)
    return buf


def tremor_rumble():
    s = 3.0
    tt = t(s)
    env = np.clip(tt / 0.6, 0, 1) * np.exp(-np.maximum(tt - 0.8, 0) / 0.9)
    x = lowpass(noise(s), 140) * 3.0 + 0.8 * np.sin(2 * np.pi * 31 * tt)
    grit = np.zeros(int(s * SR))
    for _ in range(25):
        place(grit, band(noise(0.03), 1500, 6000) * decay(0.03, 0.006) * rng.uniform(0.1, 0.5), rng.uniform(0.2, 2.2))
    return x * env + grit


def crack_snap():
    """Concrete cracking under load: a sharp snap, grit, a short low knock."""
    s = 0.7
    tt = t(s)
    snap = band(noise(s), 1200, 12000) * np.exp(-tt / 0.008)
    grit = np.zeros(int(s * SR))
    for _ in range(14):
        place(grit, band(noise(0.025), 2000, 9000) * decay(0.025, 0.004) * rng.uniform(0.1, 0.6), abs(rng.normal(0.03, 0.08)))
    knock = thump(s, 180, 70, 0.05)
    return 1.3 * snap + 0.6 * grit + 0.6 * knock + 0.3 * lowpass(noise(s), 600) * np.exp(-tt / 0.1)


def deck_groan():
    """Weight coming onto the deck: it settles - a slow, deep stressed creak
    that tightens, a crunch, then grit trickling."""
    s = 2.0
    n = int(s * SR)
    env = np.concatenate([np.linspace(0, 1, n // 5), np.ones(n // 2), np.linspace(1, 0, n - n // 5 - n // 2)])
    creak = stick_slip(s, 14, 52, [(110, 0.03, 1.0), (260, 0.022, 0.8), (560, 0.015, 0.6), (1100, 0.009, 0.4),
                                   (2100, 0.006, 0.25)], jitter=0.35, env=env)
    x = 1.0 * creak
    place(x, 0.5 * thump(0.4, 120, 55, 0.06), 0.02)
    crunch = np.zeros(n)
    for _ in range(18):
        place(crunch, band(noise(0.03), 1500, 8000) * decay(0.03, 0.005) * rng.uniform(0.1, 0.7), abs(rng.normal(0.9, 0.35)))
    return x + 0.5 * crunch


def grit_loop():
    """Dust and grit trickling out of the cracks."""
    s = 2.0
    buf = np.zeros(int(s * SR))
    for _ in range(int(s * 60)):
        wrap_add(buf, band(noise(0.02), 2500, 10000) * decay(0.02, 0.003) * rng.uniform(0.05, 0.5), rng.uniform(0, s))
    hiss = crossfade_loop(band(noise(s + 0.3), 3000, 9000), 0.3)
    return buf + 0.15 * pad(hiss, s)


# --- Machines and ambience ----------------------------------------------------------------

def hum_loop():
    s = 4.0
    tt = t(s)
    x = np.sin(2 * np.pi * 50 * tt) + 0.6 * np.sin(2 * np.pi * 100 * tt) + 0.3 * np.sin(2 * np.pi * 150 * tt)
    x += 0.15 * np.sin(2 * np.pi * 400 * tt)
    air = crossfade_loop(lowpass(noise(s + 0.5), 500), 0.5)
    return 0.6 * x + 0.5 * air


def ratchet_loop():
    s = 1.0
    buf = np.zeros(int(s * SR))
    for i in range(8):
        wrap_add(buf, tick(1500, 6000, 0.01) + 0.5 * ring(0.06, [950], [0.015]), i / 8.0)
    return buf


def bolt_free():
    s = 0.6
    return 0.7 * impact_light_metal()[: int(s * SR)] + 0.4 * ring(s, [1980, 2650], [0.15, 0.1])


def truck_engine_loop():
    s = 2.0
    tt = t(s)
    pulses = np.zeros_like(tt)
    for k in range(1, 12):
        pulses += np.sin(2 * np.pi * 25 * k * tt + k) / k
    x = lowpass(pulses * (1.0 + 0.2 * np.sin(2 * np.pi * 12.5 * tt)), 500)
    rumble = crossfade_loop(lowpass(noise(s + 0.2), 180), 0.2)
    return x + 0.4 * rumble


SOUNDS = {
    "impact_heavy_metal": impact_heavy_metal,
    "impact_light_metal": impact_light_metal,
    "impact_crate": impact_crate,
    "impact_concrete": impact_concrete,
    "damage_crunch": damage_crunch,
    "hoist_motor_loop": hoist_motor_loop,
    "chain_loop": chain_loop,
    "brake_clunk": brake_clunk,
    "trolley_roll_loop": trolley_roll_loop,
    "water_gush_loop": water_gush_loop,
    "spray_loop": spray_loop,
    "pipe_burst": pipe_burst,
    "creak_loop": creak_loop,
    "collapse": collapse,
    "tremor_rumble": tremor_rumble,
    "hum_loop": hum_loop,
    "ratchet_loop": ratchet_loop,
    "bolt_free": bolt_free,
    "truck_engine_loop": truck_engine_loop,
    # Added later: kept at the end so the sounds above stay identical.
    "crack_snap": crack_snap,
    "deck_groan": deck_groan,
    "grit_loop": grit_loop,
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, make in SOUNDS.items():
        # Each sound has its own random stream, so changing one never changes another.
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        save(name, make())
