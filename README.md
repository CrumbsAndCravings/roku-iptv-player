# ARAN+

A Netflix-style IPTV player for Roku. Sign in with the Xtream Codes login from your IPTV provider and browse movies and series as poster rows, with a big backdrop for whatever you're focused on, a Continue Watching row, and resume-where-you-left-off playback.

Built for a 720p Roku TV (TCL 32S357, Roku OS 15), so the UI is laid out at 1280x720 and images are requested at sizes that suit that screen.

## What works

- **Sign in** with server, username and password. Pasting a full M3U link into Server fills in the username and password for you. The login is saved on the TV only.
- **Search** (the tab after Series): a keyboard on the left and Movies and Series results on the right, updating as you type. Xtream servers have no search, so the first search of a session indexes your library in the background, a few lists at a time, and results fill in as it goes. Matching ignores case, accents and punctuation; titles that start with what you typed come first. Right from the keyboard's last column (or ⏩) reaches the results, Left or Back returns. Typing a category's name ("punjabi", "bollywood", "comedy") also shows a **Categories** row; OK on one opens its page. Down from the keyboard's bottom row reaches a few rows of symbols (& ' - : . , ! ? ( ) + # @ /).
- **Home, Movies and Series tabs.** Each category is a row of posters, newest first. Rows load a few at a time as you scroll so big catalogs don't choke the TV. Category names are tidied (`EN | ACTION ★` becomes "Action", `|IN| ACTION` becomes "Hindi Action"), categories of new releases come first, and Home mixes the newest movie and series categories. Every row ends with a **See all** tile that opens a page of the whole category, newest first; **Search this category** at the top of that page (Up from the first row, or \*) narrows it as you type, and Back clears it. The **Categories** tab lists every category in your languages as cards: new releases first, then each language's movies and series, with how many titles each holds. Category pages and search both read the library stored on the Roku, so they don't ask the provider for anything. A personal build can list the languages you watch (`"languages": ["en", "hi", "pa"]` in `src/source/account.json`); categories in other languages are then left out of the tabs and of search, which also means far fewer requests when the library loads. Language comes from the provider's codes (`EN ✪`, `FR ◉`, `IN ✪ PUNJABI`), language names, or the script a name is written in. On Home, each language takes turns after the new releases, so a Punjabi or Bollywood row isn't buried. On a screen that isn't 4K, 4K categories go to the end. Titles lose provider tags and years (`EN ★ Alterity - 2026` shows as "Alterity", 2026).
- **Hero banner** with the focused title's backdrop, year, runtime, genre, rating and plot. Movie details are fetched once you pause on a poster.
- **Picked for you** (new in 0.5.7): Home learns from what you watch, as Netflix does. Under Continue Watching come **Top picks for you** (new titles from the categories you watch most) and **Because you watched …** rows (the rest of that series of films first, then more from its category), and the categories you watch move up the page. It all comes from the library stored on the Roku, so it asks the provider for nothing more. Taking a title off Continue Watching early counts against what it's like.
- **Rate and save titles** (new in 0.5.8): **Not for me**, **I like this** or **Love this!** on a title's page (or press \* on any poster on Home) teaches Home more than watching does: loved titles get their own "Because you watched" rows, and a "Not for me" pushes that kind of title down. **+ My List** saves a title for later, in a **My List** row at the top of Home.
- **Continue Watching** at the top of Home, with a progress bar on each poster. Movies drop off when finished; series move on to the next episode. To take something off by hand, press \* on its poster, or use **Remove from Continue Watching** on its details page. With a sync service set up (see [`sync/`](sync/README.md)), Continue Watching follows you between devices: stop on one TV and pick up on another.
- **Details page** with Resume / Play from start, and for series a season bar and episode list with stills, runtimes and synopses. Left and Right in the episode list switch to the previous or next season.
- **Player** with its own controls: play/pause beside a scrollbar, a Back button with the title on top, and a button row with Audio & subtitles, Episodes, Next episode and Restart. It resumes a few seconds before where you stopped, saves progress every 15 seconds, and counts down to the next episode ("Up next", OK to skip the wait). Paused for 3 minutes, it lets go of the provider's connection (which the provider may drop anyway) and opens it again when you press play; when the provider's server fails, it asks once more after 5 seconds before showing an error.
- **Online subtitles (English):** when a file has no subtitles of its own, **Find English subtitles online** in the Subtitles column searches OpenSubtitles by the title's TMDB id (or its name), plus a fingerprint of your exact file when it plays through the helper on a computer at home (below), and lists the best matches with "matches this file" ones first. Picking one loads it and resumes where you were; **1s earlier / later** fixes timing. After you use one, later videos without built-in English subtitles fetch a match automatically. Connect your free OpenSubtitles account from Home → \* → **Online subtitles**. With the sync service, subtitles downloaded on any device (this Roku, the Samsung TV, the iPhone) are saved for that movie or episode, timing nudges too, and every device shows them without another download (the sync service needs its October 2026 update, see `sync/README.md`; the player says so when it hasn't had it): listed first as "English · saved for this title", and on by themselves unless subtitles are set to Off or a built-in language. Nudging saved ones costs no download either.
- **Audio & subtitles:** pick an audio track or turn on subtitles built into the file. Your language choice is remembered and applied to the next video automatically.
- Adult categories and titles are hidden.

Remote shortcuts: **Left** from a row's first poster (or **Up** from the first row) reaches the tabs, **Back** jumps to the top row, then the tabs, then exits, **\*** (options) opens the account menu (Change server address, for when the provider moves, keeps everything; Sign out), **Play** on a details page starts the main button.

## Player controls

| Controls hidden | |
|---|---|
| OK | Pause and show the controls |
| Up / Down | Show the controls |
| Left / Right (or ⏪ ⏩) | Preview a jump of 10 seconds; hold to go faster (30 s steps after 1.5 s, then doubling every 1.5 s, up to 10 min per step). The video jumps shortly after you let go. Through [the helper](#the-helper-on-your-computer), a picture of that moment shows above the bar. |
| Play/Pause | Pause or resume |
| Instant replay | Back 10 seconds |
| \* | Audio & subtitles |
| Back | Leave the player (with the controls showing, Back hides them first) |

With the controls showing, **Up** reaches Back (top left), **Down** reaches the button row, and on the scrollbar row **OK** pauses and **Left/Right** seek as above. The controls hide after 5 seconds while playing and stay up while paused.

## When a video won't play

Some files can't play on a given Roku no matter which app you use: AVI (DivX/Xvid) files don't play on any Roku, and TVs without an HEVC decoder (like the TCL 32S357) can't play HEVC/H.265 video. ARAN+ asks the TV what it can decode and marks those titles before you press Play: posters are dimmed with "Won't play", episodes say "Won't play" instead of a runtime, and the details page explains why. Playing one anyway shows a plain explanation, with OK to try anyway. With [the helper on your computer](#the-helper-on-your-computer), those titles play too.

For other failures the player retries once without a format hint, then shows what went wrong: Roku's own error, the file's container and codecs (as reported by your provider), whether this TV can decode them, and the stream address with the password hidden. A title only counts as watched once it has actually played.

## The helper on your computer

The helper is a small program on a computer at home, switched on while you watch, that uses [FFmpeg](https://ffmpeg.org) to turn files the Roku can't play into a stream it can. It lives in the Samsung app's repo ([CrumbsAndCravings/Samsung-IPTV-Player](https://github.com/CrumbsAndCravings/Samsung-IPTV-Player), `helper/`, on its default branch: helper 1.2, which also serves the iPhone app), and the Samsung TV, the iPhone and the Roku share it.

**What goes through it:**

- **AVI files** (DivX and Xvid): the picture is converted to H.264.
- **HEVC files** when this Roku can't decode HEVC (most Roku TVs, the TCL 32S357 among them). These are most of the library, and the heaviest work for the computer.
- **Files whose sound this Roku can't play** (DTS or TrueHD, with no other track): the player switches to the helper from where you are, and remembers the title so it starts there next time.
- **Anything that fails on its own** after the usual retry, unless the provider refused it outright (it would refuse the helper too).

**How it plays.** The helper fetches the file with your login (from its own settings file, so the login never travels from the TV) and turns it into HLS, the format Roku streams in: a playlist for the whole film in six-second pieces, which the helper makes as the Roku asks for them. The picture becomes H.264 at the Roku's screen height (720 lines on a 720p TV, which saves the computer most of the work on 1080p and 4K files) and the sound stereo AAC, in your language when the file has it.

- **The time bar** shows the whole film, and resuming starts right where you were.
- **Jumping** is the Roku's own: a piece the helper has made plays at once, and one further away takes a few seconds while the helper starts converting from there.
- **Pictures while you choose a jump:** holding Left/Right shows a picture of where you'd land, for every part the helper has converted: behind you, and ahead as far as it has got. Further on there's just the time, since asking the provider for pictures would stop the film (it allows one connection).
- **Another language:** the Audio column lists the file's sound tracks; picking one starts the stream again with it, from where you were.
- **Online subtitles** work as they do for any other video. Subtitle tracks built into the file don't come through.
- **When you leave a video,** the Roku tells the helper to stop, so the provider's one connection is free for whatever plays next.
- **One at a time:** the provider allows one connection, so the Samsung TV, the iPhone and the Roku can't watch at once, with or without the helper.

**Set it up on Windows (once):**

1. Install FFmpeg: open PowerShell and run `winget install Gyan.FFmpeg`.
2. Get the Samsung repo (its default branch) and follow its README's "The helper on your computer" section: put your provider's login in its `personal.json` and start the helper with `npm run helper` (or double-click `helper\start-helper.cmd`). The first time, it adds `"transcoder": { "url": ..., "key": ... }` (this computer's address and a random key) to that `personal.json`, and Windows asks whether Node.js may use the network: allow **private networks**.
3. Copy that `"transcoder"` part into this repo's `src/source/account.json`. `npm run helper-settings` does it for you when the Samsung repo sits next to this one (otherwise name it: `npm run helper-settings -- C:\path\to\Samsung-IPTV-Player`), keeping the rest of the file. By hand, it goes next to your login:

   ```json
   { "server": "...", "username": "...", "password": "...",
     "transcoder": { "url": "http://192.168.1.20:8090", "key": "the key the helper wrote" } }
   ```

4. Build and install the app again (`npm run build`, then upload the zip, or `npm run deploy`).

From then on, start the helper before you watch (or put a shortcut to `helper\start-helper.cmd` in the Startup folder: press Win+R, type `shell:startup`). Its window shows what it is converting and with what: the graphics card, Intel Quick Sync, or the processor. If the Roku says the helper didn't answer, check that the computer is on and the window is open. Give the computer a fixed address in your router, or the Roku may lose it. Without `transcoder` in `account.json`, ARAN+ plays exactly as it did before.

## Look and feel

| | |
|---|---|
| Night plum `#151028` | backgrounds |
| Lavender `#C9B8FF` | whatever has focus: buttons, tabs, the ring around a poster |
| Bubblegum `#FF9ECF` | progress bars and the + in the logo |
| Butter `#FFD98A` | sparkles and "won't play" notes |

Titles and buttons use Fredoka (rounded), everything else Nunito. Posters, buttons and cards have small, sharp corners in the Netflix manner, posters sit close together with badges and progress on the poster, and soft lavender and pink glows sit behind each screen.

The motion follows the web app's. ARAN+ opens with an intro and its own sting: the plus knocks, ARAN punches in out of a glow with light rays behind it, the plus spins and sparks, and the intro flies through the plus into the app. Home's tab bar is floating glass with a glass lens that springs from tab to tab, stretching as it goes; OK swells the bar and lifts the lens. Screens slide in from the right (Details rises like a card, the player fades) while the one underneath sinks back, the home banner's lines come up one after another as its picture settles (and, resting on a title, its backdrops take turns, slowly zooming, as Netflix's banner does), rows of posters build in one after another with each picture fading in as it loads, buttons spring up when you land on them, and the player's controls are drawn up from the bottom of the screen, with Back and the title sliding in from the side. Soft click sounds go with moving, choosing and going back. The Account menu (`*` on Home) turns the click sounds and the intro off and on.

Artwork (icon, splash, logo, glass, intro pieces, gradients, rounded shapes) is generated by `tools/make_images.py`, and the sounds (clicks and the sting) by `tools/make_sounds.py`.

## Install on your Roku

1. **Turn on developer mode.** On the Roku remote press: Home ×3, Up ×2, Right, Left, Right, Left, Right. Note the IP address shown, accept the agreement, and set a password. The TV restarts.
2. **Open the installer.** On a computer or phone on the same Wi-Fi, go to `http://<your-roku-ip>` and sign in as `rokudev` with the password you set.
3. **Upload** `aranplus.zip` (from `npm run build`, or from the latest build shared with you) and press **Install**. ARAN+ opens on the TV and stays in your channel list.

To update, upload a newer zip the same way. A Roku can only hold one developer channel at a time, which is fine for this.

## Develop

Every push to `main` is validated, tested and packaged by GitHub Actions; the zip is attached to each run under **Actions → Build → Artifacts**.


Needs Node 18+.

```sh
npm install
npm test          # off-device tests for parsing, storage and helpers
npm run lint      # BrighterScript validation of all .brs/.xml
npm run build     # build/aranplus.zip
ROKU_HOST=192.168.1.50 ROKU_PASSWORD=yourpass npm run deploy   # build and install over Wi-Fi
npm run images    # regenerate icons, splash, glass and gradients (needs Pillow)
npm run sounds    # regenerate the click sounds and the intro sting (needs numpy)
```

For a personal build that signs in by itself, put your login in `src/source/account.json` as `{"server": "...", "username": "...", "password": "..."}` before `npm run build`. Git ignores that file, so it never reaches the repo or the CI builds. The login screen also opens filled in with it after a sign-out. The same file holds `languages`, `sync` (see [`sync/`](sync/README.md)), `transcoder` (see [the helper](#the-helper-on-your-computer)) and `opensubtitles` (`{"apiKey": "...", "username": "...", "password": "..."}`, used whenever the Roku has no OpenSubtitles account of its own, so it survives a reinstall or a sign-out).

A 35 second vertical promo video, made from the app's own fonts, images and screens, is in [promo/](promo/README.md).

### Layout

```
src/
  manifest                    channel metadata, icons, splash
  source/main.brs             entry point
  components/
    MainScene.*               screen stack: Login/Home, Details, Player; click sounds
    Intro.*                   the intro when the app opens
    screens/                  LoginScreen, HomeScreen, SearchScreen, DetailsScreen, PlayerScreen
    items/                    PosterItem (rows), EpisodeItem (episode list)
    tasks/XtreamTask.*        HTTP off the UI thread
    tasks/XtreamParse.brs     API response -> content nodes (tested)
    tasks/SearchTask.*        background library index; SearchIndex.brs does the matching (tested)
    tasks/SubtitleTask.*      OpenSubtitles sign-in, search and download; common/Subtitles.brs (tested)
    tasks/HelperTask.*        requests to the helper on a computer at home; common/Helper.brs (tested)
    common/                   Utils, Registry, Progress (Continue Watching), Taste (what you watch and rate),
                              MyList, Pills (buttons),
                              Motion (springs, tweens, Sound)
  fonts/                      Fredoka and Nunito (SIL Open Font License)
  images/                     generated by tools/make_images.py
  sounds/                     generated by tools/make_sounds.py
tests/                        brs interpreter tests
```

The Xtream endpoints used are `player_api.php` with `get_vod_categories`, `get_series_categories`, `get_vod_streams`, `get_series`, `get_vod_info` and `get_series_info`, and streams play from `/movie/…` and `/series/…`.

## Docs

- [`docs/features.md`](docs/features.md): every feature with its exact rules, where the code is, and a checklist for bringing the Samsung app level.
- [`docs/samsung-plan.md`](docs/samsung-plan.md): the original plan for the Samsung (Tizen) version.

## Roadmap

- **Live TV and sports:** a Live tab with favourite channels and a "Live now" sports row for tournaments, plus a simple guide.
- **Pick your rows:** hide categories you never watch (other languages, kids) and reorder the rest.
- **See all** grid for a whole category, and **My List**.
- Audio track and subtitle picker in the player.
- Profiles, and optional sync of Continue Watching between TVs.
- **Samsung TVs:** a Tizen version with the same look and features, planned in [docs/samsung-plan.md](docs/samsung-plan.md).
