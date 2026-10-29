const C="clean-budget-v25";
self.addEventListener("install",e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(["./","index.html","icon.png","manifest.webmanifest"])));self.skipWaiting()});
self.addEventListener("activate",e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x)))).then(()=>clients.claim())));
self.addEventListener("fetch",e=>{const q=e.request;if(q.method!=="GET")return;
 const html=q.mode==="navigate"||q.destination==="document";
 if(html){// réseau d'abord : la dernière version s'affiche dès qu'il y a internet, sinon la copie hors ligne
  e.respondWith(fetch(q,{cache:"no-store"}).then(r=>{if(r&&r.ok){const k=r.clone();caches.open(C).then(c=>c.put("index.html",k))}return r}).catch(()=>caches.match("index.html").then(m=>m||caches.match("./"))));return}
 e.respondWith(caches.match(q,{ignoreSearch:true}).then(m=>{const n=fetch(q).then(r=>{if(r&&r.ok){const k=r.clone();caches.open(C).then(c=>c.put(q,k))}return r}).catch(()=>m);return m||n}))});
