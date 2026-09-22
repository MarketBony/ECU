# ECU sur GitHub — plan de chantier et passation

> **⏸️ CHANTIER EN PAUSE — décision de Théo du 22/09/2026.**
> ECU reste en **fonctionnement local** : hooks `post-commit`, `ECU.ps1`,
> `localhost:7420`. Rien de ce qui suit n'est engagé, et **aucune session ne doit
> attaquer une étape sans le feu vert explicite de Théo.**
> Seules l'étape 0 (faite) et l'étape 0 bis (à faire, indépendante de GitHub)
> ont un effet aujourd'hui.

> **À Claude Code, nouvelle session :** ce document est autonome. Lis-le en
> entier avant d'agir. Il contient le contexte, le plan validé, et les
> découvertes qui ont coûté cher à faire — ne les redécouvre pas.
>
> Rédigé le 20/09/2026, révisé le 22/09/2026. Interlocuteur : **Théo**.

---

## Révisions du 22/09/2026

Cinq modifications depuis la rédaction. Le reste du document est inchangé.

| # | Où | Quoi |
|---|---|---|
| 1 | §5 étape 0 | **Faite et poussée** le 20/09 (`e8ea00a`). Deux corrections imprévues consignées. |
| 2 | §5 **étape 0 bis** (nouvelle) · §4 · pièges n°4 et n°5 · §9 | Les trois `.gitignore` deviennent une étape à eux, à faire tout de suite, au lieu d'attendre l'étape 6. **Elle ne dépend pas de GitHub et reste valable malgré la pause.** |
| 3 | §2 décision 4 · §5 étape 7 · §8 | **Les hooks locaux sont gardés.** Décision renversée, avec son motif. |
| 4 | §5 étape 1 · piège n°14 | Le jeton `gh` n'a pas le scope `workflow` — bloquerait l'étape 6 au premier push. |
| 5 | §5 étape 4 | Le critère « `data.json` identique à la virgule près » est infaisable ; corrigé et mesuré. |

---

## 0. Qui, quoi, où

**Théo** travaille depuis le compte Claude de sa collègue Romane pour économiser
ses propres tokens. Les commits existants de ce dépôt sont signés
« Romane Chambon » pour cette raison — **l'auteur réel est Théo**. ✅ **Réglé :**
`user.name` / `user.email` du dépôt valent
`Theo <theo.labonne@bonyauto-mobile.com>`, effectif depuis `e8ea00a`.
L'historique antérieur n'est pas réécrit.

**ECU** (Engine Control Unit) est le réseau de connaissance des projets du
groupe Bony auto-mobile : un graphe de 3 663 nœuds construit par
[graphify](https://github.com/Graphify-Labs/graphify), visualisé par une
application 3D maison (three.js, shaders, disposition précalculée).

### Où vit quoi

| Quoi | Où |
|---|---|
| Racine du projet | `C:\Users\Operateur\Documents\graphify-kb` |
| **Dépôt git** | `…\graphify-kb\kb` ← **attention, c'est `kb`, pas la racine** |
| Application 3D | `…\graphify-kb\kb\ecu\` |
| Scripts du moteur | `…\graphify-kb\kb\tools\` ← **versionnés depuis l'étape 0** |
| Graphe global | `C:\Users\Operateur\.graphify\global-graph.json` |
| Liste des projets | `…\graphify-kb\kb\projets.ps1` — source unique de vérité |
| Sauvegarde | [MarketBony/graphify-kb](https://github.com/MarketBony/graphify-kb) (privé) |

### Les trois projets indexés

| Tag | Dossier de travail réel | Dépôt GitHub | Branche |
|---|---|---|---|
| `gearbox` | `Documents\gearbox3backup` | MarketBony/gearbox | `master` |
| `GRID` | `Documents\RELTEL` | MarketBony/GRID | `master` |
| `Forum-2026` | `Documents\APP FORUM` | MarketBony/Forum-2026 | `main` |

Les noms de dossiers ne correspondent pas aux noms de dépôts. C'est voulu et
vérifié — ce sont bien les dossiers de travail actifs.

### Outillage installé

- `graphify` **0.9.64** sur le PATH (`~\.local\bin`)
- L'interpréteur Python qui le porte est sous
  `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\uv\tools\graphifyy\Scripts\python.exe`
  — **ne jamais le coder en dur**, utiliser `Get-PythonECU` de `kb\python.ps1`
  (voir piège n°1 de `NOUVEAU-PROJET-BONY.md`)
- `gh` authentifié sur le compte **MarketBony** — mais **sans le scope
  `workflow`**, voir étape 1
- Hooks git `post-commit` actifs dans les 3 dossiers de travail

---

## 1. Ce qu'on veut, et pourquoi

Aujourd'hui ECU ne vit que sur ce PC : des hooks locaux le régénèrent à chaque
commit, et l'application n'est consultable que sur `localhost:7420`. Coder
ailleurs, ou consulter ECU depuis un autre poste, est impossible.

**Objectif :** le réseau se met à jour **parce qu'on a poussé sur GitHub**, et
ECU est consultable sur `https://gearbox.bonyauto-mobile.com/ECU` derrière un
login / mot de passe.

> ⏸️ Objectif **reporté** au 22/09/2026. Le fonctionnement local ci-dessus reste
> en place et suffit aujourd'hui.

### Ce qui s'automatise, et ce qui ne s'automatise pas

| Couche | Nœuds | Sur push | Pourquoi |
|---|---:|---|---|
| **Code** | 2 775 (76 %) | ✅ automatique, gratuit | tree-sitter lit la structure : `function`, `import`, `class`. Aucune IA. |
| **Documents** | 888 (24 %) | ❌ manuel | comprendre que « Pas de framework de test » et « Épreuve de restauration » parlent du même sujet demande de *lire*, pas de parser. |

La distinction n'est pas « fichiers contre fichiers », c'est **structure contre
sens**. ECU se mettra bien à jour tout seul sur push ; seules les *idées* d'un
nouveau document exigent un `/graphify .` occasionnel.

---

## 2. Décisions déjà prises par Théo

1. **Authentification** : login / mot de passe simple (`basic_auth` Caddy).
2. **Où vit `data.json`** : branche orpheline `deploy` de `graphify-kb`, écrasée
   à chaque publication.
3. **Fréquence** : à chaque push.
4. **Hooks locaux** : **à garder** — décision renversée le 20/09/2026. Ils sont
   gratuits, instantanés et marchent hors-ligne ; les couper remplacerait deux
   secondes en local par huit minutes d'aller-retour GitHub. Surtout, ils
   n'alimentent pas la même chose que la CI : le hook rafraîchit
   `<projet>/graphify-out/graph.json` sur ce PC, qu'`ECU.ps1` fusionne ensuite
   (`graphify update` puis `global add`) en `~/.graphify/global-graph.json` —
   **le fichier que `/graphify query` interroge, donc toute l'économie de
   tokens**. La CI, elle, alimente le web : les deux chemins sont parallèles,
   pas redondants. Et le risque qui justifiait leur suppression —
   `graphify-out/` parti dans un commit — est traité par l'étape 0 bis, pas par
   le débranchement.
5. **Isolation Caddy** : **conteneur séparé**, pas d'édition du Caddyfile de
   production au-delà de deux lignes.
6. **Autorisation gearbox** : accordée. Montrer le diff complet avant
   d'appliquer, et mettre à jour la doc dans le même lot.
7. **Mise en pause du chantier GitHub** — 22/09/2026. On conserve le
   fonctionnement local. Le plan reste valable tel quel ; il reprend au feu vert
   de Théo, à l'étape 0 bis puis à l'étape 1.

---

## 3. Découvertes qui changent tout

Quatre faits vérifiés dans le code de `graphify` et sur les dépôts. Chacun
aurait causé une panne **silencieuse**.

**① Le cache sémantique est inutile en CI.**
`--code-only` vide la liste des fichiers non-code *avant* toute lecture du cache
(`graphify/cli.py`). Ce qui préserve les 888 nœuds documents, c'est la présence
d'un `graph.json` existant, fusionné par :

```python
merge_existing_graph = incremental_mode or (code_only and existing_graph_path.exists())
```

**C'est `graph.json` qu'il faut transporter, pas `cache/`.** Sans ça, ECU
perdrait 24 % de son contenu sans le moindre message d'erreur.

**② Le cache serait froid à 100 % de toute façon.**
`core.autocrlf=true` sur ce PC, LF sur un runner Linux, et la clé de cache hache
les octets bruts sans normaliser les fins de ligne.

**③ `--depth 1` casserait la coloration par ancienneté.**
`_layout3d.py` lit tout l'historique git (`git log --name-only`) **et** la taille
des fichiers sur disque. Il faut un clone complet avec arbre de travail
(`fetch-depth: 0`).

**④ `PYTHONHASHSEED=0` est obligatoire.**
Sans lui, Louvain réordonne les communautés à chaque exécution : la galaxie se
réorganiserait visuellement à chaque push et `data.json` serait intégralement
différent à chaque fois. Le hook `post-commit` le pose déjà — la CI doit faire
pareil.

---

## 4. Architecture retenue

```
  3 dépôts projet          (+2 fichiers chacun, aucun graphify-out commité)
     .gitignore                        + graphify-out/      ← étape 0 bis
     .github/workflows/ecu-ping.yml    ~12 lignes, dispatch ← étape 6
            │  push
            ▼
  graphify-kb — branche main (humaine)
     state/<repo>/graph.json + manifest.json + cache/   ← les 888 nœuds docs
     tools/_layout3d.py et les 10 autres scripts       ← enfin versionnés
            │
            ▼  workflow de fusion
     restaure state/ → clone/graphify-out/, extract --code-only,
     global add ×3 (ordre figé), _layout3d.py
            │
            ▼  publie sur la branche orpheline « deploy » (écrasée)
     ecu/  index.html, ecu.js, data.json, version.json, vendor/
            │
            ▼  le VPS TIRE (timer systemd, deploy key lecture seule)
  VPS  ~/ecu
            │
     conteneur « ecu » (caddy)   ← TOUTE la config ECU vit ici
            ▲
     caddy gearbox : 2 lignes figées, redir + reverse_proxy /ECU/*
```

### Trois décisions structurantes

**Le VPS tire, GitHub ne pousse pas.** Une clé SSH privée dans les secrets
GitHub, c'est un shell root sur la production, détenu par un tiers, utilisable
par quiconque peut faire atterrir un fichier de workflow dans le dépôt — pour
déposer 700 Ko de JSON statique. Le VPS reçoit à la place une deploy key
*lecture seule* sur un dépôt sans code de production. Le pire cas devient
« quelqu'un lit le graphe », pas « quelqu'un est root sur le VPS ».

**Conteneur Caddy séparé.** Le `Caddyfile` de gearbox ne gagne que deux lignes,
de la même forme que les trois déjà en production depuis des mois. Toute la
config ECU (auth, racine, compression) vit dans un autre processus : une erreur
donne un 502 sur `/ECU`, gearbox ne bouge pas. Caddy est en `restart: always` —
une config invalide ne donne pas une erreur mais une **boucle de redémarrage**,
réparable uniquement depuis un hotspot 4G (port 22 bloqué au bureau).

**Branche `deploy` orpheline.** Chaque reconstruction pèse ~810 Ko
incompressibles (`global-graph.json` + `graph.html` + `data.json`). À 10 push
par jour, 3 Go par an sur `main`. GitHub alerte à 1 Go. La branche orpheline
écrasée à chaque publication supprime le problème, et sépare l'auteur humain
(`main`) de l'auteur machine (`deploy`).

---

## 5. Les étapes

Chaque étape est vérifiable seule et annulable par une commande.

> ⏸️ **Les étapes 1 à 7 sont gelées** depuis le 22/09/2026 et ne reprennent
> qu'au feu vert de Théo. L'étape 0 bis, elle, ne dépend pas de GitHub.

### Étape 0 — Sauver ce qui n'est nulle part · ✅ **FAIT le 20/09/2026** (`e8ea00a`)

**11 scripts, 42 Ko, n'étaient dans aucun dépôt git.** Le dépôt est
`graphify-kb\kb`, pas `graphify-kb` — les scripts du dossier parent étaient hors
de son périmètre :

```
_layout3d.py      15 992 o   ← tout le moteur de disposition 3D
_labels.json       3 903 o   ← 194 libellés de communautés écrits à la main
_apply_labels.py   3 171 o
_pipeline.py       4 999 o
_brancher.ps1      2 602 o
_repin.py          2 615 o
_dup.py            2 458 o
_finish.py         2 010 o
_prep.py           1 923 o
_validate.py       1 635 o
_dumpc.py          1 189 o
```

Ils avaient d'abord été **copiés** dans `kb\tools\` sans toucher aux originaux :
il en existait donc deux exemplaires identiques, et c'était **celui hors git**
que les scripts exécutaient. Les originaux sont maintenant retirés.

**Deux corrections que le plan n'avait pas vues, et qui étaient nécessaires :**

- `_apply_labels.py` lisait `_labels.json` **du dossier parent** par chemin
  absolu. Sans le repointer (`Path(__file__).with_name(...)`), le déplacement
  faisait perdre les 194 libellés écrits à la main, silencieusement.
- `$Root` ne servait plus qu'à ça dans les trois appelants : retirée.

`_patch_ecu.py` (11 Ko), absent de la liste des 11, a rejoint le lot : correctif
ponctuel déjà appliqué à `ecu.js`, gardé pour la trace, pas pour être relancé.

**Vérification :** `git -C kb ls-files tools/` renvoie **13** entrées
(11 scripts + `_patch_ecu.py` + `README.md`).

**Contrôle de non-régression passé :** `_layout3d.py` relancé depuis `tools/`
avec `--force` (55 s) reproduit un `data.json` identique — voir étape 4 pour la
seule exception, le champ `a`.

### Étape 0 bis — Fermer la porte de `graphify-out/` · 5 min · **PROCHAINE ACTION**

**12,4 Mo attendent un `git add -A` un soir de fatigue**, dans trois dépôts de
production : gearbox 4,0 Mo · GRID 6,1 Mo · Forum-2026 2,3 Mo. Vérifié le
20/09 : les trois `.gitignore` existent, **aucun** ne contient de règle
`graphify-out`, et aucun fichier n'est suivi aujourd'hui — la porte est ouverte,
personne n'est encore passé.

Le `.gitignore` de gearbox documente déjà l'incident exact du 07/09 et sa
leçon : « l'exclusion ne doit pas dépendre de la vigilance ». C'est mot pour mot
le sujet.

Cette étape était prévue pour l'étape 6, la dernière avant le débranchement.
Elle n'a aucune raison d'attendre : cinq minutes, aucune décision, c'est le
risque le plus proche — **et elle ne dépend pas du chantier GitHub, donc elle
reste valable pendant la pause.**

**À faire :** ajouter `graphify-out/` aux trois `.gitignore`, avec un
commentaire qui dit *pourquoi* (index régénéré par le hook, reconstructible à
tout moment, et il porte des chemins absolus Windows), au style de chaque
fichier — gearbox à la suite de sa section « Exclusions VOLONTAIRES », GRID
après le bloc « Éditeurs / OS », Forum-2026 dans « Divers ».

Couvre au passage le **piège n°5** : `.graphify_python` et `.graphify_root`
vivent dans `graphify-out/`.

> ⚠️ Trois dépôts de production. Montrer le diff à Théo avant de commiter, et
> ne rien mettre d'autre dans le lot que le `.gitignore`.

**Vérification :** `git -C <dépôt> check-ignore -v graphify-out/graph.json` nomme
la règle dans les trois, et `git status --short` reste vide.
**Retour arrière :** retirer les deux lignes.

### Étape 1 — Pré-vol · 30 min, aucune écriture

- `docker compose exec caddy caddy version` sur le VPS → la directive est-elle
  `basic_auth` (Caddy ≥ 2.8) ou `basicauth` ? L'image est le tag flottant
  `caddy:2-alpine`, donc la version est inconnue.
- **Minutes Actions restantes.** Dépôts privés = facturés, chaque job arrondi à
  la minute pleine. Le workflow de fusion tournera 4 à 8 min. **Si le quota est
  court, tout le chantier change de forme — le savoir maintenant.**
- Actions activé sur `Forum-2026` ? Il n'a jamais eu de `.github/`.
- **Le jeton `gh` n'a pas le scope `workflow`** — vérifié le 20/09 : `gist`,
  `read:org`, `repo`. GitHub **refuse** un push qui crée ou modifie un
  `.github/workflows/*.yml` avec un tel jeton, et le message d'erreur parle
  d'OAuth App : de quoi chercher un problème de droits pendant une heure.
  Bloquerait l'étape 6 au premier fichier. Correctif :
  `gh auth refresh -h github.com -s workflow` — action sur le compte MarketBony,
  **à valider par Théo avant de la lancer.**
- Hotspot 4G disponible (port 22 bloqué au bureau).

### Étape 2 — Héberger, alimenté à la main · 1 h 30

Service `ecu` dans `docker-compose.yml`, fichier `ecu-Caddyfile` (hors git,
comme `.env`), 2 lignes dans le `Caddyfile` de gearbox, `data.json` d'aujourd'hui
copié dans `~/ecu`. **Corriger `sw.js` avant** (piège n°1 ci-dessous).

```yaml
  ecu:
    image: caddy:2-alpine
    restart: always
    volumes:
      - ./ecu-Caddyfile:/etc/caddy/Caddyfile:ro
      - ../ecu/kb/ecu:/srv/ecu:ro      # bind RELATIF, jamais /home/ubuntu/...
    networks:
      - app-network
```

```caddy
    redir /ECU /ECU/ 308
    reverse_proxy /ECU/* ecu:80
```

**Procédure sans risque :**
1. valider dans un conteneur jetable :
   `docker run --rm -e DOMAIN=… -v ~/gearbox/Caddyfile:/etc/caddy/Caddyfile:ro caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile`
2. démarrer `ecu` seul : `docker compose up -d --no-deps ecu`
3. recharger à chaud : `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`
   — un `reload` **refuse** une config invalide et laisse tourner l'ancienne.
   C'est la différence entre un message d'erreur et un incident.

**Ne jamais faire `docker compose up -d --build caddy` pour un changement de
Caddyfile** : le fichier est monté en bind, `reload` suffit.

**Vérification :** `https://gearbox.bonyauto-mobile.com/ECU` demande un mot de
passe et affiche la galaxie ; `https://gearbox.bonyauto-mobile.com` répond
toujours 200.
**Retour arrière :** `git checkout Caddyfile && docker compose exec caddy caddy reload …`

> ⚠️ Cette étape touche la production. Montrer le diff complet à Théo avant
> d'appliquer, et mettre à jour `DEPLOIEMENT.md` (§5 affirme « 3 services »,
> ça devient faux), `ETAT-PROJET.md` et `README.md` **dans le même lot** —
> règle d'or du `CLAUDE.md` de gearbox.

### Étape 3 — Le VPS tire · 1 h

Deploy key `ecu_deploy_key` **et alias SSH obligatoire** : le VPS a déjà

```
Host github.com
  IdentityFile ~/.ssh/gearbox_deploy_key
  IdentitiesOnly yes
```

Une deploy key est liée à **un seul** dépôt. Cloner `graphify-kb` avec cette
config présenterait la clé de gearbox et GitHub répondrait
`ERROR: Repository not found` — message trompeur qui fait chercher un problème
de droits pendant une heure. D'où :

```
Host github-ecu
  HostName github.com
  IdentityFile ~/.ssh/ecu_deploy_key
  IdentitiesOnly yes
```

puis `git clone git@github-ecu:MarketBony/graphify-kb.git ~/ecu`.

Timer **systemd** (pas cron : on récupère `journalctl` et `OnFailure=`), toutes
les 5 min, sous `flock`, avec `fetch --depth 1 && reset --hard origin/deploy` —
**jamais `git pull`**, qui part en merge sur une branche force-pushée et se
bloque définitivement.

**Vérification :** pousser un commit sur `deploy`, compter 5 min, la page change.
**Retour arrière :** `systemctl disable --now ecu-pull`.

### Étape 4 — Rendre `_layout3d.py` portable · 1 h

Aujourd'hui il contient des chemins Windows en dur (`SRC`, `OUT`, `DEPOTS`),
construit les chemins en `sf.replace('/', '\\')`, lit l'historique git complet
et la taille des fichiers sur disque.

À faire : chemins par variables d'environnement, `os.sep`, mode « les dépôts
sont dans `repos/` ».

**Vérification sans CI :** le lancer sur ce PC avec les chemins injectés et
comparer le `data.json` produit à l'actuel. Il doit être identique
**sauf le champ `a`**.

> **Mesuré le 20/09**, recalcul `--force` complet (55 s) avec `PYTHONHASHSEED=0` :
> tout est identique à l'octet près — positions, communautés, liens, et le
> `hash` du graphe — **sauf `a`, qui a bougé sur 62 nœuds sur 3 663**.
> `_layout3d.py:310` le calcule par `int((maintenant - ts) / 86400)` : c'est
> l'âge du fichier en jours, il dérive avec l'horloge, par construction — c'est
> lui qui porte la coloration par ancienneté.
>
> Le critère « identique à la virgule près » était donc **infaisable tel
> qu'écrit**, et aurait envoyé chercher un bug qui n'existe pas.
>
> Conséquence pour la CI : deux exécutions ne produiront **jamais** le même
> `data.json` à l'octet, même si rien n'a changé. Pour détecter « rien n'a
> bougé », c'est le champ `hash` qu'il faut comparer, pas le fichier.

### Étape 5 — Workflow de fusion, en `workflow_dispatch` seul · 2 h

- **Trois deploy keys lecture seule** dans les secrets de `graphify-kb`
  (`DEPLOY_KEY_GEARBOX`, etc.) plutôt qu'un PAT : elles n'expirent pas, sont
  limitées à un dépôt chacune, et ne sont liées à aucun compte humain. Un PAT
  fine-grained expire à 12 mois et le réseau s'arrêterait sans bruit.
- `graphifyy[sql]==0.9.64` **épinglé** : le cache AST est rangé sous
  `cache/ast/v0.9.64-s4/` et une version différente change les identifiants de
  nœuds, donc la fusion, donc la disposition. La carte bougerait seule le jour
  d'une sortie amont.
- `fetch-depth: 0`, `PYTHONHASHSEED=0`, ordre d'ajout des 3 dépôts figé.

**Critère d'acceptation chiffré : 3 663 nœuds ± 2 %, dont ~888 non-code.**
Si les 888 manquent, c'est la découverte ① — visible immédiatement.

### Étape 6 — Brancher les déclencheurs · 1 h

**Prérequis : le scope `workflow` sur le jeton `gh` (étape 1).** Sans lui, le
premier `git push` d'un fichier de workflow est refusé.

`Forum-2026` d'abord (aucun workflow à casser), vérifier, puis les deux autres.

- `paths-ignore: ['backups/**']` — sinon le dump Supabase du lundi déclenche une
  reconstruction complète d'ECU pour un fichier Postgres.
- **`gearbox` et `GRID` sont sur `master`, `Forum-2026` sur `main`.** Un workflow
  copié-collé ne se déclenchera jamais sur l'un des trois.
- Un `schedule` hebdomadaire comme filet, et `workflow_dispatch: {}` partout.

Le `.gitignore` de ces trois dépôts a déjà été posé à l'étape 0 bis : il ne
reste que le fichier de workflow à ajouter.

### Étape 7 — Documenter · 1 h

**Les hooks locaux restent en place** (décision 2.4). Ils tiennent à jour le
graphe que `/graphify query` interroge sur ce PC ; la CI, elle, alimente le web.
Rien à débrancher.

Mettre à jour `NOUVEAU-PROJET-BONY.md` : brancher un projet devient « lancer le
script **puis** ajouter le workflow ». Écrire la règle « ECU n'indexe **jamais**
avec `--no-gitignore` » (voir piège n°11).

**Total restant : ~7 h 30.** Après l'étape 2, ECU est en ligne — si on s'arrête
là, le bénéfice principal est acquis.

---

## 6. Pièges identifiés

| # | Piège | Traitement |
|---|---|---|
| 1 | `sw.js` fait `caches.delete` sur **toute l'origine**. Servir ECU sur le domaine gearbox mettrait les deux apps dans la même origine : ECU effacerait les caches de gearbox à chaque activation. Rien ne casse aujourd'hui (le SW de gearbox n'utilise aucun cache, délibérément) mais c'est une mine. | `ks.filter(k => k.startsWith('ecu-') && k !== CACHE)` — **avant l'étape 2**. Vérifié le 20/09 : **non corrigé à ce jour**. |
| 2 | `/ECU` sans slash final ne matche pas `handle_path /ECU/*` : la requête tombe sur `reverse_proxy * web:80` et l'utilisateur reçoit gearbox. Pire, ECU est en chemins relatifs : le navigateur chercherait `/ecu.js` à la racine. | `redir /ECU /ECU/ 308` obligatoire |
| 3 | Un hash bcrypt commence par `$2a$14$…` ; chaque `$` est interprété comme une variable par compose **et** par `.env` | écrire le hash en clair dans `ecu-Caddyfile`, gardé sur le VPS hors git — même règle que `.env` |
| 4 | Aucun `.gitignore` n'exclut `graphify-out/` dans les 3 dépôts : 12,4 Mo attendent un `git add -A` un soir de fatigue. Le `.gitignore` de gearbox documente déjà cet incident exact, daté du 07/09 : « l'exclusion ne doit pas dépendre de la vigilance ». | **→ étape 0 bis**, remontée en tête de chantier |
| 5 | `.graphify_python` et `.graphify_root` contiennent des chemins absolus Windows | ils vivent dans `graphify-out/` : couverts par l'étape 0 bis |
| 6 | Un push fait avec `GITHUB_TOKEN` ne déclenche **aucun** autre workflow (règle GitHub) | la boucle infinie redoutée n'existe pas ; `paths-ignore` sert au piège n°6 bis |
| 7 | `graphifyy` non épinglé → identifiants de nœuds changés → carte qui bouge seule | `==0.9.64` |
| 8 | Sans signal de fraîcheur, un ECU en panne est **indiscernable** d'un ECU à jour — on prendrait des décisions sur une carte périmée | `version.json` (SHA court + date UTC) publié par la CI et affiché en coin d'écran |
| 9 | `Dockerfile.frontend` fait `COPY . .` depuis la racine | `~/ecu` est hors de `~/gearbox`, mais ajouter `ecu` au `.dockerignore` par précaution |
| 10 | `rebuild.ps1` (local) et la CI écrivent le même `kb/ecu/data.json` → conflit sur 700 Ko de JSON minifié | la séparation `main` / `deploy` supprime la classe de problème |
| 11 | Le graphe contient la prose de `BUGS-CONNUS.md`, `ETAT-PROJET.md`, `BACKEND-AUDIT.md`. `ACCES-INFRA-SECRET.md` en est absent **parce que le `.gitignore` est respecté par défaut** — c'est un défaut, pas une garantie. Un `--no-gitignore` un jour et des nœuds issus des fichiers de secrets partent sur le web derrière un simple `basic_auth`. | écrire la règle maintenant, avec sa justification |
| 12 | Les commits de `graphify-kb` sont signés « Romane Chambon » alors que l'auteur est Théo | ✅ réglé : `user.name` / `user.email` du dépôt valent `Theo <theo.labonne@bonyauto-mobile.com>`, effectif depuis `e8ea00a` |
| 13 | La passe documents restant manuelle, l'écart va se creuser : le code frais à la minute, les 888 nœuds « pourquoi » gelés | afficher dans ECU la date de la dernière passe documents à côté de celle du code |
| 14 | Le jeton `gh` n'a pas le scope `workflow` : GitHub refuse tout push d'un `.github/workflows/*.yml`, avec un message qui parle d'OAuth App et fait chercher ailleurs | `gh auth refresh -h github.com -s workflow` — vérifié à l'étape 1, validé par Théo |

---

## 7. Vérification de bout en bout

1. `https://gearbox.bonyauto-mobile.com/ECU` → mot de passe → galaxie, **et**
   `https://gearbox.bonyauto-mobile.com` répond toujours 200
2. Commit trivial sur `Forum-2026` → push → attendre ~8 min → `version.json`
   affiche le nouveau SHA et le nœud du fichier modifié apparaît dans ECU
3. `graphify global list` en CI : 3 dépôts, **3 663 nœuds ± 2 %**
4. Compter les nœuds non-code dans `data.json` : **~888 attendus**
5. Couper le timer systemd, pousser : ECU doit afficher un `version.json`
   périmé — **la panne doit être visible**

---

## 8. Ce qui ne change pas

- Coût en tokens **nul** pour la couche code
- Les 1,29 M de tokens de la passe documents préservés via `state/<repo>/graph.json`
- La skill `/graphify` continue de fonctionner en local, indépendamment
- **Les hooks `post-commit` restent** : ce sont eux qui tiennent à jour le graphe
  local que `/graphify query` interroge (décision 2.4). Brancher GitHub n'aurait
  déplacé que le *déclencheur* de la reconstruction, jamais l'endroit où Claude
  Code lit le graphe — **l'économie de tokens n'a jamais été en jeu.**

---

## 9. Pour reprendre

Le chantier GitHub est **en pause** (décision 2.7). Ce qui reste vrai :

| | État |
|---|---|
| Étape 0 — sauver le moteur | ✅ faite le 20/09 (`e8ea00a`) |
| Étape 0 bis — les 3 `.gitignore` | ⬜ **à faire, indépendante de GitHub** |
| Étapes 1 à 7 | ⏸️ gelées, au feu vert de Théo |

Au feu vert, ouvrir Claude Code sur
`C:\Users\Operateur\Documents\graphify-kb` et dire :

> Lis `kb/PLAN-ECU-GITHUB.md`. Théo donne son feu vert, attaque l'étape 0 bis
> puis l'étape 1.

L'étape 0 bis ne dépend d'aucune décision, prend cinq minutes et supprime le
risque le plus immédiat. L'étape 1 suit : elle n'écrit rien mais conditionne la
forme de tout le reste. Après l'étape 2, ECU est en ligne.

**Documents liés dans ce dépôt :**
- `README.md` — état du réseau, usage quotidien
- `NOUVEAU-PROJET-BONY.md` — brancher un nouveau projet (à réviser à l'étape 7)
- `tools/README.md` — le moteur, et ce que l'étape 0 a corrigé
- `CHANTIER-GITHUB.md` — première version de ce plan, avant l'étude technique.
  **Périmée sur trois points** (le cache, la branche de publication, l'isolation
  Caddy). Ce document-ci fait foi.
