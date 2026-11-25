// The machines of the schematic simulator in 3D (GLB models from v2/models/machines.py).
// Flutter sends the machine's state every few frames: mc.update({...}); this page eases
// every moving part toward it, so the motion stays smooth between updates.
// Blender axes → three.js: x → x, z (up) → y, y → −z.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const bridge = (name, ...args) => {
  try { const b = window.flutter_inappwebview; if (b && b.callHandler) return b.callHandler(name, ...args); } catch (e) { /* preview */ }
  return undefined;
};
const msg = document.getElementById('msg');

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.95;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.02).texture;
scene.environmentIntensity = 0.6;
const sun = new THREE.DirectionalLight(0xfff2e0, 2.2);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.bias = -0.0005;
sun.shadow.normalBias = 0.01;
scene.add(sun, sun.target);
const fillL = new THREE.DirectionalLight(0xc8dcff, 0.5);
scene.add(fillL);
scene.add(new THREE.HemisphereLight(0xdfe8f5, 0x1a2030, 0.35));

const camera = new THREE.PerspectiveCamera(35, 1, 0.01, 200);
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.maxPolarAngle = Math.PI * 0.49;
controls.screenSpacePanning = true;

const loader = new GLTFLoader();
let root = null, kind = '', N = {}, lamps = {}, protos = {}, items = new Map(), ghosts = [], cleats = [];
let state = {};          // last state from Flutter
const cur = {};          // eased values
let token = 0;

const ease = (k, v, rate, dt) => {
  if (cur[k] === undefined) cur[k] = v;
  cur[k] += (v - cur[k]) * Math.min(1, dt * rate);
  return cur[k];
};

function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  renderer.domElement.style.width = w + 'px';
  renderer.domElement.style.height = h + 'px';
  camera.aspect = w / Math.max(1, h);
  camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize);
resize();

// lamp lenses: lit = their own colour glowing, unlit = dark glass
function lampSet(tag, on) {
  const m = lamps[tag];
  if (!m || m.userData.on === on) return;
  m.userData.on = on;
  m.emissive.copy(on ? m.userData.c0 : new THREE.Color(0, 0, 0));
  m.emissiveIntensity = on ? 2.6 : 0;
  m.color.copy(on ? m.userData.c0 : m.userData.c0.clone().multiplyScalar(0.18));
}

function fit() {
  const box = new THREE.Box3();
  root.traverse((o) => { if (o.isMesh && o.visible && !o.userData.proto) box.expandByObject(o); });
  const c = box.getCenter(new THREE.Vector3()), size = box.getSize(new THREE.Vector3());
  const r = size.length() / 2;
  const dist = r / Math.sin(THREE.MathUtils.degToRad(camera.fov / 2)) * (camera.aspect < 1 ? 1.1 / camera.aspect : 0.75);
  const dir = new THREE.Vector3(0.55, kind === 'lift' ? 0.25 : 0.5, 1).normalize();
  controls.target.copy(c);
  camera.position.copy(c).addScaledVector(dir, dist);
  camera.near = dist / 100; camera.far = dist * 20; camera.updateProjectionMatrix();
  controls.minDistance = dist * 0.2; controls.maxDistance = dist * 3;
  sun.position.copy(c).add(new THREE.Vector3(0.6, 1.5, 0.9).multiplyScalar(r * 1.4));
  sun.target.position.copy(c);
  const sc = sun.shadow.camera;
  sc.left = sc.bottom = -r * 1.2; sc.right = sc.top = r * 1.2; sc.near = r * 0.1; sc.far = r * 5;
  sc.updateProjectionMatrix();
  fillL.position.copy(c).add(new THREE.Vector3(-1.2, 0.5, 0.7).multiplyScalar(r));
}

function clear() {
  if (root) scene.remove(root);
  root = null; N = {}; lamps = {}; protos = {}; items = new Map(); ghosts = []; cleats = [];
  for (const k of Object.keys(cur)) delete cur[k];
}

function load(url, k) {
  clear();
  kind = k;
  msg.style.display = 'flex';
  const t = ++token;
  loader.load(url, (gltf) => {
    if (t !== token) return;
    root = gltf.scene;
    root.traverse((o) => {
      if (o.name) N[o.name] = o;
      if (!o.isMesh) return;
      o.castShadow = true; o.receiveShadow = true;
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      for (const m of mats) {
        if (m.name.startsWith('glass')) { m.transparent = true; m.opacity = 0.28; m.depthWrite = false; o.castShadow = false; }
        if (m.name.startsWith('water')) { m.transparent = true; m.opacity = 0.8; }
      }
      if (o.name.startsWith('lamp_')) {
        const m = o.material.clone();
        o.material = m;
        m.userData.c0 = m.color.clone();
        lamps[o.name.slice(5)] = m;
        o.castShadow = false;
      }
    });
    for (const tag of Object.keys(lamps)) lampSet(tag, tag === 'CAR');
    for (const p of ['proto_metal', 'proto_plastic', 'proto_bottle']) {
      if (N[p]) { protos[p] = N[p]; N[p].visible = false; N[p].traverse((o) => { o.userData.proto = true; }); }
    }
    for (const n of ['rope', 'rope_car', 'hook', 'cart', 'car', 'cw', 'rod', 'ram']) if (N[n]) N[n].userData.p0 = N[n].position.clone();
    if (kind === 'sort' || kind === 'fill') makeCleats(kind === 'sort' ? 0.5 : 0.3);
    scene.add(root);
    fit();
    msg.style.display = 'none';
    apply(0.016, true);
    bridge('loaded', kind);
  }, undefined, () => { msg.textContent = 'تعذّر تحميل المجسم'; });
}

// lines across the belt that move with it
function makeCleats(w) {
  const g = new THREE.BoxGeometry(0.018, 0.003, w);
  const m = new THREE.MeshStandardMaterial({ color: 0x3a4256, roughness: 0.8 });
  for (let i = 0; i < 9; i++) {
    const c = new THREE.Mesh(g, m);
    c.position.set(0, 0.8215, 0);
    root.add(c);
    cleats.push(c);
  }
}

const BELT_L = 3.2;
function clone(name) {
  const c = protos[name].clone(true);
  c.visible = true;
  c.traverse((o) => {
    o.userData.proto = false;
    if (o.isMesh && o.name.includes('liquid')) { /* own material so the level is per bottle */ }
  });
  root.add(c);
  return c;
}

function syncItems(list, protoOf, place, dt) {
  const seen = new Set();
  for (const it of list) {
    const id = it[0];
    seen.add(id);
    let o = items.get(id);
    if (!o) { o = clone(protoOf(it)); o.userData.sx = it[1]; items.set(id, o); }
    o.userData.sx += (it[1] - o.userData.sx) * Math.min(1, dt * 12);
    o.userData.last = it;
    place(o, it);
  }
  for (const [id, o] of items) {
    if (seen.has(id)) continue;
    items.delete(id);
    ghosts.push({ o, t: 0, it: o.userData.last });
  }
}

function apply(dt, snap = false) {
  if (!root) return;
  const s = state, r = snap ? 1e6 : 1;
  for (const [tag, on] of Object.entries(s.lamps || {})) lampSet(tag, !!on);
  if (kind === 'cart') {
    const x = ease('x', s.x ?? 0.5, 10 * r, dt);
    N.cart.position.x = 0.8 + x * 2.8;
    for (let i = 1; i <= 4; i++) if (N['wheel' + i]) N['wheel' + i].rotation.z = -(x * 2.8) / 0.09;
    lampSet('RUN', Math.abs(s.run || 0) > 0.05 && (performance.now() / 300 | 0) % 2 === 0);
  } else if (kind === 'hoist') {
    const z = ease('z', s.z ?? 0, 10 * r, dt);
    const y = N.hook.userData.p0.y + z * 0.95;
    N.hook.position.y = y;
    N.rope.scale.y = Math.max(0.02, 2.16 - (y + 0.12));
    N.drum.rotation.x = -y / 0.085;
  } else if (kind === 'lift') {
    const z = ease('z', s.z ?? 0, 10 * r, dt);
    const y = z * 5.2;
    N.car.position.y = y;
    N.cw.position.y = (1 - z) * 5.4 + 0.1;
    N.rope_car.scale.y = Math.max(0.02, 7.86 - (y + 2.6));
    N.sheave.rotation.x = y / 0.26;
    const d = ease('door', s.door ?? 1, 8 * r, dt);
    N.door_l.position.x = -d * 0.38;
    N.door_r.position.x = d * 0.38;
  } else if (kind === 'sort') {
    const e = ease('ext', s.ext ?? 0, 14 * r, dt);
    N.rod.position.z = -e * 0.55;
    belt(s.belt || 0, dt, r);
    syncItems(s.items || [], (it) => (it[2] ? 'proto_metal' : 'proto_plastic'), (o, it) => {
      o.position.set(0.11 + o.userData.sx * (BELT_L - 0.22), 0.82, 0);
    }, dt);
    ghostsTick(dt, (g) => {
      const [, sx, metal] = g.it;
      const atPusher = Math.abs(sx - 0.6) < 0.1 && metal !== undefined && cur.ext > 0.3;
      if (atPusher) {
        const k = Math.min(1, g.t / 0.7);
        g.o.position.set(0.6 * BELT_L, 0.82 - 0.8 * k * k, -0.25 - 0.45 * k);
        g.o.rotation.x = -k * 0.6;
        return k >= 1 ? (g.t > 2.5) : false;
      }
      g.o.position.y += dt * 0.6;
      g.o.traverse((m) => { if (m.isMesh) { m.material = m.material.clone(); m.material.transparent = true; m.material.opacity = Math.max(0, 1 - g.t * 3); } });
      return g.t > 0.35;
    });
  } else if (kind === 'press') {
    const e = ease('ext', s.ext ?? 0, 16 * r, dt);
    N.ram.position.y = -e * (s.part === 1 ? 0.3 : 0.33);
    N.part_raw.visible = s.part === 1;
    N.part_pressed.visible = s.part === 2;
  } else if (kind === 'fill') {
    belt(s.belt || 0, dt, r);
    N.stream.visible = !!s.y1;
    if (s.y1) N.stream.scale.x = N.stream.scale.z = 0.8 + 0.4 * Math.random();
    syncItems(s.items || [], () => 'proto_bottle', (o, it) => {
      o.position.set(o.userData.sx * BELT_L, 0.82, 0);
      const liq = o.getObjectByName('proto_liquid');
      if (liq) { liq.scale.y = Math.max(0.001, it[2]); liq.visible = it[2] > 0.005; }
    }, dt);
    ghostsTick(dt, (g) => {
      const k = Math.min(1, g.t / 0.6);
      g.o.position.set(BELT_L + 0.12 * k, 0.82 - 0.45 * k * k, 0);
      return g.t > 1.5;
    });
  }
}

function belt(travel, dt, r) {
  const t = ease('belt', travel, 20 * r, dt) * BELT_L;
  cleats.forEach((c, i) => {
    let x = (i * 0.4 + t) % (cleats.length * 0.4);
    c.position.x = 0.05 + x;
    c.visible = c.position.x < BELT_L - 0.06;
  });
}

function ghostsTick(dt, step) {
  ghosts = ghosts.filter((g) => {
    g.t += dt;
    const done = step(g);
    if (done) root.remove(g.o);
    return !done;
  });
}

let last = performance.now();
function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  apply(dt);
  controls.update();
  renderer.render(scene, camera);
}
requestAnimationFrame(frame);

window.mc = {
  load,
  update(s) { state = s || {}; },
  reset() { if (root) fit(); },
};

let announced = false;
const announce = () => { if (!announced && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) { announced = true; bridge('ready'); } };
window.addEventListener('flutterInAppWebViewPlatformReady', announce);
announce();

// browser preview: machine.html?m=sort
const q = new URLSearchParams(location.search).get('m');
if (q) load('/assets/models/machine_' + q + '.glb', q);
