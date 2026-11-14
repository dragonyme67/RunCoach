# RunCoach

App iPhone personnelle de course à pied : import de tes sorties Garmin, plan d'entraînement et coach IA,
envoi des séances sur ta montre Garmin, replay de tes sorties sur une carte.

Gratuite, sans serveur : tout reste sur ton iPhone. Tu utilises **ton** compte Garmin et **ta** clé IA gratuite.
Elle ne passe pas par l'App Store : on l'installe soi-même depuis un PC, et l'installation dure **7 jours**
(limite d'Apple pour un identifiant gratuit). Il suffit ensuite de la réinstaller par-dessus, tes données restent.

> **À savoir avant de commencer**
> - L'accès à Garmin n'est **pas officiel** : Garmin peut le bloquer du jour au lendemain ou restreindre ton compte.
> - Le coach n'est pas un médecin. En cas de douleur ou de doute, consulte.

## Ce qu'il te faut
- Un iPhone sous iOS 18 ou plus récent, et son câble.
- Un PC Windows.
- Un identifiant Apple (celui de ton iPhone convient).
- Un compte Garmin Connect et ta montre déjà synchronisée avec l'app Garmin Connect.
- Une clé IA gratuite Groq (étape 4, deux minutes).
- Le fichier **`RunCoach.ipa`** : demande-le à la personne qui t'a parlé de l'app, ou, avec un compte GitHub,
  onglet **Actions** de ce dépôt → dernière exécution **iOS** réussie (coche verte) → en bas, artefact **ipa**
  (un zip qui contient `RunCoach.ipa`).

## 1. Préparer le PC (une seule fois)
1. Installe **Apple Devices** depuis le Microsoft Store (il fournit les pilotes de l'iPhone ; iTunes convient aussi).
2. Installe **Sideloadly** depuis [sideloadly.io](https://sideloadly.io).
3. Branche l'iPhone, déverrouille-le et touche **Se fier à cet ordinateur**.

## 2. Préparer l'iPhone (une seule fois)
1. Réglages → Confidentialité et sécurité → **Mode développeur** → active-le. L'iPhone redémarre ; confirme
   l'activation au réveil. (L'option n'apparaît qu'après une première tentative d'installation : si tu ne la vois
   pas, fais l'étape 3 puis reviens ici.)

## 3. Installer l'app
1. Ouvre Sideloadly. Ton iPhone apparaît dans **iDevice**.
2. Glisse `RunCoach.ipa` dans la fenêtre.
3. Dans **Apple ID**, saisis ton identifiant Apple, puis **Start**. Saisis ton mot de passe Apple quand il est
   demandé (et le code à deux facteurs). Sideloadly l'envoie à Apple uniquement pour signer l'app.
4. Sur l'iPhone : Réglages → Général → **VPN et gestion de l'appareil** → ton identifiant → **Faire confiance**.
5. Ouvre RunCoach.

## 4. Premier lancement
1. Réponds aux questions (niveau, objectif, jours disponibles). Tout reste modifiable ensuite dans Réglages.
2. **Garmin** : « Connecter mon compte ». Tu te connectes sur la page de Garmin, l'app ne voit jamais ton mot
   de passe. Le premier import récupère tout ton historique : laisse l'app ouverte quelques minutes.
3. **Clé IA** : sur [console.groq.com](https://console.groq.com), crée un compte gratuit → **API Keys** →
   **Create API Key** → copie la clé. Dans l'app : Réglages → Coach IA → colle-la, puis **Tester**.
   Sans clé, l'app fonctionne avec un plan de secours simple, sans chat.
4. Onglet Aujourd'hui : **Générer mon plan**. Les séances des 7 prochains jours partent sur ta montre ; elle les
   reçoit à sa prochaine synchronisation avec l'app Garmin Connect.

## Tous les 7 jours
L'app cesse de s'ouvrir quand sa signature expire (Réglages → À propos affiche la date ; une notification
prévient 2 jours avant si tu actives les rappels). Pour la prolonger :
- Branche l'iPhone, ouvre Sideloadly, glisse le même `RunCoach.ipa`, **Start**. Ça la réinstalle **par-dessus** :
  tes sorties, ton plan et ta connexion Garmin sont gardés.
- **Ne supprime jamais l'app pour la réinstaller** : supprimer l'app efface toutes ses données.
- Sideloadly sait aussi rafraîchir l'app tout seul en Wi-Fi quand le PC est allumé (option « auto-refresh »).

## Option sans PC chaque semaine : SideStore
SideStore est une app installée sur l'iPhone qui renouvelle elle-même la signature de 7 jours, en Wi-Fi, sans PC.
Le PC ne sert qu'une fois, pour l'installer. Guide officiel : [docs.sidestore.io](https://docs.sidestore.io/docs/installation/prerequisites).

1. iPhone : **Mode développeur** activé (étape 2). Installe **LocalDevVPN** depuis l'App Store.
2. PC : télécharge **iLoader** (lien dans le guide officiel, page *Install*), branche l'iPhone en USB, connecte-toi
   avec ton identifiant Apple et choisis **Install SideStore (Stable)**. iLoader crée aussi le « fichier
   d'appairage » dont SideStore a besoin.
3. iPhone : Réglages → Général → VPN et gestion de l'appareil → **Faire confiance**. Ouvre LocalDevVPN →
   **Connect**, puis ouvre SideStore et touche le compteur **7 DAYS** de SideStore pour finir l'installation.
4. Ajoute la source de RunCoach : SideStore → **Sources** → **+** → colle
   `https://github.com/dragonyme67/RunCoach/releases/latest/download/source.json`, puis installe RunCoach.
   Chaque nouvelle version compilée apparaît ensuite dans SideStore comme une mise à jour.
5. Laisse **LocalDevVPN connecté** : SideStore renouvelle alors les apps tout seul en arrière-plan, en Wi-Fi.
   Pour plus de sûreté, une automatisation quotidienne dans l'app Raccourcis peut lancer l'action de
   rafraîchissement de SideStore.

> **Attention aux données.** SideStore installe probablement RunCoach comme une app distincte de celle posée par
> Sideloadly (il modifie l'identifiant des apps signées avec un compte gratuit). Dans ce cas la nouvelle copie
> repart de zéro : refais la configuration, reconnecte Garmin (l'historique se réimporte tout seul) et
> régénère le plan. Supprime ensuite l'ancienne copie pour libérer une place (3 apps au plus par compte gratuit).
> Si le fichier d'appairage ne marche plus (mise à jour d'iOS, réinitialisation), refais l'étape 2.

## En cas de souci
- **« Garmin refuse la connexion pour le moment »** : Garmin limite les appels. L'app réessaie seule plus tard ;
  ne te reconnecte pas en boucle, ça aggrave le blocage.
- **Une séance en « Échec » sur la montre** : sa fiche donne la raison ; onglet Plan → **Envoyer sur la montre**
  pour réessayer.
- **Le coach ne répond pas** : Réglages → Coach IA → **Tester chaque modèle**. Le quota gratuit peut être atteint
  pour la journée ; le plan de secours prend le relais.
- **Sideloadly refuse d'installer** : vérifie que l'iPhone est déverrouillé et en mode développeur. Un identifiant
  Apple gratuit est limité à 3 apps installées de cette façon.

## Pour les développeurs
Tout se compile sur GitHub Actions (pas de Mac) : `ARCHITECTURE.md` est la référence, `CLAUDE.md` en est le
résumé avec les règles du projet.
