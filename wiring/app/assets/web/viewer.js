// 3D component viewer: orbit, explode (scrub), tap-to-pick parts, numbered bilingual labels,
// lesson-sheet snapshots and an exported presentation video.
// Talks to Flutter through flutter_inappwebview's JavaScript bridge; big binaries go back
// through the app's local server (POST /upload/<token>).
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const bridge = (name, ...args) => {
  try {
    const b = window.flutter_inappwebview;
    if (b && b.callHandler) return b.callHandler(name, ...args);
  } catch (e) { /* browser preview */ }
  return undefined;
};

const msg = document.getElementById('msg');
const labelsEl = document.getElementById('labels');
const linesEl = document.getElementById('lines');
const SVGNS = 'http://www.w3.org/2000/svg';
const AMBER = '#F6B91A', CYAN = '#4FD8FF';

// ---------- renderer / scene (tuned for natural colours) ----------
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.92;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.02).texture;
scene.environmentIntensity = 0.55;

const keyLight = new THREE.DirectionalLight(0xfff4e6, 2.1);
keyLight.castShadow = true;
keyLight.shadow.mapSize.set(2048, 2048);
keyLight.shadow.bias = -0.0004;
keyLight.shadow.normalBias = 0.002;
scene.add(keyLight, keyLight.target);
const fill = new THREE.DirectionalLight(0xc8dcff, 0.45);
scene.add(fill);
const rim = new THREE.DirectionalLight(0xffffff, 0.7);
scene.add(rim);
scene.add(new THREE.HemisphereLight(0xdfe8f5, 0x20262c, 0.25));

const shadowMat = new THREE.ShadowMaterial({ opacity: 0.32 });
const ground = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), shadowMat);
ground.rotation.x = -Math.PI / 2;
ground.receiveShadow = true;
scene.add(ground);

const camera = new THREE.PerspectiveCamera(30, 1, 0.001, 100);
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.09;
controls.screenSpacePanning = true;
controls.rotateSpeed = 0.8;

const loader = new GLTFLoader();
const VIEW_DIR = new THREE.Vector3(0.62, 0.42, 1).normalize();

// ---------- state ----------
let root = null;
let parts = [];
let explode = 0;
let explodeTarget = 0;
let labelsOn = true;
let selected = null;
let boxA = null;
let boxE = null;
let camGoal = null;
let loadToken = 0;
let busy = false;           // capture / video in progress
let meta = { ar: '', en: '' };

const smooth = (t) => t * t * (3 - 2 * t);

function applyExplode() {
  const e = smooth(explode);
  for (const p of parts) p.obj.position.copy(p.base).addScaledVector(p.off, e);
}

function fitFor(box) {
  const center = box.getCenter(new THREE.Vector3());
  const radius = Math.max(box.getSize(new THREE.Vector3()).length() / 2, 0.005);
  const vHalf = THREE.MathUtils.degToRad(camera.fov / 2);
  const hHalf = Math.atan(Math.tan(vHalf) * camera.aspect);
  const dist = (radius / Math.sin(Math.min(vHalf, hHalf))) * 1.04;
  return { target: center, dist };
}

function goalFor(t) {
  const a = fitFor(boxA), e = fitFor(boxE), k = smooth(t);
  return { target: a.target.clone().lerp(e.target, k), dist: a.dist + (e.dist - a.dist) * k };
}

function setNearFar(dist) {
  camera.near = Math.max(dist / 200, 0.0005);
  camera.far = dist * 30;
  camera.updateProjectionMatrix();
}

function placeLights() {
  if (!boxE) return;
  const c = boxE.getCenter(new THREE.Vector3());
  const r = boxE.getSize(new THREE.Vector3()).length();
  keyLight.position.copy(c).add(new THREE.Vector3(0.7, 1.4, 1.0).multiplyScalar(r));
  keyLight.target.position.copy(c);
  const cam = keyLight.shadow.camera;
  cam.left = cam.bottom = -r; cam.right = cam.top = r;
  cam.near = r * 0.1; cam.far = r * 5;
  cam.updateProjectionMatrix();
  fill.position.copy(c).add(new THREE.Vector3(-1.2, 0.4, 0.6).multiplyScalar(r));
  rim.position.copy(c).add(new THREE.Vector3(-0.3, 0.9, -1.3).multiplyScalar(r));
  ground.position.set(c.x, boxA.min.y - r * 0.002, c.z);
  ground.scale.set(r * 6, r * 6, 1);
}

function refit(snap, t = explodeTarget) {
  if (!boxA) return;
  const goal = goalFor(t);
  setNearFar(goal.dist);
  if (snap) {
    controls.target.copy(goal.target);
    camera.position.copy(goal.target).addScaledVector(VIEW_DIR, goal.dist);
    camGoal = null;
  } else {
    camGoal = goal;
  }
}

function clearModel() {
  if (root) {
    scene.remove(root);
    root.traverse((o) => {
      if (o.isMesh) {
        o.geometry.dispose();
        (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => m.dispose());
      }
    });
  }
  root = null; parts = []; selected = null; boxA = boxE = null;
  labelsEl.innerHTML = ''; linesEl.innerHTML = '';
}

function hasPartAncestor(o) {
  for (let a = o.parent; a; a = a.parent) if (a.userData && a.userData.name_ar) return true;
  return false;
}

function load(url, ar, en) {
  clearModel();
  meta = { ar: ar || '', en: en || '' };
  explode = explodeTarget = 0;
  msg.style.display = 'flex';
  msg.textContent = 'جاري تحميل المجسم…';
  const token = ++loadToken;
  loader.load(url, (gltf) => {
    if (token !== loadToken) return;
    root = gltf.scene;
    scene.add(root);
    root.updateMatrixWorld(true);
    root.traverse((m) => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = true; } });

    const partNodes = [];
    root.traverse((o) => { if (o.userData && o.userData.name_ar && !hasPartAncestor(o)) partNodes.push(o); });
    partNodes.forEach((o, i) => {
      const meshes = [];
      o.traverse((m) => {
        if (!m.isMesh) return;
        m.material = Array.isArray(m.material) ? m.material.map((x) => x.clone()) : m.material.clone();
        for (const mat of Array.isArray(m.material) ? m.material : [m.material]) {
          if (mat.emissive) { mat.userData.e0 = mat.emissive.clone(); mat.userData.ei0 = mat.emissiveIntensity; }
        }
        m.userData.__part = o.name;
        meshes.push(m);
      });
      const d = o.userData.explode_mm || [0, 0, 0];
      // explode_mm is authored in Blender world axes (Z up, front = -Y) → glTF (Y up, front = +Z)
      const worldOff = new THREE.Vector3(d[0], d[2], -d[1]).multiplyScalar(0.001);
      const par = o.parent;
      const w0 = o.getWorldPosition(new THREE.Vector3());
      const localOff = par.worldToLocal(w0.clone().add(worldOff)).sub(par.worldToLocal(w0.clone()));
      const box = new THREE.Box3().setFromObject(o);
      const localCenter = box.isEmpty() ? new THREE.Vector3() : o.worldToLocal(box.getCenter(new THREE.Vector3()));
      parts.push({
        id: o.name, n: i + 1, ar: o.userData.name_ar, en: o.userData.name_en || '',
        obj: o, base: o.position.clone(), off: localOff, meshes, localCenter, el: null, w: 0, h: 0,
      });
    });

    boxA = new THREE.Box3().setFromObject(root);
    if (parts.length) {
      explode = 1; applyExplode(); root.updateMatrixWorld(true);
      boxE = new THREE.Box3().setFromObject(root).union(boxA);
      explode = 0; applyExplode(); root.updateMatrixWorld(true);
    } else {
      boxE = boxA.clone();
    }
    placeLights();
    buildLabels();
    refit(true, 0);
    msg.style.display = 'none';
    bridge('loaded', JSON.stringify(parts.map((p) => ({ id: p.id, n: p.n, ar: p.ar, en: p.en }))));
  }, undefined, () => {
    if (token !== loadToken) return;
    msg.style.display = 'flex';
    msg.textContent = 'تعذّر تحميل المجسم';
  });
}

// ---------- selection ----------
function select(id) {
  selected = id || null;
  for (const p of parts) {
    const on = p.id === selected;
    for (const m of p.meshes) {
      for (const mat of Array.isArray(m.material) ? m.material : [m.material]) {
        if (!mat.emissive) continue;
        if (on) { mat.emissive.setHex(0xf5a400); mat.emissiveIntensity = 0.28; }
        else { mat.emissive.copy(mat.userData.e0 || new THREE.Color(0)); mat.emissiveIntensity = mat.userData.ei0 ?? 1; }
      }
    }
    if (p.el) p.el.classList.toggle('sel', on);
  }
}

function focusPart(id) {
  const p = parts.find((x) => x.id === id);
  if (!p) return;
  const c = p.obj.localToWorld(p.localCenter.clone());
  const dist = camera.position.distanceTo(controls.target);
  camGoal = { target: controls.target.clone().lerp(c, 0.55), dist };
}

const ray = new THREE.Raycaster();
const ndc = new THREE.Vector2();
let down = null;
let pointers = 0;
renderer.domElement.addEventListener('pointerdown', (e) => {
  pointers++;
  down = pointers === 1 ? { x: e.clientX, y: e.clientY, t: performance.now() } : null;
});
const endPointer = (e, cancelled) => {
  pointers = Math.max(0, pointers - 1);
  if (cancelled || !down || busy) { down = null; return; }
  const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y);
  const dt = performance.now() - down.t;
  down = null;
  if (moved > 8 || dt > 650) return;
  pick(e.clientX, e.clientY);
};
renderer.domElement.addEventListener('pointerup', (e) => endPointer(e, false));
renderer.domElement.addEventListener('pointercancel', (e) => endPointer(e, true));

function pick(x, y) {
  if (!parts.length) return;
  const r = renderer.domElement.getBoundingClientRect();
  ndc.set(((x - r.left) / r.width) * 2 - 1, -((y - r.top) / r.height) * 2 + 1);
  ray.setFromCamera(ndc, camera);
  const hits = ray.intersectObjects(parts.flatMap((p) => p.meshes), false);
  const id = hits.length ? hits[0].object.userData.__part : null;
  select(id);
  bridge('part', id);
}

// ---------- labels ----------
function buildLabels() {
  labelsEl.innerHTML = '';
  linesEl.innerHTML = '';
  for (const p of parts) {
    const el = document.createElement('div');
    el.className = 'lbl';
    const num = document.createElement('b');
    num.textContent = p.n;
    const txt = document.createElement('span');
    txt.textContent = p.ar;
    el.append(num, txt);
    if (p.en) {
      const s = document.createElement('small');
      s.textContent = p.en;
      el.appendChild(s);
    }
    labelsEl.appendChild(el);
    const ln = document.createElementNS(SVGNS, 'polyline');
    ln.setAttribute('fill', 'none');
    ln.setAttribute('stroke-width', '1.3');
    linesEl.appendChild(ln);
    const dot = document.createElementNS(SVGNS, 'circle');
    dot.setAttribute('r', '3.5');
    dot.setAttribute('fill', '#0A1228');
    dot.setAttribute('stroke-width', '2');
    linesEl.appendChild(dot);
    p.el = el; p.line = ln; p.dot = dot; p.w = 0;
  }
}

const tmp = new THREE.Vector3();
/** Leader-label layout for a W×H view, labels in side columns like a textbook drawing. */
function layout(W, H, which, size) {
  const vis = [];
  for (const p of parts) {
    if (!which(p)) continue;
    p.obj.localToWorld(tmp.copy(p.localCenter));
    tmp.project(camera);
    if (tmp.z > 1) continue;
    const s = size(p);
    vis.push({ p, x: (tmp.x + 1) / 2 * W, y: (1 - tmp.y) / 2 * H, w: s.w, h: s.h });
  }
  if (!vis.length) return vis;
  let cx = 0;
  for (const v of vis) cx += v.x;
  cx /= vis.length;
  const margin = Math.max(8, W * 0.015);
  const left = vis.filter((v) => v.x < cx), right = vis.filter((v) => v.x >= cx);
  for (const [group, side] of [[left, -1], [right, 1]]) {
    group.sort((a, b) => a.y - b.y);
    const gap = 6;
    let y = margin;
    for (const v of group) {
      const want = v.y - v.h / 2;
      y = Math.max(y, Math.min(want, H - margin - v.h));
      v.ly = y; y += v.h + gap;
      v.side = side;
      v.lx = side < 0 ? margin : W - margin - v.w;
    }
    const last = group[group.length - 1];
    if (last && last.ly + last.h > H - margin) {
      const shift = last.ly + last.h - (H - margin);
      for (const v of group) v.ly -= shift;
    }
  }
  return vis;
}

function updateLabels() {
  const W = window.innerWidth, H = window.innerHeight;
  document.body.classList.toggle('compact', W < 560);
  const which = (p) => labelsOn || p.id === selected;
  for (const p of parts) {
    const show = which(p);
    p.el.style.display = show ? 'block' : 'none';
    if (show && !p.w) { p.w = p.el.offsetWidth; p.h = p.el.offsetHeight; }
  }
  const vis = layout(W, H, which, (p) => ({ w: p.w || 90, h: p.h || 30 }));
  const shown = new Set(vis.map((v) => v.p));
  for (const p of parts) {
    const on = shown.has(p);
    if (!on) p.el.style.display = 'none';
    p.line.style.display = on ? '' : 'none';
    p.dot.style.display = on ? '' : 'none';
  }
  for (const v of vis) {
    const sel = v.p.id === selected;
    v.p.el.style.transform = `translate(${v.lx.toFixed(1)}px, ${v.ly.toFixed(1)}px)`;
    const ax = v.side < 0 ? v.lx + v.w : v.lx;
    const ay = v.ly + v.h / 2;
    const elbow = v.side < 0 ? ax + 12 : ax - 12;
    v.p.line.setAttribute('points', `${ax.toFixed(1)},${ay.toFixed(1)} ${elbow.toFixed(1)},${ay.toFixed(1)} ${v.x.toFixed(1)},${v.y.toFixed(1)}`);
    v.p.line.setAttribute('stroke', sel ? AMBER : 'rgba(201,212,219,.85)');
    v.p.dot.setAttribute('cx', v.x.toFixed(1)); v.p.dot.setAttribute('cy', v.y.toFixed(1));
    v.p.dot.setAttribute('stroke', sel ? AMBER : CYAN);
  }
}

// ---------- 2D composition (snapshots + video frames) ----------
function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}

function drawLabels(ctx, W, H, k, only) {
  const fN = `700 ${Math.round(15 * k)}px Cairo, sans-serif`;
  const fE = `400 ${Math.round(11 * k)}px Cairo, sans-serif`;
  const pad = 9 * k, badge = 20 * k;
  const size = (p) => {
    ctx.font = fN; const wn = ctx.measureText(p.ar).width;
    ctx.font = fE; const we = p.en ? ctx.measureText(p.en).width : 0;
    return { w: Math.max(wn, we) + badge + pad * 3, h: (p.en ? 40 : 26) * k };
  };
  const vis = layout(W, H, only ? (p) => p.id === only : () => true, size);
  for (const v of vis) {
    const sel = v.p.id === selected;
    const ax = v.side < 0 ? v.lx + v.w : v.lx, ay = v.ly + v.h / 2;
    const elbow = v.side < 0 ? ax + 16 * k : ax - 16 * k;
    ctx.strokeStyle = sel ? AMBER : 'rgba(201,212,219,.9)';
    ctx.lineWidth = 1.6 * k;
    ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(elbow, ay); ctx.lineTo(v.x, v.y); ctx.stroke();
    ctx.fillStyle = '#0A1228'; ctx.strokeStyle = sel ? AMBER : CYAN; ctx.lineWidth = 2.2 * k;
    ctx.beginPath(); ctx.arc(v.x, v.y, 4.5 * k, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    roundRect(ctx, v.lx, v.ly, v.w, v.h, 8 * k);
    ctx.fillStyle = sel ? AMBER : 'rgba(11,15,18,.92)'; ctx.fill();
    ctx.strokeStyle = sel ? AMBER : '#33414C'; ctx.lineWidth = 1.2 * k; ctx.stroke();
    const bx = v.lx + v.w - pad - badge, by = v.ly + (v.h - badge) / 2;
    roundRect(ctx, bx, by, badge, badge, 6 * k);
    ctx.fillStyle = sel ? '#0A1228' : AMBER; ctx.fill();
    ctx.fillStyle = sel ? AMBER : '#0A1228';
    ctx.font = `700 ${Math.round(12 * k)}px Cairo, sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(String(v.p.n), bx + badge / 2, by + badge / 2 + 0.5 * k);
    ctx.textAlign = 'right'; ctx.direction = 'rtl';
    ctx.fillStyle = sel ? '#0A1228' : '#E8EEF2'; ctx.font = fN;
    const tx = bx - pad * 0.8;
    ctx.fillText(v.p.ar, tx, v.ly + (v.p.en ? 14 * k : v.h / 2));
    if (v.p.en) {
      ctx.direction = 'ltr'; ctx.textAlign = 'right';
      ctx.fillStyle = sel ? '#4a3500' : '#93A3AF'; ctx.font = fE;
      ctx.fillText(v.p.en, tx, v.ly + 29 * k);
    }
    ctx.direction = 'ltr';
  }
}

function paintBackground(ctx, W, H) {
  ctx.fillStyle = '#081024';
  ctx.fillRect(0, 0, W, H);
  ctx.fillStyle = '#1A2738';
  const step = Math.max(12, Math.round(16 * W / 900));
  for (let y = step / 2; y < H; y += step) for (let x = step / 2; x < W; x += step) ctx.fillRect(x, y, 1.4, 1.4);
}

/** Render the current scene into a 2D canvas of W×H, optionally with labels. */
function composeFrame(ctx, W, H, withLabels) {
  renderer.setPixelRatio(1);
  renderer.setSize(W, H, false);
  camera.aspect = W / H;
  camera.updateProjectionMatrix();
  renderer.render(scene, camera);
  paintBackground(ctx, W, H);
  ctx.drawImage(renderer.domElement, 0, 0, W, H);
  if (withLabels && parts.length) drawLabels(ctx, W, H, W / 900);
}

function restoreView() {
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  resize();
}

const nextFrame = () => new Promise((r) => requestAnimationFrame(() => r()));

async function upload(name, blob) {
  const res = await fetch('/upload/' + name, { method: 'POST', body: blob });
  return res.ok;
}

/** Two labelled shots for the lesson sheet: assembled + exploded. */
async function captureSheet(token) {
  if (!root || busy) { bridge('captured', token, false); return; }
  busy = true;
  try {
    await document.fonts.ready;
    const W = 1600, H = 1100;
    const canvas = document.createElement('canvas');
    canvas.width = W; canvas.height = H;
    const ctx = canvas.getContext('2d');
    const keep = { e: explode, t: explodeTarget, sel: selected };
    select(null);
    const shots = [];
    for (const t of parts.length ? [0, 1] : [0]) {
      explode = explodeTarget = t; applyExplode();
      camera.aspect = W / H;
      const g = goalFor(t);
      setNearFar(g.dist);
      controls.target.copy(g.target);
      camera.position.copy(g.target).addScaledVector(VIEW_DIR, g.dist * (t ? 1.18 : 1.0));
      camera.lookAt(g.target);
      camera.updateProjectionMatrix();
      await nextFrame();
      composeFrame(ctx, W, H, t === 1);
      const blob = await new Promise((r) => canvas.toBlob(r, 'image/jpeg', 0.92));
      const name = `${token}_${t ? 'exploded' : 'assembled'}.jpg`;
      await upload(name, blob);
      shots.push(name);
    }
    explode = keep.e; explodeTarget = keep.t; applyExplode(); select(keep.sel);
    restoreView();
    refit(true);
    busy = false;
    bridge('captured', token, shots.join(','));
  } catch (e) {
    busy = false;
    restoreView();
    bridge('captured', token, false);
  }
}

/** Presentation video: turntable → explode with labels → assemble. Recorded with MediaRecorder. */
async function recordVideo(token) {
  if (!root || busy) { bridge('recorded', token, false); return; }
  if (!window.MediaRecorder || !HTMLCanvasElement.prototype.captureStream) { bridge('recorded', token, 'unsupported'); return; }
  busy = true;
  const W = 1280, H = 720, FPS = 30;
  const canvas = document.createElement('canvas');
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext('2d');
  const types = ['video/mp4;codecs=avc1.42E01E', 'video/mp4', 'video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm'];
  const mime = types.find((t) => MediaRecorder.isTypeSupported(t)) || '';
  const ext = mime.startsWith('video/mp4') ? 'mp4' : 'webm';
  const stream = canvas.captureStream(FPS);
  const rec = new MediaRecorder(stream, mime ? { mimeType: mime, videoBitsPerSecond: 6000000 } : { videoBitsPerSecond: 6000000 });
  const chunks = [];
  rec.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data); };
  const done = new Promise((r) => { rec.onstop = r; });
  await document.fonts.ready;
  const keepSel = selected;
  select(null);
  const hasParts = parts.length > 0;
  const T = hasParts ? 16 : 8;
  const baseAz = Math.atan2(VIEW_DIR.x, VIEW_DIR.z);
  // paint one frame before starting so the video doesn't open on black
  composeFrame(ctx, W, H, false);
  rec.start(250);
  const start = performance.now();
  let lastPct = -1;
  while (true) {
    const s = (performance.now() - start) / 1000;
    if (s > T) break;
    // timeline (s): 0–4 turntable · 4–6.5 explode · 6.5–12 labelled · 12–14.5 assemble · hold
    let e = 0;
    if (hasParts) {
      if (s < 4) e = 0;
      else if (s < 6.5) e = (s - 4) / 2.5;
      else if (s < 12) e = 1;
      else if (s < 14.5) e = 1 - (s - 12) / 2.5;
    }
    explode = explodeTarget = Math.min(1, Math.max(0, e)); applyExplode();
    camera.aspect = W / H;
    const g = goalFor(explode);
    setNearFar(g.dist);
    const az = baseAz + Math.sin((s / T) * Math.PI * 2) * 0.55;
    const dir = new THREE.Vector3(Math.sin(az) * 0.9, VIEW_DIR.y, Math.cos(az) * 0.9).normalize();
    controls.target.copy(g.target);
    camera.position.copy(g.target).addScaledVector(dir, g.dist * (1 + 0.12 * smooth(explode)));
    camera.lookAt(g.target);
    composeFrame(ctx, W, H, hasParts && s > 6.2 && s < 12.2);
    const k = W / 900;
    ctx.fillStyle = 'rgba(11,15,18,.8)';
    ctx.fillRect(0, H - 56 * k, W, 56 * k);
    ctx.fillStyle = AMBER;
    ctx.fillRect(0, H - 56 * k, W, 3 * k);
    ctx.textBaseline = 'middle';
    ctx.direction = 'rtl'; ctx.textAlign = 'right';
    ctx.fillStyle = '#E8EEF2'; ctx.font = `700 ${Math.round(21 * k)}px Cairo, sans-serif`;
    ctx.fillText(meta.ar, W - 22 * k, H - 30 * k);
    ctx.direction = 'ltr'; ctx.textAlign = 'left';
    ctx.fillStyle = '#93A3AF'; ctx.font = `600 ${Math.round(12.5 * k)}px Cairo, sans-serif`;
    ctx.fillText('Control Academy · ' + meta.en, 22 * k, H - 30 * k);
    const pct = Math.round((s / T) * 100);
    if (pct !== lastPct) { lastPct = pct; bridge('progress', token, pct); }
    await nextFrame();
  }
  rec.stop();
  await done;
  select(keepSel);
  explode = explodeTarget = 0; applyExplode();
  restoreView();
  refit(true, 0);
  busy = false;
  const blob = new Blob(chunks, { type: mime || 'video/webm' });
  const name = `${token}.${ext}`;
  const ok = await upload(name, blob).catch(() => false);
  bridge('recorded', token, ok ? name : false);
}

/**
 * Narrated lesson video: opening and introduction while the model turns, the model
 * comes apart, every part is highlighted and explained in turn (its own recorded
 * narration, with subtitles), then it is assembled again and the lesson closes.
 * Video (canvas) and narration (Web Audio) go into one MediaRecorder stream.
 * plan: {title, en, steps: [{kind: 'open'|'part'|'close', part?, audio, title, text}]}
 */
async function recordLesson(token, plan) {
  if (!root || busy) { bridge('recorded', token, false); return; }
  if (!window.MediaRecorder || !HTMLCanvasElement.prototype.captureStream) { bridge('recorded', token, 'unsupported'); return; }
  busy = true;
  const W = 1280, H = 720, FPS = 30;
  const canvas = document.createElement('canvas');
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext('2d');
  const AC = window.AudioContext || window.webkitAudioContext;
  const ac = new AC();
  try { await ac.resume(); } catch (_) {}
  const dest = ac.createMediaStreamDestination();
  // load every narration clip first
  const bufs = await Promise.all(plan.steps.map(async (st) => {
    if (!st.audio) return null;
    try {
      const r = await fetch('/assets/audio/' + st.audio);
      if (!r.ok) return null;
      return await ac.decodeAudioData(await r.arrayBuffer());
    } catch (_) { return null; }
  }));
  const types = ['video/mp4;codecs=avc1.42E01E,mp4a.40.2', 'video/mp4', 'video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm'];
  const mime = types.find((t) => MediaRecorder.isTypeSupported(t)) || '';
  const ext = mime.startsWith('video/mp4') ? 'mp4' : 'webm';
  const vs = canvas.captureStream(FPS);
  const stream = new MediaStream([...vs.getVideoTracks(), ...dest.stream.getAudioTracks()]);
  const rec = new MediaRecorder(stream, mime ? { mimeType: mime, videoBitsPerSecond: 6000000 } : { videoBitsPerSecond: 6000000 });
  const chunks = [];
  rec.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data); };
  const done = new Promise((r) => { rec.onstop = r; });
  await document.fonts.ready;
  const keepSel = selected;
  select(null);
  const hasParts = parts.length > 0;
  const baseAz = Math.atan2(VIEW_DIR.x, VIEW_DIR.z);
  // timeline: [kind, seconds, step index | -1]
  const segs = [];
  plan.steps.forEach((st, i) => {
    const d = bufs[i] ? bufs[i].duration + 0.7 : 3.2;
    if (st.kind === 'part' && segs.length && segs[segs.length - 1][0] !== 'part' && segs[segs.length - 1][0] !== 'explode') segs.push(['explode', 2.4, -1]);
    if (st.kind === 'close' && hasParts) segs.push(['assemble', 2.6, -1]);
    if (st.kind !== 'part' || hasParts) segs.push([st.kind, d, i]);
  });
  const total = segs.reduce((a, s) => a + s[1], 0);
  composeFrame(ctx, W, H, false);
  rec.start(250);
  const t0 = performance.now();
  let elapsedBefore = 0, lastPct = -1, az = 0;
  const k = W / 900;
  const wrap = (text, maxW) => {
    const words = text.split(/\s+/), lines = [];
    let cur = '';
    for (const w of words) {
      const t = cur ? cur + ' ' + w : w;
      if (ctx.measureText(t).width > maxW && cur) { lines.push(cur); cur = w; } else cur = t;
    }
    if (cur) lines.push(cur);
    return lines;
  };
  for (const [kind, dur, idx] of segs) {
    const st = idx >= 0 ? plan.steps[idx] : null;
    if (idx >= 0 && bufs[idx]) {
      const src = ac.createBufferSource();
      src.buffer = bufs[idx];
      src.connect(dest);
      src.connect(ac.destination); // heard while recording too
      src.start();
    }
    if (st && st.kind === 'part') select(st.part); else select(null);
    // subtitles: sentences shown in proportion to their length
    const sentences = st && st.text ? st.text.split(/(?<=[.!؟?،:])\s+/).filter((x) => x.trim()) : [];
    const lens = sentences.map((x) => x.length), sum = lens.reduce((a, b) => a + b, 0) || 1;
    const segStart = performance.now();
    while (true) {
      const s = (performance.now() - segStart) / 1000;
      if (s > dur) break;
      const u = s / dur;
      let e = 0;
      if (kind === 'explode') e = smooth(u);
      else if (kind === 'part') e = 1;
      else if (kind === 'assemble') e = 1 - smooth(u);
      if (!hasParts) e = 0;
      explode = explodeTarget = Math.min(1, Math.max(0, e)); applyExplode();
      camera.aspect = W / H;
      const g = goalFor(explode);
      let target = g.target.clone(), dist = g.dist * (1 + 0.1 * smooth(explode));
      if (kind === 'part') {
        const p = parts.find((x) => x.id === st.part);
        if (p) {
          const c = p.obj.localToWorld(p.localCenter.clone());
          const z = smooth(Math.min(1, s / 1.2));
          target = target.lerp(c, 0.45 * z);
          dist *= 1 - 0.22 * z;
        }
      }
      setNearFar(dist);
      az += 0.0022;
      const a = baseAz + Math.sin(az * 2.2) * 0.5;
      const dir = new THREE.Vector3(Math.sin(a) * 0.9, VIEW_DIR.y, Math.cos(a) * 0.9).normalize();
      controls.target.copy(target);
      camera.position.copy(target).addScaledVector(dir, dist);
      camera.lookAt(target);
      composeFrame(ctx, W, H, false);
      if (kind === 'part' && st) drawLabels(ctx, W, H, k * 1.15, st.part);
      // title card for opening / closing
      if (kind === 'open' || kind === 'close') {
        const a2 = Math.min(1, s / 0.6, (dur - s) / 0.6);
        ctx.globalAlpha = Math.max(0, a2);
        ctx.fillStyle = 'rgba(7,12,26,.55)';
        ctx.fillRect(0, H * 0.08, W, 92 * k);
        ctx.direction = 'rtl'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillStyle = '#FFFFFF'; ctx.font = `800 ${Math.round(34 * k)}px Cairo, sans-serif`;
        ctx.fillText(plan.title, W / 2, H * 0.08 + 36 * k);
        ctx.fillStyle = '#9FB4D8'; ctx.font = `600 ${Math.round(14 * k)}px Cairo, sans-serif`;
        ctx.direction = 'ltr';
        ctx.fillText(plan.en + ' · Control Academy', W / 2, H * 0.08 + 72 * k);
        ctx.globalAlpha = 1;
      }
      // bottom bar: step title + subtitle line
      const barH = 92 * k;
      ctx.fillStyle = 'rgba(7,12,26,.82)';
      ctx.fillRect(0, H - barH, W, barH);
      ctx.fillStyle = AMBER;
      ctx.fillRect(0, H - barH, W * ((elapsedBefore + s) / total), 3 * k);
      ctx.textBaseline = 'middle';
      ctx.direction = 'rtl'; ctx.textAlign = 'right';
      ctx.fillStyle = CYAN; ctx.font = `700 ${Math.round(15 * k)}px Cairo, sans-serif`;
      const head = st ? (st.kind === 'part' ? `${(parts.find((x) => x.id === st.part) || {}).n || ''}. ${st.title}` : st.title) : (kind === 'explode' ? 'فك المكوّن' : 'إعادة التركيب');
      ctx.fillText(head, W - 22 * k, H - barH + 20 * k);
      if (sentences.length) {
        let acc = 0, cur = sentences[sentences.length - 1];
        for (let j = 0; j < sentences.length; j++) {
          acc += lens[j] / sum;
          if (u * 1.03 <= acc) { cur = sentences[j]; break; }
        }
        ctx.fillStyle = '#E8EEF2'; ctx.font = `500 ${Math.round(14.5 * k)}px Cairo, sans-serif`;
        const lines = wrap(cur, W - 44 * k).slice(0, 2);
        lines.forEach((ln, j) => ctx.fillText(ln, W - 22 * k, H - barH + (46 + j * 24) * k));
      }
      const pct = Math.round(((elapsedBefore + s) / total) * 100);
      if (pct !== lastPct) { lastPct = pct; bridge('progress', token, pct); }
      await nextFrame();
    }
    elapsedBefore += dur;
  }
  rec.stop();
  await done;
  try { ac.close(); } catch (_) {}
  select(keepSel);
  explode = explodeTarget = 0; applyExplode();
  restoreView();
  refit(true, 0);
  busy = false;
  const blob = new Blob(chunks, { type: mime || 'video/webm' });
  const name = `${token}.${ext}`;
  const ok = await upload(name, blob).catch(() => false);
  bridge('recorded', token, ok ? name : false);
}

// ---------- loop ----------
function resize() {
  const W = window.innerWidth, H = window.innerHeight;
  renderer.setSize(W, H);
  camera.aspect = W / Math.max(H, 1);
  camera.updateProjectionMatrix();
  linesEl.setAttribute('width', W);
  linesEl.setAttribute('height', H);
  for (const p of parts) p.w = 0;
}
window.addEventListener('resize', () => { if (!busy) resize(); });
resize();

function tick() {
  requestAnimationFrame(tick);
  if (busy) return;
  if (explode !== explodeTarget) {
    const step = 0.04;
    explode = explode < explodeTarget ? Math.min(explodeTarget, explode + step) : Math.max(explodeTarget, explode - step);
    applyExplode();
  }
  if (camGoal) {
    controls.target.lerp(camGoal.target, 0.12);
    const dir = camera.position.clone().sub(controls.target).normalize();
    const cur = camera.position.distanceTo(controls.target);
    const nd = cur + (camGoal.dist - cur) * 0.12;
    camera.position.copy(controls.target).addScaledVector(dir, nd);
    if (controls.target.distanceTo(camGoal.target) < camGoal.dist * 1e-3 && Math.abs(nd - camGoal.dist) < camGoal.dist * 1e-3) camGoal = null;
  }
  controls.update();
  renderer.render(scene, camera);
  if (parts.length) updateLabels();
}
tick();

// ---------- API for Flutter ----------
window.cc = {
  load,
  setExplode(t) { explodeTarget = Math.min(1, Math.max(0, Number(t) || 0)); refit(false); },
  scrub(t) {
    const v = Math.min(1, Math.max(0, Number(t) || 0));
    explode = explodeTarget = v; applyExplode();
    if (boxA) { const g = goalFor(v); setNearFar(g.dist); camGoal = g; }
  },
  setLabels(on) { labelsOn = !!on; },
  select(id) { select(id); },
  focus(id) { select(id); focusPart(id); },
  reset() { refit(true); },
  captureSheet,
  recordVideo,
  recordLesson,
};

let announced = false;
const announce = () => { if (!announced && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) { announced = true; bridge('ready'); } };
window.addEventListener('flutterInAppWebViewPlatformReady', announce);
announce();

const q = new URLSearchParams(location.search).get('model');
if (q) load('/assets/models/' + q, q, q);
