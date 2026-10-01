# ARAN+ promo

A 35 second vertical (1080x1920) promo for ARAN+, made from the app's own look: the
Fredoka and Nunito fonts in `src/fonts`, the glow, sparkle, fade and icon images in
`src/images`, and the colours, layouts and wording of the real screens (Home, Continue
Watching, Categories, Search and the player).

- `index.html` plays the promo in a browser. Open it from this folder so it can reach `../src`.
- `aranplus-promo.mp4` is the rendered video, silent, 30 fps.
- `render.cjs` renders the video again after a change:

```sh
NODE_PATH="$(npm root -g)" node promo/render.cjs promo/aranplus-promo.mp4 30
```

It needs Playwright with Chromium and ffmpeg. `STILLS=4.6,12,27.5` renders PNGs at those
times instead, which is quicker for checking a change.

Posters, backdrops and the titles on them are drawn for the promo, since real ones come
from each person's provider; the video says so on screen.
