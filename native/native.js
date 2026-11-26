/* Clean Budget — pont vers l'iPhone (chargé seulement dans l'app App Store).
   Dans le navigateur, ce fichier ne fait rien. */
(function () {
  "use strict";
  var C = window.Capacitor;
  if (!C || !C.isNativePlatform || !C.isNativePlatform()) return;

  var plug = function (n) { try { return C.registerPlugin(n); } catch (e) { return null; } };
  var FS = plug("Filesystem"), SH = plug("Share"), HA = plug("Haptics"),
      BIO = plug("BiometricAuthNative"), SB = plug("StatusBar"), SPL = plug("SplashScreen"),
      APP = plug("App"), ICON = plug("AppIcon"), LN = plug("LocalNotifications"),
      CB = C.isPluginAvailable && C.isPluginAvailable("CBBridge") ? plug("CBBridge") : null;
  window.__cbBridge = !!CB;

  /* ---------- Icône de l'app selon la mascotte ---------- */
  window.__setIcon = async function (pet) {
    if (!ICON) return false;
    try {
      var cur = (await ICON.getName()).value || null, want = pet && pet !== "pig" ? "AppIcon-" + pet : null;
      if (cur === want) return true;
      if (want) await ICON.change({ name: want, suppressNotification: true }); else await ICON.reset({ suppressNotification: true });
      return true;
    } catch (e) { return false; }
  };

  /* ---------- Version de l'app (pied de page des réglages) ---------- */
  if (APP) APP.getInfo().then(function (i) { window.__appVer = i.version + " (" + i.build + ")"; }).catch(function () {});

  /* ---------- Rappel du soir (notifications locales, sans internet) ----------
     On programme les 7 prochains soirs. Si une opération a déjà été notée aujourd'hui,
     le rappel de ce soir est sauté. Reprogrammé à chaque enregistrement. */
  var RIDS = [9101, 9102, 9103, 9104, 9105, 9106, 9107, 9108];
  window.__notif = !!LN;
  window.__notifAsk = async function () {
    if (!LN) return false;
    try {
      var p = await LN.checkPermissions();
      if (p.display !== "granted") p = await LN.requestPermissions();
      return p.display === "granted";
    } catch (e) { return false; }
  };
  window.__notifPlan = async function (on, time, doneToday) {
    if (!LN) return;
    try {
      await LN.cancel({ notifications: RIDS.map(function (id) { return { id: id }; }) }).catch(function () {});
      if (!on) return;
      var p = await LN.checkPermissions(); if (p.display !== "granted") return;
      var hm = String(time || "20:00").split(":"), now = new Date(), list = [];
      for (var d = 0; d < 8; d++) {
        var at = new Date(now.getFullYear(), now.getMonth(), now.getDate() + d, +hm[0] || 20, +hm[1] || 0, 0);
        if (at <= now || (d === 0 && doneToday)) continue;
        list.push({ id: RIDS[d], title: "Clean Budget", body: "As-tu noté tes dépenses aujourd’hui ? 💸", schedule: { at: at, allowWhileIdle: true } });
      }
      if (list.length) await LN.schedule({ notifications: list });
    } catch (e) {}
  };

  document.documentElement.classList.add("native");

  /* ---------- 1. Copie de secours native des données ----------
     L'app garde ses données dans IndexedDB comme avant. En plus, chaque
     enregistrement est copié dans un fichier natif (dossier Library de l'app,
     inclus dans la sauvegarde iCloud de l'iPhone). Si iOS vide un jour le
     stockage web, les données sont reprises depuis ce fichier au démarrage. */
  var FILE = "clean-budget-donnees.json", DIR = "LIBRARY";
  var pending = null, timer = 0;

  function writeNow() {
    clearTimeout(timer); timer = 0;
    if (pending == null || !FS) return;
    var js = pending; pending = null;
    FS.writeFile({ path: FILE, directory: DIR, data: js, encoding: "utf8", recursive: true })
      .catch(function () { pending = pending == null ? js : pending; });
    autoBackup(js);
    syncSoon(2500);
    notifSync();
    widgetSync();
  }
  /* ---------- Widget : résumé du mois envoyé à chaque enregistrement ---------- */
  var wTimer = 0, wKey = "";
  function widgetSync() { clearTimeout(wTimer); wTimer = setTimeout(widgetSyncNow, 700); }
  async function widgetSyncNow() {
    try {
      if (!CB || typeof cbSummary != "function" || (typeof DEMO != "undefined" && DEMO)) return;
      if (document.body && document.body.classList.contains("scr")) { widgetSync(); return; }   // pas pendant que tu fais défiler
      if (typeof petPng == "function" && typeof petWKey == "function") {
        var k = petWKey();
        if (k != wKey) {
          var d = await petPng(false), n = await petPng(true);
          if (d) await CB.setWidgetImage({ name: "pet-day.png", b64: d }).catch(function () {});
          if (n) await CB.setWidgetImage({ name: "pet-night.png", b64: n }).catch(function () {});
          if (d) wKey = k;
        }
      }
      await CB.setWidgetData({ json: JSON.stringify(cbSummary()) }).catch(function () {});
      if (CB.liveSet) CB.liveSet({ on: !!S.o.live }).catch(function () {});
    } catch (e) {}
  }
  /* ---------- Opérations ajoutées par Siri / Raccourcis pendant que l'app était fermée ---------- */
  async function takePending() {
    if (!CB || typeof cbAddOps != "function") return;
    try { var r = await CB.takePending(); if (r && r.ops && r.ops.length) cbAddOps(r.ops); if (r && r.openAdd && typeof cbOpenUrl == "function") cbOpenUrl("cleanbudget://add"); } catch (e) {}
  }
  document.addEventListener("visibilitychange", function () { if (!document.hidden) { setTimeout(takePending, 400); widgetSync(); } });
  try { if (CB && CB.addListener) CB.addListener("pending", function () { takePending(); }); } catch (e) {}
  setTimeout(function () { takePending(); widgetSync(); }, 3200);   // après l’animation de démarrage, pour qu’elle reste fluide
  /* ---------- Liens du widget (cleanbudget://add) ---------- */
  if (APP) {
    try { var lr = APP.addListener("appUrlOpen", function (e) { if (e && e.url && typeof cbOpenUrl == "function") cbOpenUrl(e.url); }); if (lr && lr.catch) lr.catch(function () {}); } catch (e) {}
    APP.getLaunchUrl().then(function (r) { if (r && r.url) setTimeout(function () { if (typeof cbOpenUrl == "function") cbOpenUrl(r.url); }, 1800); }).catch(function () {});
  }
  /* ---------- iCloud Drive ---------- */
  if (CB) CB.icloudStatus().then(function (r) {
    window.__icloud = !!(r && r.available);
    if (window.__icloud) {
      if (CB.syncWatch) CB.syncWatch().catch(function () {});
      setTimeout(function () { syncNow(); }, 2500);
    }
  }).catch(function () { window.__icloud = false; });

  /* ---------- Synchro iPhone ⇄ iPad par iCloud ----------
     Un seul fichier caché (conteneur iCloud › Sync › etat.json) contient l'état complet.
     Chaque appareil garde aussi la « base » : le dernier état sur lequel les deux étaient d'accord.
     Fusion à trois : ce qui a changé d'un seul côté gagne, les ajouts des deux côtés sont gardés,
     une suppression n'est appliquée que si l'autre côté n'a pas modifié l'élément entre-temps.
     On ne lit pas les sauvegardes du jour : elles restent un filet de sécurité à part. */
  var SY = { busy: false, again: false, base: undefined, t: 0 }, BASE = "sync-base.json";
  function syncOn() {
    try { if (localStorage.getItem("cb_isync") === "0") return false; } catch (e) {}
    return !!(CB && CB.syncRead && window.__icloud && typeof S != "undefined" && S && Array.isArray(S.tx) && !(typeof DEMO != "undefined" && DEMO));
  }
  function syncSoon(ms) { clearTimeout(SY.t); SY.t = setTimeout(syncNow, ms || 2500); }
  window.__syncNow = function () { syncSoon(100); };
  async function syncNow() {
    if (!syncOn()) return;
    if (SY.busy) { SY.again = true; return; }
    var sh = document.getElementById("sheet"), fresh = S.tx.length === 0;
    if (sh && sh.classList.contains("on") && !fresh) { syncSoon(4000); return; }   // pas pendant une saisie (sauf appareil neuf)
    SY.busy = true;
    try {
      if (SY.base === undefined) {
        try { SY.base = JSON.parse((await FS.readFile({ path: BASE, directory: DIR, encoding: "utf8" })).data); } catch (e) { SY.base = null; }
      }
      var r = await CB.syncRead();
      if (r && r.pending) return;                     // iCloud le télécharge : « icloudChanged » arrivera
      var R = null;
      if (r && r.data) { try { var o = JSON.parse(r.data); if (o && o.s && Array.isArray(o.s.tx)) R = o.s; } catch (e) {} }
      var jL = JSON.stringify(S), L = JSON.parse(jL), M;
      if (!R) M = L;
      else if (!SY.base && !L.tx.length) M = R;       // appareil neuf : il reprend tout
      else M = cbMerge(L, R, SY.base || {});
      var jM = JSON.stringify(M), jR = R ? JSON.stringify(R) : "";
      if (jM !== jL && typeof cbSyncApply == "function") {
        var sh2 = document.getElementById("sheet");
        if (sh2 && sh2.classList.contains("on")) {
          if (!fresh) { SY.again = true; return; }
          if (typeof closeSh == "function") closeSh();   // appareil neuf : on ferme l'accueil, tout arrive d'iCloud
        }
        cbSyncApply(M);
        M = JSON.parse(JSON.stringify(S)); jM = JSON.stringify(M);
      }
      var base = R;
      if (jM !== jR) {
        try { await CB.syncWrite({ data: JSON.stringify({ v: 1, at: Date.now(), s: M }) }); base = M; } catch (e) {}
      } else base = M;
      if (base) {
        SY.base = base;
        FS.writeFile({ path: BASE, directory: DIR, data: JSON.stringify(base), encoding: "utf8", recursive: true }).catch(function () {});
      }
      window.__syncAt = Date.now();
    } catch (e) {
    } finally {
      SY.busy = false;
      if (SY.again) { SY.again = false; syncSoon(1500); }
    }
  }
  /* Fusion à trois : L = cet appareil, R = iCloud, B = base commune */
  function J(v) { return v === undefined ? "\u0000" : JSON.stringify(v); }
  function isObj(v) { return v && typeof v == "object" && !Array.isArray(v); }
  function idArr(a) { return Array.isArray(a) && a.every(function (x) { return isObj(x) && x.id != null; }); }
  function mergeVal(l, r, b) {
    var jl = J(l), jr = J(r), jb = J(b);
    if (jl === jr) return l;
    if (jl === jb) return r;
    if (jr === jb) return l;
    if (idArr(l) && idArr(r)) return mergeArr(l, r, idArr(b) ? b : []);
    if (isObj(l) && isObj(r)) {
      var out = {}, bb = isObj(b) ? b : {}, k;
      for (k in l) { var v = mergeVal(l[k], r[k], bb[k]); if (v !== undefined) out[k] = v; }
      for (k in r) if (!(k in l)) { var w = mergeVal(undefined, r[k], bb[k]); if (w !== undefined) out[k] = w; }
      return out;
    }
    return l;                                          // modifié des deux côtés : cet appareil gagne
  }
  function mergeArr(l, r, b) {
    var Rm = {}, Bm = {}, Lm = {}, out = [];
    r.forEach(function (x) { Rm[x.id] = x; }); b.forEach(function (x) { Bm[x.id] = x; }); l.forEach(function (x) { Lm[x.id] = x; });
    l.forEach(function (x) {
      if (x.id in Rm) out.push(mergeVal(x, Rm[x.id], Bm[x.id]));
      else if (!(x.id in Bm) || J(x) !== J(Bm[x.id])) out.push(x);     // ajouté ici, ou modifié ici après suppression là-bas
    });
    r.forEach(function (y) {
      if (y.id in Lm) return;
      if (!(y.id in Bm) || J(y) !== J(Bm[y.id])) out.push(y);         // ajouté là-bas
    });
    return out;
  }
  window.cbMergeTest = mergeVal;
  function cbMerge(L, R, B) { return mergeVal(L, R, B); }
  try { if (CB && CB.addListener) CB.addListener("icloudChanged", function () { syncSoon(800); }); } catch (e) {}
  document.addEventListener("visibilitychange", function () { if (!document.hidden) syncSoon(1200); });
  /* Prêts : rappel ponctuel pour penser à demander le remboursement */
  if (LN) window.__remindOne = async function (key, at, body) {
    var ok = window.__notifAsk ? await window.__notifAsk() : false;
    if (!ok) { if (typeof toast == "function") toast("Autorise les notifications pour recevoir le rappel"); return; }
    var h = 0, k = String(key); for (var i = 0; i < k.length; i++) h = (h * 31 + k.charCodeAt(i)) % 600;
    await LN.schedule({ notifications: [{ id: 9300 + h, title: "Clean Budget", body: body, schedule: { at: at, allowWhileIdle: true } }] }).catch(function () {});
  };
  /* Partager un texte (SMS, WhatsApp…) */
  if (SH) window.__shareText = function (text) { SH.share({ text: text }).catch(function () {}); };
  if (HA) window.__hapTick = function () { HA.selectionChanged().catch(function () {}); };
  /* Mascotte : « tu me manques » si l'app n'est pas ouverte pendant 3 jours */
  window.__boredPlan = async function () {
    if (!LN) return;
    try {
      await LN.cancel({ notifications: [{ id: 9201 }] }).catch(function () {});
      if (typeof S == "undefined" || !S || !S.o || S.o.bored === 0 || (typeof DEMO != "undefined" && DEMO)) return;
      var p = await LN.checkPermissions(); if (p.display !== "granted") return;
      var n = new Date(), at = new Date(n.getFullYear(), n.getMonth(), n.getDate() + 3, 18, 30, 0);
      var pe = typeof PE == "function" ? PE() : "🐷";
      await LN.schedule({ notifications: [{ id: 9201, title: "Clean Budget", body: pe + " Ta mascotte s’ennuie… Ça fait 3 jours ! Viens noter tes dépenses.", schedule: { at: at, allowWhileIdle: true } }] });
    } catch (e) {}
  };
  document.addEventListener("visibilitychange", function () { if (!document.hidden) setTimeout(window.__boredPlan, 1500); });
  setTimeout(function () { window.__boredPlan(); }, 4500);
  function notifSync() {
    try {
      if (!window.__notifPlan || typeof S == "undefined" || !S || !S.o || !S.o.rmd) return;
      var t = dayKey(new Date());
      window.__notifPlan(1, S.o.rmdt, (S.tx || []).some(function (x) { return x.d === t; }));
    } catch (e) {}
  }
  setTimeout(notifSync, 4000);   // au démarrage : on prolonge la semaine de rappels

  /* ---------- 1 bis. Sauvegarde automatique visible dans l'app Fichiers ----------
     Fichiers › Sur mon iPhone › Clean Budget › Sauvegardes
     Un fichier par jour (clean-budget-AAAA-MM-JJ.json), mis à jour à chaque modification.
     On garde les 7 derniers jours + 1 par semaine pendant 8 semaines.
     Même format que « Sauvegarder maintenant » : réimportable avec « Importer ». */
  window.__autoBk = true;
  var BK_DIR = "Sauvegardes", BK_RE = /^clean-budget-(\d{4})-(\d{2})-(\d{2})\.json$/, lastPrune = "";
  function dayKey(d) { return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2); }

  async function autoBackup(js) {
    try {
      var o = JSON.parse(js);
      if (!o || !Array.isArray(o.tx) || !o.tx.length) return;   // jamais écraser avec un budget vide
      var body = js;
      try {
        var pw = typeof bkPw == "function" ? bkPw() : "";
        if (pw && typeof bkEnc == "function") body = await bkEnc(js, pw);   // chiffrée si tu as mis un mot de passe
      } catch (e) { return; }                                          // en cas d'échec, ne rien écrire en clair
      var today = dayKey(new Date());
      await FS.writeFile({ path: BK_DIR + "/clean-budget-" + today + ".json", directory: "DOCUMENTS", data: body, encoding: "utf8", recursive: true });
      if (lastPrune !== today) { lastPrune = today; await prune(); }
      if (CB && window.__icloud && !(S && S.o && S.o.icb === 0)) {
        var keep = (await window.__bkList()).map(function (b) { return b.name; });
        CB.icloudSync({ name: "clean-budget-" + today + ".json", data: body, keep: keep }).catch(function () {});
      }
    } catch (e) {}
  }

  /* Liste, lecture, partage et ouverture du dossier — utilisés par Réglages › Sauvegardes */
  window.__bkList = async function () {
    var r = await FS.readdir({ path: BK_DIR, directory: "DOCUMENTS" }).catch(function () { return { files: [] }; });
    return (r.files || []).map(function (f) {
      var n = typeof f == "string" ? f : f.name, m = n.match(BK_RE);
      return m ? { name: n, date: m[1] + "-" + m[2] + "-" + m[3], size: f.size || 0, mtime: +f.mtime || 0 } : null;
    }).filter(Boolean).sort(function (a, b) { return a.name < b.name ? 1 : -1; });
  };
  window.__bkRead = async function (name) {
    if (!BK_RE.test(name)) throw new Error("nom");
    return (await FS.readFile({ path: BK_DIR + "/" + name, directory: "DOCUMENTS", encoding: "utf8" })).data;
  };
  window.__bkShare = async function (name) {
    if (!BK_RE.test(name) || !SH) return;
    var u = await FS.getUri({ path: BK_DIR + "/" + name, directory: "DOCUMENTS" });
    await SH.share({ files: [u.uri] }).catch(function () {});
  };
  window.__bkFolder = async function () {
    try {
      var u = await FS.getUri({ path: BK_DIR, directory: "DOCUMENTS" });
      location.href = String(u.uri).replace(/^file:\/\//, "shareddocuments://");   // ouvre l'app Fichiers sur le dossier
    } catch (e) {}
  };

  async function prune() {
    try {
      var r = await FS.readdir({ path: BK_DIR, directory: "DOCUMENTS" });
      var names = (r.files || []).map(function (f) { return typeof f == "string" ? f : f.name; })
        .filter(function (n) { return BK_RE.test(n); }).sort().reverse();   // du plus récent au plus ancien
      var keep = {}, weeks = {}, now = Date.now();
      names.forEach(function (n, i) {
        var m = n.match(BK_RE), t = new Date(+m[1], +m[2] - 1, +m[3]).getTime(), age = (now - t) / 864e5;
        if (i < 7) { keep[n] = 1; return; }                                    // 7 derniers jours
        var wk = Math.floor(age / 7);
        if (age <= 56 && !weeks[wk]) { weeks[wk] = 1; keep[n] = 1; }           // 1 par semaine, 8 semaines
      });
      for (var i = 0; i < names.length; i++) {
        if (!keep[names[i]]) await FS.deleteFile({ path: BK_DIR + "/" + names[i], directory: "DOCUMENTS" }).catch(function () {});
      }
    } catch (e) {}
  }
  window.__nativeSave = function (js) {
    pending = js;
    if (!timer) timer = setTimeout(writeNow, 600);
  };
  document.addEventListener("visibilitychange", function () { if (document.hidden) writeNow(); });
  window.addEventListener("pagehide", writeNow);

  function idbOpen() {
    return new Promise(function (res, rej) {
      try {
        var r = indexedDB.open("cleanbudget", 1);
        r.onupgradeneeded = function () { r.result.createObjectStore("kv"); };
        r.onsuccess = function () { res(r.result); };
        r.onerror = function () { rej(r.error); };
      } catch (e) { rej(e); }
    });
  }
  function hasTx(v) {
    try { var o = typeof v == "string" ? JSON.parse(v) : v; return !!(o && Array.isArray(o.tx)); } catch (e) { return false; }
  }

  window.__nativeRestore = async function () {
    if (!FS) return;
    var db = null;
    try {
      db = await idbOpen();
      var cur = await new Promise(function (res) {
        var q = db.transaction("kv").objectStore("kv").get("state");
        q.onsuccess = function () { res(q.result); }; q.onerror = function () { res(null); };
      });
      if (hasTx(cur)) return;                          // données web présentes : rien à faire
    } catch (e) { db = null; }
    try { if (hasTx(localStorage.getItem("argent2"))) return; } catch (e) {}

    var file;
    try { file = (await FS.readFile({ path: FILE, directory: DIR, encoding: "utf8" })).data; }
    catch (e) { return; }                               // pas de copie native : première installation
    if (!hasTx(file)) return;

    var done = false;
    if (db) {
      try {
        await new Promise(function (res, rej) {
          var t = db.transaction("kv", "readwrite"); t.objectStore("kv").put(file, "state");
          t.oncomplete = res; t.onerror = t.onabort = function () { rej(t.error); };
        });
        done = true;
      } catch (e) {}
    }
    if (!done) { try { localStorage.setItem("argent2", file); } catch (e) {} }
    window.__nativeRestored = true;
  };

  /* ---------- 2. Remplacements après le chargement de l'app ---------- */
  document.addEventListener("DOMContentLoaded", function () {

    /* Vibrations : vrai retour haptique de l'iPhone */
    if (HA) {
      window.hap = function () {
        try { if (typeof S != "undefined" && S && S.o && !S.o.vib) return; } catch (e) {}
        HA.impact({ style: "MEDIUM" }).catch(function () {});
      };
      // navigator.vibrate n'existe pas sur iPhone : on le remplace par le vrai moteur haptique
      try {
        navigator.vibrate = function (p) {
          if (Array.isArray(p) && p.length > 1) HA.notification({ type: "ERROR" }).catch(function () {});
          else HA.impact({ style: "MEDIUM" }).catch(function () {});
          return true;
        };
      } catch (e) {}
    }

    /* Export / sauvegarde : feuille de partage iOS (Enregistrer dans Fichiers, AirDrop, Mail…) */
    if (FS && SH) window.out = function (blob, name) {
      return new Promise(function (res) {
        var r = new FileReader();
        r.onload = function () { res(String(r.result).split(",")[1] || ""); };
        r.onerror = function () { res(null); };
        r.readAsDataURL(blob);
      }).then(function (b64) {
        if (b64 == null) throw new Error("lecture");
        return FS.writeFile({ path: name, directory: "CACHE", data: b64, recursive: true });
      }).then(function (w) {
        return SH.share({ files: [w.uri], dialogTitle: name });
      }).then(function () { return true; }, function (e) {
        var m = String((e && (e.message || e.code)) || e);
        if (/cancel/i.test(m)) return false;          // l'utilisateur a fermé la feuille
        try { toast("Partage impossible : " + m); } catch (x) {}
        return false;
      });
    };

    /* Face ID natif à la place de WebAuthn (qui ne marche pas dans une app) */
    if (BIO) {
      window.bioAvail = function () {
        return BIO.checkBiometry().then(function (r) { return !!(r && r.isAvailable); }, function () { return false; });
      };
      window.bioCreate = function () {
        return BIO.internalAuthenticate({ reason: "Activer Face ID pour ouvrir Clean Budget", cancelTitle: "Annuler" })
          .then(function () { return "native"; });
      };
      window.bioGet = function () {
        return BIO.internalAuthenticate({ reason: "Déverrouiller Clean Budget", cancelTitle: "Utiliser le code" })
          .then(function () { return true; });
      };
    }

    /* Couleur du texte de la barre d'état (heure, batterie) selon le thème de l'app */
    if (SB) {
      var last = "";
      var lum = function (c) {
        var m = String(c).match(/\d+(\.\d+)?/g); if (!m || m.length < 3) return null;
        if (m.length > 3 && +m[3] === 0) return null;   // transparent
        return (0.299 * m[0] + 0.587 * m[1] + 0.114 * m[2]) / 255;
      };
      var upd = function () {
        var l = lum(getComputedStyle(document.body).backgroundColor);
        if (l == null) l = lum(getComputedStyle(document.documentElement).backgroundColor);
        var st = l == null ? "DEFAULT" : (l < 0.5 ? "DARK" : "LIGHT");
        if (st !== last) { last = st; SB.setStyle({ style: st }).catch(function () {}); }
      };
      var t = 0, soon = function () { clearTimeout(t); t = setTimeout(upd, 60); };
      new MutationObserver(soon).observe(document.documentElement, { attributes: true, attributeFilter: ["class", "style", "data-theme"] });
      new MutationObserver(soon).observe(document.body, { attributes: true, attributeFilter: ["class", "style"] });
      matchMedia("(prefers-color-scheme: dark)").addEventListener("change", soon);
      setTimeout(upd, 300);
    }

    /* Écran de lancement : on le retire dès que l'app est dessinée */
    // Écran natif uni (même couleur que l'app) : on attend que la page soit dessinée,
    // puis on le fond pendant que l'animation de démarrage commence.
    var gone = false, go = function () {
      if (gone) return; gone = true;
      if (SPL) SPL.hide({ fadeOutDuration: 250 }).catch(function () {});
      if (typeof window.__splGo == "function") window.__splGo();
    };
    requestAnimationFrame(function () { requestAnimationFrame(function () { setTimeout(go, 30); }); });
    setTimeout(go, 1500);
  });
})();
