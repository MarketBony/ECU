# ECU — réseau de connaissance Bony

Graphe de connaissance unifié des projets du groupe Bony auto-mobile, construit avec
[Graphify](https://github.com/Graphify-Labs/graphify) (AST tree-sitter, local, déterministe).

> ⚠️ **Dépôt privé obligatoire.** Ce graphe expose la structure de code privé
> (`gearbox`, `GRID`, `Forum-2026`).

## Contenu

| Fichier | Rôle |
|---|---|
| `global-graph.json` | Le graphe unifié — c'est lui qu'on interroge |
| `ecu/` | **L'application 3D** — `index.html`, `ecu.js`, `data.json`, icônes |
| `graph.html` | Carte 2D d'origine de graphify |
| `projets.ps1` | La liste des projets branchés — **le seul fichier à éditer** |
| `ECU.ps1` | Ouvre ECU et rafraîchit le graphe derrière |
| `ecu-silencieux.vbs` | Ce que lance le raccourci : `ECU.ps1` sans aucune console |
| `creer-raccourci.ps1` | Pose l'icône ECU sur le Bureau — **à lancer une fois** |
| `nouveau-projet.ps1` | Branche un nouveau projet Bony sur le réseau |
| `rebuild.ps1` | Reconstruit tout depuis les dossiers de travail |
| `tools/` | Le moteur : `_layout3d.py` et les dix autres scripts |

## Lancer ECU

Double-clic sur l'icône **ECU** du Bureau. La fenêtre s'ouvre en quelques
secondes sur le dernier état connu ; le graphe se met à jour **derrière**, et la
page propose de se recharger quand c'est prêt.

Si l'icône n'existe pas encore :

```powershell
.\creer-raccourci.ps1
```

**Pour l'épingler à la barre des tâches avec le logo ECU**, il faut l'installer
une fois comme application : un bouton **« Installer ECU comme application »**
apparaît en bas de la colonne de gauche tant que ce n'est pas fait. Un clic
suffit.

Sans cette étape, Windows range la fenêtre sous l'icône de Chrome — c'est Chrome
qui décide, pas le raccourci. Une fois installée, `ECU.ps1` détecte le raccourci
posé par Chrome dans `Chrome Apps` et lance l'application par son identité
propre, ce qui lui donne son icône.

Si le bouton n'obtient rien (Chrome ne propose pas toujours l'installation), le
chemin manuel reste : menu `⋮` → *Ouvrir dans Chrome* → icône d'installation
dans la barre d'adresse.

**Une fois installée, l'application s'ouvre de trois endroits qui ne démarrent
PAS le serveur** : le raccourci « ECU — Engine Control Unit » que Chrome pose sur
le Bureau, son entrée dans le menu Démarrer (« Applications Chrome »), et l'icône
épinglée. C'est Chrome qui les lance, sans passer par `ECU.ps1`. D'où une tâche
planifiée qui garde le serveur debout, à poser une fois :

```powershell
.\creer-raccourci.ps1 -Demarrage
```

La tâche « ECU - serveur » tourne à l'ouverture de session **et toutes les 10
minutes** ; elle ne fait rien si le serveur tourne déjà, et le relève s'il est
tombé. Lancée par le Planificateur, elle vit hors de toute session Claude.

| Icône | Serveur | Rafraîchit le graphe |
|---|---|---|
| **ECU** (Bureau ou menu Démarrer) — le lanceur | oui | **oui** |
| **ECU — Engine Control Unit** (posée par Chrome), icône épinglée | par la tâche | non |

Le rafraîchissement reste le fait du lanceur « ECU », parce que personne ne veut
deux minutes de calcul à chaque ouverture ni en tâche de fond permanente. Ouvrir
par l'icône de Chrome montre donc l'état du dernier rafraîchissement.

> Historique : la première version posait un raccourci dans le dossier
> Démarrage. Il ne joue qu'à l'ouverture de session — et le 23/09/2026 la machine
> tournait sans redémarrer depuis une semaine : il n'avait jamais servi.

| Commande | Effet |
|---|---|
| `.\ECU.ps1` | ouvre, puis rafraîchit en arrière-plan |
| `.\ECU.ps1 -Vite` | ouvre sans rien rafraîchir |
| `.\ECU.ps1 -Rafraichir` | met à jour le graphe sans ouvrir de fenêtre |
| `.\ECU.ps1 -Serveur` | démarre le serveur seul, sans fenêtre (c'est ce que lance la tâche planifiée) |
| `.\ECU.ps1 -Arreter` | arrête le serveur local |
| `.\creer-raccourci.ps1 -Retirer` | enlève les raccourcis ECU et la tâche planifiée |

Journal du rafraîchissement de fond : `~/.cache/ecu-rafraichissement.log`.

### Quand ECU dit « hors ligne »

La barre du bas affiche **« hors ligne — données du JJ/MM à HH:MM »**, pastille
grise, quand le serveur local ne répond pas. L'application continue de
fonctionner — le service worker la sert entièrement depuis son cache — mais ce
qu'elle montre date de ce moment-là.

Sans ce signal, une fenêtre ECU ouverte sur un serveur mort est **indiscernable**
d'une fenêtre à jour : elle s'affiche, la galaxie tourne, les compteurs sont là.
C'est arrivé le 22/09/2026, et ça a fait chercher un bug d'indexation pendant
une heure. Relancer ECU par son icône remet le serveur en route.

## Dans l'application

Un **panneau Historique** (bouton dans la barre du bas, ou touche `H`) liste les
commits des trois projets, du plus récent au plus ancien. Cliquer un commit
éclaire dans la galaxie les nœuds qu'il a touchés et y amène la caméra ;
recliquer éteint. `Échap` remet tout à plat.

**Couleurs de la légende.** Cliquer le *libellé* filtre, comme avant ; cliquer la
*pastille* ouvre un sélecteur de couleur — n'importe laquelle, y compris hors
charte Bony. Clic droit sur une pastille rend sa couleur d'origine, et un bouton
« ↺ Couleurs d'origine » sous la légende remet tout à zéro. Un liseré blanc
marque les entrées modifiées.

**Tous les réglages sont retenus** d'une session à l'autre — mode de couleur,
disposition, qualité, filtre d'activité, bascules de rendu, groupes masqués,
couleurs choisies, état du panneau Historique. Recharger après une mise à jour
ne remet donc plus rien à zéro. Ils vivent dans le stockage local du navigateur,
sous la clé `ecu-reglages`.

## État au 22/09/2026

| Projet | Dossier de travail | Nœuds |
|---|---|---:|
| gearbox | `Documents\gearbox3backup` | 1 638 |
| GRID | `Documents\RELTEL` | 1 434 |
| Forum-2026 | `Documents\APP FORUM` | 582 |
| **Global** | — | **3 680 nœuds, 6 987 arêtes** |

Ces nombres bougent à chaque rafraîchissement : le graphe suit l'arbre de
travail, pas seulement les commits. `ecu/version.json` porte l'empreinte du
graphe réellement affiché, c'est elle qui fait foi.

Les 3 projets ont la passe **code + documents**.
`clutch-press-review` a été retiré du réseau (projet obsolète).

Réduction mesurée : **17,5× moins de tokens par question** (`graphify benchmark`),
et jusqu'à **86×** sur les questions d'architecture.

## Où vivent les index

Dans les **dossiers de travail eux-mêmes** (`<projet>/graphify-out/`), pas dans des
clones séparés. C'est précisément ce qui rend la mise à jour automatique : le hook
git du dépôt où tu travailles réellement régénère son propre index.

## Usage quotidien

```powershell
$G = "$env:USERPROFILE\.graphify\global-graph.json"

graphify query "comment GRID gère l'authentification" --graph $G
graphify explain "DataService" --graph $G
graphify path "useAuth()" "prisma" --graph $G
graphify god-nodes --graph $G --top 15
graphify affected "DataService" --graph $G     # ce qui casse si je touche à ça
```

Dans Claude Code, la skill est installée globalement : `/graphify query "..."`
fonctionne dans n'importe quelle session, dans n'importe quel dossier.

## Brancher un nouveau projet Bony

```powershell
.\nouveau-projet.ps1 "C:\Users\Operateur\Documents\MON-PROJET"
```

Indexe le code (gratuit), installe les hooks, enregistre le projet et l'ajoute à
`projets.ps1`. Ensuite chaque commit met à jour **l'index du projet** tout seul ;
le graphe global et la galaxie suivent au lancement suivant d'ECU. Il n'y a rien
à faire dans ECU après un push de code — le détail, et la seule exception (la
passe documents), sont dans `NOUVEAU-PROJET-BONY.md`, section « Après un push ».

Pour y ajouter aussi les documents (README, CLAUDE.md, PDF, logos) : ouvrir Claude
Code dans le dossier et taper `/graphify .` — ça coûte des tokens, une seule fois.

## Mise à jour automatique

| | Déclencheur | Coût |
|---|---|---|
| **Code** | hook `post-commit` / `post-checkout` | gratuit, automatique |
| **Documents** | `/graphify .` dans Claude Code | tokens, seulement les fichiers modifiés |

La reconstruction se lance détachée : `git commit` rend la main immédiatement.
Journal dans `~/.cache/graphify-rebuild.log`.

Après un `git pull`, lancer `graphify update <dossier>` (aucun LLM, instantané),
ou simplement le raccourci du Bureau qui le fait pour tous les projets.

## Passe sémantique — faite

58 fichiers non-code extraits (docs, workflows, `brandbook.pdf`, logos) via le
modèle de l'assistant Claude Code, sans clé API.

| Projet | Fichiers | Coût |
|---|---:|---:|
| gearbox | 24 | 554 662 |
| GRID | 19 | 365 030 |
| Forum-2026 | 10 | 231 123 |
| clutch-press-review (retiré) | 5 | 142 580 |
| **Total** | **58** | **1 293 395** |

Coût unique : le cache (`<projet>/graphify-out/cache/`) ne fait relire que les
fichiers modifiés.

> La clé Gemini n'a pas pu servir : le compte Google `marketbony@gmail.com` est
> restreint (403 PERMISSION_DENIED sur toute génération, création de clé refusée).
> Inutile de réessayer par API — la passe passe par le modèle de l'assistant.

## Pièges connus sur cette machine

- **`.html` est associé à Internet Explorer**, qui n'existe plus. `Start-Process`
  sur un fichier HTML n'ouvre rien : `carte.ps1` résout Chrome/Edge/Firefox
  explicitement.
- L'extraction AST bascule en séquentiel sous Windows (garde `__main__` du
  multiprocessing) — plus lent, sans conséquence sur le résultat.
- **Le recalcul de la disposition 3D prend ~2 min quand le graphe a changé.**
  `_layout3d.py` compare l'empreinte du graphe à celle de `data.json` : si rien
  n'a bougé il sort en une seconde (« graphe inchangé — disposition
  conservée ») ; sinon il rejoue 210 itérations de simulation puis relit
  l'historique git des trois dépôts. C'est normal, et la progression défile
  maintenant à l'écran — le 22/09/2026, la version muette a fait prendre un
  calcul parfaitement sain pour un plantage.
