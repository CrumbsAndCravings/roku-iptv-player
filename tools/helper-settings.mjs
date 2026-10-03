// Copies the helper's address and key ("transcoder") from the Samsung repo's
// personal.json, where the helper wrote them the first time it ran, into this app's
// src/source/account.json. Everything else in account.json stays as it is.
//
//   npm run helper-settings                    (the Samsung repo sits next to this one)
//   npm run helper-settings -- <the Samsung repo's folder, or its personal.json>
//
// account.json is git-ignored, and the key is never printed.

import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const target = path.join(root, "src", "source", "account.json");

function fail(message) {
  console.error("\n" + message + "\n");
  process.exit(1);
}

function readJson(file) {
  try {
    return JSON.parse(readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
  } catch (err) {
    return fail(`${file} isn't valid JSON: ${err.message}`);
  }
}

// The Samsung repo's personal.json: the one named, or next to this repo.
function findPersonal(named) {
  const candidates = named ? [named] : ["Samsung-IPTV-Player", "samsung-iptv-player"].map((name) => path.join(root, "..", name));
  for (const candidate of candidates) {
    const file = existsSync(candidate) && statSync(candidate).isDirectory() ? path.join(candidate, "personal.json") : candidate;
    if (existsSync(file)) return file;
  }
  return "";
}

const source = findPersonal(process.argv[2]);
if (!source) {
  fail(
    "Couldn't find the Samsung repo's personal.json.\n" +
      "Name it:   npm run helper-settings -- C:\\path\\to\\Samsung-IPTV-Player",
  );
}
const transcoder = readJson(source).transcoder;
const url = transcoder ? String(transcoder.url || "").trim() : "";
const key = transcoder ? String(transcoder.key || "").trim() : "";
if (!url || !key) {
  fail(`${source} has no "transcoder" yet. Start the helper once (npm run helper in the Samsung repo); it writes it there.`);
}

const account = existsSync(target) ? readJson(target) : {};
if (!account || typeof account !== "object" || Array.isArray(account)) fail(`${target} should hold a JSON object.`);
const same = account.transcoder && account.transcoder.url === url && account.transcoder.key === key;
account.transcoder = { url, key };
writeFileSync(target, JSON.stringify(account, null, 2) + "\n");

console.log("");
console.log(same ? "account.json already had the helper's settings." : "Copied the helper's settings into src/source/account.json.");
console.log(`  The Roku reaches the helper at ${url}`);
console.log("  Build and install the app again (npm run build, then upload the zip, or npm run deploy).");
console.log("");
