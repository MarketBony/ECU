/* ECU — Engine Control Unit
 * Réseau de connaissance des projets Bony auto-mobile.
 *
 * Pourquoi c'est rapide :
 *   - les deux dispositions 3D sont PRÉCALCULÉES hors ligne (_layout3d.py) et
 *     figées ; aucune simulation de forces ne tourne dans le navigateur.
 *   - tous les nœuds forment UN seul THREE.Points, toutes les arêtes UN seul
 *     THREE.LineSegments : 2 appels de dessin pour 3 663 nœuds et 6 973 liens.
 *   - lueur et impulsion sont calculées en fragment shader, pas en
 *     post-traitement : le coût est en pixels, pas en objets.
 *
 * Charte Bony (brandbook.pdf p.24-25, retrouvée via le réseau lui-même) :
 * #f75632 → #8f12ab, bleu nuit #293f74.
 */
import * as THREE from './vendor/three.module.min.js';

const BONY = { orange: 0xf75632, violet: 0x8f12ab, nuit: 0x4a6bbd, magenta: 0xd4327a };

// Tranches d'ancienneté, du plus frais au plus dormant.
const AGES = [
  { l: 'moins de 7 j', max: 7, c: 0xff6a3d },
  { l: '7 à 30 j', max: 30, c: 0xf0417a },
  { l: '1 à 3 mois', max: 90, c: 0xb9259c },
  { l: '3 à 6 mois', max: 180, c: 0x8f12ab },
  { l: 'plus de 6 mois', max: 1e9, c: 0x4a6bbd },
  { l: 'date inconnue', max: null, c: 0x55556a },
];

// ── Palette ────────────────────────────────────────────────────────────────
// Arc de marque : orange (18°) → bleu nuit (220°) en DESCENDANT par le rouge,
// le magenta et le violet. Monter par le jaune et le vert sortirait de la charte.
//
// Limite assumée : au-delà d'une douzaine de catégories, deux teintes voisines
// de cet arc deviennent difficiles à distinguer. C'est le prix de la charte —
// et c'est pourquoi la légende reste filtrable au clic.
function palette(n) {
  const out = [];
  if (n <= 4) {
    const base = [BONY.orange, BONY.violet, BONY.nuit, BONY.magenta];
    for (let i = 0; i < n; i++) out.push(new THREE.Color(base[i]));
    return out;
  }
  for (let i = 0; i < n; i++) {
    const t = (i * 0.6180339887) % 1;              // suite dorée : voisins contrastés
    const hue = ((18 - t * 158) + 360) % 360;
    const sat = 0.66 + ((i * 7) % 5) * 0.055;
    const lig = 0.55 + ((i * 3) % 4) * 0.065;
    out.push(new THREE.Color().setHSL(hue / 360, Math.min(sat, 0.93), Math.min(lig, 0.76)));
  }
  return out;
}

// ── Shaders ────────────────────────────────────────────────────────────────
const NODE_VERT = `
attribute float aSize;
attribute vec3  aColor;
attribute float aDim;
attribute float aHot;
varying vec3  vColor;
varying float vDim;
varying float vHot;
uniform float uScale;
uniform float uBoost;
uniform float uMaxSize;
void main() {
  vColor = aColor; vDim = aDim; vHot = aHot;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  float s = aSize * uBoost * (1.0 + aHot * 0.7) * uScale / max(-mv.z, 1.0);
  // Plafond : sans lui, un hub proche de la caméra couvre un quart de l'écran
  // en pixels translucides additifs, et le coût de remplissage effondre la
  // fréquence d'images sans rien apporter de lisible.
  gl_PointSize = clamp(s, 1.0, uMaxSize);
  gl_Position = projectionMatrix * mv;
}`;

const NODE_FRAG = `
varying vec3  vColor;
varying float vDim;
varying float vHot;
uniform float uOpacity;
void main() {
  vec2 c = gl_PointCoord - 0.5;
  float d = length(c);
  if (d > 0.5) discard;
  float core = smoothstep(0.48, 0.05, d);
  float halo = exp(-d * d * 11.0) - 0.03;
  float a = (core * 0.92 + max(halo, 0.0) * 0.6) * uOpacity;
  vec3 col = mix(vColor, vec3(1.0), core * core * 0.42);
  col = mix(col, vec3(1.0, 0.95, 0.88), vHot * 0.55);   // nœud d'un chemin tracé
  // 0,11 et non 0,05 : un chemin trace ne doit pas faire disparaitre le
  // reseau, sinon on perd le contexte qui donne son sens au chemin.
  a *= mix(1.0, 0.11, vDim);
  a *= 1.0 + vHot * 0.8;
  if (a < 0.004) discard;
  gl_FragColor = vec4(col, a);
}`;

const LINK_VERT = `
attribute vec3  aColor;
attribute float aT;
attribute float aPhase;
attribute float aDim;
attribute float aConf;   // 0 = EXTRACTED, 1 = INFERRED
attribute float aHot;
varying vec3  vColor;
varying float vT;
varying float vPhase;
varying float vDim;
varying float vConf;
varying float vHot;
void main() {
  vColor = aColor; vT = aT; vPhase = aPhase; vDim = aDim; vConf = aConf; vHot = aHot;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

// L'impulsion dit quelque chose de vrai : sur un lien EXTRACTED (lu tel quel dans
// la source) elle est rapide, brève et blanche — une certitude. Sur un lien
// INFERRED (déduit par graphify) elle est lente, large et reste teintée : une
// hypothèse qui circule plus mollement.
const LINK_FRAG = `
varying vec3  vColor;
varying float vT;
varying float vPhase;
varying float vDim;
varying float vConf;
varying float vHot;
uniform float uTime;
uniform float uPulse;
uniform float uBase;
void main() {
  float vitesse  = mix(0.26, 0.09, vConf);
  float etroit   = mix(320.0, 46.0, vConf);
  float eclat    = mix(0.95, 0.42, vConf);
  float blanc    = mix(0.70, 0.18, vConf);

  float p = fract(uTime * vitesse + vPhase);
  float d = vT - p;
  d -= floor(d + 0.5);
  float pulse = exp(-d * d * etroit) * uPulse;

  float a = uBase * mix(1.0, 0.72, vConf) + pulse * eclat;
  vec3 col = mix(vColor, vec3(1.0, 0.94, 0.88), pulse * blanc);

  // arête appartenant au chemin tracé : toujours vive, quoi qu'il arrive
  a = mix(a, max(a, 0.82), vHot);
  col = mix(col, vec3(1.0, 0.86, 0.72), vHot * 0.5);

  a *= mix(1.0, 0.07, vDim);
  if (a < 0.004) discard;
  gl_FragColor = vec4(col, a);
}`;

// ── Scène ──────────────────────────────────────────────────────────────────
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(55, innerWidth / innerHeight, 1, 30000);
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
// 1,5 suffit largement pour des points flous : au-delà on quadruple le nombre
// de pixels a remplir sans gain visible sur un rendu additif.
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.setClearColor(0x000000, 0);
document.body.appendChild(renderer.domElement);

let DATA, NODES, LINKS, nodeGeo, linkGeo, nodeMat, linkMat, points, lines;
let colorMode = 'r', hidden = new Set(), focusIdx = -1;
let neighbours = null, adjacency = null, colors = [];
let pathNodes = null, pathLinks = null, armPath = false;
let morph = null;   // { t, from, to } pendant une bascule de disposition
let layout = 'p';

const state = { pulse: 1, links: 1, inferred: 1, spin: 1, etiquettes: 1 };

// Filtre temporel : -1 = pas de filtre, sinon âge maximum en jours.
let ageMax = -1;
// Vue communautés : les 3 663 nœuds repliés en ~300 amas nommés.
let vueComm = false;
let cPoints = null, cLines = null, cGeo = null, cLinkGeo = null;
// Étiquettes DOM des plus grosses masses.
let etiquettes = [], topIdx = [];

// ── Contrôles caméra (maison : pas de dépendance) ──────────────────────────
const cam = { target: new THREE.Vector3(), radius: 2600, theta: 0.6, phi: 1.15, spin: 0.018 };
const maison = { target: new THREE.Vector3(), radius: 2600, theta: 0.6, phi: 1.15 };
let drag = null, idle = 0;

/** Ramène la caméra au cadrage d'origine, en douceur. */
function recentrer() {
  pathNodes = pathLinks = null;
  const t0 = performance.now();
  const from = cam.target.clone();
  const r0 = cam.radius, th0 = cam.theta, ph0 = cam.phi;
  // angle le plus court : sans ça, revenir peut faire trois tours
  let dTheta = (maison.theta - th0) % (Math.PI * 2);
  if (dTheta > Math.PI) dTheta -= Math.PI * 2;
  if (dTheta < -Math.PI) dTheta += Math.PI * 2;
  (function pas() {
    const k = Math.min(1, (performance.now() - t0) / 850);
    const e = k < 0.5 ? 4 * k ** 3 : 1 - Math.pow(-2 * k + 2, 3) / 2;
    cam.target.lerpVectors(from, maison.target, e);
    cam.radius = r0 + (maison.radius - r0) * e;
    cam.theta = th0 + dTheta * e;
    cam.phi = ph0 + (maison.phi - ph0) * e;
    applyCamera();
    if (k < 1) requestAnimationFrame(pas);
  })();
  applyDim();
}

function applyCamera() {
  const sp = Math.max(0.05, Math.min(Math.PI - 0.05, cam.phi));
  camera.position.set(
    cam.target.x + cam.radius * Math.sin(sp) * Math.cos(cam.theta),
    cam.target.y + cam.radius * Math.cos(sp),
    cam.target.z + cam.radius * Math.sin(sp) * Math.sin(cam.theta),
  );
  camera.lookAt(cam.target);
}

const el = renderer.domElement;
el.addEventListener('contextmenu', e => e.preventDefault());
el.addEventListener('pointerdown', e => {
  el.setPointerCapture(e.pointerId);
  drag = { x: e.clientX, y: e.clientY, btn: e.button, moved: 0 };
  idle = 0;
});
el.addEventListener('pointermove', e => {
  if (!drag) return;
  const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
  drag.x = e.clientX; drag.y = e.clientY;
  drag.moved += Math.abs(dx) + Math.abs(dy);
  idle = 0;
  if (drag.btn === 2 || e.shiftKey) {
    const right = new THREE.Vector3().setFromMatrixColumn(camera.matrix, 0);
    const up = new THREE.Vector3().setFromMatrixColumn(camera.matrix, 1);
    const k = cam.radius * 0.0013;
    cam.target.addScaledVector(right, -dx * k).addScaledVector(up, dy * k);
  } else {
    cam.theta -= dx * 0.005;
    cam.phi -= dy * 0.005;
  }
  applyCamera();
});
addEventListener('pointerup', e => {
  if (drag && drag.moved < 5) {
    if (drag.btn === 0) pick(e.clientX, e.clientY);
    else if (drag.btn === 2) { const i = nearest(e.clientX, e.clientY); if (i >= 0) copierCommande(i); }
  }
  drag = null;
});
el.addEventListener('wheel', e => {
  e.preventDefault();
  cam.radius = Math.max(60, Math.min(11000, cam.radius * (1 + Math.sign(e.deltaY) * 0.11)));
  idle = 0;
  applyCamera();
}, { passive: false });

// ── Sélection : projection écran, plus fiable qu'un raycast sur Points ─────
const _v = new THREE.Vector3();
function nearest(cx, cy) {
  if (!NODES) return -1;
  const r = renderer.domElement.getBoundingClientRect();
  const hw = r.width / 2, hh = r.height / 2;
  let best = -1, bestD = 26 * 26;
  camera.updateMatrixWorld();
  const vp = new THREE.Matrix4().multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
  const pos = nodeGeo.getAttribute('position');
  for (let i = 0; i < NODES.length; i++) {
    if (hidden.has(groupKey(NODES[i]))) continue;
    _v.set(pos.getX(i), pos.getY(i), pos.getZ(i)).applyMatrix4(vp);
    if (_v.z < -1 || _v.z > 1) continue;
    const sx = (_v.x * hw) + hw, sy = (-_v.y * hh) + hh;
    const dx = sx - (cx - r.left), dy = sy - (cy - r.top);
    const d = dx * dx + dy * dy;
    if (d < bestD) { bestD = d; best = i; }
  }
  return best;
}

function pick(cx, cy) {
  const i = nearest(cx, cy);
  if (i < 0) { clearSelection(); return; }
  if (armPath && focusIdx >= 0 && i !== focusIdx) { tracerChemin(focusIdx, i); return; }
  select(i);
}

// ── Groupes et couleurs ────────────────────────────────────────────────────
function ageBucket(a) {
  if (a < 0) return AGES.length - 1;
  for (let i = 0; i < AGES.length - 1; i++) if (a < AGES[i].max) return i;
  return AGES.length - 2;
}
function groupKey(n) {
  return colorMode === 'r' ? n.r : colorMode === 'c' ? n.c
    : colorMode === 't' ? n.t : ageBucket(n.a);
}
function groupList() {
  return colorMode === 'r' ? DATA.repos : colorMode === 'c' ? DATA.comms
    : colorMode === 't' ? DATA.types : AGES.map(a => a.l);
}

function recolor() {
  const keys = groupList();
  colors = colorMode === 'a' ? AGES.map(a => new THREE.Color(a.c)) : palette(keys.length);
  // Couleurs choisies à la main : elles écrasent la charte, volontairement.
  // Indexées par LIBELLÉ et jamais par rang — Louvain renumérote les communautés
  // à chaque recalcul, un index aurait recoloré n'importe quoi le lendemain.
  const perso = teintes[colorMode] || {};
  for (let i = 0; i < keys.length; i++) {
    if (perso[keys[i]]) colors[i] = new THREE.Color(perso[keys[i]]);
  }
  const col = nodeGeo.getAttribute('aColor');
  for (let i = 0; i < NODES.length; i++) {
    const c = colors[groupKey(NODES[i])] || colors[0];
    col.setXYZ(i, c.r, c.g, c.b);
  }
  col.needsUpdate = true;

  const lc = linkGeo.getAttribute('aColor');
  for (let i = 0; i < LINKS.length; i++) {
    const [s, t] = LINKS[i];
    const a = colors[groupKey(NODES[s])] || colors[0];
    const b = colors[groupKey(NODES[t])] || colors[0];
    lc.setXYZ(i * 2, a.r, a.g, a.b);
    lc.setXYZ(i * 2 + 1, b.r, b.g, b.b);
  }
  lc.needsUpdate = true;
  applyDim();
}

function applyDim() {
  const nd = nodeGeo.getAttribute('aDim');
  const nh = nodeGeo.getAttribute('aHot');
  const ld = linkGeo.getAttribute('aDim');
  const lh = linkGeo.getAttribute('aHot');

  for (let i = 0; i < NODES.length; i++) {
    let d = hidden.has(groupKey(NODES[i])) ? 1 : 0;
    // Filtre temporel : un nœud sans date connue est traité comme ancien —
    // prétendre l'inverse ferait passer de l'ignorance pour de la fraîcheur.
    if (!d && ageMax >= 0 && (NODES[i].a < 0 || NODES[i].a > ageMax)) d = 1;
    if (!d && pathNodes) d = pathNodes.has(i) ? 0 : 1;
    else if (!d && focusIdx >= 0 && i !== focusIdx && !neighbours.has(i)) d = 1;
    nd.setX(i, d);
    nh.setX(i, pathNodes && pathNodes.has(i) ? 1 : 0);
  }
  for (let i = 0; i < LINKS.length; i++) {
    const [s, t, inf] = LINKS[i];
    let d = 0;
    if (!state.links) d = 1;
    else if (inf && !state.inferred) d = 1;
    else if (hidden.has(groupKey(NODES[s])) || hidden.has(groupKey(NODES[t]))) d = 1;
    else if (ageMax >= 0 && !(NODES[s].a >= 0 && NODES[s].a <= ageMax
                           && NODES[t].a >= 0 && NODES[t].a <= ageMax)) d = 1;
    else if (pathLinks) d = pathLinks.has(i) ? 0 : 1;
    else if (focusIdx >= 0 && s !== focusIdx && t !== focusIdx) d = 1;
    ld.setX(i * 2, d); ld.setX(i * 2 + 1, d);
    const hot = pathLinks && pathLinks.has(i) ? 1 : 0;
    lh.setX(i * 2, hot); lh.setX(i * 2 + 1, hot);
  }
  nd.needsUpdate = true; nh.needsUpdate = true;
  ld.needsUpdate = true; lh.needsUpdate = true;
}

/** Taille de fichier lisible : 12,4 Ko plutôt que 12698. */
const poids = o => o < 1024 ? `${o} o`
  : o < 1048576 ? `${(o / 1024).toFixed(1).replace('.', ',')} Ko`
    : `${(o / 1048576).toFixed(1).replace('.', ',')} Mo`;

const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function buildLegend() {
  const keys = groupList();
  const counts = new Array(keys.length).fill(0);
  for (const n of NODES) counts[groupKey(n)]++;
  const order = colorMode === 'a'
    ? keys.map((k, i) => i)
    : keys.map((k, i) => i).sort((a, b) => counts[b] - counts[a]).slice(0, 60);
  const box = document.getElementById('legend');
  box.innerHTML = '';
  for (const i of order) {
    if (colorMode === 'a' && !counts[i]) continue;
    const d = document.createElement('div');
    d.className = 'lg' + (hidden.has(i) ? ' off' : '');
    const c = colors[i];
    const perso = (teintes[colorMode] || {})[keys[i]] ? ' perso' : '';
    d.innerHTML = `<span class="dot${perso}" title="Choisir la couleur — clic droit pour revenir à l'origine" style="background:#${c.getHexString()};color:#${c.getHexString()}"></span>
                   <span class="nm">${esc(keys[i])}</span><span class="cnt">${counts[i]}</span>`;
    d.onclick = () => {
      hidden.has(i) ? hidden.delete(i) : hidden.add(i);
      d.classList.toggle('off');
      applyDim();
      ecrireReglages();
    };
    // La pastille court-circuite le filtre : deux gestes voisins, deux effets.
    const pastille = d.firstElementChild;
    pastille.onclick = e => { e.stopPropagation(); ouvrirTeinte(keys[i], c); };
    pastille.oncontextmenu = e => { e.preventDefault(); e.stopPropagation(); rendreTeinte(keys[i]); };
    box.appendChild(d);
  }
  majBoutonRaz();
}

// ── Couleurs choisies à la main ────────────────────────────────────────────
// La charte Bony tient sur un arc orange → violet ; au-delà d'une douzaine de
// catégories, deux teintes voisines deviennent indistinguables. Pouvoir sortir
// de l'arc n'est donc pas un caprice, c'est la seule échappatoire quand la
// lisibilité passe avant la marque. Le choix est gardé d'une session à l'autre.
let teinteCourante = null;

function ouvrirTeinte(cle, couleurActuelle) {
  teinteCourante = cle;
  const inp = document.getElementById('teinte');
  inp.value = '#' + couleurActuelle.getHexString();
  inp.click();
}

function poserTeinte(cle, hex) {
  (teintes[colorMode] = teintes[colorMode] || {})[cle] = hex;
  recolor(); buildLegend(); ecrireReglages();
}

function rendreTeinte(cle) {
  if (!teintes[colorMode] || !teintes[colorMode][cle]) return;
  delete teintes[colorMode][cle];
  if (!Object.keys(teintes[colorMode]).length) delete teintes[colorMode];
  recolor(); buildLegend(); ecrireReglages();
  toast(`« ${cle} » revient à sa couleur d'origine`);
}

function majBoutonRaz() {
  const n = Object.values(teintes).reduce((s, o) => s + Object.keys(o).length, 0);
  document.getElementById('legende-raz').classList.toggle('show', n > 0);
}

// ── Panneau d'inspection ───────────────────────────────────────────────────
function select(i) {
  pathNodes = pathLinks = null; armPath = false;
  focusIdx = i;
  majBoutonChemin();          // après focusIdx : c'est lui qui décide de l'affichage
  neighbours = new Set(adjacency[i].map(a => a[0]));
  applyDim();

  const n = NODES[i];
  document.getElementById('info').classList.add('show');
  document.getElementById('i-label').textContent = n.l;
  document.getElementById('i-file').textContent = n.f || '—';
  const age = n.a < 0 ? 'date inconnue'
    : n.a === 0 ? "modifié aujourd'hui"
      : `modifié il y a ${n.a} j`;
  document.getElementById('i-tags').innerHTML =
    `<span class="tag grad">${esc(DATA.repos[n.r])}</span>` +
    `<span class="tag">${esc(DATA.types[n.t])}</span>` +
    `<span class="tag">${esc(DATA.comms[n.c])}</span>` +
    `<span class="tag">${n.d} liens</span>` +
    `<span class="tag">${age}</span>` +
    (n.o ? `<span class="tag">${poids(n.o)}</span>` : '');

  const list = adjacency[i].slice().sort((a, b) => NODES[b[0]].d - NODES[a[0]].d);
  document.getElementById('i-n').textContent = `(${adjacency[i].length})`;
  const box = document.getElementById('i-cx');
  box.innerHTML = '';
  for (const [j, li] of list.slice(0, 80)) {
    const o = NODES[j];
    const row = document.createElement('div');
    row.className = 'cx';
    row.innerHTML = `<span class="ar">${LINKS[li][0] === i ? '→' : '←'}</span>
      <span class="nm">${esc(o.l)}<br><span class="rl">${esc(o.f || DATA.comms[o.c])}${LINKS[li][2] ? ' · inféré' : ''}</span></span>`;
    // Viser un nœud précis dans la 3D est pénible ; quand le mode chemin est
    // armé, la liste sert aussi de sélecteur d'arrivée.
    row.onclick = () => {
      if (armPath) tracerChemin(focusIdx, j);
      else { select(j); flyTo(j); }
    };
    box.appendChild(row);
  }
}

function clearSelection() {
  focusIdx = -1; neighbours = null; pathNodes = pathLinks = null; armPath = false;
  majBoutonChemin();
  document.getElementById('info').classList.remove('show');
  applyDim();
}

function flyTo(i) {
  const pos = nodeGeo.getAttribute('position');
  const to = new THREE.Vector3(pos.getX(i), pos.getY(i), pos.getZ(i));
  const from = cam.target.clone();
  const r0 = cam.radius, r1 = Math.max(180, Math.min(r0, 460));
  const t0 = performance.now();
  (function step() {
    const k = Math.min(1, (performance.now() - t0) / 700);
    const e = 1 - Math.pow(1 - k, 3);
    cam.target.lerpVectors(from, to, e);
    cam.radius = r0 + (r1 - r0) * e;
    applyCamera();
    if (k < 1) requestAnimationFrame(step);
  })();
}

// ── Chemin le plus court ───────────────────────────────────────────────────
function tracerChemin(a, b) {
  const prev = new Int32Array(NODES.length).fill(-1);
  const viaLink = new Int32Array(NODES.length).fill(-1);
  const vu = new Uint8Array(NODES.length);
  const file = [a]; vu[a] = 1;
  let trouve = false;
  for (let h = 0; h < file.length && !trouve; h++) {
    const cur = file[h];
    for (const [next, li] of adjacency[cur]) {
      if (vu[next]) continue;
      vu[next] = 1; prev[next] = cur; viaLink[next] = li;
      if (next === b) { trouve = true; break; }
      file.push(next);
    }
  }
  if (!trouve) { toast('Aucun chemin entre ces deux nœuds'); armPath = false; majBoutonChemin(); return; }

  pathNodes = new Set(); pathLinks = new Set();
  let cur = b;
  while (cur !== -1) {
    pathNodes.add(cur);
    if (viaLink[cur] >= 0) pathLinks.add(viaLink[cur]);
    cur = prev[cur];
  }
  armPath = false;
  majBoutonChemin();
  focusIdx = -1; neighbours = null;
  applyDim();

  // recadre sur l'ensemble du chemin
  const pos = nodeGeo.getAttribute('position');
  const box = new THREE.Box3();
  for (const i of pathNodes) box.expandByPoint(new THREE.Vector3(pos.getX(i), pos.getY(i), pos.getZ(i)));
  box.getCenter(cam.target);
  cam.radius = Math.max(340, box.getSize(new THREE.Vector3()).length() * 1.45);
  applyCamera();

  const ordre = [...pathNodes].reverse();
  document.getElementById('info').classList.add('show');
  document.getElementById('i-label').textContent = `Chemin — ${ordre.length - 1} saut${ordre.length > 2 ? 's' : ''}`;
  document.getElementById('i-file').textContent = `${NODES[a].l} → ${NODES[b].l}`;
  document.getElementById('i-tags').innerHTML = `<span class="tag grad">chemin le plus court</span>`;
  document.getElementById('i-n').textContent = `(${ordre.length})`;
  const bx = document.getElementById('i-cx');
  bx.innerHTML = '';
  ordre.forEach((i, k) => {
    const n = NODES[i];
    const row = document.createElement('div');
    row.className = 'cx';
    row.innerHTML = `<span class="ar">${k + 1}</span>
      <span class="nm">${esc(n.l)}<br><span class="rl">${esc(n.f || DATA.comms[n.c])}</span></span>`;
    row.onclick = () => flyTo(i);
    bx.appendChild(row);
  });
}

function majBoutonChemin() {
  const b = document.getElementById('btn-path');
  if (!b) return;
  b.classList.toggle('armed', armPath);
  b.textContent = armPath ? 'Clique le nœud d\'arrivée…' : 'Tracer un chemin depuis ici';
  b.style.display = focusIdx >= 0 ? '' : 'none';
}

// ── Commande graphify dans le presse-papier ────────────────────────────────
function copierCommande(i) {
  const n = NODES[i];
  const cmd = `graphify explain "${n.l.replace(/"/g, '\\"')}" --graph "$env:USERPROFILE\\.graphify\\global-graph.json"`;
  navigator.clipboard?.writeText(cmd)
    .then(() => toast('Commande copiée : graphify explain « ' + n.l.slice(0, 40) + ' »'))
    .catch(() => toast('Copie impossible (presse-papier refusé)'));
}

let toastT = null;
function toast(msg) {
  let t = document.getElementById('toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'toast'; t.className = 'glass';
    document.getElementById('ui').appendChild(t);
  }
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastT);
  toastT = setTimeout(() => t.classList.remove('show'), 3200);
}

// ── Bascule de disposition, par interpolation ──────────────────────────────
function setLayout(next) {
  if (next === layout || morph) return;
  const pos = nodeGeo.getAttribute('position');
  const from = new Float32Array(pos.array);
  const to = new Float32Array(NODES.length * 3);
  for (let i = 0; i < NODES.length; i++) {
    const p = NODES[i][next];
    to[i * 3] = p[0]; to[i * 3 + 1] = p[1]; to[i * 3 + 2] = p[2];
  }
  morph = { t: 0, from, to };
  layout = next;
}

function appliquerMorph(dt) {
  morph.t = Math.min(1, morph.t + dt / 1.1);
  const e = morph.t < 0.5 ? 4 * morph.t ** 3 : 1 - Math.pow(-2 * morph.t + 2, 3) / 2;
  const pos = nodeGeo.getAttribute('position');
  const arr = pos.array;
  for (let i = 0; i < arr.length; i++) arr[i] = morph.from[i] + (morph.to[i] - morph.from[i]) * e;
  pos.needsUpdate = true;

  const lp = linkGeo.getAttribute('position');
  const la = lp.array;
  for (let i = 0; i < LINKS.length; i++) {
    const s = LINKS[i][0] * 3, t = LINKS[i][1] * 3;
    la[i * 6] = arr[s]; la[i * 6 + 1] = arr[s + 1]; la[i * 6 + 2] = arr[s + 2];
    la[i * 6 + 3] = arr[t]; la[i * 6 + 4] = arr[t + 1]; la[i * 6 + 5] = arr[t + 2];
  }
  lp.needsUpdate = true;
  if (morph.t >= 1) { morph = null; nodeGeo.computeBoundingSphere(); linkGeo.computeBoundingSphere(); }
}

// ── Construction ───────────────────────────────────────────────────────────
async function build() {
  DATA = await (await fetch('data.json')).json();
  NODES = DATA.nodes; LINKS = DATA.links;

  document.getElementById('n-nodes').textContent = NODES.length.toLocaleString('fr-FR');
  document.getElementById('n-links').textContent = LINKS.length.toLocaleString('fr-FR');

  adjacency = Array.from({ length: NODES.length }, () => []);
  for (let i = 0; i < LINKS.length; i++) {
    adjacency[LINKS[i][0]].push([LINKS[i][1], i]);
    adjacency[LINKS[i][1]].push([LINKS[i][0], i]);
  }

  const N = NODES.length;
  const pos = new Float32Array(N * 3), col = new Float32Array(N * 3);
  const siz = new Float32Array(N), dim = new Float32Array(N), hot = new Float32Array(N);
  nodeGeo = new THREE.BufferGeometry();
  nodeGeo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  nodeGeo.setAttribute('aColor', new THREE.BufferAttribute(col, 3));
  nodeGeo.setAttribute('aSize', new THREE.BufferAttribute(siz, 1));
  nodeGeo.setAttribute('aDim', new THREE.BufferAttribute(dim, 1));
  nodeGeo.setAttribute('aHot', new THREE.BufferAttribute(hot, 1));
  for (let i = 0; i < N; i++) {
    const n = NODES[i];
    pos[i * 3] = n.p[0]; pos[i * 3 + 1] = n.p[1]; pos[i * 3 + 2] = n.p[2];
    // Galaxie : l'exposant creuse l'écart, mais 1,55 rendait la poussière
    // quasi invisible. 1,3 sur une base plus haute garde le contraste tout en
    // laissant les petits points exister.
    siz[i] = 9 + Math.pow(n.w ?? 0, 1.3) * 122;
  }
  nodeGeo.computeBoundingSphere();

  const box = new THREE.Box3().setFromBufferAttribute(nodeGeo.getAttribute('position'));
  box.getCenter(cam.target);
  cam.radius = box.getSize(new THREE.Vector3()).length() * 0.88;
  // Point de retour : une fois qu'on s'est promené, la rotation auto reprend
  // autour d'un centre arbitraire et on ne sait plus revenir. On mémorise.
  maison.target.copy(cam.target);
  maison.radius = cam.radius;

  nodeMat = new THREE.ShaderMaterial({
    uniforms: {
      uScale: { value: innerHeight * 0.55 }, uOpacity: { value: 1 },
      uBoost: { value: 1 }, uMaxSize: { value: 34 },
    },
    vertexShader: NODE_VERT, fragmentShader: NODE_FRAG,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
  points = new THREE.Points(nodeGeo, nodeMat);
  points.frustumCulled = false;
  scene.add(points);

  const L = LINKS.length;
  const lp = new Float32Array(L * 6), lc = new Float32Array(L * 6);
  const lt = new Float32Array(L * 2), lph = new Float32Array(L * 2);
  const ld = new Float32Array(L * 2), lcf = new Float32Array(L * 2), lh = new Float32Array(L * 2);
  linkGeo = new THREE.BufferGeometry();
  linkGeo.setAttribute('position', new THREE.BufferAttribute(lp, 3));
  linkGeo.setAttribute('aColor', new THREE.BufferAttribute(lc, 3));
  linkGeo.setAttribute('aT', new THREE.BufferAttribute(lt, 1));
  linkGeo.setAttribute('aPhase', new THREE.BufferAttribute(lph, 1));
  linkGeo.setAttribute('aDim', new THREE.BufferAttribute(ld, 1));
  linkGeo.setAttribute('aConf', new THREE.BufferAttribute(lcf, 1));
  linkGeo.setAttribute('aHot', new THREE.BufferAttribute(lh, 1));
  for (let i = 0; i < L; i++) {
    const [s, t, inf] = LINKS[i];
    const a = NODES[s].p, b = NODES[t].p;
    lp[i * 6] = a[0]; lp[i * 6 + 1] = a[1]; lp[i * 6 + 2] = a[2];
    lp[i * 6 + 3] = b[0]; lp[i * 6 + 4] = b[1]; lp[i * 6 + 5] = b[2];
    lt[i * 2] = 0; lt[i * 2 + 1] = 1;
    const ph = (i * 0.6180339887) % 1;
    lph[i * 2] = ph; lph[i * 2 + 1] = ph;
    lcf[i * 2] = inf; lcf[i * 2 + 1] = inf;
  }
  linkGeo.computeBoundingSphere();

  linkMat = new THREE.ShaderMaterial({
    uniforms: { uTime: { value: 0 }, uPulse: { value: 1 }, uBase: { value: 0.14 } },
    vertexShader: LINK_VERT, fragmentShader: LINK_FRAG,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
  lines = new THREE.LineSegments(linkGeo, linkMat);
  lines.frustumCulled = false;
  scene.add(lines);

  construireCommunautes();
  construireEtiquettes();
  recolor();
  buildLegend();
  majBoutonChemin();
  appliquerQualite('equilibre');
  applyCamera();
  document.getElementById('boot').classList.add('gone');
  setTimeout(() => document.getElementById('boot')?.remove(), 700);
}

// ── Vue communautés ────────────────────────────────────────────────────────
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
    topIdx.forEach(i => ajouterEtiquette(box, DATA.repos[C[i].r], C[i].l));
  } else {
    topIdx = NODES.map((n, i) => i).sort((a, b) => (NODES[b].w ?? 0) - (NODES[a].w ?? 0)).slice(0, COMBIEN);
    topIdx.forEach(i => ajouterEtiquette(box, DATA.repos[NODES[i].r], NODES[i].l));
  }
}

// Deux niveaux : le PROJET en gros, le fichier en dessous. Un nom de fichier
// seul — « 10_garages.sql » — ne dit rien tant qu'on ignore d'où il sort.
function ajouterEtiquette(box, projet, detail) {
  const d = document.createElement('div');
  d.className = 'etiq';
  const p = document.createElement('b');
  p.textContent = projet;
  const s = document.createElement('span');
  s.textContent = detail;
  d.append(p, s);
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

// ── Interface ──────────────────────────────────────────────────────────────
document.getElementById('close').onclick = clearSelection;
document.getElementById('btn-home').onclick = recentrer;
addEventListener('keydown', e => {
  if (e.key === 'Escape') clearSelection();
  // R comme recentrer — mais pas pendant qu'on tape dans la recherche
  if ((e.key === 'r' || e.key === 'R') && e.target.tagName !== 'INPUT') recentrer();
  if ((e.key === 'h' || e.key === 'H') && e.target.tagName !== 'INPUT') {
    majHisto(!histoBox.classList.contains('show'), false);
  }
});

document.getElementById('mode').onchange = e => {
  colorMode = e.target.value; hidden.clear(); recolor(); buildLegend(); ecrireReglages();
};
document.getElementById('layout').onchange = e => { setLayout(e.target.value); ecrireReglages(); };

document.getElementById('btn-path').onclick = () => {
  if (focusIdx < 0) return;
  armPath = !armPath;
  majBoutonChemin();
  if (armPath) toast('Clique maintenant le nœud d\'arrivée');
};

document.getElementById('q').oninput = e => {
  const q = e.target.value.trim().toLowerCase();
  if (q.length < 2) return;
  let best = -1, bestScore = 1e9;
  for (let i = 0; i < NODES.length; i++) {
    const n = NODES[i];
    const pl = n.l.toLowerCase().indexOf(q);
    const pf = (n.f || '').toLowerCase().indexOf(q);
    let score = 1e9;
    if (pl >= 0) score = pl; else if (pf >= 0) score = 100 + pf;
    if (score < bestScore || (score === bestScore && best >= 0 && n.d > NODES[best].d)) {
      bestScore = score; best = i;
    }
  }
  if (best < 0) return;
  // Mode chemin armé : la recherche désigne l'arrivée. C'est le cas d'usage
  // réel — « de useAuth à prisma » — sans avoir à viser un point dans la 3D.
  if (armPath && focusIdx >= 0 && best !== focusIdx) tracerChemin(focusIdx, best);
  else { select(best); flyTo(best); }
};

const bascules = {};
function toggle(id, key, after) {
  const b = document.getElementById(id);
  bascules[key] = b;          // pour pouvoir les remettre comme on les a laissées
  b.onclick = () => {
    state[key] = state[key] ? 0 : 1;
    b.classList.toggle('on', !!state[key]);
    after && after();
    ecrireReglages();
  };
}
toggle('sw-pulse', 'pulse');
// Masquer les liens doit VRAIMENT cesser de les dessiner. Les atténuer via aDim
// laissait le fragment shader tourner sur chacun d'eux : aucun gain.
toggle('sw-links', 'links', () => {
  lines.visible = !vueComm && !!state.links;
  if (cLines) cLines.visible = vueComm && !!state.links;
  applyDim();
});
toggle('sw-inf', 'inferred', applyDim);
toggle('sw-spin', 'spin');
toggle('sw-etiq', 'etiquettes');
document.getElementById('sw-comm').onclick = function () {
  this.classList.toggle('on');
  basculerVue(this.classList.contains('on'));
  ecrireReglages();
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
  ecrireReglages();
};

// ── Qualité ────────────────────────────────────────────────────────────────
// Sur un GPU intégré, le coût dominant est le remplissage : des milliers de
// halos translucides additifs, sans rejet de profondeur possible. Les trois
// niveaux jouent sur la résolution, la taille des halos et l'impulsion.
const QUALITES = {
  haute:     { dpr: 1.5, taille: 38, pulse: 1, base: 0.14, flou: '22px' },
  equilibre: { dpr: 1.0, taille: 30, pulse: 1, base: 0.12, flou: '16px' },
  fluide:    { dpr: 1.0, taille: 22, pulse: 0, base: 0.20, flou: '10px' },
};
let qualite = 'equilibre';

function appliquerQualite(q) {
  qualite = q;
  const k = QUALITES[q];
  renderer.setPixelRatio(Math.min(devicePixelRatio, k.dpr));
  renderer.setSize(innerWidth, innerHeight);
  nodeMat.uniforms.uMaxSize.value = k.taille;
  linkMat.uniforms.uBase.value = k.base;
  state.pulse = k.pulse;
  document.getElementById('sw-pulse').classList.toggle('on', !!k.pulse);
  document.documentElement.style.setProperty('--glass-blur', k.flou);
  const sel = document.getElementById('qualite');
  if (sel && sel.value !== q) sel.value = q;
}

document.getElementById('qualite').onchange = e => {
  autoQualite = false; appliquerQualite(e.target.value); ecrireReglages();
};

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
  if (nodeMat) nodeMat.uniforms.uScale.value = innerHeight * 0.55;
});

// ── Boucle ─────────────────────────────────────────────────────────────────
let last = performance.now(), fpsAcc = 0, fpsN = 0;
let autoQualite = true;
const echantillons = [];
const fpsEl = document.getElementById('fps');

function loop(now) {
  requestAnimationFrame(loop);
  const dt = Math.min((now - last) / 1000, 0.1); last = now;

  if (morph) appliquerMorph(dt);

  if (linkMat) {
    linkMat.uniforms.uTime.value += dt;
    const target = state.pulse && state.links ? 1 : 0;
    const u = linkMat.uniforms.uPulse;
    u.value += (target - u.value) * Math.min(1, dt * 6);
  }

  if (state.spin && !drag && !morph) {
    idle += dt;
    if (idle > 1.2) { cam.theta += cam.spin * dt; applyCamera(); }
  }

  renderer.render(scene, camera);
  placerEtiquettes();

  fpsAcc += dt; fpsN++;
  if (fpsAcc >= 0.5) {
    const fps = fpsN / fpsAcc;
    fpsEl.textContent = Math.round(fps) + ' i/s';
    fpsEl.style.color = fps < 30 ? '#f75632' : fps < 50 ? '#c1348c' : '';
    // Réglage automatique : on descend d'un cran tant que ça n'est pas fluide,
    // et on le dit. L'utilisateur reprend la main dès qu'il touche au sélecteur.
    if (autoQualite && !morph) {
      echantillons.push(fps);
      if (echantillons.length >= 4) {
        const median = echantillons.slice().sort((a, b) => a - b)[2];
        echantillons.length = 0;
        if (median < 40 && qualite === 'haute') {
          appliquerQualite('equilibre');
          toast('Qualité ajustée : équilibrée (' + Math.round(median) + ' i/s)');
        } else if (median < 32 && qualite === 'equilibre') {
          appliquerQualite('fluide');
          toast('Qualité ajustée : fluide — impulsions coupées (' + Math.round(median) + ' i/s)');
        } else if (median > 56 && qualite === 'equilibre') {
          appliquerQualite('haute');
          autoQualite = false;
        } else if (median >= 32) {
          autoQualite = false;   // stable : on arrête de tripoter
        }
      }
    }
    fpsAcc = 0; fpsN = 0;
  }
}

// ── Réglages retenus d'une session à l'autre ───────────────────────────────
// Recharger la page pour prendre les nouvelles données remettait TOUT à zéro :
// mode de couleur, disposition, qualité, filtre temporel, bascules, groupes
// masqués. Autrement dit, le bandeau « recharger » punissait celui qui l'écoute.
// Une application ne perd pas ce qu'on vient de régler.
const CLE_REGLAGES = 'ecu-reglages';
let teintes = {};

function lireReglages() {
  try { return JSON.parse(localStorage.getItem(CLE_REGLAGES) || '{}'); }
  catch (e) { return {}; }
}

function ecrireReglages() {
  try {
    localStorage.setItem(CLE_REGLAGES, JSON.stringify({
      colorMode, layout, qualite, ageMax, vueComm, teintes,
      etats: { ...state },
      // Les groupes masqués sont retenus par LIBELLÉ. Les index changent au
      // prochain recalcul du graphe et masqueraient alors autre chose.
      masques: [...hidden].map(i => groupList()[i]).filter(Boolean),
      histo: {
        ouvert: histoBox.classList.contains('show'),
        reduit: histoBox.classList.contains('reduit'),
      },
    }));
  } catch (e) { /* navigation privée : les réglages ne survivront pas, tant pis */ }
}

function appliquerReglages() {
  const r = lireReglages();
  teintes = (r.teintes && typeof r.teintes === 'object') ? r.teintes : {};

  if (r.colorMode) {
    colorMode = r.colorMode;
    document.getElementById('mode').value = colorMode;
  }
  // La qualité pose state.pulse : elle passe AVANT les bascules, sinon elle
  // écraserait le choix de l'utilisateur au lieu de lui servir de défaut.
  if (r.qualite && QUALITES[r.qualite]) { autoQualite = false; appliquerQualite(r.qualite); }
  if (r.layout && r.layout !== layout) {
    document.getElementById('layout').value = r.layout;
    setLayout(r.layout);
  }
  if (typeof r.ageMax === 'number' && FENETRES.includes(r.ageMax)) {
    const curseur = document.getElementById('temps');
    curseur.value = String(FENETRES.indexOf(r.ageMax));
    curseur.dispatchEvent(new Event('input'));
  }
  if (r.etats) {
    for (const k of Object.keys(bascules)) {
      if (typeof r.etats[k] === 'number' && !!r.etats[k] !== !!state[k]) bascules[k].click();
    }
  }
  if (r.vueComm) document.getElementById('sw-comm').click();

  // Recolorer AVANT de résoudre les masques : les libellés se cherchent dans la
  // liste du mode restauré, pas dans celle du mode par défaut.
  recolor();
  if (Array.isArray(r.masques) && r.masques.length) {
    const keys = groupList();
    hidden = new Set(r.masques.map(l => keys.indexOf(l)).filter(i => i >= 0));
    applyDim();
  }
  buildLegend();

  const h = r.histo || {};
  majHisto(!!h.ouvert, !!h.reduit);
}

document.getElementById('teinte').oninput = e => {
  if (teinteCourante !== null) poserTeinte(teinteCourante, e.target.value);
};
document.getElementById('legende-raz').onclick = () => {
  teintes = {};
  recolor(); buildLegend(); ecrireReglages();
  toast('Toutes les couleurs sont revenues à la charte Bony');
};

// ── Installer ECU comme application ────────────────────────────────────────
// Tant qu'ECU n'est pas installé, Chrome range sa fenêtre sous l'icône Chrome —
// c'est Chrome qui décide, aucun réglage de raccourci ne le contourne. Chrome
// signale lui-même qu'une installation est possible ; on transforme ce signal
// en un bouton, au lieu d'un mode d'emploi dans une console que le lanceur
// silencieux ne montre plus.
let invite = null;
const boutonInstall = document.getElementById('btn-install');
addEventListener('beforeinstallprompt', e => {
  e.preventDefault();
  invite = e;
  boutonInstall.classList.add('show');
});
// Pas de filet qui forcerait le bouton : Chrome ne propose l'installation que
// si l'application ne l'est PAS encore. La version précédente l'affichait de
// force au bout de 4 s — donc aussi dans ECU déjà installé, où il n'avait plus
// rien à faire. Si l'événement ne vient pas, c'est que la question est réglée.

boutonInstall.onclick = async () => {
  if (!invite) {
    toast('Menu ⋮ de la fenêtre → Ouvrir dans Chrome → icône d\'installation dans la barre d\'adresse');
    return;
  }
  boutonInstall.disabled = true;
  invite.prompt();
  const { outcome } = await invite.userChoice;
  invite = null;
  boutonInstall.disabled = false;
  if (outcome === 'accepted') {
    boutonInstall.classList.remove('show');
    toast('ECU installé — relance-le par son icône pour avoir son logo dans la barre des tâches');
  }
};
addEventListener('appinstalled', () => {
  invite = null;
  boutonInstall.classList.remove('show');
});

// ── Historique des nœuds ───────────────────────────────────────────────────
// Les commits des trois dépôts, fusionnés et datés par _layout3d.py. Cliquer un
// commit éclaire les nœuds qu'il a touchés : c'est ce qui en fait un historique
// DU RÉSEAU, et pas un journal git de plus posé à côté.

/** « il y a 3 j » — la date exacte reste en infobulle, pour qui la cherche. */
function depuis(ts) {
  const s = Date.now() / 1000 - ts;
  if (s < 3600) return `il y a ${Math.max(1, Math.round(s / 60))} min`;
  if (s < 86400) return `il y a ${Math.round(s / 3600)} h`;
  const j = Math.round(s / 86400);
  if (j < 31) return `il y a ${j} j`;
  if (j < 365) return `il y a ${Math.round(j / 30)} mois`;
  return `il y a ${(j / 365).toFixed(1).replace('.', ',')} ans`;
}

const dateExacte = ts =>
  new Date(ts * 1000).toLocaleString('fr-FR', { dateStyle: 'full', timeStyle: 'short' });

let commitActif = -1;

function buildHistorique() {
  const hist = DATA.hist || [];
  const box = document.getElementById('hlist');
  document.getElementById('h-n').textContent = hist.length ? `${hist.length} commits` : '';
  box.innerHTML = '';
  if (!hist.length) {
    box.innerHTML = '<div class="cm"><span class="co"><span class="me">Aucun commit lu — '
      + 'relance ECU pour reconstruire l\'historique.</span></span></div>';
    return;
  }
  // Une teinte par projet, indépendante du mode de couleur courant : dans
  // l'historique la pastille veut toujours dire « quel dépôt », même quand la
  // galaxie est colorée par ancienneté ou par communauté.
  const teintes = palette(DATA.repos.length).map(c => '#' + c.getHexString());
  hist.forEach((c, k) => {
    const el = document.createElement('div');
    el.className = 'cm';
    const t = teintes[c.r] || '#8a8a96';
    el.innerHTML =
      `<span class="pt" style="background:${t};color:${t}"></span>`
      + `<span class="co"><span class="su">${esc(c.s)}</span>`
      + `<span class="me">${esc(DATA.repos[c.r] || 'externe')} · ${depuis(c.t)} · ${esc(c.a)}`
      + `${c.n.length ? ' · ' + c.n.length + ' nœuds' : ''}</span></span>`;
    el.title = `${c.h} — ${dateExacte(c.t)}`;
    el.onclick = () => choisirCommit(k, el);
    box.appendChild(el);
  });
}

function choisirCommit(k, el) {
  for (const d of document.querySelectorAll('.cm.on')) d.classList.remove('on');
  if (commitActif === k) {            // re-cliquer éteint : pas de piège sans issue
    commitActif = -1;
    pathNodes = pathLinks = null;
    applyDim();
    return;
  }
  const c = DATA.hist[k];
  commitActif = k;
  el.classList.add('on');
  if (!c.n.length) {
    pathNodes = pathLinks = null; applyDim();
    toast('Ce commit ne touche aucun nœud du réseau — document ou fichier non indexé');
    return;
  }
  // On réutilise le surlignage du mode « chemin » : même attribut de shader,
  // même remise à zéro par Échap et par clearSelection(). Rien à réinventer.
  pathNodes = new Set(c.n);
  pathLinks = null;
  applyDim();
  flyTo(c.n[0]);
  const n = c.n.length;
  toast(`${c.h} — ${n} nœud${n > 1 ? 's' : ''} touché${n > 1 ? 's' : ''}`);
}

const histoBox = document.getElementById('histo');

const boutonHisto = document.getElementById('btn-histo');

/** Aligne le volet sur le bas quand la barre centrale lui laisse la place.
 *
 * Tout est mesuré, rien n'est supposé : la barre change de hauteur avec la
 * densité d'écran et de largeur selon que le signal de fraîcheur est affiché.
 * Une valeur en dur se trompait déjà de 12px au premier essai.
 */
function ajusterHisto() {
  const barre = document.getElementById('foot').getBoundingClientRect();
  const gap = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--gap')) || 14;
  const bordGauche = innerWidth - gap - (histoBox.offsetWidth || 330);
  const cohabitent = barre.right < bordGauche - 8;
  histoBox.style.bottom = cohabitent ? `${gap}px` : `${Math.round(gap + barre.height + 8)}px`;
}
addEventListener('resize', ajusterHisto);

function majHisto(ouvert, reduit) {
  histoBox.classList.toggle('show', ouvert);
  histoBox.classList.toggle('reduit', reduit);
  boutonHisto.classList.toggle('on', ouvert);   // le bouton dit d'où vient le volet
  if (ouvert) ajusterHisto();
  ecrireReglages();
}

boutonHisto.onclick =
  () => majHisto(!histoBox.classList.contains('show'), false);
document.getElementById('hhead').onclick =
  () => majHisto(true, !histoBox.classList.contains('reduit'));

// ── Signal de fraîcheur ────────────────────────────────────────────────────
// ECU s'ouvre tout de suite sur le dernier état connu et le rafraîchissement
// tourne derrière (voir ECU.ps1). Sans ce sondage on lirait un graphe périmé
// sans jamais le savoir : c'est la panne invisible du piège n°8 du plan.
// On compare DEUX champs — l'empreinte du graphe ET le dernier commit — parce
// qu'un commit de documents seuls change l'historique sans changer le graphe.
/** « 22/09 à 17:33 » — la date de fabrication des données affichées. */
function dateCourte(iso) {
  const d = new Date(iso);
  return isNaN(d) ? '?' : d.toLocaleString('fr-FR',
    { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }).replace(',', ' à');
}

function surveillerVersion() {
  const bandeau = document.getElementById('maj');
  const texte = document.getElementById('maj-txt');
  const bouton = document.getElementById('maj-go');
  bouton.onclick = () => location.reload();

  // LE SERVEUR PEUT ÊTRE MORT SANS QUE RIEN NE LE DISE. Le service worker sert
  // l'application entière depuis son cache : la fenêtre s'ouvre, la galaxie
  // tourne, tout a l'air normal — avec les données de la dernière fois. C'est
  // arrivé le 22/09/2026 : ECU semblait ignorer un projet qui y était depuis
  // une heure, et le vrai coupable était un serveur arrêté. Un échec de sondage
  // ne doit donc PAS être avalé ; c'est le piège n°8 du plan, à l'envers.
  // Le REMÈDE est dans le texte visible, pas dans l'infobulle. Le 23/09/2026,
  // Théo a vu « hors ligne » et a fait le geste naturel : rouvrir la fenêtre,
  // recharger. Ni l'un ni l'autre ne démarre le serveur — seule l'icône ECU du
  // Bureau le fait. Un diagnostic juste qui ne dit pas quoi faire ne suffit pas.
  function horsLigne() {
    bandeau.classList.add('show', 'froid');
    bouton.style.display = 'none';
    const quand = DATA.date ? ` · données du ${dateCourte(DATA.date)}` : '';
    texte.textContent = `serveur arrêté — double-clique l'icône ECU du Bureau${quand}`;
    bandeau.title = 'Le serveur local ne répond pas : la fenêtre est servie depuis le cache. '
      + 'Recharger ou rouvrir la fenêtre ne le redémarre pas ; l\'icône ECU du Bureau, si.';
    ajusterHisto();
  }

  // Fenêtre cachée (derrière l'éditeur, réduite) : on recharge sans demander.
  // C'est le cas normal — on code dans un projet, la veille recalcule la
  // galaxie, et en revenant sur ECU on veut la trouver à jour, pas cliquer. Les
  // réglages survivent au rechargement. Fenêtre visible : on ne retire pas la
  // vue sous les yeux, on propose. Au plus un rechargement par minute, pour
  // qu'aucun décalage entre version.json et data.json ne tourne en boucle.
  function rechargementAutorise() {
    try {
      const der = +sessionStorage.getItem('ecu-recharge') || 0;
      if (Date.now() - der < 60000) return false;
      sessionStorage.setItem('ecu-recharge', String(Date.now()));
      return true;
    } catch (e) { return false; }
  }

  function enLigne(v) {
    const dernier = DATA.hist && DATA.hist.length ? DATA.hist[0].h : '';
    if (v.hash !== DATA.hash || v.dernier !== dernier) {
      if (document.hidden && rechargementAutorise()) { location.reload(); return; }
      bandeau.classList.add('show');
      bandeau.classList.remove('froid');
      bouton.style.display = '';
      texte.textContent = 'réseau mis à jour';
      bandeau.title = 'Le graphe a changé depuis l\'ouverture de cette fenêtre';
      ajusterHisto();   // la barre s'élargit : le volet peut devoir remonter
    } else {
      bandeau.classList.remove('show', 'froid');   // tout va bien : on se tait
    }
  }

  async function verifier() {
    try {
      // L'horodatage dans l'URL n'est pas une précaution de style : un service
      // worker d'une version précédente reste aux commandes jusqu'à ce que la
      // page soit rechargée, et le sien met TOUT en cache sauf data.json. Il
      // servirait donc éternellement le premier version.json qu'il a vu, et le
      // signal de fraîcheur ne se déclencherait jamais. Une URL toujours neuve
      // ne peut être servie par aucun cache.
      const r = await fetch(`version.json?t=${Date.now()}`, { cache: 'no-store' });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const v = await r.json();
      if (v && v.hash) enLigne(v); else horsLigne();
    } catch (e) { horsLigne(); }
  }

  setInterval(verifier, 20000);
  // Chrome bride sévèrement les minuteries d'une fenêtre en arrière-plan : le
  // rafraîchissement peut finir sans que le sondage ne tourne. Revenir sur la
  // fenêtre est justement le moment où l'on veut savoir.
  addEventListener('visibilitychange', () => { if (!document.hidden) verifier(); });
  addEventListener('focus', verifier);
  verifier();
}

build().then(() => {
  appliquerReglages();     // avant tout affichage : la galaxie apparaît déjà réglée
  buildHistorique();
  surveillerVersion();
  requestAnimationFrame(loop);
}).catch(err => {
  document.getElementById('boot').innerHTML =
    `<div class="t">ECU</div><div class="s" style="color:#f75632;max-width:420px;text-align:center">
     Échec du chargement : ${esc(err.message)}</div>`;
  console.error(err);
});
