// Renders promo/index.html to a 1080x1920 MP4 with its soundtrack.
//   NODE_PATH="$(npm root -g)" node promo/render.cjs [out.mp4] [fps]
// Needs Playwright (with Chromium) and ffmpeg.
//   STILLS=1.5,6,12   renders PNGs at those times instead of the video
//   AUDIO_ONLY=1      only rebuilds promo/soundtrack.mp3
//   REMUX=1           rebuilds the soundtrack and swaps it into the existing MP4
//   WORKERS=3         browser pages rendering frames in parallel
const { chromium } = require("playwright");
const { spawn } = require("child_process");
const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { makeSoundtrack } = require("./soundtrack.cjs");

const out = path.resolve(process.argv[2] || path.join(__dirname, "aranplus-promo.mp4"));
const fps = Number(process.argv[3] || 30);
const workers = Number(process.env.WORKERS || Math.max(1, Math.min(4, os.cpus().length - 1)));

// Served over HTTP: browsers refuse CSS mask images (the glows and sparkles) on file:// pages.
const root = path.resolve(__dirname, "..");
const TYPES = { ".html": "text/html; charset=utf-8", ".png": "image/png", ".ttf": "font/ttf", ".mp3": "audio/mpeg", ".js": "text/javascript" };
const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(req.url.split("?")[0]));
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});
let pageUrl;

function run(args, { input, quiet } = {}) {
  return new Promise((res, rej) => {
    const p = spawn("ffmpeg", ["-hide_banner", "-y", ...args], { stdio: [input ? "pipe" : "ignore", "ignore", "pipe"] });
    let err = "";
    p.stderr.on("data", d => { err += d; if (!quiet) process.stderr.write(d); });
    p.on("close", c => (c === 0 ? res(err) : rej(new Error("ffmpeg exited " + c + "\n" + err.slice(-2000)))));
    if (input) input(p.stdin);
  });
}

async function openPage(browser) {
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
  await page.goto(pageUrl);
  await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
  return page;
}

async function soundtrack(sound) {
  const wav = path.join(os.tmpdir(), "aranplus-soundtrack.wav");
  const m4a = path.join(os.tmpdir(), "aranplus-soundtrack.m4a"), mp3 = path.join(__dirname, "soundtrack.mp3");
  // The voiceover comes from voiceover.py as FLAC; decode it to 48 kHz mono floats.
  let vo = null;
  const flac = path.join(__dirname, "voiceover.flac");
  if (fs.existsSync(flac)) {
    const raw = path.join(os.tmpdir(), "aranplus-vo.f32");
    await run(["-i", flac, "-f", "f32le", "-ac", "1", "-ar", "48000", raw], { quiet: true });
    const b = fs.readFileSync(raw);
    vo = new Float32Array(b.buffer, b.byteOffset, b.length / 4);
  }
  const info = makeSoundtrack(sound, wav, vo);
  console.log(`soundtrack: ${info.bpm.toFixed(1)} bpm, breakdown in bar ${info.bars.breakdown}`);
  // Two-pass loudness normalisation to -14 LUFS, -1.5 dBTP.
  const target = "I=-14:TP=-1.5:LRA=11";
  const log = await run(["-i", wav, "-af", `loudnorm=${target}:print_format=json`, "-f", "null", "-"], { quiet: true });
  const m = JSON.parse(log.slice(log.lastIndexOf("{"), log.lastIndexOf("}") + 1));
  const second = `loudnorm=${target}:measured_I=${m.input_i}:measured_TP=${m.input_tp}:measured_LRA=${m.input_lra}:measured_thresh=${m.input_thresh}:offset=${m.target_offset}:linear=true,aresample=48000`;
  await run(["-i", wav, "-af", second, "-c:a", "aac", "-b:a", "192k", m4a], { quiet: true });
  // MP3 for the page: every browser plays it, which isn't true of AAC.
  await run(["-i", m4a, "-c:a", "libmp3lame", "-b:a", "192k", mp3], { quiet: true });
  console.log(`soundtrack: ${m.input_i} LUFS before, normalised to -14 -> ${mp3}`);
  return m4a;
}

(async () => {
  await new Promise(r => server.listen(0, "127.0.0.1", r));
  pageUrl = `http://127.0.0.1:${server.address().port}/promo/index.html?render`;
  const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
  const first = await openPage(browser);

  if (process.env.STILLS) {
    for (const t of process.env.STILLS.split(",").map(Number)) {
      await first.evaluate(x => window.__seek(x), t);
      const file = out.replace(/\.mp4$/, "") + `-${t.toFixed(2)}.png`;
      await first.screenshot({ path: file });
      console.log(file);
    }
    await browser.close(); server.close();
    return;
  }

  const sound = await first.evaluate(() => window.__sound);
  const m4a = await soundtrack(sound);
  if (process.env.AUDIO_ONLY || process.env.REMUX) {
    await browser.close(); server.close();
    if (process.env.REMUX) {
      const tmpOut = out.replace(/\.mp4$/, ".remux.mp4");
      await run(["-i", out, "-i", m4a, "-map", "0:v", "-map", "1:a", "-c", "copy", "-movflags", "+faststart", "-t", String(sound.duration), tmpOut], { quiet: true });
      fs.renameSync(tmpOut, out);
      console.log("new soundtrack in " + out);
    }
    return;
  }

  const frames = Math.round(sound.duration * fps);
  const per = Math.ceil(frames / workers);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "aranplus-"));
  let done = 0;
  const segments = await Promise.all(Array.from({ length: workers }, async (_, w) => {
    const page = w === 0 ? first : await openPage(browser);
    const from = w * per, to = Math.min(frames, from + per);
    const seg = path.join(tmp, `seg${w}.mp4`);
    await run(["-f", "image2pipe", "-framerate", String(fps), "-c:v", "mjpeg", "-i", "-",
      "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-r", String(fps), seg], {
      quiet: true,
      input: async stdin => {
        for (let f = from; f < to; f++) {
          await page.evaluate(x => window.__seek(x), f / fps);
          const jpg = await page.screenshot({ type: "jpeg", quality: 95 });
          if (!stdin.write(jpg)) await new Promise(r => stdin.once("drain", r));
          if (++done % fps === 0) process.stdout.write(`\rframes ${done} / ${frames}`);
        }
        stdin.end();
      },
    });
    return seg;
  }));
  await browser.close(); server.close();

  const list = path.join(tmp, "list.txt");
  fs.writeFileSync(list, segments.map(s => `file '${s}'`).join("\n"));
  await run(["-f", "concat", "-safe", "0", "-i", list, "-i", m4a, "-map", "0:v", "-map", "1:a",
    "-c", "copy", "-movflags", "+faststart", "-t", String(sound.duration), out], { quiet: true });
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log("\n" + out);
})().catch(e => { console.error(e); process.exit(1); });
