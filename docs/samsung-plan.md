# ARAN+ for Samsung TVs (Tizen): build plan

This is the handoff plan for building ARAN+ as a Samsung Tizen app in its own repo. The Roku app in this repo (v0.4.1) is the working reference for every feature: when this plan says "same as Roku", read the Roku file named next to it.

## 1. Why, and for whom

- **The viewer:** one household, one Samsung Q60 series 65" TV (4K QLED), watching movies and series from an Xtream Codes IPTV provider. Live TV is rare (big tournaments only).
- **Why Samsung:** the Roku TV (TCL 32S357) has no HEVC decoder and no Roku plays AVI, so titles like Supernatural and That '70s Show won't play there. Every 4K Samsung TV decodes HEVC in hardware, and Samsung's native player (AVPlay) opens MKV and most AVI files directly.
- **Goal for v1:** feature parity with ARAN+ for Roku v0.4.1, same look (lavender, rounded, joyful), laid out for 1920x1080.
- **Not in v1:** live TV and guide, profiles, sync between devices, My List, category hiding. (All on the Roku roadmap too.)

## 2. Facts to confirm first

Do these before writing features. Each one can change the plan.

1. **Exact model code.** On the sticker on the back, or Settings > Support > About This TV. In Canada it looks like `QN65Q60?AFXZC`; the letter after `Q60` is the year:

   | Letter | Year | Tizen | Web engine (about) |
   |---|---|---|---|
   | R | 2019 | 5.0 | Chromium 63 |
   | T | 2020 | 5.5 | Chromium 69 |
   | A | 2021 | 6.0 | Chromium 76 |
   | B | 2022 | 6.5 | Chromium 85 |
   | C | 2023 | 7.0 | Chromium 94 |
   | D | 2024 | 8.0 | Chromium 108 |

   The engine column is from Samsung's web engine spec page as remembered; confirm it with `navigator.userAgent` on the TV in M0. Until the model is known, build for Chromium 63 (the oldest likely case).
2. **A computer on the same Wi-Fi** (Windows, Mac or Linux) for Tizen Studio and the first install. Samsung requires a signed package tied to the TV's ID (DUID), so a phone alone can't install it.
3. **A Samsung account** for the free Samsung certificate.
4. **Cross-origin requests.** A packaged Tizen web app with `<access origin="*" subdomains="true"/>` should be able to call the Xtream server and OpenSubtitles without CORS headers. Prove it on the TV in M0.
5. **OpenSubtitles User-Agent.** OpenSubtitles wants `Api-Key` and a `User-Agent` naming the app. Browsers refuse to set `User-Agent` on XHR/fetch, and the Tizen engine probably does too. In M0, try the request from the TV and check what arrives; if the header can't be set, also send `X-User-Agent: ARANplus v1.0` and see which OpenSubtitles accepts.
6. **Playback reality check.** On the TV, play one HEVC MKV, one AVI (Xvid/DivX), one H.264 MP4 and one file with DTS audio from the provider through AVPlay. Samsung dropped DTS decoding on several model years, so audio is the most likely surprise.

## 3. Platform notes (Tizen TV web apps)

- **Package:** a `.wgt` (zip) with `config.xml`, `index.html`, JS, CSS, fonts, images and a signature. Icon is a PNG (Samsung asks for 512x423).
- **config.xml essentials:**

  ```xml
  <widget xmlns="http://www.w3.org/ns/widgets" xmlns:tizen="http://tizen.org/ns/widgets"
          id="https://github.com/CrumbsAndCravings/aranplus-samsung" version="0.1.0" viewmodes="maximized">
    <tizen:application id="ARANplus01.ARANplus" package="ARANplus01" required_version="5.0"/>
    <tizen:profile name="tv-samsung"/>
    <content src="index.html"/>
    <icon src="icon.png"/>
    <name>ARAN+</name>
    <feature name="http://tizen.org/feature/screen.size.normal.1080.1920"/>
    <tizen:privilege name="http://tizen.org/privilege/internet"/>
    <tizen:privilege name="http://tizen.org/privilege/tv.inputdevice"/>
    <access origin="*" subdomains="true"/>
    <tizen:setting screen-orientation="landscape" context-menu="disable" background-support="disable"
                   encryption="disable" install-location="auto" hwkey-event="enable"/>
  </widget>
  ```

  The package id is exactly 10 letters or digits. Keep it stable forever, or the TV treats a new build as a different app and Continue Watching (in localStorage) is lost.
- **Screen:** the UI plane is 1920x1080 even on a 4K panel; video plays on its own plane underneath at full resolution. Design at 1920x1080. Roku layout numbers are for 1280x720, so **multiply Roku coordinates and font sizes by 1.5**.
- **Player: AVPlay** (`webapis.avplay`), loaded with `<script src="$WEBAPIS/webapis/webapis.js"></script>` and drawn into `<object id="av-player" type="application/avplayer">`. Use it, not `<video>`: it handles MKV, AVI, HEVC, AC3/EAC3 and embedded subtitle tracks. The calls that matter:
  - `open(url)`, `setDisplayRect(0, 0, 1920, 1080)`, `setListener({...})`, `prepareAsync(ok, fail)`, `play()`, `pause()`, `stop()`, `close()`
  - `seekTo(ms, ok, fail)`, `getCurrentTime()` and `getDuration()` (both in ms), `getState()` (`NONE`, `IDLE`, `READY`, `PLAYING`, `PAUSED`)
  - `getTotalTrackInfo()` (array of `{index, type: "VIDEO" | "AUDIO" | "TEXT", extra_info}`; `extra_info` is a JSON string with the language), `setSelectTrack("AUDIO" | "TEXT", index)`
  - listener events: `onbufferingstart`, `onbufferingcomplete`, `oncurrentplaytime`, `onstreamcompleted`, `onerror`, `onsubtitlechange(duration, text, ...)`
  - `suspend()` and `restore()` when the app is hidden and shown (`visibilitychange`)
  - AVPlay does **not** draw subtitles. It hands text to `onsubtitlechange` and the app draws it. So ARAN+ needs its own subtitle layer anyway, which is good news for online subtitles (see section 6).
- **Keys:** arrows (37 to 40), Enter (13) and Back (10009) arrive without registration. Register the media keys with `tizen.tvinputdevice.registerKey(...)` for `MediaPlayPause`, `MediaPlay`, `MediaPause`, `MediaRewind`, `MediaFastForward`, `MediaStop`, and read their codes with `tizen.tvinputdevice.getKey(name).code` instead of hard-coding. The Samsung remote has no `*` key, so anything that was on `*` on Roku gets a visible button instead. Exit and Home can't be captured. When the system keyboard is up, its Done and Cancel arrive as key codes 65376 and 65385.
- **Leaving:** Back on the top level asks "Exit ARAN+?" and then calls `tizen.application.getCurrentApplication().exit()`.
- **Storage:** `localStorage` persists across launches and has no 16 KB limit like the Roku registry.
- **JS and CSS limits on old engines (Chromium 63):** no optional chaining or `??` (80), no BigInt (67), no `Array.prototype.flat` (69), no `AbortController` (66, use XHR and `abort()`), no flexbox `gap` (84, use margins), no `aspect-ratio` (88), no `inset` (87), no `backdrop-filter` (76). Let the bundler lower syntax to ES2017 (`target: chrome63`), and keep CSS to what 63 supports. Drop these limits if the TV turns out to be newer.
- **Performance:** TV CPUs are slow. Animate only `transform` and `opacity`, avoid `filter: blur` and large `box-shadow`s (use pre-rendered glow PNGs like Roku does), keep off-screen rows out of the DOM, and size images for the screen (TMDB `w342` posters, `w1280` backdrops).

## 4. Architecture

Plain TypeScript, no UI framework, bundled with esbuild into one JS file. A handful of screens doesn't need React, and fewer layers means fewer surprises on an old engine.

```
aranplus-samsung/
  config.xml  index.html  icon.png
  src/
    main.ts                 boot, screen stack, key dispatch
    core/                   pure logic, no DOM, unit tested (ports of the Roku files)
      utils.ts              Utils.brs: text/number helpers, SizedImage, MetaLine, NormalizeSearch,
                            NormalizeServer, ParseProviderLink, ApiUrl, StreamUrl, EpisodeCode, codec labels
      xtream.ts             XtreamParse.brs + XtreamTask.brs: API calls and parsing
      progress.ts           Progress.brs: Continue Watching entries
      search.ts             SearchIndex.brs + SearchTask.brs: background index and matching
      tracks.ts             Tracks.brs: language names, audio/subtitle options
      playback.ts           Playback.brs: HoldStep, ClampSeek, BarFraction
      opensubtitles.ts      Subtitles.brs + SubtitleTask.brs: login, search, download, ranking
      oshash.ts             OsHashHex without BigInt (two 32-bit halves with carry)
      srt.ts                new: SRT/WebVTT parser and cue lookup with a time offset
      compat.ts             Compat.brs, rebuilt for Samsung (see section 6)
      storage.ts            Registry.brs over localStorage
    platform/
      player.ts             interface: open, play, pause, seek, tracks, events
      avplay.ts             Tizen implementation
      html5.ts              desktop fallback (<video>, MP4 only) for development
      keys.ts               maps Tizen and desktop keys to: up down left right ok back playpause play pause rew ff
    ui/
      focus.ts              focus manager (section 4.1)
      dom.ts                tiny h() helper, class toggles, image preloading
      components/           PosterRow, Hero, Pills, NavBar, Keyboard, Dialog, Spinner, SubtitleLayer
      screens/              Login, Home, Details, Search, Player, SubtitleSetup
    styles/                 tokens.css (section 5), base.css, one file per screen
  assets/fonts/  assets/images/
  tests/                    vitest unit tests for core/
  dev/                      desktop harness and mock Xtream server with fixture data
  tools/                    package.sh (build + sign .wgt), install.sh (sdb/tizen install)
```

### 4.1 Focus

The Roku build's worst bugs were focus bugs (OK on a tab also opened the movie under it). Rules for the web version:

- One `FocusManager` owns the current focus target. Screens register zones (nav bar, rows, buttons, keyboard, panels) and each zone decides what Up/Down/Left/Right do inside it and where focus leaves to.
- One global `keydown` listener. It calls `preventDefault()` and hands the key to the active screen only. Nothing else listens for keys.
- Act on **OK when the key goes down**, but ignore auto-repeat (`event.repeat`) for OK and Back, and swallow any key that arrives within 150 ms of a screen change. That replaces Roku's "act on release" trick.
- Seeking needs key-up too: Left/Right start a hold on keydown and stop on keyup (section 7.5).

### 4.2 Data flow

- `xtream.ts` does all HTTP with XHR and a 20 s timeout. Same endpoints as Roku: `player_api.php?username&password` with `action` = `get_vod_categories`, `get_series_categories`, `get_vod_streams&category_id`, `get_series&category_id`, `get_vod_info&vod_id`, `get_series_info&series_id`. Streams: `/movie/<u>/<p>/<id>.<ext>` and `/series/<u>/<p>/<id>.<ext>`.
- Parse exactly as Roku does, including the provider quirks in section 10.
- Keep a small in-memory cache per session (categories, rows, vod info, series info) so going back to Home never refetches.

## 5. Design tokens

Same palette and shapes as Roku (`tools/make_images.py`, `src/components/common/Pills.brs`). At 1080p:

| Token | Value | Use |
|---|---|---|
| `--bg` | `#151028` | screen background (night plum) |
| `--surface-1` | `#1E1736` | cards, error box, tips card |
| `--surface-2` | `#241C42` | unfocused input fields |
| `--pill` | `#30275A` | unfocused buttons and pills |
| `--pill-selected` | `#43377A` | chosen but not focused (current season, current track) |
| `--focus` | `#C9B8FF` | anything focused: button fill, poster ring, tab highlight |
| `--on-focus` | `#151028` | text on a focused button |
| `--lavender` | `#B9A3FF` | glow tint, accents |
| `--pink` | `#FF9ECF` | progress bars, eyebrows ("UP NEXT"), errors, the + in the logo |
| `--butter` | `#FFD98A` | sparkles, "won't play" notes |
| `--text` | `#F7F3FF` | main text |
| `--text-dim` | `#C3B8E6` | secondary text |
| `--text-faint` | `#9083BD` | captions, hints |

- **Fonts:** Fredoka Medium and SemiBold for titles, buttons and tabs; Nunito SemiBold and ExtraBold for everything else (copy the TTFs and OFL licences from `src/fonts`).
- **Shapes:** pills fully rounded (Roku 14 px radius at 44 px tall, so `border-radius: 999px`), cards 15 px radius, posters 15 px corners, focus ring 4 px lavender outside the poster, focused buttons scale to 1.06.
- **Motion** (ease-out cubic unless noted):
  - screen enter: 300 ms fade plus a 27 px float up (Roku uses 18 px at 720p)
  - hero text: 350 ms fade and float up each time the focused title changes
  - backdrop: 500 ms cross-fade, only after the image has loaded
  - tab highlight: 220 ms glide between tabs
  - loading posters: 1.4 s gentle opacity pulse
  - player controls: 200 ms fade
- **Glows:** two big soft radial glows behind each screen (lavender top left at 20 % opacity, pink bottom right at 12 %), as pre-rendered PNGs.

## 6. Samsung-specific design decisions

1. **Subtitles are drawn by ARAN+.** Embedded text tracks come through `onsubtitlechange`; online subtitles are fetched once as SRT, parsed in `srt.ts` and timed against `getCurrentTime()`. Because the file is local, "1s earlier/later" just changes an offset. On Roku every nudge cost a download; here it costs none. Style: Nunito ExtraBold 44 px, white with a dark outline, bottom centre, lifted above the controls when they're showing.
2. **Playability check.** Tizen has no reliable "can you decode this" call like Roku's `CanDecodeVideo`. Instead:
   - a static table of what the TV's model year plays (containers, video codecs, audio codecs), filled in from the M0 tests and Samsung's spec sheet;
   - a learned list in localStorage: when AVPlay fails with a format error on a file whose codecs the provider reported, remember that combination and mark it "Won't play" next time;
   - never block: a warning with "OK to try anyway", as on Roku.
   Expect far fewer warnings than on the Roku TV.
3. **Search keyboard.** Use a custom on-screen keyboard grid for Search (results update as you type, focus stays predictable). For the login and OpenSubtitles forms, a normal `<input>` with the Samsung system keyboard is fine and supports long pasted values.
4. **No `*` key.** The account menu (Keep watching, Online subtitles, Sign out) is a round icon at the right end of the nav bar. In the player, Audio & subtitles is reached from the button row.
5. **Moviehash without BigInt.** Sum the 64-bit little-endian words as pairs of 32-bit numbers with carry. Use the Roku test vectors (section 9) to prove it matches.

## 7. Screens and behaviour

Everything below matches Roku v0.4.1 unless it says otherwise.

### 7.1 Login
- Fields: Server, Username, Password. Pasting a full M3U or `get.php` link into Server fills in the username and password (`ParseProviderLink`), and servers without a scheme get `http://` (`NormalizeServer`).
- Sign in calls `player_api.php` and checks `user_info.auth = 1` and status `Active` (`ParseAuth`), showing the server's reason when it fails.
- Saved in localStorage only. Title: "Welcome to ARAN+".

### 7.2 Home, Movies, Series
- **Nav bar** at the top: Home, Movies, Series, Search, and the account icon. A lavender highlight glides between tabs.
- **Hero** fills the top half: backdrop (right side, fading into the background on the left and bottom), title, meta line (year · runtime · genre · ★ rating), three lines of plot. Resting 0.6 s on a movie fetches `get_vod_info` to fill in the backdrop, runtime and codecs.
- **Rows** of posters below the hero. Home has Continue Watching first, then the provider's first six movie and first six series categories, interleaved, titled "Category · Movies" or "Category · Series". Movies and Series tabs list all their categories. Each row holds the 40 newest titles (`added` for movies, `last_modified` for series). Rows load five at a time as you scroll down, at most three requests in flight, and show eight pulsing placeholder posters until loaded.
- **Poster:** rounded, lavender ring and slight scale on focus, pink progress bar for Continue Watching, "S1:E4" caption for series in Continue Watching, dimmed with a butter "Won't play" tag when the check says so.
- **Keys:** Up from the first row or Left from a row's first poster goes to the nav bar. OK on a tab switches tabs. Back from the rows jumps to the first row, then the nav bar, then asks to exit.
- Adult categories and titles are hidden (`IsAdultName`, `is_adult`).

### 7.3 Details
- Backdrop with fade, title, meta line, plot, cast and director, and a butter compatibility note when relevant.
- **Movie:** Resume (with the time) and Play from start, or just Play.
- **Series:** Resume S1:E4 (or Play S1:E1), a row of season pills, and an episode list (still, "1. Title", runtime or "Won't play", two lines of synopsis). The in-progress episode shows its progress bar. Season 0 is called "Specials" (Roku lists it first).

### 7.4 Search
- Keyboard on the left (a to z, 0 to 9, space, delete, clear), results on the right as two rows, Movies and Series.
- Xtream has no search, so the first search of a session builds an index in the background: `get_vod_streams` and `get_series` for each category, three at a time, keeping only name, id, poster, year, kind and extension. (Try the single all-categories call first; fall back to per-category if it is huge or times out.) Results fill in while it indexes, with a small "Still indexing your library" note.
- Matching: `NormalizeSearch` (lower case, accents folded, apostrophes dropped, other punctuation to spaces). Titles that start with the query come first, then word-start matches, then anywhere. Debounce typing by 250 ms.

### 7.5 Player
Layout (1080p): a top fade with the Back pill and the title; a bottom fade with the play/pause circle, elapsed time, the scrollbar (lavender fill, pink preview), remaining time; and a button row: **Audio & subtitles**, **Episodes** (series), **Next episode** (when there is one), **Restart**.

| Controls hidden | |
|---|---|
| OK | pause and show the controls |
| Up / Down | show the controls |
| Left / Right, Rewind / Fast forward | preview a jump (below) |
| Play/Pause, Play, Pause | as named |
| Back | leave the player |

With the controls showing: Up from the bar reaches Back, Down reaches the button row, OK on the bar toggles pause, Left/Right on the bar preview a jump. They hide after 5 s while playing and stay while paused.

**Back order:** cancel a pending jump preview, else close a panel, else hide the controls, else leave.

**Jump preview:** each step moves a preview marker and a time bubble, not the video. Step size comes from `HoldStep(msHeld)`: 10 s for the first 1.5 s of holding, then 30 s, then doubling every 1.5 s up to 10 min. While held, step every 250 ms on a timer (ignore the remote's own key repeat). The video jumps 0.8 s after the last press. Clamp with `ClampSeek` (never past 3 s before the end).

**Resume and progress:**
- Start 5 s before the saved position when it is past 10 s.
- Save every 15 s of playback, on pause, and on leaving. Nothing under 10 s is saved.
- At 95 % a movie leaves Continue Watching; a series entry moves on to the next episode at 0, and leaves after the last one.
- Only a stream that actually started playing counts. An error never adds to Continue Watching and never triggers Up Next.
- Continue Watching keeps 20 entries, newest first, keyed `m:<streamId>` and `s:<seriesId>`, same fields as Roku's `Progress.brs`.

**Up Next:** when an episode ends and another follows, a card at the bottom right says "UP NEXT", the episode, and "Starts in 8 · OK to play now". OK or Play starts it at once; Back leaves the player.

**Panels** (dim the video, keep it playing):
- *Audio & subtitles:* Audio column and Subtitles column. Subtitles lists Off, the file's own tracks, then "Find English subtitles online", then online results once found, and "Show subtitles 1s earlier / later" while an online one is on. A note underneath explains states and shows OpenSubtitles downloads left today. The choice (`{audio: language, subtitles: language | "off" | "online"}`) is remembered and applied to the next video.
- *Episodes:* the current season's list; OK plays that episode.

**Errors:** before playing, if the check says it won't play, explain why with "OK to try anyway". If AVPlay fails, retry once, then show "This video didn't play" with AVPlay's error name, the container and codecs from the provider, whether this TV is known to play them, and the stream address with the password hidden. OK retries, Back returns.

### 7.6 Online subtitles (English only)
- **Setup screen** from the account menu: API key, username ("Your username, not your email"), password. Save first, then check, so nothing is lost when the check fails. Check the key on its own with `GET /infos/formats`, then `POST /login`, and show OpenSubtitles' exact message and HTTP code on failure. Keep `token` and `base_url` from login. Remove button clears it.
- **Search:** `GET /subtitles` with `languages=en`, `type=movie` + `tmdb_id` (or `type=episode` + `parent_tmdb_id` + `season_number` + `episode_number`), plus `moviehash` when the server supports range requests. Query keys sorted, values lower case (`OsQuery`). If the TMDB search finds nothing, retry by cleaned title and year (`CleanTitleForSearch`).
- **Ranking** (`ParseOsResults`): hash matches first, then human-made over machine-translated, then non-SDH, then most downloaded; show the top six, labelled "matches this file" where it applies.
- **Download:** `POST /download {file_id}` gives a `link` and `remaining`; fetch the SRT once, keep it in memory for the video. Retry once with a fresh login on 401 or 403. Timing nudges change a local offset.
- **Auto mode:** once the viewer has picked an online subtitle, later videos without an English text track search and load the best match 2.5 s after playback starts.
- **Moviehash:** two range requests for the first and last 64 KB (`Range: bytes=0-65535`), total size from `Content-Range`, 8 s timeout, give up quietly without a 206 of exactly 65536 bytes.

## 8. Getting it onto the TV

**One-time setup**
1. On the TV: open Apps, press 1 2 3 4 5 on the remote (the 123 button brings up the number pad), turn Developer mode on, enter the computer's IP address, and restart the TV (hold the power button until it restarts).
2. On the computer: install Tizen Studio with the TV Extensions and the Samsung Certificate Extension (from Package Manager).
3. In Device Manager, add the TV by IP and connect. Note its DUID.
4. In Certificate Manager, create a **Samsung** certificate (not Tizen), sign in with the Samsung account, and include the TV's DUID. Back up the author and distributor `.p12` files and passwords somewhere safe outside the repo.

**Every build**
- `npm run package` builds and signs `ARANplus.wgt` with the Tizen CLI (`tizen package -t wgt -s <profile>`).
- `npm run install:tv` runs `sdb connect <tv-ip>` and `tizen install -n ARANplus.wgt -t <device>`.
- The app stays installed and appears in the Apps list; developer mode can stay on.

**Later, to cut out the computer (experiments, not v1):**
- **CI signing:** store the `.p12` files and passwords as encrypted GitHub Actions secrets and have CI produce a signed `.wgt` on every push. Installing still needs something on the home network.
- **Thin launcher:** install a small shell app once that loads the real app bundle from GitHub Pages and falls back to the last cached copy. Updates would then be a `git push`. Needs a public repo (or paid Pages for a private one), a matching content security policy, and care with HTTP-only Xtream servers (an HTTPS page can't XHR to HTTP).
- **Community installers** such as TizenBrew exist for loading apps without Tizen Studio; worth a look, not relied on.

## 9. Testing

- **Unit tests (vitest)** for everything in `core/`. Port the Roku tests as they are (`tests/utils_test.brs`: 137 checks; `tests/parse_test.brs`: 100 checks), including:
  - the moviehash vectors: the 64-byte head and tail arrays at `tests/utils_test.brs` around line 128 give `4d9a760e894662f2` for size 131072, `4d9a760fc94462f2` for 5368709120, `a2efcb63de99b847` for 6148914691236517205, and 64 bytes of `0xFF` for both with size 12884901895 give `00000002fffffff7` (tests the 64-bit wrap);
  - `HoldStep`: 10 at 0 ms, 30 at 1.5 s, 480 at 7.5 s, 600 at 9 s and beyond; `ClampSeek(4000, 3600) = 3597`;
  - the Xtream quirk fixtures in `tests/parse_test.brs`;
  - new tests for `srt.ts` (CRLF, BOM, HTML tags, overlapping cues, offsets).
- **Desktop harness** (`npm run dev`): the app in desktop Chrome at 1920x1080, arrow keys, Enter, and Escape or Backspace as Back, the HTML5 player for MP4s, and a mock Xtream server serving fixture JSON and sample artwork. No real credentials in the repo, ever.
- **Screenshots:** Playwright captures each screen from the harness for review in chat.
- **On the TV:** debug through Tizen Studio (Run As > Tizen Web Application in debug mode opens Chrome DevTools against the TV). Keep a hidden diagnostics panel (for example, press Up Up Down Down on the account icon) showing `navigator.userAgent`, the model, and the last 50 log lines.
- **CI:** GitHub Actions runs typecheck, lint, tests and the bundle on every push, and uploads the unsigned build.

## 10. Lessons from the Roku build

- **Xtream quirks:** numbers arrive as strings; empty objects arrive as `[]` (`info: []`); `episodes` is normally `{"1": [...], "2": [...]}` but PHP sends a plain array when season keys are sequential; season names come from `seasons[]`; TMDB id may be `tmdb` or `tmdb_id`; `backdrop_path` is a list; codecs sit in `info.video.codec_name`, `info.video.profile` and `info.audio.codec_name`; episode titles often carry a "Show - S01E02 - " prefix to strip; `is_adult` is `"1"`.
- **Only real playback counts.** Mark a video as started on the first real progress, not on open. Errors can be followed by an "ended" event; ignore it.
- **Save before you validate.** The OpenSubtitles form lost typed keys because it saved only after a successful check.
- **Show the server's own words.** "HTTP 401: invalid username/password" beat any friendly guess when debugging from a photo of the TV.
- **Usernames, not emails,** for OpenSubtitles login.
- **One focus owner** (section 4.1).
- **Back hides before it leaves** in the player.
- **Keep secrets out of git.** The IPTV login, OpenSubtitles key and signing certificates live on the TV or on the computer only. Scan every diff for the provider's hostname and username before pushing, and mask passwords in any on-screen URL.

## 11. Milestones

| | Scope | Done when |
|---|---|---|
| **M0** | Repo, config.xml, hello-world screen with fonts and palette, packaging and install scripts, the section 2 checks | A signed ARAN+ tile opens on the TV and shows the engine version; one XHR to the Xtream server works; AVPlay plays an HEVC MKV and an AVI from the provider |
| **M1** | `core/` ports with tests, storage, mock server and desktop harness | All ported Roku checks pass in CI |
| **M2** | Login, Home (nav, hero, rows, Continue Watching, lazy loading), Details (movie and series), account menu | Browse and open any title on the TV |
| **M3** | Player: AVPlay wrapper, controls, jump preview, Back order, resume, progress, Up Next, episodes panel, restart, errors and diagnostics | Watch an episode start to finish and roll into the next; Continue Watching is right afterwards |
| **M4** | Audio and embedded subtitle tracks, subtitle layer, remembered choices, OpenSubtitles setup, search, download, auto mode, timing | English subtitles on a title that has none, nudged by 1 s without a new download |
| **M5** | Search tab, motion polish, performance pass on the TV, README, CI build | Smooth scrolling on the TV, search finds titles across the whole library |

## 12. Kickoff checklist for the new repo

- Create an empty repo (suggested name `aranplus-samsung`, private is fine unless the thin launcher is wanted later).
- Attach `CrumbsAndCravings/roku-iptv-player` for reference and read this file first.
- Have the TV's model code, the computer, and the Samsung account ready for M0.
