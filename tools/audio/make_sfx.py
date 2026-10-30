"""Synthesizes the game's cartoon sound effects (no recordings, no samples) into client/sfx/*.ogg.

    python3 tools/audio/make_sfx.py

Every sound is built from sine / saw / noise with pitch sweeps and envelopes, so they are original
and tiny. Tweak a recipe below and re-run. Needs numpy and ffmpeg (libvorbis).
Each file gets a "keep" .import so Godot exports it as-is; the game loads it at runtime (ui/sfx.gd).
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "client", "sfx")
SR = 22050
rng = np.random.default_rng(7)


def t_(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, attack=0.005, release=None, curve=3.0):
    """Fast attack, exponential-ish decay to 0 over the whole sound (or `release` seconds)."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    total = n / SR if release is None else release
    d = np.clip(1 - t / total, 0, 1) ** curve
    return a * d


def osc(freq, dur, shape="sine"):
    """Oscillator with a per-sample frequency (array or number)."""
    n = int(SR * dur)
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(ph)
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "tri":
        return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1.0) - 1) - 1
    raise ValueError(shape)


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be an array (a sweep)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def sweep(f0, f1, dur, kind="exp"):
    t = np.linspace(0, 1, int(SR * dur))
    return f0 * (f1 / f0) ** t if kind == "exp" else f0 + (f1 - f0) * t


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def seq(*parts, gap=0.0):
    g = np.zeros(int(SR * gap))
    out = []
    for p in parts:
        out += [p, g]
    return np.concatenate(out[:-1]) if out else np.zeros(0)


# --- recipes ------------------------------------------------------------------------------------

def boing():                       # jump: a spring
    d = 0.42
    t = t_(d)
    f = sweep(140, 520, d) * (1 + 0.18 * np.sin(2 * np.pi * 18 * t) * np.exp(-t * 4))
    return osc(f, d) * env(len(t), 0.003, curve=1.6) * 0.8


def thump():                       # landing
    d = 0.16
    return (osc(sweep(120, 45, d), d) * env(int(SR * d), 0.002, curve=2.5)
            + lowpass(noise(d), 600) * env(int(SR * d), 0.001, 0.05) * 0.6)


def whoosh(d=0.18, lo=500, hi=3500):   # swings
    n = noise(d)
    c = np.concatenate([sweep(lo, hi, d * 0.6), sweep(hi, lo, d * 0.4)])
    c = np.pad(c, (0, max(0, len(n) - len(c))), mode="edge")[: len(n)]
    return highpass(lowpass(n, c), 250) * np.sin(np.linspace(0, np.pi, len(n))) ** 1.5 * 1.4


def zip_():                        # dash
    d = 0.13
    return osc(sweep(400, 2400, d), d, "tri") * env(int(SR * d), 0.004, curve=1.2) * 0.35 + whoosh(0.13, 900, 5000) * 0.5


def bonk(f=520, d=0.14):          # light hit: wood block
    t = t_(d)
    body = osc(f * (1 + 0.9 * np.exp(-t * 60)), d) * env(len(t), 0.001, curve=4)
    click = highpass(noise(0.012), 2000) * 0.5
    return mix(body, click)


def doink():                       # heavy hit: bonk + cartoon pitch drop + splat
    d = 0.32
    t = t_(d)
    drop = osc(sweep(900, 180, d), d, "tri") * env(len(t), 0.002, curve=2.2) * 0.7
    return mix(bonk(330, 0.18) * 1.1, drop, splat(0.22) * 0.55)


def splat(d=0.28):                 # ink: wet squelch
    t = t_(d)
    wet = lowpass(noise(d), sweep(2500, 300, d)) * env(len(t), 0.002, curve=2) * 1.6
    bubble = osc(sweep(300, 90, d) * (1 + 0.3 * np.sin(2 * np.pi * 35 * t)), d) * env(len(t), 0.005, curve=3) * 0.5
    return mix(wet, bubble)


def tink():                        # block: metal
    d = 0.22
    parts = [osc(f, d) * env(int(SR * d), 0.001, curve=c) * a for f, a, c in
             [(1850, 0.5, 5), (2730, 0.35, 6), (4120, 0.25, 7), (960, 0.2, 4)]]
    return mix(*parts, highpass(noise(0.01), 3000) * 0.4)


def slide_up(d=0.45):              # launched into the air
    t = t_(d)
    f = sweep(500, 1900, d) * (1 + 0.012 * np.sin(2 * np.pi * 7 * t))
    return lowpass(osc(f, d, "tri"), 4000) * np.sin(np.linspace(0, np.pi, len(t))) ** 0.6 * 0.5


def slide_down(d=0.5):
    return slide_up(d)[::-1].copy()


def crash():                       # knockdown: thud + bouncing boings
    b1 = osc(sweep(260, 140, 0.12), 0.12) * env(int(SR * 0.12), 0.002) * 0.4
    b2 = osc(sweep(240, 130, 0.09), 0.09) * env(int(SR * 0.09), 0.002) * 0.25
    return mix(thump() * 1.4, np.concatenate([np.zeros(int(SR * 0.14)), b1, np.zeros(int(SR * 0.05)), b2]))


def squeak():                      # grab: rubber duck
    d = 0.2
    t = t_(d)
    f = 1150 + 250 * np.sin(2 * np.pi * 22 * t) + sweep(0, 300, d, "lin")
    return lowpass(osc(f, d, "saw"), 3000) * env(len(t), 0.01, curve=1.5) * 0.35


def kazoo(notes, note_d=0.16, gap=0.02, vib=6.0):
    """Buzzy kazoo voice: saw with vibrato, a nasal band-pass feel from two filters."""
    out = []
    for i, n in enumerate(notes):
        d = note_d * (2.6 if i == len(notes) - 1 else 1.0)
        t = t_(d)
        f = n * (1 + 0.025 * np.sin(2 * np.pi * vib * t))
        x = osc(f, d, "saw") + 0.4 * osc(f * 2.01, d, "saw")
        x = highpass(lowpass(x, 2600), 350)
        e = np.clip(t / 0.02, 0, 1) * np.clip((d - t) / 0.05, 0, 1)
        out.append(x * e * 0.45)
    return seq(*out, gap=gap)


def sad_trombone():                # KO: wah wah wah waaah
    out = []
    for i, n in enumerate([311, 294, 277, 262]):
        d = 0.32 if i < 3 else 1.1
        t = t_(d)
        bend = 1 - (0.06 * np.clip((t - 0.15) / 0.17, 0, 1) if i < 3 else 0)
        wob = 1 + (0.03 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.3, 0, 1) if i == 3 else 0)
        x = osc(n * bend * wob, d, "saw")
        x = lowpass(x, 300 + 1500 * np.clip(t / 0.06, 0, 1) * np.exp(-t * 2.5))   # "wah" mute
        e = np.clip(t / 0.03, 0, 1) * np.clip((d - t) / 0.08, 0, 1)
        out.append(x * e * 0.9)
    return seq(*out, gap=0.03)


def air_horn():                    # FIGHT!
    d = 0.75
    t = t_(d)
    chord = sum(osc(f * (1 + 0.004 * np.sin(2 * np.pi * 6 * t)), d, "saw") for f in (466, 554, 698))
    x = lowpass(chord, 3200) * np.clip(t / 0.03, 0, 1) * np.clip((d - t) / 0.12, 0, 1)
    return x * 0.3


def ding():                        # round start bell
    d = 1.0
    return mix(*[osc(f, d) * env(int(SR * d), 0.001, curve=c) * a for f, a, c in
                 [(1320, 0.5, 3), (2640, 0.2, 5), (3960, 0.12, 7), (1985, 0.15, 4)]])


def power_up():                    # super flash: rising arpeggio + sparkle
    notes = [523, 659, 784, 1047, 1319, 1568]
    out = []
    for n in notes:
        d = 0.06
        out.append(osc(n, d, "square") * env(int(SR * d), 0.002, curve=1.5) * 0.18)
    arp = np.concatenate(out)
    sparkle = highpass(noise(0.5), 5000) * env(int(SR * 0.5), 0.2, curve=2) * 0.2
    return mix(arp, np.concatenate([np.zeros(int(SR * 0.2)), sparkle]))


def party_horn():                  # victory: ta-da kazoo + noisemaker
    return mix(kazoo([523, 659, 784], note_d=0.12, gap=0.01) * 0.9,
               np.concatenate([np.zeros(int(SR * 0.4)), squeak() * 0.6]))


def blip():                        # menu move
    d = 0.05
    return osc(880, d, "square") * env(int(SR * d), 0.001, curve=2) * 0.15


def boop():                        # menu select
    d = 0.12
    return osc(sweep(660, 990, d), d, "square") * env(int(SR * d), 0.002, curve=1.5) * 0.18


def honk():                        # counter hit: clown horn
    d = 0.22
    t = t_(d)
    f = 330 * (1 + 0.04 * np.sin(2 * np.pi * 30 * t))
    x = highpass(lowpass(osc(f, d, "square") + osc(f * 1.5, d, "saw") * 0.5, 1800), 200)
    return x * np.clip(t / 0.01, 0, 1) * np.clip((d - t) / 0.04, 0, 1) * 0.5


SOUNDS = {
    "jump": boing, "land": thump, "dash": zip_,
    "whoosh_light": lambda: whoosh(0.14, 700, 4500) * 0.8, "whoosh_heavy": lambda: whoosh(0.26, 300, 2600),
    "hit_light": bonk, "hit_heavy": doink, "counter": honk, "block": tink,
    "splat": splat, "launch": slide_up, "fall": slide_down, "knockdown": crash, "grab": squeak,
    "super": power_up, "ko": sad_trombone, "fight": air_horn, "round": ding, "win": party_horn,
    "menu_move": blip, "menu_select": boop,
}


def write(name, x):
    x = np.asarray(x, dtype=np.float64)
    x = x * (0.9 / max(1e-6, np.max(np.abs(x))))    # same peak level for every sound; the game sets the mix
    pcm = (x * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = tmp.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-c:a", "libvorbis", "-q:a", "3", out], check=True)
    os.remove(path)
    with open(out + ".import", "w") as f:
        f.write('[remap]\n\nimporter="keep"\n')
    return os.path.getsize(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for name, make in SOUNDS.items():
        total += write(name, make())
    print(f"{len(SOUNDS)} sounds, {total / 1024:.0f} KB in {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
