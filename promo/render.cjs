// Renders promo/index.html to a 1080x1920 MP4, frame by frame.
//   NODE_PATH="$(npm root -g)" node promo/render.cjs [out.mp4] [fps]
// Needs Playwright (with Chromium) and ffmpeg.
const { chromium } = require("playwright");
const { spawn } = require("child_process");
const path = require("path");

const out = path.resolve(process.argv[2] || path.join(__dirname, "aranplus-promo.mp4"));
const fps = Number(process.argv[3] || 30);
const stills = process.env.STILLS; // "1.5,6,12" renders PNGs at those times instead

(async () => {
  const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
  await page.goto("file://" + path.join(__dirname, "index.html") + "?render");
  await page.waitForFunction(() => window.__ready === true);

  if (stills) {
    for (const t of stills.split(",").map(Number)) {
      await page.evaluate(x => window.__seek(x), t);
      const file = out.replace(/\.mp4$/, "") + `-${t.toFixed(2)}.png`;
      await page.screenshot({ path: file });
      console.log(file);
    }
    await browser.close();
    return;
  }

  const duration = await page.evaluate(() => window.__duration);
  const frames = Math.round(duration * fps);
  const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(fps), "-c:v", "png", "-i", "-",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out], { stdio: ["pipe", "inherit", "inherit"] });
  for (let f = 0; f < frames; f++) {
    await page.evaluate(x => window.__seek(x), f / fps);
    const png = await page.screenshot({ type: "png" });
    if (!ff.stdin.write(png)) await new Promise(r => ff.stdin.once("drain", r));
    if (f % fps === 0) process.stdout.write(`\r${(f / fps).toFixed(0)}s / ${duration}s`);
  }
  ff.stdin.end();
  await new Promise((res, rej) => ff.on("close", c => (c === 0 ? res() : rej(new Error("ffmpeg exited " + c)))));
  await browser.close();
  console.log("\n" + out);
})().catch(e => { console.error(e); process.exit(1); });
