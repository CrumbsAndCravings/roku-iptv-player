"""Generates the channel's sounds (src/sounds/*.wav).

  move.wav     a soft glassy tick for moving around
  select.wav   a little rising pop with a ping, for choosing something
  back.wav     the pop falling, for going back
  intro.wav    the ARAN+ sting, played with the intro (components/Intro.brs): the web
               app's src/ui/sting.ts, rendered to a file here, since a Roku plays
               recorded sounds. A soft low knock; a big boom with a dreamy chord
               (D major 9) blooming out of it through an opening filter; two bell-like
               pings for the plus; and a rising whoosh as the intro flies into the app.

Run from the repo root:  python3 tools/make_sounds.py
Needs numpy (pip install numpy). The noise is seeded, so the files only change when
this script does.
"""

import math
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "sounds"
RATE = 44100
rng = np.random.default_rng(7)

# When each part of the sting happens, in seconds from the start of intro.wav. The
# intro's animation keeps time with these (INTRO_BEAT in components/Intro.brs).
BEAT = {"knock": 0.1, "boom": 0.5, "pings": (0.68, 0.82), "whoosh": 1.55}
STING_FILE_SECONDS = 3.2
REVERB_SECONDS = 2.4

# D3, A3, E4, F#4, C#5: open, warm and a little wistful.
CHORD = [146.83, 220.0, 329.63, 369.99, 554.37]
PINGS = [1760.0, 2637.02]  # A6, E7


# --- Building blocks ---------------------------------------------------------------------


def samples(seconds):
    return int(round(seconds * RATE))


def clock(seconds):
    return np.arange(samples(seconds)) / RATE


def envelope(t, peak, attack, decay):
    """Up to `peak` in `attack` seconds, then dying away over `decay` seconds (Web
    Audio's linear then exponential ramp to 0.0001)."""
    rise = peak * t / attack
    fall = peak * (0.0001 / peak) ** ((t - attack) / decay)
    env = np.where(t < attack, rise, fall)
    env[t > attack + decay] = 0.0
    return env


def glide(t, start, end, seconds):
    """A frequency ramping exponentially from `start` to `end` over `seconds`, then held."""
    k = np.clip(t / seconds, 0, 1)
    return start * (end / start) ** k


def sine(t, freq):
    """A sine; `freq` may change over time (one value per sample)."""
    if np.isscalar(freq):
        return np.sin(2 * math.pi * freq * t)
    return np.sin(2 * math.pi * np.cumsum(freq) / RATE)


def saw(t, freq):
    """A band-limited sawtooth (PolyBLEP), as Web Audio's is."""
    dt = freq / RATE
    p = (freq * t) % 1.0
    out = 2 * p - 1
    near_start = p < dt
    x = p[near_start] / dt
    out[near_start] -= x + x - x * x - 1
    near_end = p > 1 - dt
    x = (p[near_end] - 1) / dt
    out[near_end] -= x * x + x + x + 1
    return out


def noise(seconds):
    return rng.uniform(-1, 1, samples(seconds))


def biquad(signal, kind, freq, q):
    """Web Audio's BiquadFilterNode (lowpass Q in dB, bandpass Q linear). `freq` may
    change over time (one value per sample); coefficients follow every 16 samples."""
    x = np.asarray(signal, dtype=float)
    n = len(x)
    freqs = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq, dtype=float)
    y = np.zeros(n)
    x1 = x2 = y1 = y2 = 0.0
    b0 = b1 = b2 = a1 = a2 = 0.0
    for i in range(n):
        if i % 16 == 0:
            w0 = 2 * math.pi * min(freqs[i], RATE * 0.49) / RATE
            cos = math.cos(w0)
            if kind == "lowpass":
                alpha = math.sin(w0) / (2 * 10 ** (q / 20))
                a0 = 1 + alpha
                b0 = (1 - cos) / 2 / a0
                b1 = (1 - cos) / a0
                b2 = b0
            else:
                alpha = math.sin(w0) / (2 * q)
                a0 = 1 + alpha
                b0 = alpha / a0
                b1 = 0.0
                b2 = -alpha / a0
            a1 = -2 * cos / a0
            a2 = (1 - alpha) / a0
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, xi
        y2, y1 = y1, yi
        y[i] = yi
    return y


def pan(mono, position):
    """Web Audio's StereoPanner for a one-channel sound: equal power."""
    x = (position + 1) / 2
    return np.stack([mono * math.cos(x * math.pi / 2), mono * math.sin(x * math.pi / 2)])


class Mix:
    """A stereo mix with a send to the reverb, like sting.ts's bus()."""

    def __init__(self, seconds):
        self.dry = np.zeros((2, samples(seconds)))
        self.send = np.zeros((2, samples(seconds)))

    def add(self, stereo, at, send=0.0):
        start = samples(at)
        end = min(start + stereo.shape[1], self.dry.shape[1])
        part = stereo[:, : end - start]
        self.dry[:, start:end] += part
        self.send[:, start:end] += part * send


def impulse(seconds):
    """A room's echo: two channels of noise fading away, a little differently on each
    side, scaled as Web Audio's ConvolverNode scales it (normalize)."""
    n = samples(seconds)
    fade = (1 - np.arange(n) / n) ** 2.8
    ir = rng.uniform(-1, 1, (2, n)) * fade
    power = max(math.sqrt(np.sum(ir * ir) / ir.size), 0.000125)
    return ir * (0.00125 / power)


def convolve(stereo, ir):
    n = stereo.shape[1] + ir.shape[1] - 1
    size = 1 << (n - 1).bit_length()
    out = np.fft.irfft(np.fft.rfft(stereo, size) * np.fft.rfft(ir, size), size)
    return out[:, : stereo.shape[1]]


def limit(stereo, threshold=-10.0, knee=8.0, ratio=8.0, attack=0.003, release=0.25):
    """A gentle limiter (sting.ts's DynamicsCompressor), so the boom never clips."""
    level = 20 * np.log10(np.maximum(np.max(np.abs(stereo), axis=0), 1e-9))
    over = level - threshold
    target = np.where(
        2 * over < -knee,
        0.0,
        np.where(2 * np.abs(over) <= knee, (1 / ratio - 1) * (over + knee / 2) ** 2 / (2 * knee), (1 / ratio - 1) * over),
    )
    gain = np.zeros_like(target)
    up = math.exp(-1 / (attack * RATE))
    down = math.exp(-1 / (release * RATE))
    g = 0.0
    for i, want in enumerate(target):
        k = up if want < g else down
        g = want + (g - want) * k
        gain[i] = g
    return stereo * 10 ** (gain / 20)


def peak_to(stereo, dbfs):
    return stereo * (10 ** (dbfs / 20) / np.max(np.abs(stereo)))


def save(name, sound):
    sound = np.atleast_2d(sound)
    pcm = np.clip(np.round(sound * 32767), -32768, 32767).astype("<i2")
    with wave.open(str(OUT / name), "wb") as f:
        f.setnchannels(sound.shape[0])
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm.T.tobytes())


# --- The sting ---------------------------------------------------------------------------


def sting():
    mix = Mix(STING_FILE_SECONDS)

    # The knock: a soft, low thump with a little click on top.
    t = clock(0.45)
    mix.add(pan(sine(t, glide(t, 150, 55, 0.14)) * envelope(t, 0.55, 0.004, 0.35), 0), BEAT["knock"], 0.15)
    t = clock(0.06)
    mix.add(pan(biquad(noise(0.06), "bandpass", 1800, 1) * envelope(t, 0.12, 0.002, 0.05), 0), BEAT["knock"], 0.1)

    # The boom: a falling sub, a punch of noise, and the chord opening up.
    boom = BEAT["boom"]
    t = clock(2.35)
    mix.add(pan(sine(t, glide(t, 120, 38, 0.9)) * envelope(t, 0.95, 0.006, 2.2), 0), boom, 0.2)
    t = clock(0.3)
    mix.add(pan(biquad(noise(0.3), "lowpass", 900, 1) * envelope(t, 0.35, 0.003, 0.25), 0), boom, 0.2)

    t = clock(2.95)
    voices = np.zeros((2, len(t)))
    for i, freq in enumerate(CHORD):
        position = (-1 if i % 2 == 0 else 1) * 0.12 * i
        # Two saws a hair apart in pitch: one warm, wide voice.
        voice = sum(saw(t, freq * 2 ** (cents / 1200)) for cents in (-8, 8)) * envelope(t, 0.07, 0.06, 2.8)
        voices += pan(voice, position)
    cutoff = np.where(t < 0.45, 350 * (3200 / 350) ** (t / 0.45), 3200 * (900 / 3200) ** (np.clip(t - 0.45, 0, 1.95) / 1.95))
    filtered = np.stack([biquad(voices[c], "lowpass", cutoff, 2) for c in range(2)])
    mix.add(filtered, boom, 0.45)
    # High air over the chord, mostly reverb.
    t = clock(2.7)
    mix.add(pan(sine(t, 1174.66) * envelope(t, 0.03, 0.3, 2.4), 0), boom + 0.05, 0.8)

    # The plus: two bell-like pings, left then right.
    for i, at in enumerate(BEAT["pings"]):
        t = clock(1.05)
        bell = sine(t, PINGS[i]) * envelope(t, 0.16, 0.002, 0.9)
        # A quieter, inharmonic partial makes it ring like metal.
        bell += sine(t, PINGS[i] * 2.76) * envelope(t, 0.04, 0.002, 0.5)
        mix.add(pan(bell, -0.35 if i == 0 else 0.35), at, 0.6)

    wet = convolve(mix.send, impulse(REVERB_SECONDS)) * 0.38
    out = limit((mix.dry + wet) * 0.85)

    # The whoosh: noise swept up as the intro flies into the app (straight out, as in
    # sting.ts).
    t = clock(0.8)
    gain = np.interp(t, [0, 0.5, 0.78, 0.8], [0, 0.2, 0, 0])
    whoosh = biquad(noise(0.8) * gain, "bandpass", glide(t, 300, 5000, 0.7), 0.8) * 0.85
    start = samples(BEAT["whoosh"])
    out[:, start : start + len(t)] += pan(whoosh, 0) * math.sqrt(2)

    # The reverb rings on; fade its last half second.
    tail = samples(0.5)
    out[:, -tail:] *= np.linspace(1, 0, tail) ** 2
    return peak_to(out, -3.0)


# --- Click sounds ------------------------------------------------------------------------


def small_room(sound, wet):
    """A touch of a small, bright room, so the clicks sound like glass rather than a beep."""
    stereo = pan(sound, 0) * math.sqrt(2)
    return (stereo + convolve(stereo, impulse(0.3)) * wet)[0]


def move():
    t = clock(0.09)
    tick = biquad(noise(0.09), "bandpass", 3200, 1.2) * envelope(t, 0.5, 0.0008, 0.012)
    tick += sine(t, 1760) * envelope(t, 0.35, 0.0015, 0.045)
    tick += sine(t, 1760 * 2.76) * envelope(t, 0.06, 0.001, 0.02)
    return peak_to(small_room(tick, 0.25), -20.0)


def select():
    t = clock(0.42)
    # A bubble rising from D5 to A5, and a ping (A6) as it pops.
    pop = sine(t, glide(t, 587.33, 880.0, 0.04)) * envelope(t, 1.0, 0.002, 0.12)
    pop += sine(t, 1760) * envelope(t, 0.3, 0.003, 0.28)
    pop += sine(t, 1760 * 2.76) * envelope(t, 0.06, 0.002, 0.12)
    return peak_to(small_room(pop, 0.35), -14.0)


def back():
    t = clock(0.34)
    # The same bubble falling, A5 to D5, with a softer ping (D6).
    pop = sine(t, glide(t, 880.0, 587.33, 0.05)) * envelope(t, 1.0, 0.002, 0.1)
    pop += sine(t, 1174.66) * envelope(t, 0.18, 0.003, 0.16)
    return peak_to(small_room(pop, 0.3), -16.0)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    save("move.wav", move())
    save("select.wav", select())
    save("back.wav", back())
    save("intro.wav", sting())
    for p in sorted(OUT.iterdir()):
        with wave.open(str(p)) as f:
            print(p.name, f.getnchannels(), "channel(s)", round(f.getnframes() / f.getframerate(), 2), "s", p.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
