# Brancher un nouveau projet Bony sur ECU

> **À Claude Code :** ce fichier est un mode d'emploi à exécuter. Lis-le en entier,
> puis déroule la section « Procédure ». Ne t'écarte pas des étapes sans le dire.

---

## Contexte

**ECU** (Engine Control Unit) est le réseau de connaissance des projets du groupe
Bony auto-mobile. C'est un graphe unifié construit par
[graphify](https://github.com/Graphify-Labs/graphify) : les nœuds sont les fichiers,
fonctions, classes et concepts des projets ; les arêtes sont les appels, imports et
relations sémantiques.

À quoi il sert : **poser une question au graphe coûte ~16× moins de tokens que
grepper puis lire les fichiers.** Une fois un projet branché, chaque commit met le
réseau à jour tout seul, gratuitement.

### Où vit quoi

| Quoi | Où |
|---|---|
| Racine ECU | `C:\Users\Operateur\Documents\graphify-kb` |
| Application 3D | `…\graphify-kb\kb\ecu\` — raccourci **ECU** sur le Bureau |
| Graphe global | `C:\Users\Operateur\.graphify\global-graph.json` |
| Liste des projets branchés | `…\graphify-kb\kb\projets.ps1` — **source unique de vérité** |
| Index d'un projet | `<projet>\graphify-out\` — **dans le dossier de travail lui-même** |
| Sauvegarde | dépôt privé [MarketBony/graphify-kb](https://github.com/MarketBony/graphify-kb) |

Les index vivent **dans les dossiers de travail réels**, pas dans des clones
séparés. C'est précisément ce qui rend la mise à jour automatique : le hook git du
dépôt où l'on travaille régénère son propre index.

### Périmètre — important

ECU est réservé aux **projets Bony poussés sur le GitHub MarketBony**.
Les projets personnels n'y entrent pas. En cas de doute, demander avant de brancher.

---

## Procédure

### 0. Vérifier les prérequis

```powershell
graphify --version          # attendu : 0.9.x ou plus
gh auth status              # attendu : logged in to github.com account MarketBony
Test-Path "C:\Users\Operateur\Documents\graphify-kb\kb\nouveau-projet.ps1"
```

Si `graphify` est introuvable :

```powershell
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
```

et si ça ne suffit pas : `uv tool install "graphifyy[all]"`.

### 1. Lancer le branchement

Une seule commande fait tout. Remplacer le chemin par celui du nouveau projet.

```powershell
& "C:\Users\Operateur\Documents\graphify-kb\kb\nouveau-projet.ps1" "C:\Users\Operateur\Documents\MON-PROJET" -Github
```

| Option | Effet |
|---|---|
| `-Github` | crée le dépôt **privé** `MarketBony/<nom>` et pousse. **Demander à Romane avant** : c'est une action publique sur son compte. |
| `-Tag <nom>` | force le nom dans le graphe (par défaut : le nom du dépôt GitHub, sinon le nom du dossier) |
| `-SansCarte` | saute le recalcul de la disposition 3D (~1 min) |

Le script enchaîne : dépôt GitHub → indexation du code → skill Claude Code + hooks
git → ré-épinglage de l'interpréteur → enregistrement dans le graphe global →
ajout à `projets.ps1` → recalcul de la disposition 3D.

**L'indexation du code ne coûte aucun token** : c'est du parsing AST tree-sitter,
en local, sans appel LLM.

### 2. Vérifier que c'est bien branché

```powershell
graphify global list
```

Le nouveau projet doit apparaître avec son nombre de nœuds.

```powershell
Test-Path "C:\Users\Operateur\Documents\MON-PROJET\.git\hooks\post-commit"
Select-String -Path "C:\Users\Operateur\Documents\graphify-kb\kb\projets.ps1" -Pattern "MON-PROJET"
```

Puis **vérifier que le hook fonctionne vraiment** — ne pas se contenter de sa présence :

```powershell
Get-Content "C:\Users\Operateur\Documents\MON-PROJET\.git\hooks\post-commit" | Select-String "_PINNED"
```

Le chemin affiché doit **exister** :

```powershell
Test-Path (Get-Content "C:\Users\Operateur\Documents\MON-PROJET\.git\hooks\post-commit" |
  Select-String "_PINNED='([^']*)'" |
  ForEach-Object { $_.Matches[0].Groups[1].Value })
```

Attendu : `True`. Si c'est `False`, voir le premier piège ci-dessous.

### 3. Proposer la passe documents — ne pas la lancer d'office

L'indexation du code est faite. Les **documents** (README, CLAUDE.md, cahier des
charges, PDF, logos) ne le sont pas : ils exigent une lecture par un modèle, donc
des tokens.

Romane surveille sa consommation de près. **Lui annoncer le nombre de fichiers
concernés et demander avant de lancer.** Ordre de grandeur constaté : environ
**20 000 tokens par fichier non-code** (58 fichiers ont coûté 1,29 M).

Pour compter sans rien dépenser :

```powershell
graphify extract "C:\Users\Operateur\Documents\MON-PROJET" --code-only
# la sortie indique : "--code-only: skipping N non-code file(s) (X docs, Y papers, Z images)"
```

Si elle accepte, la passe se lance depuis une session Claude Code ouverte **dans le
dossier du projet** :

```
/graphify .
```

Aucune clé API n'est nécessaire — la skill utilise le modèle de l'assistant.
Le compte Google `marketbony@gmail.com` est restreint côté API Gemini (403 sur
toute génération) : inutile de repasser par là.

### 4. Ouvrir ECU pour vérifier visuellement

Double-clic sur le raccourci **ECU** du Bureau, ou :

```powershell
& "C:\Users\Operateur\Documents\graphify-kb\kb\ECU.ps1"
```

Le nouveau projet doit apparaître dans la légende « Couleur par → Projet ».

### 5. Sauvegarder l'état du réseau

```powershell
cd "C:\Users\Operateur\Documents\graphify-kb\kb"
git add -A
git commit -m "Branchement de MON-PROJET sur ECU"
git push origin master
```

---

## Pièges connus sur cette machine

Ils ont tous été rencontrés pour de vrai. Les lire évite de les redécouvrir.

### 1. Le bac à sable de l'app Claude virtualise `%APPDATA%`

`graphify` est installé sous
`C:\Users\Operateur\AppData\Local\Packages\Claude_*\LocalCache\Roaming\uv\tools\`.
Mais **depuis l'application Claude**, ce même dossier apparaît comme
`C:\Users\Operateur\AppData\Roaming\uv\tools\`.

Conséquence : un chemin en dur écrit depuis l'app semble valide ici et **échoue
depuis un vrai terminal**. C'est ce qui a cassé les hooks git une première fois,
silencieusement.

**Ne jamais coder un chemin d'interpréteur en dur.** Utiliser :

```powershell
. "C:\Users\Operateur\Documents\graphify-kb\kb\python.ps1"
$Py = Get-PythonECU        # résout et vérifie que graphify s'importe
```

Pour réparer des hooks mal épinglés :

```powershell
& (Get-PythonECU) "C:\Users\Operateur\Documents\graphify-kb\kb\tools\_repin.py"
```

### 2. `.html` est associé à Internet Explorer

Sur cette machine, `Start-Process fichier.html` appelle un programme qui n'existe
plus : rien ne s'ouvre, aucune erreur. Il faut résoudre Chrome explicitement —
c'est ce que fait `ECU.ps1`.

### 3. Un service worker exige `http://`

La PWA ne peut pas fonctionner depuis `file://`. `ECU.ps1` sert donc le dossier sur
`127.0.0.1:7420` et ouvre Chrome en mode application.

### 4. L'extraction AST bascule en séquentiel sous Windows

Un avertissement sur le garde `__main__` du multiprocessing apparaît, puis
l'extraction repart en séquentiel. C'est plus lent, sans conséquence sur le
résultat. Ne pas s'en alarmer.

### 5. `graphify global add` avertit quand un tag change de cible

`warning: repo tag 'X' previously pointed to …, now updating to …` est
**informatif**, pas une erreur. C'est le comportement voulu quand un projet
déménage.

---

## Utiliser le réseau au quotidien

```powershell
$G = "$env:USERPROFILE\.graphify\global-graph.json"

graphify query "comment ce projet gère l'authentification" --graph $G
graphify explain "NomDuSymbole" --graph $G
graphify path "A" "B" --graph $G          # comment deux choses sont reliées
graphify affected "NomDuSymbole" --graph $G   # ce qui casse si j'y touche
graphify god-nodes --graph $G --top 15    # les hubs architecturaux
```

Dans n'importe quelle session Claude Code sur cette machine, la skill est installée
globalement : `/graphify query "..."` fonctionne partout.

**Réflexe à prendre :** avant de grepper ou de lire une série de fichiers dans un
projet branché, interroger le graphe. C'est là que se fait l'économie.

---

## Mise à jour — qui fait quoi

| | Déclencheur | Coût |
|---|---|---|
| **Code** | hook `post-commit` / `post-checkout` | gratuit, automatique |
| **Documents** | `/graphify .` dans Claude Code | tokens, seulement les fichiers modifiés |
| **Disposition 3D** | au lancement d'ECU, si le graphe a changé | gratuit, ~1 min |

La reconstruction se lance détachée : `git commit` rend la main immédiatement.
Journal dans `~/.cache/graphify-rebuild.log`.

Après un `git pull` : `graphify update <dossier>` (aucun LLM, instantané), ou
simplement lancer ECU, qui le fait pour tous les projets.

---

## Si le script n'existe pas — procédure manuelle

```powershell
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
$P = "C:\Users\Operateur\Documents\MON-PROJET"
$T = "mon-projet"

# dépôt privé (demander confirmation avant)
cd $P; gh repo create "MarketBony/$T" --private --source=. --remote=origin --push

# index + intégration
graphify extract $P --code-only
graphify cluster-only $P --no-label
cd $P; graphify claude install; graphify hook install
graphify global add "$P\graphify-out\graph.json" --as $T

# corriger l'épinglage (voir piège n°1), puis ajouter à la main dans projets.ps1 :
#   @{ Tag = 'mon-projet'; Chemin = 'C:\Users\Operateur\Documents\MON-PROJET' }

# disposition 3D
& (Get-PythonECU) "C:\Users\Operateur\Documents\graphify-kb\kb\tools\_layout3d.py" --force
```
