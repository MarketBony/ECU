# -*- coding: utf-8 -*-
"""Precalcule les dispositions 3D du reseau ECU et ecrit ecu/data.json.

Le navigateur ne simule rien : les positions sont calculees ici, une fois, puis
figees. Deux dispositions sont produites, le viewer interpole de l'une a l'autre.

  ORGANIQUE  une seule simulation de forces, appliquee a TOUS les noeuds de la
             meme maniere. Les amas emergent de la topologie ; aucun n'est place
             a la main.
  SPHERIQUE  les memes directions, mais les rayons sont redistribues pour
             remplir une boule a densite constante.

Historique des erreurs corrigees ici, parce qu'elles etaient visibles a l'oeil :
  - placer d'abord chaque communaute en boule puis relaxer donnait un resultat
    INEGAL : les communautes tres liees se dissolvaient, les autres restaient
    des boules compactes au milieu d'un tissu etale.
  - ranger les noeuds isoles sur une coquille spherique dessinait un cercle net
    que rien dans les donnees ne justifiait. Ils participent desormais a la
    simulation comme les autres et se placent en peripherie d'eux-memes.
"""
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import networkx as nx
import numpy as np

SRC = Path(r'C:\Users\Operateur\.graphify\global-graph.json')
OUT = Path(r'C:\Users\Operateur\Documents\graphify-kb\kb\ecu\data.json')
SEED = 42
ECHELLE = 1250.0

def depots_declares():
    """Les projets branches, lus dans projets.ps1 — la source unique de verite.

    CETTE LISTE ETAIT RECOPIEE ICI A LA MAIN, et le 22/09/2026 elle a fini par
    diverger : un quatrieme projet a ete branche, ses noeuds sont apparus dans
    la galaxie — ils viennent du graphe global, qui ne passe pas par ici — mais
    ni ses commits ni les dates de ses fichiers, qui se lisent DEPUIS CETTE
    LISTE. Symptome vu par l'utilisateur : « l'historique ne se met plus a
    jour », alors que tout le reste marchait. Une copie qu'il faut penser a
    tenir a jour finit toujours par ne plus l'etre ; on lit donc l'original.

    Un echec est BRUYANT : se rabattre sur une liste de secours recreerait
    exactement le silence qu'on vient de corriger.
    """
    fichier = Path(__file__).resolve().parent.parent / 'projets.ps1'
    texte = fichier.read_text(encoding='utf-8-sig')   # le fichier porte un BOM
    trouves = re.findall(r"Tag\s*=\s*'([^']+)'\s*;\s*Chemin\s*=\s*'([^']+)'", texte)
    if not trouves:
        raise SystemExit(f'aucun projet lu dans {fichier} — format inattendu')
    return dict(trouves)


DEPOTS = depots_declares()


def dates_par_fichier(depot):
    """Dernier commit touchant chaque fichier, en une seule passe sur l'historique."""
    out = {}
    try:
        p = subprocess.run(
            ['git', '-C', depot, 'log', '--no-merges', '--format=@%ct', '--name-only'],
            capture_output=True, text=True, timeout=180, encoding='utf-8', errors='replace')
    except (OSError, subprocess.SubprocessError):
        return out
    if p.returncode != 0:
        return out
    ts = 0
    for ligne in p.stdout.splitlines():
        if not ligne:
            continue
        if ligne.startswith('@'):
            try:
                ts = int(ligne[1:])
            except ValueError:
                ts = 0
        elif ts and ligne not in out:
            out[ligne.replace('\\', '/')] = ts
    return out


def commits_recents(depot, n=40):
    """Les n derniers commits d'un depot, avec les fichiers que chacun touche.

    Meme forme que dates_par_fichier : un seul appel a git, et un depot
    injoignable rend une liste vide plutot que de faire echouer tout le rendu.
    \\x1e separe les commits et \\x1f les champs : aucun des deux ne peut
    apparaitre dans un message de commit, contrairement a « | » ou « ; ».
    """
    out = []
    try:
        p = subprocess.run(
            ['git', '-C', depot, 'log', '--no-merges', f'-n{n}',
             '--format=\x1e%h\x1f%ct\x1f%an\x1f%s', '--name-only'],
            capture_output=True, text=True, timeout=60, encoding='utf-8', errors='replace')
    except (OSError, subprocess.SubprocessError):
        return out
    if p.returncode != 0:
        return out
    for bloc in p.stdout.split('\x1e'):
        if not bloc.strip():
            continue
        lignes = bloc.splitlines()
        tete = lignes[0].split('\x1f')
        if len(tete) < 4:
            continue
        try:
            ts = int(tete[1])
        except ValueError:
            continue
        out.append({
            'h': tete[0],
            't': ts,
            'a': tete[2],
            's': '\x1f'.join(tete[3:])[:120],
            'fichiers': [l.replace('\\', '/') for l in lignes[1:] if l],
        })
    return out


def historique(depots, repos, noeuds_par_fichier, n=40):
    """Les commits des trois depots fusionnes, du plus recent au plus ancien.

    Chaque commit porte les INDEX des noeuds qu'il a touches, pour que le
    viewer puisse les eclairer sans rien recalculer. Le nombre est borne : un
    commit de reformatage touche des centaines de noeuds et ferait grossir
    data.json pour une surbrillance illisible.
    """
    tout = []
    for tag, chemin in depots.items():
        r = repos.index(tag) if tag in repos else -1
        for c in commits_recents(chemin, n):
            noeuds = []
            for f in c.pop('fichiers'):
                noeuds.extend(noeuds_par_fichier.get((tag, f), ()))
            c['r'] = r
            c['n'] = sorted(set(noeuds))[:80]
            tout.append(c)
    tout.sort(key=lambda c: -c['t'])
    return tout


def ecrire_version(empreinte, hist):
    """Signal de fraicheur, lu par le viewer pour proposer un rechargement.

    Tient dans un fichier minuscule expres : il est sonde toutes les 20 s, la
    ou data.json pese 700 Ko. C'est aussi le version.json que reclame le piege
    n°8 de PLAN-ECU-GITHUB.md pour la CI, ecrit ici au meme format.

    « dernier » est indispensable en plus de l'empreinte : un commit qui ne
    touche que des documents ne cree aucun noeud, donc l'empreinte du graphe ne
    bouge pas — et le viewer resterait sur un historique perime sans jamais
    savoir qu'il l'est.
    """
    OUT.with_name('version.json').write_text(json.dumps({
        'hash': empreinte,
        'dernier': hist[0]['h'] if hist else '',
        'date': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'commits': len(hist),
    }, ensure_ascii=False), encoding='utf-8')


def force_dirigee(n, aretes, masse, iterations=210, seed=SEED):
    """Fruchterman-Reingold 3D vectorise, avec masse par noeud.

    networkx met ~2 s par iteration sur ce graphe ; en calculant la repulsion
    par blocs avec numpy on tombe a ~0,25 s, ce qui permet d'en faire assez pour
    que la disposition converge vraiment au lieu de rester a moitie demelee.

    `masse` module la repulsion : un gros fichier pousse ses voisins plus loin,
    exactement comme un astre massif degage son orbite. Sans ca, les points
    volumineux se chevauchent et le rendu devient une bouillie la ou la matiere
    est dense — tout en laissant des vides ailleurs.
    """
    rng = np.random.default_rng(seed)
    pos = rng.normal(scale=0.35, size=(n, 3)).astype(np.float32)

    src = aretes[:, 0]
    dst = aretes[:, 1]
    # LE DESEQUILIBRE FONDAMENTAL DE CE GRAPHE :
    # 3 663 noeuds = 13,4 M de paires qui se repoussent, contre 6 973 aretes qui
    # attirent. Un rapport de 1 900 contre 1. Fruchterman-Reingold suppose un
    # graphe bien plus dense ; applique tel quel ici, il souffle tout vers
    # l'exterieur et ne laisse que quelques noyaux serres dans du vide.
    # Les quatre contre-mesures sont commentees en place ci-dessous.
    k = (1.0 / n) ** (1 / 3) * 1.05          # 1) distance d'equilibre resserree
    ATTRACTION = 1.45                         # 2) les aretes tirent plus fort
    GRAVITE = 0.030                           # 3) rappel central renforce
    COUPURE = 0.55                            # 4) portee max de la repulsion
    temp = 0.22
    refroidissement = (0.0022 / temp) ** (1.0 / iterations)
    BLOC = 256
    # masse ecrasee : la version precedente laissait un gros fichier repousser
    # 3,6x plus fort, ce qui creusait les vides au lieu de seulement eviter les
    # chevauchements.
    m = (1.0 + (masse - 1.0) * 0.42).astype(np.float32)
    coupure2 = COUPURE * COUPURE

    for it in range(iterations):
        dep = np.zeros_like(pos)

        # repulsion : tous contre tous, par blocs pour tenir en memoire
        for i0 in range(0, n, BLOC):
            i1 = min(i0 + BLOC, n)
            diff = pos[i0:i1, None, :] - pos[None, :, :]
            d2 = np.einsum('ijk,ijk->ij', diff, diff) + 1e-6
            coef = (k * k) * (m[i0:i1, None] * m[None, :]) / d2
            # au-dela de la coupure, deux noeuds n'ont plus a se repousser : la
            # somme de milliers de poussees lointaines et faibles est ce qui
            # dilate l'ensemble sans rien structurer.
            coef[d2 > coupure2] = 0.0
            np.fill_diagonal(coef[:, i0:i1], 0.0)
            dep[i0:i1] += np.einsum('ij,ijk->ik', coef, diff)

        # attraction le long des aretes
        d = pos[src] - pos[dst]
        dist = np.sqrt(np.einsum('ij,ij->i', d, d)) + 1e-6
        f = ATTRACTION * (dist / k)[:, None] * d / dist[:, None]
        np.add.at(dep, src, -f)
        np.add.at(dep, dst, f)

        # gravite : evite que les composantes isolees partent a l'infini
        dep -= pos * GRAVITE

        norme = np.sqrt(np.einsum('ij,ij->i', dep, dep)) + 1e-9
        pas = np.minimum(norme, temp) / norme
        pos += dep * pas[:, None]
        temp *= refroidissement

        if it % 40 == 0:
            print(f'    iteration {it}/{iterations}')

    return pos


def compacter(pos, force=0.55):
    """Resserre la couronne exterieure sans toucher a la structure.

    Apres la simulation, la densite s'effondre avec le rayon : le coeur est
    dense, la peripherie presque vide. On remappe les rayons vers ceux qu'aurait
    une boule de densite constante, puis on melange avec les rayons d'origine.

    `force = 0`   : aucune compaction, le vide d'origine
    `force = 1`   : densite parfaitement uniforme, structure aplatie
    `force = 0.55`: les vides se comblent, les amas restent des amas

    Les DIRECTIONS ne changent jamais — seule la distance au centre bouge. La
    topologie visible (qui est pres de qui) est donc preservee.
    """
    centre = pos.mean(axis=0)
    rel = pos - centre
    r = np.linalg.norm(rel, axis=1) + 1e-9
    dirs = rel / r[:, None]
    ordre = np.argsort(r)
    rangs = np.empty(len(r), dtype=np.float64)
    rangs[ordre] = np.arange(len(r))
    uniforme = ((rangs + 0.5) / len(r)) ** (1 / 3) * r.max()
    return (dirs * (r * (1 - force) + uniforme * force)[:, None]).astype(np.float32)


def en_boule(pos):
    """Meme structure angulaire, mais rayons redistribues a densite constante.

    Le rang du rayon est remappe en r ∝ (rang/n)^(1/3), la loi qui remplit une
    boule uniformement. La disposition reste reconnaissable, mais compacte.
    """
    centre = pos.mean(axis=0)
    rel = pos - centre
    r = np.linalg.norm(rel, axis=1) + 1e-9
    dirs = rel / r[:, None]
    ordre = np.argsort(r)
    rangs = np.empty(len(r), dtype=np.float64)
    rangs[ordre] = np.arange(len(r))
    nouveau = ((rangs + 0.5) / len(r)) ** (1 / 3)
    return dirs * nouveau[:, None]


# ─── entree ───────────────────────────────────────────────────────────────────
brut = SRC.read_bytes()
empreinte = hashlib.sha1(brut).hexdigest()[:16]
FORCE = '--force' in sys.argv

g = json.loads(brut.decode('utf-8'))
raw_nodes = g['nodes']
raw_links = g['links']
index = {n['id']: i for i, n in enumerate(raw_nodes)}
N = len(raw_nodes)

# Quels noeuds vivent dans quel fichier. Sert a l'historique, et c'est la meme
# cle (depot, chemin normalise) que celle des dates plus bas.
noeuds_par_fichier = {}
for i, n in enumerate(raw_nodes):
    sf = (n.get('source_file') or '').replace('\\', '/')
    if sf:
        noeuds_par_fichier.setdefault((n.get('repo'), sf), []).append(i)

# Le graphe peut n'avoir pas bouge alors que des commits sont arrives : un
# commit qui ne touche que des documents ne cree aucun noeud. On refait donc
# TOUJOURS l'historique — trois « git log », une fraction de seconde — et on ne
# saute que les 210 iterations de simulation, qui sont le vrai cout.
if OUT.is_file() and not FORCE:
    try:
        deja = json.loads(OUT.read_text(encoding='utf-8'))
    except ValueError:
        deja = None
    if deja and deja.get('hash') == empreinte:
        print(f'graphe inchange ({empreinte}) — disposition conservee')
        deja['hist'] = historique(DEPOTS, deja.get('repos') or [], noeuds_par_fichier)
        OUT.write_text(json.dumps(deja, ensure_ascii=False, separators=(',', ':')),
                       encoding='utf-8')
        ecrire_version(empreinte, deja['hist'])
        print(f"historique rafraichi : {len(deja['hist'])} commits")
        raise SystemExit(0)

paires = []
for l in raw_links:
    s, t = index.get(l['source']), index.get(l['target'])
    if s is not None and t is not None and s != t:
        paires.append((s, t))
aretes = np.array(sorted(set(paires)), dtype=np.int32)

deg = np.zeros(N, dtype=np.int32)
np.add.at(deg, aretes[:, 0], 1)
np.add.at(deg, aretes[:, 1], 1)

print(f'{N} noeuds, {len(aretes)} aretes uniques')

# ─── poids visuel : la galaxie ────────────────────────────────────────────────
# Un reseau ou tous les points font la meme taille se lit mal : rien n'indique
# ce qui pese. On distingue deux natures de noeud.
#
#   FICHIER  (le label est le nom de son propre fichier source)
#            taille ∝ log2(octets) — un gros fichier est un gros astre
#   SYMBOLE  (fonction, classe, constante)
#            taille ∝ racine(degre) — son importance est relationnelle,
#            pas volumetrique : une fonction de 3 lignes appelee partout
#            compte plus qu'une fonction de 300 lignes appelee nulle part
#
# Melanger les deux dans une meme echelle donnerait de faux geants : les
# 60 symboles d'un gros fichier heriteraient tous de sa masse.
def _base(p):
    return re.split(r'[\\/]', p or '')[-1]


octets = np.zeros(N, dtype=np.float64)
est_fichier = np.zeros(N, dtype=bool)
caches = {}
for i, n in enumerate(raw_nodes):
    sf = n.get('source_file') or ''
    if not sf:
        continue
    racine = DEPOTS.get(n.get('repo'))
    if not racine:
        continue
    chemin = Path(racine) / sf.replace('/', '\\')
    if chemin not in caches:
        try:
            caches[chemin] = chemin.stat().st_size
        except OSError:
            caches[chemin] = 0
    octets[i] = caches[chemin]
    est_fichier[i] = (n.get('label') or '') == _base(sf)

connus = octets[est_fichier & (octets > 0)]
print(f'  {est_fichier.sum()} noeuds-fichier, {len(connus)} tailles lues'
      + (f' — de {connus.min():.0f} a {connus.max():.0f} octets' if len(connus) else ''))

# poids normalise dans [0, 1], deux echelles separees puis fusionnees
poids = np.zeros(N, dtype=np.float64)
if len(connus):
    lo, hi = np.log2(connus.min() + 1), np.log2(connus.max() + 1)
    lf = (np.log2(octets + 1) - lo) / max(hi - lo, 1e-6)
    poids[est_fichier] = np.clip(lf[est_fichier], 0.0, 1.0)
sym = ~est_fichier
if deg[sym].max() if sym.any() else 0:
    ds = np.sqrt(deg.astype(np.float64))
    poids[sym] = np.clip(ds[sym] / max(ds[sym].max(), 1e-6), 0.0, 1.0) * 0.72

# masse pour la simulation : un gros astre degage son orbite
masse = 1.0 + 2.6 * poids

# ─── dispositions ─────────────────────────────────────────────────────────────
print('disposition organique (simulation globale, tous les noeuds a egalite)...')
t0 = time.time()
org = force_dirigee(N, aretes, masse)
org = compacter(org, 0.55)
span = np.abs(org).max() or 1.0
org = org / span * ECHELLE
print(f'  {time.time() - t0:.0f} s')

print('disposition spherique...')
sph = en_boule(org) * ECHELLE * 0.94

# ─── anciennete git ───────────────────────────────────────────────────────────
print('anciennete git...')
dates = {}
for tag, chemin in DEPOTS.items():
    d = dates_par_fichier(chemin)
    dates[tag] = d
    print(f'  {tag}: {len(d)} fichiers dates')
maintenant = int(time.time())

# ─── sortie ───────────────────────────────────────────────────────────────────
def court(p):
    return re.split(r'[\\/]', p or '')[-1]


comm_of = {n['id']: (n.get('community_name') or f"Communaute {n.get('community')}") for n in raw_nodes}
tailles = {}
for c in comm_of.values():
    tailles[c] = tailles.get(c, 0) + 1
comms = sorted(tailles, key=lambda c: -tailles[c])
comm_index = {c: i for i, c in enumerate(comms)}
repos = sorted({(n.get('repo') or 'externe') for n in raw_nodes})
types = sorted({(n.get('file_type') or 'code') for n in raw_nodes})

nodes_out = []
for i, n in enumerate(raw_nodes):
    a, b = org[i], sph[i]
    src_f = (n.get('source_file') or '').replace('\\', '/')
    ts = dates.get(n.get('repo'), {}).get(src_f)
    age = int((maintenant - ts) / 86400) if ts else -1
    nodes_out.append({
        'l': (n.get('label') or '')[:90],
        'r': repos.index(n.get('repo') or 'externe'),
        'c': comm_index[comm_of[n['id']]],
        't': types.index(n.get('file_type') or 'code'),
        'f': court(n.get('source_file')),
        'd': int(deg[i]),
        'a': age,
        'w': round(float(poids[i]), 3),
        'o': int(octets[i]),
        'p': [round(float(a[0]), 1), round(float(a[1]), 1), round(float(a[2]), 1)],
        'q': [round(float(b[0]), 1), round(float(b[1]), 1), round(float(b[2]), 1)],
    })

links_out = []
for l in raw_links:
    s, t = index.get(l['source']), index.get(l['target'])
    if s is None or t is None or s == t:
        continue
    links_out.append([s, t, 1 if (l.get('confidence') or 'E')[0] == 'I' else 0])

# ─── vue « communautes » ──────────────────────────────────────────────────────
# Replie les 3 663 noeuds en ~300 boules nommees : un zoom CONCEPTUEL, pas
# geometrique. Chaque communaute devient un noeud place au barycentre de ses
# membres, dont la taille suit son effectif ; les aretes inter-communautes sont
# agregees en une seule, ponderee par le nombre de liens reels.
ci = np.array([comm_index[comm_of[n['id']]] for n in raw_nodes], dtype=np.int32)
NC = len(comms)

cent_org = np.zeros((NC, 3)); cent_sph = np.zeros((NC, 3)); eff = np.zeros(NC)
np.add.at(cent_org, ci, org)
np.add.at(cent_sph, ci, sph)
np.add.at(eff, ci, 1.0)
cent_org /= eff[:, None]
cent_sph /= eff[:, None]

# repo dominant de chaque communaute, pour la colorer comme ses membres
repo_par_comm = [{} for _ in range(NC)]
for i, n in enumerate(raw_nodes):
    r = n.get('repo') or 'externe'
    d = repo_par_comm[ci[i]]
    d[r] = d.get(r, 0) + 1

poids_ct = {}
for s, t, _ in links_out:
    a, b = int(ci[s]), int(ci[t])
    if a == b:
        continue
    cle = (a, b) if a < b else (b, a)
    poids_ct[cle] = poids_ct.get(cle, 0) + 1

comms_out = []
for c in range(NC):
    dom = max(repo_par_comm[c], key=repo_par_comm[c].get) if repo_par_comm[c] else 'externe'
    comms_out.append({
        'l': comms[c],
        'n': int(eff[c]),
        'r': repos.index(dom),
        'p': [round(float(x), 1) for x in cent_org[c]],
        'q': [round(float(x), 1) for x in cent_sph[c]],
    })
comm_links = [[a, b, w] for (a, b), w in sorted(poids_ct.items(), key=lambda kv: -kv[1])]
print(f'vue communautes : {NC} noeuds, {len(comm_links)} liens agreges')

hist = historique(DEPOTS, repos, noeuds_par_fichier)
print(f'historique : {len(hist)} commits')

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps({
    'hash': empreinte, 'nodes': nodes_out, 'links': links_out,
    'repos': repos, 'types': types, 'comms': comms,
    'commNodes': comms_out, 'commLinks': comm_links, 'hist': hist,
}, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
ecrire_version(empreinte, hist)
print(f'{OUT} — {OUT.stat().st_size/1024:.0f} Ko · {len(nodes_out)} noeuds · {len(links_out)} liens'
      f' · empreinte {empreinte}')
