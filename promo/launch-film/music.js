// AIUsage launch film: soundtrack.
// Synthesised entirely with Web Audio (no samples), 120 BPM in D major, rendered offline so
// the same buffer plays in the browser and gets muxed into the exported MP4.
// Every hit lines up with a visual event in film.js.

export const BPM = 120;
export const BEAT = 60 / BPM; // 0.5s
export const DURATION = 44;

const midi = (n) => 440 * Math.pow(2, (n - 69) / 12);

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Chords, two bars (4s) each. Root for the bass, voicing for pads and arps.
const CHORDS = [
  { t: 0, root: 38, notes: [50, 57, 61, 64, 66] },   // Dmaj9
  { t: 4, root: 35, notes: [47, 54, 57, 62, 64] },   // Bm11
  { t: 8, root: 31, notes: [43, 50, 54, 57, 59, 62] }, // Gmaj9
  { t: 12, root: 33, notes: [45, 52, 54, 59, 61] },  // A6sus
  { t: 16, root: 38, notes: [50, 57, 61, 64, 66] },
  { t: 20, root: 35, notes: [47, 54, 57, 62, 64] },
  { t: 24, root: 31, notes: [43, 50, 54, 57, 59, 62] },
  { t: 28, root: 33, notes: [45, 52, 54, 59, 61] },
  { t: 32, root: 35, notes: [47, 54, 57, 62, 66] },  // breakdown
  { t: 36, root: 33, notes: [45, 52, 57, 59, 64] },  // lift
  { t: 38, root: 38, notes: [50, 57, 61, 64, 66, 69] }, // home
];
const chordAt = (t) => { let c = CHORDS[0]; for (const k of CHORDS) if (k.t <= t + 1e-6) c = k; return c; };

export async function renderMusic(sampleRate = 48000) {
  const ctx = new OfflineAudioContext(2, Math.ceil(sampleRate * DURATION), sampleRate);
  build(ctx);
  return ctx.startRendering();
}

function build(ctx) {
  const rand = mulberry32(7);
  const sr = ctx.sampleRate;

  // ---------- buses ----------
  const comp = ctx.createDynamicsCompressor();
  comp.threshold.value = -16; comp.knee.value = 10; comp.ratio.value = 3.2;
  comp.attack.value = 0.006; comp.release.value = 0.18;
  const master = ctx.createGain(); master.gain.value = 0.82;
  master.connect(comp); comp.connect(ctx.destination);
  // gentle fade at the very end
  master.gain.setValueAtTime(0.82, 42.6);
  master.gain.linearRampToValueAtTime(0.0, DURATION - 0.02);

  // reverb
  const irLen = Math.floor(sr * 3.2);
  const ir = ctx.createBuffer(2, irLen, sr);
  for (let ch = 0; ch < 2; ch++) {
    const d = ir.getChannelData(ch);
    for (let i = 0; i < irLen; i++) d[i] = (rand() * 2 - 1) * Math.pow(1 - i / irLen, 2.6);
  }
  const verb = ctx.createConvolver(); verb.buffer = ir;
  const verbIn = ctx.createGain(); verbIn.gain.value = 0.55;
  const verbHP = ctx.createBiquadFilter(); verbHP.type = 'highpass'; verbHP.frequency.value = 220;
  verbIn.connect(verbHP); verbHP.connect(verb); verb.connect(master);

  // dotted-eighth delay
  const delay = ctx.createDelay(2); delay.delayTime.value = BEAT * 0.75;
  const fb = ctx.createGain(); fb.gain.value = 0.34;
  const dlp = ctx.createBiquadFilter(); dlp.type = 'lowpass'; dlp.frequency.value = 3600;
  const delayIn = ctx.createGain(); delayIn.gain.value = 0.4;
  delayIn.connect(delay); delay.connect(dlp); dlp.connect(fb); fb.connect(delay); dlp.connect(master); dlp.connect(verbIn);

  // music bus: filter sweeps + sidechain duck
  const musicLP = ctx.createBiquadFilter(); musicLP.type = 'lowpass'; musicLP.Q.value = 0.6;
  const duck = ctx.createGain();
  const music = ctx.createGain(); music.gain.value = 0.9;
  music.connect(musicLP); musicLP.connect(duck); duck.connect(master);
  const f = musicLP.frequency;
  f.setValueAtTime(900, 0);
  f.exponentialRampToValueAtTime(2600, 4);
  f.exponentialRampToValueAtTime(7000, 7.9);
  f.setValueAtTime(18000, 8.0);
  f.setValueAtTime(18000, 32.0);
  f.exponentialRampToValueAtTime(700, 32.6);
  f.setValueAtTime(700, 35.6);
  f.exponentialRampToValueAtTime(9000, 37.95);
  f.setValueAtTime(18000, 38.0);

  const drums = ctx.createGain(); drums.gain.value = 0.95; drums.connect(master);
  const sfx = ctx.createGain(); sfx.gain.value = 0.8; sfx.connect(master);

  // shared noise
  const nbuf = ctx.createBuffer(1, sr * 2, sr);
  { const d = nbuf.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = rand() * 2 - 1; }
  const noise = (t, dur) => {
    const s = ctx.createBufferSource(); s.buffer = nbuf; s.loop = true;
    s.start(t, rand() * 1.5); s.stop(t + dur + 0.05); return s;
  };
  const panner = (p) => { const n = ctx.createStereoPanner(); n.pan.value = p; return n; };

  // ---------- instruments ----------
  function kick(t, v = 1) {
    const o = ctx.createOscillator(); o.type = 'sine';
    o.frequency.setValueAtTime(165, t); o.frequency.exponentialRampToValueAtTime(46, t + 0.12);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.004);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.48);
    o.connect(g); g.connect(drums); o.start(t); o.stop(t + 0.5);
    const n = noise(t, 0.02); const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 2500;
    const ng = ctx.createGain(); ng.gain.setValueAtTime(0.18 * v, t); ng.gain.exponentialRampToValueAtTime(0.001, t + 0.015);
    n.connect(hp); hp.connect(ng); ng.connect(drums);
  }
  function clap(t, v = 0.5) {
    const n = noise(t, 0.35);
    const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 1500; bp.Q.value = 0.9;
    const g = ctx.createGain(); g.gain.setValueAtTime(0, t);
    for (let k = 0; k < 3; k++) {
      const tk = t + k * 0.011;
      g.gain.setValueAtTime(v, tk); g.gain.setTargetAtTime(0.0001, tk + 0.002, 0.004);
    }
    g.gain.setValueAtTime(v * 0.9, t + 0.034); g.gain.setTargetAtTime(0.0001, t + 0.036, 0.07);
    n.connect(bp); bp.connect(g); g.connect(drums);
    const s = ctx.createGain(); s.gain.value = 0.35; g.connect(s); s.connect(verbIn);
  }
  function hat(t, v = 0.12, open = false, pan = 0.15) {
    const n = noise(t, open ? 0.3 : 0.08);
    const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 7600;
    const g = ctx.createGain(); g.gain.setValueAtTime(v, t);
    g.gain.exponentialRampToValueAtTime(0.0008, t + (open ? 0.22 : 0.045));
    const p = panner(pan);
    n.connect(hp); hp.connect(g); g.connect(p); p.connect(drums);
  }
  function bass(t, dur, note, v = 0.36) {
    const fr = midi(note);
    const o1 = ctx.createOscillator(); o1.type = 'sawtooth'; o1.frequency.value = fr;
    const o2 = ctx.createOscillator(); o2.type = 'sine'; o2.frequency.value = fr;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.Q.value = 3;
    lp.frequency.setValueAtTime(900, t); lp.frequency.exponentialRampToValueAtTime(180, t + Math.min(dur, 0.3));
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(v, t + 0.012); g.gain.setTargetAtTime(0.0001, t + dur * 0.8, 0.05);
    const g2 = ctx.createGain(); g2.gain.value = 0.9;
    o1.connect(lp); lp.connect(g); o2.connect(g2); g2.connect(g); g.connect(music);
    o1.start(t); o2.start(t); o1.stop(t + dur + 0.4); o2.stop(t + dur + 0.4);
  }
  function pluck(t, note, v = 0.12, pan = 0, send = 0.5) {
    const fr = midi(note);
    const o = ctx.createOscillator(); o.type = 'triangle'; o.frequency.value = fr;
    const o2 = ctx.createOscillator(); o2.type = 'sine'; o2.frequency.value = fr * 2;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass';
    lp.frequency.setValueAtTime(5200, t); lp.frequency.exponentialRampToValueAtTime(900, t + 0.28);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(v, t + 0.004); g.gain.exponentialRampToValueAtTime(0.0006, t + 0.55);
    const g2 = ctx.createGain(); g2.gain.value = 0.25;
    const p = panner(pan);
    o.connect(lp); o2.connect(g2); g2.connect(lp); lp.connect(g); g.connect(p); p.connect(music);
    const s = ctx.createGain(); s.gain.value = send; p.connect(s); s.connect(delayIn);
    const r = ctx.createGain(); r.gain.value = 0.3; p.connect(r); r.connect(verbIn);
    o.start(t); o2.start(t); o.stop(t + 0.7); o2.stop(t + 0.7);
  }
  function pad(t, dur, notes, v = 0.05, attack = 1.0, release = 1.4) {
    const out = ctx.createGain();
    out.gain.setValueAtTime(0.0001, t);
    out.gain.linearRampToValueAtTime(v, t + attack);
    out.gain.setValueAtTime(v, t + dur);
    out.gain.linearRampToValueAtTime(0.0001, t + dur + release);
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 2400; lp.Q.value = 0.4;
    lp.connect(out); out.connect(music);
    const r = ctx.createGain(); r.gain.value = 0.6; out.connect(r); r.connect(verbIn);
    notes.forEach((n, i) => {
      for (const det of [-9, 8]) {
        const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = midi(n); o.detune.value = det;
        const p = panner(((i % 2) ? 0.35 : -0.35) * (det > 0 ? 1 : -1));
        const g = ctx.createGain(); g.gain.value = 0.5 / notes.length;
        o.connect(g); g.connect(p); p.connect(lp);
        o.start(t); o.stop(t + dur + release + 0.1);
      }
    });
  }
  function bell(t, note, v = 0.12, pan = 0) {
    const fr = midi(note);
    const out = ctx.createGain(); out.gain.value = v;
    const p = panner(pan); out.connect(p); p.connect(sfx);
    const r = ctx.createGain(); r.gain.value = 0.7; p.connect(r); r.connect(verbIn);
    const d = ctx.createGain(); d.gain.value = 0.35; p.connect(d); d.connect(delayIn);
    [[1, 1, 1.8], [2.76, 0.35, 0.9], [5.4, 0.12, 0.45], [2, 0.25, 1.2]].forEach(([m, a, dec]) => {
      const o = ctx.createOscillator(); o.type = 'sine'; o.frequency.value = fr * m;
      const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t);
      g.gain.linearRampToValueAtTime(a, t + 0.003); g.gain.exponentialRampToValueAtTime(0.0005, t + dec);
      o.connect(g); g.connect(out); o.start(t); o.stop(t + dec + 0.05);
    });
  }
  function whoosh(t, dur, v = 0.22, f0 = 300, f1 = 5000, pan = 0) {
    const n = noise(t, dur);
    const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.Q.value = 1.1;
    bp.frequency.setValueAtTime(f0, t); bp.frequency.exponentialRampToValueAtTime(f1, t + dur);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(v, t + dur * 0.65); g.gain.exponentialRampToValueAtTime(0.0005, t + dur);
    const p = panner(pan);
    n.connect(bp); bp.connect(g); g.connect(p); p.connect(sfx);
    const r = ctx.createGain(); r.gain.value = 0.4; p.connect(r); r.connect(verbIn);
  }
  function riser(t0, t1, v = 0.2) {
    whoosh(t0, t1 - t0, v, 250, 7000);
    const o = ctx.createOscillator(); o.type = 'sine';
    o.frequency.setValueAtTime(220, t0); o.frequency.exponentialRampToValueAtTime(1760, t1);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(v * 0.25, t1 - 0.02); g.gain.linearRampToValueAtTime(0.0001, t1);
    o.connect(g); g.connect(sfx); const r = ctx.createGain(); r.gain.value = 0.5; g.connect(r); r.connect(verbIn);
    o.start(t0); o.stop(t1 + 0.05);
  }
  function reverseSwell(tEnd, dur, v = 0.28) {
    const t = tEnd - dur; const n = noise(t, dur);
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass';
    lp.frequency.setValueAtTime(800, t); lp.frequency.exponentialRampToValueAtTime(9000, tEnd);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0005, t);
    g.gain.exponentialRampToValueAtTime(v, tEnd - 0.01); g.gain.linearRampToValueAtTime(0, tEnd);
    n.connect(lp); lp.connect(g); g.connect(sfx);
  }
  function impact(t, v = 1) {
    const o = ctx.createOscillator(); o.type = 'sine';
    o.frequency.setValueAtTime(78, t); o.frequency.exponentialRampToValueAtTime(30, t + 1.4);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.9 * v, t + 0.01); g.gain.exponentialRampToValueAtTime(0.001, t + 2.2);
    o.connect(g); g.connect(drums); o.start(t); o.stop(t + 2.3);
    const n = noise(t, 2.4); const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 2600;
    const ng = ctx.createGain(); ng.gain.setValueAtTime(0.16 * v, t); ng.gain.setTargetAtTime(0.0001, t + 0.05, 0.55);
    n.connect(hp); hp.connect(ng); ng.connect(sfx);
    const r = ctx.createGain(); r.gain.value = 0.8; ng.connect(r); r.connect(verbIn);
    kick(t, 1.1 * v);
  }
  function tick(t, freq = 2600, v = 0.08, pan = 0) {
    const o = ctx.createOscillator(); o.type = 'sine'; o.frequency.value = freq;
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(v, t + 0.002); g.gain.exponentialRampToValueAtTime(0.0005, t + 0.07);
    const p = panner(pan); o.connect(g); g.connect(p); p.connect(sfx);
    const r = ctx.createGain(); r.gain.value = 0.3; p.connect(r); r.connect(verbIn);
    o.start(t); o.stop(t + 0.1);
  }
  function mouseClick(t) {
    const n = noise(t, 0.02); const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 3200; bp.Q.value = 2;
    const g = ctx.createGain(); g.gain.setValueAtTime(0.5, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.012);
    n.connect(bp); bp.connect(g); g.connect(sfx);
    const n2 = noise(t + 0.075, 0.02); const g2 = ctx.createGain(); g2.gain.setValueAtTime(0.3, t + 0.075);
    g2.gain.exponentialRampToValueAtTime(0.001, t + 0.085); const bp2 = ctx.createBiquadFilter(); bp2.type = 'bandpass'; bp2.frequency.value = 2400;
    n2.connect(bp2); bp2.connect(g2); g2.connect(sfx);
  }
  function drop(t) { // descending blip: quota falls
    const o = ctx.createOscillator(); o.type = 'triangle';
    o.frequency.setValueAtTime(1400, t); o.frequency.exponentialRampToValueAtTime(380, t + 0.35);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.12, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0005, t + 0.4);
    o.connect(g); g.connect(sfx); const r = ctx.createGain(); r.gain.value = 0.4; g.connect(r); r.connect(verbIn);
    o.start(t); o.stop(t + 0.45);
  }

  // ---------- arrangement ----------
  // Pads: whole song, one per chord
  CHORDS.forEach((c, i) => {
    const next = CHORDS[i + 1] ? CHORDS[i + 1].t : DURATION;
    const dur = next - c.t;
    const v = c.t < 8 ? 0.06 : (c.t >= 32 && c.t < 38) ? 0.075 : c.t >= 38 ? 0.08 : 0.05;
    pad(c.t, dur - 0.2, c.notes, v, c.t === 0 ? 2.2 : 0.35, c.t >= 38 ? 2.0 : 0.9);
  });

  // Intro sparkles: the star forms, rings draw
  bell(0.55, 86, 0.10, 0.1);
  [[1.0, 81], [1.25, 85], [1.5, 88], [1.75, 90]].forEach(([t, n], i) => pluck(t, n, 0.06, i % 2 ? 0.4 : -0.4, 0.7));
  whoosh(1.55, 1.3, 0.16, 400, 6000, -0.2);
  [2.0, 2.25, 2.5, 2.75].forEach((t, i) => tick(t, 2200 + i * 300, 0.04, 0.3 - i * 0.2));
  whoosh(2.55, 1.0, 0.12, 200, 2200, 0.2); // slab materialises
  bell(3.5, 74, 0.08, -0.2);
  [4.0, 5.0, 6.0, 7.0].forEach((t, i) => pluck(t, [74, 78, 81, 85][i], 0.07, i % 2 ? 0.35 : -0.35, 0.6));
  riser(5.4, 8.0, 0.22);
  reverseSwell(8.0, 1.6, 0.3);

  // THE DROP
  impact(8.0, 1.0);

  // Ring gauges fill on the beats
  bell(8.0, 81, 0.10, -0.3); bell(8.5, 85, 0.10, 0.0); bell(9.0, 88, 0.10, 0.3);
  // provider words
  [10.0, 10.5, 11.0].forEach((t, i) => tick(t, 1800 + i * 400, 0.05));

  // icon -> menu bar
  whoosh(11.8, 0.9, 0.2, 300, 5000, 0.3);
  // cursor click & popover open
  mouseClick(16.0);
  whoosh(16.02, 0.55, 0.2, 4500, 500, 0.1);
  // tile gauges
  [17.5, 18.0, 18.5, 19.0].forEach((t, i) => bell(t, [74, 78, 81, 86][i], 0.065, -0.3 + i * 0.2));
  // tab switches
  [20.0, 22.0, 24.0].forEach((t) => { whoosh(t - 0.18, 0.3, 0.1, 1200, 6000); tick(t, 3000, 0.06); });
  // explode
  whoosh(25.6, 1.4, 0.16, 250, 3000, 0.3);
  // activity bars build (16ths)
  for (let i = 0; i < 14; i++) tick(26.5 + i * 0.125, 1500 + i * 120, 0.025, -0.4 + i * 0.06);
  // quota drop + notification
  drop(28.5);
  bell(29.0, 88, 0.09, 0.4); bell(29.12, 93, 0.07, 0.4);
  // collapse
  whoosh(31.2, 0.8, 0.14, 3000, 400, -0.2);
  // breakdown accents
  bell(32.5, 78, 0.09, 0); bell(33.9, 81, 0.06, -0.3); bell(34.8, 85, 0.06, 0.3);
  // lift into the finale
  riser(36.0, 38.0, 0.26);
  reverseSwell(38.0, 1.2, 0.3);
  impact(38.0, 1.05);
  bell(38.0, 86, 0.11, 0); bell(38.5, 90, 0.07, 0.3); bell(39.0, 93, 0.05, -0.3);
  [39.8, 40.4].forEach((t) => tick(t, 2400, 0.04));

  // Drums
  const kicks = [];
  for (let t = 8.0; t < 32.0 - 1e-6; t += BEAT) {
    if (t > 15.4 && t < 16.0) continue; // breath before the click
    kicks.push(t);
  }
  kicks.push(38.0, 39.0, 40.0, 41.0);
  kicks.forEach((t) => { if (t !== 8.0 && t !== 38.0) kick(t, t >= 38 ? 0.6 : 0.85); });
  // heartbeat in the breakdown
  [32.0, 33.0, 34.0, 35.0].forEach((t) => kick(t, 0.35));

  // sidechain duck
  duck.gain.setValueAtTime(1, 0);
  [...kicks, 32.0, 33.0, 34.0, 35.0].sort((a, b) => a - b).forEach((t) => {
    duck.gain.setValueAtTime(0.42, t);
    duck.gain.setTargetAtTime(1.0, t + 0.03, 0.09);
  });

  for (let t = 12.0; t < 32.0 - 1e-6; t += BEAT * 2) {
    if (t > 15.4 && t < 16.0) continue;
    clap(t + BEAT, 0.42);
  }
  for (let t = 8.0; t < 32.0 - 1e-6; t += BEAT) {
    hat(t + BEAT / 2, 0.1, ((t * 2) % 4) === 3, 0.2);
    if (t >= 24.0) hat(t + BEAT / 4, 0.045, false, -0.25), hat(t + 3 * BEAT / 4, 0.045, false, -0.25);
  }
  // snare roll into the finale
  for (let i = 0; i < 16; i++) clap(36.0 + i * 0.125, 0.08 + i * 0.022);

  // Bass: pumping eighths
  for (let t = 8.0; t < 32.0 - 1e-6; t += BEAT / 2) {
    if (t > 15.4 && t < 16.0) continue;
    const c = chordAt(t);
    const off = ((t * 4) % 2) === 1;
    bass(t, BEAT / 2 - 0.02, c.root + (off ? 12 : 0), off ? 0.26 : 0.34);
  }
  bass(38.0, 3.8, 38, 0.4);

  // Arp
  const pattern = [0, 2, 1, 3, 2, 4, 3, 1];
  let step = 0;
  for (let t = 8.0; t < 32.0 - 1e-6; t += (t >= 24 ? BEAT / 4 : BEAT / 2)) {
    const c = chordAt(t);
    const n = c.notes[pattern[step % pattern.length] % c.notes.length] + 24;
    pluck(t, n, t >= 24 ? 0.05 : 0.065, step % 2 ? 0.45 : -0.45, 0.35);
    step++;
  }
  // breakdown: slow arp
  for (let t = 32.0; t < 36.0; t += BEAT) {
    const c = chordAt(t); pluck(t, c.notes[(step++) % c.notes.length] + 24, 0.05, Math.sin(t) * 0.5, 0.6);
  }
  // finale arp, settling
  for (let t = 38.0; t < 42.0; t += BEAT / 2) {
    const c = chordAt(t); pluck(t, c.notes[pattern[(step++) % 8] % c.notes.length] + 24, 0.045 * (1 - (t - 38) / 5), step % 2 ? 0.4 : -0.4, 0.5);
  }
}

// ---------- WAV export (for the MP4 mux) ----------
export function toWavBase64(buf) {
  const ch = buf.numberOfChannels, len = buf.length, sr = buf.sampleRate;
  const data = new DataView(new ArrayBuffer(44 + len * ch * 2));
  const w = (o, s) => { for (let i = 0; i < s.length; i++) data.setUint8(o + i, s.charCodeAt(i)); };
  w(0, 'RIFF'); data.setUint32(4, 36 + len * ch * 2, true); w(8, 'WAVE'); w(12, 'fmt ');
  data.setUint32(16, 16, true); data.setUint16(20, 1, true); data.setUint16(22, ch, true);
  data.setUint32(24, sr, true); data.setUint32(28, sr * ch * 2, true); data.setUint16(32, ch * 2, true);
  data.setUint16(34, 16, true); w(36, 'data'); data.setUint32(40, len * ch * 2, true);
  const chans = []; for (let c = 0; c < ch; c++) chans.push(buf.getChannelData(c));
  let o = 44;
  for (let i = 0; i < len; i++) for (let c = 0; c < ch; c++) {
    const s = Math.max(-1, Math.min(1, chans[c][i])); data.setInt16(o, s < 0 ? s * 0x8000 : s * 0x7fff, true); o += 2;
  }
  const bytes = new Uint8Array(data.buffer); let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
