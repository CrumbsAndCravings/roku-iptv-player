// Synthesizes the promo's soundtrack from nothing but code: a dreamy pop groove in D
// major plus UI sounds (focus ticks, key presses, whooshes, sparkles), each placed on a
// cue that promo/index.html exposes as window.__sound, so picture and sound stay in step.
//
// Every part is rendered as its own stem and mixed to a measured level, then reverb and
// a dotted-eighth echo are added and the mix is softly limited. The voiceover (from
// voiceover.py) sits on top, with the music ducking while someone speaks. render.cjs
// calls this and then normalises loudness with ffmpeg.

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

function makeSoundtrack(sound, outFile, vo) {
  const { duration, sections: S, cues } = sound;
  const N = Math.ceil(duration * SR);
  const stem = () => [new Float32Array(N), new Float32Array(N)];
  const stems = {};
  const get = name => (stems[name] = stems[name] || stem());

  // Adds a mono generator to a stem from time t0 for len seconds, panned -1..1.
  function voice(name, t0, len, pan, gen) {
    const st = get(name), i0 = Math.max(0, Math.round(t0 * SR)), i1 = Math.min(N, Math.round((t0 + len) * SR));
    const gl = Math.cos((pan + 1) * Math.PI / 4), gr = Math.sin((pan + 1) * Math.PI / 4);
    for (let i = i0; i < i1; i++) { const v = gen((i - t0 * SR) / SR); st[0][i] += v * gl; st[1][i] += v * gr; }
  }
  const env = (tt, a, len, r) => clamp(tt / a) * clamp((len - tt) / r);

  // Musical grid: bars land on the drum entry and on the final logo hit.
  const BAR = (S.final - S.drums) / 13, BEAT = BAR / 4, SIX = BEAT / 4;
  const barT = n => S.drums + n * BAR;
  const barOf = t => Math.floor((t - S.drums) / BAR);
  const breakBar = barOf(S.breakdown), backBar = breakBar + 1;
  const CH = {
    D: { pad: [62, 66, 69, 73, 76], root: 38 },
    Bm: { pad: [59, 62, 66, 69, 73], root: 35 },
    G: { pad: [55, 59, 62, 66, 69], root: 43 },
    A: { pad: [57, 61, 64, 66, 71], root: 45 },
  };
  const chordName = n => n <= -2 ? "D" : n === -1 ? "A" : n >= 13 ? "D" : n === 12 ? "G" : ["D", "Bm", "G", "A"][n % 4];
  const drumsOn = t => t >= S.drums - 1e-6 && t < S.final && !(t >= barT(breakBar) && t < barT(backBar));
  // How open the pads and plucks sound over the piece.
  const bright = t => t < S.drums ? .35 + .4 * clamp((t - S.bloom) / (S.drums - S.bloom))
    : (t >= barT(breakBar) && t < barT(backBar)) ? .3 : 1;

  /* ---------------- hook: a dull hum, a clock, a droop ---------------- */
  const hookEnd = S.bloom;
  for (const [m, det, pan] of [[38, -.12, -.3], [38, .1, .3], [45, .06, 0]]) {
    const f = mtof(m + det);
    voice("hook", 0, hookEnd, pan, tt => {
      const e = clamp(tt / .3) * clamp((hookEnd - .2 - tt) / .6) * (.8 + .2 * Math.sin(TAU * .7 * tt));
      return e * (Math.sin(TAU * f * tt) + .35 * Math.sin(TAU * 2 * f * tt) + .12 * Math.sin(TAU * 3 * f * tt));
    });
  }
  for (let k = 0; k * .5 < hookEnd - .6; k++) {
    const f = k % 2 ? 980 : 1240;
    voice("clock", .1 + k * .5, .08, k % 2 ? .25 : -.25, tt => Math.exp(-tt / .012) * (Math.sin(TAU * f * tt) + .3 * noise()));
  }

  /* ---------------- pads, with the kick ducking them ---------------- */
  const padChord = (t0, len, name, stab) => {
    CH[name].pad.forEach((m, vi) => {
      for (const [det, pan] of [[-.07, -.6], [.07, .6]]) {
        const f = mtof(m + det), ph = vi * 1.3 + det * 40;
        voice("pad", t0, len + .7, pan, tt => {
          const t = t0 + tt, k = 1.6 - 1.25 * bright(t);
          const e = clamp(tt / (stab ? .01 : .3)) * clamp((len + .7 - tt) / .7) * (stab ? .55 + .45 * Math.exp(-tt / .8) : 1);
          let v = 0;
          for (let h = 1; h <= 7; h++) v += Math.pow(h, -1.35) * Math.exp(-(h - 1) * k) * Math.sin(TAU * f * h * tt + ph * h);
          return e * v;
        });
      }
    });
  };
  padChord(S.bloom, barT(-1) - S.bloom, "D", true);
  for (let n = -1; barT(n) < S.final; n++) padChord(barT(n), BAR, chordName(n), false);
  padChord(S.final, duration - S.final - .6, "D", true);

  /* ---------------- bass ---------------- */
  for (let n = 0; barT(n) < S.final + 1e-6; n++) {
    const root = mtof(CH[chordName(n)].root);
    const inBreak = n === breakBar;
    const hits = inBreak ? [[0, 8]] : [[0, 1.6], [3, 1.6], [4, 1.6], [6, 1.6]];
    for (const [pos, lenE] of hits) {
      const t0 = barT(n) + pos * 2 * SIX, len = lenE * 2 * SIX;
      voice("bass", t0, len + .06, 0, tt => {
        const e = clamp(tt / .006) * clamp((len + .06 - tt) / .06) * (inBreak ? .7 : .75 + .25 * Math.exp(-tt / .15));
        return e * (Math.sin(TAU * root * tt) + .4 * Math.sin(TAU * 2 * root * tt) + .15 * Math.sin(TAU * 3 * root * tt));
      });
    }
  }
  { const root = mtof(38), len = 3.2;
    voice("bass", S.final, len, 0, tt => clamp(tt / .006) * Math.exp(-tt / 1.1) * (Math.sin(TAU * root * tt) + .4 * Math.sin(TAU * 2 * root * tt))); }

  /* ---------------- plucked arpeggio, FM bell ---------------- */
  const PAT = [0, 2, 3, 1, 2, 3, 4, 3, 0, 2, 3, 1, 4, 3, 2, 1];
  const pluck = (t0, m, vel, pan, name = "arp", decay = .17) => {
    const f = mtof(m);
    voice(name, t0, decay * 6, pan, tt => {
      const idx = (.6 + 1.4 * bright(t0)) * Math.exp(-tt / .05);
      return vel * Math.exp(-tt / decay) * clamp(tt / .002) * Math.sin(TAU * f * tt + idx * Math.sin(TAU * 2 * f * tt));
    });
  };
  for (let k = Math.ceil((S.bloom + .25 - S.drums) / SIX); S.drums + k * SIX < S.final - 1e-6; k++) {
    const t0 = S.drums + k * SIX, n = barOf(t0), step = ((k % 16) + 16) % 16;
    const tones = CH[chordName(n)].pad.slice(1).map(m => m + 12);
    const m = tones[PAT[step] % tones.length];
    const ramp = t0 < S.drums ? .35 + .65 * clamp((t0 - S.bloom) / (S.drums - S.bloom)) : 1;
    pluck(t0, m, ramp * (step % 4 === 0 ? 1 : .72), step % 2 ? .35 : -.35);
  }
  // After the logo: slower, fading plucks over the last chord.
  for (let k = 0; S.final + k * 2 * SIX < duration - 1.2; k++) {
    const t0 = S.final + k * 2 * SIX, tones = [78, 81, 85, 88, 85, 81];
    pluck(t0, tones[k % tones.length], Math.exp(-k / 9), k % 2 ? .4 : -.4, "arp", .25);
  }

  /* ---------------- drums ---------------- */
  const kick = (t0, vel = 1) => {
    let ph = 0;
    voice("kick", t0, .45, 0, tt => { const f = 48 + 95 * Math.exp(-tt / .032); ph += TAU * f / SR; return vel * (Math.exp(-tt / .26) * Math.sin(ph) + .25 * Math.exp(-tt / .003) * noise()); });
  };
  const clap = (t0, vel = 1) => {
    const f = biquad("bp", 1250, .9);
    voice("clap", t0, .4, 0, tt => {
      const bursts = [0, .011, .022].reduce((a, o) => a + (tt >= o ? Math.exp(-(tt - o) / .007) : 0), 0) + .7 * Math.exp(-tt / .11);
      return vel * (bq(f, noise() * bursts) * 2.2 + .25 * Math.exp(-tt / .04) * Math.sin(TAU * 190 * tt));
    });
  };
  const hat = (t0, vel, open = false, pan = .2) => {
    const f = biquad("hp", 7200, .7);
    voice("hats", t0, open ? .5 : .08, pan, tt => vel * bq(f, noise()) * Math.exp(-tt / (open ? .2 : .028)));
  };
  const crash = (t0, vel = 1) => {
    const fl = biquad("hp", 4200, .6), fr = biquad("hp", 4200, .6);
    voice("crash", t0, 2.6, -.3, tt => vel * bq(fl, noise()) * Math.exp(-tt / .75) * clamp(tt / .004));
    voice("crash", t0, 2.6, .3, tt => vel * bq(fr, noise()) * Math.exp(-tt / .8) * clamp(tt / .004));
  };
  for (let k = 0; S.drums + k * SIX < S.final - 1e-6; k++) {
    const t0 = S.drums + k * SIX;
    if (!drumsOn(t0 + 1e-4)) continue;
    const step = k % 16, n = barOf(t0 + 1e-4);
    if ([0, 6, 8].includes(step) || (n % 2 === 1 && step === 11)) kick(t0, step === 0 ? 1 : .85);
    if (step === 4 || step === 12) clap(t0);
    if (step % 2 === 0) hat(t0, step % 4 === 2 ? .9 : .55);
    else if (t0 > 10.6) hat(t0, .25, false, -.25);
    if (step === 14 && n % 2 === 1) hat(t0, .5, true);
  }
  // Fills into the drop and back from the breakdown.
  const fill = (end, beats) => { const steps = Math.round(beats * 4); for (let i = 0; i < steps; i++) clap(end - (steps - i) * SIX, .25 + .75 * (i / steps)); };
  fill(S.drums, 1);
  fill(barT(backBar), 2);
  crash(S.drums, .9); crash(barT(backBar), .8); crash(S.final, 1);
  kick(S.final, 1.1);

  /* ---------------- effects and UI sounds ---------------- */
  const bell = (t0, m, vel, pan, name, decay = .9, ratio = 3.5) => {
    const f = mtof(m);
    voice(name, t0, decay * 5, pan, tt => vel * Math.exp(-tt / decay) * clamp(tt / .003) * Math.sin(TAU * f * tt + 1.8 * Math.exp(-tt / .3) * Math.sin(TAU * ratio * f * tt)));
  };
  const whoosh = (t0, len = .7, vel = 1) => {
    const f = biquad("bp", 400, 1.4);
    let i = 0, pan = 0;
    const g = tt => {
      const x = tt / len;
      if (i++ % 32 === 0) setBq(f, "bp", 350 + 2600 * Math.sin(Math.PI * Math.min(1, x * 1.1)), 1.4);
      return vel * Math.pow(Math.sin(Math.PI * clamp(x)), 1.6) * bq(f, noise()) * 2.5;
    };
    voice("whoosh", t0, len, pan, g);
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
        let i = 0, ph = 0;
        voice("riser", t, len, 0, tt => {
          const x = tt / len;
          if (i++ % 32 === 0) setBq(f, "bp", 300 * Math.pow(20, x), 2);
          ph += TAU * (180 * Math.pow(6, x)) / SR;
          return Math.pow(x, 2.2) * (bq(f, noise()) * 2.4 + .25 * Math.sin(ph));
        });
        break;
      }
      case "bloom":
      case "hit": {
        let ph = 0;
        voice("boom", t, 2.2, 0, tt => { ph += TAU * (40 + 22 * Math.exp(-tt / .12)) / SR; return Math.exp(-tt / .7) * Math.sin(ph) * clamp(tt / .004); });
        [74, 78, 81, 85, 88, 90, 93].forEach((m, i) => bell(t + .03 + i * .035, m, .9 - i * .06, (i / 3) - 1, "shimmer", 1.2));
        break;
      }
      case "sparkle": [88, 93, 97, 100].forEach((m, i) => bell(t + i * .045, m, .8 - i * .12, .5 - i * .25, "sparkle", .6, 2.76)); break;
      case "tick": voice("tick", t, .12, 0, tt => Math.exp(-tt / .016) * (Math.sin(TAU * 1480 * tt) + .3 * Math.sin(TAU * 2960 * tt))); break;
      case "key": { const f = biquad("hp", 2400, .7); voice("key", t, .08, -.15, tt => Math.exp(-tt / .009) * bq(f, noise()) * 1.6 + .6 * Math.exp(-tt / .018) * Math.sin(TAU * 1050 * tt)); break; }
      case "select": [0, .06].forEach((o, i) => voice("tick", t + o, .14, 0, tt => Math.exp(-tt / .03) * Math.sin(TAU * (i ? 1320 : 880) * tt))); break;
      case "whoosh": whoosh(t); break;
      case "chime": [81, 86].forEach((m, i) => bell(t + i * .13, m, .9, i ? .3 : -.3, "chime", .8, 2)); break;
      case "count": voice("tick", t, .1, 0, tt => .8 * Math.exp(-tt / .03) * Math.sin(TAU * 900 * tt)); break;
      case "card": [86, 90, 93].forEach((m, i) => bell(t + i * .09, m, .8, (i - 1) * .4, "chime", .9, 2)); break;
    }
  }

  /* ---------------- mix ---------------- */
  const rms = (st, a = 0, b = duration) => {
    const i0 = Math.round(a * SR), i1 = Math.min(N, Math.round(b * SR));
    let s = 0, n = 0;
    for (let i = i0; i < i1; i++) { s += st[0][i] * st[0][i] + st[1][i] * st[1][i]; n += 2; }
    return Math.sqrt(s / Math.max(1, n));
  };
  const peak = st => { let p = 0; for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) p = Math.max(p, Math.abs(st[c][i])); return p; };
  const db = x => Math.pow(10, x / 20);
  // Levels in dBFS before the master stage: RMS over the groove for music, peak for one-shots.
  const groove = [S.drums, barT(breakBar)];
  const TARGET = {
    kick: ["rms", -19], clap: ["rms", -22], hats: ["rms", -28], crash: ["peak", -10],
    bass: ["rms", -21.5], pad: ["rms", -21], arp: ["rms", -23.5],
    hook: ["rms", -26], clock: ["peak", -17], droop: ["peak", -11], riser: ["peak", -9],
    boom: ["peak", -5], shimmer: ["peak", -12], sparkle: ["peak", -13], tick: ["peak", -16],
    key: ["peak", -17], whoosh: ["peak", -13], chime: ["peak", -12],
  };
  const report = {};
  for (const name in stems) {
    const [mode, level] = TARGET[name] || ["peak", -14];
    const measured = mode === "rms" && name !== "hook" ? rms(stems[name], ...groove) : mode === "rms" ? rms(stems[name], .3, S.bloom - .3) : peak(stems[name]);
    const g = measured > 0 ? db(level) / measured : 0;
    for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) stems[name][c][i] *= g;
    report[name] = level;
  }
  // Voiceover: gently compressed, set well above the music, which ducks under it.
  let duck = null;
  if (vo) {
    const v = new Float32Array(N);
    v.set(vo.subarray(0, N));
    let env = 0;
    for (let i = 0; i < N; i++) {
      const x = Math.abs(v[i]);
      env += (x > env ? .02 : .0004) * (x - env);
      const over = env > db(-24) ? Math.pow(env / db(-24), 1 / 3 - 1) : 1; // 3:1 above -24 dBFS
      v[i] *= over;
    }
    let s2 = 0, n2 = 0;
    for (let i = 0; i < N; i++) if (Math.abs(v[i]) > db(-40)) { s2 += v[i] * v[i]; n2++; }
    const g = db(-15) / Math.sqrt(s2 / Math.max(1, n2));
    const st = get("voice");
    for (let i = 0; i < N; i++) { st[0][i] = v[i] * g * Math.SQRT1_2; st[1][i] = v[i] * g * Math.SQRT1_2; }
    report.voice = -15;
    // Music drops about 8 dB while the voice is active: 60 ms down, 450 ms back up.
    duck = new Float32Array(N);
    let e2 = 0, gd = 1;
    const low = db(-8), down = 1 - Math.exp(-1 / (.06 * SR)), up = 1 - Math.exp(-1 / (.45 * SR));
    for (let i = 0; i < N; i++) {
      e2 = Math.max(Math.abs(v[i]) * g, e2 * Math.exp(-1 / (.12 * SR)));
      const target = e2 > db(-32) ? low : 1;
      gd += (target - gd) * (target < gd ? down : up);
      duck[i] = gd;
    }
    const UI = new Set(["tick", "key", "chime", "sparkle"]);
    for (const name in stems) {
      if (name === "voice") continue;
      const depth = UI.has(name) ? .5 : 1;
      for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) stems[name][c][i] *= 1 - depth * (1 - duck[i]);
    }
  }
  // Sidechain: the pads breathe with the kick.
  { const kicks = []; const k = stems.kick;
    for (let i = 1; i < N; i++) if (Math.abs(k[0][i]) > .05 && Math.abs(k[0][i - 1]) <= .05 && (!kicks.length || i - kicks[kicks.length - 1] > SR * .1)) kicks.push(i);
    let j = 0;
    for (let i = 0; i < N; i++) {
      while (j + 1 < kicks.length && kicks[j + 1] <= i) j++;
      const d = kicks.length && kicks[j] <= i ? (i - kicks[j]) / SR : 9;
      const g = 1 - .45 * Math.exp(-d / .12);
      stems.pad[0][i] *= g; stems.pad[1][i] *= g;
    }
  }

  const SEND_VERB = { voice: .06, pad: .35, arp: .3, clap: .2, shimmer: .7, sparkle: .7, chime: .6, droop: .3, clock: .25, tick: .15, key: .08, whoosh: .3, crash: .25, riser: .3 };
  const SEND_ECHO = { arp: .32, sparkle: .25, chime: .2 };
  const mix = stem(), vin = stem(), ein = stem();
  for (const name in stems) for (let c = 0; c < 2; c++) {
    const s = stems[name][c], m = mix[c], v = vin[c], e = ein[c], sv = SEND_VERB[name] || 0, se = SEND_ECHO[name] || 0;
    for (let i = 0; i < N; i++) { m[i] += s[i]; if (sv) v[i] += s[i] * sv; if (se) e[i] += s[i] * se; }
  }
  // Ping-pong echo at a dotted eighth, darkening as it repeats.
  { const d = Math.round(BEAT * .75 * SR), fb = .38; let lpL = 0, lpR = 0;
    const L = new Float32Array(N), R = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      const pl = i >= d ? R[i - d] : 0, pr = i >= d ? L[i - d] : 0;
      lpL += .35 * (pl - lpL); lpR += .35 * (pr - lpR);
      L[i] = ein[0][i] + lpL * fb; R[i] = ein[1][i] + lpR * fb;
      mix[0][i] += (L[i] - ein[0][i]) * .9; mix[1][i] += (R[i] - ein[1][i]) * .9;
      vin[0][i] += (L[i] - ein[0][i]) * .3; vin[1][i] += (R[i] - ein[1][i]) * .3;
    }
  }
  // Freeverb-style room.
  { const scale = SR / 44100, combT = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617], apT = [556, 441, 341, 225];
    const room = .86, damp = .3;
    const chan = (off) => {
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
  return { bpm: 60 / BEAT, bars: { breakdown: breakBar, back: backBar }, stems: report };
}

module.exports = { makeSoundtrack };
