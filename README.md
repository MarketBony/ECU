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
| gearbox | 1 653 | 3 749 | 100 |
| GRID | 1 146 | 2 168 | 83 |
| Forum-2026 | 558 | 845 | 77 |
| clutch-press-review | 64 | 88 | 10 |
| **Global** | **3 425** | **6 844** | — |

Les 4 dépôts ont la passe **code + documents**. 273 communautés nommées.

Réduction mesurée : **16,6× moins de tokens par question** (`graphify benchmark`),
et jusqu'à **103×** sur les questions d'architecture.

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

## Passe sémantique — terminée sur les 4 dépôts

48 fichiers non-code extraits (docs, workflows, PDF, logos) via le modèle de
l'assistant Claude Code, sans clé API.

| Dépôt | Fichiers | Coût |
|---|---:|---:|
| gearbox | 24 | 554 662 |
| GRID | 19 | 365 030 |
| Forum-2026 | 10 | 231 123 |
| clutch-press-review | 5 | 142 580 |
| **Total** | **58** | **1 293 395** |

Coût unique : le cache ne relit que les fichiers modifiés. La passe code, elle,
reste gratuite et se régénère seule à chaque commit.

> La clé Gemini n'a pas pu servir : le compte Google est restreint
> (403 PERMISSION_DENIED sur toute génération, création de clé API refusée).
