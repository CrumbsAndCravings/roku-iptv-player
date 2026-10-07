# ARAN+ promo

A 56 second vertical (1080x1920) promo for ARAN+, with a voiceover and its own music. It
tells a small, warm story (a tired evening, falling asleep halfway, watching with family)
and compares a plain IPTV player with ARAN+ along the way: grey lists against posters,
messy provider names against tidy ones, a file that won't play against the helper, and it
ends on the point that ARAN+ is only a player and doesn't sell IPTV or playlists.

Everything on screen comes from the app's own look: the Fredoka and Nunito fonts in
`src/fonts`, the glow, sparkle, fade and icon images in `src/images`, and the colours,
layouts and wording of the real screens (Home, Continue Watching, Details, the player's
Audio & subtitles panel and Up next). The grey "Before" screens stand for a plain player
and are drawn for the promo; posters, backdrops and their titles are too, since real ones
come from each person's provider. The video says both on screen.

- `index.html` plays the promo in a browser, with a Sound button. Serve the repo root over HTTP (for example `python3 -m http.server` there, then open `/promo/`), since browsers drop the glow and sparkle masks on `file://` pages. It owns all the timing: scenes, sound cues and when each voice line plays (`window.__sound`).
- `aranplus-promo.mp4` is the rendered video: 56.5 seconds, 30 fps, with sound.
- `voiceover.py` voices the script with [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), an open (Apache 2.0) text-to-speech model run locally: a narrator (`af_heart`) and a viewer (`am_puck`) who answers twice. It writes one clip per line to `voice/` and their lengths to `voice/lines.json`. It needs `pip install kokoro-onnx soundfile huggingface_hub` and downloads the model (about 330 MB) on first run.
- `soundtrack.cjs` synthesizes the music and UI sounds in code (no third-party audio), places the voice clips on their cues, warns if one would run into the next, and ducks the music under the voices. `soundtrack.mp3` is the finished mix, used by the page.
- `render.cjs` renders the video again after a change:

```sh
NODE_PATH="$(npm root -g)" node promo/render.cjs promo/aranplus-promo.mp4 30
```

It needs Playwright with Chromium and ffmpeg. `STILLS=4.6,12,27.5` renders PNGs at those
times instead, which is quicker for checking a change. After changing only the voice or
the music, `REMUX=1` rebuilds the soundtrack and swaps it into the existing MP4 without
rendering the frames again.

To change a line: edit it in `voiceover.py`, run it, then check the printed lengths
against the line's start time in `index.html` (the `"vo"` cues) and the next line's.
