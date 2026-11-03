# Makes the Pack Brawl sound effects and music stings from scratch (pure synthesis, no samples),
# so the game owns every sound. Writes assets/sounds/<name>.ogg (and .wav with --wav).
# Usage: python3 tools/make_sounds.py   (needs numpy and ffmpeg)
import math, os, subprocess, sys, wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
rng = np.random.default_rng(7)


def t_(dur):
    return np.arange(int(dur * SR)) / SR


def env_exp(dur, decay, attack=0.002):
    t = t_(dur)
    e = np.exp(-t / decay)
    a = np.clip(t / attack, 0, 1) if attack > 0 else 1
    return e * a


def sweep(f0, f1, dur, curve="exp"):
    t = t_(dur)
    if curve == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:
        f = f0 + (f1 - f0) * t / dur
    return 2 * np.pi * np.cumsum(f) / SR


def sine(f, dur, phase=0):
    return np.sin(2 * np.pi * f * t_(dur) + phase)


def saw(f, dur):
    ph = (f * t_(dur)) % 1
    return 2 * ph - 1


def square(f, dur):
    return np.sign(np.sin(2 * np.pi * f * t_(dur)))


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be a number or an array (sweeps)."""
    c = np.broadcast_to(np.asarray(cutoff, float), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def pad(x, dur):
    n = int(dur * SR)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts, dur=None):
    n = max(len(p) for p in parts) if dur is None else int(dur * SR)
    out = np.zeros(n)
    for p in parts:
        m = min(n, len(p))
        out[:m] += p[:m]
    return out


def at(x, start, dur):
    """Place x starting at `start` seconds inside a buffer of `dur` seconds."""
    out = np.zeros(int(dur * SR))
    s = int(start * SR)
    m = min(len(x), len(out) - s)
    if m > 0:
        out[s:s + m] += x[:m]
    return out


def reverb(x, amount=0.25, length=0.6):
    """Cheap reverb: a few decaying echoes plus a diffuse noise tail."""
    out = x.copy()
    for d, g in ((0.031, 0.5), (0.047, 0.4), (0.071, 0.33), (0.113, 0.25), (0.167, 0.18)):
        s = int(d * SR)
        out[s:] += x[:-s] * g * amount * 2
    ir = noise(length) * np.exp(-t_(length) / (length / 5))
    tail = np.convolve(x, ir[::8], mode="full")[: len(x)] * amount * 0.02
    return out + tail


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1
    return x / m * peak


def drive(x, k=2.0):
    return np.tanh(x * k) / np.tanh(k)


NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name):
    n, o = name[:-1], int(name[-1])
    return 440 * 2 ** ((NOTE[n] + 12 * (o - 4) - 9) / 12)


def pluck(f, dur, bright=0.6):
    """Karplus-Strong plucked string."""
    n = int(dur * SR)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    out = np.empty(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = bright * buf[i % p] + (1 - bright) * buf[(i + 1) % p]
        buf[i % p] *= 0.996
    return out


def bell(f, dur):
    t = t_(dur)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2.2 * np.exp(-t / 0.4)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 0.7)


def marimba(f, dur):
    t = t_(dur)
    return (np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t / 0.05)) * np.exp(-t / 0.25)


def brass(f, dur, bright=2500):
    t = t_(dur)
    x = saw(f, dur) + 0.6 * saw(f * 1.003, dur)
    cut = 300 + bright * np.clip(t / 0.06, 0, 1) * np.exp(-t / 0.6)
    e = np.clip(t / 0.02, 0, 1) * np.exp(-t / max(dur, 0.1) * 0.6)
    return lowpass(x, cut) * e


def chord(fn, notes, dur, **kw):
    return mix(*[fn(hz(n), dur, **kw) for n in notes])


def kick(dur=0.35):
    return np.sin(sweep(150, 45, dur)) * env_exp(dur, 0.12)


def snare(dur=0.2):
    return highpass(noise(dur), 800) * env_exp(dur, 0.05) + 0.3 * sine(190, dur) * env_exp(dur, 0.04)


def hat(dur=0.05):
    return highpass(noise(dur), 6000) * env_exp(dur, 0.015)


SOUNDS = {}


def sound(fn):
    SOUNDS[fn.__name__] = fn
    return fn


@sound
def bonk():
    d = 0.22
    return np.sin(sweep(560, 170, d)) * env_exp(d, 0.06) + 0.3 * highpass(noise(d), 3000) * env_exp(d, 0.004)


@sound
def slap():
    d = 0.14
    return highpass(noise(d), 1500) * env_exp(d, 0.018) + 0.35 * sine(900, d) * env_exp(d, 0.01)


@sound
def thud():
    d = 0.35
    return drive(np.sin(sweep(130, 50, d)) * env_exp(d, 0.09) + 0.5 * lowpass(noise(d), 600) * env_exp(d, 0.04), 1.5)


@sound
def heavy():
    d = 0.6
    body = np.sin(sweep(160, 38, d)) * env_exp(d, 0.16)
    crack = highpass(noise(d), 2000) * env_exp(d, 0.02)
    return reverb(drive(body * 1.2 + 0.7 * crack + 0.4 * lowpass(noise(d), 900) * env_exp(d, 0.08), 2.5), 0.25)


@sound
def land():
    d = 0.4
    return mix(np.sin(sweep(110, 45, d)) * env_exp(d, 0.1), 0.6 * lowpass(noise(d), 1200) * env_exp(d, 0.12))


@sound
def pop():
    d = 0.2
    return np.sin(sweep(300, 1300, d)) * env_exp(d, 0.03) + 0.4 * highpass(noise(d), 2500) * env_exp(d, 0.006)


@sound
def rip():
    d = 0.5
    t = t_(d)
    crackle = (rng.uniform(0, 1, len(t)) > 0.93).astype(float) * rng.uniform(0.3, 1, len(t))
    tear = highpass(noise(d), 1200) * (0.4 + 0.6 * crackle)
    return tear * np.clip(t / 0.02, 0, 1) * np.clip((d - t) / 0.12, 0, 1)


@sound
def burrow():
    d = 0.8
    t = t_(d)
    rumble = lowpass(noise(d), 120 + 500 * t / d) * np.clip(t / 0.3, 0, 1) * 3
    crack = at(highpass(noise(0.3), 1500) * env_exp(0.3, 0.03), 0.3, d)
    return drive(rumble + crack + at(np.sin(sweep(120, 40, 0.4)) * env_exp(0.4, 0.1), 0.3, d), 1.5)


@sound
def twang():
    d = 0.9
    s = pluck(98, d, 0.55) + 0.5 * pluck(147, d, 0.55)
    return s * np.clip(t_(d) / 0.003, 0, 1)


@sound
def whoosh():
    d = 0.45
    t = t_(d)
    shape = np.sin(np.pi * t / d) ** 2
    return lowpass(noise(d), 400 + 3500 * shape) * shape * 2


@sound
def whistle():
    d = 0.7
    t = t_(d)
    f = 2200 * (600 / 2200) ** (t / d) * (1 + 0.01 * np.sin(2 * np.pi * 7 * t))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.clip(t / 0.05, 0, 1) * 0.7


@sound
def crater():
    d = 1.6
    body = np.sin(sweep(90, 28, d)) * env_exp(d, 0.4)
    debris = lowpass(noise(d), 1500) * env_exp(d, 0.35)
    crack = highpass(noise(d), 2500) * env_exp(d, 0.03)
    return reverb(drive(body * 1.5 + debris + crack * 0.8, 3), 0.3)


@sound
def beam():
    d = 2.6
    t = t_(d)
    tone = saw(110, d) + saw(110.7, d) + 0.6 * saw(220.4, d)
    trem = 0.7 + 0.3 * np.sin(2 * np.pi * 13 * t)
    crackle = highpass(noise(d), 4000) * (rng.uniform(0, 1, len(t)) > 0.97)
    e = np.clip(t / 0.15, 0, 1) * np.clip((d - t) / 0.2, 0, 1)
    return lowpass(tone, 1800) * trem * e + crackle * 0.5 * e


@sound
def tick():
    d = 0.6
    click = highpass(noise(0.02), 3000) * env_exp(0.02, 0.003) + sine(3200, 0.02) * env_exp(0.02, 0.004)
    return reverb(pad(click, d), 0.6, 0.6)


@sound
def boom():
    d = 1.8
    return reverb(drive(np.sin(sweep(70, 25, d)) * env_exp(d, 0.5) * 1.4 + lowpass(noise(d), 1100) * env_exp(d, 0.45), 2.5), 0.35)


@sound
def wind():
    d = 1.6
    t = t_(d)
    gust = 0.5 + 0.5 * np.sin(2 * np.pi * 1.3 * t) ** 2
    return lowpass(noise(d), 300 + 900 * gust) * gust * np.clip(t / 0.2, 0, 1) * np.clip((d - t) / 0.3, 0, 1) * 3


def ah(f, dur):
    t = t_(dur)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    x = sum((1 / k) * np.sin(k * ph) * (1.6 if k in (2, 3) else 1) for k in range(1, 12))
    return lowpass(x, 1400)


@sound
def choir():
    d = 1.8
    t = t_(d)
    x = mix(*[ah(hz(n), d) for n in ("A3", "C#4", "E4", "A4")])
    return reverb(x * np.clip(t / 0.35, 0, 1) * np.clip((d - t) / 0.4, 0, 1), 0.4)


@sound
def charge():
    d = 1.4
    t = t_(d)
    ph = sweep(180, 1700, d)
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * (6 + 30 * t / d) * t)
    return (0.6 * np.sin(ph) + 0.4 * lowpass(np.sign(np.sin(ph)), 3000)) * trem * np.clip(t / 0.05, 0, 1)


@sound
def glass():
    d = 1.0
    t = t_(d)
    burst = highpass(noise(d), 3500) * env_exp(d, 0.05)
    shards = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-t / rng.uniform(0.1, 0.35)) * (t > s) for f, s in zip(rng.uniform(2500, 7500, 14), rng.uniform(0, 0.25, 14)))
    return reverb(burst + 0.25 * shards, 0.3)


@sound
def heartbeat():
    d = 0.7
    lub = np.sin(sweep(70, 40, 0.15)) * env_exp(0.15, 0.05)
    dub = np.sin(sweep(60, 35, 0.15)) * env_exp(0.15, 0.04)
    return drive(at(lub, 0, d) + 0.8 * at(dub, 0.22, d), 2)


@sound
def fakesting():
    d = 0.8
    a = square(hz("C5"), 0.15) * env_exp(0.15, 0.08)
    b = square(hz("G5"), 0.5) * env_exp(0.5, 0.25)
    return lowpass(at(a, 0, d) + at(b, 0.16, d), 3000) * 0.6


# ---- tier stings (play at the victory pose) ----
@sound
def sting_Common():
    d = 1.2
    notes = ["C5", "E5", "G5"]
    return reverb(mix(*[at(marimba(hz(n), 0.6), k * 0.12, d) for k, n in enumerate(notes)]), 0.25)


@sound
def sting_Rare():
    d = 1.8
    notes = ["E5", "G#5", "B5", "E6"]
    return reverb(mix(*[at(bell(hz(n), 1.2), k * 0.1, d) for k, n in enumerate(notes)]), 0.35)


@sound
def sting_Epic():
    d = 2.0
    stab = chord(brass, ["D4", "F#4", "A4", "D5"], 1.2)
    cym = highpass(noise(d), 5000) * env_exp(d, 0.5) * 0.4
    return reverb(drive(at(stab, 0, d), 1.3) + cym, 0.35)


@sound
def sting_Mythic():
    d = 2.6
    big = chord(brass, ["C3", "G3", "C4", "D#4", "G4"], 2.0)
    voices = mix(*[ah(hz(n), 2.0) for n in ("C4", "D#4", "G4")]) * np.clip(t_(2.0) / 0.2, 0, 1)
    hit = np.sin(sweep(80, 30, 1.0)) * env_exp(1.0, 0.3)
    return reverb(drive(at(big, 0, d) + 0.6 * at(voices, 0.05, d) + at(hit, 0, d), 1.4), 0.4)


@sound
def sting_Legendary():
    d = 3.0
    line = [("G4", 0.0, 0.12), ("C5", 0.13, 0.12), ("E5", 0.26, 0.12), ("G5", 0.39, 1.4)]
    fan = mix(*[at(brass(hz(n), l, 3500), s, d) for n, s, l in line])
    held = at(chord(brass, ["C4", "E4", "G4", "C5"], 1.6), 0.39, d)
    roll_t = t_(1.0)
    roll = (lowpass(noise(1.0), 300) * 2 + np.sin(2 * np.pi * 70 * roll_t)) * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * roll_t)) * (roll_t / 1.0)
    timp = at(roll * 0.6, 0, d) + at(np.sin(sweep(100, 60, 0.8)) * env_exp(0.8, 0.3), 0.39, d)
    return reverb(drive(fan + 0.7 * held + timp, 1.3), 0.4)


@sound
def sting_Secret():
    d = 3.2
    t = t_(d)
    riser = at(lowpass(noise(0.6), np.linspace(300, 8000, int(0.6 * SR))) * np.linspace(0, 1, int(0.6 * SR)) ** 2, 0, d)
    drop = at(np.sin(sweep(120, 32, 1.6)) * env_exp(1.6, 0.7) * 1.4, 0.6, d)
    stab = at(mix(*[lowpass(saw(hz(n) * dt, 1.5), 2400) * env_exp(1.5, 0.5) for n in ("A3", "C4", "E4", "A4") for dt in (0.995, 1.0, 1.005)]), 0.6, d)
    sparkle = at(mix(*[at(bell(hz(n), 0.8), k * 0.07, 1.5) for k, n in enumerate(["A5", "C6", "E6", "A6"])]), 0.7, d)
    return reverb(drive(riser + drop + 0.5 * stab + 0.5 * sparkle, 1.6), 0.45)


# ---- music ----
@sound
def brawl():
    """Bouncy 2-bar loop, 128 bpm (3.75 s), loops cleanly."""
    bpm = 128
    beat = 60 / bpm
    d = beat * 8
    out = np.zeros(int(d * SR))
    for b in range(8):
        out += at(kick(), b * beat, d) * (1 if b % 2 == 0 else 0.7)
        if b % 2 == 1:
            out += at(snare(), b * beat, d) * 0.8
        for h in range(2):
            out += at(hat(), b * beat + h * beat / 2, d) * 0.4
    bass = ["C2", "C2", "D#2", "C2", "F2", "F2", "G2", "A#1"]
    for b, n in enumerate(bass):
        out += at(lowpass(saw(hz(n), beat * 0.9), 700) * env_exp(beat * 0.9, 0.15), b * beat, d) * 0.6
    melody = [("G4", 0), ("A#4", 1.5), ("C5", 2), ("G4", 3.5), ("F4", 4), ("G4", 5.5), ("D#4", 6), ("C4", 7)]
    for n, b in melody:
        out += at(lowpass(square(hz(n), beat * 0.4), 2500) * env_exp(beat * 0.4, 0.12), b * beat, d) * 0.25
    return out


@sound
def theme():
    """Secret hype theme: riser, bass drop at 0.3 s, 4 bars at 140 bpm."""
    bpm = 140
    beat = 60 / bpm
    d = 0.3 + beat * 16
    out = np.zeros(int(d * SR))
    out += at(lowpass(noise(0.3), np.linspace(500, 9000, int(0.3 * SR))) * np.linspace(0, 1, int(0.3 * SR)), 0, d) * 0.8
    start = 0.3
    out += at(np.sin(sweep(110, 30, 1.8)) * env_exp(1.8, 0.8) * 1.5, start, d)
    chords = [["A3", "C4", "E4"], ["F3", "A3", "C4"], ["C4", "E4", "G4"], ["G3", "B3", "D4"]]
    roots = ["A1", "F1", "C2", "G1"]
    for bar in range(4):
        t0 = start + bar * 4 * beat
        sup = mix(*[lowpass(saw(hz(n) * dt, 4 * beat), 3000) for n in chords[bar] for dt in (0.993, 1.0, 1.007)])
        pump = np.clip(((t_(4 * beat) % beat) / beat) * 1.6, 0.25, 1)
        out += at(sup * pump * 0.25, t0, d)
        for b in range(4):
            out += at(kick(0.3), t0 + b * beat, d) * 1.1
            out += at(drive(np.sin(2 * np.pi * hz(roots[bar]) * t_(beat * 0.95)) * env_exp(beat * 0.95, 0.4), 2), t0 + b * beat, d) * 0.6
            if b % 2 == 1:
                out += at(snare(0.25), t0 + b * beat, d) * 0.9
            for h in range(2):
                out += at(hat(), t0 + b * beat + (h + 0.5) * beat / 2, d) * 0.35
    lead = ["E5", "E5", "D5", "C5", "A4", "C5", "D5", "E5", "G5", "E5", "D5", "C5", "B4", "D5", "B4", "G4"]
    for k, n in enumerate(lead):
        out += at(lowpass(saw(hz(n), beat * 0.9), 4000) * env_exp(beat * 0.9, 0.3), start + k * beat, d) * 0.2
    return reverb(drive(out, 1.2), 0.2)


def write_wav(path, x):
    x = norm(x)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    keep_wav = "--wav" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    for name, fn in SOUNDS.items():
        if only and name not in only:
            continue
        x = fn()
        wav = os.path.join(OUT, name + ".wav")
        write_wav(wav, x)
        ogg = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
        if not keep_wav:
            os.remove(wav)
        print(f"{name:16s} {len(x) / SR:5.2f} s")
