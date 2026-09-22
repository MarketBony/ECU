# -*- coding: utf-8 -*-
"""Applique les trois nouvelles fonctions au viewer ECU.

Écrit en Python plutôt qu'en une série d'Edit : les remplacements sont longs et
il vaut mieux qu'ils échouent bruyamment (assert) que silencieusement.
"""
from pathlib import Path

p = Path(__file__).resolve().parent.parent / 'ecu' / 'ecu.js'
t = p.read_text(encoding='utf-8')


def sub(avant, apres, quoi):
    global t
    assert avant in t, f'motif introuvable : {quoi}'
    t = t.replace(avant, apres, 1)
    print(f'  ok  {quoi}')


# ── 1. état : filtre temporel, vue communautés, étiquettes ───────────────────
sub(
    "const state = { pulse: 1, links: 1, inferred: 1, spin: 1 };",
    """const state = { pulse: 1, links: 1, inferred: 1, spin: 1, etiquettes: 1 };

// Filtre temporel : -1 = pas de filtre, sinon âge maximum en jours.
let ageMax = -1;
// Vue communautés : les 3 663 nœuds repliés en ~300 amas nommés.
let vueComm = false;
let cPoints = null, cLines = null, cGeo = null, cLinkGeo = null;
// Étiquettes DOM des plus grosses masses.
let etiquettes = [], topIdx = [];""",
    'etat global')

# ── 2. filtre temporel dans applyDim ─────────────────────────────────────────
sub(
    """  for (let i = 0; i < NODES.length; i++) {
    let d = hidden.has(groupKey(NODES[i])) ? 1 : 0;
    if (!d && pathNodes) d = pathNodes.has(i) ? 0 : 1;
    else if (!d && focusIdx >= 0 && i !== focusIdx && !neighbours.has(i)) d = 1;""",
    """  for (let i = 0; i < NODES.length; i++) {
    let d = hidden.has(groupKey(NODES[i])) ? 1 : 0;
    // Filtre temporel : un nœud sans date connue est traité comme ancien —
    // prétendre l'inverse ferait passer de l'ignorance pour de la fraîcheur.
    if (!d && ageMax >= 0 && (NODES[i].a < 0 || NODES[i].a > ageMax)) d = 1;
    if (!d && pathNodes) d = pathNodes.has(i) ? 0 : 1;
    else if (!d && focusIdx >= 0 && i !== focusIdx && !neighbours.has(i)) d = 1;""",
    'filtre temporel (noeuds)')

sub(
    """    else if (hidden.has(groupKey(NODES[s])) || hidden.has(groupKey(NODES[t]))) d = 1;
    else if (pathLinks) d = pathLinks.has(i) ? 0 : 1;""",
    """    else if (hidden.has(groupKey(NODES[s])) || hidden.has(groupKey(NODES[t]))) d = 1;
    else if (ageMax >= 0 && !(NODES[s].a >= 0 && NODES[s].a <= ageMax
                           && NODES[t].a >= 0 && NODES[t].a <= ageMax)) d = 1;
    else if (pathLinks) d = pathLinks.has(i) ? 0 : 1;""",
    'filtre temporel (aretes)')

# ── 3. construction de la vue communautés + étiquettes ───────────────────────
sub(
    """  recolor();
  buildLegend();
  majBoutonChemin();
  appliquerQualite('equilibre');""",
    """  construireCommunautes();
  construireEtiquettes();
  recolor();
  buildLegend();
  majBoutonChemin();
  appliquerQualite('equilibre');""",
    'appels de construction')

# ── 4. les fonctions elles-mêmes, avant la section Interface ─────────────────
sub(
    "// ── Interface ──────────────────────────────────────────────────────────────",
    """// ── Vue communautés ────────────────────────────────────────────────────────
// Un zoom CONCEPTUEL, pas géométrique : chaque communauté devient une sphère
// posée au barycentre de ses membres, dont la taille suit son effectif. Les
// liens inter-communautés sont agrégés et leur épaisseur dit combien de liens
// réels ils résument.
function construireCommunautes() {
  const C = DATA.commNodes || [];
  if (!C.length) return;

  const pos = new Float32Array(C.length * 3), col = new Float32Array(C.length * 3);
  const siz = new Float32Array(C.length), dim = new Float32Array(C.length);
  const hot = new Float32Array(C.length);
  cGeo = new THREE.BufferGeometry();
  cGeo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  cGeo.setAttribute('aColor', new THREE.BufferAttribute(col, 3));
  cGeo.setAttribute('aSize', new THREE.BufferAttribute(siz, 1));
  cGeo.setAttribute('aDim', new THREE.BufferAttribute(dim, 1));
  cGeo.setAttribute('aHot', new THREE.BufferAttribute(hot, 1));
  for (let i = 0; i < C.length; i++) {
    pos[i * 3] = C[i].p[0]; pos[i * 3 + 1] = C[i].p[1]; pos[i * 3 + 2] = C[i].p[2];
    siz[i] = 16 + Math.pow(C[i].n, 0.62) * 13;
  }
  cGeo.computeBoundingSphere();
  cPoints = new THREE.Points(cGeo, nodeMat);
  cPoints.frustumCulled = false;
  cPoints.visible = false;
  scene.add(cPoints);

  const L = DATA.commLinks || [];
  const lp = new Float32Array(L.length * 6), lc = new Float32Array(L.length * 6);
  const lt = new Float32Array(L.length * 2), lph = new Float32Array(L.length * 2);
  const ld = new Float32Array(L.length * 2), lcf = new Float32Array(L.length * 2);
  const lh = new Float32Array(L.length * 2);
  cLinkGeo = new THREE.BufferGeometry();
  cLinkGeo.setAttribute('position', new THREE.BufferAttribute(lp, 3));
  cLinkGeo.setAttribute('aColor', new THREE.BufferAttribute(lc, 3));
  cLinkGeo.setAttribute('aT', new THREE.BufferAttribute(lt, 1));
  cLinkGeo.setAttribute('aPhase', new THREE.BufferAttribute(lph, 1));
  cLinkGeo.setAttribute('aDim', new THREE.BufferAttribute(ld, 1));
  cLinkGeo.setAttribute('aConf', new THREE.BufferAttribute(lcf, 1));
  cLinkGeo.setAttribute('aHot', new THREE.BufferAttribute(lh, 1));
  for (let i = 0; i < L.length; i++) {
    const a = C[L[i][0]].p, b = C[L[i][1]].p;
    lp[i * 6] = a[0]; lp[i * 6 + 1] = a[1]; lp[i * 6 + 2] = a[2];
    lp[i * 6 + 3] = b[0]; lp[i * 6 + 4] = b[1]; lp[i * 6 + 5] = b[2];
    lt[i * 2] = 0; lt[i * 2 + 1] = 1;
    const ph = (i * 0.6180339887) % 1;
    lph[i * 2] = ph; lph[i * 2 + 1] = ph;
  }
  cLinkGeo.computeBoundingSphere();
  cLines = new THREE.LineSegments(cLinkGeo, linkMat);
  cLines.frustumCulled = false;
  cLines.visible = false;
  scene.add(cLines);
}

function colorerCommunautes() {
  if (!cGeo) return;
  const C = DATA.commNodes;
  const pal = palette(DATA.repos.length);
  const col = cGeo.getAttribute('aColor');
  for (let i = 0; i < C.length; i++) {
    const c = pal[C[i].r] || pal[0];
    col.setXYZ(i, c.r, c.g, c.b);
  }
  col.needsUpdate = true;
  const lc = cLinkGeo.getAttribute('aColor');
  for (let i = 0; i < DATA.commLinks.length; i++) {
    const a = pal[C[DATA.commLinks[i][0]].r] || pal[0];
    const b = pal[C[DATA.commLinks[i][1]].r] || pal[0];
    lc.setXYZ(i * 2, a.r, a.g, a.b);
    lc.setXYZ(i * 2 + 1, b.r, b.g, b.b);
  }
  lc.needsUpdate = true;
}

function basculerVue(actif) {
  vueComm = actif;
  if (!cPoints) return;
  points.visible = !actif;
  lines.visible = !actif && !!state.links;
  cPoints.visible = actif;
  cLines.visible = actif && !!state.links;
  if (actif) colorerCommunautes();
  clearSelection();
  construireEtiquettes();
}

// ── Étiquettes des plus grosses masses ─────────────────────────────────────
// En DOM plutôt qu'en texture 3D : une quinzaine d'éléments repositionnés à
// l'écran coûtent moins qu'un atlas de glyphes, et restent nets à tout zoom.
function construireEtiquettes() {
  const box = document.getElementById('etiquettes');
  box.innerHTML = '';
  etiquettes = [];
  const COMBIEN = 16;
  if (vueComm) {
    const C = DATA.commNodes;
    topIdx = C.map((c, i) => i).sort((a, b) => C[b].n - C[a].n).slice(0, COMBIEN);
    topIdx.forEach(i => ajouterEtiquette(box, C[i].l));
  } else {
    topIdx = NODES.map((n, i) => i).sort((a, b) => (NODES[b].w ?? 0) - (NODES[a].w ?? 0)).slice(0, COMBIEN);
    topIdx.forEach(i => ajouterEtiquette(box, NODES[i].l));
  }
}

function ajouterEtiquette(box, texte) {
  const d = document.createElement('div');
  d.className = 'etiq';
  d.textContent = texte;
  box.appendChild(d);
  etiquettes.push(d);
}

const _p = new THREE.Vector3();
function placerEtiquettes() {
  if (!etiquettes.length) return;
  const montrer = state.etiquettes && !morph;
  const geo = vueComm ? cGeo : nodeGeo;
  const src = vueComm ? DATA.commNodes : NODES;
  const pos = geo.getAttribute('position');
  const dimA = geo.getAttribute('aDim');
  const w = innerWidth / 2, h = innerHeight / 2;
  camera.updateMatrixWorld();
  const vp = new THREE.Matrix4().multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
  for (let j = 0; j < topIdx.length; j++) {
    const el = etiquettes[j];
    if (!montrer) { el.style.display = 'none'; continue; }
    const i = topIdx[j];
    if (!vueComm && dimA.getX(i) > 0.5) { el.style.display = 'none'; continue; }
    _p.set(pos.getX(i), pos.getY(i), pos.getZ(i)).applyMatrix4(vp);
    if (_p.z < -1 || _p.z > 1) { el.style.display = 'none'; continue; }
    el.style.display = '';
    el.style.transform = `translate(${(_p.x * w) + w}px, ${(-_p.y * h) + h}px)`;
    // les plus lointaines s'effacent : sinon la vue se couvre de texte
    el.style.opacity = String(Math.max(0.25, 1 - (_p.z + 1) * 0.55));
  }
}

// ── Interface ──────────────────────────────────────────────────────────────""",
    'fonctions communautes + etiquettes')

# ── 5. câblage des contrôles ─────────────────────────────────────────────────
sub(
    "toggle('sw-spin', 'spin');",
    """toggle('sw-spin', 'spin');
toggle('sw-etiq', 'etiquettes');
document.getElementById('sw-comm').onclick = function () {
  this.classList.toggle('on');
  basculerVue(this.classList.contains('on'));
};

// Curseur temporel : 0 = tout, puis fenêtres de plus en plus courtes.
const FENETRES = [-1, 180, 90, 30, 7];
document.getElementById('temps').oninput = e => {
  ageMax = FENETRES[+e.target.value];
  document.getElementById('temps-l').textContent =
    ageMax < 0 ? 'tout l historique'
      : ageMax >= 30 ? `${Math.round(ageMax / 30)} mois`
        : `${ageMax} jours`;
  applyDim();
};""",
    'controles')

# ── 6. étiquettes dans la boucle ─────────────────────────────────────────────
sub(
    "  renderer.render(scene, camera);\n\n  fpsAcc += dt; fpsN++;",
    "  renderer.render(scene, camera);\n  placerEtiquettes();\n\n  fpsAcc += dt; fpsN++;",
    'boucle')

# ── 7. le masquage des liens doit connaître la vue courante ──────────────────
sub(
    "toggle('sw-links', 'links', () => { lines.visible = !!state.links; applyDim(); });",
    """toggle('sw-links', 'links', () => {
  lines.visible = !vueComm && !!state.links;
  if (cLines) cLines.visible = vueComm && !!state.links;
  applyDim();
});""",
    'masquage des liens')

p.write_text(t, encoding='utf-8')
print('\necu.js mis a jour')
