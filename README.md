# graphify-kb — réseau de connaissance Bony

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
une fois comme application : dans la fenêtre, menu `⋮` → *Ouvrir dans Chrome* →
icône d'installation dans la barre d'adresse. Sans cette étape, Windows range la
fenêtre sous l'icône de Chrome — c'est Chrome qui décide, pas le raccourci.
`ECU.ps1` rappelle la marche à suivre tant que ce n'est pas fait.

| Commande | Effet |
|---|---|
| `.\ECU.ps1` | ouvre, puis rafraîchit en arrière-plan |
| `.\ECU.ps1 -Vite` | ouvre sans rien rafraîchir |
| `.\ECU.ps1 -Rafraichir` | met à jour le graphe sans ouvrir de fenêtre |
| `.\ECU.ps1 -Arreter` | arrête le serveur local |

Journal du rafraîchissement de fond : `~/.cache/ecu-rafraichissement.log`.

## Dans l'application

Un **panneau Historique** (bouton dans la barre du bas, ou touche `H`) liste les
commits des trois projets, du plus récent au plus ancien. Cliquer un commit
éclaire dans la galaxie les nœuds qu'il a touchés et y amène la caméra ;
recliquer éteint. `Échap` remet tout à plat.

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
`projets.ps1`. Ensuite chaque commit met le réseau à jour tout seul.

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
