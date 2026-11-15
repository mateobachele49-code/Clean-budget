# Clean Budget sur l'App Store — guide pas à pas

Tu continues à modifier **`index.html` comme avant**. Le reste du dossier sert à en faire une vraie app iPhone, compilée par Codemagic (pas besoin de Mac).

## Ce qui a été ajouté

| Fichier | À quoi il sert |
|---|---|
| `ios/` | Le projet Xcode de l'app (généré par Capacitor) |
| `native/native.js` | Le pont vers l'iPhone : Face ID natif, vibrations, partage, copie de secours des données |
| `scripts/prepare-www.mjs` | Copie `index.html` dans l'app en l'adaptant (tu n'as rien à faire) |
| `capacitor.config.json` | Nom de l'app, identifiant `com.mateobachele.cleanbudget` |
| `codemagic.yaml` | La recette de compilation pour Codemagic |
| `confidentialite.html` | La politique de confidentialité exigée par Apple |

**Ce qui change dans l'app iPhone par rapport au site :**
- Face ID passe par le vrai Face ID de l'iPhone (l'ancien système ne marche pas dans une app).
- Les exports (sauvegarde JSON, Excel) ouvrent la feuille de partage iOS : « Enregistrer dans Fichiers », AirDrop, Mail…
- Chaque enregistrement est aussi copié dans un fichier de l'app, inclus dans la sauvegarde iCloud de l'iPhone. Si iOS vidait le stockage, les données reviennent toutes seules au démarrage.
- Plus de bandeau « Nouvelle version » : les mises à jour passent par l'App Store.

⚠️ **Tes données du site ne passent pas toutes seules dans l'app.** Fais une sauvegarde JSON depuis la version web, puis importe-la dans l'app.

---

## 1. Compte Apple Developer
1. Va sur **developer.apple.com/programs** → S'inscrire, en tant que **personne physique**, avec ton vrai nom.
2. Paie l'abonnement (99 USD/an, prix en euros affiché au paiement).
3. Attends l'e-mail de validation (souvent 24 à 48 h).

## 2. Réserver l'identifiant de l'app
1. **developer.apple.com/account** → Certificates, Identifiers & Profiles → **Identifiers** → **+**.
2. Choisis **App IDs** → **App**.
3. Description : `Clean Budget` · Bundle ID : **Explicit** → `com.mateobachele.cleanbudget`.
4. Ne coche aucune option → Continue → Register.

## 3. Créer la fiche dans App Store Connect
1. **appstoreconnect.apple.com** → Apps → **+** → Nouvelle app.
2. Plateforme **iOS**, nom **Clean Budget** (s'il est déjà pris : `Clean Budget – Mon budget`), langue **Français**, bundle ID `com.mateobachele.cleanbudget`, SKU `cleanbudget`.

## 4. Clé API pour Codemagic
1. App Store Connect → **Utilisateurs et accès** → **Intégrations** → **API App Store Connect** → Générer une clé.
2. Nom : `Codemagic` · Accès : **Gestionnaire d'app**.
3. **Télécharge le fichier `.p8`** (une seule fois possible !) et note l'**Issuer ID** et le **Key ID**.

## 5. Codemagic
1. **codemagic.io** → crée un compte avec **GitHub** → ajoute l'app **Clean-budget**.
2. **Team settings → Integrations → Developer Portal** → Connect :
   - Nom de la clé : **`Clean budget`** (exactement, c'est le nom utilisé dans `codemagic.yaml`)
   - Issuer ID, Key ID, et le fichier `.p8`.
3. **Team settings → codemagic.yaml settings → Code signing identities** :
   - Onglet **iOS certificates** → **Generate certificate** → choisis la clé `Clean Budget` → type **Apple Distribution**.
   - Va sur developer.apple.com → **Profiles** → **+** → **App Store Connect** → App ID `com.mateobachele.cleanbudget` → coche le certificat créé par Codemagic → nom `Clean Budget App Store` → Generate.
   - Retour dans Codemagic → onglet **iOS provisioning profiles** → **Fetch profiles** → sélectionne `Clean Budget App Store`.

## 6. Premier build
1. Codemagic → ton app → **Start new build** → branche **`app-ios`** → workflow **Clean Budget → TestFlight**.
2. Compte 10 à 20 minutes. Si ça échoue, envoie le message d'erreur à Claude.
3. Sur ton iPhone : installe l'app **TestFlight**.
4. App Store Connect → ton app → **TestFlight** → Testeurs internes → ajoute-toi. L'app apparaît dans TestFlight.

## 7. Mise en vente à 0,99 €
1. App Store Connect → **Accords, taxes et services bancaires** → signe l'accord **Apps payantes**, ajoute ton IBAN et remplis les infos fiscales.
2. Fais la demande pour l'**App Store Small Business Program** (commission 15 % au lieu de 30 %).
3. Dans la fiche de l'app :
   - **Tarifs et disponibilité** → 0,99 €.
   - **Confidentialité de l'app** → « Aucune donnée collectée ».
   - **URL de la politique de confidentialité** : `https://mateobachele49-code.github.io/Clean-budget/confidentialite.html` (la page existe une fois la branche `app-ios` fusionnée dans `main`, si GitHub Pages est activé sur le dépôt ; vérifie qu'elle s'ouvre avant de soumettre)
   - **Catégorie** : Finance.
   - **Statut de commerçant (DSA, UE)** : à déclarer, tes coordonnées seront visibles sur la fiche.
   - **Captures d'écran** iPhone 6,9" (1320 × 2868) : 3 minimum. Tu peux les faire depuis l'app installée par TestFlight sur un grand iPhone.
   - Description, mots-clés, URL d'assistance (la page GitHub du projet suffit).
4. Choisis le build envoyé par Codemagic → **Soumettre pour vérification**.

## Mettre à jour l'app plus tard
1. Modifie `index.html` comme d'habitude.
2. Dans `ios/App/App.xcodeproj/project.pbxproj`, change `MARKETING_VERSION = 1.0;` en `1.1` (2 endroits).
3. Lance un nouveau build dans Codemagic, puis soumets la nouvelle version dans App Store Connect.

Si Codemagic affiche « Repère introuvable » à l'étape *Préparer l'app*, c'est qu'un bout de `index.html` a trop changé pour l'adaptation automatique : envoie le message à Claude.
