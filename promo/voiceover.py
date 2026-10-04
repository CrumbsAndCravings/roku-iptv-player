"""Voices the promo with Kokoro, an open (Apache 2.0) text-to-speech model, run locally.

A narrator carries the promo and a second voice, the viewer, answers twice. Each line
starts at a time picked to sit inside its scene in index.html; the script prints how
long every line runs and warns when one would run into the next.

    pip install kokoro-onnx soundfile huggingface_hub
    python3 promo/voiceover.py          # downloads the model on first run (about 330 MB)

Writes promo/voiceover.flac: the whole 38 second track, 48 kHz mono, which
render.cjs mixes over the music, lowering the music while someone speaks.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from huggingface_hub import hf_hub_download
from kokoro_onnx import Kokoro

HERE = Path(__file__).resolve().parent
DURATION = 38.0
REPO = "onnx-community/Kokoro-82M-v1.0-ONNX"
NARRATOR, VIEWER = "af_heart", "am_puck"

# (start seconds, voice, speed, text, latest end). The end is where the scene moves on.
LINES = [
    (0.05, NARRATOR, 1.15, "Bored from the UI of your IPTV player?", 2.62),
    (2.62, VIEWER, 1.0, "Yeah.", 3.25),
    (3.4, NARRATOR, 1.05, "Meet Aran Plus. A cinematic player for your Roku.", 6.5),
    (6.6, NARRATOR, 1.05, "Posters, not lists. With a big backdrop for whatever you land on.", 10.7),
    (10.9, NARRATOR, 1.05, "Continue Watching takes you right back where you left off.", 14.7),
    (14.9, NARRATOR, 1.05, "Every category, tidied. New releases first, then your languages.", 19.1),
    (19.3, NARRATOR, 1.05, "Search finds movies, series and categories as you type.", 23.6),
    (23.75, NARRATOR, 1.05, "And when an episode ends, the next one counts down on its own.", 27.0),
    (27.05, VIEWER, 1.0, "Okay. One more episode.", 28.4),
    (28.45, NARRATOR, 1.05, "Plus subtitles, seasons, and all the little things.", 31.7),
    (31.9, NARRATOR, 1.0, "Aran Plus. Made for Roku.", 33.8),
    (33.85, NARRATOR, 1.0, "Just a player. It doesn't sell IPTV or playlists.", 37.4),
]


def model_files():
    model = hf_hub_download(REPO, "onnx/model.onnx")
    voices = {}
    for name in sorted({line[1] for line in LINES}):
        raw = np.fromfile(hf_hub_download(REPO, f"voices/{name}.bin"), dtype=np.float32)
        voices[name] = raw.reshape(-1, 1, 256)
    pack = Path(tempfile.gettempdir()) / "aranplus-voices.npz"
    np.savez(pack, **voices)
    return model, str(pack)


def trim(audio, sr, floor=0.01):
    loud = np.flatnonzero(np.abs(audio) > floor)
    if not len(loud):
        return audio
    pad = int(0.03 * sr)
    return audio[max(0, loud[0] - pad): loud[-1] + pad]


def main():
    kokoro = Kokoro(*model_files())
    sr = 24000
    track = np.zeros(int(DURATION * sr), dtype=np.float32)
    ok = True
    print(f"{'start':>6} {'end':>6} {'limit':>6}  line")
    for start, voice, speed, text, limit in LINES:
        audio, sr = kokoro.create(text, voice=voice, speed=speed, lang="en-us")
        audio = trim(audio.astype(np.float32), sr)
        end = start + len(audio) / sr
        flag = "" if end <= limit else "  <-- too long"
        ok = ok and not flag
        print(f"{start:6.2f} {end:6.2f} {limit:6.2f}  [{voice}] {text}{flag}")
        i = int(start * sr)
        track[i: i + len(audio)] += audio[: len(track) - i]
    peak = float(np.max(np.abs(track))) or 1.0
    track *= 0.89 / peak
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "vo.wav"
        sf.write(wav, track, sr)
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav),
                        "-af", "highpass=f=80,aresample=48000", "-ac", "1", str(HERE / "voiceover.flac")], check=True)
    print("wrote", HERE / "voiceover.flac")
    if not ok:
        sys.exit("some lines run past their scene; shorten them or speed them up")


if __name__ == "__main__":
    main()
