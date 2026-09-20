# tools — le moteur d'ECU

Ces scripts vivaient dans `graphify-kb/` (le dossier **parent** du dépôt git),
donc hors de tout versionnement. `_layout3d.py` est tout le moteur de
disposition 3D, `_labels.json` porte 194 libellés de communautés écrits à la
main : un disque perdu et ECU n'était plus reconstructible.

Copiés ici en urgence le 20/09/2026, puis **déplacés pour de bon le même jour**
(étape 0 de `PLAN-ECU-GITHUB.md`) : les originaux du dossier parent ont été
retirés et les appelants corrigés. Il n'existe plus qu'**un seul exemplaire de
chacun**, et il est versionné.

Ce qui a changé avec le déplacement :

| Fichier | Correction |
|---|---|
| `ECU.ps1`, `rebuild.ps1`, `nouveau-projet.ps1` | `$Root\_layout3d.py` → `$Kb\tools\_layout3d.py`, et la variable `$Root`, devenue inutile, a été retirée |
| `_apply_labels.py` | `LABELS_FILE` pointait sur `_labels.json` **du dossier parent** ; il lit maintenant son voisin via `Path(__file__)` — sans ça, le déplacement cassait les 194 libellés |
| `NOUVEAU-PROJET-BONY.md` | les deux chemins cités dans la procédure manuelle |

`_patch_ecu.py` a rejoint le lot : c'est un correctif ponctuel déjà appliqué à
`ecu.js`, conservé pour la trace, pas pour être relancé (ses `assert`
échoueraient).

**Reste hors de ce chantier — étape 4 du plan :** `_layout3d.py` contient encore
des chemins Windows en dur (`SRC`, `OUT`, `DEPOTS`). C'est ce qui l'empêche de
tourner sur un runner Linux, et ça se traite en même temps que la CI.
