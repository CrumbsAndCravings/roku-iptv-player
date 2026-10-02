// ARAN+ sync: one small Cloudflare Worker that keeps Continue Watching in step between
// the Roku, the Samsung TV and the iPhone.
//
// Storage: one KV value per provider login ("progress:<space>") in the namespace bound
// as ARANPLUS. `space` is the first 16 hex digits of SHA-256 of the login (see
// SyncSpaceText in the Roku app), so every device signed in to the same provider
// account shares one list, and a different provider never mixes in.
// Security: every request needs "Authorization: Bearer <SYNC_KEY>", a secret set in
// the Worker's settings and built into your personal app builds.
//
//   GET  /v1/progress?space=<space>  ->  { entries, removed, at }
//   POST /v1/progress?space=<space>  with { entries, removed }  ->  the merged state
//
// entries  Continue Watching entries as the apps store them; each has a key `k`
//          ("m:<streamId>" or "s:<seriesId>") and `at`, when it last changed (seconds).
// removed  [{ k, at }] titles taken off Continue Watching, so a removal on one device
//          isn't undone by another device's older copy.
//
// For each title the newest change wins, whether that's an entry or a removal. The
// server keeps the 50 newest entries and 30 days of removals.

const MAX_ENTRIES = 50;
const MAX_REMOVED = 300;
const REMOVED_DAYS = 30;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return withCors(new Response(null, { status: 204 }));
    const url = new URL(request.url);
    if (url.pathname === "/") return withCors(json({ ok: true, service: "aranplus-sync" }));
    if (!env.SYNC_KEY) return withCors(json({ error: "SYNC_KEY isn't set in the Worker's settings." }, 500));
    if (!env.ARANPLUS) return withCors(json({ error: "The KV namespace isn't bound as ARANPLUS." }, 500));
    const given = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!sameText(given, env.SYNC_KEY)) return withCors(json({ error: "Wrong or missing key." }, 401));

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
