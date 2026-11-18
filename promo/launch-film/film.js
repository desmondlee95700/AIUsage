// AIUsage launch film: one continuous WebGL shot.
// Everything is a pure function of time t (seconds), so the film scrubs, loops and renders
// frame-exact. The hero is a single glass slab that morphs: app icon -> menu bar item ->
// popover -> app icon. The UI on it is drawn from the app's own design tokens
// (Sources/DesignSystem/LiquidGlass.swift) and components (LiquidRingGauge, QuotaTile, ...).

import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

export const W = 1920, H = 1080, DURATION = 44;

// ───────────────────────── math ─────────────────────────
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const inv = (a, b, x) => clamp((x - a) / (b - a));
const ss = (a, b, x) => { const t = inv(a, b, x); return t * t * (3 - 2 * t); };
const eInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const eOutExpo = (t) => (t >= 1 ? 1 : 1 - Math.pow(2, -10 * t));
const eOutCubic = (t) => 1 - Math.pow(1 - t, 3);
const eInOutSine = (t) => -(Math.cos(Math.PI * t) - 1) / 2;
// Damped spring step response, same parameters SwiftUI's .spring(response:dampingFraction:) uses
function spring(x, response = 0.5, damping = 0.72) {
  if (x <= 0) return 0;
  const w = (2 * Math.PI) / response, z = Math.min(damping, 0.999), wd = w * Math.sqrt(1 - z * z);
  return 1 - Math.exp(-z * w * x) * (Math.cos(wd * x) + ((z * w) / wd) * Math.sin(wd * x));
}
// Value that springs through a list of [time, value] targets
function springSeq(t, v0, keys, resp = 0.6, damp = 0.8) {
  let v = v0, prev = v0;
  for (const [tk, vk, r, d] of keys) { v += (vk - prev) * spring(t - tk, r ?? resp, d ?? damp); prev = vk; }
  return v;
}
// Design tokens (LiquidGlassTokens)
const METRIC = [0.5, 0.7];   // metricSpring
const STATE = [0.42, 0.78];  // stateSpring

const rgb = (c, a = 1) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
const mixc = (a, b, t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)].map(Math.round);

// LiquidGlassPalette, in sRGB 0-255
const PAL = {
  aiBlue: [64, 122, 250], healthy: [51, 209, 122], moderate: [250, 173, 46], critical: [245, 71, 82],
  credit: [250, 199, 64], antigravity: [71, 138, 250], chatgpt: [41, 189, 133], claude: [217, 115, 64],
};
const level = (f) => (f > 0.3 ? 'healthy' : f > 0.1 ? 'moderate' : 'critical');
const LEVEL_GRAD = { healthy: [[46, 184, 217], PAL.healthy], moderate: [[250, 214, 77], PAL.moderate], critical: [[250, 122, 107], PAL.critical] };

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ───────────────────────── data shown in the UI ─────────────────────────
const PROVIDERS = {
  claude: {
    name: 'Claude', plan: 'Claude Max', color: PAL.claude, img: 'claude', status: '72% left',
    tiles: [
      { title: '5-Hour', caption: 'Rolling burst window', v: 0.72, reset: '2h 14m' },
      { title: 'Weekly', caption: 'All models', v: 0.58, reset: 'Thu 09:00' },
      { title: 'Sonnet', caption: 'Weekly Sonnet limit', v: 0.81, reset: 'Thu 09:00' },
      { title: 'Opus', caption: 'Weekly Opus limit', v: 0.34, reset: 'Thu 09:00' },
    ],
    activity: 'Claude Activity', seed: 3, avg: '1.4M', peak: '3.1M',
  },
  chatgpt: {
    name: 'ChatGPT', plan: 'ChatGPT Pro', color: PAL.chatgpt, img: 'chatgpt', status: '64% left',
    tiles: [
      { title: '5-Hour', caption: 'Codex burst window', v: 0.64, reset: '3h 02m' },
      { title: 'Weekly', caption: 'All Codex usage', v: 0.41, reset: 'Mon 14:20' },
    ],
    extra: { kind: 'credits', label: 'Reset credits', value: '2 available', button: 'Use Reset' },
    activity: 'Codex Activity', seed: 11, avg: '0.9M', peak: '2.2M',
  },
  antigravity: {
    name: 'Antigravity', plan: 'Google AI Ultra', color: PAL.antigravity, img: 'antigravity', status: '88% left',
    tiles: [
      { title: '5-Hour', caption: 'Model quota window', v: 0.88, reset: '4h 41m' },
      { title: 'Weekly', caption: 'All models', v: 0.76, reset: 'Sun 18:00' },
    ],
    extra: { kind: 'meters', rows: [['Prompt credits', '4,200 / 5,000', 0.84], ['Flow credits', '1,150 / 2,000', 0.575]] },
    activity: 'Antigravity Activity', seed: 23, avg: '0.6M', peak: '1.7M',
  },
};
for (const p of Object.values(PROVIDERS)) {
  const r = mulberry32(p.seed);
  p.bars = Array.from({ length: 14 }, (_, i) => 0.22 + 0.78 * Math.pow(r(), 0.8) * (i === 13 ? 1 : 0.9));
  p.bars[13] = Math.max(p.bars[13], 0.7);
}
// Which provider the popover shows, and when it switched to it
const TABS = [[0, 'claude'], [20.0, 'chatgpt'], [22.0, 'antigravity'], [24.0, 'claude']];
const TAB_ORDER = ['claude', 'chatgpt', 'antigravity'];
function tabState(t) {
  let cur = TABS[0], prev = null;
  for (const k of TABS) if (k[0] <= t) { prev = cur; cur = k; }
  return { id: cur[1], since: cur[0] === 0 ? 16.9 : cur[0], prevId: cur[0] === 0 ? null : prev[1] };
}
// Claude weekly drops at 28.5 (the low-quota alert moment)
const claudeWeekly = (t) => springSeq(t, 0.58, [[28.5, 0.28, ...METRIC]]);

// ───────────────────────── canvas helpers ─────────────────────────
const FONT = '-apple-system, "SF Pro Display", "SF Pro Text", system-ui, "Helvetica Neue", sans-serif';
const ROUNDED = '"SF Pro Rounded", ui-rounded, -apple-system, system-ui, sans-serif';
const MONO = '"SF Mono", ui-monospace, Menlo, monospace';
const font = (w, px, fam = FONT) => `${w} ${px}px ${fam}`;

function rr(ctx, x, y, w, h, r) {
  r = Math.max(0, Math.min(r, w / 2, h / 2));
  ctx.beginPath(); ctx.roundRect(x, y, w, h, r);
}
function specularStroke(ctx, x, y, w, h, r, lw, intensity = 1) {
  const g = ctx.createLinearGradient(x, y, x + w, y + h);
  g.addColorStop(0, `rgba(255,255,255,${0.32 * intensity})`);
  g.addColorStop(0.45, `rgba(255,255,255,${0.10 * intensity})`);
  g.addColorStop(1, `rgba(255,255,255,${0.03 * intensity})`);
  rr(ctx, x + lw / 2, y + lw / 2, w - lw, h - lw, r); ctx.strokeStyle = g; ctx.lineWidth = lw; ctx.stroke();
}
// L1 card: .liquidGlassCard
function glassCard(ctx, x, y, w, h, r, P, tint, a = 1) {
  ctx.save(); ctx.globalAlpha *= a;
  rr(ctx, x, y, w, h, r);
  const g = ctx.createLinearGradient(x, y, x, y + h);
  g.addColorStop(0, 'rgba(255,255,255,0.075)'); g.addColorStop(1, 'rgba(255,255,255,0.035)');
  ctx.fillStyle = g; ctx.fill();
  if (tint) {
    const rg = ctx.createRadialGradient(x + w * 0.15, y, 0, x + w * 0.15, y, w * 0.9);
    rg.addColorStop(0, rgb(tint, 0.13)); rg.addColorStop(1, rgb(tint, 0));
    rr(ctx, x, y, w, h, r); ctx.fillStyle = rg; ctx.fill();
  }
  // inner rim highlight
  const ih = ctx.createLinearGradient(x, y, x, y + h * 0.5);
  ih.addColorStop(0, 'rgba(255,255,255,0.10)'); ih.addColorStop(1, 'rgba(255,255,255,0)');
  rr(ctx, x + P, y + P, w - 2 * P, h - 2 * P, r - P); ctx.strokeStyle = ih; ctx.lineWidth = P * 0.8; ctx.stroke();
  specularStroke(ctx, x, y, w, h, r, P, 1);
  ctx.restore();
}

// LiquidRingGauge
function ringGauge(ctx, cx, cy, size, lw, fraction, P, showLabel = true, a = 1) {
  const f = clamp(fraction), lv = level(f), col = PAL[lv], [c0, c1] = LEVEL_GRAD[lv];
  const r = (size - lw) / 2;
  ctx.save(); ctx.globalAlpha *= a;
  ctx.lineCap = 'round';
  ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.strokeStyle = 'rgba(255,255,255,0.09)'; ctx.lineWidth = lw; ctx.stroke();
  if (showLabel) {
    const rg = ctx.createRadialGradient(cx, cy, 0, cx, cy, size / 2 - lw);
    rg.addColorStop(0, rgb(col, 0.16)); rg.addColorStop(1, rgb(col, 0));
    ctx.beginPath(); ctx.arc(cx, cy, size / 2 - lw, 0, Math.PI * 2); ctx.fillStyle = rg; ctx.fill();
  }
  if (f > 0.002) {
    const cg = ctx.createConicGradient(-Math.PI / 2, cx, cy);
    cg.addColorStop(0, rgb(c0)); cg.addColorStop(Math.max(f, 0.01), rgb(c1)); cg.addColorStop(1, rgb(c1));
    ctx.shadowColor = rgb(col, 0.55); ctx.shadowBlur = lw * 1.6;
    ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * f);
    ctx.strokeStyle = cg; ctx.lineWidth = lw; ctx.stroke(); ctx.shadowBlur = 0;
  }
  if (showLabel) {
    const pct = Math.round(f * 100);
    ctx.textBaseline = 'alphabetic'; ctx.fillStyle = '#fff';
    ctx.font = font(700, size * 0.27, ROUNDED);
    const nw = ctx.measureText(String(pct)).width;
    ctx.font = font(600, size * 0.15, ROUNDED);
    const pw = ctx.measureText('%').width;
    const x0 = cx - (nw + pw + 0.5 * P) / 2, by = cy + size * 0.06;
    ctx.font = font(700, size * 0.27, ROUNDED); ctx.textAlign = 'left'; ctx.fillText(String(pct), x0, by);
    ctx.font = font(600, size * 0.15, ROUNDED); ctx.fillStyle = 'rgba(255,255,255,0.65)'; ctx.fillText('%', x0 + nw + 0.5 * P, by);
    ctx.font = font(500, size * 0.13, ROUNDED); ctx.textAlign = 'center'; ctx.fillText('left', cx, by + size * 0.16);
  }
  ctx.restore();
}
// LiquidMeterBar
function meterBar(ctx, x, y, w, h, fraction, tint, a = 1) {
  const f = clamp(fraction); const lv = level(f);
  const cols = tint ? [tint.map((v) => v), tint] : LEVEL_GRAD[lv];
  ctx.save(); ctx.globalAlpha *= a;
  rr(ctx, x, y, w, h, h / 2); ctx.fillStyle = 'rgba(255,255,255,0.08)'; ctx.fill();
  if (f > 0) {
    const fw = Math.max(h, w * f);
    const g = ctx.createLinearGradient(x, 0, x + fw, 0); g.addColorStop(0, rgb(cols[0], tint ? 0.7 : 1)); g.addColorStop(1, rgb(cols[1]));
    ctx.shadowColor = rgb(tint || PAL[lv], 0.5); ctx.shadowBlur = h * 1.2;
    rr(ctx, x, y, fw, h, h / 2); ctx.fillStyle = g; ctx.fill(); ctx.shadowBlur = 0;
    const s = ctx.createLinearGradient(0, y, 0, y + h / 2); s.addColorStop(0, 'rgba(255,255,255,0.35)'); s.addColorStop(1, 'rgba(255,255,255,0)');
    rr(ctx, x, y, fw, h, h / 2); ctx.fillStyle = s; ctx.fill();
  }
  ctx.restore();
}
// Small vector stand-ins for the SF Symbols the app uses
function symbol(ctx, name, cx, cy, s, color) {
  ctx.save(); ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = s * 0.12; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  const h = s / 2;
  if (name === 'gauge') {
    ctx.beginPath(); ctx.arc(cx, cy + h * 0.35, h * 0.85, Math.PI * 1.05, Math.PI * 1.95); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(cx, cy + h * 0.35); ctx.lineTo(cx + h * 0.45, cy - h * 0.2); ctx.stroke();
    ctx.beginPath(); ctx.arc(cx, cy + h * 0.35, s * 0.09, 0, 7); ctx.fill();
  } else if (name === 'chart') {
    [[-0.55, 0.45], [-0.05, 0.85], [0.45, 0.65]].forEach(([dx, hh]) => { rr(ctx, cx + dx * h - s * 0.1, cy + h * 0.7 - hh * s * 0.7, s * 0.2, hh * s * 0.7, s * 0.05); ctx.fill(); });
  } else if (name === 'sliders') {
    [-0.45, 0, 0.45].forEach((dy, i) => {
      ctx.beginPath(); ctx.moveTo(cx - h * 0.8, cy + dy * h); ctx.lineTo(cx + h * 0.8, cy + dy * h); ctx.stroke();
      ctx.beginPath(); ctx.arc(cx + [-0.35, 0.3, -0.05][i] * h, cy + dy * h, s * 0.11, 0, 7); ctx.fill();
    });
  } else if (name === 'refresh') {
    ctx.beginPath(); ctx.arc(cx, cy, h * 0.7, -Math.PI * 0.35, Math.PI * 1.45); ctx.stroke();
    const ax = cx + h * 0.7 * Math.cos(-Math.PI * 0.35), ay = cy + h * 0.7 * Math.sin(-Math.PI * 0.35);
    ctx.beginPath(); ctx.moveTo(ax - s * 0.2, ay - s * 0.06); ctx.lineTo(ax + s * 0.02, ay + s * 0.02); ctx.lineTo(ax - s * 0.04, ay - s * 0.24); ctx.stroke();
  } else if (name === 'ellipsis') {
    [-0.5, 0, 0.5].forEach((dx) => { ctx.beginPath(); ctx.arc(cx + dx * h, cy, s * 0.08, 0, 7); ctx.fill(); });
  } else if (name === 'clock') {
    ctx.lineWidth = s * 0.1; ctx.beginPath(); ctx.arc(cx, cy, h * 0.75, 0, 7); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(cx, cy - h * 0.4); ctx.lineTo(cx, cy); ctx.lineTo(cx + h * 0.3, cy + h * 0.15); ctx.stroke();
  } else if (name === 'arrow') {
    ctx.beginPath(); ctx.moveTo(cx - h * 0.4, cy + h * 0.4); ctx.lineTo(cx + h * 0.4, cy - h * 0.4); ctx.moveTo(cx - h * 0.1, cy - h * 0.4); ctx.lineTo(cx + h * 0.4, cy - h * 0.4); ctx.lineTo(cx + h * 0.4, cy + h * 0.1); ctx.stroke();
  } else if (name === 'bell') {
    ctx.beginPath(); ctx.moveTo(cx - h * 0.6, cy + h * 0.4); ctx.quadraticCurveTo(cx - h * 0.5, cy - h * 0.7, cx, cy - h * 0.7); ctx.quadraticCurveTo(cx + h * 0.5, cy - h * 0.7, cx + h * 0.6, cy + h * 0.4); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.arc(cx, cy + h * 0.6, s * 0.1, 0, 7); ctx.fill();
  } else if (name === 'wifi') {
    for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc(cx, cy + h * 0.55, h * (0.35 + i * 0.32), -Math.PI * 0.75, -Math.PI * 0.25); ctx.stroke(); }
  } else if (name === 'battery') {
    ctx.lineWidth = s * 0.07; rr(ctx, cx - h * 0.95, cy - h * 0.4, h * 1.75, h * 0.8, h * 0.2); ctx.stroke();
    rr(ctx, cx - h * 0.82, cy - h * 0.27, h * 1.2, h * 0.54, h * 0.1); ctx.fill();
    rr(ctx, cx + h * 0.86, cy - h * 0.15, h * 0.12, h * 0.3, h * 0.05); ctx.fill();
  } else if (name === 'toggles') {
    ctx.lineWidth = s * 0.08;
    rr(ctx, cx - h * 0.8, cy - h * 0.6, h * 1.6, h * 0.5, h * 0.25); ctx.stroke(); ctx.beginPath(); ctx.arc(cx + h * 0.55, cy - h * 0.35, h * 0.17, 0, 7); ctx.fill();
    rr(ctx, cx - h * 0.8, cy + h * 0.1, h * 1.6, h * 0.5, h * 0.25); ctx.stroke(); ctx.beginPath(); ctx.arc(cx - h * 0.55, cy + h * 0.35, h * 0.17, 0, 7); ctx.fill();
  } else if (name === 'search') {
    ctx.beginPath(); ctx.arc(cx - h * 0.15, cy - h * 0.15, h * 0.5, 0, 7); ctx.stroke(); ctx.beginPath(); ctx.moveTo(cx + h * 0.22, cy + h * 0.22); ctx.lineTo(cx + h * 0.7, cy + h * 0.7); ctx.stroke();
  }
  ctx.restore();
}

// ───────────────────────── the film ─────────────────────────
export class Film {
  constructor(canvas) {
    this.canvas = canvas;
    const r = (this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true, alpha: false }));
    r.setPixelRatio(1); r.setSize(W, H, false);
    r.toneMapping = THREE.ACESFilmicToneMapping; r.toneMappingExposure = 1.08;
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.sortObjects = true;
    this.maxAniso = r.capabilities.getMaxAnisotropy();

    const scene = (this.scene = new THREE.Scene());
    const pmrem = new THREE.PMREMGenerator(r);
    scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.035).texture;
    scene.environmentIntensity = 1.0;

    const cam = (this.camera = new THREE.PerspectiveCamera(30, W / H, 0.1, 200));
    scene.add(cam);

    const key = new THREE.DirectionalLight(0xffffff, 1.6); key.position.set(-4, 6, 8); scene.add(key);
    const rim = new THREE.DirectionalLight(0x9fc4ff, 1.2); rim.position.set(6, 2, -5); scene.add(rim);
    this.sweep = new THREE.PointLight(0xdfe9ff, 0, 14, 1.6); scene.add(this.sweep);
    scene.add(new THREE.AmbientLight(0xffffff, 0.25));

    this.images = {};
    this.ready = this.loadImages().then(() => this.build());
  }

  async loadImages() {
    const names = ['appicon', 'claude', 'chatgpt', 'antigravity'];
    await Promise.all(names.map((n) => new Promise((res, rej) => {
      const im = new Image(); im.onload = () => { this.images[n] = im; res(); }; im.onerror = rej;
      im.src = new URL(`./assets/${n}.png`, import.meta.url).href;
    })));
    if (document.fonts) await document.fonts.ready;
  }

  canvasTex(w, h) {
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = this.maxAniso;
    tex.minFilter = THREE.LinearMipmapLinearFilter; tex.generateMipmaps = true;
    return { c, ctx: c.getContext('2d'), tex };
  }
  uiPlane(w, h, order = 3) {
    const t = this.canvasTex(w, h);
    const mat = new THREE.MeshBasicMaterial({ map: t.tex, transparent: true, toneMapped: false, depthWrite: false });
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), mat); mesh.renderOrder = order;
    return { ...t, mesh, mat };
  }

  build() {
    const scene = this.scene, cam = this.camera;

    // ── background: soft daylight gradient with drifting colour fields
    const bgMat = new THREE.ShaderMaterial({
      depthWrite: false, depthTest: false, toneMapped: false,
      uniforms: { uTime: { value: 0 }, uTint: { value: new THREE.Color() }, uTintAmt: { value: 0 }, uLift: { value: 0 } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: `
        varying vec2 vUv; uniform float uTime; uniform vec3 uTint; uniform float uTintAmt; uniform float uLift;
        float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }
        float blob(vec2 p, vec2 c, vec2 r){ vec2 d = (p - c) / r; return exp(-dot(d,d)); }
        void main(){
          vec2 p = vUv; p.x *= 1.7778;
          vec3 top = vec3(0.955, 0.965, 0.990);
          vec3 bot = vec3(0.860, 0.860, 0.945);
          vec3 col = mix(bot, top, smoothstep(-0.1, 1.05, vUv.y));
          float tt = uTime * 0.12;
          col = mix(col, vec3(0.760, 0.900, 0.995), 0.55 * blob(p, vec2(0.35 + 0.12*sin(tt*1.3), 0.78 + 0.06*cos(tt)), vec2(0.75, 0.42)));
          col = mix(col, vec3(0.840, 0.800, 0.985), 0.55 * blob(p, vec2(1.45 + 0.1*cos(tt*0.9), 0.25 + 0.08*sin(tt*1.1)), vec2(0.8, 0.5)));
          col = mix(col, vec3(0.990, 0.930, 0.900), 0.25 * blob(p, vec2(1.25 + 0.15*sin(tt*0.7), 0.95), vec2(0.6, 0.35)));
          col = mix(col, uTint, uTintAmt * blob(p, vec2(1.1, 0.35), vec2(0.9, 0.55)));
          col += uLift;
          float v = length(vUv - 0.5); col *= 1.0 - 0.10 * smoothstep(0.35, 0.85, v);
          col += (hash(gl_FragCoord.xy + fract(uTime)) - 0.5) / 255.0 * 1.6;
          gl_FragColor = vec4(col, 1.0);
        }`,
    });
    this.bgMat = bgMat;
    const bg = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), bgMat);
    bg.renderOrder = -10; bg.frustumCulled = false; bg.position.z = -150;
    const bh = 2 * 150 * Math.tan(THREE.MathUtils.degToRad(17)); bg.scale.set(bh * 1.78 * 1.05, bh * 1.05, 1);
    cam.add(bg);

    // ── ambient dust (depth cue) + the spark that becomes the star
    const N = 260, rnd = mulberry32(5);
    const pos = new Float32Array(N * 3), seed = new Float32Array(N * 4);
    for (let i = 0; i < N; i++) {
      seed[i * 4] = (rnd() - 0.5) * 26; seed[i * 4 + 1] = (rnd() - 0.5) * 14; seed[i * 4 + 2] = -8 + rnd() * 12; seed[i * 4 + 3] = rnd();
    }
    const pg = new THREE.BufferGeometry(); pg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    const sizes = new Float32Array(N); for (let i = 0; i < N; i++) sizes[i] = 0.5 + rnd() * 1.5;
    pg.setAttribute('aSize', new THREE.BufferAttribute(sizes, 1));
    const alphas = new Float32Array(N); pg.setAttribute('aAlpha', new THREE.BufferAttribute(alphas, 1));
    this.dust = { pos, seed, alphas, geo: pg, N };
    const pm = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, toneMapped: false,
      uniforms: { uScale: { value: H / 2 } },
      vertexShader: `attribute float aSize; attribute float aAlpha; varying float vA; uniform float uScale;
        void main(){ vec4 mv = modelViewMatrix * vec4(position,1.0); gl_Position = projectionMatrix * mv; gl_PointSize = aSize * uScale * 0.018 / -mv.z * 6.0; vA = aAlpha; }`,
      fragmentShader: `varying float vA; void main(){ float d = length(gl_PointCoord - 0.5); float a = smoothstep(0.5, 0.0, d); gl_FragColor = vec4(0.42, 0.58, 0.98, a * vA); }`,
    });
    const pts = new THREE.Points(pg, pm); pts.frustumCulled = false; pts.renderOrder = 8; scene.add(pts);

    // ── HERO: one slab that is the icon, the menu bar item and the popover
    const hero = (this.hero = new THREE.Group()); scene.add(hero);
    this.slabMat = new THREE.MeshPhysicalMaterial({
      color: 0x0b1122, roughness: 0.16, metalness: 0.15, clearcoat: 1, clearcoatRoughness: 0.05,
      iridescence: 0.85, iridescenceIOR: 1.7, iridescenceThicknessRange: [180, 720],
      envMapIntensity: 1.6, transparent: true, opacity: 1,
    });
    this.slab = new THREE.Mesh(new THREE.BufferGeometry(), this.slabMat); this.slab.renderOrder = 1; hero.add(this.slab);
    this.slabKey = '';

    // face: the UI drawn on the slab's front
    this.PPU = 290; // canvas px per world unit
    this.face = this.uiPlane(1024, 1600, 2);
    this.face.tex.wrapS = this.face.tex.wrapT = THREE.ClampToEdgeWrapping;
    hero.add(this.face.mesh);

    // popover cards (lift off the face for the exploded view)
    const P = 2.6; this.cardP = P;
    this.cards = {
      plan: { pt: [14, 118, 352, 60] },
      rate: { pt: [14, 190, 352, 296] },
      act: { pt: [14, 498, 352, 88] },
    };
    for (const k of Object.keys(this.cards)) {
      const c = this.cards[k]; const [, , w, h] = c.pt; const pad = 24;
      Object.assign(c, this.uiPlane(Math.ceil(w * P + pad * 2), Math.ceil(h * P + pad * 2), 3), { pad });
      hero.add(c.mesh);
    }

    // star (four-point crystal from the icon)
    const sg = new THREE.BufferGeometry(); const v = [];
    const outer = []; for (let k = 0; k < 8; k++) {
      const a = Math.PI / 2 - (k * Math.PI) / 4; const R = k % 2 ? 0.17 : (k % 4 === 0 ? 0.62 : 0.56);
      outer.push([Math.cos(a) * R, Math.sin(a) * R, 0]);
    }
    const F = [0, 0, 0.2], B = [0, 0, -0.2];
    for (let k = 0; k < 8; k++) { const a = outer[k], b = outer[(k + 1) % 8]; v.push(...F, ...a, ...b, ...B, ...b, ...a); }
    sg.setAttribute('position', new THREE.Float32BufferAttribute(v, 3)); sg.computeVertexNormals();
    this.starMat = new THREE.MeshPhysicalMaterial({
      color: 0xa8dcff, emissive: 0x2d6bff, emissiveIntensity: 0.9, metalness: 0.05, roughness: 0.08,
      iridescence: 1, iridescenceIOR: 1.9, clearcoat: 1, flatShading: true, envMapIntensity: 2.0, transparent: true,
    });
    this.star = new THREE.Mesh(sg, this.starMat); this.star.renderOrder = 6; hero.add(this.star);
    // star glow sprite
    const gl = this.canvasTex(256, 256); {
      const g = gl.ctx.createRadialGradient(128, 128, 0, 128, 128, 128);
      g.addColorStop(0, 'rgba(120,190,255,0.9)'); g.addColorStop(0.25, 'rgba(70,140,255,0.35)'); g.addColorStop(1, 'rgba(60,110,255,0)');
      gl.ctx.fillStyle = g; gl.ctx.fillRect(0, 0, 256, 256); gl.tex.needsUpdate = true;
    }
    this.glow = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({ map: gl.tex, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false }));
    this.glow.renderOrder = 5; hero.add(this.glow);

    // rings (gauges), drawn as arcs on tori with a shader-trimmed sweep
    const ringVS = 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }';
    const ringFS = `varying vec2 vUv; uniform float uArc; uniform vec3 uA; uniform vec3 uB; uniform float uOp; uniform float uBoost;
      void main(){ if (vUv.x > uArc) discard; float k = vUv.x / max(uArc, 0.001);
        vec3 c = mix(uA, uB, k) * (1.0 + uBoost); float shade = 0.75 + 0.25 * sin(vUv.y * 6.2831);
        gl_FragColor = vec4(c * shade, uOp); }`;
    const glowFS = `varying vec2 vUv; uniform float uArc; uniform vec3 uA; uniform vec3 uB; uniform float uOp;
      void main(){ if (vUv.x > uArc) discard; float k = vUv.x / max(uArc, 0.001); float e = smoothstep(0.0, 0.02, vUv.x) * smoothstep(uArc, uArc - 0.02, vUv.x);
        float rad = abs(sin(vUv.y * 3.14159)); gl_FragColor = vec4(mix(uA, uB, k), uOp * 0.35 * pow(rad, 2.0) * e); }`;
    this.rings = [0.78, 0.95, 1.1].map((R, i) => {
      const tube = [0.05, 0.045, 0.036][i];
      const uni = { uArc: { value: 0 }, uA: { value: new THREE.Color() }, uB: { value: new THREE.Color() }, uOp: { value: 1 }, uBoost: { value: 0 } };
      const m = new THREE.Mesh(new THREE.TorusGeometry(R, tube, 18, 220), new THREE.ShaderMaterial({ uniforms: uni, vertexShader: ringVS, fragmentShader: ringFS, transparent: true, toneMapped: false }));
      m.renderOrder = 4;
      const gu = { uArc: uni.uArc, uA: uni.uA, uB: uni.uB, uOp: { value: 1 } };
      const g = new THREE.Mesh(new THREE.TorusGeometry(R, tube * 3.4, 12, 220), new THREE.ShaderMaterial({ uniforms: gu, vertexShader: ringVS, fragmentShader: glowFS, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false }));
      g.renderOrder = 4;
      const track = new THREE.Mesh(new THREE.TorusGeometry(R, tube * 0.55, 8, 160), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.08, depthWrite: false, toneMapped: false }));
      track.renderOrder = 3;
      const capMat = new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false, transparent: true });
      const cap0 = new THREE.Mesh(new THREE.SphereGeometry(tube, 16, 12), capMat), cap1 = new THREE.Mesh(new THREE.SphereGeometry(tube, 16, 12), capMat);
      cap0.renderOrder = cap1.renderOrder = 4;
      const grp = new THREE.Group(); grp.add(track, m, g, cap0, cap1);
      // start at 12 o'clock, run clockwise (like the app's gauges)
      for (const o of [track, m, g]) { o.scale.x = -1; o.rotation.z = -Math.PI / 2; }
      hero.add(grp);
      return { R, grp, uni, gu, track, capMat, cap0, cap1 };
    });

    // provider chips that read out the rings after the drop
    this.chips = TAB_ORDER.map((id) => { const p = this.uiPlane(700, 200, 7); hero.add(p.mesh); return { id, ...p }; });

    // contact shadow
    const sh = this.canvasTex(256, 128); {
      const g = sh.ctx.createRadialGradient(128, 64, 0, 128, 64, 128); g.addColorStop(0, 'rgba(20,24,60,0.55)'); g.addColorStop(1, 'rgba(20,24,60,0)');
      sh.ctx.setTransform(1, 0, 0, 0.5, 0, 32); sh.ctx.fillStyle = g; sh.ctx.fillRect(0, 0, 256, 256); sh.tex.needsUpdate = true;
    }
    this.shadow = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({ map: sh.tex, transparent: true, depthWrite: false, toneMapped: false }));
    this.shadow.rotation.x = -Math.PI / 2; this.shadow.renderOrder = 0; scene.add(this.shadow);

    // macOS menu bar (light, frosted)
    this.menubar = this.uiPlane(3200, 80, 1); this.menubar.mesh.scale.set(20, 0.5, 1); this.menubar.mesh.position.set(0, 3.35, -0.05);
    scene.add(this.menubar.mesh);
    // pointer
    this.cursor = this.uiPlane(128, 128, 9); this.cursor.mesh.scale.set(0.42, 0.42, 1); scene.add(this.cursor.mesh);
    this.drawCursor();
    // notification banner
    this.banner = this.uiPlane(1120, 300, 8); this.banner.mesh.scale.set(3.36, 0.9, 1); hero.add(this.banner.mesh);

    // typography layer: screen-space, locked to the lens
    this.type = this.uiPlane(W, H, 20); this.type.mat.depthTest = false;
    const td = 6; const th = 2 * td * Math.tan(THREE.MathUtils.degToRad(15));
    this.type.mesh.position.z = -td; this.type.mesh.scale.set(th * (W / H), th, 1); cam.add(this.type.mesh);
    this.typeDist = td;
  }

  // ───────── slab geometry (rebuilt only when the shape changes)
  setSlab(w, h, r, d) {
    const key = [w, h, r, d].map((x) => x.toFixed(3)).join(',');
    if (key === this.slabKey) return; this.slabKey = key;
    const bs = 0.06, bt = 0.05;
    const iw = Math.max(0.05, w - 2 * bs), ih = Math.max(0.05, h - 2 * bs), ir = clamp(r - bs, 0.01, Math.min(iw, ih) / 2 - 0.001);
    const s = new THREE.Shape(); const x = -iw / 2, y = -ih / 2;
    s.moveTo(x + ir, y); s.lineTo(x + iw - ir, y); s.absarc(x + iw - ir, y + ir, ir, -Math.PI / 2, 0);
    s.lineTo(x + iw, y + ih - ir); s.absarc(x + iw - ir, y + ih - ir, ir, 0, Math.PI / 2);
    s.lineTo(x + ir, y + ih); s.absarc(x + ir, y + ih - ir, ir, Math.PI / 2, Math.PI);
    s.lineTo(x, y + ir); s.absarc(x + ir, y + ir, ir, Math.PI, Math.PI * 1.5);
    const g = new THREE.ExtrudeGeometry(s, { depth: d, bevelEnabled: true, bevelThickness: bt, bevelSize: bs, bevelSegments: 6, curveSegments: 22 });
    g.translate(0, 0, -d / 2);
    this.slab.geometry.dispose(); this.slab.geometry = g;
  }

  drawCursor() {
    const { ctx, tex } = this.cursor; ctx.clearRect(0, 0, 128, 128);
    ctx.save(); ctx.translate(30, 14); ctx.scale(3.2, 3.2);
    ctx.shadowColor = 'rgba(0,0,0,0.35)'; ctx.shadowBlur = 6; ctx.shadowOffsetY = 2;
    ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, 22); ctx.lineTo(5.2, 17); ctx.lineTo(8.8, 25); ctx.lineTo(12, 23.6); ctx.lineTo(8.6, 16); ctx.lineTo(15.5, 16); ctx.closePath();
    ctx.fillStyle = '#fff'; ctx.fill(); ctx.shadowBlur = 0; ctx.shadowOffsetY = 0;
    ctx.beginPath(); ctx.moveTo(1.6, 3.8); ctx.lineTo(1.6, 18.2); ctx.lineTo(5.6, 14.4); ctx.lineTo(9.4, 22.4); ctx.lineTo(10.6, 21.8); ctx.lineTo(6.8, 14); ctx.lineTo(12, 14); ctx.closePath();
    ctx.fillStyle = '#000'; ctx.fill(); ctx.restore(); tex.needsUpdate = true;
  }

  // ───────────────────────── per-frame ─────────────────────────
  renderAt(t) {
    t = clamp(t, 0, DURATION);
    this.t = t;
    this.updateHero(t);
    this.updateCamera(t);
    this.updateFace(t);
    this.updateCards(t);
    this.updateRingsAndStar(t);
    this.updateChips(t);
    this.updateMenubar(t);
    this.updateBanner(t);
    this.updateCursor(t);
    this.updateDust(t);
    this.updateBackground(t);
    this.updateType(t);
    this.renderer.render(this.scene, this.camera);
  }

  // shape + placement of the slab
  slabState(t) {
    const ICON = [3.0, 3.0, 0.72, 0.34], PILL = [3.5, 0.52, 0.26, 0.14], POP = [3.5, 5.468, 0.26, 0.18];
    const a = spring(t - 12.0, 0.8, 0.86), a2 = spring(t - 12.14, 0.85, 0.8);
    const b = spring(t - 16.0, 0.62, 0.78), b2 = spring(t - 16.03, 0.7, 0.68);
    const c = spring(t - 37.0, 0.85, 0.82), c2 = spring(t - 37.08, 0.8, 0.74);
    const mix4 = (A, B, k, k2) => [lerp(A[0], B[0], k), lerp(A[1], B[1], k2), lerp(A[2], B[2], k), lerp(A[3], B[3], k)];
    let s = mix4(ICON, PILL, a, a2); s = mix4(s, POP, b, b2); s = mix4(s, ICON, c, c2);
    let [w, h, r, d] = s; h = Math.max(h, 0.3); w = Math.max(w, 0.3);

    // position: icon at origin, pill in the menu bar, popover hangs under the bar
    const ap = spring(t - 12.0, 1.1, 0.9);
    let x = lerp(0, 2.6, ap), y = lerp(0, 3.35, ap);
    const top = lerp(3.35 + 0.26, 2.96, b);
    const yPop = top - h / 2;
    x = lerp(x, 2.4, b); y = lerp(y, yPop, clamp(b * 4));
    const cp = spring(t - 37.0, 0.95, 0.9);
    x = lerp(x, 0, cp); y = lerp(y, 0, cp);
    let z = lerp(0, 0.12, ap) * (1 - b);
    z += -1.8 * ss(32.0, 33.6, t) * (1 - ss(36.2, 37.6, t));
    return { w, h, r, d, x, y, z };
  }

  updateHero(t) {
    const s = (this.S = this.slabState(t));
    this.setSlab(s.w, s.h, s.r, s.d);
    const hero = this.hero;
    hero.position.set(s.x, s.y, s.z);
    // intro turn, gentle float, popover angled toward the copy
    const intro = 0.42 * (1 - spring(t - 0.3, 3.2, 1)) ;
    const popTurn = -0.13 * ss(16.4, 18.4, t) * (1 - ss(36.6, 37.8, t));
    const breathe = 0.035 * Math.sin(t * 0.55) * (1 - ss(12, 13, t) * (1 - ss(36.5, 38, t)));
    hero.rotation.set(0.04 * Math.sin(t * 0.43) * (1 - ss(12, 13, t)) + 0.0, intro + popTurn + breathe, 0);
    // slab materialises behind the rings
    const appear = spring(t - 2.55, 0.9, 0.82);
    const sc = lerp(0.72, 1, appear);
    this.slab.scale.set(sc, sc, sc);
    this.slabMat.opacity = clamp(appear * 1.4);
    this.slabMat.visible = appear > 0.002;
    this.faceZ = (s.d / 2 + 0.05) * sc + 0.002;
    // breakdown: dim the popover while the type speaks
    this.dim = 1 - 0.5 * ss(32.0, 33.0, t) * (1 - ss(36.4, 37.4, t));
    // specular sweep across the glass on key beats
    const sw = (t0) => ss(t0, t0 + 1.4, t);
    let sx = -6;
    for (const t0 of [3.0, 8.0, 16.4, 38.0]) if (t >= t0 && t < t0 + 1.6) sx = lerp(-4, 6, sw(t0));
    this.sweep.position.set(s.x + sx, s.y + 1.5, 3); this.sweep.intensity = sx > -5.5 ? 28 : 0;
    this.scene.environmentRotation.set(0, t * 0.08 + 0.4, 0);
    // contact shadow under the icon / popover
    const shOp = (1 - ss(12.0, 12.6, t)) * appear + ss(16.6, 17.6, t) * (1 - ss(31.8, 33, t)) + ss(37.4, 38.4, t);
    this.shadow.material.opacity = clamp(shOp) * 0.8;
    this.shadow.position.set(s.x, s.y - s.h / 2 - 0.7, s.z);
    this.shadow.scale.set(s.w * 1.6, s.w * 0.5, 1);
  }

  // camera path: a spline through hand-placed keys, eased so it never stops dead
  updateCamera(t) {
    const K = [
      [0.0, [0.25, 0.15, 3.6], [0, 0, 0]],
      [2.3, [0.5, 0.3, 5.6], [0, -0.05, 0]],
      [4.6, [-0.9, 0.85, 10.4], [0, -0.72, 0]],
      [7.7, [-0.35, 0.55, 11.1], [0, -0.68, 0]],
      [9.2, [3.5, 1.2, 9.3], [1.25, -0.05, 0]],
      [11.6, [2.7, 0.55, 9.8], [1.3, -0.12, 0]],
      [12.85, [1.6, 2.0, 9.6], [2.0, 2.1, 0]],
      [14.0, [2.3, 2.75, 7.8], [2.6, 2.7, 0]],
      [15.1, [2.8, 3.05, 6.5], [2.85, 2.75, 0]],
      [16.0, [2.9, 3.0, 6.1], [2.9, 2.72, 0]],
      [18.0, [-0.4, 0.9, 11.8], [0.5, 0.12, 0]],
      [25.3, [-0.15, 0.6, 11.1], [0.6, 0.12, 0]],
      [27.6, [6.0, 1.5, 10.8], [0.3, 0.15, 0.4]],
      [31.0, [5.4, 0.7, 11.2], [0.35, 0.05, 0.4]],
      [33.2, [-1.0, 0.3, 12.4], [-1.25, 0.1, 0]],
      [36.6, [-1.2, 0.25, 12.9], [-1.3, 0.05, 0]],
      [38.5, [0.0, 0.62, 10.3], [0, -0.78, 0]],
      [44.0, [0.0, 0.5, 9.4], [0, -0.72, 0]],
    ];
    let i = 0; while (i < K.length - 2 && t >= K[i + 1][0]) i++;
    const k0 = K[Math.max(0, i - 1)], k1 = K[i], k2 = K[i + 1], k3 = K[Math.min(K.length - 1, i + 2)];
    let u = inv(k1[0], k2[0], t); u = lerp(u, eInOutSine(u), 0.6);
    const cr = (a, b, c, d, u) => { const u2 = u * u, u3 = u2 * u; return 0.5 * (2 * b + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u2 + (-a + 3 * b - 3 * c + d) * u3); };
    const P = [0, 1, 2].map((j) => cr(k0[1][j], k1[1][j], k2[1][j], k3[1][j], u));
    const L = [0, 1, 2].map((j) => cr(k0[2][j], k1[2][j], k2[2][j], k3[2][j], u));
    // the drop punches in a touch; the finale breathes out
    const punch = 0.5 * Math.exp(-Math.max(0, t - 8.0) * 3.0) * (t >= 8 ? 1 : 0) + 0.35 * Math.exp(-Math.max(0, t - 38.0) * 2.5) * (t >= 38 ? 1 : 0);
    const cam = this.camera;
    cam.position.set(P[0], P[1], P[2]);
    cam.lookAt(L[0], L[1], L[2]);
    cam.fov = 30 - punch * 2.2; cam.updateProjectionMatrix();
    // keep the type layer filling the frame at the current fov
    if (this.type) { const th = 2 * this.typeDist * Math.tan(THREE.MathUtils.degToRad(cam.fov / 2)); this.type.mesh.scale.set(th * (W / H), th, 1); }
  }

  // ───────── face: icon / menu-bar item / popover chrome
  updateFace(t) {
    const s = this.S, PPU = this.PPU;
    const fw = Math.max(8, (s.w - 0.1) * PPU), fh = Math.max(8, (s.h - 0.1) * PPU);
    const { ctx, tex, mesh, c } = this.face;
    ctx.clearRect(0, 0, c.width, c.height);
    const rad = Math.max(2, (s.r - 0.05) * PPU);
    ctx.save(); rr(ctx, 0, 0, fw, fh, rad); ctx.clip();
    const appear = spring(t - 2.55, 0.9, 0.82);

    // base: dark liquid glass, tinted by the active accent
    const tab = tabState(t);
    const accent = this.accent(t);
    const g = ctx.createLinearGradient(0, 0, 0, fh);
    g.addColorStop(0, '#1a2140'); g.addColorStop(1, '#0a0e1c');
    ctx.fillStyle = g; ctx.fillRect(0, 0, fw, fh);
    const rg = ctx.createRadialGradient(fw * 0.2, 0, 0, fw * 0.2, 0, Math.max(fw, fh) * 0.9);
    rg.addColorStop(0, rgb(accent, 0.22)); rg.addColorStop(1, rgb(accent, 0));
    ctx.fillStyle = rg; ctx.fillRect(0, 0, fw, fh);

    const iconAmt = (1 - ss(12.0, 12.55, t)) + ss(37.2, 37.9, t);
    const pillAmt = ss(12.35, 12.9, t) * (1 - ss(16.0, 16.3, t));
    const popAmt = ss(16.15, 16.6, t) * (1 - ss(36.9, 37.35, t));

    if (iconAmt > 0.001) {
      ctx.save(); ctx.globalAlpha = clamp(iconAmt);
      const ig = ctx.createRadialGradient(fw / 2, fh / 2, 0, fw / 2, fh / 2, fw * 0.6);
      ig.addColorStop(0, 'rgba(40,90,255,0.20)'); ig.addColorStop(0.55, 'rgba(20,40,120,0.08)'); ig.addColorStop(1, 'rgba(0,0,0,0.25)');
      ctx.fillStyle = ig; ctx.fillRect(0, 0, fw, fh);
      ctx.restore();
    }
    if (pillAmt > 0.001) this.drawPill(ctx, fw, fh, t, pillAmt);
    if (popAmt > 0.001) this.drawPopoverChrome(ctx, fw, fh, t, popAmt, tab);

    // dim during the breakdown
    if (this.dim < 0.999) { ctx.fillStyle = `rgba(8,10,20,${1 - this.dim})`; ctx.fillRect(0, 0, fw, fh); }
    ctx.restore();
    // rim highlight
    specularStroke(ctx, 0, 0, fw, fh, rad, 3, 0.9);

    tex.repeat.set(fw / c.width, fh / c.height); tex.offset.set(0, 1 - fh / c.height);
    tex.needsUpdate = true;
    const sc = lerp(0.72, 1, appear);
    mesh.scale.set((s.w - 0.1) * sc, (s.h - 0.1) * sc, 1);
    mesh.position.z = this.faceZ;
    mesh.material.opacity = clamp(appear * 1.4);
    mesh.visible = appear > 0.002;
  }

  accent(t) {
    // the popover's ambient tint follows the provider on screen
    const tabs = [[0, PAL.aiBlue], [16.4, PAL.claude], [20.0, PAL.chatgpt], [22.0, PAL.antigravity], [24.0, PAL.claude], [36.8, PAL.aiBlue]];
    let c = tabs[0][1];
    for (let i = 1; i < tabs.length; i++) c = mixc(c, tabs[i][1], ss(tabs[i][0] - 0.15, tabs[i][0] + 0.35, t));
    return c;
  }

  // the menu-bar status item: provider glyphs, figures and twin micro bars (MenuBarMeter)
  drawPill(ctx, fw, fh, t, a) {
    ctx.save(); ctx.globalAlpha = a;
    const click = ss(15.95, 16.05, t);
    if (click > 0) { rr(ctx, 6, 6, fw - 12, fh - 12, (fh - 12) / 2); ctx.fillStyle = `rgba(255,255,255,${0.12 * click})`; ctx.fill(); }
    const items = [['claude', 72, 0.72, 0.58], ['chatgpt', 64, 0.64, 0.41], ['antigravity', 88, 0.88, 0.76]];
    const fs = fh * 0.42, icon = fh * 0.5, gap = fh * 0.14;
    ctx.font = font(600, fs, ROUNDED);
    const widths = items.map(([, pct]) => icon + gap + ctx.measureText(`${pct}%`).width + gap * 0.9 + fh * 0.16);
    const sep = fh * 0.5; const total = widths.reduce((x, y) => x + y, 0) + sep * (items.length - 1);
    let x = (fw - total) / 2; const cy = fh / 2;
    items.forEach(([id, pct, f5, fw7], i) => {
      const k = ss(12.5 + i * 0.12, 12.9 + i * 0.12, t);
      ctx.save(); ctx.globalAlpha *= k; ctx.translate(0, (1 - k) * fh * 0.3);
      ctx.drawImage(this.images[id], x, cy - icon / 2, icon, icon);
      let xx = x + icon + gap;
      ctx.fillStyle = '#fff'; ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
      ctx.font = font(600, fs, ROUNDED); ctx.fillText(`${pct}%`, xx, cy + fs * 0.04);
      xx += ctx.measureText(`${pct}%`).width + gap * 0.9;
      const bw = fh * 0.16, bh = fh * 0.1;
      for (const [j, fv] of [[0, f5], [1, fw7]]) {
        const by = cy - bh * 1.15 + j * bh * 1.3;
        rr(ctx, xx, by, bw, bh, bh / 2); ctx.fillStyle = 'rgba(255,255,255,0.22)'; ctx.fill();
        rr(ctx, xx, by, bw * fv * ss(12.8, 13.4, t), bh, bh / 2); ctx.fillStyle = rgb(PAL[level(fv)]); ctx.fill();
      }
      ctx.restore();
      x += widths[i] + sep;
    });
    ctx.restore();
  }

  // popover chrome: header, freshness pill, control capsule, provider switcher
  drawPopoverChrome(ctx, fw, fh, t, a, tab) {
    const P = fw / 380; // px per pt
    ctx.save(); ctx.globalAlpha = a;
    const hk = ss(16.15, 16.6, t);
    ctx.save(); ctx.globalAlpha *= hk; ctx.translate(0, (1 - hk) * -8 * P);
    // app icon
    const ix = 14 * P, iy = 18 * P, is = 22 * P;
    ctx.save(); rr(ctx, ix, iy, is, is, 6 * P); ctx.clip();
    ctx.drawImage(this.images.appicon, 132, 132, 760, 760, ix - 2 * P, iy - 2 * P, is + 4 * P, is + 4 * P); ctx.restore();
    specularStroke(ctx, ix, iy, is, is, 6 * P, 0.8 * P);
    ctx.fillStyle = '#fff'; ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
    ctx.font = font(700, 13.5 * P); ctx.fillText('AIUsage', ix + is + 8 * P, iy + 11 * P);
    ctx.font = font(500, 9.5 * P, ROUNDED); ctx.fillStyle = 'rgba(255,255,255,0.65)'; ctx.fillText('v2.6.7', ix + is + 8 * P, iy + 22 * P);
    // freshness pill
    const px = 112 * P, py = 21 * P, ph = 17 * P;
    const live = t > 28.4 && t < 28.9 ? PAL.aiBlue : PAL.healthy;
    ctx.font = font(600, 10.5 * P); const label = 'Updated just now'; const lw = ctx.measureText(label).width;
    rr(ctx, px, py, lw + 27 * P, ph, ph / 2); ctx.fillStyle = 'rgba(255,255,255,0.08)'; ctx.fill(); specularStroke(ctx, px, py, lw + 27 * P, ph, ph / 2, 0.8 * P, 0.8);
    ctx.save(); ctx.shadowColor = rgb(live, 0.8); ctx.shadowBlur = 6 * P; ctx.beginPath(); ctx.arc(px + 11 * P, py + ph / 2, 3 * P, 0, 7); ctx.fillStyle = rgb(live); ctx.fill(); ctx.restore();
    ctx.fillStyle = 'rgba(255,255,255,0.78)'; ctx.textBaseline = 'middle'; ctx.fillText(label, px + 18 * P, py + ph / 2 + 0.5 * P);
    // control capsule
    const cw = 84 * P, cx0 = fw - 14 * P - cw, cy0 = 16 * P, ch = 28 * P;
    rr(ctx, cx0, cy0, cw, ch, ch / 2); ctx.fillStyle = 'rgba(255,255,255,0.07)'; ctx.fill(); specularStroke(ctx, cx0, cy0, cw, ch, ch / 2, 0.8 * P);
    const spin = spring(t - 16.6, 0.9, 0.8) * Math.PI * 2;
    ['sliders', 'refresh', 'ellipsis'].forEach((n, i) => {
      const bx = cx0 + 15 * P + i * 27 * P, by = cy0 + ch / 2;
      if (n === 'refresh') { ctx.save(); ctx.translate(bx, by); ctx.rotate(spin); symbol(ctx, n, 0, 0, 13 * P, 'rgba(255,255,255,0.82)'); ctx.restore(); }
      else symbol(ctx, n, bx, by, 13 * P, 'rgba(255,255,255,0.82)');
    });
    ctx.restore();

    // divider
    const dg = ctx.createLinearGradient(14 * P, 0, fw - 14 * P, 0);
    dg.addColorStop(0, 'rgba(255,255,255,0)'); dg.addColorStop(0.5, 'rgba(255,255,255,0.16)'); dg.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = dg; ctx.fillRect(14 * P, 52 * P, fw - 28 * P, 1 * P);

    // provider switcher
    const tk = ss(16.5, 17.0, t);
    ctx.save(); ctx.globalAlpha *= tk; ctx.translate(0, (1 - tk) * 10 * P);
    const tx0 = 14 * P, ty = 60 * P, tw = (352 * P - 2 * 6 * P) / 3, th = 46 * P;
    rr(ctx, tx0 - 3 * P, ty - 3 * P, 352 * P + 6 * P, th + 6 * P, 14 * P); ctx.fillStyle = 'rgba(255,255,255,0.04)'; ctx.fill();
    const idx = TAB_ORDER.indexOf(tab.id);
    const hx = springSeq(t, 0, TABS.slice(1).map(([tt, id]) => [tt, TAB_ORDER.indexOf(id), ...STATE]));
    const col = this.accent(t);
    const sx = tx0 + hx * (tw + 6 * P);
    ctx.save(); rr(ctx, sx, ty, tw, th, 12 * P);
    const hg = ctx.createLinearGradient(sx, ty, sx, ty + th); hg.addColorStop(0, rgb(col, 0.42)); hg.addColorStop(1, rgb(col, 0.24));
    ctx.shadowColor = rgb(col, 0.5); ctx.shadowBlur = 12 * P; ctx.fillStyle = hg; ctx.fill(); ctx.restore();
    specularStroke(ctx, sx, ty, tw, th, 12 * P, 1 * P, 1.2);
    TAB_ORDER.forEach((id, i) => {
      const p = PROVIDERS[id]; const x = tx0 + i * (tw + 6 * P);
      const on = 1 - clamp(Math.abs(hx - i));
      ctx.drawImage(this.images[id], x + 9 * P, ty + 11 * P, 24 * P, 24 * P);
      ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
      ctx.fillStyle = `rgba(255,255,255,${0.78 + 0.22 * on})`; ctx.font = font(600, 11.5 * P);
      ctx.fillText(p.name, x + 39 * P, ty + 21 * P);
      ctx.fillStyle = `rgba(255,255,255,${0.62 + 0.2 * on})`; ctx.font = font(500, 10 * P, ROUNDED);
      const st = id === 'claude' ? `${Math.round(Math.min(0.72, claudeWeekly(t)) * 100)}% left${claudeWeekly(t) < 0.72 ? ' weekly' : ''}` : p.status;
      ctx.fillText(st, x + 39 * P, ty + 35 * P);
    });
    ctx.restore();
    ctx.restore();
  }

  // ───────── cards (plan, rate limits, activity)
  updateCards(t) {
    const s = this.S, P = this.cardP;
    const u = (s.w - 0.1) / 380; // world units per pt
    const tab = tabState(t);
    const open = (k) => ss(16.55 + k * 0.12, 17.05 + k * 0.12, t) * (1 - ss(36.75 - k * 0.05, 37.15 - k * 0.05, t));
    const explode = spring(t - 25.9, 0.9, 0.78) - spring(t - 31.2, 0.75, 0.86);
    const lift = { plan: 0.42, rate: 0.95, act: 1.45 };
    ['plan', 'rate', 'act'].forEach((name, k) => {
      const c = this.cards[name]; const [x, y, w, h] = c.pt; const a = open(k);
      c.mesh.visible = a > 0.002;
      if (!c.mesh.visible) return;
      const { ctx, c: cv, tex } = c; ctx.clearRect(0, 0, cv.width, cv.height);
      ctx.save(); ctx.translate(c.pad, c.pad);
      // soft drop shadow when lifted
      if (explode > 0.02) { ctx.save(); ctx.shadowColor = `rgba(0,0,0,${0.45 * explode})`; ctx.shadowBlur = 20; ctx.shadowOffsetY = 6; rr(ctx, 0, 0, w * P, h * P, 16 * P); ctx.fillStyle = 'rgba(12,16,30,0.9)'; ctx.fill(); ctx.restore(); }
      if (name === 'plan') this.drawPlanCard(ctx, w * P, h * P, P, t, tab);
      if (name === 'rate') this.drawRateCard(ctx, w * P, h * P, P, t, tab);
      if (name === 'act') this.drawActivityCard(ctx, w * P, h * P, P, t, tab);
      ctx.restore();
      if (this.dim < 0.999) { ctx.fillStyle = `rgba(8,10,20,${1 - this.dim})`; ctx.globalCompositeOperation = 'source-atop'; ctx.fillRect(0, 0, cv.width, cv.height); ctx.globalCompositeOperation = 'source-over'; }
      tex.needsUpdate = true;
      const pw = (w + (2 * c.pad) / P) * u, ph = (h + (2 * c.pad) / P) * u;
      c.mesh.scale.set(pw, ph, 1);
      c.mesh.position.set((x + w / 2 - 190) * u, (300 - (y + h / 2)) * u - (1 - a) * 0.12, this.faceZ + 0.004 + k * 0.002 + explode * lift[name]);
      c.mat.opacity = a;
    });
  }

  drawPlanCard(ctx, w, h, P, t, tab) {
    const p = PROVIDERS[tab.id];
    this.swap(ctx, t, tab, w, P, (id, k) => {
      const q = PROVIDERS[id];
      glassCard(ctx, 0, 0, w, h, 16 * P, P, q.color, 1);
      ctx.save(); ctx.globalAlpha *= k;
      ctx.drawImage(this.images[id], 12 * P, 12 * P, 36 * P, 36 * P);
      ctx.fillStyle = '#fff'; ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
      ctx.font = font(600, 13 * P); ctx.fillText(q.plan, 58 * P, 27 * P);
      ctx.font = font(400, 11 * P); ctx.fillStyle = 'rgba(255,255,255,0.65)'; ctx.fillText('•••••@•••••.com', 58 * P, 43 * P);
      // GlassCapsuleButton
      const bw = 78 * P, bh = 24 * P, bx = w - 12 * P - bw, by = (h - bh) / 2;
      rr(ctx, bx, by, bw, bh, bh / 2); ctx.fillStyle = rgb(q.color, 0.32); ctx.fill(); specularStroke(ctx, bx, by, bw, bh, bh / 2, 0.8 * P, 1.1);
      ctx.fillStyle = '#fff'; ctx.font = font(600, 11 * P); ctx.textBaseline = 'middle'; ctx.fillText('Open', bx + 12 * P, by + bh / 2);
      symbol(ctx, 'arrow', bx + bw - 16 * P, by + bh / 2, 11 * P, '#fff');
      ctx.restore();
    }, false);
  }

  // content cross-slide used when the provider tab changes
  swap(ctx, t, tab, w, P, draw, slide = true) {
    const k = spring(t - tab.since, STATE[0], STATE[1]);
    if (tab.prevId && k < 0.995) {
      ctx.save(); ctx.globalAlpha *= clamp(1 - k * 1.6); if (slide) ctx.translate(-k * 30 * P, 0); draw(tab.prevId, 1, true); ctx.restore();
      ctx.save(); ctx.globalAlpha *= clamp(k * 1.3); if (slide) ctx.translate((1 - k) * 30 * P, 0); draw(tab.id, 1, false); ctx.restore();
    } else draw(tab.id, 1, false);
  }

  drawRateCard(ctx, w, h, P, t, tab) {
    glassCard(ctx, 0, 0, w, h, 16 * P, P, this.accent(t), 1);
    // GlassSectionHeader
    const col = this.accent(t);
    ctx.beginPath(); ctx.arc(22 * P, 20 * P, 10 * P, 0, 7); ctx.fillStyle = rgb(col, 0.16); ctx.fill();
    symbol(ctx, 'gauge', 22 * P, 20 * P, 12 * P, rgb(col));
    ctx.fillStyle = 'rgba(255,255,255,0.78)'; ctx.font = font(600, 11.5 * P); ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    ctx.fillText('Rate Limits', 38 * P, 20.5 * P);
    this.swap(ctx, t, tab, w, P, (id, _k, isPrev) => {
      const q = PROVIDERS[id];
      const since = isPrev ? -99 : tab.since;
      const gx = 12 * P, gy = 38 * P, gw = w - 24 * P, tw = (gw - 10 * P) / 2, th = 120 * P;
      const tiles = q.tiles.map((ti) => ({ ...ti }));
      if (id === 'claude') tiles[1].v = claudeWeekly(t);
      tiles.forEach((ti, i) => {
        const x = gx + (i % 2) * (tw + 10 * P), y = gy + Math.floor(i / 2) * (th + 10 * P);
        const appearAt = since + (id === 'claude' && since < 17 ? 0.6 + i * 0.5 : 0.1 + i * 0.12);
        const grow = isPrev ? 1 : spring(t - appearAt, ...METRIC);
        this.drawTile(ctx, x, y, tw, th, P, ti, ti.v * grow, t, i, appearAt);
      });
      if (q.extra) {
        const y = gy + th + 10 * P, eh = th;
        rr(ctx, gx, y, gw, eh, 14 * P); ctx.fillStyle = 'rgba(255,255,255,0.04)'; ctx.fill(); specularStroke(ctx, gx, y, gw, eh, 14 * P, 0.8 * P, 0.7);
        const ek = isPrev ? 1 : spring(t - (since + 0.35), ...METRIC);
        if (q.extra.kind === 'credits') {
          ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic'; ctx.fillStyle = '#fff'; ctx.font = font(600, 12.5 * P);
          ctx.fillText(q.extra.label, gx + 16 * P, y + 30 * P);
          ctx.fillStyle = 'rgba(255,255,255,0.65)'; ctx.font = font(400, 10.5 * P); ctx.fillText('Restore your 5-hour and weekly limits', gx + 16 * P, y + 46 * P);
          for (let i = 0; i < 2; i++) {
            const cx = gx + 30 * P + i * 34 * P, cy = y + 82 * P; const pk = spring(t - (since + 0.4 + i * 0.12), 0.45, 0.6);
            ctx.save(); ctx.translate(cx, cy); ctx.scale(isPrev ? 1 : pk, isPrev ? 1 : pk);
            ctx.shadowColor = rgb(PAL.credit, 0.6); ctx.shadowBlur = 10 * P;
            ctx.beginPath(); ctx.arc(0, 0, 13 * P, 0, 7); ctx.fillStyle = rgb(PAL.credit, 0.9); ctx.fill(); ctx.shadowBlur = 0;
            ctx.fillStyle = '#3a2a00'; ctx.font = font(800, 13 * P, ROUNDED); ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('↺', 0, 1 * P); ctx.restore();
          }
          ctx.fillStyle = '#fff'; ctx.textAlign = 'left'; ctx.font = font(600, 12 * P, ROUNDED); ctx.textBaseline = 'middle'; ctx.fillText(q.extra.value, gx + 92 * P, y + 82 * P);
          const bw = 92 * P, bh = 28 * P, bx = gx + gw - 16 * P - bw, by = y + 68 * P;
          rr(ctx, bx, by, bw, bh, bh / 2); ctx.fillStyle = rgb(q.color, 0.55 * ek); ctx.fill(); specularStroke(ctx, bx, by, bw, bh, bh / 2, 0.8 * P, 1.2);
          ctx.fillStyle = '#fff'; ctx.font = font(600, 12 * P); ctx.textAlign = 'center'; ctx.fillText(q.extra.button, bx + bw / 2, by + bh / 2 + 0.5 * P);
        } else {
          q.extra.rows.forEach(([label, val, f], i) => {
            const ry = y + 22 * P + i * 50 * P;
            ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic'; ctx.fillStyle = '#fff'; ctx.font = font(600, 12 * P); ctx.fillText(label, gx + 16 * P, ry + 10 * P);
            ctx.textAlign = 'right'; ctx.fillStyle = 'rgba(255,255,255,0.78)'; ctx.font = font(600, 11 * P, ROUNDED); ctx.fillText(val, gx + gw - 16 * P, ry + 10 * P);
            meterBar(ctx, gx + 16 * P, ry + 20 * P, gw - 32 * P, 7 * P, f * ek, i === 0 ? q.color : PAL.credit);
          });
        }
      }
    });
  }

  // QuotaTile
  drawTile(ctx, x, y, w, h, P, ti, f, t, i, appearAt) {
    rr(ctx, x, y, w, h, 14 * P); ctx.fillStyle = 'rgba(255,255,255,0.045)'; ctx.fill();
    specularStroke(ctx, x, y, w, h, 14 * P, 0.8 * P, 0.7);
    const lv = level(ti.v);
    if (lv !== 'healthy') { // tile glows amber when it needs attention
      rr(ctx, x, y, w, h, 14 * P); const g = ctx.createRadialGradient(x + w / 2, y + 40 * P, 0, x + w / 2, y + 40 * P, w * 0.7);
      g.addColorStop(0, rgb(PAL[lv], 0.16)); g.addColorStop(1, rgb(PAL[lv], 0)); ctx.fillStyle = g; ctx.fill();
    }
    ringGauge(ctx, x + w / 2, y + 41 * P, 62 * P, 6.5 * P, f, P);
    ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = '#fff'; ctx.font = font(600, 12 * P); ctx.fillText(ti.title, x + w / 2, y + 89 * P);
    ctx.fillStyle = 'rgba(255,255,255,0.65)'; ctx.font = font(400, 10 * P); ctx.fillText(ti.caption, x + w / 2, y + 102 * P);
    // reset countdown
    ctx.font = font(500, 9.5 * P, ROUNDED); const rt = ti.reset; const rw = ctx.measureText(rt).width + 20 * P;
    symbol(ctx, 'clock', x + w / 2 - rw / 2 + 6 * P, y + 112.5 * P, 8 * P, 'rgba(255,255,255,0.6)');
    ctx.fillStyle = 'rgba(255,255,255,0.78)'; ctx.textAlign = 'left'; ctx.fillText(rt, x + w / 2 - rw / 2 + 13 * P, y + 116 * P);
    if (lv !== 'healthy') {
      const k = ss(28.55, 28.85, t);
      ctx.save(); ctx.globalAlpha *= k; const label = lv === 'moderate' ? 'Low' : 'Almost out';
      ctx.font = font(700, 9.5 * P); const cw = ctx.measureText(label).width + 14 * P; const cx = x + w - 8 * P - cw, cy = y + 8 * P;
      rr(ctx, cx, cy, cw, 17 * P, 8.5 * P); ctx.fillStyle = rgb(PAL[lv], 0.16); ctx.fill(); ctx.strokeStyle = rgb(PAL[lv], 0.38); ctx.lineWidth = 0.8 * P; ctx.stroke();
      ctx.fillStyle = rgb(PAL[lv]); ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(label, cx + cw / 2, cy + 8.8 * P); ctx.restore();
    }
  }

  drawActivityCard(ctx, w, h, P, t, tab) {
    this.swap(ctx, t, tab, w, P, (id, _k, isPrev) => {
      const q = PROVIDERS[id];
      glassCard(ctx, 0, 0, w, h, 16 * P, P, q.color, 1);
      ctx.beginPath(); ctx.arc(22 * P, 18 * P, 10 * P, 0, 7); ctx.fillStyle = rgb(q.color, 0.16); ctx.fill();
      symbol(ctx, 'chart', 22 * P, 18 * P, 12 * P, rgb(q.color));
      ctx.fillStyle = 'rgba(255,255,255,0.78)'; ctx.font = font(600, 11.5 * P); ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
      ctx.fillText(q.activity, 38 * P, 18.5 * P);
      ctx.textAlign = 'right'; ctx.fillStyle = 'rgba(255,255,255,0.65)'; ctx.font = font(500, 10 * P, ROUNDED); ctx.fillText('14 days', w - 14 * P, 18.5 * P);
      const bx = 14 * P, by = 32 * P, bw = w - 28 * P, bh = 36 * P, n = q.bars.length, gap = 4 * P, cw = (bw - gap * (n - 1)) / n;
      const since = isPrev ? -99 : tab.since;
      q.bars.forEach((v, i) => {
        const g1 = spring(t - (since + 0.25 + i * 0.035), 0.55, 0.75);
        const g2 = id === 'claude' ? 1 - 0.85 * (ss(26.2, 26.45, t) - spring(t - (26.5 + i * 0.125), 0.45, 0.62) * ss(26.2, 26.45, t)) : 1;
        const hh = Math.max(2 * P, bh * v * (isPrev ? 1 : g1) * g2);
        const x = bx + i * (cw + gap), y = by + bh - hh;
        const today = i === n - 1;
        const g = ctx.createLinearGradient(0, y, 0, by + bh);
        g.addColorStop(0, rgb(q.color, today ? 1 : 0.85)); g.addColorStop(1, rgb(q.color, today ? 0.55 : 0.3));
        rr(ctx, x, y, cw, hh, 3 * P); ctx.fillStyle = g; ctx.fill();
        rr(ctx, x, y, cw, Math.min(hh, 3 * P), 3 * P); ctx.fillStyle = 'rgba(255,255,255,0.35)'; ctx.fill();
        if (today) { ctx.save(); ctx.shadowColor = rgb(q.color, 0.8); ctx.shadowBlur = 10 * P; rr(ctx, x, y, cw, hh, 3 * P); ctx.fill(); ctx.restore(); }
      });
      // average line
      ctx.setLineDash([3 * P, 3 * P]); ctx.strokeStyle = 'rgba(255,255,255,0.28)'; ctx.lineWidth = 1 * P;
      const avgY = by + bh * (1 - 0.55); ctx.beginPath(); ctx.moveTo(bx, avgY); ctx.lineTo(bx + bw, avgY); ctx.stroke(); ctx.setLineDash([]);
      ctx.font = font(500, 9.5 * P, ROUNDED); ctx.fillStyle = 'rgba(255,255,255,0.65)'; ctx.textBaseline = 'alphabetic';
      ctx.textAlign = 'left'; ctx.fillText(`avg ${q.avg}`, bx, h - 8 * P);
      ctx.textAlign = 'center'; ctx.fillText(`peak ${q.peak}/day`, w / 2, h - 8 * P);
      ctx.textAlign = 'right'; ctx.fillText('Today', bx + bw, h - 8 * P);
    });
  }

  // ───────── rings + star
  updateRingsAndStar(t) {
    const s = this.S;
    // star: a spark that crystallises, lives in the icon, ducks into the slab, returns for the finale
    const born = spring(t - 0.45, 0.7, 0.55);
    const gone = ss(11.95, 12.45, t);
    const back = spring(t - 37.55, 0.6, 0.6);
    const sk = born * (1 - gone) + back * gone;
    const zIn = this.faceZ + 0.42;
    this.star.scale.setScalar(Math.max(0.0001, sk) * 1.0);
    this.star.position.set(0, 0, zIn - (1 - sk) * 0.3);
    this.star.rotation.set(0.22 * Math.sin(t * 0.7), 0.5 * Math.sin(t * 0.6) + (1 - born) * 2.4, 0.08 * Math.sin(t * 0.9) + (1 - born) * 0.8);
    this.star.visible = sk > 0.002;
    const beatPulse = (t > 8 && t < 12) || t > 38 ? Math.exp(-((t % 0.5)) * 7) : 0;
    this.starMat.emissiveIntensity = 0.8 + 0.9 * beatPulse + 1.5 * Math.exp(-Math.max(0, t - 0.45) * 2.2) * (t > 0.45 ? 1 : 0);
    this.glow.position.set(0, 0, zIn - 0.05);
    this.glow.scale.setScalar((1.9 + 0.3 * beatPulse) * sk);
    this.glow.visible = sk > 0.002;
    this.glow.material.opacity = 0.9;

    // rings
    const ICONC = [[[60, 220, 255], [70, 160, 255]], [[70, 120, 255], [130, 150, 255]], [[110, 175, 255], [80, 120, 255]]];
    const PROVC = [[PAL.claude, [250, 170, 120]], [PAL.chatgpt, [110, 230, 180]], [PAL.antigravity, [140, 190, 255]]];
    const ICONARC = [0.8, 0.62, 0.42], PROVARC = [0.72, 0.64, 0.88];
    const explodeC = spring(t - 8.0, 0.9, 0.75) * (1 - ss(11.6, 12.3, t));
    this.rings.forEach((rg, i) => {
      const draw = ss(1.55 + i * 0.22, 2.75 + i * 0.22, t);
      const drain = ss(7.7, 7.98, t) * (1 - spring(t - (8.0 + i * 0.5), ...METRIC));
      const prov = spring(t - (8.0 + i * 0.5), 0.35, 0.9) * (1 - ss(11.7, 12.2, t));
      const finale = spring(t - (37.7 + i * 0.12), 0.7, 0.75);
      let arc = lerp(ICONARC[i], PROVARC[i], prov) * eOutCubic(draw) * (1 - drain);
      const show = (1 - gone) + back * gone;
      if (gone > 0) arc *= 1 - gone; if (t > 37) arc = ICONARC[i] * finale;
      const cA = mixc(ICONC[i][0], PROVC[i][0], prov), cB = mixc(ICONC[i][1], PROVC[i][1], prov);
      rg.uni.uArc.value = Math.max(0, arc);
      rg.uni.uA.value.setRGB(cA[0] / 255, cA[1] / 255, cA[2] / 255, THREE.SRGBColorSpace);
      rg.uni.uB.value.setRGB(cB[0] / 255, cB[1] / 255, cB[2] / 255, THREE.SRGBColorSpace);
      rg.uni.uOp.value = 1; rg.gu.uOp.value = 1;
      rg.uni.uBoost.value = 0.25 * (t > 8 && t < 12 ? Math.exp(-((t - 8 - i * 0.5 + 10) % 0.5) * 6) : 0);
      const zBase = this.faceZ + 0.1 + i * 0.07;
      rg.grp.position.set(0, 0, zBase + explodeC * (0.25 + i * 0.42));
      const sc = lerp(0.85, 1, eOutCubic(draw)) * (show > 0 ? 1 : 0);
      rg.grp.scale.setScalar(Math.max(0.0001, sc * (gone > 0 && t < 37 ? 1 - 0.4 * gone : 1)));
      rg.grp.visible = arc > 0.001 || (draw > 0 && show > 0.01);
      rg.track.material.opacity = 0.09 * draw * show;
      // caps
      const ang0 = Math.PI / 2, ang1 = Math.PI / 2 - arc * Math.PI * 2;
      rg.cap0.position.set(Math.cos(ang0) * rg.R, Math.sin(ang0) * rg.R, 0);
      rg.cap1.position.set(Math.cos(ang1) * rg.R, Math.sin(ang1) * rg.R, 0);
      rg.cap0.material.color.setRGB(cA[0] / 255, cA[1] / 255, cA[2] / 255, THREE.SRGBColorSpace);
      rg.cap1.material.color.setRGB(cB[0] / 255, cB[1] / 255, cB[2] / 255, THREE.SRGBColorSpace);
      rg.cap0.visible = rg.cap1.visible = arc > 0.004;
    });
  }

  // read-out chips beside the rings after the drop
  updateChips(t) {
    const items = [['claude', 72], ['chatgpt', 64], ['antigravity', 88]];
    const zs = (i) => this.faceZ + 0.1 + i * 0.07 + (spring(t - 8.0, 0.9, 0.75)) * (0.25 + i * 0.42);
    this.chips.forEach((ch, i) => {
      const [id, pct] = items[i];
      const k = spring(t - (8.05 + i * 0.5), 0.5, 0.62);
      const out = ss(11.55 + i * 0.06, 12.0 + i * 0.06, t);
      const a = clamp(k) * (1 - out);
      ch.mesh.visible = a > 0.002;
      if (!ch.mesh.visible) return;
      const { ctx, c, tex } = ch; ctx.clearRect(0, 0, c.width, c.height);
      const pad = 24, w = c.width - pad * 2, h = c.height - pad * 2;
      ctx.save(); ctx.shadowColor = 'rgba(30,40,90,0.22)'; ctx.shadowBlur = 22; ctx.shadowOffsetY = 8;
      rr(ctx, pad, pad, w, h, h / 2); ctx.fillStyle = 'rgba(255,255,255,0.86)'; ctx.fill(); ctx.restore();
      rr(ctx, pad + 1, pad + 1, w - 2, h - 2, h / 2 - 1); ctx.strokeStyle = 'rgba(255,255,255,0.9)'; ctx.lineWidth = 2; ctx.stroke();
      ctx.drawImage(this.images[id], pad + 22, pad + 22, h - 44, h - 44);
      ctx.fillStyle = '#121528'; ctx.font = font(600, 46); ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
      ctx.fillText(PROVIDERS[id].name, pad + h + 4, pad + h / 2 + 2);
      const shown = Math.round(pct * clamp(spring(t - (8.0 + i * 0.5), ...METRIC)));
      ctx.textAlign = 'right'; ctx.font = font(700, 58, ROUNDED); ctx.fillStyle = rgb(PROVIDERS[id].color);
      ctx.fillText(`${shown}%`, pad + w - 34, pad + h / 2 + 3);
      tex.needsUpdate = true;
      ch.mat.opacity = a;
      const sc = lerp(0.7, 1, clamp(k));
      ch.mesh.scale.set(2.1 * sc, 0.6 * sc, 1);
      ch.mesh.position.set(2.45 + (1 - clamp(k)) * 0.5 - out * 0.6, 0.85 - i * 0.85, zs(i));
      ch.mesh.rotation.y = -0.18 + (1 - clamp(k)) * 0.5;
    });
  }

  updateMenubar(t) {
    const a = ss(12.3, 13.0, t) * (1 - ss(17.4, 18.4, t));
    const m = this.menubar; m.mesh.visible = a > 0.002;
    if (!m.mesh.visible) return;
    const { ctx, c, tex } = m; const ppu = c.width / 20;
    ctx.clearRect(0, 0, c.width, c.height);
    const g = ctx.createLinearGradient(0, 0, 0, c.height); g.addColorStop(0, 'rgba(255,255,255,0.78)'); g.addColorStop(1, 'rgba(250,251,255,0.62)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, c.width, c.height);
    ctx.fillStyle = 'rgba(20,24,50,0.10)'; ctx.fillRect(0, c.height - 2, c.width, 2);
    const X = (wx) => (wx + 10) * ppu, cy = c.height / 2;
    ctx.fillStyle = '#16192c'; ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
    ctx.font = font(700, 30); ctx.fillText('Finder', X(-6.6), cy + 1);
    ctx.font = font(500, 30); let x = X(-6.6) + ctx.measureText('Finder').width + 46;
    for (const w of ['File', 'Edit', 'View', 'Go', 'Window', 'Help']) { ctx.fillText(w, x, cy + 1); x += ctx.measureText(w).width + 44; }
    const rx = [[4.75, 'wifi'], [5.25, 'battery'], [5.8, 'search'], [6.25, 'toggles']];
    for (const [wx, n] of rx) symbol(ctx, n, X(wx), cy, 34, '#16192c');
    ctx.font = font(500, 30); ctx.textAlign = 'left'; ctx.fillText('Wed 18 Nov  9:41', X(6.6), cy + 1);
    tex.needsUpdate = true; m.mat.opacity = a;
  }

  updateBanner(t) {
    const k = spring(t - 29.0, 0.55, 0.72), out = ss(31.2, 31.7, t);
    const a = clamp(k) * (1 - out);
    const b = this.banner; b.mesh.visible = a > 0.002;
    if (!b.mesh.visible) return;
    const { ctx, c, tex } = b; ctx.clearRect(0, 0, c.width, c.height);
    const pad = 30, w = c.width - pad * 2, h = c.height - pad * 2, r = 56;
    ctx.save(); ctx.shadowColor = 'rgba(20,30,70,0.30)'; ctx.shadowBlur = 30; ctx.shadowOffsetY = 10;
    rr(ctx, pad, pad, w, h, r); ctx.fillStyle = 'rgba(248,249,253,0.94)'; ctx.fill(); ctx.restore();
    rr(ctx, pad + 1.5, pad + 1.5, w - 3, h - 3, r - 1); ctx.strokeStyle = 'rgba(255,255,255,1)'; ctx.lineWidth = 3; ctx.stroke();
    const is = 120; ctx.save(); rr(ctx, pad + 34, pad + (h - is) / 2, is, is, 28); ctx.clip();
    ctx.drawImage(this.images.appicon, 132, 132, 760, 760, pad + 30, pad + (h - is) / 2 - 4, is + 8, is + 8); ctx.restore();
    const tx = pad + 34 + is + 34;
    ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = 'rgba(20,24,44,0.55)'; ctx.font = font(600, 30); ctx.fillText('AIUsage', tx, pad + 72);
    ctx.textAlign = 'right'; ctx.fillText('now', pad + w - 40, pad + 72);
    ctx.textAlign = 'left'; ctx.fillStyle = '#121528'; ctx.font = font(700, 40); ctx.fillText('Claude weekly limit is low', tx, pad + 126);
    ctx.fillStyle = 'rgba(20,24,44,0.72)'; ctx.font = font(500, 34); ctx.fillText('28% left · resets Thursday 09:00', tx, pad + 174);
    tex.needsUpdate = true; b.mat.opacity = a;
    const s = this.S;
    b.mesh.position.set(0.9 + (1 - clamp(k)) * 1.6, s.h / 2 - 1.2 - (1 - clamp(k)) * 0.1, this.faceZ + 2.1);
    b.mesh.rotation.set(0, -0.12 + (1 - clamp(k)) * 0.4, 0);
    const sc = lerp(0.85, 1, clamp(k)); b.mesh.scale.set(3.36 * sc, 0.9 * sc, 1);
  }

  updateCursor(t) {
    const m = this.cursor.mesh;
    const a = ss(14.3, 14.6, t) * (1 - ss(16.35, 16.7, t));
    m.visible = a > 0.002; if (!m.visible) return;
    const k = eInOut(inv(14.3, 15.75, t));
    const tip = [lerp(4.4, 2.05, k), lerp(1.95, 3.24, k) + Math.sin(k * Math.PI) * 0.25, 0.45];
    const press = 1 - 0.14 * Math.exp(-Math.pow((t - 16.0) / 0.06, 2));
    tip[1] -= (t > 16.05 ? eOutCubic(inv(16.05, 16.7, t)) * 0.5 : 0);
    m.scale.set(0.42 * press, 0.42 * press, 1);
    m.position.set(tip[0] + 0.11 * press, tip[1] - 0.164 * press, tip[2]);
    m.material.opacity = a;
  }

  updateDust(t) {
    const { pos, seed, alphas, geo, N } = this.dust;
    const rnd = mulberry32(99);
    for (let i = 0; i < N; i++) {
      const sx = seed[i * 4], sy = seed[i * 4 + 1], sz = seed[i * 4 + 2], ph = seed[i * 4 + 3];
      let x = sx + Math.sin(t * 0.13 + ph * 6) * 0.4, y = sy + Math.cos(t * 0.11 + ph * 9) * 0.3 + t * 0.03, z = sz;
      let a = 0.22 + 0.2 * Math.sin(t * 0.8 + ph * 20);
      // first 70 converge into the star at the start
      if (i < 70) {
        const ang = ph * Math.PI * 2 * 7, rad = 1.2 + rnd() * 2.5;
        const k = eInOut(inv(0.0 + ph * 0.25, 0.75 + ph * 0.2, t));
        const hx = this.hero.position.x, hy = this.hero.position.y, hz = this.faceZ + 0.42;
        x = lerp(Math.cos(ang) * rad, hx, k); y = lerp(Math.sin(ang) * rad, hy, k); z = lerp(hz + (rnd() - 0.5) * 2, hz, k);
        a = (t < 1.4 ? 0.9 * (1 - k * k) : 0) * ss(0, 0.2, t);
      } else a *= ss(0.3, 2.5, t);
      pos[i * 3] = x; pos[i * 3 + 1] = y; pos[i * 3 + 2] = z; alphas[i] = clamp(a);
    }
    geo.attributes.position.needsUpdate = true; geo.attributes.aAlpha.needsUpdate = true;
  }

  updateBackground(t) {
    const u = this.bgMat.uniforms; u.uTime.value = t;
    const c = this.accent(t); u.uTint.value.setRGB(...c.map((v) => lerp(v / 255, 1, 0.55)));
    u.uTintAmt.value = 0.35 * ss(16.2, 17.2, t) * (1 - ss(36.6, 37.6, t));
    u.uLift.value = 0.02 * Math.exp(-Math.max(0, t - 8) * 2.5) * (t >= 8 ? 1 : 0) + 0.025 * Math.exp(-Math.max(0, t - 38) * 2) * (t >= 38 ? 1 : 0);
  }

  // ───────── typography (kinetic, per character)
  updateType(t) {
    const { ctx, tex } = this.type; ctx.clearRect(0, 0, W, H);
    const INK = '#101326', SUB = 'rgba(28,32,58,0.62)';
    const GRAD = [[25, 170, 255], [64, 110, 250], [140, 92, 255]];
    const prov = tabState(t).id;
    const L = [];
    // hero
    L.push({ text: 'AIUsage', x: 960, y: 846, size: 112, weight: 700, at: 4.55, out: 7.75, align: 'center', track: -0.025 });
    L.push({ text: 'Every AI limit. One glance.', x: 960, y: 930, size: 42, weight: 500, at: 5.95, out: 7.8, color: SUB, align: 'center', stagger: 0.012 });
    // after the drop
    L.push({ text: 'Claude.  ChatGPT.  Antigravity.', x: 960, y: 985, size: 46, weight: 650, words: [8.05, 8.55, 9.05], out: 11.55, align: 'center', wordColors: [PAL.claude, PAL.chatgpt, PAL.antigravity] });
    // menu bar
    L.push({ text: 'Lives in your menu bar.', x: 960, y: 752, size: 80, weight: 700, at: 13.45, out: 15.75, align: 'center', track: -0.02 });
    // popover
    L.push({ text: 'Every limit.', x: 168, y: 470, size: 104, weight: 700, at: 17.75, out: 19.75, track: -0.025 });
    L.push({ text: '5-hour, weekly and per-model windows,', x: 172, y: 548, size: 36, weight: 500, at: 18.3, out: 19.75, color: SUB, stagger: 0.008 });
    L.push({ text: 'with live reset countdowns.', x: 172, y: 596, size: 36, weight: 500, at: 18.5, out: 19.75, color: SUB, stagger: 0.008 });
    L.push({ text: 'Every provider.', x: 168, y: 470, size: 104, weight: 700, at: 20.0, out: 25.4, track: -0.025 });
    L.push({ text: 'Claude   ChatGPT   Antigravity', x: 172, y: 552, size: 40, weight: 600, at: 20.35, out: 25.4, stagger: 0.01, wordColors: 'tabs', prov });
    // exploded
    L.push({ text: 'Token activity,', x: 150, y: 470, size: 84, weight: 700, at: 26.55, out: 28.55, track: -0.025 });
    L.push({ text: 'read from your local session logs.', x: 154, y: 548, size: 36, weight: 500, at: 26.9, out: 28.55, color: SUB, stagger: 0.008 });
    L.push({ text: 'A heads-up', x: 140, y: 456, size: 76, weight: 700, at: 28.95, out: 31.45, track: -0.025 });
    L.push({ text: 'before you hit the wall.', x: 140, y: 536, size: 76, weight: 700, at: 29.15, out: 31.45, track: -0.025, grad: [PAL.moderate, [245, 120, 80], PAL.critical] });
    // breakdown
    L.push({ text: 'Zero tokens.', x: 760, y: 520, size: 150, weight: 750, at: 32.55, out: 36.75, align: 'center', track: -0.035, grad: GRAD });
    L.push({ text: 'Checks your limits without a single inference call.', x: 760, y: 612, size: 38, weight: 500, at: 33.9, out: 36.75, align: 'center', color: SUB, stagger: 0.006 });
    L.push({ text: 'No telemetry  ·  No proxies  ·  Native Swift', x: 760, y: 668, size: 30, weight: 600, at: 34.8, out: 36.75, align: 'center', color: 'rgba(28,32,58,0.5)', stagger: 0.006 });
    // finale
    L.push({ text: 'AIUsage', x: 960, y: 818, size: 116, weight: 700, at: 38.25, out: 99, align: 'center', track: -0.025 });
    L.push({ text: 'Every AI quota. One glance.', x: 960, y: 900, size: 42, weight: 500, at: 38.95, out: 99, align: 'center', color: SUB, stagger: 0.012 });
    L.push({ text: 'brew install --cask desmondlee95700/tap/aiusage', x: 960, y: 978, size: 27, weight: 500, at: 39.8, out: 99, align: 'center', mono: true, pill: true, stagger: 0.004 });
    L.push({ text: 'Free and open source  ·  macOS 13+  ·  github.com/desmondlee95700/AIUsage', x: 960, y: 1040, size: 23, weight: 500, at: 40.4, out: 99, align: 'center', color: 'rgba(28,32,58,0.55)', stagger: 0.004 });

    for (const l of L) this.drawLine(ctx, l, t, INK);
    tex.needsUpdate = true;
  }

  drawLine(ctx, l, t, INK) {
    const first = l.words ? l.words[0] : l.at;
    if (t < first - 0.01 || t > l.out + 0.6) return;
    const fam = l.mono ? MONO : FONT;
    ctx.font = font(l.weight, l.size, fam);
    ctx.letterSpacing = `${(l.track || 0) * l.size}px`;
    ctx.textBaseline = 'alphabetic'; ctx.textAlign = 'left';
    const total = ctx.measureText(l.text).width;
    const x0 = l.align === 'center' ? l.x - total / 2 : l.x;
    const q = eInOut(inv(l.out, l.out + 0.5, t));
    // word index for each char
    let wi = 0; const wordOf = [];
    for (let i = 0; i < l.text.length; i++) { wordOf.push(wi); if (l.text[i] === ' ' && l.text[i + 1] !== ' ' && i + 1 < l.text.length) wi++; }
    if (l.pill) {
      const k = eOutExpo(inv(l.at, l.at + 0.6, t)) * (1 - q);
      ctx.save(); ctx.globalAlpha = k; rr(ctx, x0 - 26, l.y - l.size * 1.15, total + 52, l.size * 1.75, l.size * 0.875);
      ctx.fillStyle = 'rgba(255,255,255,0.62)'; ctx.fill(); ctx.strokeStyle = 'rgba(255,255,255,0.95)'; ctx.lineWidth = 2; ctx.stroke(); ctx.restore();
    }
    let fill = l.color || INK;
    if (l.grad) {
      const g = ctx.createLinearGradient(x0, 0, x0 + total, 0);
      l.grad.forEach((c, i) => g.addColorStop(i / (l.grad.length - 1), rgb(c)));
      fill = g;
    }
    const stagger = l.stagger ?? 0.024;
    let prefix = '';
    for (let i = 0; i < l.text.length; i++) {
      const ch = l.text[i];
      const cx = x0 + ctx.measureText(prefix).width; prefix += ch;
      if (ch === ' ') continue;
      const start = l.words ? l.words[wordOf[i]] + (i - l.text.indexOf(l.text.split(/\s+/)[wordOf[i]])) * 0.02 : l.at + i * stagger;
      const p = eOutExpo(inv(start, start + 0.75, t));
      if (p <= 0) continue;
      const a = p * (1 - q);
      if (a <= 0.001) continue;
      const dy = (1 - p) * l.size * 0.42 - q * l.size * 0.22;
      const blur = (1 - p) * 10 + q * 6;
      ctx.save(); ctx.globalAlpha = a;
      if (blur > 0.4) ctx.filter = `blur(${blur.toFixed(1)}px)`;
      let f = fill;
      if (l.wordColors === 'tabs') {
        const ids = ['claude', 'chatgpt', 'antigravity'];
        const on = ids[wordOf[i]] === l.prov;
        f = on ? rgb(PROVIDERS[ids[wordOf[i]]].color) : 'rgba(28,32,58,0.35)';
      } else if (Array.isArray(l.wordColors)) f = rgb(l.wordColors[wordOf[i]] || [16, 19, 38]);
      ctx.fillStyle = f;
      ctx.fillText(ch, cx, l.y + dy);
      ctx.restore();
    }
    ctx.letterSpacing = '0px';
  }
}
