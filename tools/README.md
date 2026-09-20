# tools — le moteur d'ECU

Ces scripts vivaient dans `graphify-kb/` (le dossier **parent** du dépôt git),
donc hors de tout versionnement. `_layout3d.py` est tout le moteur de
disposition 3D, `_labels.json` porte 194 libellés de communautés écrits à la
main : un disque perdu et ECU n'était plus reconstructible.

Copiés ici en urgence le 20/09/2026, **sans déplacement**, pour ne casser aucun
appelant (`ECU.ps1`, `rebuild.ps1` et `nouveau-projet.ps1` référencent encore
`$Root\_layout3d.py`).

**Reste à faire — étape 0 de `PLAN-ECU-GITHUB.md` :** supprimer les originaux du
dossier parent et corriger les chemins dans les trois scripts appelants, pour
qu'il n'existe plus qu'un seul exemplaire de chacun.
