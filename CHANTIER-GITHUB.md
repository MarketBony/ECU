# Chantier — ECU alimenté par GitHub, hébergé sur le VPS

> Plan de travail à valider avant de commencer. Rien n'est engagé.
> Rédigé le 20/09/2026.

---

## L'objectif en une phrase

Que le réseau se mette à jour **parce que tu as poussé sur GitHub**, et non parce
que tu as commité sur *cette* machine — et qu'il soit consultable depuis
n'importe où à l'adresse `https://gearbox.bonyauto-mobile.com/ECU`.

## Où on en est

```
  [ton PC]
     ├── gearbox3backup ──┐
     ├── RELTEL ──────────┤ hook post-commit (local)
     └── APP FORUM ───────┘
              │
              ▼
      ~/.graphify/global-graph.json ──► ECU (localhost:7420)
```

Tout dépend de cette machine. Si tu codes ailleurs, rien ne bouge.

## Où on veut aller

```
  [GitHub]  push sur MarketBony/*
     │
     ▼
  Action « graphify » dans chaque dépôt
     │  parse le code (tree-sitter, 0 token)
     │  commite graphify-out/ dans le dépôt
     ▼
  Action « fusion » dans graphify-kb
     │  récupère les 3 graphes, les fusionne
     │  recalcule la disposition 3D
     │  publie data.json
     ▼
  VPS gearbox (Caddy) ──► https://gearbox.bonyauto-mobile.com/ECU
```

---

## Ce qui joue en notre faveur

**Tu utilises déjà GitHub Actions.** `gearbox` a *Supabase backup* et
*keep-alive*, `GRID` a en plus *Invariants*. Le mécanisme, les secrets, tes
habitudes : tout est déjà en place. On ajoute un workflow de plus, pas une
technologie de plus.

**Le VPS tourne déjà avec Caddy.** Son `Caddyfile` est minimal :

```caddy
{$DOMAIN} {
    reverse_proxy /api/* api:3000
    reverse_proxy /socket.io/* api:3000
    reverse_proxy /uploads/* api:3000
    reverse_proxy * web:80
}
```

Ajouter `/ECU` est une affaire de six lignes, avant la règle `reverse_proxy *`.

**ECU est déjà un site statique.** Rien à porter : `index.html`, `ecu.js`,
`data.json`, le dossier `vendor/` et les icônes. 1,4 Mo au total.

**L'indexation du code ne coûte rien.** C'est du parsing AST, aucun appel LLM.
En CI ça prendra une à deux minutes par dépôt.

---

## Les quatre chantiers

### A — Indexer en CI  ·  ~2 h

Un fichier `.github/workflows/graphify.yml` par dépôt :

```yaml
name: graphify
on:
  push:
    branches: [master, main]
    paths-ignore: ['graphify-out/**']   # sinon le commit du bot se relance lui-même
jobs:
  indexer:
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install "graphifyy[sql]"
      - run: |
          graphify extract . --code-only
          graphify cluster-only . --no-label
      - run: |
          git config user.name  "graphify[bot]"
          git config user.email "graphify@bonyauto-mobile.com"
          git add graphify-out/
          git diff --staged --quiet || git commit -m "graphify : index du code"
          git push
```

**Points d'attention :**
- `paths-ignore` est indispensable : sans lui, le commit du bot déclenche le
  workflow, qui recommite, à l'infini.
- Le cache sémantique (`graphify-out/cache/`) doit rester versionné, sinon la
  passe documents serait perdue à chaque run.
- À faire d'abord sur **un seul dépôt**, vérifier, puis copier sur les deux autres.

### B — Fusionner  ·  ~2 h

Un workflow dans `graphify-kb`, déclenché par les trois autres
(`repository_dispatch`) ou toutes les heures :

```yaml
- run: |
    for r in gearbox GRID Forum-2026; do
      gh repo clone "MarketBony/$r" "repos/$r" -- --depth 1
      graphify global add "repos/$r/graphify-out/graph.json" --as "$r"
    done
    python _layout3d.py --force
```

**Le point technique :** `_layout3d.py` lit aujourd'hui les tailles de fichiers
et l'historique git **sur le disque local**. En CI il aura les clones sous la
main, donc ça marche — mais il faudra remplacer les chemins codés en dur
(`DEPOTS = {...}`) par une détection relative. Une heure de travail propre.

Sortie : `data.json` publié en artefact, ou commité dans `graphify-kb`.

### C — Héberger sur le VPS  ·  ~2 h

**1. Servir les fichiers.** Dans `docker-compose.yml`, monter un volume :

```yaml
  caddy:
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./ecu:/srv/ecu:ro          # ← nouveau
```

**2. Router et protéger.** Dans le `Caddyfile`, **avant** `reverse_proxy *` :

```caddy
    handle_path /ECU/* {
        basic_auth {
            romane {$ECU_HASH}
        }
        root * /srv/ecu
        file_server
    }
```

Le hash se génère avec `docker run caddy:2-alpine caddy hash-password`.

**3. Déployer.** Une Action qui pousse le dossier `ecu/` en SCP après la fusion.

> ⚠️ **Contrainte relevée dans ton `CLAUDE.md` :** *« ports 22, 5432, 6543
> bloqués au bureau »*. Ça t'empêche de déployer en SSH depuis le bureau —
> mais **les runners GitHub ne sont pas derrière ton pare-feu**. Ce chantier
> résout donc au passage une gêne que tu as aujourd'hui.

### D — Basculer et débrancher le local  ·  ~1 h

Une fois que ça tourne : retirer les hooks locaux, ou les garder en secours pour
travailler hors-ligne. Mettre à jour `NOUVEAU-PROJET-BONY.md` : brancher un
projet deviendra « ajouter le workflow », plus « lancer le script ».

---

## Le point dur : la passe documents

**En CI, je ne suis pas là.** L'indexation du code tournera seule, parfaitement.
La lecture des documents — README, `CLAUDE.md`, `brandbook.pdf`, logos — exige
un modèle. Trois options, aucune parfaite :

| Option | Ce que ça donne | Le prix |
|---|---|---|
| **Rien en CI** | les docs restent rafraîchis à la main via `/graphify .` depuis Claude Code | gratuit, mais manuel |
| **Clé API en secret GitHub** | tout automatique | il faut une clé qui marche — ton compte Google est bloqué, donc un autre fournisseur, payant |
| **Runner auto-hébergé sur le VPS** | un modèle local (Ollama) sur le VPS | gratuit, mais lent et à administrer |

**Ma recommandation : commencer sans.** Le code représente l'essentiel du graphe
et se met à jour tout seul. Les documents changent beaucoup plus rarement — un
`/graphify .` de temps en temps suffit largement. On ajoutera une clé le jour où
ce sera vraiment gênant.

---

## Décisions qui t'appartiennent

1. **Authentification sur `/ECU`.** Basic auth suffit-il, ou tu veux mieux ?
   Rappel : le graphe expose la structure de ton code privé.
2. **Où vit `data.json` ?** Commité dans `graphify-kb` (versionné, lisible dans
   l'historique) ou simple artefact (plus propre, mais pas d'historique).
3. **Fréquence.** À chaque push, ou groupé toutes les heures ?
4. **Le sort des hooks locaux.** Supprimés, ou gardés en secours ?
5. **La passe documents.** Manuelle pour commencer, comme je le recommande ?

---

## Estimation

| Chantier | Durée |
|---|---|
| A — indexer en CI | ~2 h |
| B — fusionner | ~2 h |
| C — héberger sur le VPS | ~2 h |
| D — basculer | ~1 h |
| **Total** | **~7 h**, soit une bonne journée avec les essais |

**Ordre conseillé : C, puis A, puis B.** Héberger d'abord permet de voir ECU en
ligne dès la première heure, alimenté à la main par le `data.json` actuel. Tu
disposes d'un résultat visible avant d'avoir touché à la moindre Action — et si
on s'arrête là, tu y gagnes déjà.

## Ce qui ne change pas

- Le coût en tokens reste nul pour le code.
- Les 1,29 M de tokens déjà investis dans les documents sont préservés : le
  cache sémantique est dans `graphify-out/cache/`, versionné avec le reste.
- La skill `/graphify` continue de marcher en local, indépendamment.
