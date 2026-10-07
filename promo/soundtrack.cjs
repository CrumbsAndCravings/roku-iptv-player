// Synthesizes the promo's soundtrack from nothing but code: a warm, unhurried groove in
// D major (electric piano, soft pads, a gentle beat) plus UI sounds, and places the
// voiceover clips from voiceover.py. Every sound sits on a cue that promo/index.html
// exposes as window.__sound, so picture, voice and music stay in step.
//
// Each part is rendered as its own stem and mixed to a measured level; the music ducks
// under the voices; then reverb and a dotted-eighth echo are added and the mix is softly
// limited. render.cjs calls this and then normalises loudness with ffmpeg.

const fs = require("fs");

const SR = 48000;

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const noise = (() => { const r = rng(99); return () => r() * 2 - 1; })();
const mtof = m => 440 * Math.pow(2, (m - 69) / 12);
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const TAU = Math.PI * 2;
const db = x => Math.pow(10, x / 20);

// RBJ biquad; coefficients can be changed while the state carries on.
function biquad(type, freq, q) { const f = { x1: 0, x2: 0, y1: 0, y2: 0 }; setBq(f, type, freq, q); return f; }
function setBq(f, type, freq, q) {
  const w = TAU * clamp(freq, 20, SR * .45) / SR, c = Math.cos(w), s = Math.sin(w), a = s / (2 * q);
  let b0, b1, b2;
  if (type === "lp") { b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2; }
  else if (type === "hp") { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2; }
  else { b0 = a; b1 = 0; b2 = -a; }
  const a0 = 1 + a;
  f.b0 = b0 / a0; f.b1 = b1 / a0; f.b2 = b2 / a0; f.a1 = -2 * c / a0; f.a2 = (1 - a) / a0;
}
function bq(f, x) { const y = f.b0 * x + f.b1 * f.x1 + f.b2 * f.x2 - f.a1 * f.y1 - f.a2 * f.y2; f.x2 = f.x1; f.x1 = x; f.y2 = f.y1; f.y1 = y; return y; }

// sound: { duration, sections, cues } from the page. voices: { id: Float32Array at 48 kHz }.
function makeSoundtrack(sound, outFile, voices = {}) {
  const { duration, sections: S, cues } = sound;
  const N = Math.ceil(duration * SR);
  const stem = () => [new Float32Array(N), new Float32Array(N)];
  const stems = {};
  const get = name => (stems[name] = stems[name] || stem());
  const warnings = [];

  // Adds a mono generator to a stem from time t0 for len seconds, panned -1..1.
  function voice(name, t0, len, pan, gen) {
    const st = get(name), i0 = Math.max(0, Math.round(t0 * SR)), i1 = Math.min(N, Math.round((t0 + len) * SR));
    const gl = Math.cos((pan + 1) * Math.PI / 4), gr = Math.sin((pan + 1) * Math.PI / 4);
    for (let i = i0; i < i1; i++) { const v = gen((i - t0 * SR) / SR); st[0][i] += v * gl; st[1][i] += v * gr; }
  }
  const env = (tt, a, len, r) => clamp(tt / a) * clamp((len - tt) / r);

  // Musical grid: bars land on the beat's entry and on the final logo hit.
  const BAR = (S.final - S.drums) / S.bars, BEAT = BAR / 4, SIX = BEAT / 4;
  const barT = n => S.drums + n * BAR;
  const barOf = t => Math.floor((t - S.drums) / BAR + 1e-6);
  const has = (list, n) => (list || []).includes(n);
  const CH = {
    G: { pad: [55, 59, 62, 66, 69], root: 43 },
    "D/F#": { pad: [54, 57, 62, 66, 69], root: 42 },
    Em: { pad: [52, 55, 59, 62, 67], root: 40 },
    A: { pad: [57, 61, 64, 69, 71], root: 45 },
    D: { pad: [62, 66, 69, 73, 76], root: 38 },
  };
  const chordName = n => n <= -2 ? "D" : n === -1 ? "A" : n >= S.bars ? "D" : n === S.bars - 1 ? "A" : ["G", "D/F#", "Em", "A"][n % 4];
  const drumsOn = n => n >= 0 && n < S.bars && !has(S.quiet, n) && !has(S.breakdown, n);

  /* ---------------- the "before": a dull hum, a clock, a droop ---------------- */
  const hookEnd = S.warm;
  for (const [m, det, pan] of [[38, -.12, -.3], [38, .1, .3], [45, .06, 0]]) {
    const f = mtof(m + det);
    voice("hook", 0, hookEnd, pan, tt => {
      const e = clamp(tt / .3) * clamp((hookEnd - tt) / .8) * (.8 + .2 * Math.sin(TAU * .7 * tt));
      return e * (Math.sin(TAU * f * tt) + .35 * Math.sin(TAU * 2 * f * tt) + .12 * Math.sin(TAU * 3 * f * tt));
    });
  }
  for (let k = 0; .1 + k * .5 < hookEnd - .4; k++) {
    const f = k % 2 ? 980 : 1240;
    voice("clock", .1 + k * .5, .08, k % 2 ? .25 : -.25, tt => Math.exp(-tt / .012) * (Math.sin(TAU * f * tt) + .3 * noise()));
  }

  /* ---------------- pads ---------------- */
  const padChord = (t0, len, name, opts = {}) => {
    const atk = opts.attack || .5, bright = opts.bright == null ? .55 : opts.bright, lvl = opts.level || 1;
    CH[name].pad.forEach((m, vi) => {
      for (const [det, pan] of [[-.06, -.55], [.06, .55]]) {
        const f = mtof(m + det), ph = vi * 1.3 + det * 40, k = 1.7 - 1.3 * bright;
        voice("pad", t0, len + .9, pan, tt => {
          const e = lvl * clamp(tt / atk) * clamp((len + .9 - tt) / .9) * (opts.stab ? .55 + .45 * Math.exp(-tt / .9) : 1);
          let v = 0;
          for (let h = 1; h <= 6; h++) v += Math.pow(h, -1.4) * Math.exp(-(h - 1) * k) * Math.sin(TAU * f * h * tt + ph * h);
          return e * v;
        });
      }
    });
  };
  padChord(S.warm, S.bloom - S.warm, "G", { attack: .9, bright: .3, level: .8 });
  padChord(S.bloom, barT(-1) - S.bloom, "D", { stab: true, attack: .02 });
  for (let n = -1; n < S.bars; n++) {
    const quiet = has(S.quiet, n) || has(S.breakdown, n);
    padChord(barT(n), BAR, chordName(n), { bright: quiet ? .3 : has(S.soft, n) ? .45 : .55, level: quiet ? .85 : 1 });
  }
  padChord(S.final, duration - S.final - .8, "D", { stab: true, attack: .02, bright: .6 });

  /* ---------------- electric piano (FM), comping each bar ---------------- */
  const ep = (t0, m, vel, pan, len = 1.6) => {
    const f = mtof(m);
    voice("epiano", t0, len, pan, tt => {
      const idx = 1.1 * Math.exp(-tt / .35);
      const e = vel * clamp(tt / .004) * Math.exp(-tt / .9) * clamp((len - tt) / .2) * (1 + .06 * Math.sin(TAU * 4.5 * tt));
      return e * (Math.sin(TAU * f * tt + idx * Math.sin(TAU * f * tt)) + .12 * Math.sin(TAU * 2 * f * tt));
    });
  };
  const comp = (t0, name, vel) => {
    const notes = CH[name].pad;
    notes.forEach((m, i) => ep(t0 + i * .012, m, vel * (i ? .8 : 1), (i - 2) * .25));
    notes.slice(2).forEach((m, i) => ep(t0 + 1.5 * BEAT + i * .01, m + 12, vel * .55, (i - 1) * .35, 1.1));
  };
  for (let n = 0; n < S.bars; n++) comp(barT(n), chordName(n), has(S.quiet, n) || has(S.breakdown, n) ? .7 : has(S.soft, n) ? .8 : 1);
  comp(S.final, "D", 1.1);
  // After the logo: a slow, fading line over the last chord.
  [74, 78, 81, 85, 81, 78, 76, 74].forEach((m, k) => ep(S.final + 1.2 + k * 2 * BEAT, m + 12, .8 * Math.exp(-k / 5), k % 2 ? .35 : -.35, 1.8));

  /* ---------------- bass ---------------- */
  for (let n = 0; n < S.bars; n++) {
    const root = mtof(CH[chordName(n)].root);
    const hits = has(S.quiet, n) || has(S.breakdown, n) ? [[0, 4]] : [[0, 1.4], [1.5, .9], [2.5, 1.3]];
    for (const [pos, lenB] of hits) {
      const t0 = barT(n) + pos * BEAT, len = lenB * BEAT;
      voice("bass", t0, len + .08, 0, tt => {
        const e = clamp(tt / .008) * clamp((len + .08 - tt) / .08) * (.75 + .25 * Math.exp(-tt / .2));
        return e * (Math.sin(TAU * root * tt) + .35 * Math.sin(TAU * 2 * root * tt) + .1 * Math.sin(TAU * 3 * root * tt));
      });
    }
  }
  { const root = mtof(38); voice("bass", S.final, 3.6, 0, tt => clamp(tt / .008) * Math.exp(-tt / 1.3) * (Math.sin(TAU * root * tt) + .35 * Math.sin(TAU * 2 * root * tt))); }

  /* ---------------- soft plucks in eighths ---------------- */
  const PAT = [0, 2, 3, 1, 2, 3, 4, 3];
  const pluck = (t0, m, vel, pan) => {
    const f = mtof(m);
    voice("arp", t0, 1.2, pan, tt => vel * Math.exp(-tt / .22) * clamp(tt / .003) * Math.sin(TAU * f * tt + .9 * Math.exp(-tt / .06) * Math.sin(TAU * 2 * f * tt)));
  };
  for (let n = 0; n < S.bars; n++) {
    if (has(S.quiet, n) || has(S.soft, n) || n < 2) continue;
    const tones = CH[chordName(n)].pad.slice(1).map(m => m + 12);
    for (let k = 0; k < 8; k++) pluck(barT(n) + k * 2 * SIX, tones[PAT[k] % tones.length], has(S.breakdown, n) ? .6 : (k % 4 === 0 ? 1 : .7), k % 2 ? .35 : -.35);
  }

  /* ---------------- drums: soft kick, rim, shaker ---------------- */
  const kick = (t0, vel = 1) => {
    let ph = 0;
    voice("kick", t0, .5, 0, tt => { const f = 46 + 70 * Math.exp(-tt / .035); ph += TAU * f / SR; return vel * (Math.exp(-tt / .3) * Math.sin(ph) + .12 * Math.exp(-tt / .003) * noise()); });
  };
  const rim = (t0, vel = 1) => {
    const f = biquad("bp", 1900, 2.2);
    voice("rim", t0, .2, -.1, tt => vel * (bq(f, noise()) * 2.4 * Math.exp(-tt / .018) + .5 * Math.exp(-tt / .025) * Math.sin(TAU * 820 * tt)));
  };
  const shaker = (t0, vel) => {
    const f = biquad("bp", 6500, 1.2);
    voice("shaker", t0, .12, .25, tt => vel * bq(f, noise()) * Math.sin(Math.PI * clamp(tt / .09)));
  };
  const crash = (t0, vel = 1) => {
    for (const pan of [-.3, .3]) {
      const fl = biquad("hp", 4500, .6);
      voice("crash", t0, 3, pan, tt => vel * bq(fl, noise()) * Math.exp(-tt / .9) * clamp(tt / .004));
    }
  };
  for (let n = 0; n < S.bars; n++) {
    const soft = has(S.soft, n) ? .7 : 1;
    if (drumsOn(n)) {
      for (let k = 0; k < 16; k++) {
        const t0 = barT(n) + k * SIX;
        if (k === 0 || k === 8 || (n % 2 === 1 && k === 10)) kick(t0, (k === 0 ? 1 : .85) * soft);
        if (k === 4 || k === 12) rim(t0, soft);
        shaker(t0, (k % 2 ? .55 : .35) * soft);
      }
    }
    if (has(S.build, n)) {
      // Back from the quiet: kicks on every beat and a rising roll into the logo.
      for (let k = 0; k < 4; k++) kick(barT(n) + k * BEAT, .6 + .1 * k);
      for (let k = 0; k < 8; k++) rim(barT(n) + 2 * BEAT + k * BEAT / 4, .3 + .7 * k / 8);
    }
  }
  crash(barT(S.lift), .7); crash(S.final, 1); kick(S.final, 1.1);

  /* ---------------- effects and UI sounds ---------------- */
  const bell = (t0, m, vel, pan, name, decay = .9, ratio = 3.5) => {
    const f = mtof(m);
    voice(name, t0, decay * 5, pan, tt => vel * Math.exp(-tt / decay) * clamp(tt / .003) * Math.sin(TAU * f * tt + 1.8 * Math.exp(-tt / .3) * Math.sin(TAU * ratio * f * tt)));
  };
  const sweep = (name, t0, len, lo, hi, vel, q = 1.4) => {
    const f = biquad("bp", lo, q);
    let i = 0;
    voice(name, t0, len, 0, tt => {
      const x = tt / len;
      if (i++ % 32 === 0) setBq(f, "bp", lo + (hi - lo) * Math.sin(Math.PI * Math.min(1, x * 1.1)), q);
      return vel * Math.pow(Math.sin(Math.PI * clamp(x)), 1.6) * bq(f, noise()) * 2.5;
    });
  };
  for (const c of cues) {
    const t = c.t;
    switch (c.type) {
      case "droop": {
        let ph = 0;
        voice("droop", t, .75, 0, tt => {
          const f = (300 - 108 * clamp(tt / .55)) * (1 + .02 * Math.sin(TAU * 6 * tt));
          ph += TAU * f / SR;
          return env(tt, .03, .75, .25) * (Math.sin(ph) + .3 * Math.sin(3 * ph) + .12 * Math.sin(5 * ph));
        });
        break;
      }
      case "riser": {
        const len = S.bloom - t, f = biquad("bp", 300, 2);
        let i = 0;
        voice("riser", t, len, 0, tt => {
          const x = tt / len;
          if (i++ % 32 === 0) setBq(f, "bp", 300 * Math.pow(16, x), 2);
          return Math.pow(x, 2.2) * bq(f, noise()) * 2.4;
        });
        break;
      }
      case "bloom":
      case "hit": {
        let ph = 0;
        voice("boom", t, 2.2, 0, tt => { ph += TAU * (40 + 22 * Math.exp(-tt / .12)) / SR; return Math.exp(-tt / .7) * Math.sin(ph) * clamp(tt / .004); });
        [74, 78, 81, 85, 88, 90, 93].forEach((m, i) => bell(t + .03 + i * .04, m, .9 - i * .06, (i / 3) - 1, "shimmer", 1.3));
        break;
      }
      case "sparkle": [88, 93, 97, 100].forEach((m, i) => bell(t + i * .045, m, .8 - i * .12, .5 - i * .25, "sparkle", .6, 2.76)); break;
      case "tick": voice("tick", t, .12, 0, tt => Math.exp(-tt / .016) * (Math.sin(TAU * 1480 * tt) + .3 * Math.sin(TAU * 2960 * tt))); break;
      case "select": [0, .06].forEach((o, i) => voice("tick", t + o, .14, 0, tt => Math.exp(-tt / .03) * Math.sin(TAU * (i ? 1320 : 880) * tt))); break;
      case "whoosh": sweep("whoosh", t, .7, 350, 2950, 1); break;
      case "slide": sweep("slide", t, 1.0, 500, 3500, 1, 2.2); break;
      case "pop": [81, 88].forEach((m, i) => bell(t + i * .07, m, .8, .2, "chime", .55, 2)); break;
      case "glide": [74, 78, 81, 86, 90, 93].forEach((m, i) => bell(t + i * .12, m, .55 + i * .05, -.5 + i * .2, "chime", .7, 2)); break;
      case "land": [86, 93].forEach((m, i) => bell(t + i * .1, m, .9, .3, "chime", .9, 2)); break;
      case "chime": [81, 86].forEach((m, i) => bell(t + i * .13, m, .9, i ? .3 : -.3, "chime", .8, 2)); break;
      case "count": voice("tick", t, .1, 0, tt => .8 * Math.exp(-tt / .03) * Math.sin(TAU * 900 * tt)); break;
      case "card": [86, 90, 93].forEach((m, i) => bell(t + i * .09, m, .8, (i - 1) * .4, "chime", .9, 2)); break;
    }
  }

  /* ---------------- mix ---------------- */
  const peak = st => { let p = 0; for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) p = Math.max(p, Math.abs(st[c][i])); return p; };
  // RMS over the stretch where the part actually plays (bars it sits out don't count).
  const rms = (st, a = 0, b = duration) => {
    const i0 = Math.round(a * SR), i1 = Math.min(N, Math.round(b * SR)), floor = peak(st) * 1e-3;
    let s = 0, n = 0;
    for (let i = i0; i < i1; i++) for (let c = 0; c < 2; c++) { const x = st[c][i]; if (Math.abs(x) > floor) { s += x * x; n++; } }
    return Math.sqrt(s / Math.max(1, n));
  };
  // Levels in dBFS before the master stage: RMS over the groove for music, peak for one-shots.
  const groove = [barT(0), barT(5)];
  const TARGET = {
    kick: ["rms", -22], rim: ["rms", -27], shaker: ["rms", -33], crash: ["peak", -15],
    bass: ["rms", -22], pad: ["rms", -23], epiano: ["rms", -22], arp: ["rms", -28],
    hook: ["rms", -26], clock: ["peak", -17], droop: ["peak", -11], riser: ["peak", -11],
    boom: ["peak", -6], shimmer: ["peak", -12], sparkle: ["peak", -13], tick: ["peak", -17],
    whoosh: ["peak", -15], slide: ["peak", -16], chime: ["peak", -12],
  };
  for (const name in stems) {
    const [mode, level] = TARGET[name] || ["peak", -14];
    const measured = mode === "rms" && name !== "hook" ? rms(stems[name], ...groove) : mode === "rms" ? rms(stems[name], .3, S.warm - .3) : peak(stems[name]);
    const g = measured > 0 ? db(level) / measured : 0;
    for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) stems[name][c][i] *= g;
  }
  // Sidechain: the pads and piano breathe with the kick.
  { const kicks = []; const k = stems.kick;
    for (let i = 1; i < N; i++) if (Math.abs(k[0][i]) > .03 && Math.abs(k[0][i - 1]) <= .03 && (!kicks.length || i - kicks[kicks.length - 1] > SR * .1)) kicks.push(i);
    let j = 0;
    for (let i = 0; i < N; i++) {
      while (j + 1 < kicks.length && kicks[j + 1] <= i) j++;
      const d = kicks.length && kicks[j] <= i ? (i - kicks[j]) / SR : 9;
      const g = 1 - .3 * Math.exp(-d / .14);
      for (const name of ["pad", "epiano"]) { stems[name][0][i] *= g; stems[name][1][i] *= g; }
    }
  }

  // Voices: each clip at its cue, gently compressed, set well above the music.
  const vo = new Float32Array(N);
  const voCues = cues.filter(c => c.type === "vo");
  voCues.forEach((c, k) => {
    const clip = voices[c.id];
    if (!clip) { warnings.push(`no voice clip for "${c.id}"`); return; }
    const end = c.t + clip.length / SR, next = voCues[k + 1];
    if (next && end > next.t - .05) warnings.push(`"${c.id}" runs to ${end.toFixed(2)}s, into "${next.id}" at ${next.t}s`);
    if (end > duration) warnings.push(`"${c.id}" runs past the end`);
    const i0 = Math.round(c.t * SR);
    for (let i = 0; i < clip.length && i0 + i < N; i++) vo[i0 + i] += clip[i];
  });
  if (voCues.length) {
    let e = 0;
    for (let i = 0; i < N; i++) {
      const x = Math.abs(vo[i]);
      e += (x > e ? .02 : .0004) * (x - e);
      if (e > db(-24)) vo[i] *= Math.pow(e / db(-24), 1 / 3 - 1); // 3:1 above -24 dBFS
    }
    let s2 = 0, n2 = 0;
    for (let i = 0; i < N; i++) if (Math.abs(vo[i]) > db(-40)) { s2 += vo[i] * vo[i]; n2++; }
    const g = db(-15) / Math.sqrt(s2 / Math.max(1, n2));
    const st = get("voice");
    for (let i = 0; i < N; i++) { st[0][i] = vo[i] * g * Math.SQRT1_2; st[1][i] = vo[i] * g * Math.SQRT1_2; }
    // Music drops about 9 dB while someone speaks: 60 ms down, 500 ms back up.
    let e2 = 0, gd = 1;
    const low = db(-9), down = 1 - Math.exp(-1 / (.06 * SR)), up = 1 - Math.exp(-1 / (.5 * SR));
    const UI = new Set(["tick", "chime", "sparkle"]);
    for (let i = 0; i < N; i++) {
      e2 = Math.max(Math.abs(vo[i]) * g, e2 * Math.exp(-1 / (.12 * SR)));
      const target = e2 > db(-32) ? low : 1;
      gd += (target - gd) * (target < gd ? down : up);
      for (const name in stems) {
        if (name === "voice") continue;
        const k = UI.has(name) ? 1 - .5 * (1 - gd) : gd;
        stems[name][0][i] *= k; stems[name][1][i] *= k;
      }
    }
  }

  const SEND_VERB = { voice: .06, pad: .35, epiano: .25, arp: .3, rim: .15, shimmer: .7, sparkle: .7, chime: .55, droop: .3, clock: .25, tick: .12, whoosh: .3, slide: .3, crash: .25, riser: .3 };
  const SEND_ECHO = { arp: .3, epiano: .12, sparkle: .25, chime: .2 };
  const mix = stem(), vin = stem(), ein = stem();
  for (const name in stems) for (let c = 0; c < 2; c++) {
    const s = stems[name][c], m = mix[c], v = vin[c], e = ein[c], sv = SEND_VERB[name] || 0, se = SEND_ECHO[name] || 0;
    for (let i = 0; i < N; i++) { m[i] += s[i]; if (sv) v[i] += s[i] * sv; if (se) e[i] += s[i] * se; }
  }
  // Ping-pong echo at a dotted eighth, darkening as it repeats.
  { const d = Math.round(BEAT * .75 * SR), fb = .36; let lpL = 0, lpR = 0;
    const L = new Float32Array(N), R = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      const pl = i >= d ? R[i - d] : 0, pr = i >= d ? L[i - d] : 0;
      lpL += .35 * (pl - lpL); lpR += .35 * (pr - lpR);
      L[i] = ein[0][i] + lpL * fb; R[i] = ein[1][i] + lpR * fb;
      mix[0][i] += (L[i] - ein[0][i]) * .9; mix[1][i] += (R[i] - ein[1][i]) * .9;
      vin[0][i] += (L[i] - ein[0][i]) * .3; vin[1][i] += (R[i] - ein[1][i]) * .3;
    }
  }
  // Freeverb-style room, a little larger for the warmer mood.
  { const scale = SR / 44100, combT = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617], apT = [556, 441, 341, 225];
    const room = .88, damp = .32;
    const chan = off => {
      const combs = combT.map(n => ({ b: new Float32Array(Math.round((n + off) * scale)), i: 0, s: 0 }));
      const aps = apT.map(n => ({ b: new Float32Array(Math.round((n + off) * scale)), i: 0 }));
      const out = new Float32Array(N);
      for (let i = 0; i < N; i++) {
        const x = (vin[0][i] + vin[1][i]) * .015;
        let acc = 0;
        for (const c of combs) { const y = c.b[c.i]; c.s = y * (1 - damp) + c.s * damp; c.b[c.i] = x + c.s * room; if (++c.i >= c.b.length) c.i = 0; acc += y; }
        for (const a of aps) { const b = a.b[a.i]; const y = b - acc; a.b[a.i] = acc + b * .5; if (++a.i >= a.b.length) a.i = 0; acc = y; }
        out[i] = acc;
      }
      return out;
    };
    const wl = chan(0), wr = chan(23);
    for (let i = 0; i < N; i++) { mix[0][i] += wl[i] * 2.4; mix[1][i] += wr[i] * 2.4; }
  }
  // Master: gentle saturation, a short fade in, and a fade out over the last second.
  let pk = 0;
  for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) {
    const t = i / SR, fade = clamp(t / .02) * clamp((duration - t) / 1.1);
    mix[c][i] = Math.tanh(mix[c][i] * 1.3) / 1.3 * fade;
    pk = Math.max(pk, Math.abs(mix[c][i]));
  }
  const norm = .89 / pk;

  // 24-bit stereo WAV.
  const data = Buffer.alloc(N * 6);
  for (let i = 0, o = 0; i < N; i++) for (let c = 0; c < 2; c++, o += 3) {
    const v = Math.max(-8388608, Math.min(8388607, Math.round(mix[c][i] * norm * 8388607)));
    data.writeIntLE(v, o, 3);
  }
  const head = Buffer.alloc(44);
  head.write("RIFF", 0); head.writeUInt32LE(36 + data.length, 4); head.write("WAVE", 8);
  head.write("fmt ", 12); head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20); head.writeUInt16LE(2, 22);
  head.writeUInt32LE(SR, 24); head.writeUInt32LE(SR * 6, 28); head.writeUInt16LE(6, 32); head.writeUInt16LE(24, 34);
  head.write("data", 36); head.writeUInt32LE(data.length, 40);
  fs.writeFileSync(outFile, Buffer.concat([head, data]));
  return { bpm: 60 / BEAT, warnings };
}

module.exports = { makeSoundtrack };
