// Off-device tests for the sync Worker (sync/worker.js), run with Node.
import worker, { merge, moveCues } from "../sync/worker.js";

let failures = 0;
let count = 0;
function check(name, actual, expected) {
  count++;
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    failures++;
    console.log(`FAIL ${name}: expected ${e} got ${a}`);
  }
}

// Merging
const now = 2000000000;
let m = merge({ entries: [{ k: "m:1", at: 10, pos: 100 }], removed: [] }, { entries: [{ k: "m:1", at: 20, pos: 900 }] }, now);
check("newer entry wins", m.entries[0].pos, 900);
m = merge({ entries: [{ k: "m:1", at: 30, pos: 100 }], removed: [] }, { entries: [{ k: "m:1", at: 20, pos: 900 }] }, now);
check("older entry loses", m.entries[0].pos, 100);
m = merge({ entries: [{ k: "m:1", at: 10 }], removed: [] }, { removed: [{ k: "m:1", at: 15 }] }, now);
check("removal after the entry removes it", m.entries.length, 0);
m = merge({ entries: [{ k: "m:1", at: 20 }], removed: [] }, { removed: [{ k: "m:1", at: 15 }] }, now);
check("entry after the removal stays", m.entries.length, 1);
m = merge({ entries: [], removed: [{ k: "m:1", at: 15 }] }, { entries: [{ k: "m:1", at: 15 }] }, now);
check("removal wins a tie", m.entries.length, 0);
m = merge({ entries: [{ k: "m:1", at: 5 }, { k: "s:2", at: 50 }], removed: [] }, {}, now);
check("newest first", m.entries.map((e) => e.k), ["s:2", "m:1"]);
const many = [];
for (let i = 0; i < 70; i++) many.push({ k: "m:" + i, at: i });
check("keeps 50", merge({ entries: [], removed: [] }, { entries: many }, now).entries.length, 50);
m = merge({ entries: [], removed: [{ k: "m:old", at: now - 31 * 86400 }, { k: "m:new", at: now - 86400 }] }, {}, now);
check("old removals forgotten", m.removed.map((g) => g.k), ["m:new"]);
check("junk ignored", merge({ entries: [{ at: 1 }, null, "x"], removed: [] }, { entries: [{ k: "", at: 1 }] }, now).entries.length, 0);

// The Worker over HTTP, with an in-memory KV
const store = new Map();
const env = { SYNC_KEY: "secret-key", ARANPLUS: { get: async (k) => store.get(k) ?? null, put: async (k, v) => void store.set(k, v) } };
const call = (method, body, key = "secret-key") =>
  worker.fetch(new Request("https://sync.example/v1/progress?space=abc123def4567890", { method, headers: { Authorization: "Bearer " + key, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined }), env);

let res2;
let res = await call("GET", undefined, "wrong");
check("wrong key refused", res.status, 401);
res = await call("GET");
check("empty to start", (await res.json()).entries, []);
const t = Math.floor(Date.now() / 1000);
res = await call("POST", { entries: [{ k: "m:7", at: t - 100, pos: 60 }], removed: [] });
check("post merges", (await res.json()).entries[0].k, "m:7");
res = await call("POST", { entries: [], removed: [{ k: "m:7", at: t - 50 }] });
check("removal syncs", (await res.json()).entries.length, 0);
res = await call("GET");
check("stored", (await res.json()).removed[0].k, "m:7");
res = await worker.fetch(new Request("https://sync.example/v1/progress?space=abc123def4567890", { method: "POST", headers: { Authorization: "Bearer secret-key" }, body: "not json" }), env);
check("bad body", res.status, 400);
res = await worker.fetch(new Request("https://sync.example/v1/progress?space=abc123def4567890", { method: "OPTIONS" }), env);
res2 = await worker.fetch(new Request("https://sync.example/v1/progress", { headers: { Authorization: "Bearer secret-key" } }), env);
check("space required", res2.status, 400);
res2 = await worker.fetch(new Request("https://sync.example/v1/progress?space=0000aaaa1111bbbb", { headers: { Authorization: "Bearer secret-key" } }), env);
check("spaces kept apart", (await res2.json()).removed, []);
check("cors preflight", res.headers.get("Access-Control-Allow-Origin"), "*");
res = await worker.fetch(new Request("https://sync.example/v1/progress"), { ARANPLUS: env.ARANPLUS });
check("missing secret explained", res.status, 500);

// Saved subtitles
const SPACE = "abc123def4567890";
const subs = (method, query, body, key = "secret-key") =>
  worker.fetch(new Request("https://sync.example/v1/subtitles?space=" + SPACE + query, { method, headers: { Authorization: "Bearer " + key, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined }), env);
const SRT = "1\n00:00:01,000 --> 00:00:02,500\nHello\n";
res = await subs("GET", "&k=m:7", undefined, "wrong");
check("subtitles need the key", res.status, 401);
res = await subs("GET", "&k=m:7");
check("none saved to start", await res.json(), { found: false });
res = await subs("GET", "&k=x:7");
check("odd title refused", res.status, 400);
res = await subs("POST", "&k=e:42", { fileId: "9001", name: "Show.S01E02.WEB", delayMs: 0, text: SRT });
const saved = await res.json();
check("saved", [res.status, saved.fileId, saved.name, saved.delayMs, "text" in saved], [200, "9001", "Show.S01E02.WEB", 0, false]);
res = await subs("GET", "&k=e:42");
let got = await res.json();
check("another device gets them", [got.found, got.fileId, got.text], [true, "9001", SRT]);
check("with the file's address", got.file.startsWith("https://sync.example/v1/subtitles/file?space=" + SPACE + "&k=e%3A42&t="), true);
res = await subs("GET", "&k=e:42&text=0");
check("text left out when asked", "text" in (await res.json()), false);
res = await worker.fetch(new Request(got.file), env);
check("file without the key", [res.status, await res.text()], [200, SRT]);
res = await worker.fetch(new Request(got.file + "&delay=1500"), env);
check("file moved later", (await res.text()).split("\n")[1], "00:00:02,500 --> 00:00:04,000");
res = await worker.fetch(new Request(got.file.replace(/t=[0-9a-f]+/, "t=" + "0".repeat(32))), env);
check("wrong token refused", res.status, 404);
res = await subs("POST", "&k=e:42", { fileId: "9001", delayMs: -1000 });
check("nudge saved", (await res.json()).delayMs, -1000);
res = await subs("GET", "&k=e:42");
got = await res.json();
check("nudge kept the file", [got.delayMs, got.text], [-1000, SRT]);
res = await subs("POST", "&k=e:42", { fileId: "1234", delayMs: 500 });
check("nudge for other subtitles refused", res.status, 404);
res = await subs("POST", "&k=e:42", { fileId: "9002", name: "Other", delayMs: 0, text: "" });
check("empty file refused", res.status, 400);
res = await subs("POST", "&k=e:42", { fileId: "9002", name: "Other", text: "x".repeat(3 * 1024 * 1024 + 1) });
check("huge file refused", res.status, 400);
res = await subs("POST", "&k=e:42", { fileId: "9002", name: "Better.Match", text: SRT + "\n2\n00:00:03,000 --> 00:00:04,000\nAgain\n" });
check("new choice replaces", (await res.json()).fileId, "9002");
res = await worker.fetch(new Request(got.file), env);
check("old address stops working", res.status, 404);
res = await subs("GET", "&k=m:42");
check("titles kept apart", (await res.json()).found, false);
check("move cues earlier stops at 0", moveCues("00:00:01,000 --> 00:00:02,000", -1500), "00:00:00,000 --> 00:00:00,500");
check("move cues past an hour", moveCues("00:59:59,500 --> 01:00:00,000", 1000), "01:00:00,500 --> 01:00:01,000");
check("move webvtt cues", moveCues("WEBVTT\n\n00:01.000 --> 00:02.000", 250), "WEBVTT\n\n00:01.250 --> 00:02.250");
check("text lines untouched", moveCues("Meet at 10:00:00,000 sharp", 1000), "Meet at 10:00:00,000 sharp");

if (failures === 0) {
  console.log(`ALL PASSED (${count} checks)`);
} else {
  console.log(`FAILED: ${failures} of ${count} checks`);
  process.exit(1);
}
