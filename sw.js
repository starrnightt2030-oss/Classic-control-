/* Classic Control Simulation Lab — service worker (offline cache) — Mohamed _ Eldawly */
const CACHE="ccl-v1.3.0";
const CORE=["./","./index.html","./manifest.webmanifest","./icon-192.png","./icon-512.png","./icon-180.png"];
self.addEventListener("install",e=>{ e.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).catch(()=>{})); });
self.addEventListener("activate",e=>{ e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==CACHE).map(x=>caches.delete(x)))).then(()=>self.clients.claim())); });
self.addEventListener("message",e=>{ if(e.data==="skip") self.skipWaiting(); });
self.addEventListener("fetch",e=>{ const r=e.request; if(r.method!=="GET") return; const u=new URL(r.url);
  if(u.pathname.endsWith("config.json")){ e.respondWith(fetch(r).catch(()=>caches.match(r))); return; }
  if(r.mode==="navigate"||u.pathname.endsWith("/")||u.pathname.endsWith("index.html")){ e.respondWith(fetch(r).then(res=>{ const cp=res.clone(); caches.open(CACHE).then(c=>c.put(r,cp)); return res; }).catch(()=>caches.match(r).then(m=>m||caches.match("./index.html")))); return; }
  e.respondWith(caches.match(r).then(m=>m||fetch(r).then(res=>{ if(res.ok||res.type==="opaque"){ const cp=res.clone(); caches.open(CACHE).then(c=>c.put(r,cp)); } return res; }))); });
