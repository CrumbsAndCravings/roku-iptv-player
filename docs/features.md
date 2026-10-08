# ARAN+ feature reference

Every feature of ARAN+ for Roku as of **v0.5.6** (sync added after commit `8d861e1`; the helper on a computer at home, §15, in 0.5.0, and its whole-film playlists in 0.5.2; subtitles saved for every device, §9.5, in 0.5.3; the OpenSubtitles account kept, §8, in 0.5.4; the glass tab bar, sounds, intro and motion, §10, in 0.5.5; pictures above the bar while choosing a jump through the helper, §15.4, in 0.5.6). Each feature lists what it does, the exact rules and numbers, why it works that way, and where the Roku code lives. Use it as the checklist and spec for bringing the Samsung app ([CrumbsAndCravings/Samsung-IPTV-Player](https://github.com/CrumbsAndCravings/Samsung-IPTV-Player)) up to the same level.

- **Build plan for Samsung:** [`samsung-plan.md`](samsung-plan.md). That plan covers parity with Roku v0.4.1; everything added since then is in this document, marked **New since 0.4.1**.
- **User-facing summary:** [`../README.md`](../README.md).
- **Samsung status** below is taken from the Samsung repo's README at commit `5840feb`: **Has**, **Partly**, **Missing**, or **n/a**. Check the repo before relying on it.
- Code pointers are Roku paths under `src/components/`. The pure logic is in `common/*.brs` and `tasks/*Parse.brs` / `tasks/SearchIndex.brs`, all covered by the off-device tests in `tests/`. Port those tests with the logic: they are the fastest way to prove a port matches.

## Contents

1. [At a glance](#1-at-a-glance)
2. [Signing in](#2-signing-in)
3. [Being gentle with the provider](#3-being-gentle-with-the-provider)
4. [Organizing the library](#4-organizing-the-library)
5. [Browsing](#5-browsing)
6. [Search and the stored library](#6-search-and-the-stored-library)
7. [Player](#7-player)
8. [Online subtitles](#8-online-subtitles)
9. [Continue Watching](#9-continue-watching)
10. [Look and feel](#10-look-and-feel)
11. [Messages and diagnostics](#11-messages-and-diagnostics)
12. [Data formats and interfaces](#12-data-formats-and-interfaces)
13. [Lessons and gotchas](#13-lessons-and-gotchas)
14. [Samsung port checklist](#14-samsung-port-checklist)
15. [The helper on a computer at home](#15-the-helper-on-a-computer-at-home)

## 1. At a glance

| Area | Feature | Samsung |
|---|---|---|
| Sign-in | Server, username, password; paste an M3U link to fill all three | Has |
| Sign-in | Links in `/playlist/<user>/<pass>/…` and stream-path form | Missing |
| Sign-in | Built-in personal login, auto sign-in, switches when it changes | Missing |
| Sign-in | Refusals explained: who answered, what they said, the address, likely causes | Missing |
| Sign-in | Retry as ARAN+, then as a web browser, when a server turns the app away | n/a (the TV fixes the user agent; port the explanations) |
| Provider | Session row cache; stop after a refused row; paced search loading | Partly (has cache and pacing) |
| Library | Language detection from codes, words and script; tidy category names | Missing |
| Library | Language preferences hide other languages everywhere | Missing |
| Library | New-release categories first; languages take turns on Home | Missing |
| Library | 4K categories last on non-4K screens | n/a (the Q60 is 4K) |
| Library | Provider tags and years removed from titles (`EN ★ Alterity - 2026`) | Missing |
| Browsing | Home, Movies, Series tabs with hero and lazy rows | Has |
| Browsing | **Categories** tab of category cards | Missing |
| Browsing | **See all** tile at the end of every row; category page (grid) | Missing |
| Browsing | Search inside a category | Missing |
| Browsing | Left/Right in the episode list switches seasons | Missing |
| Search | Background library index; Movies and Series rows | Has |
| Search | Every match ranked (no cap), per kind | Partly (still caps at `MATCH_CAP`) |
| Search | One- and two-letter queries match word starts only | Missing |
| Search | Categories row in results | Missing |
| Search | Library saved on the device, searched instantly, refreshed in the background daily | Missing |
| Search | Only the languages you watch are indexed | Missing |
| Search | Symbol keys | Has (its own keyboard with symbols, Shift, Caps) |
| Player | Custom controls, jump preview, Back order, resume, Up Next | Has |
| Player | Refused streams checked and retried under another identity | n/a (port the explanation) |
| Player | Poster-image codecs (MJPEG, PNG) ignored as "video" | Missing |
| Player | Audio formats shown; unplayable audio track swapped automatically | Missing |
| Player | **The helper on a computer at home** converts AVI, HEVC (where this Roku can't decode it), unplayable sound, and titles that fail on their own (§15) | Has (it started there; the Roku uses its HLS output) |
| Player | Pictures above the bar while choosing a jump through the helper (§15.4) | Missing (its one MPEG-TS stream from the helper has no pictures; the web app has them) |
| Subtitles | OpenSubtitles search, download, auto mode, timing nudges | Has |
| Continue Watching | Row, progress, resume, next episode | Has |
| Continue Watching | Remove a title (Home poster menu, details button) | Missing |
| Continue Watching | **Sync between devices** through a small Cloudflare Worker (§9.4) | Missing |
| Look | Sharp 3 to 5 px corners, posters 10 px apart, badges on the poster | Missing (Samsung is still rounded) |

## 2. Signing in

### 2.1 Login form and pasted links
- Three fields: **Server**, **Username**, **Password**. Whitespace is trimmed from all three. A server without `http://` or `https://` gets `http://`; any path or query is dropped (`NormalizeServer`).
- **Pasting a link into Server fills in all three fields** (`ParseProviderLink`), when the link has:
  - `?username=…&password=…`, like `get.php` and `player_api.php` links, or
  - a path of the form `/playlist/<user>/<pass>/…` (for example `/playlist/u/p/m3u_plus?output=hls`), or
  - a stream path: `/live/`, `/movie/` or `/series/` followed by `<user>/<pass>/`.
  - Path parts are URL-decoded.
- **New since 0.4.1:** the stream-path and `/playlist/` forms, and parsing whatever is typed into Server, not only text containing `username=`.
- **Why:** one provider sent only a `/playlist/` link, and its username differed from the one typed by hand by a single letter. Pasted links avoid typos.
- Code: `common/Utils.brs` (`NormalizeServer`, `ParseProviderLink`), `screens/LoginScreen.brs`.

### 2.2 Built-in personal login (new since 0.4.1)
- A personal build can carry a login in `src/source/account.json`:
  - `{"server": …, "username": …, "password": …, "languages": ["en", "hi", "pa"]}`
  - The file is **git-ignored**. The repo is public, so never commit it, and CI builds don't have it.
- **No saved login:** the login screen fills in from the file and signs in by itself at launch (`autoSignIn`).
- **After a sign-out:** the form is prefilled but not submitted.
- **Switching providers:** the app stores a stamp (`server + " " + username`) under registry `account/builtIn`. When a newer build carries a different login, the app replaces the saved login and clears Continue Watching, whose IDs belong to the old provider. Online subtitles are kept.
- **The same account** (fixed in 0.5.6): when the stamp is new but the saved login is the build's own account (`SameLogin`: the same server as `NormalizeServer` writes it, ignoring case, and the same username), nothing is cleared: the saved login takes the build's password and the stamp is written. Before, the first build carrying a login cleared Continue Watching even for the account already signed in by hand.
- Code: `common/Registry.brs` (`BuiltInCreds`, `LanguagePrefs`), `common/Utils.brs` (`SameLogin`, tested), `MainScene.brs` (init), `screens/LoginScreen.brs`.
- **Samsung:** the equivalent is a git-ignored `personal.json` bundled into the `.wgt`. The same "switch when the stamp changes" rule applies.

### 2.3 Refused sign-ins, explained (new since 0.4.1)
When the server answers anything other than 200, the error says who answered and what they said. On the login screen it replaces the tips card, so long messages stay inside the TV's safe area (y below 648 at 720p).

- **The first line** comes from `HttpDetail(code, headers, body)`:
  - `HTTP 403 from nginx: "Forbidden"`, using the server header up to the first `/`, space or `(`.
  - JSON bodies use `message` or `error`. HTML bodies are reduced to text by `BriefText`: scripts and styles dropped, tags stripped, whitespace collapsed, at most 70 characters, and a repeated title like `404 Not Found 404 Not Found` said once.
  - **Cloudflare:** every answer from a site behind Cloudflare carries `server: cloudflare` and `cf-ray`, so those headers alone don't mean Cloudflare blocked anything.
    - A refusal counts as Cloudflare's own only when its page or headers say so (`IsCloudflareBlock`): a `cf-mitigated: challenge` header or a "Just a moment" / `challenge-platform` page is a "browser check"; an `error 1xxx` code is shown as that code; "you have been blocked" is a "block".
    - Anything else is written as `HTTP 403 via Cloudflare`, with the origin's own words.
  - **Lesson:** an early build blamed Cloudflare for answers that came from the provider's own server.
- **Then the address used,** on its own line (`Address: http://…`), so a missing port or http/https mix-up is visible in a photo.
- **Then a hint, by status:**
  - **401 or 403:** "Often a typo in the login, an old address the provider has retired, a trial that has ended, or a block on your internet connection after too many attempts."
  - **A Cloudflare block:** "Only the provider can allow it, or give you another address."
  - **404:** "Nothing at this address answers as an Xtream server. Ask the provider for the Xtream or API address (often with a port like :8080), or paste their whole M3U link into Server."
- **Retrying under another identity** (Roku only): on 403, 404, 503, or a Cloudflare-proxied 401 at sign-in, the app asks again as `ARANplus/<version>`, then as a desktop browser (`UserAgentsToTry`). It keeps the first identity that gets through, in `creds.userAgent`, for API calls, search indexing, playback (`HttpHeaders` on the content node) and the subtitle file hash.
  - **Samsung:** the TV replaces `User-Agent` with its own browser string, which is why Samsung got in where the Roku didn't. Skip the retries; port the explanations.
- Code: `common/Utils.brs` (`HttpDetail`, `BriefText`, `IsCloudflare`, `IsCloudflareBlock`, `CloudflareKind`, `IsRefusalCode`, `UserAgentsToTry`, `UserAgentName`, `BrowserUserAgent`, `AppUserAgent`), `tasks/Http.brs`, `tasks/XtreamTask.brs` (`runAuth`), `screens/LoginScreen.*`.

### 2.4 Account menu and sign-out
- `*` on Home's tab bar, or **Account** in the menu `*` opens on a poster (§5.1.2), opens: **Keep watching**, **Online subtitles**, **Turn click sounds off** (or on), **Turn the intro off** (or on), **Change server address** (new in 0.5.13, §2.5), **Sign out** (new in 0.5.5: the two switches, §10).
- **Sign out** clears the login, Continue Watching on the TV (it comes back from the sync service), the OpenSubtitles account and the saved search library (`ClearAccount`), and stops the library worker. A personal build's own OpenSubtitles account (§8) comes back by itself. Since 0.5.13 the watch history, ratings and My List stay for the same account signing back in, even at a new address; another account signing in clears them (`NoteLogin`).

### 2.5 When the provider moves (new in 0.5.13)
Providers change their address now and then (a new domain, the rest of the address the same). The titles and their ids stay, and so does the account, so nothing should be lost.
- **Change server address** in the Account menu: a keyboard with the current address; **Check and save** signs in at the new address first (one request), then the same account carries on there, Home starting again. A failed check changes nothing and offers **Try again**.
- **The same account at a new address** (`LoginChange` in `common/Utils.brs`): the same username and password at another server is "moved"; the same server and username is "same"; anything else is another account. The TV keeps the last account signed in (registry `account/last`: server, username, and a fingerprint of the password, `PasswordStamp`, not the password). This counts for Change server address, signing out and back in at the new address, and a personal build whose built-in address changed (MainScene, which also reads the old build's stamp `account/builtIn`).
- **Continue Watching follows** (`NoteMovedFrom`, registry `sync/previous`): Continue Watching syncs by a space made from the address (§9.4), so a new address starts an empty space. After a move, the next sync fetches the old address's space once and sends its list and removals along to the new one (`progressRound` in `tasks/SyncTask.brs`), then forgets it. Subtitles saved on the sync service under the old address aren't moved; they're found again when wanted.
- **The stored library** stays: a saved library belongs to the username wherever the server is (`SameOwner`), and the daily refresh brings anything new.

## 3. Being gentle with the provider
New since 0.4.1. **Why:** one provider stopped answering for a while after about 100 requests in a minute; the Samsung app's M0 notes saw the same thing. During a block, sign-in and videos fail too, so every part of the app avoids bursts and stops asking once it is refused.

| Rule | Value | Where |
|---|---|---|
| Home row requests in flight | 3 | `HomeScreen.brs` `pumpQueue` |
| Rows kept for the session (tab switches don't refetch) | by `kind:categoryId` | `HomeScreen.brs` `m.rowCache` |
| A failed row (refused or no answer) | stop loading more rows for that tab; no walking through other categories | `onRowLoaded` |
| Search: first library load | 2 lists in flight, starts at least 1 s apart | `SearchTask.brs` |
| Search: background refresh | 1 list at a time, starts at least 2 s apart | `SearchTask.brs` |
| Search: while a video plays | no new list starts (checked every 2 s) | `m.global.playing` |
| Search: failures | stop after 3 in a row (refused, timed out, unreadable) | `SearchTask.brs` |
| A list that hangs | given up after 45 s | `SearchTask.brs` |
| API timeout | 45 s per request | `tasks/Http.brs` |
| Indexed categories | only the languages you watch (about 75 of 312 lists on the provider in use) | `SearchTask.brs` |
| Series | one request for the whole list (about 5 MB, 3 s for 7,000 series) | `SearchTask.brs` |
| Online subtitles while a video plays straight from the provider | no reads of the file for a fingerprint (since 0.5.15); the search goes by TMDB id or name | `SubtitleTask.brs` `osFind` |
| A direct stream paused 3 minutes | lets go of its connection; play opens it again at the same spot (since 0.5.15) | `PlayerScreen.brs` `releaseConnection` |
| The provider's server failing (a 5xx) | asked again once, 5 s later, then at most once a minute of playing (since 0.5.15) | `PlayerScreen.brs` `retryLater` |
| A stream opened again for new subtitles | 1.2 s after it closed (since 0.5.15) | `PlayerScreen.brs` `reloadWithSubtitle` |

## 4. Organizing the library
All new since 0.4.1. Code: `common/Categories.brs`, tested in `tests/utils_test.brs` with the real category names of the provider in use.

### 4.1 Reading a category name: `ClassifyCategory(name, year)`
Returns `{ lang, isNew, kids, label }`.

- **Language** is `en`, `hi`, `pa`, `other` or `""` (can't tell). It's decided in this order:
  1. **A language code** in any segment wins: `EN ✪ ACTION`, `|FR|`, `[AR]`.
     - **Segments:** the name is split on `|`, `[`, `]`, `(`, `)`, `:`, `*`, `#`, `=`, `~`, on a hyphen only when it has spaces around it (so `SCI-FI` stays whole), and on any symbol outside Latin letters (`✪`, `◉`, `★`, emoji). Letters with accents are kept.
     - **English codes:** `EN`, `ENG`, `UK`, `GB`, `US`, `USA`, `AU`, `NZ`, `IE`.
     - **Hindi codes:** `IN`, `IND`, `HI`, `HIN`. **Punjabi codes:** `PB`, `PJ`, `PUN`, `PAN`.
     - **Other-language codes:** about 90, including `CA` (Québec French in IPTV movie lists), `EX` (ex-Yugoslavia), `AS` (Asian, written in Arabic), `SW`, `AR`, `FR`, `DE`, `ES`, `TR`, `PK`.
     - **Why codes win:** `EN ◉ TURKISH` is Turkish shows with English subtitles, filed under English by the provider.
  2. **`IN` covers all of India,** so the name refines it: Punjabi words make it `pa`; Tamil, Telugu, Malayalam, Kannada, Gujarati (including the provider's typo `GUJARTI`) and the like make it `other`; anything else stays `hi`.
  3. **No code:** language words decide. Punjabi (`PUNJABI`, `PUNJAB`, `POLLYWOOD`), then Hindi (`HINDI`, `BOLLYWOOD`), then about 120 other-language and country words (`TAMIL`, `ARABIC`, `URDU`, `KOREAN`, `SOUTH INDIAN`, `K-DRAMA`, `SWEDEN`, `NOLLYWOOD`, …), then English (`ENGLISH`, `HOLLYWOOD`), then `INDIAN`, `INDIA` or `DESI` as Hindi.
  4. **Otherwise the script decides:** Devanagari is `hi`, Gurmukhi is `pa`, and Arabic, Greek, Cyrillic, other Indian scripts, Thai, Chinese, Japanese or Korean are `other`.
- **isNew** is set by:
  - the words `NEW`, `LATEST`, `RECENT`, `RECENTLY`, `TRENDING`, `POPULAR`, `THEATRICAL`;
  - the phrases `JUST ADDED`, `TOP 10`, `THIS WEEK`, `IN CINEMA`, `IN THEATER`, `IN THEATRE`, `BOX OFFICE`, `NOW PLAYING`, `NOW SHOWING`;
  - the current or last year as a word, so `[2025/2026]` counts.
- **kids:** `KIDS`, `KID`, `CHILDREN`, `CHILD`, `CARTOON`, `CARTOONS`, `JUNIOR`. Flagged only; nothing is hidden for it.
- **label**, the tidy name:
  1. Drop code segments and `VOD` / `VIP` decorations.
  2. Drop segments that are just `MOVIES` / `SERIES` / `FILMS` / `TV SHOWS` when other segments remain.
  3. Strip a trailing generic word from the last segment, unless what's left is two letters or less (`TV SHOWS`, `UK SERIES`, `3D MOVIES` stay whole) or is itself generic (`MOVIE SERIES` stays whole).
  4. Join the segments with ` · ` and title-case words that are all capitals. Acronyms stay as they are (`TV`, `HD`, `UHD`, `HBO`, `BBC`, `DC`, `MCU`, `UFC`, `IMDB`, `FIFA`, `BET+`, `OSN`, `VIU`, …), as do words with digits. There's a capital after `-` and `/` (`Sci-Fi`, `Concerts/Musical`).
  5. A label that's only `Movies` or `Series` becomes the language name, so `EN ◉ SERIES` becomes "English".
  6. Hindi and Punjabi labels get the language in front if it isn't already in them: `|IN| ACTION` becomes "Hindi Action".
  7. Other-language labels keep their code: `FR ✪ ACTION` becomes "FR · Action", so it isn't mistaken for the English one when every language is shown.
- **Examples from the provider in use:**

  | Category | Language | Label |
  |---|---|---|
  | `EN ✪ ACTION [4K]` | en | Action · 4K |
  | `EN ✪ 4K [2024/2025]` | en, new | 4K · 2024/2025 |
  | `VIP ✪ FIFA World Cup 2026` | "", new | FIFA World Cup 2026 |
  | `IN ✪ PUNJABI` | pa | Punjabi |
  | `IN ◉ INDIAN` | hi | Indian |
  | `UK ◉ UK SERIES` | en | UK Series |
  | `CA ◉ QUEBECOISE` | other | CA · Quebecoise |
  | `VIP ✪ كأس العالم 2026` (Arabic) | other | (hidden) |

### 4.2 Language preferences
- `LanguagePrefs()` reads registry `prefs/languages` (a JSON array) first, then `languages` in the built-in `account.json`. An empty list means every language.
- `CategoryWanted(info, langs)`: everything is wanted when the list is empty; categories of unknown language are always wanted; otherwise the category's language must be in the list.
- **Effect:** other-language categories leave Home, the Movies, Series and Categories tabs, **and search** (their lists aren't indexed). For the user: English, Hindi and Punjabi, which is 53 movie and 23 series categories of 312.
- There is no on-TV screen for this yet; the personal build sets it.

### 4.3 Ordering
- `OrganizeCategories(list, langs, year, demote4K)`:
  - Wanted categories, each with `{ id, name, label, lang, isNew, demoted, order }`.
  - Order: new releases first, then by language in the chosen order (unknown counts as the first language), otherwise the provider's order.
- **4K last:** with `demote4K` (the screen isn't 4K; `IsUhdScreen` reads `roDeviceInfo.GetVideoMode()` for `2160`/`4k`), labels matching `4K` or `UHD` go last and lose their new-release status. On 720p or 1080p they only cost bandwidth. **Samsung:** the Q60 is 4K, so don't demote.
- `TakeTurns(a, b)` merges two lists alternately: `a1, b1, a2, b2, …`. Used for movies and series.
- `LanguageTurns(entries, langs)` groups entries by language rank and merges them one per language per round, with demoted entries last. **Why:** without it, 50 English rows buried Bollywood and Punjabi.

### 4.4 Tab contents
- **Home:** Continue Watching, then up to 18 rows:
  - new-release categories, movies and series taking turns;
  - then the rest, movies and series taking turns, with each language taking turns.
- **Example Home for the provider in use, on the 720p TV:**
  1. FIFA World Cup 2026 · Movies
  2. Multi-Sub · 2025/2026 · Movies
  3. Box Office · Movies
  4. Multi-Sub · 2023 · Movies
  5. Indian · Series
  6. Punjabi · Movies
  7. Multi-Sub · Series
  8. Bollywood · Movies
  9. Multi-Sub · Movies
  10. Multi-Audio · Series
  11. Drama · Movies
  12. English · Series
  13. Action · Movies
  14. …
- **Movies and Series tabs:** every wanted category of that kind, organized as above.
- Row titles are the tidy labels; Home adds `  ·  Movies` or `  ·  Series`.
- Each row holds the 40 newest titles: movies sorted by `added`, series by `last_modified`. The first 5 rows load at once and 3 more as you near the end, at most 3 requests at a time, with 8 pulsing placeholder posters until each row arrives.
- Code: `screens/HomeScreen.brs` (`buildPlan`, `planEntries`).

### 4.5 Tidy titles: `SplitTitle(name)`
- Some providers put a language tag in front of every title and the year at the end: `EN ★ Alterity - 2026`, `PUN ★ Nikka Zaildar 4 - 2025`, `BL ★ BOMBAY STORIES - 2026`.
- **Tag:** 2 to 4 capitals followed by `|` or a symbol beyond Latin (`★`, `✪`, `◉`) is removed. `UFO - 2018`, `M3GAN` and `DC: …` stay intact.
- **Year:** a trailing ` - 19xx` / ` - 20xx` is removed and used as the year when the provider gives none.
- Applied to row titles, series names (`ParseSeriesInfo`, which also cleans episode-title prefixes) and the search library. Continue Watching entries saved before this keep their old names.
- Code: `common/Utils.brs` (`SplitTitle`), `tasks/XtreamParse.brs`, `tasks/SearchIndex.brs`.

### 4.6 Adult content
Categories whose names hold `xxx`, `adult`, `18+` or `porn`, and titles with `is_adult = 1`, are never shown (`IsAdultName`). The whole-series request includes adult categories, so its titles are filtered to the allowed category IDs.

## 5. Browsing

### 5.1 Home
- **Tabs:** Home, Movies, Series, **Categories** (new), Search, on a floating glass bar with a glass lens on the current tab (new in 0.5.5, §10).
- **Hero:** backdrop, title, meta (year · runtime · genre · ★ rating), plot. Resting 0.6 s on a movie fetches `get_vod_info` for runtime, backdrop and codecs.
- **Moving banner** (new in 0.5.12, `common/Slides.brs`): the provider's details list several backdrops for most titles (`backdrop_path`; up to 5 kept, sized w780, in the item's `backdrops` field, `BackdropList`). Resting on a title with more than one, they take turns every 7 seconds, cross-fading over 1.4 s, each slowly zooming in to 106 % (a little longer than it shows). It starts once the details are in (straight away for series, whose lists carry them), stops when the focus moves, and waits while another screen is on top. The same on Details. The pictures come from the image hosts, not the provider's video connection.
- **Keys:**
  - Left from a row's first poster, or Up from the first row, reaches the tabs.
  - OK on a tab acts on key release, so the release can't land on a poster.
  - Back jumps to the first row, then the tabs, then exits.
  - `*` on a poster opens its menu (My List, rating, Continue Watching, Account; §5.1.2); on the tab bar, the account menu.
- **See all tile** (new): every category row ends with a "See all ›" card that opens the category page (5.3). It isn't added to Continue Watching. Focusing it keeps the previous hero.
- **"Won't play"** posters are dimmed, with a badge on the poster.

### 5.1.1 Picked for you (new in 0.5.7)
Home learns from what you watch, as Netflix does. Code: `common/Taste.brs`, `tasks/SearchIndex.brs` (`IndexFind`, `CategoriesFrom`, `IndexPersonal`, `ListItems`), `tasks/SearchTask.brs` (`answerPicks`), `screens/HomeScreen.brs` (`addPersonalRows`, `askPicks`, `onPicks`); tested in `tests/parse_test.brs`.
- **What counts** (registry `taste/history`, newest first, at most 30): a movie counts 1 once you're 3 minutes in, 2 from half way, 3 when finished; a series counts 1 while you watch it and half a point more for each episode finished, up to 4; taking a title off Continue Watching before a fifth of it counts −1. Continue Watching also counts (1, or 2 from half way) for what isn't in the history, which brings in what you watched on your other devices through sync. When the registry is nearly full, the history keeps only 10.
- **Liking a category:** each title's weight, halving every 30 days, added to its category. The library worker knows every title's category from the stored library, so no request goes to the provider.
- **Rows under Continue Watching** on the Home tab:
  - **Top picks for you:** titles from the 6 categories you like most, scored by how much you like the category times how new the title is (halving every 90 days since it was added, or by year), at most 8 from one category, 30 in all, each title once, nothing you've watched (by key, and by name for its other copies).
  - **Because you watched …:** for your 2 latest titles watched at least half way (or started, when there are none): first the rest of its series of films (titles starting with the same first two words, or its one word of four letters or more, a leading "the" aside, like "Carry On Jatta 2" after "Carry On Jatta"), then the newest from its category. 20 in all.
  - They're laid out as placeholders as Home builds, so nothing jumps when they arrive, and refresh when you come back from a video. A row with nothing to pick goes. With no stored library yet (it's built the first time Search, Categories or a "See all" page is used), they wait for a launch that has one. The library worker starts 6 seconds after Home's own rows, so Home and the intro come first.
  - **How they get to Home** (since 0.5.9): the worker makes two passes over the library (`IndexFind` for the titles named, `IndexPersonal` for all the picking) and sends back plain lists of fields (`picked`), which Home makes into rows itself.
  - **The freeze in 0.5.7 to 0.5.9:** Home checked for the stored library with `roFileSystem`, which a Roku only allows on the main thread and in tasks; on the render thread it isn't made, so the app crashed (and a sideloaded app sits frozen in the debugger) whenever Home built these rows. Since 0.5.10 the library worker records that it has a library (registry `search/saved`, `LibrarySaved`), and `tools/test.sh` fails if a screen-side file makes such an object. A library stored before 0.5.10 counts once the worker has loaded it (opening Search or Categories). 0.5.9 also had a guard that switched My List, the picks and the row order off for a whole version after a launch that stopped part way; after 0.5.9's own crash it hid My List in 0.5.10, so 0.5.11 took it out (and clears its registry marks).
- **Row order:** the likings are kept (`taste/scores`, the 12 most liked categories) and Home moves the categories you like up, most liked first: after the first two rows on the Home tab (new releases, so something new stays near the top), after the first on Movies and Series.
- Sign-out keeps the history and likings for the same account signing back in; another account signing in clears them (§2.4).

### 5.1.2 Ratings and My List (new in 0.5.8)
- **Rating:** on Details, a button after My List says **Rate** (or the rating given); on Home, \* on any poster opens **Add to My List** (or Remove), **Rate it** (or "Rated: …"), **Remove from Continue Watching** on those posters, and **Account** (\* on the tab bar still opens Account straight away). The choices: **Not for me**, **I like this**, **Love this!**, and **Take my rating away** once rated. The menu that leads to another (Rate it, Account) opens it once it has closed.
- **What a rating does** (stored as `r` on the title's history entry, `TasteRate`): "Not for me" counts −3 for its category whatever was watched; a like adds 1.5 and a love 3 to what watching counted (at least 1, so rating before watching counts). Loved titles come first for "Because you watched", then liked, then watched; a title that's not for you never gets one. Rated titles are the last to drop out of the 30-title history. Home's picks refresh right after a rating.
- **My List** (`common/MyList.brs`, registry `mylist/items`): **+ My List** / **In My List** on Details, or the \* menu on Home. Newest first, at most 40, each `{ k, n, x, t }` (no pictures, to keep the registry small). Adding a title counts 1 towards its category, as starting it would. Home shows a **My List** row right under Continue Watching: name cards straight away, with pictures from the stored library (`IndexListRow`) when it's there. It follows changes when you come back to Home, keeping the focus on the same poster. It stays across a sign-out for the same account (§2.4).
- Neither is shared between devices yet.

### 5.2 Categories tab (new)
- A screen of category cards (210×104: name, plus "Movies · 104"), in rows:
  1. **New releases**
  2. then for each language in the chosen order: "**<Language> movies**" and "**<Language> series**", or a single "**<Language>**" row when the language has 8 categories or fewer.
- **For the provider in use:** New releases (3), English movies (about 48, 4K last), English series (23), Hindi (Bollywood, Indian), Punjabi.
- Built from the category lists Home already has. Title counts come from the stored library (`countsRequest` → `counts`); a card shows just "Movies" until the library has loaded.
- OK opens the category page.
- Code: `screens/CategoriesScreen.*`, `items/CategoryTile.*`.

### 5.3 Category page, "See all" (new)
- **Every title in one category, newest first,** from the stored library: no request to the provider. Capped at the newest 1,000, with the count line saying so.
- **Layout (720p):** a poster grid 9 across and 3 down, 120×180 posters 10 px apart (1160×560 from x 60, y 104). The heading and count are top left; the focused title, year and "won't play" note are top right.
- **Search this category:** the button at the top right, reached with Up from the first row or `*` anywhere on the page.
  - Roku's keyboard opens, and the grid behind it narrows as you type (0.35 s debounce).
  - **Done** keeps the results; **Clear** clears them; Back from the grid clears a search before leaving.
  - **Matching** is the same as search (6.4): every word typed must appear, and one or two letters only match word starts.
  - **Order:** name starts with the query, then a word starts with it, then elsewhere; newest first within each.
  - The count line reads "3 matching "jatt" of 104".
  - Don't move focus to the grid while the keyboard is open; it would take the keyboard away.
- **While the library is still loading,** the page says so and asks again at most every 5 s as the library grows.
- Code: `screens/CategoryScreen.*`, `tasks/SearchIndex.brs` (`IndexBrowse`, `nameMatches`, `matchRank`).

### 5.4 Details
- **Movie:** "Resume from 1:02:33" and "Play from start", or just "Play". With progress, also **Remove from Continue Watching** (new).
- **Series:** "Resume S1:E4" (or "Play S1:E1") and "Episodes", plus **Remove from Continue Watching** when the show is in progress (new).
  - **Episodes:** a season bar and an episode list (still, "1.  Title", runtime or "Won't play", synopsis). Specials are season 0.
  - **Left/Right in the episode list switch to the previous or next season** (new), jump to its first episode, and update the season bar. Up still reaches the season bar.
- **Compatibility line** in butter yellow, for example "Won't play on this Roku: it can't decode AVI files." It says "TV" on a Roku TV and "Roku" on a stick or box (`DeviceWord`).
- Code: `screens/DetailsScreen.brs`.

## 6. Search and the stored library

### 6.1 The library index (`tasks/SearchIndex.brs`)
- **Parallel arrays of strings,** to keep memory low on tens of thousands of titles:
  - `names[i]`: a space, then the title through `NormalizeSearch`.
  - `records[i]`: kind letter (`m`/`s`), id, ext, poster URL, title, category id, date added (seconds), year, joined by `Chr(30)`, with `-` for blanks.
- `seen` dedupes by `kind+id`. In the provider in use, each title is in exactly one category, so a record's single category is complete.
- **`categories`:** `{ key "m:<id>"/"s:<id>", kind, id, name, label, norm, count }`, counted while adding titles. `catIndex` maps a key to its position.
- **`NormalizeSearch`:** lower case; accents folded (only when the text has non-ASCII); `'` and `` ` `` dropped; other punctuation and spaces collapsed to one space.

### 6.2 Loading the library (`tasks/SearchTask.brs`, the session's "library worker")
- Started on first use by Search, a category page or the Categories tab (`LibraryTask()`), and kept in `m.global.search` until sign-out.
- **Order of work:**
  1. Download both category lists and keep the wanted ones (4.2).
  2. Download **all series in one request**, filtered to the wanted category IDs. If that fails or takes over 45 s, fall back to one request per series category, alternating with the movies.
  3. Download movies one category at a time, with the pacing in section 3.
- The open search refreshes after every 4 lists and when the series arrive.

### 6.3 Keeping it (new since 0.4.1)
- **Saved to `cachefs:/aranplus-search.txt`**, format `aranplus-search-4`:
  - a header line: format, owner (`server username`), saved-at seconds, title count, category count;
  - then every name, then every record, then every category (`key`, `kind`, `id`, `count`, `name`, tab-separated);
  - one item per line, with `\r`, `\n` and tabs replaced by spaces.
  - Format 3 (records without a year) still loads.
- **Searched instantly on every later launch,** whatever its age. A copy for another login is ignored.
- **Once the saved copy is a day old,** a fresh copy loads in the background: 1 list at a time, 2 s apart, never during playback. Searches use the old copy until the new one is complete, then it is swapped in and saved. A refresh that stops early keeps the old copy and tries again next time.
- **Saved only when complete,** allowing up to 3 broken categories.
- **Trade-off:** titles added today reach search and category pages within about a day; Home rows show them at once.
- Roku may clear `cachefs:` when it needs space; that just means one first-time load again.
- **Samsung:** use `localStorage` if the size allows (measure the TV's quota), otherwise IndexedDB.

### 6.4 Ranking: `IndexSearch(index, query, limit)`
- **Every word typed must appear** in the title. **One or two letters only match word starts:** "th" finds "The Office" but not "Other", which keeps typing quick.
- **Rank:** title starts with the query (0), a word starts with it (1), elsewhere (2); then shorter titles first; then index position.
- **Every match is ranked; there is no cap.** Movies and series are ranked separately, so thousands of movie matches can't push the series out. Each row shows its best 40.
  - Matches are kept as one sortable Double per match: `(rank*1000 + min(len, 999)) * 1e7 + position`.
  - **Why:** the old code stopped looking after 2,000 matches in index order, and movies were indexed first. "the" then showed no series, and a title called exactly "The" could be missed. **The Samsung app still has this cap (`MATCH_CAP` in `src/core/search.ts`).**
- **Typing:** the screen waits 0.35 s after a key (debounce). The worker reads the latest query, not each queued one.
- Tested in `tests/parse_test.brs` with 2,500 matching movies plus two series, and an exact match indexed last.

### 6.5 Categories in search results (new)
- **A Categories row before Movies and Series:** categories whose tidy name matches the query, by the same word rules.
  - **Order:** names starting with the query first, then the biggest.
  - At most 20, and only categories that hold titles.
  - Each card shows "Punjabi" with "Movies · 104"; OK opens its page.
- Typing "punjabi" therefore reaches every Punjabi title, even though the titles themselves don't contain the word.

### 6.6 Search screen
- **Roku:** the system mini keyboard on the left, with two rows of symbol keys under it: `& ' - : . , !` and `? ( ) + # @ /`. Down from the keyboard's bottom row reaches them; OK types one.
- Results are on the right: Categories, Movies, Series. Right from the keyboard or `⏩` reaches them.
- The library status ("Loading your library: 12 of 60 lists (3,400 titles so far)") sits beside the heading.
- **Samsung** has its own keyboard with symbols, Shift and Caps. Keep it.

## 7. Player
The core is unchanged since 0.4.1 and is specified in `samsung-plan.md` §7.5:
- custom controls; jump preview with `HoldStep`;
- Back order: cancel preview → close panel → hide controls → leave;
- resume 5 s early; save every 15 s; finished at 95%;
- Up Next 8 s; retry once; diagnostics.

Additions since then:

- **Picture codecs aren't the video** (new): providers often report an MKV's poster image as its video stream (`MJPEG Baseline`, `PNG`). `IsPictureCodec` treats `mjpeg`, `png`, `bmp`, `gif`, `webp` and `tiff` as unknown, so those files no longer show a false "won't play".
- **Device wording** (new): messages say "this TV" on a Roku TV and "this Roku" on a stick or box. The heading reads "Your Roku can't play this file". On a stick there's no "a Roku stick could play it" sentence.
- **Refused streams** (new, Roku only):
  - On a Roku HTTP error (code -1 or a 4xx/5xx in the error text, `HttpCodeIn`), the player sends header-only requests for the stream under each identity (Roku, ARAN+, browser).
  - If another identity is allowed and the current one isn't, the player switches to it, saves it and plays.
  - Otherwise the error box lists what each identity got ("Checked as a Roku: HTTP 403 via Cloudflare, no reason given."). When every identity is refused, it says "The trial may not include it, may allow one device at a time, or may have ended."
  - **Samsung:** port the "every way refused" explanation only.
- **Audio rescue** (new):
  - Audio tracks show their format ("English · DTS").
  - At playback start, if the current track's format can't be decoded (`CanDecodeAudio`; DTS through a TV is the usual case), the player switches to a track it can play and shows a 9 s note: "Switched to English · Dolby AC-3, because this Roku can't play DTS audio."
  - If there's no playable track: "No sound? This file's audio is DTS, which this Roku can't play. Your provider may have another version of this title."
  - The Audio & subtitles panel notes "Audio now: AAC."
  - **Samsung:** AVPlay decodes most formats, but DTS varies by model year. Port the format labels and the swap when `getTotalTrackInfo` shows an undecodable track.
- **AVI:** Roku can't play AVI, so without the helper those titles are marked "Won't play" with "OK to try anyway". They're about 0.3% of the provider's library. With the helper on a computer at home (§15) they play, converted to H.264, and so do HEVC files on a Roku without HEVC, which is most of the library on the user's Roku TV.
- **Long pauses** (new in 0.5.15): a paused stream holds the provider's one connection, idle, and the provider may drop it, so that resuming stalls or is turned away. After 3 minutes paused (`releaseTimer`), a direct stream saves where it is, its subtitles and its sound track, and stops (`releaseConnection`); the title's backdrop stands in for the paused frame (`restPicture`). Play opens the stream again there with the same subtitles and sound (`resumeReleased`); jumps while it's let go move the spot. Helper streams are left alone, since their connection is the helper's, which keeps converting while you're paused.
- **The provider's server failing** (new in 0.5.15): an error with an HTTP 5xx in Roku's words, or FFmpeg's "Server returned 5XX" from the helper (`ProviderServerTrouble` in `common/Playback.brs`), is often over in a moment. The player asks once more 5 s later (`retryLater`: the stream, or the helper's description or start), and asks again only after a minute of playing. If it still fails, the error screen starts with plain words (`ServerTroubleText`): "Your provider's server had a problem sending this video. That's on their side, not your internet or this TV. Wait a minute and try again."
- Code: `screens/PlayerScreen.brs`, `common/Compat.brs`, `common/Tracks.brs`, `tasks/XtreamParse.brs` (`CodecFields`, `IsPictureCodec`).

## 8. Online subtitles
Unchanged since 0.4.1 apart from where the account is kept; see `samsung-plan.md` §7.6. Samsung has it. Points:
- **Save before checking.**
- **Show OpenSubtitles' own words and HTTP code** in errors. Long errors replace the tips card, as on the login screen.
- **Keeping the account** (new in 0.5.4). It's saved in the registry (`opensubtitles/account`), which a reinstall after deleting the channel, a cleared registry or a sign-out empties. So:
  - A personal build can carry it in `account.json`: `"opensubtitles": { "apiKey", "username", "password" }` (`OsAccountSettings`). It's used whenever the registry has none (`PickOsAccount`), and a build with a different key or username replaces the saved one at launch (stamp in `opensubtitles/builtIn`, as for the built-in login).
  - **Remove** saves `{ removed: true }`, so the build's own stays off too, until sign-out.
  - Leaving the setup screen with Back keeps what was typed, unchecked (`keepTyped`).
  - After saving, the screen reads the account back; if the Roku didn't keep it (an app's registry is about 16 KB), it says so instead of "Connected".

## 9. Continue Watching

### 9.1 Storage (`common/Progress.brs`)
- Registry `progress/items`: a JSON array, newest first, at most 20 entries.
- Keys are `m:<streamId>` and `s:<seriesId>`.
- Fields: `k`, `kind`, `id`, `ext`, `name`, `poster`, `bd`, `pos`, `dur`, `at`; series add `sid`, `season`, `episode`, `etitle`.

### 9.2 Rules
- **Saving:** every 15 s of playback, on pause and on leaving. Nothing under 10 s is saved.
- **Only real playback counts:** errors never add an entry and never trigger Up Next.
- **At 95%:** a movie leaves the row; a series moves to the next episode at 0, or leaves after its last episode.

### 9.3 Removing a title (new)
- **On Home:** `*` on a Continue Watching poster asks "Remove it from Continue Watching? Where you stopped is forgotten.", with **Remove from Continue Watching** and **Keep it**. The hero shows "* to remove" on those posters.
- **On Details:** a **Remove from Continue Watching** button whenever the title has an entry. For a series it removes the whole show. Buttons go back to plain Play.
- Removal is `ProgressRemove(key)`; Home refreshes the row when it regains focus.
- Each removal is also recorded with its time in registry `progress/removed` (`[{ k, at }]`, newest first, at most 100), so sync can pass it on.
- Code: `screens/HomeScreen.brs` (`continueItem`, `showContinueMenu`), `screens/DetailsScreen.brs` (`forgetProgress`).

### 9.4 Sync between devices (new)
- **Service:** a Cloudflare Worker on the free plan, with code, tests and setup steps in [`../sync/`](../sync/README.md).
  - It stores one list per provider login in KV and merges on every request.
  - Every request needs `Authorization: Bearer <SYNC_KEY>`.
  - CORS is open, so a web app can call it too.
- **One list per login:** the `space` is the first 16 hex digits of SHA-256 of `SyncSpaceText(creds)`: the server in lower case without a default port (`:80` for http, `:443` for https), a newline, then the username.
  - Every device signed in to the same provider account shares one list.
  - A different provider never mixes in.
  - **Every platform must build this text exactly the same way.**
- **Merging:** for each title (`k`), the newest change wins, whether an entry (`at`) or a removal (`removed[].at`); a removal wins a tie. `MergeProgress(local, localRemoved, remote)` on the device mirrors `merge` in the Worker, and both are tested.
- **What's kept:** the server keeps the 50 newest entries and 30 days of removals; devices keep their 20 newest entries and 100 removals.
- **One round:** `POST /v1/progress?space=…` with `{ entries, removed }` returns the merged state. The device then merges that into its *current* lists, never a blind replace, so a save made while the request was out isn't lost.
- **When the Roku syncs:**
  - at launch and sign-in;
  - right away after leaving a video or removing a title;
  - every 5 minutes while a video plays;
  - when Home regains focus, at most once a minute.
  - A round already running queues one more forced round.
- **Writes:** a few dozen on a busy day; the free KV plan allows 1,000.
- **Home** redraws Continue Watching only when a round changed the list (`m.global.syncedAt`).
- **Setup on a device:** `"sync": { "url": "https://aranplus-sync.<sub>.workers.dev", "key": "…" }` in the git-ignored `account.json`. With no `sync`, nothing changes.
- **Code:** `common/Progress.brs` (`ProgressRemovedList`, `MergeProgress`, `ProgressSave`), `common/Utils.brs` (`SyncSpaceText`), `common/Registry.brs` (`SyncConfig`, `SyncSpace`), `tasks/SyncTask.*`, `MainScene.brs` (`requestSync`, `onSynced`), `sync/worker.js`.
- **Samsung/iPhone:** port `SyncSpaceText` and `MergeProgress` with their tests, compute SHA-256 with Web Crypto (`crypto.subtle.digest`), and sync at the same moments.

### 9.5 Online subtitles saved for every device (new in 0.5.3)
- **What:** a download from OpenSubtitles on any device (this Roku, the Samsung TV, the iPhone) is saved on the sync service for that movie or episode, nudges included, so every other device shows it without a download, and without an OpenSubtitles account.
- **Storage:** one file per title (`m:<streamId>` or `e:<episodeId>`, as `itemKey()`), under `subs:<space>:<title>` in the Worker's KV, kept a year after it was last saved, up to 3 MB. Choosing other subtitles replaces it.
- **API:** `GET /v1/subtitles?space&k` (`&text=0` leaves the file out), `POST` with `{ fileId, name, delayMs, text }` to save, or `{ fileId, delayMs }` for a nudge; `GET /v1/subtitles/file?space&k&t=<token>&delay=<ms>` serves the file, moved by `delay`, with its own token instead of the key, because Roku's player fetches subtitles by address and can't send headers.
- **When the Roku shows them by itself:** where the subtitle preference is "online" (after built-in English ones) or not chosen yet (""); never over "off" or a built-in language. The column lists them first as "English · saved for this title", even without an OpenSubtitles account.
- **The Roku's way:** `lookUpSaved()` asks the service as each video starts; `autoSubtitles()` waits for the answer if it's still out. Saved subtitles play from the service's address (`SavedSubtitleUrl`), and nudges change `delay` there, so on the Roku they no longer use a download either. A fresh download (not one moved by OpenSubtitles) is fetched once more by `SyncTask` and saved (`shareSubtitle`).
- **No second opening** (new in 0.5.15): Roku only reads subtitle files when a stream loads, so showing new ones opens the stream again. A direct stream now waits for the lookup (3 s at most, `savedWait`) and saved ones go into it from the start, not showing (`onSavedLooked` sets `m.extraSubtitle`); `autoSubtitles()` or a choice in the column then just shows them (`reloadWithSubtitle` sees `m.attachedSubtitle`). The column and the subtitle preference never take them for the file's own (`builtInSubtitles`).
- **When saving fails** (new in 0.5.15): a note says why straight after the download, and the Audio & subtitles panel keeps it (`SubtitleSaveText`). A sync service from before saved subtitles answers 404, and both the lookup and the save then say "Subtitles can't be saved for next time, because your sync service is an older version" with where to update it (`OldSyncText`). Until 0.5.15 this failed silently, so a Worker that was never updated meant a download every time.
- **Code:** `sync/worker.js` (`subtitles`, `subtitleFile`, `moveCues`), `tasks/SyncTask.*` (modes `subtitle-get`, `subtitle-save`, `subtitle-delay`), `common/Subtitles.brs` (`SavedCandidate`, `SplitSavedCandidates`, `SavedSubtitleUrl`, tested), `screens/PlayerScreen.brs` (`lookUpSaved`, `showSaved`, `shareSubtitle`, `nudgeSaved`).
- **Setup:** the Worker needs updating once (`sync/README.md`, "Update it"); until then the service answers 404 to these requests, every device behaves as before, and the Roku says so (above).

## 10. Look and feel
- **Palette:**

  | Colour | Hex | Used for |
  |---|---|---|
  | Night plum | `#151028` | background |
  | Lavender | `#C9B8FF` | focus |
  | Pink | `#FF9ECF` | progress, eyebrows, accents |
  | Butter | `#FFD98A` | sparkles, "won't play" |
  | Text | `#F7F3FF` | main text |
  | Dim | `#C3B8E6` | secondary text |

- **Surfaces:** `#1E1736` cards, `#241C42` fields, `#30275A` pills, `#43377A` selected.
- **Fonts:** Fredoka (titles, buttons, tabs) and Nunito (everything else).
- **Sharp corners** (new, replacing the rounded look): Netflix-style radii from `tools/make_images.py`:
  - buttons and cards 4 px;
  - poster corner mask 3 px;
  - focus ring 5 px with a 3 px outline.
- **Dense posters** (new):
  - 10 px apart in rows, grids and search.
  - Badges ("Won't play", "S1:E4") sit on a dark band at the bottom of the poster, with the progress bar as a 4 px strip along the bottom edge, so rows don't need caption space.
  - Focus lifts the poster 6% (it was 10%) and shows the ring.
  - Home rows are 218 px tall; search rows 232 px.
- **Category and See-all cards:** the name on a tinted card. Category cards in the Categories tab have a pink left accent.
- **Motion** (new in 0.5.5, after the web app's `src/styles/motion.css` and `shell.css`; `common/Motion.brs` has its springs and `Tween`):
  - **Screens:** a page slides in from the right (28 px, 300 ms) and leaves the same way (240 ms); Details rises 40 px like a card (380 ms) and drops away; the player, Home and Login fade. The page underneath sinks back (to 97 %, faded out) and comes up again when you return (`MainScene.brs`, `moveScreen`).
  - **Home's banner:** it rises 14 px as its title, meta and plot fade in 70 ms apart; its backdrop fades in (500 ms) while settling from 106 % (1.6 s). Details does the same with its lines 40 ms apart.
  - **Posters:** a row's posters build in from the right, 45 ms apart (480 ms), when the row arrives; each picture fades in once loaded (320 ms); progress bars fill in after them (800 ms). Placeholders pulse (1.4 s).
  - **Buttons** (`Pills.brs`): the focused one springs to 106 % (the web app's spring, 420 ms).
  - **Player:** the controls are dragged on (since 0.5.14): Back and the title slide in 180 px from the left while the bar, the times and the buttons come up 180 px from under the screen, fading in (420 ms, easing out); they go back the same way, fading (320 ms, easing in), and come back from where they got to when a key brings them up while they're leaving (`showControls`, `hideControls`). Play turning into pause pops from 60 %.
- **Glass tab bar** (new in 0.5.5, after the web app's iOS 26 tab bar): a translucent plum pill with light along its top, a rim and a soft shadow (drawn: a Roku can't blur what's behind). A glass lens rests on the current tab, clear with the tab name lavender; with the bar focused it's lit lavender and follows the cursor, the names inside it dark (a second copy of the names, clipped to the lens). It springs from tab to tab (620 ms, overshooting a touch), stretching by its speed, longer one way and thinner the other. OK swells the bar to 104 % and lifts the lens (110 % by 122 %, its rainbow rim brighter); letting go, both spring back, the lens wobbling like jelly (760 ms), and the tab name pops. Tabs have equal 112 px slots. Code: `screens/HomeScreen.*` (`styleTabs`, `moveLens`, `pressBar`).
- **Glass buttons:** every pill has a sheen and rim over its tint (`glass_pill.9.png`), and unfocused ones are a little see-through.
- **Click sounds** (new in 0.5.5): a soft glassy tick for moving (focus moving in any list or row of buttons), a little rising pop with a ping for choosing, the pop falling for going back. Screens call `Sound("move" | "select" | "back")` (`common/Motion.brs`); MainScene holds the three `SoundEffect` nodes and plays them, leaving them out when they're off, while a video plays and during the intro. Moves closer than 60 ms apart (a key held down) tick once. Made by `tools/make_sounds.py`, quiet by design (peaks at −20, −14 and −16 dBFS).
- **Intro** (new in 0.5.5, after the web app's `src/ui/intro.ts`, `intro.css` and `sting.ts`): about 2.5 s over the first screen, which loads underneath. The splash screen is its first frame (the plus alone). The plus knocks (0.1 s); a boom (0.5 s) and ARAN punches in letter by letter out of a lavender and pink glow with 16 light rays bursting behind; the plus spins half a turn with two pings (0.68 and 0.82 s) and six sparks; at 1.55 s it flies through the plus (scaling 70 times around its middle) into the app, with a whoosh. The sting (`sounds/intro.wav`) is the web app's sting rendered to a file. Any key skips it; the Account menu turns it off. While it plays it keeps the keys (Home leaves the focus alone, `introPlaying`). Code: `components/Intro.*`; pieces and their places from `tools/make_images.py` (`images/intro.json`).
- **Safe area:** keep important text above y 648 at 720p. TVs crop the edges, which is why long errors moved into side cards.

## 11. Messages and diagnostics
- **Say who answered and what they said,** and include the address used. A photo of the screen is the main debugging channel.
- **Don't guess a cause as fact.** Write "Often…" and list the usual causes. An early build wrongly blamed Cloudflare.
- **Library state is always visible:**
  - "Loading your library: 12 of 60 lists (3,400 titles so far)"
  - "Searching all 31,000 titles"
  - "Your provider stopped answering, so the rest wait until you open ARAN+ again."
- **Home load errors** wrap to 3 lines, and add the retired-address and trial hints for refusals.

## 12. Data formats and interfaces

| Thing | Shape |
|---|---|
| Login (registry `account/creds`) | `{ server, username, password, userAgent }`; `userAgent` "" means the device's own |
| Built-in login stamp | registry `account/builtIn` = `"<server> <username>"` |
| Watch history (`taste/history`) | `[{ k: "m:<id>" \| "s:<seriesId>", n: name (≤ 32), w: weight, r: rating (-1, 1, 2; optional), t: seconds }]`, newest first, at most 30 (§5.1.1, §5.1.2) |
| My List (`mylist/items`) | `[{ k, n: name (≤ 40), x: extension, t }]`, newest first, at most 40 (§5.1.2) |
| Last account on this TV (`account/last`) | `{ server, username, pass }`, `pass` being a fingerprint of the password (§2.5) |
| Moved from (`sync/previous`) | the sync space of the address the account moved from, until the next sync has brought its Continue Watching (§2.5) |
| Stored library (`search/saved`) | when the library worker last loaded or saved the library stored on the Roku (seconds); cleared on sign-out |
| Category likings (`taste/scores`) | `{ "vod:12": 3.2, "series:7": 1.5 }`, the 12 most liked |
| Player prefs (`prefs/player`) | `{ audio: lang, subtitles: lang \| "off" \| "online", sounds: "on" \| "off", intro: "on" \| "off" }` (sounds and intro on unless "off") |
| Global fields (`m.global`) | `creds`, `playing`, `syncedAt`, `search`, `soundsOn`, `introPlaying`, and `sound` (alwaysNotify: the click sound a screen asks for) |
| Language prefs (`prefs/languages`) | `["en", "hi", "pa"]` |
| OpenSubtitles (`opensubtitles/account`) | `{ apiKey, username, password, token, baseUrl }`, or `{ removed: true }` when turned off here |
| Built-in OpenSubtitles (personal `account.json`) | `"opensubtitles": { "apiKey", "username", "password" }`; stamp `opensubtitles/builtIn` = `"<apiKey> <username>"` |
| Removals (`progress/removed`) | `[{ k, at }]`, newest first, at most 100 |
| Sync settings (personal `account.json`) | `"sync": { "url", "key" }` |
| Helper settings (personal `account.json`) | `"transcoder": { "url", "key" }`, copied from the helper's own `personal.json` (§15) |
| Titles that need the helper (`helper/titles`) | `["m:<id>", "e:<id>", …]`, newest first, at most 200; cleared on sign-out |
| Helper requests (`HelperTask`) | `request { mode: "info" \| "hash" \| "start" \| "lastError" \| "stop", url }` → `result { ok, info \| hash \| started \| said \| error }` |
| Sync service | see [`../sync/README.md`](../sync/README.md) |
| Library worker fields | `query` → `results` (ContentNode rows: Categories, Movies, Series; tagged `forQuery`); `status` `{ done, total, titles, stopped }`; `browse` `{ kind, categoryId, query }` → `browsed` (ContentNode with `total`, `forKey`, `loading`); `countsRequest` → `counts` `{ "vod:123": 104 }`; `picksRequest` `{ history, watching, because: [{ k, n }], list, forKey }` → `picked` `{ forKey, scores, loading, rows: [{ slot, title, items: [fields] }] }` (plain data; Home makes the rows); `stop` |
| Item fields (ContentNode) | `ItemDefaults()` in `common/Utils.brs`; new ones are `categoryId` and `listKind` (`vod`/`series`) for category and See-all cards; `kind` is also `category` or `seeAll` |
| Scene actions | `signedIn`, `signOut`, `openDetails`, `play`, `close` (with `helperStop`, the helper's stop address, after a helper stream), `openSearch`, `openSubtitleSetup`, **`openCategory`** `{ kind, categoryId, title }`, **`openCategories`** `{ lists: { vod, series, langs } }`, **`syncNow`**, **`syncSoon`** |

## 13. Lessons and gotchas

### For any port
- **Providers are inconsistent:**
  - numbers come as strings, empty objects as `[]`;
  - `episodes` is a plain array when season keys are sequential;
  - the TMDB id is `tmdb` or `tmdb_id`;
  - `backdrop_path` is a list;
  - codecs may describe the poster image (7).
- **Providers retire addresses.** A 403 or 404 at sign-in is often a dead address; trial addresses change often.
- **Bursts get you blocked** (section 3). Count requests per minute, not just requests in flight.
- **Cloudflare headers are on every answer** from a proxied site (2.3).
- **Test with real category names.** The first classifier guessed at naming patterns; the real lists showed `CA` meant Québec, `EN ◉ TURKISH` meant English, and a `GUJARTI` typo.
- **Keep the user's choices honest.** When behavior changes from what they picked (search covering only their languages), say so plainly.
- **Credentials:** never in git (both repos are public), never in logs; mask passwords in any on-screen URL; scan diffs for hosts and usernames before pushing.

### Roku-only
- **Reserved words** can't be variable names: `step`, `dim`, `pos`, `tab`, `run`, `box`.
- **Locals can't share a function's name.**
- **Names ignore case:** `helperAudio()` in a screen clashes with `HelperAudio()` in a shared file, and a parameter named `helperOn` shadows `HelperOn()`. `npm run lint` catches both.
- Comparing `invalid` with a Boolean can fail; guard with `<> invalid and …`.
- `roAssociativeArray.SortBy` needs lower-case keys in the test interpreter.
- **Large integers:** use Doubles (`10000000#`) for packed sort keys.
- **Focus:**
  - Focusing an ancestor of a RowList leaves the RowList taking keys; use an empty sibling Group as the focus holder.
  - Never take focus from an open keyboard dialog.
- The `brs` test interpreter has `tmp:` but not `cachefs:`, and throws on reading a missing `tmp:` file.
- **Animations find their nodes by id** (`fieldToInterp` "id.field"), searched within the component, so ids must be unique there. `Tween` names nodes without one; MainScene never reuses a screen id, so a late animation can't land on a new screen.
- **No `Min` or `Max`** in BrightScript; `Abs`, `Sqr` and `Exp` exist.
- **Some objects only exist on the main thread and in tasks:** `roFileSystem`, `roUrlTransfer`, sockets, `roChannelStore`. Made on the render thread (screens, items, the scene, and the shared files they include) they come back invalid and the next call crashes the app; a sideloaded app then sits frozen in the debugger. 0.5.7 to 0.5.9 did this with `roFileSystem` on Home. `tools/test.sh` checks for it. `ReadAsciiFile`, `DeleteFile` and the registry are fine on the render thread.
- **Tasks hand screens plain data where they can:** Home makes its picked rows from lists of fields the library worker sends.
- **Springs:** `easeFunction` has no overshoot, so springs are many keys (the web app's `linear()` lists, `SpringCurve` and `JellyCurve`) with `easeFunction="linear"`.

## 14. Samsung port checklist
Suggested order, most useful first:

1. **Search ranking:** remove `MATCH_CAP`; rank every match per kind; one- or two-letter word starts; latest-query collapse. Port the 2,500-movie test.
2. **Category classification, language preferences, tidy titles** (`Categories.brs`, `SplitTitle`). Port the tests that use the real category names, and set the user's languages to English, Hindi and Punjabi.
3. **Home order:** new releases first, then movies and series taking turns, with languages taking turns, up to 18 rows. Don't demote 4K on the Q60.
4. **Stored library:** save, load at any age, refresh in the background daily, swap when complete. Store category IDs, dates added and years, and category counts. Index only wanted languages.
5. **Categories tab, See all tiles and category page with search inside.**
6. **Categories row in search results.**
7. **Continue Watching removal and sync** (§9.3, §9.4): a menu on the poster (Samsung has no `*` key, so use a long-press of OK, or a button on the hero), plus the details button.
8. **Left/Right season switching** in the episode list.
9. **Refusal explanations** (`HttpDetail` wording, address line, hints) and the stop-after-refusal rules on Home.
10. **Built-in personal login** with the switch-on-change stamp.
11. **Picture codecs ignored; audio format labels and unplayable-track swap.**
12. **Sharp look:** 3 to 5 px corners, posters 10 px apart, badges on the poster, 6% focus lift. At 1080p, multiply Roku sizes by 1.5.
13. **Motion, glass, sounds and intro** (§10): the web app already has the glass, motion and intro (CSS and Web Audio) to port from; add the click sounds and the Account menu switches too.
14. **Picked for you, ratings and My List** (§5.1.1, §5.1.2): the watch history, ratings, category likings, Top picks and Because you watched rows, the row order, and My List. Sharing the history through the sync service would let every device learn from all of them.

The helper on a computer at home (§15) needs no port: Samsung has it, and the Roku came second.

## 15. The helper on a computer at home
New in 0.5.0; since 0.5.2 for the helper on the Samsung repo's default branch (helper 1.2, which also serves the iPhone app). The helper is a small Node program in the Samsung repo (`helper/aranplus-helper.mjs`) that runs on a Windows computer at home and uses FFmpeg to convert what a TV can't play, while you watch. The Samsung TV takes it as one MPEG-TS stream (`/v1/stream`); Roku plays no endless MPEG-TS, so the Roku takes HLS (`/v1/hls/start`). The plan this followed is the Samsung repo's `docs/roku-helper-plan.md`.

### 15.1 Setup
- The helper reads the provider login from its own `personal.json` and, on its first run, writes `"transcoder": { "url": "http://<this computer>:8090", "key": "<random>" }` there.
- The user copies that `transcoder` into the Roku's git-ignored `src/source/account.json`, by hand or with `npm run helper-settings` (`tools/helper-settings.mjs`), which keeps the rest of the file. `TranscoderSettings(data)` (Utils.brs) reads it, without a trailing `/`; `TranscoderConfig()` and `HelperOn()` (Registry.brs) read the file once per component.
- **Without `transcoder`, everything behaves as before.**

### 15.2 When a title goes through the helper
`HelperRoute(check, state, setUp, tried)` decides (Helper.brs, tested). Only with a helper set up, and only once per title (`tried`):

| When | `state` | Where |
|---|---|---|
| `PlaybackCheck` blocks it: an AVI container, or a picture codec this Roku can't decode (HEVC on most Roku TVs) | (`check.blocked`) | `startItem`, before anything plays |
| It's on the remembered list (registry `helper/titles`, keys `m:<id>` / `e:<id>`) | `listed` | `startItem` |
| The direct stream failed after its retry, and the stream check didn't find the provider refusing it every way (a refused stream won't do better through the helper) | `failed`, `refused` | `directFailed` |
| The audio rescue (§7) finds no sound track this Roku can play: the title is remembered, and the stream moves to the helper from where it got to | `silent` | `checkAudioPlayable` |

With a helper set up, "Won't play" is never shown: `containerProblem` (tasks) and `WontPlay(check)` (Compat.brs, for Home and Details) return nothing, `showUnplayable` isn't reached, and Details says "This TV can't play this file itself, so the helper on your computer converts it while you watch." ("Roku" on a stick, `DeviceWord`).

### 15.3 What the Roku asks for
Three requests, in order, through `HelperTask` (each answer is dropped if the title has changed since):

1. `GET /v1/info?key&kind&id&ext`: `{ duration, video { codec, width, height }, audio [{ codec, channels, language, title, plan }], videoPlan }` (`ParseHelperInfo`). Once per title; the helper keeps it for 6 hours.
2. With online subtitles set up, `GET /v1/hash?key&kind&id&ext`: `{ hash, size }`, the file's OpenSubtitles fingerprint (`ParseHelperHash`). Once per title, and before the stream, since the helper stops its FFmpeg to read it. Without it the search goes on by title.
3. `GET /v1/hls/start?key&kind&id&ext&start&vod=1&format=ts&video&height[&hevc=0][&a=<n>]` (`HelperStartUrl`), answered once the first piece is ready (up to a minute; the task waits 100 s): `{ session, url, vod, start, from, duration, video, audioTrack, audioPlan, previews, ... }` (`ParseHelperStart`).
   - `start`: the resume point (5 s early, as for direct play), the jump target, or where the stream got to.
   - `video`: `copy` only when the helper's plan is `copy` (H.264, HEVC, MPEG-2) and `CanDecodeVideo` says yes; otherwise `convert`. `hevc=0` when this Roku can't decode HEVC.
   - `height`: the screen's height (`GetDisplaySize().h`), 720 if unknown, at most 1080 (`HelperHeight`).
   - `a`: the sound track in the language of `prefs/player.audio` (`HelperTrack`, matched through `LanguageName`, so `en` finds `eng`), or the one picked in the Audio column. The stream carries that one track.

**The whole film's playlist** (`vod: true`, every file of known length with a picture): `url` is `/v1/hls/s/<session>/index.m3u8` on the helper, a VOD playlist listing the whole film in 6-second MPEG-TS pieces from 0, with `#EXT-X-START` at `from`. The helper makes each piece when Roku asks for it, from FFmpeg runs that keep the film's own timestamps, so the stream's clock is the film's (`start: 0`). The picture is always H.264 and the sound stereo AAC. The content node: that address, `streamFormat = "hls"`, `playStart = from`, no `HttpHeaders` (the helper speaks to the provider). The session's random name stands in for the key.

**A growing playlist** (`vod: false`: files of unknown length, or sound alone): the helper's older kind, from `start`, whose clock starts there (`start: <s>`).

**How the helper reads the provider:** FFmpeg reads the provider's files through the helper, which keeps the start and the end of each file (where its index is) and the provider's redirect, so a jump costs one request to the provider instead of four or five. Timed here against a fake provider taking 2 s per request: describing a file 2.2 s (1 request), its fingerprint 2.0 s (1), a start from 5:00 3.5 s, a jump forward or back 3.6 s (1).

### 15.4 Position, length and jumps
- `positionSecs()` is `m.offset` plus `m.video.position`: 0 plus Roku's for a whole film's playlist, the stream's start plus Roku's for a growing one. `durationSecs()` is the helper's `duration`. `onPosition`, `saveProgress`, `markFinished`, `renderBar`, the jump preview and `jumpBy` all use them.
- **Jumps** (`seekTo`): in a whole film's playlist, a plain `m.video.seek`; the helper makes the piece asked for (FFmpeg starts again there when it's far from where it was, a few seconds). In a growing one, a target inside what Roku has listed, with two pieces' margin (`HelperSeekInside`), is a plain seek; anything else starts the helper's stream again there.
- **Pictures while choosing a jump** (new in 0.5.6): in a whole film's playlist, the jump preview shows a picture of the target above the time bubble.
  - Where they come from: every FFmpeg run that makes pieces also writes a 180-line JPEG for each piece, from inside it. `/v1/hls/start` says where: `previews: { every: 6, prefix: "/v1/hls/s/<session>/p" }` (`parseHelperPreviews`; invalid from an older helper, or a prefix that isn't a path on the helper). The picture for `t` seconds is `prefix` + `floor(t / every)` in 5 digits + `.jpg` (`HelperPreviewUrl`), on the helper's address.
  - What exists: everything the helper has converted in this session, behind you and ahead as far as FFmpeg has got (it isn't held back, so it runs to the end at whatever pace the provider and the computer allow). A picture not made yet is a quick 404: the helper never asks the provider for one, since the provider's one connection is playing the film.
  - On screen: a 256x144 picture in a dark card with the lavender ring, over the knob, kept between x 48 and 1232, its bottom 10 px above the bubble. Wider films are letterboxed in it (`scaleToFit`, decoded at 256x144 to keep textures small).
  - Loading: one picture at a time, each into a fresh `Poster` (so its `loadStatus` can only be about that picture), observed and also checked at once in case Roku still holds it. When it's ready it replaces the one showing; until then the last picture stays up. A 404 (`failed`) or a load over 4 s hides the picture for that piece and isn't asked for again for 10 s. Holding Left/Right steps every 250 ms, which paces the requests; the picture for the final target loads during the 0.8 s before the jump.
  - Gone when the preview ends (jump, Back, a panel), and forgotten with each new stream (another session's pictures are another film's or another sound track's). Direct streams and growing playlists have none: just the time, as before.
  - Code: `renderThumb`, `loadThumb`, `thumbStatus`, `clearThumb` in `screens/PlayerScreen.brs`; `thumb` in `PlayerScreen.xml`. The web app (web-iptv-player, `renderPreview`) works the same way.
- **Sound tracks:** the Audio column lists the file's tracks from `/v1/info` (`HelperAudioOptions`); choosing another starts the stream again with it, from where you were, and saves the language (`chooseHelperTrack`).
- **To check on the device:** that Roku starts a whole film's playlist at `playStart`, and that its `position` there is the film's time (the pieces' timestamps are). For the pictures: that a `Poster` loads them from the helper's plain `http://` address, and that `loadStatus` reaches `ready` (or `failed` on a 404) for each fresh `Poster`, including one whose picture Roku already holds. If one never reports, the 4 s limit moves on.

### 15.5 Errors and the end
- A helper stream that fails after it played starts again from where it got to (or the jump target), twice at most (a minute of playing resets the count). One that never played is asked for once more.
- A "finished" more than 60 s before the helper's duration (`HelperEndedEarly`) isn't the end: the stream stopped short, and is started again from that point.
- Then the error screen: Roku's error, "Your computer says: …" from `/v1/last-error`, whether the title went to the helper from the start or after failing, what the helper was doing (`HelperPlanLine`: "Through the helper on your computer: picture converted to H.264, DTS sound converted to AAC."), the file, and the helper's address. The key is masked.
- When the helper doesn't answer: "The helper on your computer didn't answer. Is the computer on, with the helper running?", its address, and the usual causes (asleep or off, window closed, address changed). A 401 says the key doesn't match; a 404 that the helper may be older than the app (`HelperFailure`).
- The identity checks of §7 (`startProbe`) are about the provider, so they're skipped for helper streams.

### 15.6 One connection, and leaving
- The provider allows one connection, and the helper holds it while FFmpeg runs. So leaving a helper video sends `/v1/stop?session=<id>`, which stops that session only (the scene does it from the `close` action's `helperStop`), and a direct stream after a helper one sends it too, then waits 1.2 s before asking the provider. Moving a playing direct stream to the helper stops it and waits 1.2 s too.
- The helper keeps the newest session for 3 hours of not being asked for (long pauses), older ones for 2 minutes, and deletes everything when it starts.
- The Samsung TV, the iPhone and the Roku can't watch at once through the provider's one connection: the newer request stops the older one.

### 15.7 Subtitles
- Built-in subtitle tracks don't come through to the Roku. (The helper can write them out as WebVTT, `subs=1`, but those files grow as FFmpeg goes, and Roku reads a side-loaded file once, when the stream loads.)
- **Online subtitles** do. A whole film's playlist runs on the film's clock, so OpenSubtitles' file plays as it is, from any point. A growing playlist that starts partway has its own clock, so it gets none (`onlineTrackName` is "").
- **The fingerprint:** for helper titles the subtitle search uses the helper's (`/v1/hash`) and reads nothing from the provider itself (`via: "helper"` in the `SubtitleTask` request). Played straight from the provider there's none since 0.5.15: reading the file's start and end took the provider's one connection away from the video.

### 15.8 Code
- `common/Helper.brs`: addresses, `HelperRoute`, the choices, `HelperAudioOptions`, `ParseHelperInfo`, `ParseHelperStart`, `HelperPreviewUrl`, `ParseHelperHash`, `HelperFailure`, `HelperPlanLine`, the remembered titles (tested in `tests/utils_test.brs` and `tests/parse_test.brs`).
- `tasks/HelperTask.*`: the requests (`info` and `hash` 50 s, `start` 100 s, `lastError` 8 s, `stop` 4 s).
- `screens/PlayerScreen.brs`: the route, `startHelper`, `helperGo`, `requestStart`, `openHelper`, `positionSecs`, `durationSecs`, `seekTo`, `renderThumb` and the rest of the preview pictures, `chooseHelperTrack`, `helperFailed`, `helperDiagnosis`.
- The helper itself: the Samsung repo's `helper/` and its README section.
