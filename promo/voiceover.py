"""Voices the promo with Kokoro, an open (Apache 2.0) text-to-speech model, run locally.

A narrator carries the story and a second voice, the viewer, answers twice. Each line is
saved as its own clip in promo/voice/, and promo/voice/lines.json records how long each
one runs. index.html decides when each line plays (its "vo" cues), and render.cjs places
the clips there when it builds the soundtrack, warning if one would run into the next.

    pip install kokoro-onnx soundfile huggingface_hub
    python3 promo/voiceover.py          # downloads the model on first run (about 330 MB)
"""

import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from huggingface_hub import hf_hub_download
from kokoro_onnx import Kokoro

HERE = Path(__file__).resolve().parent
OUT = HERE / "voice"
REPO = "onnx-community/Kokoro-82M-v1.0-ONNX"
NARRATOR, VIEWER = "af_heart", "am_puck"

# (id, voice, speed, text). "Aran Plus" is how the voice is asked to say ARAN+.
LINES = [
    ("bored", NARRATOR, 1.1, "Bored from the UI of your IPTV player?"),
    ("tired", VIEWER, 0.95, "Honestly? I just want to watch something."),
    ("hear", NARRATOR, 0.92, "We hear you."),
    ("meet", NARRATOR, 1.0, "Meet Aran Plus. A cinematic player for your Roku."),
    ("posters", NARRATOR, 1.0, "Your library becomes posters, not lists, with a big backdrop for whatever you land on."),
    ("names", NARRATOR, 1.0, "Messy provider names are tidied into ones you can read, and sorted by your languages."),
    ("asleep", NARRATOR, 0.97, "Fell asleep halfway through? Continue Watching keeps your place."),
    ("follows", NARRATOR, 1.0, "And with sync set up, it follows you to another TV."),
    ("helper", NARRATOR, 1.0, "Some files won't play on a Roku in any app. The helper on your computer at home converts them while you watch."),
    ("subs", NARRATOR, 1.0, "And subtitles, so everyone can follow along. Found online once, and with sync, saved for every screen."),
    ("upnext", NARRATOR, 1.02, "When an episode ends, the next one counts down on its own."),
    ("onemore", VIEWER, 1.0, "Okay. One more episode."),
    ("care", NARRATOR, 0.95, "Aran Plus. Made with care, for Roku."),
    ("player", NARRATOR, 1.0, "Just a player. It doesn't sell IPTV or playlists."),
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
    OUT.mkdir(exist_ok=True)
    for old in OUT.glob("*.flac"):
        old.unlink()
    lines = {}
    with tempfile.TemporaryDirectory() as tmp:
        for key, voice, speed, text in LINES:
            audio, sr = kokoro.create(text, voice=voice, speed=speed, lang="en-us")
            audio = trim(audio.astype(np.float32), sr)
            audio *= 0.89 / (float(np.max(np.abs(audio))) or 1.0)
            wav = Path(tmp) / f"{key}.wav"
            sf.write(wav, audio, sr)
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav),
                            "-af", "highpass=f=80,aresample=48000", "-ac", "1", str(OUT / f"{key}.flac")], check=True)
            lines[key] = {"voice": voice, "text": text, "seconds": round(len(audio) / sr, 3)}
            print(f"{lines[key]['seconds']:5.2f}s  {key:8} [{voice}] {text}")
    (OUT / "lines.json").write_text(json.dumps(lines, indent=2) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
