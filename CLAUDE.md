# RunCoach — CLAUDE.md

App iPhone personnelle de course à pied : import Garmin, coach IA, envoi des séances sur la montre, replay sur carte.
**Lis `ARCHITECTURE.md` en entier avant de coder.** C'est la référence unique ; ce fichier n'en est que le résumé.
Si un fait d'`ARCHITECTURE.md` s'avère faux, corrige-le là-bas dans le même changement.

## Contraintes non négociables
- **Pas de Mac.** Tu ne peux rien compiler ici. La compilation se fait sur GitHub Actions ; lis les résultats avec `gh`.
- **Dépôt public depuis le 2026-11-13** (quota macOS gratuit épuisé en privé ; audit de tout l'historique fait, accord de l'utilisateur) : rien de personnel ni de secret ne doit y entrer, jamais.
- **Pas de backend, pas de dépendance tierce, tout gratuit.**
- **Garmin : API non officielle, appelée depuis l'iPhone.** Respecte à la lettre les règles anti-blocage (§5.1.6) : jamais de boucle de connexion, requêtes séquentielles, backoff sur 427/429/403. Aucun test automatique ne touche les serveurs de Garmin.
- **Le code calcule, l'IA rédige.** Tout ce que l'IA produit passe par `Guardrails` avant d'être enregistré.
- **Aucun secret ni donnée personnelle dans le dépôt.** Clé IA et jetons Garmin : Keychain uniquement. Fixtures synthétiques, sans coordonnées GPS réelles.
- **Vers l'IA : agrégats uniquement.** Jamais de GPS, de nom de lieu, d'identité.

## Structure
- `Packages/RunCoachCore/` : toute la logique. Swift pur, `Foundation` seulement (pas de SwiftUI, SwiftData, MapKit, CoreLocation, UIKit, Security, WebKit). Testé sur runner Linux.
- `App/` : SwiftUI, SwiftData, MapKit, services iOS. Dépend de Core.
- `AppUITests/ScreenshotTests.swift` : captures de chaque écran en mode `-mockData`.
- `project.yml` : projet Xcode généré par XcodeGen. Ne jamais écrire de `.xcodeproj` à la main.

## Conventions
- Interface en français, identifiants de code en anglais, unités métriques.
- Unité dans le nom de chaque champ numérique : `distanceM`, `durationS`, `paceSPerKm`, `speedMps`.
- Un type principal par fichier. Écran = `XxxView` + `XxxViewModel` (`@Observable`, `@MainActor`).
- Tout champ venant de Garmin est optionnel. Colonnes des détails résolues par `key`, jamais par indice.
- Données factices seulement avec l'argument `-mockData` (captures de la CI) ; sinon base persistante. Ne jamais casser une base installée : champs optionnels ou valeur par défaut, ou migration.
- Réponses Garmin réelles : uniquement hors du dépôt (`Documents\RunCoach-garmin\`). Lire le dossier `skeleton\` (valeurs masquées), jamais `raw\` ni `tokens\`.
- Aucune couleur, police ou espacement en dur dans une vue : `DesignSystem/Tokens.swift` et `Typography.swift`.
- Mode de langage Swift 5, cible iOS 18.0, API d'iOS 18 au plus.
- Toute logique de Core non triviale a un test. Les vues se vérifient par les captures de la CI.
- Commentaires : le « pourquoi » seulement. Raccourci assumé : `// shortcut: <limite>, <quand améliorer>`.
- À partir de l'étape 2, un changement d'entité SwiftData n'ajoute que des champs optionnels ou fournit une migration.
- Pas d'abstraction, d'option ni de fichier que la tâche en cours n'exige pas.

## Boucle de travail
1. Écrire un petit lot, logique dans Core d'abord.
2. Pousser. `core.yml` (Linux, rapide) à chaque push ; `ios.yml` (macOS, coûteux) sur `main` ou à la demande.
3. `gh run watch`, puis `gh run view --log-failed` en cas d'échec.
4. UI : `gh run download -n screenshots` et relire les PNG en clair et en sombre.
5. Ce qui ne se juge que sur l'appareil (connexion Garmin, replay, montre) : demander à l'utilisateur d'installer l'IPA et dire précisément quoi vérifier.

## Plan
| Étape | Contenu | État |
|---|---|---|
| 0 | Architecture (`ARCHITECTURE.md`) | fait le 2026-11-12 |
| 1 | Squelette, design system, données factices, CI, première installation | fait ; testé sur l'iPhone et accepté par l'utilisateur le 2026-11-13 (orange, onglet Activités, renfo, replay à plat). Sa demande restante, le replay vivant, est l'étape 3. |
| 2 | Connexion Garmin et import (tout l'historique au premier passage, puis ce qui manque). | fait ; validé sur l'iPhone par l'utilisateur le 2026-11-13 |
| 3 | Replay vivant : vue inclinée, entrée en zoom, effets. **Commencer par le prototype 3.0 et le faire valider.** | 3.0 à 3.2 faits (plan B `MKMapView`, satellite vu du dessus par défaut) ; halo cardiaque, bornes km, bandeau réduit livrés le 2026-11-13, en attente du verdict |
| 4 | Coach IA, génération et adaptation du plan, chat faite (Groq ou Gemini au choix, bascule de modèle sur quota, bilan de forme, chat avec actions confirmées, 4.7, douleur dosée, réglages complets) ; dernière livraison le 2026-11-14, en attente des retours de l'utilisateur sur l'iPhone. Détail : `ARCHITECTURE.md` §8 étape 4 « État » |
| 5 | Envoi des séances sur la montre | fait le 2026-11-14 (miroir des 7 prochains jours, course et renfo, envoi manuel dans Plan) ; l'utilisateur voit les séances arriver sur la Forerunner 745. Détail : `ARCHITECTURE.md` §8 étape 5 « État » |
| 6 | Finitions, notifications, tests. **À voir avec l'utilisateur (demande du 2026-11-13) : garder l'app disponible en permanence sans payer** (renouvellement auto Sideloadly en Wi-Fi, SideStore sur l'iPhone ; le compte Apple payant est la seule voie sans renouvellement hebdomadaire). | en cours (2026-11-14) : notifications locales, date d'expiration, icône et README faits ; 6.0 attend le choix de l'utilisateur ; 6.2 à 6.4 au fil des retours |

Détail des tâches, fichiers, critères de validation et risques : `ARCHITECTURE.md` §8.
Lève les points **[À VÉRIFIER étape N]** de ton étape avant d'écrire le code qui en dépend.

## Avec l'utilisateur
- Il débute en Swift (il connaît C++ et le web) : explique tes choix simplement.
- Dis clairement quand une limite vient de Garmin ou d'Apple plutôt que de la masquer.
- Ne promets jamais qu'une fonction Garmin marche avant de l'avoir vue marcher sur son compte.
