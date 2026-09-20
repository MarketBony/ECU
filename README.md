# graphify-kb — réseau de connaissance MarketBony

Graphe de connaissance unifié des projets du groupe Bony auto-mobile, construit avec
[Graphify](https://github.com/Graphify-Labs/graphify) (AST tree-sitter, local, déterministe).

> ⚠️ **Dépôt privé obligatoire.** Ce graphe expose la structure de code privé
> (`gearbox`, `GRID`, `Forum-2026`, `clutch-press-review`).

## Contenu

| Fichier | Rôle |
|---|---|
| `global-graph.json` | Le graphe unifié des 4 dépôts — c'est lui qu'on interroge |
| `graph.html` | Carte interactive, à ouvrir dans un navigateur (aucun serveur requis) |
| `rebuild.ps1` | Reconstruit tout de zéro sur n'importe quelle machine Windows |

## État au 20/09/2026

| Dépôt | Nœuds | Arêtes | Communautés |
|---|---:|---:|---:|
| gearbox | 1 360 | 3 357 | 82 |
| GRID | 938 | 1 802 | 61 |
| Forum-2026 | 479 | 697 | 69 |
| clutch-press-review | 15 | 18 | 3 |
| **Global** | **2 792** | **5 871** | — |

Réduction mesurée : **10,5× moins de tokens par question** (`graphify benchmark`).

## Usage quotidien

```powershell
$G = "$env:USERPROFILE\.graphify\global-graph.json"

graphify query "comment GRID gère l'authentification" --graph $G
graphify explain "DataService" --graph $G
graphify path "useAuth()" "prisma" --graph $G
graphify god-nodes --graph $G --top 15
graphify affected "DataService" --graph $G     # ce qui casse si je touche à ça
```

Dans Claude Code, la skill est installée : `/graphify query "..."`.

## Reconstruire

```powershell
.\rebuild.ps1              # code seul — 0 token
.\rebuild.ps1 -Docs        # + passe sémantique sur docs/PDF (clé API requise)
```

## Mise à jour automatique

Des hooks git `post-commit` et `post-checkout` sont installés dans chaque clone :
le graphe du dépôt se régénère tout seul à chaque commit et à chaque changement de branche.

Après un `git pull`, lancer `graphify update <dépôt>` (aucun LLM, instantané).

## Passe sémantique (docs, PDF) — non effectuée

Seule la passe **code** est faite (gratuite, locale). La passe sur les 43 documents
(`CLAUDE.md`, `ETAT-PROJET.md`, `MODELE-DONNEES.md`, `brandbook.pdf`…) exige un backend LLM :

```powershell
$env:ANTHROPIC_API_KEY = "..."        # ou GEMINI_API_KEY, OPENAI_API_KEY
.\rebuild.ps1 -Docs
```

Alternative gratuite et hors-ligne : `uv tool install "graphifyy[ollama]"` puis
`graphify extract <dépôt> --backend ollama --global --as <tag>`.
