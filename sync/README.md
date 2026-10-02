# ARAN+ sync

A tiny Cloudflare Worker that keeps **Continue Watching** in step between your devices
(the Roku, the Samsung TV, and later the iPhone). Code: [`worker.js`](worker.js),
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
   Secrets**, then **Add**. Type: **Secret**. Name: `SYNC_KEY`. Value: your key (you
   were given it privately; it's in your personal `account.json` under `sync.key`).
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

`entries` are Continue Watching entries as the apps store them (key `k` like
`m:<streamId>` or `s:<seriesId>`, and `at`, when it changed, in seconds). `removed`
is `[{ k, at }]`. The server keeps the 50 newest entries and 30 days of removals.
Errors: 401 wrong key, 400 bad `space` or body, 500 when the key or storage isn't set
up (the message says which).
