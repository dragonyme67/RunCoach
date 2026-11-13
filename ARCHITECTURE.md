# RunCoach — ARCHITECTURE

Référence unique du projet. Rédigée le 2026-11-12 (phase architecture, étapes 0 et 1).
L'implémentation à partir de l'étape 2 est faite par un autre modèle : tout ce qui est nécessaire pour coder est ici.

Conventions de lecture :
- **[À VÉRIFIER étape N]** = fait non confirmé par une source primaire ou par un test réel. À confirmer au début de l'étape N, avant d'écrire le code qui en dépend.
- « l'utilisateur » = le propriétaire de l'iPhone. Chaque personne (lui, son ami) installe sa propre copie avec ses propres comptes.

---

## 0. Contexte et décisions clés

### 0.1 Produit
App iPhone personnelle de suivi et de planification de course à pied, pilotée par un coach IA.
- Import automatique des séances Garmin (Forerunner 745 via Garmin Connect).
- Coach IA : génère et adapte le plan, explique chaque séance, propose du renforcement, discute en langage naturel.
- Envoi automatique des séances planifiées sur la montre (workouts structurés).
- Replay de chaque sortie sur carte satellite à plat qui tourne avec le coureur, à une vitesse proportionnelle à l'allure réelle.
- Calendrier, progression vers l'objectif.

Utilisateur de référence (sert aux données factices et aux exemples) : 21 ans, court depuis 3 semaines, 5 km à 6:30/km, objectif semi-marathon le dimanche 16 mai 2027 en moins de 2 h (5:41/km). Au 12 novembre 2026 il reste 26 semaines. **Rien de tout cela n'est codé en dur** : tout vient de l'écran Profil rempli au premier lancement.

### 0.2 Contraintes imposées par l'utilisateur
| Contrainte | Conséquence |
|---|---|
| Pas de Mac | Compilation uniquement sur GitHub Actions. Pas de simulateur local, pas de débogueur, pas d'aperçus SwiftUI. |
| Pas de compte Apple Developer payant | Installation par sideloading avec un identifiant Apple gratuit : l'app expire tous les 7 jours et doit être re-signée. Pas de TestFlight, pas de notifications push distantes. |
| Tout gratuit | Pas de backend hébergé. IA via une offre gratuite, avec la clé personnelle de l'utilisateur. |
| Envoi automatique sur la montre, impératif | Seule voie sans structure juridique : l'API non officielle de Garmin Connect (voir §1). |
| Connexion Garmin dans l'app | Écran de connexion Garmin intégré (WKWebView). |
| Usage : l'utilisateur et un ami, chacun sa copie | Mono-utilisateur. Aucune notion de compte ni de serveur partagé. |
| iPhone 16 Plus, dernier iOS | Cible de déploiement iOS 18.0. Mise en page pensée pour 6,7". |
| Machine de développement : Windows 11 | `git` est installé. `gh` (GitHub CLI) est à installer pour lire les résultats de CI. |

### 0.3 Décisions structurantes
| # | Décision | Raison |
|---|---|---|
| D1 | App native SwiftUI, **sans backend** | Le backend servait à protéger une clé IA partagée et à parler à Garmin. Ici la clé est celle de l'utilisateur (Keychain) et Garmin se joint mieux depuis le téléphone (vrai navigateur, IP résidentielle). Zéro coût, zéro donnée de santé sur un serveur. |
| D2 | Garmin : API non officielle, appelée depuis l'iPhone | Seule voie qui permet l'envoi automatique de séances. Voir §1. |
| D3 | IA : client unique compatible « OpenAI chat completions », fournisseur au choix dans Réglages | Les offres gratuites (Gemini, Groq, Mistral) exposent toutes ce format. Un seul client, changement de fournisseur sans code. |
| D4 | Le code calcule, l'IA rédige | Les modèles gratuits sont moins fiables. La périodisation, les allures cibles et les garde-fous sont déterministes et testés ; l'IA remplit le détail des séances et les explications dans des bornes fixées par le code. |
| D5 | Logique dans un package Swift pur (`RunCoachCore`), UI dans la cible app | Le package se compile et se teste sur un runner Linux (rapide, peu coûteux) et peut se compiler sous Windows. Seule l'UI exige un runner macOS. C'est la parade principale à l'absence de Mac. |
| D6 | Xcode project généré par XcodeGen (`project.yml`) | Un `.xcodeproj` ne s'écrit pas à la main et ne peut pas être créé sans Xcode. |
| D7 | Mode de langage Swift 5 (compilateur Swift 6) | Les erreurs de concurrence stricte de Swift 6 coûtent un aller-retour CI chacune. `shortcut` : à repasser en Swift 6 si un Mac devient disponible. |
| D8 | Aucune dépendance tierce | Tout est couvert par SwiftUI, SwiftData, Swift Charts, MapKit, WebKit, BackgroundTasks, Security. |
| D9 | Interface en français, identifiants de code en anglais, unités métriques | — |

---

## 1. Décision Garmin

### 1.1 Options étudiées
| Option | Import | Envoi sur la montre | Statut |
|---|---|---|---|
| Garmin Connect Developer Program, palier **Personal** (ouvert en octobre 2026) | Oui, lecture seule de son propre compte (activités JSON + FIT, santé) | **Non** | Écarté comme voie principale : ne couvre pas l'envoi, et demande de coller une clé au lieu de se connecter. Reste le **plan B d'import**. |
| Developer Program, palier **Starter** (Training API) | Oui | Oui, officiel | Écarté : candidature au nom d'une organisation. L'utilisateur n'a pas de structure. |
| **API non officielle de Garmin Connect** (celle qu'utilise l'app mobile Garmin, documentée par `python-garminconnect`) | Oui, complet (y compris VO2max, statut d'entraînement, sommeil, HRV) | **Oui** : création du workout puis planification à une date ; la montre le reçoit à sa prochaine synchro | **Retenue.** |
| Strava | — | Non | Écarté : la politique d'API Strava interdit d'envoyer les données à une IA, prompts compris. |
| Apple Santé (HealthKit) | Partiel : Garmin n'y écrit pas le tracé GPS | Non | Écarté. |
| Fichier FIT copié par USB dans `GARMIN/Workouts` | — | Manuel | Écarté : l'utilisateur exige l'automatique. |

### 1.2 Option retenue
L'app se connecte au compte Garmin de l'utilisateur comme le fait l'app Garmin Connect iOS :
1. Page de connexion Garmin officielle affichée dans un `WKWebView` (le mot de passe est saisi dans la page de Garmin, l'app ne le voit jamais).
2. Récupération du ticket de service, échangé contre des jetons « DI OAuth2 ».
3. Appels JSON à `https://connectapi.garmin.com` avec `URLSession`, depuis le téléphone.

Détails techniques complets en §5.1.

### 1.3 Limites et risques (à ne jamais masquer dans l'UI ni dans les réponses à l'utilisateur)
- **Non officiel.** Cet usage est très probablement contraire aux conditions d'utilisation de Garmin (les CGU n'ont pas été lues en détail). Garmin peut restreindre le compte. C'est un choix explicite de l'utilisateur, fait après exposé du risque.
- **Peut casser sans préavis.** Garmin a cassé toutes les librairies non officielles en mars 2026 (protection Cloudflare, changement du SSO) ; elles sont restées en panne partielle jusqu'à octobre 2026.
- **Blocages 427/429.** Des tentatives de connexion répétées font bloquer l'IP ou le client pendant 48 h et plus. Règle absolue : jamais de boucle de reconnexion (voir §5.1.6).
- **Jeton de rafraîchissement d'environ 30 jours.** Si l'app n'est pas ouverte pendant un mois, il faut se reconnecter.
- **Connexion WKWebView non prouvée.** Aucune source ne documente cette capture de ticket dans un WKWebView tiers. C'est une inférence solide (l'User-Agent utilisé par la librairie pour imiter l'app iOS est celui d'un WKWebView), à valider sur l'iPhone avec le premier IPA de l'étape 2.
- **Validation 2.0 réussie le 2026-11-13** (script Python sur le PC, `python-garminconnect` 0.3.20, méthode de connexion « mobile iOS » seule) : connexion, lecture des activités, détails, sommeil, statut d'entraînement, puis création, planification et suppression d'un workout au format §5.3.3 ; **la séance est arrivée sur la Forerunner 745** avec ses étapes. Jeton accepté : `GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2`. Le script et les réponses brutes sont hors du dépôt (`Documents\RunCoach-garmin\`).
- **La montre reçoit la séance à sa prochaine synchro** avec Garmin Connect Mobile, pas instantanément.

### 1.4 Plans B
| Panne | Plan B |
|---|---|
| La capture du ticket dans le WKWebView échoue | Connexion native : formulaire dans l'app + séquence HTTP de la « stratégie mobile » (§5.1.2 bis). |
| L'API non officielle est bloquée en lecture | Import par la Personal API officielle (clé créée sur Garmin Connect Web, collée dans Réglages). Non implémenté tant que ce n'est pas nécessaire ; `GarminAPI` est le seul point à remplacer. |
| L'envoi de workouts est bloqué | Aucune voie automatique de remplacement. L'écran Détail affiche les étapes de la séance pour une saisie manuelle dans Garmin Connect, et l'état « non envoyée » reste visible. |
| Le sideloading gratuit est bloqué par Apple | Compte Apple Developer (99 $/an) + TestFlight depuis la CI, ou accès à un Mac. |

---

## 2. Architecture globale

### 2.1 Composants
```
┌────────────────────────────── iPhone ──────────────────────────────┐
│                                                                    │
│  App RunCoach (SwiftUI)                                            │
│  ┌──────────────┐  ┌───────────────────────────────────────────┐   │
│  │ Features/    │  │ RunCoachCore (package Swift pur)          │   │
│  │ écrans +     │─▶│  Garmin/   auth, API, mapping workout     │   │
│  │ ViewModels   │  │  Coach/    snapshot, prompts, LLMClient   │   │
│  └──────┬───────┘  │  Training/ macro-plan, allures, garde-fous│   │
│         │          │  Replay/   interpolation, caméra          │   │
│  ┌──────▼───────┐  └───────────────┬───────────────────────────┘   │
│  │ Data/        │                  │ URLSession (HTTPS)            │
│  │ SwiftData    │                  │                               │
│  └──────────────┘                  │                               │
│  Keychain : jetons Garmin, clé IA  │                               │
│  WKWebView : connexion Garmin      │                               │
│  MapKit : carte satellite 3D       │                               │
│  BackgroundTasks : synchro         │                               │
└────────────────────────────────────┼───────────────────────────────┘
                                     │
        ┌────────────────────────────┼─────────────────────────────┐
        ▼                            ▼                             ▼
 sso.garmin.com              connectapi.garmin.com        Fournisseur IA (au choix)
 diauth.garmin.com           activités, santé,            POST {baseURL}/chat/completions
 (connexion, jetons)         workouts, calendrier         Gemini / Groq / Mistral / autre
                                     │
                                     ▼
                         Garmin Connect ──synchro──▶ Forerunner 745
```
Il n'y a pas de backend. Si un jour il en faut un (clé partagée, cron serveur), il s'insère derrière `GarminAPI` et `LLMClient` sans toucher aux écrans.

### 2.2 Flux de données

**F1 — Synchro Garmin (import).** Déclencheurs : ouverture de l'app (si la dernière synchro date de plus de 15 min), tirer-pour-rafraîchir, tâche d'arrière-plan `BGAppRefreshTask`.
1. `SyncEngine.sync(background:)` vérifie `SyncState.nextAllowedGarminCallAt` (backoff) et le budget de requêtes (`SyncPolicy`).
2. `GarminAuth.validToken()` rafraîchit le jeton si besoin.
3. Liste des activités (pages de 100), de la plus récente vers la plus ancienne : jusqu'au bout de l'historique tant que le premier import n'est pas fini, ensuite jusqu'à la première page qui contient un `garminActivityId` déjà en base. Chaque activité, de tout type, devient un `Run` : la liste contient déjà les stats, les zones FC (`hrTimeInZone_1…5`), la charge et le Training Effect.
4. Pour chaque activité avec tracé (`hasPolyline`) : une requête de détails → `Track`, puis kilomètres (`Track.kmSplits()`). Les tours Garmin (`/splits`) ne servent pas : ils suivent les étapes d'une séance, pas les kilomètres.
5. Métriques quotidiennes : statut d'entraînement et VO2max (une requête), sommeil et FC de repos des jours absents sur 28 jours, plus aujourd'hui et hier.
6. (Étape 4) `WorkoutMatcher` rattache chaque nouveau `Run` au `PlannedWorkout` du même jour.
7. (Étape 4) Si une séance planifiée a été réalisée ou manquée, `CoachEngine.onNewData()` décide s'il faut adapter le plan (F2).

**F2 — Génération et adaptation du plan.** Déclencheurs : fin de l'onboarding, dimanche soir (semaine suivante), séance manquée, fatigue ou douleur déclarée, demande dans le chat.
1. `MacroPlanner` (code) calcule ou met à jour le squelette : phase, volume cible, sortie longue, nombre de séances par semaine jusqu'à la course.
2. `SnapshotBuilder` (code) produit le résumé compact de l'athlète (`AthleteSnapshot`) et le cahier des charges de la semaine (`WeekBrief`).
3. `LLMClient` demande à l'IA le détail des séances en JSON (`WeekPlanResponse`).
4. `Guardrails.validate()` (code) vérifie chaque règle. En cas de violation : un seul appel de réparation avec la liste des violations ; si c'est encore invalide, `FallbackPlanner` (code) produit une semaine gabarit.
5. Enregistrement des `PlannedWorkout`, puis F3.

**F3 — Envoi sur la montre.** Déclencheurs : fin de F2, fin de F1, modification manuelle d'une séance.
1. `WatchSyncEngine` prend les `PlannedWorkout` des 7 prochains jours dont `garminSyncState` vaut `notSent` ou `needsUpdate`.
2. `needsUpdate` : suppression de la planification et du workout existants côté Garmin.
3. `GarminWorkoutMapper` convertit `WorkoutSpec` en JSON Garmin ; création du workout, puis planification à la date.
4. Stockage de `garminWorkoutId` et `garminScheduleId`, état `sent`.
5. La montre reçoit la séance à sa prochaine synchro avec Garmin Connect Mobile.

**F4 — Chat.** L'utilisateur écrit ; l'IA répond par un JSON `{reply, actions}`. Les `actions` (ajout, remplacement, déplacement, suppression de séance) passent par `Guardrails`, puis sont proposées dans une carte de confirmation. Après accord : application en base, puis F3.

**F5 — Replay.** 100 % local : lecture du `Track` stocké, horloge de lecture, interpolation, caméra MapKit, courbe synchronisée. Seules les tuiles de carte viennent du réseau (Apple).

### 2.3 Confidentialité
- Données de santé stockées uniquement sur l'iPhone (SwiftData).
- Vers Garmin : rien d'autre que les workouts créés.
- Vers le fournisseur IA : uniquement `AthleteSnapshot` (agrégats : volumes, allures, FC moyennes, âge, objectif, notes de blessure saisies). **Jamais** de coordonnées GPS, de nom de lieu, de nom de famille, d'e-mail, d'identifiant Garmin.
- Secrets (jetons Garmin, clé IA) dans le Keychain, `kSecAttrAccessibleAfterFirstUnlock` (nécessaire pour la synchro en arrière-plan).
- Aucun secret, aucune donnée personnelle, aucun tracé réel dans le dépôt Git (§9.4).

---

## 3. Structure du projet

### 3.1 Arborescence
```
RunCoach/
├─ ARCHITECTURE.md                 ← ce document
├─ CLAUDE.md                       ← conventions et plan, version courte
├─ project.yml                     ← définition XcodeGen
├─ .gitignore
├─ .github/workflows/
│  ├─ core.yml                     ← runner Linux : build + tests de RunCoachCore (chaque push)
│  └─ ios.yml                      ← runner macOS : build app, captures d'écran, IPA non signée
├─ Packages/RunCoachCore/
│  ├─ Package.swift
│  ├─ Sources/RunCoachCore/
│  │  ├─ Models/        WorkoutSpec.swift, Track.swift, AthleteSnapshot.swift, WeekBrief.swift,
│  │  │                 MacroWeek.swift, Enums.swift (WorkoutKind, StepIntent, …)
│  │  ├─ Garmin/        GarminAuth.swift, GarminAPI.swift, GarminEndpoints.swift, GarminDTO.swift,
│  │  │                 GarminWorkoutMapper.swift, GarminIdentity.swift, GarminError.swift
│  │  ├─ Coach/         LLMClient.swift, LLMProvider.swift, Prompts.swift, CoachSchemas.swift,
│  │  │                 SnapshotBuilder.swift, CoachEngine.swift
│  │  ├─ Training/      MacroPlanner.swift, PaceModel.swift, Guardrails.swift, FallbackPlanner.swift,
│  │  │                 LoadModel.swift, WorkoutMatcher.swift
│  │  ├─ Replay/        ReplayClock.swift, TrackInterpolator.swift, CameraPath.swift
│  │  └─ Support/       TokenStore.swift (protocole), HTTPClient.swift (protocole), DateUtils.swift,
│  │                    Formatters.swift (allure, durée, distance)
│  └─ Tests/RunCoachCoreTests/
│     ├─ (fixtures)     JSON synthétiques écrits dans les tests eux-mêmes (pas de dossier de ressources à gérer sous Linux)
│     └─ *Tests.swift   un fichier de tests par fichier source non trivial
├─ App/
│  ├─ RunCoachApp.swift            ← @main, ModelContainer, injection, tâche d'arrière-plan
│  ├─ AppEnvironment.swift         ← assemble les services (réels ou factices)
│  ├─ DesignSystem/
│  │  ├─ Tokens.swift              ← couleurs, espacements, rayons, animations
│  │  ├─ Typography.swift
│  │  ├─ Haptics.swift
│  │  └─ Components/               StatTile, HeroWorkoutCard, WorkoutBadge, WeekStrip, RingProgress,
│  │                               ZoneBar, MiniChart, ChatBubble, PrimaryButton, SectionHeader,
│  │                               EmptyState, SyncPill, StepRow, ConfirmCard
│  ├─ Data/
│  │  ├─ Models/                   une entité SwiftData par fichier (§4)
│  │  ├─ Stores/                   RunStore, PlanStore, ProfileStore, ChatStore (requêtes et écritures)
│  │  └─ Mock/MockData.swift       jeu de données factices déterministe
│  ├─ Services/
│  │  ├─ KeychainTokenStore.swift  ← implémente TokenStore
│  │  ├─ URLSessionHTTPClient.swift← implémente HTTPClient
│  │  ├─ SyncEngine.swift          ← F1
│  │  ├─ WatchSyncEngine.swift     ← F3
│  │  ├─ BackgroundSync.swift      ← BGTaskScheduler
│  │  └─ Notifications.swift       ← notifications locales
│  ├─ Features/
│  │  ├─ Root/                     RootView (TabView), AppRouter
│  │  ├─ Onboarding/               OnboardingFlow + une vue par étape
│  │  ├─ Today/                    TodayView, TodayViewModel
│  │  ├─ Plan/                     PlanView (semaine/mois), PlannedWorkoutDetailView
│  │  ├─ RunDetail/                RunDetailView, SplitsView
│  │  ├─ Replay/                   ReplayView, ReplayViewModel, ReplayMap, ReplayChart, ReplayControls
│  │  ├─ Coach/                    CoachChatView, CoachViewModel
│  │  ├─ Progress/                 ProgressScreen (pas « ProgressView » : nom pris par SwiftUI), RunListView
│  │  ├─ Settings/                 SettingsView, ProfileEditView, GarminSettingsView, AISettingsView
│  │  └─ GarminLogin/              GarminLoginView (WKWebView), GarminLoginCoordinator
│  └─ Resources/
│     ├─ Assets.xcassets           couleurs (clair/sombre), icône
│     └─ Info.plist
└─ AppUITests/
   └─ ScreenshotTests.swift        ← lance l'app en mode factice et capture chaque écran
```

### 3.2 Modules et dépendances
- `RunCoachCore` n'importe que `Foundation` (et `FoundationNetworking` sous Linux/Windows via `#if canImport(FoundationNetworking)`). **Interdits dans Core** : SwiftUI, SwiftData, MapKit, CoreLocation, UIKit, Security, WebKit. Les coordonnées sont des `Double` (latitude, longitude), pas des `CLLocationCoordinate2D`.
- `App` dépend de `RunCoachCore`. Les entités SwiftData vivent dans `App/Data` et se convertissent en types Core par des extensions (`Run.toSummary()`, etc.).
- Deux protocoles seulement, justifiés par la testabilité et la portabilité : `TokenStore` (Keychain côté app, mémoire dans les tests) et `HTTPClient` (`URLSession` côté app, réponses simulées dans les tests). Pas d'autre abstraction sans besoin constaté.

### 3.3 Conventions
- Un type principal par fichier, fichier nommé comme le type.
- Vues : suffixe `View`. Un écran = `XxxView` + `XxxViewModel` (`@Observable`, `@MainActor`). Les sous-vues simples restent dans le fichier de l'écran tant qu'il fait moins de 300 lignes.
- Entités SwiftData : nom au singulier sans suffixe (`Run`, `Split`). DTO de décodage réseau : suffixe `DTO`, dans `Core/Garmin/GarminDTO.swift`.
- Services : `actor` quand ils portent un état partagé (`GarminAuth`, `GarminAPI`), `struct` sans état sinon (`Guardrails`, `MacroPlanner`). `SyncEngine` est une classe `@MainActor @Observable` qui écrit dans le contexte principal de SwiftData : les écrans suivent son état, et un seul contexte évite de passer des entités d'un acteur à l'autre. Le réseau, lui, s'attend hors du fil principal (acteurs Core).
- Unités dans les noms de champs : `distanceM`, `durationS`, `paceSPerKm`, `speedMps`, `elevationGainM`. Jamais de nombre sans unité dans son nom.
- Dates : `Date` en UTC en base ; un « jour » de plan est une chaîne `yyyy-MM-dd` dans le fuseau local (`DayKey`).
- Tout champ venant de Garmin est décodé en optionnel. Un champ absent ne doit jamais faire échouer l'import d'une activité.
- Chaînes d'interface en français directement dans le code (pas de fichier de localisation : une seule langue).
- Commentaires : uniquement le « pourquoi » que le code ne montre pas. Les raccourcis assumés sont notés `// shortcut: <limite>, <quand améliorer>`.
- Aucune couleur, taille de police ou espacement en dur dans les vues : tout passe par `DesignSystem/Tokens.swift`.
- Tests : toute logique de Core non triviale a un test. Les vues n'ont pas de tests unitaires ; elles sont vérifiées par les captures d'écran de la CI.

### 3.4 Compilation et installation sans Mac
**CI `core.yml`** (Linux, à chaque push) : `swift build` puis `swift test` dans `Packages/RunCoachCore`. C'est la boucle rapide.

**CI `ios.yml`** (macOS ; à chaque push sur `main` et sur déclenchement manuel) :
1. `xcodebuild -version` et `xcrun simctl list devices available` (affichés dans le log : les images de runner changent).
2. `brew install xcodegen`, puis `xcodegen generate`.
3. Build + tests UI sur simulateur (premier iPhone grand format disponible), en clair et en sombre, avec l'argument de lancement `-mockData`.
4. Export des captures : `xcrun xcresulttool export attachments`, publiées en artefact `screenshots`.
5. Build `Release` pour `iphoneos` avec `CODE_SIGNING_ALLOWED=NO`, empaquetage `Payload/RunCoach.app` en `RunCoach.ipa`, publié en artefact `ipa`.

**Boucle de travail du modèle qui implémente** : écrire → pousser → `gh run watch` → lire les erreurs (`gh run view --log-failed`) → corriger. Pour l'UI : `gh run download -n screenshots` puis lire les PNG.

**Installation sur l'iPhone** (par l'utilisateur, sous Windows) :
1. Installer « Apple Devices » (ou iTunes) et Sideloadly.
2. Sur l'iPhone : Réglages → Confidentialité et sécurité → Mode développeur → activer.
3. Télécharger `RunCoach.ipa` depuis l'artefact de la CI, le glisser dans Sideloadly, saisir son identifiant Apple, installer (USB).
4. Sur l'iPhone : Réglages → Général → VPN et gestion de l'appareil → faire confiance au profil.
5. Tous les 7 jours : relancer l'installation par-dessus l'app existante (les données sont conservées). Sideloadly propose un rafraîchissement automatique en Wi-Fi quand le PC est allumé.

Limites du compte gratuit : 7 jours de validité, 3 apps au plus, pas de notifications push distantes. **[À VÉRIFIER étape 1]** : des blocages de profils gratuits par Apple ont été signalés en septembre 2026 (erreurs `0xe8008024` / `0xe8008018`) ; à confirmer par une première installation réelle dès que l'IPA de l'étape 1 existe.

**Quota GitHub Actions.** Les minutes macOS coûtent environ dix fois les minutes Linux. Dépôt privé : quota inclus du compte (GitHub Student = Pro) **[À VÉRIFIER étape 1 dans Settings → Billing]**. Si le quota ne suffit pas : rendre le dépôt public (Actions y est gratuit), ce qui est possible car le dépôt ne contient aucun secret ni donnée personnelle (§9.4).

---

## 4. Modèle de données

### 4.1 Entités SwiftData (`App/Data/Models`)
Toutes les relations « enfant » sont en `deleteRule: .cascade`.
Les identifiants propres s'appellent `uuid` (et non `id`, déjà fourni par SwiftData).
Fichiers : `AthleteProfile.swift`, `Goal.swift`, `Run.swift` (avec `Split` et `RunTrack`), `Plan.swift` (`TrainingPlan`, `PlannedWorkout`), `Misc.swift` (`DailyMetric`, `ChatMessage`, `SyncState`).
Insérer un objet dans le `ModelContext` **avant** de toucher à ses relations.

**`AthleteProfile`** — une seule ligne.
| Champ | Type | Note |
|---|---|---|
| `firstName` | String | Jamais envoyé à l'IA |
| `birthDate` | Date | L'IA reçoit l'âge |
| `sex` | String? | `male` / `female` / nil |
| `heightCm`, `weightKg` | Double? | Optionnels |
| `runningSince` | Date | Sert à dériver le niveau |
| `recentRunDistanceM`, `recentRunDurationS` | Double | Sortie de référence saisie à l'onboarding |
| `recentRunEffort` | String | `easy` / `moderate` / `hard` |
| `thresholdPaceOverrideSPerKm` | Double? | Réglage manuel de l'allure seuil |
| `availableWeekdays` | [Int] | 1 = lundi … 7 = dimanche |
| `longRunWeekday` | Int | |
| `maxSessionMinutes` | Int | |
| `hrMax`, `hrRest` | Int? | Sinon estimés (§6.3) |
| `injuryNote` | String | Texte libre, antécédents |
| `currentPain` | Bool | Active le mode prudent (§6.4, G11) |
| `fatigueLevel` | String | `low` / `normal` / `high` |
| `wantsStrength` | Bool | |
| `strengthEquipment` | String | `none` / `dumbbells` / `gym` |
| `medicalDisclaimerAcceptedAt` | Date? | Obligatoire pour sortir de l'onboarding |
| `updatedAt` | Date | |

**`Goal`** — `uuid: UUID`, `kind` (`race` / `fitness`), `name`, `raceDistanceM: Double?`, `raceDate: Date?`, `targetTimeS: Double?`, `isActive: Bool`. Un seul objectif actif.

**`Run`** — une activité importée.
| Champ | Type | Note |
|---|---|---|
| `garminActivityId` | Int64, `@Attribute(.unique)` | Clé d'idempotence de l'import |
| `name` | String | |
| `startDate` | Date | UTC |
| `dayKey` | String | Jour local `yyyy-MM-dd` |
| `activityType` | String | `typeKey` Garmin (`running`, `trail_running`, `treadmill_running`, `strength_training`, …). Le renfo n'a ni distance ni tracé. |
| `distanceM`, `durationS` | Double | |
| `movingDurationS` | Double? | |
| `avgSpeedMps`, `maxSpeedMps` | Double? | |
| `avgHR`, `maxHR` | Int? | |
| `avgCadenceSpm` | Double? | |
| `elevationGainM`, `elevationLossM` | Double? | |
| `calories` | Double? | |
| `avgTemperatureC` | Double? | |
| `vo2max` | Double? | |
| `aerobicTE`, `anaerobicTE` | Double? | Training effect Garmin |
| `garminLoad` | Double? | Charge Garmin, affichage seul |
| `edwardsLoad` | Double? | Charge calculée par l'app (§6.3) |
| `hrZoneSeconds` | [Double] | 5 valeurs, vide si inconnu |
| `locationName` | String? | Jamais envoyé à l'IA |
| `detailState` | String | `summaryOnly` / `complete` / `failed` |
| `perceivedEffort` | Int? | 1 à 10, saisi par l'utilisateur après coup |
| `userNote` | String? | |
| `splits` | [Split] | cascade |
| `track` | RunTrack? | cascade |
| `plannedWorkout` | PlannedWorkout? | Rattachement par `WorkoutMatcher` |

**`Split`** — `index: Int`, `distanceM`, `durationS`, `avgSpeedMps: Double?`, `avgHR: Int?`, `avgCadenceSpm: Double?`, `elevationGainM: Double?`, `elevationLossM: Double?`, `run: Run`.

**`RunTrack`** — `@Attribute(.externalStorage) samplesData: Data`, `sampleCount: Int`, `run: Run`.
`samplesData` est un `Track` (type Core, §4.2) encodé en JSON.
Le tracé n'est **pas** modélisé en une entité par point : 2 000 points par sortie donneraient plusieurs centaines de milliers de lignes par an, ce que SwiftData gère mal. Le replay a de toute façon besoin du tableau entier d'un coup.

**`DailyMetric`** — `dayKey: String` (unique), `sleepSeconds: Double?`, `sleepScore: Int?`, `hrvLastNightMs: Double?`, `hrvStatus: String?`, `restingHR: Int?`, `vo2max: Double?`, `trainingReadiness: Int?`, `trainingStatus: String?`, `bodyBattery: Int?`.

**`TrainingPlan`** — `uuid: UUID`, `createdAt`, `goal: Goal?`, `macroWeeksData: Data` (`[MacroWeek]` JSON), `isActive: Bool`, `workouts: [PlannedWorkout]` cascade.

**`PlannedWorkout`**
| Champ | Type | Note |
|---|---|---|
| `uuid` | UUID | |
| `dayKey` | String | |
| `kind` | String | `WorkoutKind` (§5.3) |
| `title`, `rationale` | String | |
| `specData` | Data | `WorkoutSpec` JSON (§5.3) |
| `estimatedDurationMin` | Int | |
| `estimatedDistanceKm` | Double? | nil pour le renfo |
| `status` | String | `planned` / `done` / `missed` / `skipped` / `cancelled` |
| `source` | String | `ai` / `fallback` / `user` |
| `garminWorkoutId`, `garminScheduleId` | Int64? | |
| `garminSyncState` | String | `notSent` / `sent` / `needsUpdate` / `failed` |
| `garminSyncError` | String? | |
| `completedRun` | Run? | inverse de `Run.plannedWorkout` |
| `plan` | TrainingPlan | |
| `updatedAt` | Date | |

**`ChatMessage`** — `uuid: UUID`, `role` (`user` / `assistant`), `text`, `createdAt`, `actionsData: Data?` (`[PlanAction]` JSON), `actionLines: [String]` (résumé lisible des actions, pour `ConfirmCard`), `actionsState` (`none` / `proposed` / `applied` / `rejected`).

**`SyncState`** — une seule ligne : `lastGarminSyncAt: Date?`, `lastSyncError: String?`, `backfillDone: Bool`, `garminDisplayName: String?`, `nextAllowedGarminCallAt: Date?`, `consecutiveFailures: Int`.

### 4.2 Types Core (`RunCoachCore/Models`, `Codable`, `Sendable`)
```swift
/// Tracé d'une sortie, en colonnes. Tous les tableaux présents ont la même longueur.
public struct Track: Codable, Sendable {
    public var t: [Double]        // secondes depuis le départ (temps écoulé)
    public var lat: [Double]
    public var lon: [Double]
    public var dist: [Double]     // mètres cumulés
    public var ele: [Double]?     // mètres
    public var hr: [Double]?      // bpm
    public var cad: [Double]?     // pas/min
    public var speed: [Double]?   // m/s
}
```
À l'import, une valeur manquante dans une colonne est remplacée par la dernière valeur connue (ou la suivante en début de série). Un échantillon sans latitude ou longitude est supprimé. Une colonne entièrement vide vaut `nil`.

`MacroWeek` : `weekStart: String`, `phase` (`base` / `build` / `peak` / `taper` / `race`), `targetKm: Double`, `longRunKm: Double`, `sessions: Int`, `qualitySessions: Int`, `isCutback: Bool`.

`WorkoutSpec`, `AthleteSnapshot`, `WeekBrief`, `PlanAction` : voir §5.3 et §6.

### 4.3 Stratégie de synchro et de cache
- **SwiftData est la source de vérité de l'affichage.** Aucun écran n'attend le réseau pour s'afficher.
- **Runs** : importés une fois, immuables ensuite. Idempotence par `garminActivityId`. Une activité dont les détails ont échoué reste en `summaryOnly` et est retentée à la synchro suivante (trois tentatives au plus, puis `failed`).
- **Premier import** (demande de l'utilisateur, 2026-11-13 : « récupérer toutes les données ») : tout l'historique, sans plafond de requêtes, app ouverte, une requête par seconde (environ une par sortie GPS). Chaque activité est enregistrée dès qu'elle est lue : si l'app passe en arrière-plan, l'import reprend à la synchro suivante. `backfillDone` ne passe à vrai que quand la liste est complète et qu'aucun détail ne manque.
- **Synchro régulière** : ce qui manque seulement, 40 requêtes au plus au premier plan, 20 en arrière-plan.
- **Détails en échec** : `Run.detailAttempts` compte les échecs ; à 3, `detailState = failed`.
- **Plan** : local. Le calendrier Garmin n'est qu'un miroir en écriture des 7 prochains jours. L'app ne relit jamais le calendrier Garmin.
- **Rattachement réalisé/prévu** (`WorkoutMatcher`) : un `Run` est rattaché au `PlannedWorkout` de type course du même `dayKey` encore `planned`. À la fin d'un jour local, une séance toujours `planned` passe à `missed`.
- **Mode factice** : avec l'argument de lancement `-mockData` (ajouté par `ScreenshotTests`), `ModelContainer` en mémoire rempli par `MockData.seed()`. Sans lui, base persistante sur l'iPhone (depuis l'étape 2).
- **Captures d'écran** : l'argument `-screen <nom>` affiche directement un écran (`DebugScreen` dans `RootView.swift`), `-scheme light|dark` force l'apparence. Tout nouvel écran s'ajoute à `DebugScreen` et à la liste de `ScreenshotTests`.

---

## 5. Contrats d'API

Il n'y a pas de backend, donc pas d'endpoints propres au projet. Les contrats sont : l'API Garmin (§5.1, §5.2), le format des séances (§5.3), l'API du fournisseur IA (§5.4), la gestion d'erreurs (§5.5).

Source des faits Garmin : code de `python-garminconnect` 0.3.20 (23 octobre 2026), lu le 2026-11-12. Rien n'a été testé en réel. **Première tâche de l'étape 2 : valider sur le compte de l'utilisateur (§8, tâche 2.0).**

### 5.1 Garmin : authentification

#### 5.1.1 Constantes (`GarminIdentity.swift`)
```
signInURL  = https://sso.garmin.com/mobile/sso/en_US/sign-in
             ?clientId=GCM_IOS_DARK
             &service=https://mobile.integration.garmin.com/gcm/ios      (valeur encodée en URL)
serviceURL = https://mobile.integration.garmin.com/gcm/ios
tokenURL   = https://diauth.garmin.com/di-oauth2-service/oauth/token
apiBase    = https://connectapi.garmin.com
grantTypeTicket = https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket

diClientIds (essayés dans l'ordre ; le premier a été accepté à la validation 2.0) =
   GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2
   GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4
   GARMIN_CONNECT_MOBILE_ANDROID_DI
   GARMIN_CONNECT_MOBILE_IOS_DI
```
Un seul jeu d'en-têtes pour les appels `diauth` et `connectapi` (`GarminIdentity.headers`), celui de la librairie, seul validé en réel (2.0). Le jeu « iOS » envisagé au départ (`GCM-iOS-5.22.1.4`) n'a jamais été testé et a été retiré.
  `User-Agent: GCM-Android-5.23`
  `X-Garmin-User-Agent: com.garmin.android.apps.connectmobile/5.23; ; Google/sdk_gphone64_arm64/google; Android/33; Dalvik/2.1.0`
  `X-Garmin-Paired-App-Version: 10861` · `X-Garmin-Client-Platform: Android` · `X-App-Ver: 10861` · `X-Lang: en` · `X-GCExperience: GC5` · `Accept: application/json` · `Accept-Language: en-US,en;q=0.9`

Constat de la validation 2.0 : la librairie appelle `connectapi` avec la pile TLS ordinaire de Python et ces en-têtes Android, et Garmin accepte. L'empreinte TLS ne compte donc pas pour l'API, seulement (peut-être) pour la connexion SSO, qui se fait ici dans le vrai navigateur de l'iPhone.

#### 5.1.2 Connexion dans l'app (méthode principale : WKWebView)
`GarminLoginView` affiche `signInURL` dans un `WKWebView` (`WKWebsiteDataStore.nonPersistent()`, User-Agent par défaut du WKWebView, ne pas le modifier). L'utilisateur saisit ses identifiants et son éventuel code MFA dans la page de Garmin.

Le ticket de service (`ST-…`) est capté par trois crochets, du plus propre au plus tolérant. Le premier qui réussit gagne ; les suivants sont ignorés.
1. **Navigation.** Dans `webView(_:decidePolicyFor:)`, si l'URL demandée contient `ticket=(ST-[A-Za-z0-9\-]+)` : extraire le ticket et répondre `.cancel`.
2. **Réponses réseau de la page.** Un `WKUserScript` injecté à `documentStart` enveloppe `fetch` et `XMLHttpRequest`. Pour toute réponse dont l'URL contient `/api/login` ou `/api/mfa/verifyCode`, si le JSON contient `serviceTicketId`, le script envoie **uniquement** cette valeur à `window.webkit.messageHandlers.rc.postMessage`.
3. **Contenu de la page.** Dans `didFinish`, recherche de la même expression régulière dans `document.documentElement.outerHTML`.

Dès qu'un ticket est capté : fermer la vue web, puis échange immédiat (§5.1.3). Le ticket est à usage unique et de courte durée.

Diagnostic sans débogueur : `GarminLoginCoordinator` tient un journal en mémoire des hôtes et chemins visités (jamais les paramètres de requête, jamais le ticket), consultable dans Réglages → Garmin → Diagnostic.

#### 5.1.2 bis Connexion native (repli si la capture échoue)
Formulaire SwiftUI (e-mail, mot de passe), puis avec `URLSession` et l'User-Agent
`Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148` :
1. `GET signInURL` (obligatoire avant le POST : sans ce chargement préalable Garmin répond 429).
2. Attendre 2 à 5 s (durée aléatoire).
3. `POST https://sso.garmin.com/mobile/api/login?clientId=GCM_IOS_DARK&locale=en-US&service=<serviceURL>`
   En-têtes : `Content-Type: application/json`, `Origin: https://sso.garmin.com`, `Referer: <signInURL complet>`.
   Corps : `{"username":"…","password":"…","rememberMe":true,"captchaToken":""}`
4. Lire `responseStatus.type` :
   - `SUCCESSFUL` → `serviceTicketId`.
   - `MFA_REQUIRED` → demander le code, puis `POST https://sso.garmin.com/mobile/api/mfa/verifyCode` (mêmes paramètres de requête), corps `{"mfaMethod":"<valeur reçue>","mfaVerificationCode":"…","rememberMyBrowser":true,"reconsentList":[],"mfaSetup":false}`.
   - `INVALID_USERNAME_PASSWORD` → message, aucune nouvelle tentative automatique.
   - `CAPTCHA_REQUIRED` → abandon, proposer la méthode WKWebView.
   - HTTP 403 → défi Cloudflare, abandon. HTTP 427 ou 429 → blocage, backoff (§5.1.6).

Le mot de passe n'est jamais stocké.

#### 5.1.3 Échange du ticket contre des jetons
```
POST https://diauth.garmin.com/di-oauth2-service/oauth/token
Authorization: Basic base64("<client_id>:")          ← deux-points final, secret vide
Content-Type: application/x-www-form-urlencoded
Accept: application/json,text/html;q=0.9,*/*;q=0.8
Cache-Control: no-cache
+ en-têtes d'identité (§5.1.1)

client_id=<client_id>
&service_ticket=<ST-…>
&grant_type=https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket
&service_url=https://mobile.integration.garmin.com/gcm/ios
```
Essayer chaque `client_id` de `diClientIds` dans l'ordre ; le premier qui répond 200 avec `access_token` gagne.

Réponse : `access_token` (JWT), `refresh_token` (opaque), `expires_in` (environ 25 h), `refresh_token_expires_in` (environ 30 jours).

Stockage Keychain (`TokenStore`), trois valeurs : `di_token`, `di_refresh_token`, `di_client_id`. `di_client_id` est relu dans la revendication `client_id` du JWT quand elle existe. L'expiration est lue dans la revendication `exp` du JWT.

#### 5.1.4 Rafraîchissement
```
POST https://diauth.garmin.com/di-oauth2-service/oauth/token
Authorization: Basic base64("<di_client_id>:")
Content-Type: application/x-www-form-urlencoded
Accept: application/json
+ en-têtes d'identité

grant_type=refresh_token&client_id=<di_client_id>&refresh_token=<di_refresh_token>
```
- Déclenchement : avant tout appel si `now > exp − 15 min`, et sur toute réponse 401 (un seul nouvel essai).
- **Le jeton de rafraîchissement tourne à chaque appel.** Persister le nouveau `refresh_token` dans le Keychain avant d'utiliser le nouvel `access_token`. Si la réponse ne contient pas de `refresh_token`, conserver l'ancien.
- **Un seul rafraîchissement à la fois** : `GarminAuth` est un `actor` et mémorise la `Task` en cours ; les appelants concurrents attendent son résultat. Deux rafraîchissements parallèles avec le même jeton invalident la session.
- Réponse 400 ou 401 : session perdue → effacer les jetons, état `needsLogin`, bandeau « Reconnecte-toi à Garmin ». Aucune reconnexion automatique.

#### 5.1.5 Appels d'API
`<apiBase><chemin>` avec `Authorization: Bearer <di_token>` et les en-têtes d'identité. Réponses JSON.

#### 5.1.6 Règles anti-blocage (à respecter à la lettre)
1. Une tentative de connexion = une action explicite de l'utilisateur. Jamais de connexion en arrière-plan ni en boucle.
2. Requêtes strictement séquentielles, 1 s au moins entre deux requêtes (`GarminAPI`). 40 requêtes au plus par synchro régulière, 20 en arrière-plan ; le premier import n'a pas de plafond (§4.3, demande de l'utilisateur) mais garde le rythme d'une requête par seconde et s'arrête au premier 427/429/403. La librairie Python, elle, enchaîne cinq méthodes de connexion après un refus : l'app n'en a qu'une.
3. HTTP 427 ou 429 (tous hôtes) : arrêt immédiat de la synchro ; `nextAllowedGarminCallAt = now + min(15 min × 2^consecutiveFailures, 24 h)`.
4. HTTP 403 sur `connectapi` : considéré comme un blocage du client ou du réseau, pas comme un jeton invalide. Arrêt, backoff d'une heure, pas de rafraîchissement.
5. Une synchro réussie remet `consecutiveFailures` à zéro.
6. Les tests automatiques n'appellent jamais les serveurs de Garmin (uniquement `HTTPClient` simulé).

### 5.2 Garmin : endpoints utilisés
Chemins relatifs à `https://connectapi.garmin.com`.

| Usage | Méthode et chemin |
|---|---|
| Profil (récupère `displayName`) | `GET /userprofile-service/socialProfile` |
| Réglages utilisateur | `GET /userprofile-service/userprofile/user-settings` |
| Zones FC | `GET /biometric-service/heartRateZones` |
| Liste des activités | `GET /activitylist-service/activities/search/activities?start=0&limit=20` |
| Résumé d'une activité | `GET /activity-service/activity/{id}` |
| Détails avec échantillons | `GET /activity-service/activity/{id}/details?maxChartSize=2000&maxPolylineSize=4000` |
| Splits | `GET /activity-service/activity/{id}/splits` |
| Temps par zone FC | `GET /activity-service/activity/{id}/hrTimeInZones` |
| Météo | `GET /activity-service/activity/{id}/weather` |
| Sommeil | `GET /sleep-service/sleep/dailySleepData?date=YYYY-MM-DD&nonSleepBufferMinutes=60` |
| HRV | `GET /hrv-service/hrv/{YYYY-MM-DD}` |
| VO2max | `GET /metrics-service/metrics/maxmet/latest/{YYYY-MM-DD}` |
| Statut d'entraînement | `GET /metrics-service/metrics/trainingstatus/aggregated/{YYYY-MM-DD}` |
| Disponibilité à l'entraînement | `GET /metrics-service/metrics/trainingreadiness/{YYYY-MM-DD}` |
| Créer un workout | `POST /workout-service/workout` (corps §5.3.3) |
| Supprimer un workout | `DELETE /workout-service/workout/{workoutId}` |
| Planifier à une date | `POST /workout-service/schedule/{workoutId}` corps `{"date":"YYYY-MM-DD"}` |
| Déplanifier | `DELETE /workout-service/schedule/{scheduleId}` |
| Lister ses workouts (nettoyage) | `GET /workout-service/workouts?start=0&limit=100&myWorkoutsOnly=true` |

**Utilisés à l'étape 2** : profil, liste des activités (pages de `limit=100` ; la librairie accepte jusqu'à 1 000), détails, sommeil, statut d'entraînement. **Inutiles** : résumé d'une activité, splits, temps par zone, météo (la liste suffit, voir F1) ; VO2max (contenu dans le statut d'entraînement) ; HRV et disponibilité à l'entraînement (réponses vides `{}` et `[]` avec la Forerunner 745, constat du 2026-11-13). Zones FC du profil : lues à l'étape 4 si le coach en a besoin.

Le temps de récupération n'a pas d'endpoint connu : non importé.

**Noms de champs JSON relevés sur le compte de l'utilisateur le 2026-11-13** (structure seulement, valeurs masquées). Tout est décodé en optionnel (`GarminDTO.swift`).
- Élément de la liste d'activités : `activityId`, `activityName`, `startTimeGMT` et `startTimeLocal` (`yyyy-MM-dd HH:mm:ss`), `beginTimestamp` (ms), `activityType.typeKey`, `distance` (m), `duration`, `elapsedDuration`, `movingDuration` (s), `averageSpeed`, `maxSpeed` (m/s), `averageHR`, `maxHR`, `averageRunningCadenceInStepsPerMinute` (pas/min, deux pieds), `elevationGain`, `elevationLoss`, `calories`, `aerobicTrainingEffect`, `anaerobicTrainingEffect`, `activityTrainingLoad`, `minTemperature`, `maxTemperature`, `locationName`, `hasPolyline`, `hrTimeInZone_1` à `hrTimeInZone_5` (s). `vO2MaxValue` n'apparaissait pas sur les sorties lues ; gardé en optionnel.
- Détails : `metricDescriptors[]` (`metricsIndex`, `key`, `unit.factor`) décrit les colonnes ; `activityDetailMetrics[].metrics[]` contient les valeurs. **Les valeurs sont déjà dans l'unité annoncée** : `factor` (100 pour les mètres, 1 000 pour les secondes) ne s'applique pas ; vérifié en comparant le dernier `sumDistance` à la distance du résumé (rapport 1,0). Clés vues : `sumElapsedDuration`, `sumMovingDuration`, `sumDuration` (s), `sumDistance` (m), `directLatitude`, `directLongitude`, `directElevation` (m), `directHeartRate`, `directRunCadence` (un pied), `directDoubleCadence` (deux pieds, l'unité de l'app), `directFractionalCadence`, `directSpeed` (m/s), `directVerticalSpeed`, `directAirTemperature`, `directTimestamp` (ms). Environ 1 900 lignes pour 2 000 demandées. **Toujours résoudre la colonne par sa `key`, jamais par un indice fixe.**
- Sommeil : `dailySleepDTO.sleepTimeSeconds`, `dailySleepDTO.sleepScores.overall.value`, `restingHeartRate` (racine).
- Statut d'entraînement : `mostRecentVO2Max.generic.vo2MaxPreciseValue`, `mostRecentTrainingStatus.latestTrainingStatusData.<idMontre>.trainingStatusFeedbackPhrase` (ex. `RECOVERY_AER_LOW_SHORT`) et `primaryTrainingDevice`.
- Réponse de création de workout : identifiant dans `workoutId`. Réponse de planification : identifiant dans `workoutScheduleId` (confirmé).

Toutes les activités sont importées, de tout type (`running`, `hiking`, `strength_training`…). Les séries réelles d'un renfo (`/activity-service/activity/{id}/exerciseSets`) ne sont pas importées : aucun renfo n'existait sur le compte pour vérifier la réponse. `shortcut` : à ajouter dès qu'un renfo Garmin existe, en relançant le script 2.0.

### 5.3 Format des séances

#### 5.3.1 `WorkoutSpec` (produit par l'IA, stocké dans `PlannedWorkout.specData`)
Une séance de course est une liste de **blocs** ; un bloc est une liste d'étapes répétée `repeat` fois (`repeat = 1` : pas de répétition). Pas de structure polymorphe ni d'imbrication plus profonde : les petits modèles s'y trompent.

```json
{
  "date": "2026-11-18",
  "kind": "intervals",
  "title": "Fractionné court 6 × 400 m",
  "rationale": "Première séance de vitesse : habituer les jambes à une allure plus rapide que l'objectif, sur des efforts très courts.",
  "estimated_duration_min": 40,
  "estimated_distance_km": 6.0,
  "blocks": [
    { "repeat": 1, "steps": [
      { "intent": "warmup", "end": "time", "value": 600,
        "target": { "type": "none", "min_s_per_km": null, "max_s_per_km": null, "hr_zone": null },
        "note": "Très facile" } ] },
    { "repeat": 6, "steps": [
      { "intent": "run", "end": "distance", "value": 400,
        "target": { "type": "pace", "min_s_per_km": 325, "max_s_per_km": 340, "hr_zone": null },
        "note": null },
      { "intent": "recover", "end": "time", "value": 90,
        "target": { "type": "none", "min_s_per_km": null, "max_s_per_km": null, "hr_zone": null },
        "note": "Marche ou trot" } ] },
    { "repeat": 1, "steps": [
      { "intent": "cooldown", "end": "time", "value": 600,
        "target": { "type": "none", "min_s_per_km": null, "max_s_per_km": null, "hr_zone": null },
        "note": null } ] }
  ],
  "exercises": []
}
```

| Champ | Valeurs |
|---|---|
| `kind` | `easy`, `long`, `tempo`, `intervals`, `recovery`, `strength`, `race` |
| `intent` | `warmup`, `run`, `recover`, `rest`, `cooldown` |
| `end` | `time` (`value` en secondes), `distance` (`value` en mètres), `lap_button` (`value` nul) |
| `target.type` | `none`, `pace` (`min_s_per_km` = borne rapide, `max_s_per_km` = borne lente, en secondes par km), `hr_zone` (`hr_zone` de 1 à 5) |
| `rationale` | 240 caractères au plus, en français, tutoiement |
| `title` | 40 caractères au plus |

Un jour sans séance est un jour de repos : il n'y a pas de `kind` « repos ».

**Renforcement** (`kind = strength`) : `blocks` est vide, `exercises` est rempli.
```json
{ "exercise_id": "squat", "sets": 3, "reps": 12, "duration_s": null, "rest_s": 60, "note": "Descends lentement" }
```
`reps` ou `duration_s`, l'autre est nul. `exercise_id` appartient au catalogue fixe `StrengthCatalog` (Core) : `squat`, `lunge`, `step_up`, `glute_bridge`, `hip_thrust`, `single_leg_deadlift`, `calf_raise`, `wall_sit`, `plank`, `side_plank`, `dead_bug`, `bird_dog`, `clamshell`, `superman`, `push_up`, `mountain_climber`. Chaque entrée du catalogue porte : nom français, consigne courte, matériel requis, catégorie Garmin.

#### 5.3.2 Schéma JSON (`CoachSchemas.swift`)
Envoyé au fournisseur IA dans `response_format`. Tous les champs sont requis, les absents valent `null`, `additionalProperties` est faux partout (exigence du mode strict).
```json
{
  "type": "object", "additionalProperties": false,
  "required": ["week_start", "summary", "workouts"],
  "properties": {
    "week_start": { "type": "string" },
    "summary": { "type": "string" },
    "workouts": { "type": "array", "items": { "$ref": "#/$defs/workout" } }
  },
  "$defs": {
    "target": {
      "type": "object", "additionalProperties": false,
      "required": ["type", "min_s_per_km", "max_s_per_km", "hr_zone"],
      "properties": {
        "type": { "type": "string", "enum": ["none", "pace", "hr_zone"] },
        "min_s_per_km": { "type": ["integer", "null"] },
        "max_s_per_km": { "type": ["integer", "null"] },
        "hr_zone": { "type": ["integer", "null"] }
      }
    },
    "step": {
      "type": "object", "additionalProperties": false,
      "required": ["intent", "end", "value", "target", "note"],
      "properties": {
        "intent": { "type": "string", "enum": ["warmup", "run", "recover", "rest", "cooldown"] },
        "end": { "type": "string", "enum": ["time", "distance", "lap_button"] },
        "value": { "type": ["number", "null"] },
        "target": { "$ref": "#/$defs/target" },
        "note": { "type": ["string", "null"] }
      }
    },
    "block": {
      "type": "object", "additionalProperties": false,
      "required": ["repeat", "steps"],
      "properties": {
        "repeat": { "type": "integer" },
        "steps": { "type": "array", "items": { "$ref": "#/$defs/step" } }
      }
    },
    "exercise": {
      "type": "object", "additionalProperties": false,
      "required": ["exercise_id", "sets", "reps", "duration_s", "rest_s", "note"],
      "properties": {
        "exercise_id": { "type": "string", "enum": ["squat", "lunge", "step_up", "glute_bridge", "hip_thrust", "single_leg_deadlift", "calf_raise", "wall_sit", "plank", "side_plank", "dead_bug", "bird_dog", "clamshell", "superman", "push_up", "mountain_climber"] },
        "sets": { "type": "integer" },
        "reps": { "type": ["integer", "null"] },
        "duration_s": { "type": ["integer", "null"] },
        "rest_s": { "type": "integer" },
        "note": { "type": ["string", "null"] }
      }
    },
    "workout": {
      "type": "object", "additionalProperties": false,
      "required": ["date", "kind", "title", "rationale", "estimated_duration_min", "estimated_distance_km", "blocks", "exercises"],
      "properties": {
        "date": { "type": "string" },
        "kind": { "type": "string", "enum": ["easy", "long", "tempo", "intervals", "recovery", "strength", "race"] },
        "title": { "type": "string" },
        "rationale": { "type": "string" },
        "estimated_duration_min": { "type": "integer" },
        "estimated_distance_km": { "type": ["number", "null"] },
        "blocks": { "type": "array", "items": { "$ref": "#/$defs/block" } },
        "exercises": { "type": "array", "items": { "$ref": "#/$defs/exercise" } }
      }
    }
  }
}
```
Le schéma du chat (`ChatResponse`) réutilise `$defs.workout` :
```json
{
  "reply": "texte affiché à l'utilisateur",
  "actions": [ { "op": "replace", "date": "2026-11-18", "new_date": null, "workout": { … } } ],
  "profile_patch": { "current_pain": null, "fatigue_level": null, "injury_note": null },
  "safety": "none"
}
```
`op` : `add`, `replace`, `remove`, `move` (`new_date` requis pour `move`, `workout` requis pour `add` et `replace`). `fatigue_level` : `low`, `normal`, `high` ou nul. `safety` : `none`, `pain`, `medical`.

#### 5.3.3 Conversion vers Garmin (`GarminWorkoutMapper`)
Corps de `POST /workout-service/workout` :
```json
{
  "workoutName": "RC · Fractionné court 6 × 400 m",
  "description": "<rationale>",
  "sportType": { "sportTypeId": 1, "sportTypeKey": "running", "displayOrder": 1 },
  "estimatedDurationInSecs": 2400,
  "workoutSegments": [ {
    "segmentOrder": 1,
    "sportType": { "sportTypeId": 1, "sportTypeKey": "running", "displayOrder": 1 },
    "workoutSteps": [
      { "type": "ExecutableStepDTO", "stepOrder": 1,
        "stepType": { "stepTypeId": 1, "stepTypeKey": "warmup", "displayOrder": 1 },
        "endCondition": { "conditionTypeId": 2, "conditionTypeKey": "time", "displayOrder": 2, "displayable": true },
        "endConditionValue": 600,
        "targetType": { "workoutTargetTypeId": 1, "workoutTargetTypeKey": "no.target", "displayOrder": 1 } },
      { "type": "RepeatGroupDTO", "stepOrder": 2,
        "stepType": { "stepTypeId": 6, "stepTypeKey": "repeat", "displayOrder": 6 },
        "numberOfIterations": 6,
        "endCondition": { "conditionTypeId": 7, "conditionTypeKey": "iterations", "displayOrder": 7, "displayable": false },
        "endConditionValue": 6,
        "smartRepeat": false,
        "workoutSteps": [
          { "type": "ExecutableStepDTO", "stepOrder": 3,
            "stepType": { "stepTypeId": 3, "stepTypeKey": "interval", "displayOrder": 3 },
            "endCondition": { "conditionTypeId": 3, "conditionTypeKey": "distance", "displayOrder": 3, "displayable": true },
            "endConditionValue": 400,
            "targetType": { "workoutTargetTypeId": 6, "workoutTargetTypeKey": "pace.zone", "displayOrder": 6 },
            "targetValueOne": 2.9412, "targetValueTwo": 3.0769 },
          { "type": "ExecutableStepDTO", "stepOrder": 4,
            "stepType": { "stepTypeId": 4, "stepTypeKey": "recovery", "displayOrder": 4 },
            "endCondition": { "conditionTypeId": 2, "conditionTypeKey": "time", "displayOrder": 2, "displayable": true },
            "endConditionValue": 90,
            "targetType": { "workoutTargetTypeId": 1, "workoutTargetTypeKey": "no.target", "displayOrder": 1 } }
        ] }
    ]
  } ]
}
```
Tables de correspondance :

| `WorkoutSpec` | Garmin |
|---|---|
| `intent: warmup` | `stepTypeId 1`, `warmup` |
| `intent: cooldown` | `stepTypeId 2`, `cooldown` |
| `intent: run` | `stepTypeId 3`, `interval` |
| `intent: recover` | `stepTypeId 4`, `recovery` |
| `intent: rest` | `stepTypeId 5`, `rest` |
| bloc avec `repeat > 1` | `RepeatGroupDTO`, `stepTypeId 6`, `repeat` ; `repeat = 1` : étapes à plat |
| `end: lap_button` | `conditionTypeId 1`, clé `lap.button` **[À VÉRIFIER étape 5]** |
| `end: time` | `conditionTypeId 2`, `time`, valeur en secondes |
| `end: distance` | `conditionTypeId 3`, `distance`, valeur en mètres |
| `target: none` | `workoutTargetTypeId 1`, `no.target` |
| `target: hr_zone` | `workoutTargetTypeId 4`, `heart.rate.zone`, champ `zoneNumber` |
| `target: pace` | `workoutTargetTypeId 6`, `pace.zone`, valeurs en **m/s** |

- Allure : `targetValueOne = 1000 / max_s_per_km` (borne lente, valeur la plus basse), `targetValueTwo = 1000 / min_s_per_km`. Exemple : 5:40/km → 2,9412 ; 5:25/km → 3,0769.
- `stepOrder` : compteur global croissant, étapes imbriquées comprises **[À VÉRIFIER étape 5 contre `garminconnect/workout.py`]**.
- `workoutName` commence toujours par `RC · ` : c'est ce préfixe qui permet de retrouver et nettoyer les workouts créés par l'app.
- Renforcement : `sportType` `{ "sportTypeId": 5, "sportTypeKey": "strength_training", "displayOrder": 5 }`. Chaque exercice devient un `RepeatGroupDTO` de `sets` itérations contenant une étape `interval` (champs `category` et `exerciseName`, condition `reps` `conditionTypeId 10` ou `time`) et une étape `rest` en temps. Les valeurs de `category` valides sont dans `garminconnect/exercises.py` **[À VÉRIFIER étape 5]**. Si l'envoi d'un renfo échoue, la séance reste dans l'app avec l'état `failed`, sans bloquer l'envoi des séances de course.

### 5.4 API du fournisseur IA (`LLMClient`)
Format « OpenAI chat completions », commun aux fournisseurs retenus.
```
POST {baseURL}/chat/completions
Authorization: Bearer <clé de l'utilisateur>
Content-Type: application/json

{
  "model": "<modèle choisi dans Réglages>",
  "temperature": 0.4,
  "messages": [
    { "role": "system", "content": "<prompt système>" },
    { "role": "user",   "content": "<contexte JSON + demande>" }
  ],
  "response_format": { "type": "json_schema",
                       "json_schema": { "name": "week_plan", "strict": true, "schema": { … } } }
}
```
Réponse utile : `choices[0].message.content` (chaîne contenant le JSON).

Si le fournisseur refuse `json_schema` (HTTP 400 mentionnant `response_format`) : un seul nouvel essai avec `{"type":"json_object"}` et le schéma recopié à la fin du prompt système ; le choix est mémorisé pour ce fournisseur. Dans tous les cas la réponse est décodée par `Codable` puis validée par `Guardrails` : le schéma côté fournisseur est une aide, pas une garantie.

Préréglages de `LLMProvider` (`baseURL` modifiable dans Réglages) **[À VÉRIFIER étape 4 dans la documentation de chaque fournisseur, ainsi que le nom du modèle gratuit le plus capable du moment : ne pas coder un nom de modèle de mémoire]** :
| Préréglage | `baseURL` | Où créer la clé |
|---|---|---|
| Gemini (défaut) | `https://generativelanguage.googleapis.com/v1beta/openai` | aistudio.google.com |
| Groq | `https://api.groq.com/openai/v1` | console.groq.com |
| Mistral | `https://api.mistral.ai/v1` | console.mistral.ai |
| Personnalisé | saisi par l'utilisateur | — |

Délai d'expiration : 60 s. Pas de streaming (`shortcut` : la réponse du chat arrive d'un bloc ; à ajouter si l'attente gêne).

### 5.5 Gestion d'erreurs
| Situation | Comportement | Message à l'utilisateur |
|---|---|---|
| Pas de réseau | Abandon silencieux de la synchro, nouvel essai au prochain déclencheur | Pastille « Hors ligne » |
| Garmin 401 | Rafraîchir, un seul nouvel essai | — |
| Rafraîchissement refusé | Effacer les jetons, état `needsLogin` | Bandeau « Reconnecte-toi à Garmin » |
| Garmin 403 | Backoff 1 h | « Garmin refuse la connexion pour le moment. Nouvel essai automatique plus tard. » |
| Garmin 427 / 429 | Backoff exponentiel | Idem, avec l'heure du prochain essai |
| Garmin 404 sur un détail | Activité en `summaryOnly` | — |
| JSON Garmin inattendu | Champ ignoré ; activité `failed` si distance ou durée manquent | — |
| Échec d'envoi d'un workout | `garminSyncState = failed`, nouvel essai à la prochaine synchro (3 au plus) | Icône d'alerte sur la séance, détail dans la fiche |
| IA 401 | — | « Clé IA refusée. Vérifie-la dans Réglages. » |
| IA 429 | Pas de nouvel essai immédiat ; `FallbackPlanner` si un plan est attendu | « Quota IA atteint. Plan généré sans IA en attendant. » |
| IA JSON invalide ou garde-fou violé | Un appel de réparation, puis `FallbackPlanner` | Rien si la réparation réussit ; sinon étiquette « sans IA » sur les séances |
| Clé IA absente | Plan par `FallbackPlanner`, chat désactivé | Carte « Ajoute une clé IA gratuite » |

Types d'erreur : `GarminError` (`needsLogin`, `rateLimited`, `blocked`, `network`, `decoding`, `http(Int)` ; l'heure du prochain essai est calculée par `SyncPolicy.nextAllowedCall` et rangée dans `SyncState`) et `LLMError` (`missingKey`, `unauthorized`, `rateLimited`, `invalidOutput`, `network`, `http(Int)`).

---

## 6. Coach IA

### 6.1 Principe : le code calcule, l'IA rédige
| Responsabilité | Qui |
|---|---|
| Phases, volume hebdomadaire cible, distance de la sortie longue, nombre de séances | Code (`MacroPlanner`) |
| Zones d'allure et de FC | Code (`PaceModel`) |
| Charge, fatigue, détection de séance manquée | Code (`LoadModel`, `WorkoutMatcher`) |
| Choix et structure des séances de la semaine dans ces bornes | IA |
| Explication de chaque séance, conversation, propositions de modification | IA |
| Validation de tout ce que l'IA produit | Code (`Guardrails`) |
| Semaine de secours si l'IA échoue | Code (`FallbackPlanner`) |

L'IA ne voit jamais l'historique brut : elle reçoit un résumé compact (moins de 2 000 jetons) calculé par le code.

### 6.2 Entrées de l'IA
**`AthleteSnapshot`** (`SnapshotBuilder`) :
```json
{
  "today": "2026-11-12",
  "athlete": { "age": 21, "sex": null, "running_since_weeks": 3, "level": "beginner",
               "injury_note": "", "current_pain": false, "fatigue_level": "normal",
               "wants_strength": true, "strength_equipment": "none" },
  "goal": { "kind": "race", "distance_km": 21.1, "date": "2027-05-16", "target_time": "2:00:00",
            "target_pace_s_per_km": 341, "weeks_left": 26,
            "predicted_time": "2:12:00", "feasibility": "ambitious" },
  "paces_s_per_km": { "recovery": [461, 514], "easy": [418, 461], "long": [418, 468],
                      "tempo": [355, 372], "intervals": [319, 340] },
  "hr_zones_bpm": [[97, 116], [116, 135], [135, 155], [155, 174], [174, 193]],
  "last_weeks": [ { "week_start": "2026-11-02", "km": 15.2, "runs": 3, "load": 210, "longest_km": 5.3 } ],
  "last_runs": [ { "date": "2026-11-10", "km": 5.0, "pace_s_per_km": 390, "avg_hr": 158,
                   "planned_kind": "easy", "effort": 6 } ],
  "load": { "acute": 210, "chronic": 180, "ratio": 1.17 },
  "recovery": { "sleep_h_avg_7d": 7.2, "hrv_status": null, "resting_hr": 58 },
  "missed_last_14d": 1
}
```
`last_weeks` : 6 semaines au plus. `last_runs` : 10 sorties au plus.

**`WeekBrief`** (cahier des charges de la semaine, calculé par le code) :
```json
{
  "week_start": "2026-11-16", "phase": "base", "is_cutback": false,
  "target_km": 16.5, "min_km": 13.2, "max_km": 17.3,
  "run_sessions": 3, "max_quality_sessions": 0,
  "long_run_km": [6.0, 7.0], "long_run_day": "2026-11-22",
  "available_days": ["2026-11-17", "2026-11-19", "2026-11-22"],
  "max_session_min": 60,
  "strength_sessions": 1, "strength_days": ["2026-11-18", "2026-11-20"],
  "allowed_kinds": ["easy", "long", "recovery", "strength"],
  "notes": ["Débutant : pas de fractionné ni de tempo avant la semaine du 2026-12-14."]
}
```

### 6.3 Calculs déterministes

**`PaceModel` — allure seuil et zones.**
1. Sortie de référence : la plus rapide des 6 dernières semaines d'au moins 3 km. À défaut, celle saisie à l'onboarding.
2. Allure seuil selon le ressenti de cette sortie (`perceivedEffort`, ou `recentRunEffort` de l'onboarding) :
   - facile (effort ≤ 4) : `seuil = allure / 1,22`
   - modéré (5 à 7) : `seuil = allure / 1,10`
   - dur (≥ 8) : temps équivalent sur 10 km par la formule de Riegel `T2 = T1 × (10 / D1)^1,06`, et `seuil = allure de ce 10 km`
   - ressenti inconnu : traiter comme modéré.
3. `thresholdPaceOverrideSPerKm` remplace le calcul s'il est renseigné.
4. Zones, en multiples de l'allure seuil (secondes par km) :

| Zone | Borne rapide | Borne lente |
|---|---|---|
| `recovery` | × 1,30 | × 1,45 |
| `easy` | × 1,18 | × 1,30 |
| `long` | × 1,18 | × 1,32 |
| `tempo` | × 1,00 | × 1,05 |
| `intervals` | × 0,90 | × 0,96 |

5. Temps prévu sur la course : `allure seuil × 1,06 × distance` pour un semi. `feasibility` : `on_track` si le temps prévu est sous l'objectif à 3 % près, `ambitious` jusqu'à 15 % au-dessus, `very_ambitious` au-delà.

Ce sont des approximations assumées, recalculées chaque semaine. Exemple de l'utilisateur de référence (5 km à 6:30/km, ressenti modéré) : seuil 5:55/km, footing entre 6:58 et 7:41/km.

**Zones FC.** Zones Garmin de l'utilisateur si l'endpoint les fournit. Sinon `hrMax` saisi, ou estimé par `208 − 0,7 × âge`, et zones à 50, 60, 70, 80, 90, 100 % de `hrMax`.

**`LoadModel`.**
- Charge d'une sortie (`edwardsLoad`) : `Σ minutes en zone i × i` pour i de 1 à 5. Sans données de zones : `durée en minutes × 2`.
- Charge aiguë : somme sur 7 jours. Charge chronique : moyenne hebdomadaire sur 28 jours. `ratio = aiguë / chronique` (indéfini avant 3 semaines de données).
- `ratio > 1,3` : note de prudence dans `WeekBrief`. `ratio > 1,5` : `max_km` plafonné au volume de la semaine précédente.

**`MacroPlanner`.** Entrées : `V0` (moyenne des km des 3 dernières semaines complètes ; à défaut `séances par semaine × distance de la sortie de référence`), `L0` (plus longue sortie des 3 dernières semaines), `N` (nombre de semaines jusqu'à la semaine de course incluse), `D` (distance de course en km), jours disponibles, `beginner` (court depuis moins de 6 mois).
- Volume de pointe : `Vpeak = clamp(1,8 × D, min: V0, max: 45)` → 38 km pour un semi.
- Phases, depuis la fin : `race` = dernière semaine ; `taper` = l'avant-dernière ; `peak` = les 4 précédentes ; le reste se partage entre `base` puis `build` à parts égales, avec au moins 6 semaines de `base` pour un débutant (4 sinon).
- Progression hebdomadaire : `V(n) = min(Vpeak, max(V(n−1) × 1,08, V(n−1) + 1,5))`. Une semaine sur quatre est allégée : `0,75 × V(n−1)` ; la semaine suivante repart de la valeur d'avant l'allègement.
- Affûtage : semaine `taper` = `0,70 × Vpeak` ; semaine `race` = `0,40 × Vpeak`, course non comprise.
- Sortie longue : première valeur `max(L0, 0,35 × V)` ; + 1 km par semaine ; − 2 km en semaine allégée ; plafond `min(0,9 × D, 0,45 × V)` ; semaine `taper` : 60 % du maximum atteint ; semaine `race` : aucune hors course.
- Séances de course par semaine : `min(jours disponibles, 3 en base, 4 en build et peak)`, jamais moins de 2.
- Séances de qualité (`tempo`, `intervals`) : `base` = 0 pour un débutant, 1 sinon ; `build` = 1 ; `peak` = 2 s'il y a au moins 4 séances, sinon 1 ; `taper` = 1 ; semaine allégée = 1 au plus.
- Renforcement : si `wantsStrength`, 1 séance par semaine en `base`, 2 en `build`, 1 ensuite, placée un jour sans séance dure.
- Sans course (objectif `fitness`) : cycles de 12 semaines visant `1,5 × V0`.
- Si les semaines manquent pour atteindre `Vpeak` : le plan s'arrête où la règle de progression le mène, et `feasibility` le signale. La règle de progression n'est jamais assouplie.
- Recalcul : chaque dimanche à partir du volume **réellement couru**, pas du volume prévu.

### 6.4 Garde-fous (`Guardrails.validate(week:brief:snapshot:) -> [Violation]`)
Chaque règle a un identifiant, un test unitaire, et un message en français utilisé dans l'appel de réparation.

| Id | Règle |
|---|---|
| G1 | Km de course de la semaine ≤ `brief.max_km` |
| G2 | Km de la semaine ≤ `max(1,10 × Vmax3, Vmax3 + 2)`, où `Vmax3` est le plus gros volume réellement couru des 3 dernières semaines |
| G3 | Sortie longue ≤ borne haute de `brief.long_run_km`, ≤ plus longue sortie des 3 dernières semaines + 2 km, ≤ 50 % du volume de la semaine |
| G4 | Nombre de séances `tempo` + `intervals` ≤ `brief.max_quality_sessions` |
| G5 | Jamais deux jours durs consécutifs (durs : `tempo`, `intervals`, `long`, `race`) |
| G6 | Au moins 1 jour sans aucune séance par semaine, 2 pour un débutant |
| G7 | Courses uniquement les jours de `brief.available_days` ; sortie longue le `brief.long_run_day` ; une seule course par jour |
| G8 | Durée estimée ≤ `brief.max_session_min` (la sortie longue peut aller jusqu'à 1,5 fois cette durée) |
| G9 | Toute cible d'allure tient dans la zone du `kind`, à 5 s/km près ; aucune allure plus rapide que la borne rapide de `intervals` |
| G10 | Distance cumulée à allure `tempo` ou `intervals` dans une séance ≤ `max(2 km, 10 % du volume cible)` |
| G11 | `current_pain` vrai : uniquement `recovery` de 30 min au plus, ou repos ; `fatigue_level = high` : aucune séance de qualité, volume ≤ 80 % de `target_km` |
| G12 | Structure : `tempo` et `intervals` ont un échauffement et un retour au calme d'au moins 5 min ; `repeat` entre 1 et 20 ; valeurs positives ; dates dans la semaine ; `kind` dans `brief.allowed_kinds` |
| G13 | Renforcement : `brief.strength_sessions` au plus, 40 min au plus, pas la veille d'une séance dure |

Le km d'une séance est recalculé par le code à partir des blocs (distance, ou durée × allure médiane de la cible, ou allure `easy` sans cible). `estimated_distance_km` fourni par l'IA n'est jamais cru.

`FallbackPlanner` : gabarits déterministes par phase (footings à l'allure `easy`, sortie longue le bon jour, une séance de qualité gabarit quand le brief l'autorise), qui passent tous les garde-fous par construction. Les séances portent `source = fallback`.

### 6.5 Prompts (`Prompts.swift`)
Les prompts sont en français, comme les réponses attendues.

**Prompt système commun (`Prompts.systemBase`)**
```
Tu es le coach de course à pied personnel d'un seul athlète. Tu écris en français, tu le tutoies,
avec un ton direct, encourageant et sans jargon inutile.

TON RÔLE
- Construire des séances adaptées à CET athlète à partir des données fournies en JSON.
- Expliquer en une ou deux phrases pourquoi chaque séance est là.
- Adapter le plan quand il te le demande ou quand ses données le justifient.

CE QUE TU NE FAIS JAMAIS
- Tu n'inventes aucune donnée. Si une information manque, tu le dis ou tu choisis l'option la plus prudente.
- Tu ne poses aucun diagnostic médical et tu ne recommandes aucun médicament.
- Tu ne dépasses jamais les bornes du bloc WEEK_BRIEF : volume, nombre de séances, sortie longue,
  jours disponibles, types de séance autorisés. Ces bornes sont calculées pour sa sécurité.
- Tu n'utilises que les allures du bloc paces_s_per_km. Tu ne calcules pas d'allures toi-même.

SÉCURITÉ
- Douleur (articulation, tendon, os, poitrine), malaise, essoufflement anormal : tu dis d'arrêter la
  séance, tu remplaces par du repos, et tu recommandes de consulter un médecin ou un kiné avant de reprendre.
- Fatigue élevée, mauvais sommeil, maladie : tu allèges. En cas de doute, tu allèges.
- Progression : jamais d'augmentation brutale. Une séance manquée ne se rattrape pas en doublant la suivante.
- Débutant : priorité à la régularité et aux footings faciles. La vitesse vient après l'endurance.
- Si l'objectif paraît hors de portée au vu des données, tu le dis honnêtement et tu proposes un
  objectif intermédiaire, sans décourager.

RÈGLES DE CONSTRUCTION DES SÉANCES
- Environ 80 % du temps de course à allure facile.
- easy / recovery : un seul bloc, cible d'allure easy ou recovery, ou zone de FC 2.
- long : allure long, continue. Pas d'accélérations avant la phase build.
- tempo : échauffement 10 à 15 min, 2 à 4 répétitions de 5 à 12 min à allure tempo avec 2 à 3 min
  de récupération, retour au calme 10 min.
- intervals : échauffement 10 à 15 min, répétitions de 200 m à 1000 m à allure intervals avec une
  récupération au moins égale à la moitié du temps d'effort, retour au calme 10 min.
- strength : 4 à 6 exercices du catalogue, orientés coureur (fessiers, mollets, gainage), 20 à 35 min.
- Jamais deux séances dures deux jours de suite (dures : tempo, intervals, long).

FORMAT
- Tu réponds UNIQUEMENT par un objet JSON conforme au schéma fourni. Aucun texte autour.
- Allures en secondes par kilomètre : min_s_per_km est la borne rapide, max_s_per_km la borne lente.
- Durées en secondes, distances en mètres.
- title : 40 caractères au plus. rationale : 240 caractères au plus, concret, lié à ses données.
```

**Génération de la semaine (`Prompts.weekPlan`)** — message utilisateur :
```
ATHLETE_SNAPSHOT:
<JSON>

WEEK_BRIEF:
<JSON>

PLAN_DES_14_DERNIERS_JOURS (prévu et réalisé):
<JSON compact : date, kind, statut, km réalisés>

Construis les séances de la semaine qui commence le <week_start>.
- Exactement <run_sessions> séances de course, uniquement aux dates de available_days.
- La sortie longue le <long_run_day>, entre <long_run_km[0]> et <long_run_km[1]> km.
- Total de course entre <min_km> et <max_km> km.
- <strength_sessions> séance(s) de renforcement, aux dates de strength_days.
- Varie par rapport à la semaine précédente quand c'est possible.
- summary : deux phrases sur l'objectif de la semaine.
```

**Réparation (`Prompts.repair`)** — envoyé une seule fois, à la suite de la réponse fautive :
```
Ta réponse précédente ne respecte pas ces règles :
<liste des violations, une par ligne, avec la séance concernée>

Renvoie l'objet JSON complet corrigé. Ne change que ce qui est nécessaire pour respecter les règles.
```

**Chat (`Prompts.chat`)** — ajouté au prompt système commun :
```
MODE CONVERSATION
- Tu réponds dans "reply", en 2 à 5 phrases, sauf si on te demande plus de détail.
- Si l'athlète demande de modifier le plan, ou si ce qu'il dit le justifie (fatigue, douleur,
  indisponibilité), propose les changements dans "actions". Sinon "actions" est vide.
- Chaque séance proposée respecte WEEK_BRIEF et les règles de construction.
- Tu ne modifies que les séances à venir.
- S'il déclare une douleur : safety = "pain", profile_patch.current_pain = true, tu remplaces les
  séances dures à venir par du repos ou de la récupération, et tu recommandes de consulter.
- S'il décrit un symptôme inquiétant (douleur thoracique, malaise, vertiges) : safety = "medical",
  tu lui dis d'arrêter et de consulter rapidement. Aucune séance proposée.
- S'il dit aller mieux : profile_patch.current_pain = false.
- Les questions sans rapport avec la course, la forme ou le plan : tu recentres poliment.
- N'annonce jamais qu'un changement est appliqué : il le sera seulement après sa confirmation.
```
Message utilisateur du chat : `ATHLETE_SNAPSHOT`, `WEEK_BRIEF` de la semaine en cours et de la suivante, les séances des 14 prochains jours, les 12 derniers messages de la conversation, puis le nouveau message.

### 6.6 Application des actions du chat
1. Décodage de `ChatResponse`. `reply` est affiché immédiatement.
2. `profile_patch` est appliqué tout de suite (une douleur déclarée doit agir sans attendre une confirmation).
3. Les `actions` sont simulées sur une copie de la semaine, puis `Guardrails.validate`. Violation : un appel de réparation ; si l'échec persiste, les actions sont abandonnées et le message « Je ne peux pas faire ce changement sans dépasser tes limites de progression » est ajouté.
4. Actions valides : `ConfirmCard` sous la bulle (résumé avant/après, boutons Appliquer et Ignorer).
5. Appliquer : écriture en base (`source = ai`, `garminSyncState = needsUpdate`), puis F3.
6. `safety` différent de `none` : bandeau permanent en haut de l'écran Aujourd'hui tant que `currentPain` est vrai.

### 6.7 Choix du fournisseur IA
- **Apple Intelligence (modèle embarqué, framework Foundation Models) n'est pas retenu pour le coach.** Le modèle est petit et sa fenêtre de contexte est de 4 096 jetons sur iOS 26 (8 192 sur certains appareils sous iOS 27, selon des sources secondaires qui se contredisent). C'est trop peu pour tenir le profil, l'historique, le plan et la conversation, et trop peu fiable pour raisonner sur plusieurs semaines. Il ne peut pas non plus être testé sans appareil ni Mac. Usage futur possible : reformuler une explication hors ligne.
- **Retenu : API cloud gratuite**, clé personnelle de l'utilisateur, préréglage Gemini par défaut (§5.4). Groq et Mistral en alternatives. Le volume d'usage (quelques générations par semaine, quelques dizaines de messages) tient largement dans les quotas gratuits annoncés.
- Données et entraînement des modèles, vérifié le 2026-11-13 :
  - **Gemini** (conditions en vigueur au 23 mars 2026, lues sur aistudio.google.com/docs/terms) : dans l'EEE, les règles de données de l'offre payante s'appliquent aussi au quota gratuit (pas d'usage des requêtes pour améliorer les produits). Mais les mêmes conditions disent : « You may use only Paid Services when making API Clients available to users in the European Economic Area », l'usage est réservé aux développeurs « for professional or business purposes, not for consumer use », et il faut avoir 18 ans. Une app personnelle avec sa propre clé est une zone grise : **à soumettre à l'utilisateur, ne pas la présenter comme conforme**.
  - **Groq** : pas de conservation des requêtes par défaut, hors journaux de fiabilité et d'abus (jusqu'à 30 jours, désactivables par « Zero Data Retention ») ; pas d'entraînement sans accord, d'après son contrat de service (lu dans une source secondaire, pas dans le texte même).
  - **Mistral** (offre gratuite « Experiment ») : requêtes utilisables pour l'entraînement par défaut, refus possible dans la console (menu Privacy).
  L'écran Réglages → IA affiche ce point en clair.

---

## 7. Design system et écrans

### 7.1 Identité
Sombre d'abord, calme, une seule couleur vive. Les chiffres sont les héros : gros, arrondis, peu de texte autour. Une information principale par écran.

**Couleurs** (définies en code dans `DesignSystem/Tokens.swift`, chaque couleur a une variante claire et une sombre ; accès par `Color.rc.<nom>`)
| Jeton | Sombre | Clair | Usage |
|---|---|---|---|
| `background` | `#0B0D10` | `#F4F5F7` | Fond d'écran |
| `surface` | `#15181D` | `#FFFFFF` | Cartes |
| `surfaceRaised` | `#1E2228` | `#EEF0F3` | Cartes dans une carte, champs |
| `separator` | `#2A2F37` | `#E3E5EA` | Filets |
| `textPrimary` | `#F5F7FA` | `#0B0D10` | |
| `textSecondary` | `#9AA3AF` | `#5B6470` | |
| `accent` | `#FF6A1F` | `#FF6A1F` | Aplats : bouton principal, anneau, point du replay. Orange, choisi par l'utilisateur le 2026-11-12 (il a refusé le vert fluo d'origine). |
| `onAccent` | `#0B0D10` | `#0B0D10` | Texte sur aplat `accent` (sombre : le blanc sur cet orange n'a que 2,9:1 de contraste) |
| `accentText` | `#FF6A1F` | `#C2410C` | Texte ou icône en couleur d'accent (contraste en clair) |
| `danger` | `#F43F5E` | `#D92D4B` | Erreurs, alerte douleur |
| `warning` | `#FACC15` | `#A16207` | Jaune, pour ne pas se confondre avec l'accent |

Types de séance (`WorkoutKind.color`) : `easy` `#34D399` · `long` `#60A5FA` · `tempo` `#F59E0B` · `intervals` `#F43F5E` · `recovery` `#2DD4BF` · `strength` `#A78BFA` · `race` `#FF6A1F`.
Zones FC 1 à 5 : `#8B95A5`, `#3B82F6`, `#10B981`, `#F59E0B`, `#EF4444` (familles de couleur de Garmin ; toujours accompagnées de « Z1 » à « Z5 » et du nom de la zone).
La couleur n'est jamais le seul porteur d'information : chaque type a aussi une icône et un libellé.

**Typographie** (`Typography.swift`) : police système uniquement, styles de texte dynamiques (Dynamic Type), jamais de taille fixe.
| Style | Définition | Usage |
|---|---|---|
| `heroNumber` | `.system(.largeTitle, design: .rounded, weight: .bold)` + `.monospacedDigit()` | Le chiffre principal d'un écran |
| `statNumber` | `.system(.title2, design: .rounded, weight: .semibold)` + `.monospacedDigit()` | Tuiles de stats |
| `title` | `.title2.weight(.bold)` | Titres d'écran et de carte |
| `body` | `.body` | Texte courant |
| `label` | `.caption.weight(.medium)`, majuscules, `textSecondary` | Libellé d'une stat |

**Formes et espacements** (`Tokens.swift`) : échelle 4 / 8 / 12 / 16 / 24 / 32. Marges d'écran 16. Cartes : rayon 24 (`.continuous`), marge intérieure 16 ; éléments internes : rayon 14. Zones tactiles d'au moins 44 pt. Pas d'ombres en sombre ; ombre légère en clair.

**Icônes** : SF Symbols uniquement. `easy` `figure.run` · `long` `road.lanes` · `tempo` `speedometer` · `intervals` `bolt.fill` · `recovery` `leaf.fill` · `strength` `dumbbell.fill` · `race` `flag.checkered`.

**Mouvement** : `Animation.rcStandard = .spring(response: 0.35, dampingFraction: 0.85)`. Chiffres qui changent : `.contentTransition(.numericText())`. Respect de « Réduire les animations » (le replay reste, les transitions décoratives disparaissent).

**Haptique** (directement par `.sensoryFeedback` dans les vues, pas de fichier dédié) : `selection` pour le changement d'onglet de période et le défilement de la barre du replay ; `success` pour la fin de synchro manuelle et l'application d'un plan ; `warning` pour une erreur. Rien d'autre.

**Accessibilité** : chaque tuile de stat a un libellé VoiceOver complet (« Allure moyenne, 6 minutes 30 par kilomètre »). Les graphiques ont un résumé textuel. Les mises en page tiennent jusqu'à la taille de texte `xxxLarge` (les grilles de tuiles passent sur une colonne).

### 7.2 Composants (`DesignSystem/Components`)
| Composant | Rôle |
|---|---|
| `StatTile(label:value:unit:icon:)` | Tuile carrée : libellé, gros chiffre, unité |
| `HeroWorkoutCard(workout:)` | Carte de la séance du jour : bandeau de couleur du type, titre, durée et distance, aperçu des étapes en barres proportionnelles, explication |
| `WorkoutBadge(kind:)` | Pastille icône + libellé du type |
| `WeekStrip(days:)` | 7 points : prévu (contour), fait (plein), manqué (barré), aujourd'hui (anneau accent) |
| `RingProgress(value:)` | Anneau de progression (volume de la semaine) |
| `ZoneBar(seconds:)` | Barre horizontale empilée des 5 zones FC |
| `MiniChart(points:)` | Courbe sans axes pour les cartes |
| `StepRow(step:)` | Ligne d'étape de séance : icône, durée ou distance, cible |
| `ChatBubble(message:)` | Bulle utilisateur (accent) ou coach (surface) |
| `ConfirmCard(actions:)` | Proposition de changement : avant, après, Appliquer / Ignorer |
| `PrimaryButton(title:action:)` | Bouton plein accent, largeur complète, hauteur 54 |
| `SectionHeader(title:action:)` | Titre de section + lien optionnel |
| `SyncPill(state:)` | Pastille d'état de synchro : à jour, en cours, hors ligne, erreur |
| `EmptyState(icon:title:message:action:)` | État vide |

### 7.3 Navigation
`TabView` à 5 onglets, dans l'ordre : **Aujourd'hui** (`sun.max.fill`), **Plan** (`calendar`), **Activités** (`figure.run`), **Coach** (`bubble.left.and.bubble.right.fill`), **Progrès** (`chart.line.uptrend.xyaxis`).
- Réglages : bouton avatar en haut à droite d'Aujourd'hui, ouvert en feuille (action rare).
- Détail d'une sortie et détail d'une séance planifiée : poussés dans la pile de navigation de l'onglet courant.
- Replay : `fullScreenCover` depuis le détail d'une sortie.
- Connexion Garmin : feuille plein écran.
- Onboarding : remplace `RootView` tant que `medicalDisclaimerAcceptedAt` est nul.
- Les actions principales sont dans le tiers bas de l'écran (pouce, écran de 6,7").

### 7.4 Écrans
**Onboarding** (une question par page, barre de progression, bouton Continuer en bas)
1. Bienvenue : nom de l'app, une phrase, Commencer.
2. Toi : prénom, date de naissance ; sexe, taille et poids facultatifs.
3. Ton niveau : depuis quand tu cours ; séances par semaine ; une sortie récente (distance, durée) et son ressenti (facile / modéré / dur).
4. Ton objectif : course (distance prédéfinie ou libre, date, temps visé) ou « progresser sans échéance ».
5. Tes disponibilités : 7 pastilles de jours, jour de la sortie longue, durée maximale d'une séance.
6. Ta santé : blessures ou antécédents (texte libre, facultatif), douleur actuelle (oui / non), puis l'avertissement médical à cocher : « Cette app ne remplace pas un avis médical. En cas de douleur ou de doute, consulte. »
7. Renforcement : oui / non ; matériel (aucun, haltères, salle).
8. Garmin : Connecter mon compte (ouvre la connexion) ou Plus tard. Le risque de l'accès non officiel est écrit en une phrase.
9. Coach IA : choix du fournisseur, lien vers la page de création de clé, champ pour coller la clé, ou Plus tard.
10. Génération du premier plan : animation, puis arrivée sur Aujourd'hui.

Tout est modifiable ensuite dans Réglages → Profil ; une modification qui touche le plan propose de le régénérer.

**Aujourd'hui** — information principale : la séance du jour.
- En-tête : date, `SyncPill`, avatar.
- `HeroWorkoutCard` de la séance du jour. Jour de repos : carte « Repos » avec la prochaine séance. Séance déjà faite : carte « Fait » avec les stats réalisées et un bouton Revoir.
- Sous la carte : état d'envoi sur la montre (« Sur ta montre » / « En attente d'envoi » / « Échec »).
- Semaine : `WeekStrip` et `RingProgress` (km faits sur km prévus).
- Dernière sortie : carte compacte avec mini-carte du tracé, distance, allure, accès au détail.
- Bandeau d'alerte en haut si `currentPain` est vrai ou si Garmin demande une reconnexion.
- Tirer pour rafraîchir : synchro.

**Plan** — information principale : la semaine en cours.
- Sélecteur Semaine / Mois.
- Semaine : liste des 7 jours ; chaque jour montre la séance (pastille de type, titre, durée) et son état. En tête : volume cible de la semaine et phase.
- Mois : grille de calendrier, un point coloré par séance (plein = fait), toucher un jour ouvre son détail en bas.
- Appui long sur une séance : Déplacer, Marquer comme passée, Demander au coach.
- Détail d'une séance planifiée : `HeroWorkoutCard` en grand, liste des `StepRow` (ou des exercices pour le renfo), explication du coach, état d'envoi Garmin, bouton « En parler au coach ».

**Détail d'une sortie** — information principale : distance et allure.
- En-tête : mini-carte du tracé (touchable), gros bouton **Rejouer** superposé.
- Chiffre héros : distance ; dessous : durée et allure moyenne.
- Grille de `StatTile` : FC moyenne, cadence, dénivelé, calories, température, VO2max, charge.
- `ZoneBreakdown` des zones FC : une barre par zone (Z5 en haut), nom, temps, pourcentage, zone dominante en tête.
- Trois courbes `TrackChart` le long de la sortie (axe en km) : allure avec moyenne en pointillé, FC avec moyenne, altitude.
- Splits : barres horizontales par km, longueur proportionnelle à l'allure, FC en regard.
- Séance prévue correspondante et écart (« Prévu : footing 5 km · Fait : 5,2 km »).
- Ressenti (1 à 10) et note, modifiables.

**Replay** — plein écran, information principale : le point qui avance.
- Carte en fond sur tout l'écran : satellite **à plat** (pas de relief 3D, refusé par l'utilisateur le 2026-11-12 : il masquait le tracé) ; tracé complet en blanc translucide, partie parcourue en accent, point accent.
- La carte **tourne avec le coureur** : le cap de la caméra suit le sens de la course (`Track.heading(at:)`), le coureur avance toujours vers le haut de l'écran. Distance 600 m. L'inclinaison de 45° demandée est ignorée par `.imagery(elevation: .flat)` : la vue est du dessus. La vue inclinée voulue par l'utilisateur est l'objet de l'étape 3 (§8).
- Haut : bouton Fermer ; bouton jumelles = vue de rue d'Apple (Look Around) au point courant, message si Apple n'a pas d'image à cet endroit ; bascule satellite / plan.
- Une vue « Street View » continue qui suit le coureur n'est pas faisable : Google Street View exige un SDK tiers et une clé payante, et Look Around ne fournit que des images fixes au bord des routes couvertes.
- Bandeau flottant bas, en verre dépoli : 6 stats qui défilent (allure, FC, cadence, altitude, distance, temps), en `statNumber`.
- Courbe sous les stats : sélecteur allure / FC / altitude, curseur vertical à la position courante.
- Contrôles tout en bas : lecture / pause (gros bouton central), vitesse ×1 / ×2 / ×4, barre de progression à faire glisser.
- Toucher la carte masque ou affiche le bandeau.
- Comportement détaillé : §8, étape 3.

**Coach** — information principale : la conversation.
- Liste de `ChatBubble`, `ConfirmCard` sous les réponses qui proposent un changement.
- Suggestions au-dessus du champ quand la conversation est vide : « Je suis fatigué aujourd'hui », « Déplace ma séance de demain », « Explique-moi ma semaine », « Ajoute du renfo ».
- Champ de saisie collé au clavier, bouton d'envoi accent.
- Sans clé IA : `EmptyState` avec le bouton « Ajouter une clé gratuite ».

**Progrès** — information principale : la distance à l'objectif.
- Carte objectif : nom de la course, jours restants, temps visé, temps estimé aujourd'hui, jauge.
- Volume hebdomadaire : barres des 12 dernières semaines, ligne du volume prévu.
- Tendance d'allure : allure moyenne des footings, par semaine.
- Charge : aiguë et chronique, zone de prudence colorée.
- Répartition du temps par zone FC sur 4 semaines (`ZoneBreakdown`).

**Activités** (onglet, ajouté le 2026-11-13 : l'utilisateur voulait un accès direct) — information principale : la liste.
- Liste chronologique de toutes les activités, course et renfo (`RunListView`, lignes `RunRow`). Une activité sans distance affiche sa durée et sa FC moyenne.
- Toucher une ligne ouvre `RunDetailView` ; sans tracé, ni carte ni bouton Rejouer.

**Réglages** (feuille)
- Profil et objectif (tous les champs de l'onboarding).
- Garmin : état de connexion, dernière synchro, Se connecter / Se déconnecter, Synchroniser maintenant, Nettoyer les séances envoyées, Diagnostic.
- IA : fournisseur, modèle, clé, bouton Tester, rappel sur l'usage des données.
- Données : Supprimer toutes les données locales.
- À propos : version, date d'expiration de la signature si elle est lisible, avertissement médical.

---

## 8. Plan de développement

Règles communes à toutes les étapes :
- Lire `ARCHITECTURE.md` et `CLAUDE.md` avant de commencer une étape.
- Lever les **[À VÉRIFIER étape N]** de l'étape avant d'écrire le code qui en dépend ; corriger ce document si un fait s'avère faux.
- Une étape est finie quand ses critères de validation sont vérifiés : CI verte, captures relues, et test sur l'iPhone par l'utilisateur.
- Chaque étape se termine par une note à l'utilisateur : ce qu'il doit installer, ce qu'il doit vérifier, ce qui dépend de Garmin ou d'Apple.

### Étape 1 — Squelette, design system, données factices
| | |
|---|---|
| Tâches | 1. Dépôt GitHub, `.gitignore`, `project.yml`, `Package.swift`. 2. Workflows `core.yml` et `ios.yml`. 3. `DesignSystem` complet. 4. Entités SwiftData et `MockData.seed()` (8 semaines de sorties factices avec tracés synthétiques, un plan de 2 semaines, une conversation). 5. Tous les écrans du §7.4 branchés sur les données factices, navigation complète. 6. `ScreenshotTests` : un test par écran, clair et sombre. 7. Première installation par Sideloadly. |
| Fichiers | Toute l'arborescence du §3.1, sauf le contenu de `Core/Garmin`, `Core/Coach` et `Core/Training` (fichiers créés à leurs étapes). |
| Validation | `core.yml` et `ios.yml` verts. Captures de tous les écrans relues en clair et en sombre. IPA installée sur l'iPhone 16 Plus ; l'utilisateur parcourt tous les écrans et valide le design. |
| Risques | Image du runner macOS et version de Xcode inconnues ; quota de minutes macOS ; blocage du sideloading gratuit par Apple. |

### Étape 2 — Connexion Garmin et import
> Ajout du 2026-11-13 (demande de l'utilisateur) : importer **toutes** les activités, pas seulement la course. Une séance de renfo (`activityType` = `strength_training`) est un `Run` sans distance, sans tracé et sans splits ; l'onglet Activités et `RunDetailView` l'affichent déjà (durée en chiffre principal, FC, calories, zones, exercices de la séance prévue liée). Les séries réellement faites (exercice, répétitions, charge) viendraient de `/activity-service/activity/{id}/exerciseSets` **[À VÉRIFIER étape 2]** ; sans elles, on montre les exercices prévus.
| | |
|---|---|
| Tâches | **2.0 Validation préalable sur le PC (avant tout code Swift)** : avec Python 3.12 et `pip install garminconnect curl_cffi`, un script de 30 lignes se connecte au compte de l'utilisateur, liste 3 activités, crée un workout de test, le planifie à demain, vérifie qu'il arrive sur la Forerunner 745 après synchro, puis le supprime. Si cette validation échoue, s'arrêter et revoir §1 avec l'utilisateur. Profiter de cette session pour enregistrer des réponses JSON réelles hors du dépôt, et en tirer des fixtures **synthétiques** (§9.4). 2.1 `GarminIdentity`, `GarminAuth` (échange, rafraîchissement à vol unique), `KeychainTokenStore`. 2.2 `GarminLoginView` et ses trois crochets de capture. 2.3 `GarminAPI`, DTO, conversion des détails en `Track`. 2.4 `SyncEngine` (backfill, incrémental, backoff), `BackgroundSync`. 2.5 Branchement des écrans sur les données réelles ; le mode factice reste disponible. |
| Fichiers | `Core/Garmin/*`, `Core/Support/*`, `App/Services/*`, `App/Features/GarminLogin/*`, `App/Features/Settings/GarminSettingsView.swift`, `App/Data/Stores/RunStore.swift`. |
| Validation | Tests Core : décodage des fixtures, colonnes résolues par clé, rafraîchissement concurrent = un seul appel, backoff. Sur l'iPhone : connexion réussie, sorties des 90 derniers jours importées avec tracé et splits, nouvelle sortie visible après ouverture de l'app, session conservée après redémarrage. |
| Risques | Capture du ticket dans le WKWebView (repli §5.1.2 bis) ; jeu d'en-têtes `ios` refusé (repli `android`) ; noms de champs JSON différents de ceux du §5.2 ; blocage 429 pendant les essais (respecter §5.1.6) ; MFA. |
| État (2026-11-13) | 2.0 réussie (§1.3). 2.1 à 2.5 codées : Core (`GarminAuth`, `GarminAPI`, `GarminDTO`, `ImportedActivity`, `ImportedDailyMetric`, `Track(details:)`, `Track.kmSplits()`, `SyncPolicy`, 29 tests verts sous Linux) ; app (`KeychainTokenStore`, `URLSessionHTTPClient`, `SyncEngine`, `BackgroundSync`, `GarminLoginView`, section Garmin et Diagnostic dans `SettingsView`, onboarding enregistré, états vides). Écarts : pas de `GarminSettingsView` ni de `RunStore` séparés (la section tient dans `SettingsView`, les requêtes dans `SyncEngine`). En attente : connexion et import vérifiés sur l'iPhone. |

### Étape 3 — Replay vivant
> Réécrite le 2026-11-13 à la demande de l'utilisateur : « rendre vivant le suivi du trajet, avec un zoom au début pour rejoindre le point, une vue pas perpendiculaire au sol », et toute idée qui rend le replay nettement meilleur. C'est la fonction qu'il regarde le plus : la soigner passe avant les mini-cartes.

**Point de départ (maquette de l'étape 1, `App/Features/Replay/ReplayView.swift`).** Déjà en place et à conserver : carte qui tourne avec le coureur, position et cap interpolés à chaque image (`Track.pose(at:)`, testé), horloge calée sur l'écran (`TimelineView(.animation)`), lecture à 30 fois le temps réel, vitesses ×1 / ×2 / ×4, point du coureur en vue fixe par-dessus la carte, courbe figée avec curseur superposé, bouton vue de rue (Look Around), bascule satellite / plan.

**Ce que l'utilisateur a refusé, à ne pas refaire :**
- Le relief 3D tel quel : le tracé disparaissait sous les arbres et les bâtiments.
- Un suivi saccadé : tout objet de la carte mis à jour à chaque image (point, tracé) saccadait. Seule la caméra bouge à chaque image.
- Une vue perpendiculaire au sol : c'est l'état actuel, voir la contrainte ci-dessous.

**Contrainte centrale : inclinaison contre lisibilité du tracé.** Constats de la CI (simulateur iOS 26.5), à confirmer sur l'iPhone :
- `.imagery(elevation: .flat)` **ignore l'inclinaison** : la capture est vue du dessus malgré `pitch: 45`.
- `.imagery(elevation: .realistic)` et `.hybrid(elevation: .realistic)` s'inclinent, mais les arbres et bâtiments 3D recouvrent tout ce qui est posé au sol.
- `.standard` incliné affiche des arbres 3D stylisés qui recouvrent aussi le tracé, moins densément.

La solution visée : carte inclinée en relief réaliste, et **tracé dessiné par-dessus la carte, en coordonnées d'écran**, donc jamais masqué. `MapReader` donne un `MapProxy` ; `proxy.convert(coordonnée, to: .local)` projette un point du tracé en point d'écran ; un `Canvas` SwiftUI trace le chemin à chaque image. Le point du coureur est déjà dessiné ainsi. **[À VÉRIFIER étape 3, tâche 3.0]** : que `convert` suit bien la perspective et le relief (pas de décalage du tracé en côte), et que 150 points projetés par image tiennent à 60 images par seconde.

| | |
|---|---|
| **3.0 Prototype à faire valider d'abord** | Vue inclinée (60°) en `.hybrid(elevation: .realistic)`, tracé et point en surimpression d'écran, lecture simple. Un seul IPA, une seule question à l'utilisateur : « le tracé reste-t-il visible et collé au chemin, et est-ce fluide ? ». Si non : plan B `MKMapView` dans un `UIViewRepresentable` (caméra pilotée par `CADisplayLink`), puis plan C vue du dessus actuelle, que l'on garde de toute façon comme mode « à plat ». Ne rien construire d'autre avant ce verdict. |
| **3.1 Réalisateur de caméra (Core)** | `Core/Replay/ReplayDirector.swift`, pur et testé : (tracé, temps d'activité, écart de temps) → `CameraState` (centre, distance, cap, inclinaison) + position du coureur. Règles : cap visé = direction d'un point 100 m plus loin sur le tracé ; lissage exponentiel du cap par le plus court chemin angulaire (constante de temps 0,6 s : la caméra accompagne le virage avec un léger retard) ; centre de la caméra 80 m devant le coureur pour qu'il soit dans le tiers bas de l'écran et que l'on voie la route à venir ; distance selon la vitesse (350 m à l'arrêt, 700 m à l'allure la plus rapide de la sortie, lissée sur 2 s) ; inclinaison 62° en ligne droite, 48° dans les virages serrés (selon la courbure). `ReplayClock` : temps d'activité = temps réel × échelle × multiplicateur ; l'échelle est choisie pour qu'une sortie dure 60 à 90 s en ×1 ; le point suit les horodatages réels (`Track.t`, recherche dichotomique), donc il ralentit et accélère comme le coureur. |
| **3.2 Entrée et sortie** | Ouverture : vue d'ensemble du tracé entier, du dessus, nord en haut (0,8 s), puis descente animée de 2,5 s vers le départ : zoom, inclinaison et rotation ensemble, jusqu'à la caméra de suivi ; la lecture démarre seule à l'arrivée. `mapCameraKeyframeAnimator` (iOS 17) ou `withAnimation` sur `MapCameraPosition` **[À VÉRIFIER étape 3]**. Fin : remontée symétrique vers la vue d'ensemble, tracé entièrement coloré, carte de bilan (distance, durée, allure, meilleur kilomètre), boutons Revoir et Fermer. Pendant ces deux séquences le coureur n'est pas au centre de l'écran : sa position vient de `proxy.convert`, comme en 3.0. |
| **3.3 Tracé et coureur vivants** | Partie parcourue colorée par zone cardiaque (couleurs `Color.rc.zone`), reste en blanc translucide. Queue de comète : les 15 dernières secondes plus épaisses, qui s'estompent. Coureur : chevron orienté vers le haut plutôt qu'un disque, halo qui bat au rythme de la fréquence cardiaque du moment et prend la couleur de sa zone. Drapeaux de départ et d'arrivée. Bornes kilométriques : à chaque kilomètre franchi, une bulle « km 3 · 6:19 » apparaît 2 s, avec un retour haptique léger. Temps forts annoncés au passage par une bulle : kilomètre le plus rapide, fréquence cardiaque maximale, point culminant. |
| **3.4 Bandeau et navigation dans la sortie** | Le bandeau actuel couvre 40 % de l'écran : pendant la lecture il se réduit à une ligne (allure, FC, distance, temps) ; toucher la carte l'agrandit ou le réduit. Chiffres rafraîchis 4 fois par seconde au plus, avec `.contentTransition(.numericText())`. La barre de progression devient le profil d'altitude de la sortie, teinté par zone cardiaque : on y glisse le doigt pour se déplacer. Saut de plus de 300 m : la caméra recule puis replonge (0,6 s) au lieu de se téléporter. En pause : la caméra tourne lentement autour du coureur (6° par seconde), et une vignette de vue de rue (`LookAroundPreview`) apparaît dans un coin si Apple a une image à cet endroit ; une seule requête par pause. |
| **3.5 Options et accessibilité** | Bascule de vue : inclinée (défaut), à plat du dessus, plan. Réglage « Réduire les animations » d'iOS actif : pas de séquence d'entrée ni de rotation en pause, vue à plat. Mini-cartes du tracé dans Aujourd'hui et le détail (déjà là, à conserver). |
| **Idées notées, à ne faire que si l'utilisateur les demande** | Fantôme : rejouer en même temps une sortie précédente sur le même parcours (demande de reconnaître deux tracés semblables). Image de la sortie à partager (tracé, chiffres) : c'est une donnée GPS personnelle, partage à l'initiative de l'utilisateur seulement. Son ou musique : non prévu. |
| Fichiers | `Core/Replay/ReplayDirector.swift`, `Core/Replay/ReplayClock.swift`, leurs tests ; `App/Features/Replay/*` (`ReplayView`, `ReplayMap`, `TrackOverlay`, `ReplayHUD`, `ReplayScrubber`). |
| Validation | Tests Core : cap lissé sans saut à 359°/0°, pas de dépassement après un demi-tour, distance et inclinaison bornées, horloge (pause, vitesses, saut, fin), position entre deux relevés et aux bornes, images clés d'entrée continues avec la caméra de suivi. Sur l'iPhone, dans cet ordre : 3.0 (tracé visible et fluide), puis entrée et sortie, puis effets. Chaque livraison dit à l'utilisateur quoi regarder. |
| Risques | Le plus gros : la surimpression d'écran décalée ou trop lente (d'où 3.0 en premier et les plans B et C). Saccades si la caméra SwiftUI est mise à jour à chaque image sur une vraie sortie de 3 600 points : simplifier le tracé à 500 points pour l'affichage. Chargement des tuiles satellite en 4G pendant la descente d'entrée. Look Around absent hors des routes couvertes. Rien de tout cela ne se juge sur une capture : seul l'iPhone fait foi. |

**État (2026-11-13).** Prototype 3.0 (carte SwiftUI `.hybrid(elevation: .realistic)` à 60°, tracé projeté par `MapProxy.convert` dans un `Canvas`) **refusé sur l'iPhone** : « la map ne bouge pas avec le tracé ». En relief, la caméra envoyée à chaque image par `MapCameraPosition` n'était pas appliquée, alors que le calque suivait. **Plan B livré** : `ReplayMapView` (`MKMapView` dans un `UIViewRepresentable`, non manipulable, sans boussole), pour les trois modes (incliné en relief 60° / 500 m, satellite à plat, plan). À chaque image : `setCamera(animated: false)`, puis projection (`convert(_:toPointTo:)`) d'un point tous les 12 m, de 600 m derrière à 1 500 m devant le coureur, dans des `CAShapeLayer` au-dessus de la carte, sans animation implicite. L'horloge reste le `TimelineView` de SwiftUI, qui appelle `updateUIView` à chaque image.
Retour de l'utilisateur sur le plan B (2026-11-13) : trait mieux calé, mais (1) traits orange qui traversent l'écran, (2) le replay doit partir du début, (3) les passages en marche ralentissent tout, (4) la carte sursaute à chaque changement de direction, (5) écart entre le trait et le terrain. Corrigé : (1) points derrière la caméra inclinée écartés du trait (`ReplayDirector.isInFrontOfCamera`, profondeur le long de l'axe de visée) ; (2) départ à 0 ; (3) **écart volontaire au §3.1** : la lecture avance à vitesse constante sur la **distance** (`Track.index(atDistanceM:)`), plus au temps réel, et une sortie dure 60 à 90 s à ×1 ; (4) cap visé = direction d'un point 80 m devant, lissé sur 0,6 s par le plus court chemin (`ReplayDirector.smoothHeading`). (5) l'utilisateur constate que le trait « bouge » seulement en relief 3D. Cause : le trait est au sol mais dessiné par-dessus des arbres et bâtiments 3D ; quand la caméra bouge, il glisse sur eux (parallaxe). Aucune projection ne corrige cela.
**Limite de MapKit constatée par la CI (2026-11-13)** : le satellite sans relief (`MKHybridMapConfiguration(elevationStyle: .flat)`) ignore l'inclinaison, même avec `MKMapView`. Un satellite incliné sans objets 3D n'existe pas. Le plan sans relief (`MKStandardMapConfiguration(elevationStyle: .flat)`) s'incline, mais affiche des arbres et bâtiments 3D stylisés (plus petits).
**Modes retenus** (bouton en haut à droite) : 0 = satellite vu du dessus, **par défaut** (trait exactement sur le sol) ; 1 = relief 3D incliné à 60° (immersif, le trait glisse sur les objets 3D) ; 2 = plan incliné à 60° (sol plat, légère parallaxe sur les arbres stylisés).
**3.2 livrée** : entrée (vue d'ensemble nord en haut 0,8 s, puis descente de 2,5 s vers le départ, `ReplayDirector.blend` : zoom géométrique, cap par le plus court chemin ; lecture lancée à l'arrivée ; le bouton lecture saute l'entrée), sortie (remontée de 2,5 s vers la vue d'ensemble, carte de bilan : distance, durée, allure, meilleur km ; Revoir, Fermer). « Réduire les animations » : ni entrée ni sortie. Caméra pilotée image par image (pas d'animation MapKit) : le tracé reste calé pendant les séquences.
**3.3 et 3.4 en partie (2026-11-13)** : halo du coureur, onde qui part du point à chaque battement au rythme cardiaque réel du moment (pas à la vitesse de lecture), dans la couleur de la zone (`HeartZones`, Core : `hrMax` du profil, sinon 208 − 0,7 × âge ; pas de halo sans FC) ; bulle « km 3 · 6:19 » 2 s au-dessus du coureur à chaque kilomètre franchi, avec retour haptique léger ; bandeau réduit à une ligne (allure, FC, distance, temps) pendant la lecture, toucher la carte l'agrandit ou le réduit, toucher la ligne l'agrandit ; chiffres rafraîchis 4 fois par seconde. « Réduire les animations » : halo fixe. Reste : tracé coloré par zone, queue de comète, chevron, drapeaux, temps forts, profil d'altitude comme barre, saut animé, rotation en pause.
**Tracé en zigzag** (remarque de l'utilisateur, 2026-11-13) : mesuré sur une vraie sortie, le GPS de la montre s'écarte de la trajectoire de 1,5 m en médiane, 4,4 m au 90e centile, 12 m au plus, avec un relevé tous les 2,7 m : le trait relie ces écarts et zigzague le long d'un trottoir. Les données Garmin elles-mêmes sont propres (aucun virage de plus de 45° entre deux relevés). Correction d'affichage : `Track.smoothed(windowM: 10)` dans `Run.loadTrack()` ; la base garde les relevés bruts. Coller le tracé au trottoir demanderait un calage sur les routes, qu'aucune API Apple ne fournit.

**Ordre et priorités.** Indispensable : 3.0, 3.1, 3.2. Fort effet pour peu de code : halo cardiaque, bornes kilométriques, bandeau réduit (3.3 et 3.4 en partie). Le reste de 3.3 et 3.4 ensuite, un effet à la fois, en s'arrêtant dès que l'utilisateur est satisfait.

### Étape 4 — Coach IA et génération de plan
| | |
|---|---|
| Tâches | 4.1 `PaceModel`, `LoadModel`, `MacroPlanner`, avec leurs tests. 4.2 `Guardrails` (G1 à G13) et `FallbackPlanner`, avec leurs tests. 4.3 `LLMClient`, `LLMProvider`, `CoachSchemas`, `Prompts`. 4.4 `SnapshotBuilder`, `CoachEngine` (F2 : génération, réparation, repli). 4.5 Chat (F4) et `ConfirmCard`. 4.6 Écran Réglages → IA, bouton Tester. 4.7 Régénération hebdomadaire et adaptation sur séance manquée, fatigue ou douleur. |
| Fichiers | `Core/Training/*`, `Core/Coach/*`, `App/Features/Coach/*`, `App/Features/Plan/*`, `App/Features/Settings/AISettingsView.swift`, `App/Data/Stores/PlanStore.swift`. |
| Validation | Tests Core : chaque garde-fou a un cas qui passe et un cas qui échoue ; `FallbackPlanner` passe tous les garde-fous sur 26 semaines simulées ; `MacroPlanner` sur le profil de référence ne dépasse jamais + 10 % ou + 2 km ; décodage de réponses IA valides et invalides (fixtures). Sur l'iPhone : plan généré après l'onboarding, chaque séance a une explication, le chat déplace une séance après confirmation, « j'ai mal au genou » déclenche le mode prudent et le conseil de consulter, sans clé le plan de secours s'affiche. |
| Risques | Qualité variable des modèles gratuits (d'où D4) ; `json_schema` non pris en charge par un fournisseur (repli `json_object`) ; quotas et noms de modèles changeants ; conditions d'usage des données. |
| État (2026-11-13) | 4.1 et 4.2 faites dans Core, 74 tests verts sous Linux : `PaceModel`, `LoadModel`, `MacroPlanner`, `WeekBriefBuilder`, `Guardrails` (G1 à G13, un cas qui passe et un qui échoue chacun), `FallbackPlanner` (passe tous les garde-fous sur 26 semaines simulées, fatigue normale et élevée), `HeartZones`, types `WeekBrief` et `AthleteSnapshot`, `StrengthCatalog` (identifiants seuls). Interprétations : sans historique, pas de G2 ni de borne « plus longue récente + 2 km » de G3 ; la course elle-même est hors volume et hors G8 ; affûtage et course se calculent sur le volume maximal réellement atteint par le plan ; en douleur, le plan de secours propose le repos complet. **Conflit de règles constaté** : G8 limite la sortie longue à 1,5 × `maxSessionMinutes` (90 min pour 60), alors que `MacroPlanner` monte jusqu'à 17 km (environ 2 h à allure longue) : le plan de secours plafonne la sortie longue à 90 min ; à trancher avec l'utilisateur. 4.3 bloquée par le choix du fournisseur (§6.7). |

### Étape 5 — Envoi des séances sur la montre
| | |
|---|---|
| Tâches | 5.1 `GarminWorkoutMapper` (course, puis renfo). 5.2 Méthodes `createWorkout`, `deleteWorkout`, `schedule`, `unschedule`, `listWorkouts` dans `GarminAPI`. 5.3 `WatchSyncEngine` (F3) : fenêtre glissante de 7 jours, mise à jour par suppression puis recréation, 3 essais au plus. 5.4 États d'envoi dans Aujourd'hui, Plan et le détail. 5.5 « Nettoyer les séances envoyées » : supprime côté Garmin tout workout dont le nom commence par `RC · `. |
| Fichiers | `Core/Garmin/GarminWorkoutMapper.swift`, `Core/Garmin/GarminAPI.swift`, `App/Services/WatchSyncEngine.swift`, vues Plan et Aujourd'hui. |
| Validation | Tests Core : le JSON produit pour une séance simple, un fractionné et un tempo est identique aux fixtures de référence tirées de la validation 2.0 ; conversion des allures. Sur la montre : la séance du lendemain apparaît dans le calendrier de la Forerunner 745 après synchro, avec ses étapes et ses cibles ; une séance modifiée dans l'app est remplacée ; une séance supprimée disparaît. |
| Risques | Schéma de workout non officiel (un champ refusé = HTTP 400 peu explicite) ; renfo : catégories d'exercices à valider ; doublons si une suppression échoue (d'où le préfixe et le nettoyage) ; délai de synchro de la montre. |

### Étape 6 — Finitions, notifications, tests
| | |
|---|---|
| Tâches | 6.0 **Voir avec l'utilisateur comment garder l'app disponible en permanence sans payer** (demande du 2026-11-13). Contrainte d'Apple : identifiant gratuit = signature de 7 jours, aucune exception. Pistes à présenter : rafraîchissement automatique de Sideloadly en Wi-Fi quand le PC est allumé ; SideStore (renouvellement depuis l'iPhone, sans PC, après installation initiale) ; à défaut, compte Apple Developer (99 $/an, 1 an + TestFlight). Écarter les certificats d'entreprise détournés. 6.1 Notifications locales : rappel de la séance du jour (heure réglable), bilan du dimanche, rappel 2 jours avant l'expiration de la signature de l'app. 6.2 États vides, de chargement et d'erreur de tous les écrans. 6.3 Passe d'accessibilité (VoiceOver, grandes tailles de texte, contrastes en clair). 6.4 Performance : ouverture de l'app, défilement de la liste des sorties, replay d'une sortie de 2 h. 6.5 Icône de l'app. 6.6 Guide d'installation pour l'ami (README). |
| Fichiers | `App/Services/Notifications.swift`, tous les écrans, `Resources/Assets.xcassets`, `README.md`. |
| Validation | Captures de tous les états en clair et en sombre. Une semaine d'usage réel sans intervention : synchro, plan, envoi sur la montre. L'ami installe sa copie en suivant le README seul. |
| Risques | Les notifications locales planifiées ne survivent pas à l'expiration de la signature ; pas de notifications push sans compte payant. |

---

## 9. Pièges connus

### 9.1 iOS
- **Arrière-plan non garanti.** `BGAppRefreshTask` est déclenché quand iOS le décide, selon l'usage de l'app ; il peut ne pas l'être pendant des heures, et jamais si l'utilisateur ferme l'app en la balayant. La synchro fiable est celle de l'ouverture de l'app. L'envoi sur la montre se fait donc aussi au moment de la génération du plan, jamais « plus tard en arrière-plan » seulement.
- Tâche d'arrière-plan : 30 s environ. Y faire uniquement la synchro incrémentale, jamais le backfill ni un appel IA.
- L'identifiant de tâche doit figurer dans `BGTaskSchedulerPermittedIdentifiers` (Info.plist) et le mode `fetch` dans `UIBackgroundModes`.
- **Keychain en arrière-plan** : `kSecAttrAccessibleAfterFirstUnlock`, sinon la lecture des jetons échoue téléphone verrouillé.
- **App expirée** (7 jours) : elle ne se lance plus, les tâches d'arrière-plan ne tournent plus, mais les données restent. Si l'expiration dure plus de 30 jours, la session Garmin est perdue.
- Ne jamais désinstaller l'app pour la mettre à jour : la réinstaller par-dessus, sinon la base locale est effacée.
- **SwiftData** : changer un modèle sans migration fait planter l'app au lancement. Tant que l'app n'a pas de données réelles (étape 1), on peut casser ; à partir de l'étape 2, tout changement d'entité passe par un `VersionedSchema` et un plan de migration, ou n'ajoute que des champs optionnels.
- SwiftData et concurrence : un `ModelContext` par acteur ; ne jamais passer une entité d'un contexte à un autre, passer son identifiant.
- **MapKit 3D** : `.imagery(elevation: .realistic)` donne le satellite drapé sur le relief. Les bâtiments en 3D photoréaliste n'existent que dans certaines villes. Pas de cartes hors ligne. Mettre à jour la caméra à chaque image peut saccader (plan B à l'étape 3).
- **Constats de la CI à l'étape 1 (simulateur iOS 26.5, Xcode 26.6), à confirmer sur l'iPhone à l'étape 3 :**
  - Une `Annotation` SwiftUI n'apparaît pas quand la carte est en relief 3D et inclinée (absente ou masquée par le relief, cause non établie) ; elle s'affiche correctement à plat. Le point du coureur est donc un `MapCircle` (posé au sol, placé comme le tracé).
  - En relief 3D, tout ce qui est posé au sol (tracé, point) est **masqué par les arbres et les bâtiments 3D**. Confirmé sur l'iPhone le 2026-11-12 (« de temps en temps on ne voit plus le tracé ») : le relief 3D a été retiré du replay, qui n'utilise plus que `.flat`.
- **Navigation** : dans une `NavigationStack`, ne jamais mélanger `NavigationLink { vue }` et `NavigationLink(value:)`. Sur l'iPhone, toucher une sortie dans la liste (ouverte par un lien à vue) rouvrait la liste au lieu du détail. Tous les liens d'une pile qui a des destinations par valeur passent par une valeur ; `testOpenRunShowsItsDetail` couvre l'ouverture d'une sortie depuis l'accueil et depuis l'onglet Activités.
- **Inclinaison** : `.imagery(elevation: .flat)` ignore `pitch` (capture de la CI vue du dessus malgré 45°). Une vue inclinée exige `.realistic` ou `.standard`, qui ramènent les arbres 3D : d'où le tracé en surimpression d'écran de l'étape 3.
- **Look Around** : `MKLookAroundSceneRequest` ne renvoie rien loin d'une route couverte par Apple (chemins, forêts, beaucoup de petites communes). Non testé sur l'appareil à l'étape 1.
  - Si ces deux limites gênent sur l'appareil réel : passer à `MKMapView` dans un `UIViewRepresentable` (annotation classique toujours au premier plan, caméra pilotée directement).
- Le simulateur de la CI ne rend pas fidèlement la carte 3D : le replay se valide sur l'iPhone.
- `WKWebView` : pas de partage de session avec Safari ; l'User-Agent par défaut ne doit pas être modifié.

### 9.2 Garmin
- Tout le §1.3 et le §5.1.6.
- La rotation du jeton de rafraîchissement : le perdre (plantage entre la réponse et l'écriture Keychain) oblige à se reconnecter.
- Les champs JSON varient selon la montre et le type d'activité : tout est optionnel.
- Les détails sont sous-échantillonnés par Garmin (`maxChartSize`) : ne pas supposer un point par seconde.
- VO2max, charge et statut d'entraînement dépendent de la montre et de l'abonnement de données ; absents, ils sont remplacés par les calculs de l'app ou masqués.
- Un workout planifié puis modifié sans suppression préalable crée un doublon sur la montre.
- Ne jamais lancer de tests automatisés contre Garmin, ni depuis la CI (IP de centre de données, risque de blocage).

### 9.3 IA
- Un modèle gratuit peut renvoyer un JSON valide mais absurde : seuls les garde-fous font foi.
- Les quotas, les noms de modèles et les conditions d'usage des offres gratuites changent sans préavis : rien de tout cela n'est codé en dur.
- Ne jamais envoyer de coordonnées GPS, de nom de lieu ni d'identité (§2.3).
- Le coach n'est pas un professionnel de santé : l'avertissement de l'onboarding et les règles de sécurité du prompt ne sont pas facultatifs.

### 9.4 Secrets et dépôt
- La clé IA et les jetons Garmin ne vivent que dans le Keychain. Jamais dans le code, dans `UserDefaults`, dans un fichier, dans un log, ni dans une capture d'écran de la CI.
- La clé IA est stockée dans l'app parce que l'app est personnelle et que la clé appartient à son utilisateur. **Si l'app est un jour distribuée avec une clé commune, il faut un backend.**
- Le dépôt ne contient aucune donnée personnelle. Les fixtures de test sont **synthétiques** : structure réelle, valeurs inventées, coordonnées GPS déplacées loin de tout lieu réel de l'utilisateur. Un tracé réel révèle son domicile.
- Les journaux de diagnostic n'incluent jamais de ticket, de jeton, d'e-mail ni de paramètre de requête.

### 9.5 Développement sans Mac
- Chaque erreur de compilation de l'UI coûte un aller-retour de plusieurs minutes : garder la logique dans Core (compilée sur Linux), écrire des vues simples, pousser de petits lots.
- Pas de débogueur : prévoir un écran de diagnostic (Réglages → Garmin → Diagnostic) plutôt que des `print`.
- Les API SwiftUI récentes dépendent de la version de Xcode du runner : s'en tenir aux API d'iOS 18 et lire `xcodebuild -version` dans le log de la CI.

---

## 10. Sources (consultées le 2026-11-12)
- Garmin Connect Developer Program : https://developer.garmin.com/gc-developer-program/overview — FAQ : https://developer.garmin.com/gc-developer-program/enterprise/program-faq/
- Personal API Garmin (sources secondaires) : https://the5krunner.com/2026/10/22/garmin-personal-api/ — https://openwearables.io/blog/garmin-connect-developer-program-reopened
- `python-garminconnect` (code lu : `client/sso.py`, `client/session.py`, `client/transport.py`, `api/*.py`, `workout.py`, `docs/API_ENDPOINTS.md`) : https://github.com/cyberjunky/python-garminconnect
- Jetons DI depuis un client sans imitation TLS : https://github.com/isllabres/garmin-mcp-server/issues/17
- Connexion par navigateur réel : https://github.com/sidequest-scribe/garmin-browser-login
- Politique d'API Strava (source secondaire) : https://tryterra.co/blog/strava-api-changes-2026
- Foundation Models d'Apple (sources secondaires, contradictoires sur iOS 27) : https://dev.to/hariharanjagan/whats-new-in-apples-foundation-models-framework-at-wwdc-2026-5227 — https://deployedwork.com/writing/apple-foundation-models-primer
- Offres IA gratuites (sources secondaires) : https://www.developersdigest.tech/models/free-api — https://0xzr.github.io/freellmpool/free-llm-api-providers-list.html
- Sideloading avec identifiant gratuit : https://sideloadly.io/index.html — https://builds.io/blog/technologies/ios-technologies/sideloadly-vs-altstore-vs-sidestore/
- Facturation GitHub Actions (sources secondaires) : https://trimci.com/learn/github-actions-billing-explained/
