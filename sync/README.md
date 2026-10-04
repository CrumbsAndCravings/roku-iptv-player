# ARAN+ sync

A tiny Cloudflare Worker that keeps **Continue Watching** in step between your devices
(the Roku, the Samsung TV and the iPhone), and keeps the **online subtitles** downloaded
for a title, so every device shows them without downloading them again. Code: [`worker.js`](worker.js),
tests: [`../tests/sync_test.mjs`](../tests/sync_test.mjs). It runs on Cloudflare's
free plan.

## How it works

- Each device sends its Continue Watching list and any titles you removed, and gets
  back the merged list from every device. For each title the newest change wins;
  a removal beats an equally new entry, so a removed title doesn't come back.
- One list per provider login (`?space=` is 16 hex digits of SHA-256 of the login,
  see `SyncSpaceText` in `src/components/common/Utils.brs`), so devices on the same
  account share one list and a different provider never mixes in.
- Every request needs `Authorization: Bearer <SYNC_KEY>`. The key lives in the
  Worker's settings and in your personal app builds (`src/source/account.json`,
  which git ignores). Never commit it.
- The Roku syncs at launch and sign-in, when you leave a video, every 5 minutes
  while one plays, after you remove a title, and when Home comes back (at most once a
  minute). That's a few dozen writes on a busy day; the free plan allows 1,000.

- Online subtitles: when a device downloads subtitles from OpenSubtitles, it saves them
  here for that movie or episode (one file per title; choosing others replaces it,
  and moving them earlier or later is saved too). The next device to play that title
  shows them straight away, without a download from your OpenSubtitles allowance.

## Update it

When `worker.js` changes (saved subtitles came in October 2026), open the
`aranplus-sync` Worker, press **Edit code**, replace everything with the new
[`worker.js`](worker.js) and press **Deploy**. The storage, key and address stay as
they are, and so does everything already synced.

## Set it up (about 10 minutes, once)

1. **Make a free Cloudflare account** at https://dash.cloudflare.com/sign-up. When it
   asks for a workers.dev subdomain, pick any name; it becomes part of your
   service's address.
2. **Create the Worker.** Go to **Workers & Pages**, then **Create**. Skip **Import a
   repository** (it wants GitHub, which isn't needed) and pick **Start with Hello
   World!** instead. Name it `aranplus-sync` and press **Deploy**. Then press **Edit
   code**, replace everything with the contents of [`worker.js`](worker.js) (open
   it on GitHub and press **Raw** to copy it cleanly), and press **Deploy** again.
3. **Create the storage.** Go to **Storage & Databases**, then **KV**, then
   **Create**. Name it `aranplus`.
4. **Connect the storage to the Worker.** Open the `aranplus-sync` Worker, then
   **Settings**, then **Bindings**, then **Add**, then **KV namespace**. Variable
   name: `ARANPLUS` (exactly). Namespace: `aranplus`. Save or deploy.
5. **Add the key.** Still in the Worker's **Settings**, open **Variables and
   Secrets**, then **Add**. Type: **Secret**. Name: `SYNC_KEY`. Value: a long random
   password you make up (30+ characters; a password manager's "generate" button is
   ideal). Every app build needs the same key in its `account.json` under `sync.key`.
   Save or deploy.
6. **Check it.** Open `https://aranplus-sync.<your-subdomain>.workers.dev/` in a
   browser. It should say `{"ok":true,"service":"aranplus-sync"}`.
7. **Send the address** (not the key) so it can go into your personal builds as
   `sync.url`.

Cloudflare's dashboard moves things around now and then; if a button isn't where
these steps say, search the dashboard for "KV", "Bindings" or "Secrets".

## API

| Request | Body | Answer |
|---|---|---|
| `GET /` | | `{"ok":true,"service":"aranplus-sync"}` (no key needed) |
| `GET /v1/progress?space=<space>` | | `{ entries, removed, at }` |
| `POST /v1/progress?space=<space>` | `{ entries, removed }` | the merged `{ entries, removed, at }` |
| `GET /v1/subtitles?space=<space>&k=<title>` | | `{ found, fileId, name, delayMs, at, file, text }` (`text` left out with `&text=0`), or `{ "found": false }` |
| `POST /v1/subtitles?space=<space>&k=<title>` | `{ fileId, name, delayMs, text }` | saves them; without `text`, only changes `delayMs` of the ones saved |
| `GET /v1/subtitles/file?space=<space>&k=<title>&t=<token>&delay=<ms>` | | the file, moved `delay` ms later (earlier when negative); no key, the token from `file` instead |

`entries` are Continue Watching entries as the apps store them (key `k` like
`m:<streamId>` or `s:<seriesId>`, and `at`, when it changed, in seconds). `removed`
is `[{ k, at }]`. The server keeps the 50 newest entries and 30 days of removals.

Subtitles: `title` is `m:<streamId>` or `e:<episodeId>`. `delayMs` is how much later
than the file says to show them (negative is earlier). `file` is an address for the
file itself, for the Roku, whose player fetches subtitles by address and can't send
the key; its token changes whenever other subtitles are saved for the title. Saved
subtitles are kept for a year after they were last saved, up to 3 MB each.
Errors: 401 wrong key, 400 bad `space` or body, 500 when the key or storage isn't set
up (the message says which).
