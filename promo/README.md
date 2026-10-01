# ARAN+ promo

A 38 second vertical (1080x1920) promo for ARAN+, made from the app's own look: the
Fredoka and Nunito fonts in `src/fonts`, the glow, sparkle, fade and icon images in
`src/images`, and the colours, layouts and wording of the real screens (Home, Continue
Watching, Categories, Search and the player).

- `index.html` plays the promo in a browser, with a Sound button. Serve the repo root over HTTP (for example `python3 -m http.server` there, then open `/promo/`), since browsers drop the glow and sparkle masks on `file://` pages.
- `aranplus-promo.mp4` is the rendered video: 38 seconds, 30 fps, with sound.
- `soundtrack.cjs` synthesizes the music and UI sounds in code, timed to cues the page exposes (`window.__sound`), so there is no third-party audio. `soundtrack.mp3` is the finished mix, used by the page.
- `voiceover.py` voices the script with [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), an open (Apache 2.0) text-to-speech model run locally: a narrator (`af_heart`) and a viewer (`am_puck`) who answers twice. It writes `voiceover.flac`, which the soundtrack mixes in with the music ducking under it. The lines and their start times are at the top of the script; it warns when a line runs past its scene. It needs `pip install kokoro-onnx soundfile huggingface_hub` and downloads the model (about 330 MB) on first run.
- `render.cjs` renders the video again after a change:

```sh
NODE_PATH="$(npm root -g)" node promo/render.cjs promo/aranplus-promo.mp4 30
```

It needs Playwright with Chromium and ffmpeg. `STILLS=4.6,12,27.5` renders PNGs at those
times instead, which is quicker for checking a change. After changing only the voiceover
or the music, `REMUX=1` rebuilds the soundtrack and swaps it into the existing MP4
without rendering the frames again.

Posters, backdrops and the titles on them are drawn for the promo, since real ones come
from each person's provider; the video says so on screen.
