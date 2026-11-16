/* Clean Budget — pont vers l'iPhone (chargé seulement dans l'app App Store).
   Dans le navigateur, ce fichier ne fait rien. */
(function () {
  "use strict";
  var C = window.Capacitor;
  if (!C || !C.isNativePlatform || !C.isNativePlatform()) return;

  var plug = function (n) { try { return C.registerPlugin(n); } catch (e) { return null; } };
  var FS = plug("Filesystem"), SH = plug("Share"), HA = plug("Haptics"),
      BIO = plug("BiometricAuthNative"), SB = plug("StatusBar"), SPL = plug("SplashScreen");

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
  }

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
      if (lastPrune !== today) { lastPrune = today; prune(); }
    } catch (e) {}
  }

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
    if (SPL) setTimeout(function () { SPL.hide({ fadeOutDuration: 200 }).catch(function () {}); }, 150);
  });
})();
