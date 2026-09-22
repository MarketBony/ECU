# tools — le moteur d'ECU

Ces scripts vivaient dans `graphify-kb/`, le dossier **parent** du dépôt git de
l'époque, donc hors de tout versionnement. (Ce double niveau n'existe plus : le
dépôt a été aplati en `Documents\ECU\` le 22/09/2026, ce qui supprime la cause
de ce piège.) `_layout3d.py` est tout le moteur de
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

## La liste des projets ne se recopie pas

`_layout3d.py` lit `projets.ps1` au démarrage (`depots_declares()`). Il en portait
une copie en dur, qui a divergé le 22/09/2026 : un quatrième projet branché, ses
nœuds bien présents dans la galaxie — ils viennent du graphe global, qui ne passe
pas par ce fichier — mais **aucun de ses commits, et aucune date pour ses
fichiers**, les deux se lisant depuis cette liste. Vu de l'application :
« l'historique ne se met plus à jour », alors que tout le reste marchait.

Une lecture qui échoue s'arrête **bruyamment**. Se rabattre sur une liste de
secours recréerait exactement le silence qu'on vient de corriger.

**Reste hors de ce chantier — étape 4 du plan :** `_layout3d.py` contient encore
`SRC` et `OUT` en chemins Windows absolus. C'est ce qui l'empêche de tourner sur
un runner Linux, et ça se traite en même temps que la CI.
