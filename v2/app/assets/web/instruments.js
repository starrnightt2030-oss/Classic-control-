// «أجهزة القياس»: the measuring instruments in 3D (GLB models from v2/models/instruments.py).
//
// Flutter owns the simulation (lib/meters/): it sends the whole state a few times a second with
// inst.update({...}) and this page draws it: the needle swings with a little overshoot, the knob
// turns, the LCD shows the reading, the test leads plug into the jacks and the probes move onto
// the terminals with their cables hanging between. A tap on anything that matters (a part, a jack,
// a test point, a breaker lever) goes back to Flutter as tap(name).
// Blender axes -> three.js: x -> x, z (up) -> y, y -> -z. An empty's Blender Z is its local +Y here.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const bridge = (name, ...args) => {
  try { const b = window.flutter_inappwebview; if (b && b.callHandler) return b.callHandler(name, ...args); } catch (e) { /* preview */ }
  return undefined;
};
const msg = document.getElementById('msg');
const pipBox = document.getElementById('pip');
const labelsBox = document.getElementById('labels');

const params = new URLSearchParams(location.search);
const LITE = params.get('q') === 'lite';
const FPS = LITE ? 30 : 45;
let ratio = Math.min(window.devicePixelRatio || 1, LITE ? 1 : 1.75);

const renderer = new THREE.WebGLRenderer({ antialias: !LITE, alpha: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(ratio);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.shadowMap.enabled = !LITE;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.autoClear = false;
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.02).texture;
scene.environmentIntensity = 0.75;
const sun = new THREE.DirectionalLight(0xfff2e0, 2.0);
sun.castShadow = !LITE;
sun.shadow.mapSize.set(1024, 1024);
sun.shadow.bias = -0.0004;
sun.shadow.normalBias = 0.01;
scene.add(sun, sun.target);
const fillL = new THREE.DirectionalLight(0xc8dcff, 0.55);
scene.add(fillL, fillL.target);
scene.add(new THREE.HemisphereLight(0xdfe8f5, 0x1a2030, 0.4));

const camera = new THREE.PerspectiveCamera(38, 1, 0.005, 60);
const pipCam = new THREE.PerspectiveCamera(30, 1, 0.005, 10);
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.09;
controls.screenSpacePanning = true;
controls.addEventListener('start', () => { dragging = true; wake(); });
controls.addEventListener('end', () => { dragging = false; wake(800); });
controls.addEventListener('change', () => wake(400));

let awakeUntil = 0, dragging = false;
function wake(ms = 600) { awakeUntil = Math.max(awakeUntil, performance.now() + ms); }

const loader = new GLTFLoader();
const glbCache = new Map();
function loadGLB(url) {
  if (!glbCache.has(url)) glbCache.set(url, new Promise((ok, bad) => loader.load(url, ok, undefined, bad)));
  return glbCache.get(url);
}

// ------------------------------------------------------------------ state
let token = 0;
let instKey = '', benchKey = '';
let instRoot = null, instModel = null, benchRoot = null;
let N = {};          // instrument nodes by name
let BN = {};         // bench nodes by name
let protos = {};     // lead protos (probe_red, plug_red, croc_red …)
let state = {};
let lcd = null;      // { canvas, ctx, tex, key }
let jawLocal = null; // jaw_center relative to the instrument root
let restPose = null; // instrument resting matrix (from the mount)
const leads = new Map();
const markers = new Map();
const sparks = [];
let lastSpark = -1;
let highlightKey = '';
let partLabel = null;

const SWEEP = THREE.MathUtils.degToRad(45);
const cur = { needle: 0, needleV: 0, knob: 0, jaw: 0, test: 0, clampT: 0, shaft: 0 };
const v3 = () => new THREE.Vector3();

function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  renderer.domElement.style.width = w + 'px';
  renderer.domElement.style.height = h + 'px';
  camera.aspect = w / Math.max(1, h);
  camera.updateProjectionMatrix();
  layoutPip();
  wake();
}
window.addEventListener('resize', resize);

// ------------------------------------------------------------------ loading
function clear() {
  for (const r of [instRoot, benchRoot]) if (r) scene.remove(r);
  for (const l of leads.values()) disposeLead(l);
  leads.clear();
  for (const m of markers.values()) scene.remove(m.g);
  markers.clear();
  labelsBox.textContent = '';
  instRoot = instModel = benchRoot = null;
  N = {}; BN = {}; lcd = null; jawLocal = null; restPose = null; highlightKey = ''; partLabel = null;
  for (const k of Object.keys(cur)) cur[k] = 0;
}

function index(root, into) {
  root.traverse((o) => {
    if (o.name && !(o.name in into)) into[o.name] = o;
    if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; }
  });
}

async function load(spec) {
  spec = spec || {};
  const my = ++token;
  clear();
  msg.style.display = 'flex';
  instKey = spec.instrument || 'avo';
  benchKey = spec.bench || '';
  try {
    const jobs = [loadGLB('/assets/models/inst_' + instKey + '.glb'), loadGLB('/assets/models/inst_leads.glb')];
    if (benchKey) jobs.push(loadGLB('/assets/models/inst_' + benchKey + '.glb'));
    const [gi, gl, gb] = await Promise.all(jobs);
    if (my !== token) return;
    instRoot = new THREE.Group();
    instModel = gi.scene.clone(true);
    instRoot.add(instModel);
    index(instModel, N);
    // own materials, so a highlight never lights another part
    instModel.traverse((o) => { if (o.isMesh) { o.material = o.material.clone(); o.userData.e0 = o.material.emissive ? o.material.emissive.clone() : null; } });
    scene.add(instRoot);
    protos = {};
    for (const c of gl.scene.children) protos[c.name] = c;
    if (N.lcd) makeLcd(N.lcd);
    if (N.lamp_live) { const m = meshOf(N.lamp_live); if (m) m.material.emissive = new THREE.Color(0, 0, 0); }
    if (gb) {
      benchRoot = gb.scene.clone(true);
      index(benchRoot, BN);
      scene.add(benchRoot);
      benchRoot.updateMatrixWorld(true);
      const mount = BN[spec.mount || 'mount_meter'];
      if (mount) { restPose = mount.matrixWorld.clone(); }
    }
    if (!restPose) restPose = new THREE.Matrix4();
    localBox = boxOf(instModel);
    setMatrix(instRoot, restPose);
    instRoot.updateMatrixWorld(true);
    if (N.jaw_center) {
      jawLocal = new THREE.Matrix4().copy(instRoot.matrixWorld).invert().multiply(N.jaw_center.matrixWorld);
    }
    fitLights();
    if (benchKey) focus('all', true); else fitInstrument(true);
    msg.style.display = 'none';
    layoutPip();
    apply(0, true);
    wake(1500);
    bridge('loaded', instKey, benchKey);
  } catch (e) {
    msg.textContent = 'تعذّر تحميل المجسم';
    console.log('load failed', e && e.message);
  }
}

function meshOf(o) { let m = null; o.traverse((c) => { if (!m && c.isMesh) m = c; }); return m; }
function setMatrix(o, m) { m.decompose(o.position, o.quaternion, o.scale); }

function boxOf(o) {
  const b = new THREE.Box3();
  o.updateMatrixWorld(true);
  o.traverse((c) => { if (c.isMesh && c.visible) b.expandByObject(c); });
  return b;
}

function fitLights() {
  const b = boxOf(benchRoot || instRoot);
  const c = b.getCenter(v3()), r = Math.max(0.15, b.getSize(v3()).length() / 2);
  sun.position.copy(c).add(new THREE.Vector3(0.7, 1.6, 1.0).multiplyScalar(r * 1.2));
  sun.target.position.copy(c);
  const sc = sun.shadow.camera;
  sc.left = sc.bottom = -r; sc.right = sc.top = r; sc.near = r * 0.05; sc.far = r * 5;
  sc.updateProjectionMatrix();
  fillL.position.copy(c).add(new THREE.Vector3(-1.2, 0.4, 0.9).multiplyScalar(r));
  fillL.target.position.copy(c);
}

// ------------------------------------------------------------------ camera
let camAnim = null;
function moveCamera(pos, target, snap) {
  const near = Math.max(0.005, pos.distanceTo(target) / 200);
  camera.near = near; camera.far = near * 4000; camera.updateProjectionMatrix();
  if (snap) { camera.position.copy(pos); controls.target.copy(target); controls.update(); camAnim = null; return; }
  camAnim = { p0: camera.position.clone(), t0: controls.target.clone(), p1: pos.clone(), t1: target.clone(), t: 0 };
  wake(1200);
}

function fitInstrument(snap) {
  const b = boxOf(instRoot);
  const c = b.getCenter(v3()), r = b.getSize(v3()).length() / 2;
  const dist = r / Math.sin(THREE.MathUtils.degToRad(camera.fov / 2)) * (camera.aspect < 1 ? 1.0 / camera.aspect : 0.85);
  const dir = new THREE.Vector3(0.32, 0.22, 1).normalize();
  controls.minDistance = r * 0.6; controls.maxDistance = dist * 3;
  controls.maxPolarAngle = Math.PI;
  moveCamera(c.clone().addScaledVector(dir, dist), c, snap);
}

let localBox = null;  // the instrument's own box, before it is placed
function faceFrame() {
  const f = N.view_face || instRoot;
  const n = new THREE.Vector3(0, 1, 0).applyQuaternion(f.getWorldQuaternion(new THREE.Quaternion()));
  const lb = localBox || new THREE.Box3(v3(), v3().setScalar(0.1));
  const p = instRoot.localToWorld(lb.getCenter(v3()));
  const s = lb.getSize(v3());
  return { p, n, size: s.length(), w: s.x, h: s.y, d: s.z };
}

function focus(name, snap) {
  if (name === 'meter' && instRoot) {
    const { p, n, size } = faceFrame();
    const up = new THREE.Vector3(0, 1, 0);
    moveCamera(p.clone().addScaledVector(n, size * 1.5).addScaledVector(up, size * 0.15), p, snap);
    return;
  }
  const t = BN['view_' + name], c = BN['cam_' + name];
  if (!t || !c) { fitInstrument(snap); return; }
  const tp = t.getWorldPosition(v3()), cp = c.getWorldPosition(v3());
  const d = tp.distanceTo(cp);
  controls.minDistance = 0.08; controls.maxDistance = Math.max(3, d * 2.5);
  controls.maxPolarAngle = Math.PI * 0.53;
  moveCamera(cp, tp, snap);
}

// ------------------------------------------------------------------ LCD
const SEG = { '0': 'abcdef', '1': 'bc', '2': 'abged', '3': 'abgcd', '4': 'fgbc', '5': 'afgcd', '6': 'afgedc', '7': 'abc', '8': 'abcdefg', '9': 'abcdfg', '-': 'g', 'O': 'abcdef', 'L': 'fed', ' ': '', 'E': 'afged', 'r': 'eg', 'F': 'afge', 'U': 'bcdef', 'S': 'afgcd', 'P': 'abfge', 'n': 'ceg', 'o': 'cdeg', 'b': 'fgcde', 'A': 'abcefg', 't': 'fged', 'H': 'fgbce', 'd': 'bcdeg' };
function makeLcd(node) {
  const mesh = meshOf(node);
  if (!mesh) return;
  const canvas = document.createElement('canvas');
  canvas.width = 512; canvas.height = 368;
  const tex = new THREE.CanvasTexture(canvas);
  tex.flipY = false;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  mesh.material = new THREE.MeshStandardMaterial({ map: tex, emissiveMap: tex, emissive: new THREE.Color(0.55, 0.6, 0.55), roughness: 0.35, metalness: 0 });
  lcd = { canvas, ctx: canvas.getContext('2d'), tex, key: '' };
  drawLcd({});
}

function seg(ctx, x, y, w, h, s, on) {
  // one 7-segment digit, slightly slanted; s = segment thickness
  const k = 0.12 * h; // slant
  const P = (px, py) => [x + px + k * (1 - py / h), y + py];
  const H = (y0) => [P(s * 0.6, y0), P(w - s * 0.6, y0), P(w - s * 1.1, y0 + s / 2), P(w - s * 0.6, y0 + s), P(s * 0.6, y0 + s), P(s * 0.1, y0 + s / 2)];
  const V = (x0, y0, y1) => [P(x0 + s / 2, y0), P(x0 + s, y0 + s * 0.5), P(x0 + s, y1 - s * 0.5), P(x0 + s / 2, y1), P(x0, y1 - s * 0.5), P(x0, y0 + s * 0.5)];
  const m = h / 2 - s / 2;
  const shapes = {
    a: H(0), g: H(m), d: H(h - s),
    f: V(0, s * 0.55, m + s * 0.45), b: V(w - s, s * 0.55, m + s * 0.45),
    e: V(0, m + s * 0.55, h - s * 0.55), c: V(w - s, m + s * 0.55, h - s * 0.55),
  };
  for (const [name, pts] of Object.entries(shapes)) {
    ctx.fillStyle = on.includes(name) ? '#121712' : 'rgba(20,30,20,0.07)';
    ctx.beginPath();
    pts.forEach(([px, py], i) => (i ? ctx.lineTo(px, py) : ctx.moveTo(px, py)));
    ctx.closePath();
    ctx.fill();
  }
}

function drawLcd(L) {
  if (!lcd) return;
  const key = JSON.stringify(L || {});
  if (key === lcd.key) return;
  lcd.key = key;
  const { ctx, canvas } = lcd;
  const W = canvas.width, H = canvas.height;
  const g = ctx.createLinearGradient(0, 0, 0, H);
  const lit = L && L.on;
  g.addColorStop(0, lit ? '#B9C8B1' : '#8E9A8A');
  g.addColorStop(1, lit ? '#A7B69F' : '#80897C');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
  if (!lit) { lcd.tex.needsUpdate = true; return; }
  const txt = String(L.t ?? '');
  // digits: up to 4 digits + sign, decimal points between
  const chars = [];
  for (const ch of txt) { if (ch === '.' && chars.length) chars[chars.length - 1].dp = true; else chars.push({ c: ch, dp: false }); }
  while (chars.length < 4) chars.unshift({ c: ' ', dp: false });
  const dw = 88, dh = 170, gap = 22, s = 17;
  const x0 = W - 28 - chars.length * (dw + gap);
  const y0 = 108;
  chars.forEach((d, i) => {
    const x = x0 + i * (dw + gap);
    if (d.c === '-' && i === 0) { ctx.fillStyle = '#121712'; ctx.fillRect(x + 10, y0 + dh / 2 - 8, dw - 20, 16); }
    else seg(ctx, x, y0, dw, dh, s, SEG[d.c] ?? '');
    if (d.dp) { ctx.fillStyle = '#121712'; ctx.beginPath(); ctx.arc(x + dw + gap / 2 - 2, y0 + dh - 6, 8, 0, Math.PI * 2); ctx.fill(); }
  });
  ctx.fillStyle = '#121712';
  ctx.font = 'bold 40px sans-serif';
  ctx.textAlign = 'left';
  if (L.ac) ctx.fillText('AC', 26, 66);
  if (L.dc) ctx.fillText('DC', 26, 66);
  if (L.auto) { ctx.font = 'bold 30px sans-serif'; ctx.fillText('AUTO', 110, 62); }
  if (L.hold) { ctx.font = 'bold 30px sans-serif'; ctx.fillText('HOLD', 220, 62); }
  if (L.beep) { ctx.font = 'bold 36px sans-serif'; ctx.fillText('•)))', 340, 66); }
  if (L.bat) { ctx.strokeStyle = '#121712'; ctx.lineWidth = 4; ctx.strokeRect(430, 34, 56, 28); ctx.fillRect(486, 42, 6, 12); }
  ctx.font = 'bold 52px sans-serif';
  ctx.textAlign = 'right';
  ctx.fillText(L.u || '', W - 26, H - 26);
  if (L.small) { ctx.textAlign = 'left'; ctx.font = 'bold 34px sans-serif'; ctx.fillText(L.small, 26, H - 30); }
  lcd.tex.needsUpdate = true;
}

// ------------------------------------------------------------------ leads
const leadMats = {
  red: new THREE.MeshStandardMaterial({ color: 0x8a0a08, roughness: 0.5 }),
  black: new THREE.MeshStandardMaterial({ color: 0x111113, roughness: 0.5 }),
  yellow: new THREE.MeshStandardMaterial({ color: 0xc89000, roughness: 0.5 }),
  blue: new THREE.MeshStandardMaterial({ color: 0x0b3aa0, roughness: 0.5 }),
};

function protoClone(name) {
  const p = protos[name];
  if (!p) return new THREE.Group();
  const c = p.clone(true);
  c.position.set(0, 0, 0);
  c.quaternion.identity();
  c.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return c;
}

function makeLead(spec) {
  const col = spec.color === 'black' ? 'black' : 'red';
  const kind = spec.kind === 'croc' ? 'croc' : 'probe';
  const plug = protoClone('plug_' + col);
  const tip = protoClone(kind + '_' + col);
  const cable = new THREE.Mesh(new THREE.BufferGeometry(), leadMats[spec.cable || col] || leadMats[col]);
  cable.castShadow = true;
  scene.add(plug, tip, cable);
  return { id: spec.id, kind, plug, tip, cable, key: '', plugA: null, tipA: null, jack: undefined, at: undefined, plugged: 0 };
}

function disposeLead(l) {
  scene.remove(l.plug, l.tip, l.cable);
  l.cable.geometry.dispose();
}

const Y = new THREE.Vector3(0, 1, 0);
function axisOf(o) { return Y.clone().applyQuaternion(o.quaternion); }

function jackPose(jack) {
  const j = N['J_' + jack];
  if (!j) return null;
  return { p: j.getWorldPosition(v3()), q: j.getWorldQuaternion(new THREE.Quaternion()) };
}

function pointPose(id) {
  const o = BN[id];
  if (!o) return null;
  return { p: o.getWorldPosition(v3()), q: o.getWorldQuaternion(new THREE.Quaternion()) };
}

// a probe that is not on anything hangs below its plug
function hangPose(plugP, i) {
  const p = plugP.clone().add(new THREE.Vector3(0.02 + 0.03 * i, -0.30, 0.04 + 0.02 * i));
  const q = new THREE.Quaternion().setFromUnitVectors(Y, new THREE.Vector3(0.1, 1, 0.12).normalize());
  return { p, q };
}

function restPlugPose(i) {
  // unplugged: lying under the instrument
  const b = boxOf(instModel);
  const p = new THREE.Vector3(b.min.x - 0.03 - i * 0.02, b.min.y + 0.01, b.max.z + 0.02);
  const q = new THREE.Quaternion().setFromUnitVectors(Y, new THREE.Vector3(-1, 0.2, 0.3).normalize());
  return { p, q };
}

function animTo(obj, anim, target, dt, lift) {
  // ease along an arc lifted by `lift` metres along the target's axis
  if (!anim.to || !anim.to.p.equals(target.p) || !anim.to.q.equals(target.q)) {
    anim.from = { p: obj.position.clone(), q: obj.quaternion.clone() };
    anim.to = { p: target.p.clone(), q: target.q.clone() };
    anim.t = anim.snap ? 1 : 0;
  }
  if (anim.t >= 1) { obj.position.copy(anim.to.p); obj.quaternion.copy(anim.to.q); return false; }
  anim.t = Math.min(1, anim.t + dt / 0.55);
  const e = anim.t < 0.5 ? 2 * anim.t * anim.t : 1 - Math.pow(-2 * anim.t + 2, 2) / 2;
  obj.position.lerpVectors(anim.from.p, anim.to.p, e);
  obj.position.addScaledVector(axisOf({ quaternion: anim.to.q }), Math.sin(Math.PI * e) * lift);
  obj.quaternion.slerpQuaternions(anim.from.q, anim.to.q, e);
  return true;
}

function cableCurve(l) {
  const a = l.plug.position.clone().addScaledVector(axisOf(l.plug), 0.044);
  const b = l.tip.position.clone().addScaledVector(axisOf(l.tip), l.kind === 'croc' ? 0.074 : 0.133);
  const a1 = a.clone().addScaledVector(axisOf(l.plug), 0.05);
  const b1 = b.clone().addScaledVector(axisOf(l.tip), 0.05);
  const d = a1.distanceTo(b1);
  const sag = Math.max(0.03, Math.sqrt(Math.max(0, 1.1 * 1.1 - d * d)) * 0.38);
  const mid = a1.clone().lerp(b1, 0.5).add(new THREE.Vector3(0, -sag, 0));
  return new THREE.CatmullRomCurve3([a, a1, a1.clone().lerp(mid, 0.6).add(new THREE.Vector3(0, -sag * 0.25, 0)), mid, b1.clone().lerp(mid, 0.6).add(new THREE.Vector3(0, -sag * 0.25, 0)), b1, b], false, 'centripetal');
}

function updateLeads(dt, snap) {
  let moving = false;
  const want = new Set((state.leads || []).map((s) => s.id));
  for (const [id, l] of leads) if (!want.has(id)) { disposeLead(l); leads.delete(id); }
  (state.leads || []).forEach((s, i) => {
    let l = leads.get(s.id);
    if (!l || l.kind !== (s.kind === 'croc' ? 'croc' : 'probe')) {
      if (l) disposeLead(l);
      l = makeLead(s);
      l.plugA = { snap: true }; l.tipA = { snap: true };
      leads.set(s.id, l);
    }
    const plugged = !!(s.jack && jackPose(s.jack));
    const pp = plugged ? jackPose(s.jack) : restPlugPose(i);
    if (snap) { l.plugA.snap = true; l.tipA.snap = true; }
    moving = animTo(l.plug, l.plugA, pp, dt, plugged ? 0.05 : 0.0) || moving;
    l.plugA.snap = false;
    const on = s.at ? pointPose(s.at) : null;
    const tp = on || (plugged ? hangPose(pp.p, i) : { p: pp.p.clone().add(new THREE.Vector3(0.01, 0, 0.05 + 0.03 * i)), q: pp.q.clone() });
    moving = animTo(l.tip, l.tipA, tp, dt, on ? 0.08 : 0.0) || moving;
    l.tipA.snap = false;
    const vis = plugged || !!on || s.show;
    l.plug.visible = l.tip.visible = l.cable.visible = vis;
    if (vis) {
      const key = [l.plug.position, l.tip.position].map((p) => p.toArray().map((x) => x.toFixed(4)).join(',')).join('|') + l.plug.quaternion.w.toFixed(3) + l.tip.quaternion.w.toFixed(3);
      if (key !== l.key) {
        l.key = key;
        l.cable.geometry.dispose();
        l.cable.geometry = new THREE.TubeGeometry(cableCurve(l), LITE ? 40 : 72, 0.0019, 8, false);
      }
    }
  });
  return moving;
}

// ------------------------------------------------------------------ markers (test points, clamp places, jacks)
const ringGeo = new THREE.TorusGeometry(0.0075, 0.0013, 8, 32);
const hitGeo = new THREE.SphereGeometry(0.016, 10, 8);
const hitMat = new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false });
function markerMat(hot) {
  return new THREE.MeshBasicMaterial({ color: hot ? 0x3d8bff : 0x4fd8ff, transparent: true, opacity: 0.95, depthTest: false });
}

function updateMarkers() {
  const want = new Map((state.points || []).map((p) => [p.id, p]));
  for (const [id, m] of markers) if (!want.has(id) || m.key !== JSON.stringify(want.get(id))) { scene.remove(m.g); m.el.remove(); markers.delete(id); }
  for (const [id, p] of want) {
    if (markers.has(id)) continue;
    const pose = id.startsWith('J_') ? jackPose(id.slice(2)) : pointPose(id);
    if (!pose) continue;
    const g = new THREE.Group();
    g.position.copy(pose.p);
    const big = id.startsWith('clamp_');
    const ring = new THREE.Mesh(ringGeo, markerMat(p.hot));
    ring.renderOrder = 10;
    if (big) ring.scale.setScalar(1.5);
    const hit = new THREE.Mesh(hitGeo, hitMat);
    if (big) hit.scale.setScalar(1.6);
    hit.userData.tap = id;
    g.add(ring, hit);
    scene.add(g);
    const el = document.createElement('div');
    el.className = 'lb' + (p.hot ? ' hot' : '');
    el.textContent = p.label || '';
    if (!p.label) el.style.display = 'none';
    labelsBox.appendChild(el);
    markers.set(id, { g, ring, el, key: JSON.stringify(p) });
  }
}

const proj = v3();
function placeLabels(now) {
  const w = window.innerWidth, h = window.innerHeight;
  for (const m of markers.values()) {
    m.ring.quaternion.copy(camera.quaternion);
    const s = 1 + 0.18 * Math.sin(now / 260);
    const d = camera.position.distanceTo(m.g.position);
    const k = Math.max(0.5, Math.min(2.4, d / 0.55));
    m.g.scale.setScalar(k * s);
    proj.copy(m.g.position).project(camera);
    const vis = proj.z < 1 && Math.abs(proj.x) < 1.1 && Math.abs(proj.y) < 1.1;
    m.el.style.visibility = vis ? 'visible' : 'hidden';
    if (vis) { m.el.style.left = ((proj.x + 1) / 2 * w) + 'px'; m.el.style.top = ((1 - proj.y) / 2 * h) + 'px'; }
  }
  if (partLabel && N[highlightKey]) {
    const b = boxOf(N[highlightKey]);
    proj.copy(b.getCenter(v3())).project(camera);
    partLabel.style.left = ((proj.x + 1) / 2 * w) + 'px';
    partLabel.style.top = ((1 - proj.y) / 2 * h - 34) + 'px';
  }
}

// ------------------------------------------------------------------ highlight (parts mode)
function setHighlight(h) {
  const key = h && h.node ? h.node : '';
  if (key === highlightKey && (!h || !partLabel || partLabel.textContent === (h.label || ''))) return;
  highlightKey = key;
  instModel && instModel.traverse((o) => { if (o.isMesh && o.userData.e0) { o.material.emissive.copy(o.userData.e0); o.material.emissiveIntensity = 1; } });
  if (partLabel) { partLabel.remove(); partLabel = null; }
  if (!key || !N[key]) return;
  if (h.label) {
    partLabel = document.createElement('div');
    partLabel.className = 'lb part';
    partLabel.textContent = h.label;
    labelsBox.appendChild(partLabel);
  }
  if (h.focus !== false && !benchKey) {
    const b = boxOf(N[key]);
    const c = b.getCenter(v3());
    const off = camera.position.clone().sub(controls.target);
    const r = Math.max(0.05, b.getSize(v3()).length());
    off.setLength(Math.max(controls.minDistance, Math.min(off.length(), r * 4 + 0.12)));
    moveCamera(c.clone().add(off), c);
  }
  wake(1000);
}

function pulseHighlight(now) {
  if (!highlightKey || !N[highlightKey]) return;
  const k = 0.35 + 0.35 * Math.sin(now / 180);
  N[highlightKey].traverse((o) => { if (o.isMesh && o.material.emissive) { o.material.emissive.setRGB(0.1, 0.3, 0.9); o.material.emissiveIntensity = k * 0.6; } });
}

// ------------------------------------------------------------------ sparks
function spark(at) {
  const pose = pointPose(at) || jackPose(at);
  const p = pose ? pose.p : (instRoot ? instRoot.getWorldPosition(v3()) : v3());
  const light = new THREE.PointLight(0x9fd0ff, 6, 0.8, 2);
  light.position.copy(p);
  const mat = new THREE.SpriteMaterial({ color: 0xcfe6ff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false });
  const sp = new THREE.Sprite(mat);
  sp.position.copy(p);
  sp.scale.setScalar(0.06);
  scene.add(light, sp);
  sparks.push({ light, sp, t: 0 });
  wake(800);
}

function tickSparks(dt) {
  for (let i = sparks.length - 1; i >= 0; i--) {
    const s = sparks[i];
    s.t += dt;
    const k = Math.max(0, 1 - s.t / 0.45);
    s.light.intensity = 8 * k * (0.6 + 0.4 * Math.random());
    s.sp.material.opacity = k;
    s.sp.scale.setScalar(0.04 + 0.12 * (1 - k) * Math.random());
    if (k <= 0) { scene.remove(s.light, s.sp); s.sp.material.dispose(); sparks.splice(i, 1); }
  }
  return sparks.length > 0;
}

// ------------------------------------------------------------------ apply the state
const tmpM = new THREE.Matrix4();
function apply(dt, snap = false) {
  if (!instRoot) return false;
  let moving = false;
  // needle: a damped spring that bounces off its stops
  if (N.needle) {
    const target = typeof state.needle === 'number' ? state.needle : 0;
    const jit = state.jitter ? state.jitter * Math.sin(performance.now() / 23) : 0;
    if (snap) { cur.needle = target; cur.needleV = 0; }
    const K = state.slow ? 18 : 55, D = state.slow ? 7 : 8.5;
    const steps = Math.max(1, Math.ceil(dt / 0.008));
    for (let i = 0; i < steps; i++) {
      const h = dt / steps;
      cur.needleV += (K * (target + jit - cur.needle) - D * cur.needleV) * h;
      cur.needle += cur.needleV * h;
      if (cur.needle > 1.055) { cur.needle = 1.055; cur.needleV = -Math.abs(cur.needleV) * 0.35; }
      if (cur.needle < -0.035) { cur.needle = -0.035; cur.needleV = Math.abs(cur.needleV) * 0.35; }
    }
    N.needle.rotation.z = -(-SWEEP + 2 * SWEEP * cur.needle);
    if (Math.abs(cur.needleV) > 1e-3 || Math.abs(target - cur.needle) > 1e-3 || jit) moving = true;
  }
  if (N.knob) {
    const t = THREE.MathUtils.degToRad(state.knob || 0);
    cur.knob = snap ? t : cur.knob + (t - cur.knob) * Math.min(1, dt * 14);
    N.knob.rotation.z = -cur.knob;
    if (Math.abs(t - cur.knob) > 1e-3) moving = true;
  }
  if (N.ohm_adj) N.ohm_adj.rotation.z = -(state.ohmAdj || 0) * 2.4;
  if (N.zero_screw) N.zero_screw.rotation.z = -(state.zero || 0) * 3;
  if (N.test) {
    if (N.test.userData.z0 === undefined) N.test.userData.z0 = N.test.position.z;
    const t = state.test ? 1 : 0;
    cur.test += (t - cur.test) * Math.min(1, dt * 18);
    N.test.position.z = N.test.userData.z0 - 0.003 * cur.test;
    N.test.rotation.z = -0.5 * cur.test * (state.testLock ? 1 : 0);
  }
  if (N.lamp_live) {
    const m = meshOf(N.lamp_live);
    if (m) { const on = !!state.led && Math.sin(performance.now() / 120) > -0.2; m.material.emissive.setRGB(on ? 1 : 0, 0, 0); m.material.emissiveIntensity = on ? 3 : 0; if (state.led) moving = true; }
  }
  drawLcd(state.lcd);
  // clamp meter: rest pose or round a wire, the jaw opening on the way
  if (jawLocal && restPose) {
    const at = state.clampAt && BN[state.clampAt];
    const tgt = at ? tmpM.copy(BN[state.clampAt].matrixWorld).multiply(new THREE.Matrix4().copy(jawLocal).invert()) : restPose;
    const key = at ? state.clampAt : '';
    if (cur.clampKey !== key) { cur.clampKey = key; cur.clampFrom = { p: instRoot.position.clone(), q: instRoot.quaternion.clone() }; cur.clampT = snap ? 1 : 0; }
    const p = v3(), q = new THREE.Quaternion(), s = v3();
    tgt.decompose(p, q, s);
    if (cur.clampT < 1) {
      cur.clampT = Math.min(1, cur.clampT + dt / 0.9);
      const e = cur.clampT < 0.5 ? 2 * cur.clampT ** 2 : 1 - (-2 * cur.clampT + 2) ** 2 / 2;
      instRoot.position.lerpVectors(cur.clampFrom.p, p, e).add(new THREE.Vector3(0, Math.sin(Math.PI * e) * 0.12, 0));
      instRoot.quaternion.slerpQuaternions(cur.clampFrom.q, q, e);
      moving = true;
    } else { instRoot.position.copy(p); instRoot.quaternion.copy(q); }
    instRoot.updateMatrixWorld(true);
    const open = cur.clampT < 1 ? Math.sin(Math.PI * Math.min(1, cur.clampT * 1.15)) : (state.jaw || 0);
    cur.jaw += (open - cur.jaw) * Math.min(1, dt * 16);
    if (N.jaw) N.jaw.rotation.z = cur.jaw * 0.5;
    if (N.trigger) N.trigger.rotation.z = -cur.jaw * 0.12;
  }
  // the bench: breakers, links, the motor
  if (benchRoot) {
    const sw = state.switches || {};
    for (const [k, on] of Object.entries(sw)) {
      const o = BN[k];
      if (!o) continue;
      const t = k === 'tog_iso' ? (on ? -Math.PI / 2 : 0) : (on ? -0.42 : 0.42);
      const ax = k === 'tog_iso' ? 'z' : 'x';
      const c = snap ? t : o.rotation[ax] + (t - o.rotation[ax]) * Math.min(1, dt * 16);
      o.rotation[ax] = c;
      if (Math.abs(t - c) > 1e-3) moving = true;
    }
    if (BN.links_star) BN.links_star.visible = state.links === 'star';
    if (BN.links_delta) BN.links_delta.visible = state.links === 'delta';
    if (BN.link_X2) BN.link_X2.visible = state.linkX2 !== false;
    if (BN.shaft) {
      const sp = state.run || 0;
      cur.shaft += (sp - cur.shaft) * Math.min(1, dt * (sp > cur.shaft ? 1.2 : 0.6));
      BN.shaft.rotation.x += cur.shaft * dt * 150;
      if (cur.shaft > 0.002) moving = true;
    }
  }
  if (state.spark && state.spark.n !== lastSpark) {
    if (lastSpark !== -1 || !snap) spark(state.spark.at);
    lastSpark = state.spark.n;
  }
  moving = updateLeads(dt, snap) || moving;
  return moving;
}

// ------------------------------------------------------------------ picture in picture: the instrument's face
function layoutPip() {
  const on = !!(benchKey && state.pip !== false && instRoot);
  pipBox.style.display = on ? 'block' : 'none';
  if (!on) return;
  const w = window.innerWidth, h = window.innerHeight;
  const s = Math.round(Math.min(w, h) * (w < h ? 0.42 : 0.36));
  const pw = instKey === 'watt' || instKey === 'megger' ? Math.round(s * 1.25) : s;
  pipBox.style.width = pw + 'px';
  pipBox.style.height = s + 'px';
  pipBox.style.left = '10px';
  pipBox.style.top = '10px';
  pipBox.dataset.w = pw; pipBox.dataset.h = s;
}

function renderPip() {
  if (pipBox.style.display === 'none') return;
  const pw = +pipBox.dataset.w, ph = +pipBox.dataset.h;
  const { p, n, w, h, d } = faceFrame();
  pipCam.aspect = pw / ph;
  const up = new THREE.Vector3(0, 1, 0).applyQuaternion(instRoot.quaternion);
  pipCam.up.copy(up);
  const t = Math.tan(THREE.MathUtils.degToRad(pipCam.fov / 2));
  // the clamp meter shows its display and dial, not the jaws
  const hh = instKey === 'clamp' ? h * 0.62 : h;
  if (instKey === 'clamp') p.addScaledVector(up, -h * 0.17);
  const dist = Math.max(hh / 2 / t, w / 2 / t / pipCam.aspect) * 1.08 + d / 2;
  pipCam.position.copy(p).addScaledVector(n, dist);
  pipCam.lookAt(p);
  pipCam.near = dist / 50; pipCam.far = dist * 20;
  pipCam.updateProjectionMatrix();
  const H = window.innerHeight;
  renderer.setScissorTest(true);
  renderer.setScissor(10, H - 10 - ph, pw, ph);
  renderer.setViewport(10, H - 10 - ph, pw, ph);
  renderer.setClearColor(0x0b1430, 1);
  renderer.clear();
  for (const m of markers.values()) m.g.visible = false;
  renderer.render(scene, pipCam);
  for (const m of markers.values()) m.g.visible = true;
  renderer.setScissorTest(false);
  renderer.setClearColor(0x000000, 0);
  renderer.setViewport(0, 0, window.innerWidth, H);
}

// ------------------------------------------------------------------ taps
const ray = new THREE.Raycaster();
let down = null;
renderer.domElement.addEventListener('pointerdown', (e) => { down = { x: e.clientX, y: e.clientY, t: performance.now() }; });
renderer.domElement.addEventListener('pointerup', (e) => {
  if (!down) return;
  const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y);
  const quick = performance.now() - down.t < 450;
  down = null;
  if (moved > 8 || !quick) return;
  const ndc = new THREE.Vector2(e.clientX / window.innerWidth * 2 - 1, -(e.clientY / window.innerHeight) * 2 + 1);
  ray.setFromCamera(ndc, camera);
  const targets = [];
  for (const m of markers.values()) targets.push(m.g);
  if (instRoot) targets.push(instRoot);
  if (benchRoot) targets.push(benchRoot);
  const hits = ray.intersectObjects(targets, true);
  // markers first: they are small and drawn on top
  const mk = hits.find((h) => h.object.userData.tap);
  if (mk) { bridge('tap', mk.object.userData.tap); wake(); return; }
  for (const h of hits) {
    let o = h.object;
    while (o) {
      if (o.parent === instModel && o.name) { bridge('tap', o.name.replace(/_mesh$/, '')); wake(); return; }
      if (benchRoot && o.parent === benchRoot && /^(tog_|link)/.test(o.name)) { bridge('tap', o.name.replace(/_mesh$/, '')); wake(); return; }
      o = o.parent;
    }
    if (h.object.visible && h.object.material && h.object.material.opacity > 0) break;
  }
});

// ------------------------------------------------------------------ loop
function busy() {
  return dragging || !!camAnim || sparks.length > 0 || markers.size > 0 || !!highlightKey || (state.run || 0) > 0 || !!state.led || !!state.jitter;
}

let last = performance.now(), drawn = 0, slow = 0, frames = 0, wasMoving = true;
function frame(now) {
  requestAnimationFrame(frame);
  if (now > awakeUntil && !busy() && !wasMoving) { last = now; return; }
  if (now - drawn < 1000 / FPS - 2) return;
  const dt = Math.min(0.06, (now - last) / 1000);
  last = now;
  const took = now - drawn;
  drawn = now;
  if (took < 200) slow = took > 2.2 * (1000 / FPS) ? slow + 1 : Math.max(0, slow - 1);
  if (slow > 45) {
    slow = 0;
    if (ratio > 0.75) { ratio = Math.max(0.75, ratio - 0.25); renderer.setPixelRatio(ratio); resize(); }
    else if (renderer.shadowMap.enabled) { renderer.shadowMap.enabled = false; scene.traverse((o) => { if (o.material) o.material.needsUpdate = true; }); }
  }
  if (camAnim) {
    camAnim.t = Math.min(1, camAnim.t + dt / 0.8);
    const e = 1 - Math.pow(1 - camAnim.t, 3);
    camera.position.lerpVectors(camAnim.p0, camAnim.p1, e);
    controls.target.lerpVectors(camAnim.t0, camAnim.t1, e);
    if (camAnim.t >= 1) camAnim = null;
  }
  wasMoving = apply(dt) || tickSparks(dt);
  pulseHighlight(now);
  controls.update();
  placeLabels(now);
  renderer.setViewport(0, 0, window.innerWidth, window.innerHeight);
  renderer.clear();
  renderer.render(scene, camera);
  renderPip();
  frames++;
}
resize();
requestAnimationFrame(frame);

window.inst = {
  load,
  update(s) {
    const pipWas = state.pip;
    state = s || {};
    updateMarkers();
    setHighlight(state.highlight);
    if (pipWas !== state.pip) layoutPip();
    wake(400);
  },
  focus(name) { focus(name); },
  stats() { return { frames, ratio, lite: LITE, leads: leads.size, markers: markers.size }; },
};

let announced = false;
const announce = () => { if (!announced && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) { announced = true; bridge('ready'); } };
window.addEventListener('flutterInAppWebViewPlatformReady', announce);
announce();

// browser preview: instruments.html?i=avo&b=board&m=mount_meter
const qi = params.get('i');
if (qi) load({ instrument: qi, bench: params.get('b') || '', mount: params.get('m') || undefined }).then(() => layoutPip());
