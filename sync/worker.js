// ARAN+ sync: one small Cloudflare Worker that keeps Continue Watching in step between
// the Roku, the Samsung TV and the iPhone, and keeps the online subtitles downloaded for
// a title, so every device shows them without downloading them again.
//
// Storage: one KV value per provider login ("progress:<space>") in the namespace bound
// as ARANPLUS, and one per title with saved subtitles ("subs:<space>:<title>"). `space` is the first 16 hex digits of SHA-256 of the login (see
// SyncSpaceText in the Roku app), so every device signed in to the same provider
// account shares one list, and a different provider never mixes in.
// Security: every request needs "Authorization: Bearer <SYNC_KEY>", a secret set in
// the Worker's settings and built into your personal app builds.
//
//   GET  /v1/progress?space=<space>  ->  { entries, removed, at }
//   POST /v1/progress?space=<space>  with { entries, removed }  ->  the merged state
//   GET  /v1/subtitles?space=<space>&k=<title>  ->  the title's saved subtitles (below)
//   POST /v1/subtitles?space=<space>&k=<title>  with { fileId, name, delayMs, text }
//        saves them (from OpenSubtitles, on any device); without text, it only changes
//        delayMs of the ones saved (a nudge earlier or later)
//   GET  /v1/subtitles/file?space=<space>&k=<title>&t=<token>[&delay=<ms>]
//        the file itself, moved `delay` ms later (or earlier); no key needed, the token
//        is the file's own (for the Roku, whose player fetches subtitles by address)
//
// entries  Continue Watching entries as the apps store them; each has a key `k`
//          ("m:<streamId>" or "s:<seriesId>") and `at`, when it last changed (seconds).
// removed  [{ k, at }] titles taken off Continue Watching, so a removal on one device
//          isn't undone by another device's older copy.
//
// For each title the newest change wins, whether that's an entry or a removal. The
// server keeps the 50 newest entries and 30 days of removals.
//
// Subtitles: one file per title (`title` is "m:<streamId>" or "e:<episodeId>", as the
// apps key a playable title); saving another replaces it. The answer to a GET is
// { found, fileId, name, delayMs, at, file, text }: `file` is the address of the file
// above, `text` the file (left out with &text=0). Kept a year after they were last saved.

const MAX_ENTRIES = 50;
const MAX_REMOVED = 300;
const REMOVED_DAYS = 30;
const SUBS_MAX_CHARS = 3 * 1024 * 1024;
const SUBS_KEEP_SECONDS = 365 * 86400;
const MAX_DELAY_MS = 10 * 60000;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return withCors(new Response(null, { status: 204 }));
    const url = new URL(request.url);
    if (url.pathname === "/") return withCors(json({ ok: true, service: "aranplus-sync" }));
    if (!env.SYNC_KEY) return withCors(json({ error: "SYNC_KEY isn't set in the Worker's settings." }, 500));
    if (!env.ARANPLUS) return withCors(json({ error: "The KV namespace isn't bound as ARANPLUS." }, 500));
    // Its own token instead of the key.
    if (url.pathname === "/v1/subtitles/file") return withCors(await subtitleFile(env, url));
    const given = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!sameText(given, env.SYNC_KEY)) return withCors(json({ error: "Wrong or missing key." }, 401));
    if (url.pathname === "/v1/subtitles") return withCors(await subtitles(request, env, url));

    if (url.pathname === "/v1/progress") {
      const space = url.searchParams.get("space") || "";
      if (!/^[a-z0-9]{8,64}$/.test(space)) return withCors(json({ error: "Missing or odd ?space=." }, 400));
      const slot = "progress:" + space;
      if (request.method === "GET") return withCors(json(await load(env, slot)));
      if (request.method === "POST") {
        let body;
        try {
          body = await request.json();
        } catch {
          return withCors(json({ error: "The body isn't JSON." }, 400));
        }
        const merged = merge(await load(env, slot), body, nowSeconds());
        await env.ARANPLUS.put(slot, JSON.stringify(merged));
        return withCors(json(merged));
      }
    }
    return withCors(json({ error: "Not found." }, 404));
  },
};

// --- Subtitles ---------------------------------------------------------------------------

function subtitleSlot(url) {
  const space = url.searchParams.get("space") || "";
  const title = url.searchParams.get("k") || "";
  if (!/^[a-z0-9]{8,64}$/.test(space) || !/^[me]:[0-9A-Za-z_-]{1,40}$/.test(title)) return "";
  return "subs:" + space + ":" + title;
}

async function loadSubtitle(env, slot) {
  const raw = await env.ARANPLUS.get(slot);
  if (!raw) return null;
  try {
    const saved = JSON.parse(raw);
    return saved && typeof saved.text === "string" && typeof saved.token === "string" ? saved : null;
  } catch {
    return null;
  }
}

function describe(saved, url, withText) {
  const file = new URL("/v1/subtitles/file", url);
  file.searchParams.set("space", url.searchParams.get("space"));
  file.searchParams.set("k", url.searchParams.get("k"));
  file.searchParams.set("t", saved.token);
  const answer = { found: true, fileId: saved.fileId, name: saved.name, delayMs: saved.delayMs, at: saved.at, file: file.toString() };
  if (withText) answer.text = saved.text;
  return answer;
}

async function subtitles(request, env, url) {
  const slot = subtitleSlot(url);
  if (!slot) return json({ error: "Missing or odd ?space= or ?k=." }, 400);
  const saved = await loadSubtitle(env, slot);
  if (request.method === "GET") return json(saved ? describe(saved, url, url.searchParams.get("text") !== "0") : { found: false });
  if (request.method !== "POST") return json({ error: "Not found." }, 404);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "The body isn't JSON." }, 400);
  }
  if (!body || typeof body !== "object") return json({ error: "The body isn't JSON." }, 400);
  const fileId = String(body.fileId ?? "");
  const delayMs = Math.max(-MAX_DELAY_MS, Math.min(MAX_DELAY_MS, Math.round(Number(body.delayMs) || 0)));
  if (!/^[0-9A-Za-z_-]{1,40}$/.test(fileId)) return json({ error: "Missing or odd fileId." }, 400);
  let next;
  if (body.text === undefined) {
    // A nudge: only for the file saved.
    if (!saved || saved.fileId !== fileId) return json({ error: "Those subtitles aren't saved." }, 404);
    next = { ...saved, delayMs, at: nowSeconds() };
  } else {
    if (typeof body.text !== "string" || body.text.trim() === "" || body.text.length > SUBS_MAX_CHARS) return json({ error: "The subtitle file is empty or too big." }, 400);
    const name = String(body.name ?? "").slice(0, 200);
    next = { fileId, name, delayMs, at: nowSeconds(), token: randomToken(), text: body.text };
  }
  await env.ARANPLUS.put(slot, JSON.stringify(next), { expirationTtl: SUBS_KEEP_SECONDS });
  return json(describe(next, url, false));
}

async function subtitleFile(env, url) {
  const slot = subtitleSlot(url);
  const saved = slot ? await loadSubtitle(env, slot) : null;
  if (!saved || !sameText(url.searchParams.get("t") || "", saved.token)) return json({ error: "No such subtitles." }, 404);
  const delay = Math.max(-MAX_DELAY_MS, Math.min(MAX_DELAY_MS, Math.round(Number(url.searchParams.get("delay")) || 0)));
  return new Response(delay ? moveCues(saved.text, delay) : saved.text, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
}

// Every cue time in an SRT or WebVTT file, `ms` later (earlier when negative, never
// before 0). Only the "start --> end" lines change.
export function moveCues(text, ms) {
  const time = /(?:(\d{1,2}):)?(\d{1,2}):(\d{2})([,.])(\d{3})/g;
  return text
    .split("\n")
    .map((line) => {
      if (line.indexOf("-->") < 0) return line;
      return line.replace(time, (all, h, m, s, mark, frac) => {
        const t = Math.max(0, ((Number(h || 0) * 60 + Number(m)) * 60 + Number(s)) * 1000 + Number(frac) + ms);
        const pad = (n, w) => String(n).padStart(w, "0");
        const hours = Math.floor(t / 3600000);
        return (h !== undefined || hours > 0 ? pad(hours, 2) + ":" : "") + pad(Math.floor(t / 60000) % 60, 2) + ":" + pad(Math.floor(t / 1000) % 60, 2) + mark + pad(t % 1000, 3);
      });
    })
    .join("\n");
}

function randomToken() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// --- Continue Watching ------------------------------------------------------------------

async function load(env, slot) {
  const raw = await env.ARANPLUS.get(slot);
  if (!raw) return { entries: [], removed: [], at: 0 };
  try {
    const state = JSON.parse(raw);
    return { entries: list(state.entries), removed: list(state.removed), at: Number(state.at) || 0 };
  } catch {
    return { entries: [], removed: [], at: 0 };
  }
}

// Newest change per title wins; removals win ties, so a remove can't be lost.
export function merge(state, incoming, now) {
  const entries = new Map();
  const removed = new Map();
  for (const source of [state, incoming || {}]) {
    for (const entry of list(source.entries)) {
      if (!valid(entry)) continue;
      const known = entries.get(entry.k);
      if (!known || Number(entry.at) > Number(known.at)) entries.set(entry.k, entry);
    }
    for (const gone of list(source.removed)) {
      if (!valid(gone)) continue;
      const known = removed.get(gone.k);
      if (!known || Number(gone.at) > Number(known.at)) removed.set(gone.k, { k: gone.k, at: Number(gone.at) });
    }
  }
  for (const [k, gone] of removed) {
    const entry = entries.get(k);
    if (entry && Number(entry.at) <= gone.at) entries.delete(k);
  }
  const keepSince = now - REMOVED_DAYS * 86400;
  return {
    entries: [...entries.values()].sort((a, b) => Number(b.at) - Number(a.at)).slice(0, MAX_ENTRIES),
    removed: [...removed.values()].filter((gone) => gone.at >= keepSince).sort((a, b) => b.at - a.at).slice(0, MAX_REMOVED),
    at: now,
  };
}

function valid(item) {
  return item && typeof item === "object" && typeof item.k === "string" && item.k !== "" && Number.isFinite(Number(item.at));
}

function list(value) {
  return Array.isArray(value) ? value : [];
}

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

// Compares in constant time, so the key can't be guessed from response times.
function sameText(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}

// Lets a web app (the iPhone one, later) call the service from a browser.
function withCors(response) {
  response.headers.set("Access-Control-Allow-Origin", "*");
  response.headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  response.headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  return response;
}
