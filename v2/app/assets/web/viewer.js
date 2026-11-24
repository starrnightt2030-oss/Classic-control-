// 3D component viewer: orbit, explode, tap-to-pick parts, bilingual leader labels.
// Talks to Flutter through flutter_inappwebview's JavaScript bridge.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const bridge = (name, ...args) => {
  try {
    const b = window.flutter_inappwebview;
    if (b && b.callHandler) return b.callHandler(name, ...args);
  } catch (e) { /* not inside the app (browser preview) */ }
  return undefined;
};

const msg = document.getElementById('msg');
const labelsEl = document.getElementById('labels');
const linesEl = document.getElementById('lines');
const SVGNS = 'http://www.w3.org/2000/svg';

// ---------- renderer / scene ----------
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.AgXToneMapping;
renderer.toneMappingExposure = 1.15;
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
const keyLight = new THREE.DirectionalLight(0xffffff, 1.4);
keyLight.position.set(2, 3, 4);
scene.add(keyLight);
const fill = new THREE.DirectionalLight(0xbfd8ff, 0.5);
fill.position.set(-3, 1, -2);
scene.add(fill);

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

function easeInOut(t) { return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2; }

function applyExplode() {
  const e = easeInOut(explode);
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

function setNearFar(dist) {
  camera.near = Math.max(dist / 200, 0.0005);
  camera.far = dist * 30;
  camera.updateProjectionMatrix();
}

function refit(snapDir) {
  if (!boxA) return;
  const goal = fitFor(explodeTarget > 0.5 ? boxE : boxA);
  setNearFar(goal.dist);
  if (snapDir) {
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
  root = null;
  parts = [];
  selected = null;
  boxA = boxE = null;
  labelsEl.innerHTML = '';
  linesEl.innerHTML = '';
}

function hasPartAncestor(o) {
  for (let a = o.parent; a; a = a.parent) if (a.userData && a.userData.name_ar) return true;
  return false;
}

function load(url) {
  clearModel();
  explode = explodeTarget = 0;
  msg.style.display = 'flex';
  msg.textContent = 'جاري تحميل المجسم…';
  const token = ++loadToken;
  loader.load(url, (gltf) => {
    if (token !== loadToken) return;
    root = gltf.scene;
    scene.add(root);
    root.updateMatrixWorld(true);

    const partNodes = [];
    root.traverse((o) => { if (o.userData && o.userData.name_ar && !hasPartAncestor(o)) partNodes.push(o); });
    for (const o of partNodes) {
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
        id: o.name, ar: o.userData.name_ar, en: o.userData.name_en || '',
        obj: o, base: o.position.clone(), off: localOff, meshes, localCenter, el: null, line: null, w: 0, h: 0,
      });
    }

    boxA = new THREE.Box3().setFromObject(root);
    if (parts.length) {
      explode = 1; applyExplode(); root.updateMatrixWorld(true);
      boxE = new THREE.Box3().setFromObject(root).union(boxA);
      explode = 0; applyExplode(); root.updateMatrixWorld(true);
    } else {
      boxE = boxA.clone();
    }
    buildLabels();
    refit(true);
    msg.style.display = 'none';
    bridge('loaded', JSON.stringify(parts.map((p) => ({ id: p.id, ar: p.ar, en: p.en }))));
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
        if (on) { mat.emissive.setHex(0xf5a400); mat.emissiveIntensity = 0.32; }
        else { mat.emissive.copy(mat.userData.e0 || new THREE.Color(0)); mat.emissiveIntensity = mat.userData.ei0 ?? 1; }
      }
    }
    if (p.el) p.el.classList.toggle('sel', on);
  }
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
  if (cancelled || !down) { down = null; return; }
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
    el.textContent = p.ar;
    if (p.en) {
      const s = document.createElement('small');
      s.textContent = p.en;
      el.appendChild(s);
    }
    labelsEl.appendChild(el);
    const ln = document.createElementNS(SVGNS, 'line');
    ln.setAttribute('stroke', '#C9D4DB');
    ln.setAttribute('stroke-width', '1.2');
    linesEl.appendChild(ln);
    const dot = document.createElementNS(SVGNS, 'circle');
    dot.setAttribute('r', '3.5');
    dot.setAttribute('fill', '#0B0F12');
    dot.setAttribute('stroke', '#3FD5E8');
    dot.setAttribute('stroke-width', '2');
    linesEl.appendChild(dot);
    p.el = el; p.line = ln; p.dot = dot; p.w = 0;
  }
}

const tmp = new THREE.Vector3();
function updateLabels() {
  const W = window.innerWidth, H = window.innerHeight;
  const compact = W < 560;
  const vis = [];
  for (const p of parts) {
    const show = labelsOn && (!compact || p.id === selected);
    p.el.style.display = show ? 'block' : 'none';
    p.line.style.display = show ? '' : 'none';
    p.dot.style.display = show ? '' : 'none';
    if (!show) continue;
    if (!p.w) { p.w = p.el.offsetWidth; p.h = p.el.offsetHeight; }
    p.obj.localToWorld(tmp.copy(p.localCenter));
    tmp.project(camera);
    if (tmp.z > 1) { p.el.style.display = 'none'; p.line.style.display = 'none'; p.dot.style.display = 'none'; continue; }
    vis.push({ p, x: (tmp.x + 1) / 2 * W, y: (1 - tmp.y) / 2 * H });
  }
  if (!vis.length) return;
  let cx = 0, cy = 0;
  for (const v of vis) { cx += v.x; cy += v.y; }
  cx /= vis.length; cy /= vis.length;
  const off = Math.max(46, Math.min(W, H) * 0.16);
  const left = [], right = [];
  for (const v of vis) {
    let dx = v.x - cx, dy = v.y - cy;
    const len = Math.hypot(dx, dy) || 1;
    dx /= len; dy /= len;
    v.ly = v.y + dy * off * 0.7;
    v.side = (v.x + dx * off) < cx ? -1 : 1;
    v.lx = v.x + dx * off;
    (v.side < 0 ? left : right).push(v);
  }
  for (const group of [left, right]) {
    group.sort((a, b) => a.ly - b.ly);
    let prev = -1e9;
    for (const v of group) {
      const h = v.p.h || 30;
      v.ly = Math.max(v.ly, prev + h + 4);
      prev = v.ly;
    }
    const last = group[group.length - 1];
    if (last && last.ly + (last.p.h || 30) / 2 > H - 6) {
      const shift = last.ly + (last.p.h || 30) / 2 - (H - 6);
      for (const v of group) v.ly -= shift;
    }
  }
  for (const v of vis) {
    const w = v.p.w || 80, h = v.p.h || 30;
    let lx = v.side < 0 ? v.lx - w : v.lx;
    lx = Math.min(Math.max(lx, 4), W - w - 4);
    const ly = Math.min(Math.max(v.ly - h / 2, 4), H - h - 4);
    v.p.el.style.transform = `translate(${lx.toFixed(1)}px, ${ly.toFixed(1)}px)`;
    const ax = v.side < 0 ? lx + w : lx;
    v.p.line.setAttribute('x1', v.x.toFixed(1)); v.p.line.setAttribute('y1', v.y.toFixed(1));
    v.p.line.setAttribute('x2', ax.toFixed(1)); v.p.line.setAttribute('y2', (ly + h / 2).toFixed(1));
    v.p.line.setAttribute('stroke', v.p.id === selected ? '#F5A400' : '#C9D4DB');
    v.p.dot.setAttribute('cx', v.x.toFixed(1)); v.p.dot.setAttribute('cy', v.y.toFixed(1));
    v.p.dot.setAttribute('stroke', v.p.id === selected ? '#F5A400' : '#3FD5E8');
  }
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
window.addEventListener('resize', resize);
resize();

function tick() {
  requestAnimationFrame(tick);
  if (explode !== explodeTarget) {
    const step = 0.045;
    explode = explode < explodeTarget ? Math.min(explodeTarget, explode + step) : Math.max(explodeTarget, explode - step);
    applyExplode();
  }
  if (camGoal) {
    controls.target.lerp(camGoal.target, 0.1);
    const dir = camera.position.clone().sub(controls.target).normalize();
    const cur = camera.position.distanceTo(controls.target);
    const nd = cur + (camGoal.dist - cur) * 0.1;
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
  setLabels(on) { labelsOn = !!on; },
  select(id) { select(id); },
  reset() { refit(true); },
  snapshot() { return renderer.domElement.toDataURL('image/png'); },
};

let announced = false;
const announce = () => { if (!announced && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) { announced = true; bridge('ready'); } };
window.addEventListener('flutterInAppWebViewPlatformReady', announce);
announce();

// browser preview: viewer.html?model=contactor.glb
const q = new URLSearchParams(location.search).get('model');
if (q) load('/assets/models/' + q);
