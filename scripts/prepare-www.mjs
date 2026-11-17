// Prépare le dossier www/ utilisé par l'app iPhone à partir de index.html.
// Tu continues à modifier index.html comme avant : ce script fait le reste.
//   node scripts/prepare-www.mjs
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const www = join(root, "www");

rmSync(www, { recursive: true, force: true });
mkdirSync(www, { recursive: true });

for (const f of ["icon.png", "manifest.webmanifest", "ocr", "pdf"]) {
  const src = join(root, f);
  if (existsSync(src)) cpSync(src, join(www, f), { recursive: true });
}
cpSync(join(root, "native", "native.js"), join(www, "native.js"));
// Le pont natif a besoin de Capacitor (registerPlugin), absent du bridge iOS seul
cpSync(join(root, "node_modules", "@capacitor", "core", "dist", "capacitor.js"), join(www, "capacitor.js"));

let html = readFileSync(join(root, "index.html"), "utf8");

// Chaque modification doit trouver son repère exactement une fois.
// Si index.html change trop, le script s'arrête au lieu de produire une app cassée.
function patch(label, find, replace) {
  const n = html.split(find).length - 1;
  if (n !== 1) {
    console.error(`\n✗ Repère introuvable ou en double (${n}×) : ${label}\n  Cherché : ${find}\n`);
    process.exit(1);
  }
  html = html.replace(find, replace);
}

// 1. Charger le pont natif avant le script principal
patch(
  "début du script principal",
  '<script>\nconst $=s=>document.querySelector(s)',
  '<script src="capacitor.js"></script>\n<script src="native.js"></script>\n<script>\nconst $=s=>document.querySelector(s)'
);

// 2. Copie native à chaque enregistrement (pas en mode démo : la fonction sort avant)
patch(
  "enregistrement",
  "const js=JSON.stringify(S);let ok=false;",
  "const js=JSON.stringify(S);let ok=false;window.__nativeSave&&window.__nativeSave(js);"
);

// 3. Reprise depuis la copie native si le stockage web est vide
patch(
  "chargement",
  "async function load(){let s=null;",
  "async function load(){let s=null;if(window.__nativeRestore){try{await window.__nativeRestore()}catch(e){}}"
);

// 4. Pas de service worker dans l'app : c'est l'App Store qui fait les mises à jour
patch(
  "service worker",
  'if("serviceWorker"in navigator){',
  'if("serviceWorker"in navigator&&!window.Capacitor){'
);

// 5. Ressenti d'app native : pas de loupe ni de sélection de texte sur les boutons
patch(
  "fin des styles",
  "</style></head>",
  "html.native{-webkit-touch-callout:none;-webkit-user-select:none;user-select:none}" +
    "html.native input,html.native textarea,html.native [contenteditable]{-webkit-user-select:text;user-select:text}" +
    "</style></head>"
);

// 6. Pas d'ouverture « en cercle » de la fiche d'ajout : WebKit l'affiche mal
//    (coin haut gauche qui clignote). La fiche glisse depuis le bas, comme les autres.
patch(
  "animation en cercle",
  'mo=MORPH&&S.o.anim&&!matchMedia("(prefers-reduced-motion:reduce)").matches',
  'mo=MORPH&&S.o.anim&&!window.Capacitor&&!matchMedia("(prefers-reduced-motion:reduce)").matches'
);

// 7. Sauvegarde automatique dans Fichiers : plus besoin du rappel « Sauvegarde de la semaine »
patch(
  "rappel de sauvegarde",
  "function weeklyBk(){if(DEMO||",
  "function weeklyBk(){if(window.__autoBk||DEMO||"
);

// 8. Comme une vraie app : pas de zoom par pincement ou double appui, ni au toucher d'un champ
patch(
  "pas de zoom",
  '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">',
  '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">'
);
patch(
  "toucher réactif",
  "</style></head>",
  "html.native,html.native body{touch-action:manipulation;-webkit-tap-highlight-color:transparent;-webkit-text-size-adjust:100%}</style></head>"
);

writeFileSync(join(www, "index.html"), html);
console.log("✓ www/ prêt pour l'iPhone");
