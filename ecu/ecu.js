/* ECU — Engine Control Unit
 * Réseau de connaissance des projets Bony auto-mobile.
 *
 * Pourquoi c'est rapide, là où la version précédente ramait :
 *   - la disposition 3D est PRÉCALCULÉE hors ligne (_layout3d.py) et figée ;
 *     aucune simulation de forces ne tourne dans le navigateur.
 *   - tous les nœuds forment UN seul THREE.Points → 1 appel de dessin.
 *     Toutes les arêtes forment UN seul THREE.LineSegments → 1 appel.
 *     La version précédente créait un objet 3D par nœud (3 663 objets).
 *   - la lueur et l'impulsion électrique sont calculées dans le fragment
 *     shader, pas en post-traitement : le coût est en pixels, pas en objets.
 *
 * Charte Bony (brandbook.pdf p.24-25) : #f75632 → #8f12ab, bleu nuit #293f74.
 */
import * as THREE from './vendor/three.module.min.js';

const BONY = { orange: 0xf75632, violet: 0x8f12ab, nuit: 0x4a6bbd };

// ── Palette ────────────────────────────────────────────────────────────────
// Ancrée sur le dégradé de marque : l'arc orange → magenta → violet, décliné
// en luminosité pour séparer les catégories sans sortir de la charte.
// L'arc va de l'orange (18°) au bleu nuit (220°) en DESCENDANT par le rouge, le
// magenta et le violet — exactement le chemin du dégradé de marque. Monter par
// le jaune et le vert sortirait de la charte : c'est interdit ici.
function palette(n) {
  const out = [];
  if (n <= 4) {
    const base = [BONY.orange, BONY.violet, BONY.nuit, 0xd4327a];
    for (let i = 0; i < n; i++) out.push(new THREE.Color(base[i]));
    return out;
  }
  for (let i = 0; i < n; i++) {
    const t = (i * 0.6180339887) % 1;              // suite dorée : voisins contrastés
    const hue = ((18 - t * 158) + 360) % 360;      // 18° → 220°, par le magenta
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
varying vec3  vColor;
varying float vDim;
uniform float uScale;
uniform float uBoost;
void main() {
  vColor = aColor;
  vDim   = aDim;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  gl_PointSize = aSize * uBoost * uScale / max(-mv.z, 1.0);
  gl_Position = projectionMatrix * mv;
}`;

const NODE_FRAG = `
varying vec3  vColor;
varying float vDim;
uniform float uOpacity;
void main() {
  vec2 c = gl_PointCoord - 0.5;
  float d = length(c);
  if (d > 0.5) discard;
  // noyau net + halo exponentiel : la lueur sans post-traitement
  float core = smoothstep(0.48, 0.05, d);
  float halo = exp(-d * d * 11.0) - 0.03;
  float a = (core * 0.92 + max(halo, 0.0) * 0.6) * uOpacity;
  vec3 col = mix(vColor, vec3(1.0), core * core * 0.42);
  a *= mix(1.0, 0.055, vDim);
  if (a < 0.004) discard;
  gl_FragColor = vec4(col, a);
}`;

const LINK_VERT = `
attribute vec3  aColor;
attribute float aT;
attribute float aPhase;
attribute float aDim;
varying vec3  vColor;
varying float vT;
varying float vPhase;
varying float vDim;
void main() {
  vColor = aColor; vT = aT; vPhase = aPhase; vDim = aDim;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const LINK_FRAG = `
varying vec3  vColor;
varying float vT;
varying float vPhase;
varying float vDim;
uniform float uTime;
uniform float uPulse;
uniform float uBase;
void main() {
  // impulsion : une bosse gaussienne qui remonte le fil, décalée par arête
  float p = fract(uTime * 0.19 + vPhase);
  float d = vT - p;
  d -= floor(d + 0.5);                       // distance circulaire
  float pulse = exp(-d * d * 300.0) * uPulse;
  float a = uBase + pulse * 0.9;
  // la crête vire au blanc chaud — l'arc électrique
  vec3 col = mix(vColor, vec3(1.0, 0.93, 0.86), pulse * 0.62);
  a *= mix(1.0, 0.045, vDim);
  if (a < 0.004) discard;
  gl_FragColor = vec4(col, a);
}`;

// ── Scène ──────────────────────────────────────────────────────────────────
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(55, innerWidth / innerHeight, 1, 30000);
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.setClearColor(0x000000, 0);
document.body.appendChild(renderer.domElement);

let DATA, NODES, LINKS, nodeGeo, linkGeo, nodeMat, linkMat, points, lines;
let colorMode = 'r', hidden = new Set(), focusIdx = -1;
let neighbours = null, adjacency = null;

const state = { pulse: 1, links: 1, inferred: 1, spin: 1, boost: 1 };

// ── Contrôles caméra (maison : pas de dépendance, pas de surcoût) ──────────
const cam = { target: new THREE.Vector3(), radius: 2600, theta: 0.6, phi: 1.15, spin: 0.018 };
let drag = null, idle = 0;

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
    // déplacement latéral dans le plan de la caméra
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
  if (drag && drag.moved < 5 && drag.btn === 0) pick(e.clientX, e.clientY);
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
function pick(cx, cy) {
  if (!NODES) return;
  const r = renderer.domElement.getBoundingClientRect();
  const hw = r.width / 2, hh = r.height / 2;
  let best = -1, bestD = 26 * 26;
  camera.updateMatrixWorld();
  const vp = new THREE.Matrix4().multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
  for (let i = 0; i < NODES.length; i++) {
    const n = NODES[i];
    if (hidden.has(groupKey(n))) continue;
    _v.set(n.p[0], n.p[1], n.p[2]).applyMatrix4(vp);
    if (_v.z < -1 || _v.z > 1) continue;
    const sx = (_v.x * hw) + hw, sy = (-_v.y * hh) + hh;
    const dx = sx - (cx - r.left), dy = sy - (cy - r.top);
    const d = dx * dx + dy * dy;
    if (d < bestD) { bestD = d; best = i; }
  }
  if (best >= 0) select(best); else clearSelection();
}

function groupKey(n) { return colorMode === 'r' ? n.r : colorMode === 'c' ? n.c : n.t; }
function groupList() { return colorMode === 'r' ? DATA.repos : colorMode === 'c' ? DATA.comms : DATA.types; }

// ── Construction ───────────────────────────────────────────────────────────
async function build() {
  DATA = await (await fetch('data.json')).json();
  NODES = DATA.nodes; LINKS = DATA.links;

  document.getElementById('n-nodes').textContent = NODES.length.toLocaleString('fr-FR');
  document.getElementById('n-links').textContent = LINKS.length.toLocaleString('fr-FR');

  // adjacence pour le panneau et la mise en évidence
  adjacency = Array.from({ length: NODES.length }, () => []);
  for (let i = 0; i < LINKS.length; i++) {
    const [s, t] = LINKS[i];
    adjacency[s].push([t, i]);
    adjacency[t].push([s, i]);
  }

  // centre et échelle de la scène
  const box = new THREE.Box3();
  for (const n of NODES) box.expandByPoint(new THREE.Vector3(n.p[0], n.p[1], n.p[2]));
  box.getCenter(cam.target);
  cam.radius = box.getSize(new THREE.Vector3()).length() * 0.40;

  // ── nœuds ──
  const N = NODES.length;
  const pos = new Float32Array(N * 3), col = new Float32Array(N * 3);
  const siz = new Float32Array(N), dim = new Float32Array(N);
  nodeGeo = new THREE.BufferGeometry();
  nodeGeo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  nodeGeo.setAttribute('aColor', new THREE.BufferAttribute(col, 3));
  nodeGeo.setAttribute('aSize', new THREE.BufferAttribute(siz, 1));
  nodeGeo.setAttribute('aDim', new THREE.BufferAttribute(dim, 1));
  for (let i = 0; i < N; i++) {
    const n = NODES[i];
    pos[i * 3] = n.p[0]; pos[i * 3 + 1] = n.p[1]; pos[i * 3 + 2] = n.p[2];
    siz[i] = 7 + Math.sqrt(n.d) * 7.4;
  }
  nodeGeo.computeBoundingSphere();

  nodeMat = new THREE.ShaderMaterial({
    uniforms: {
      uScale: { value: innerHeight * 0.55 },
      uOpacity: { value: 1 },
      uBoost: { value: 1 },
    },
    vertexShader: NODE_VERT, fragmentShader: NODE_FRAG,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
  points = new THREE.Points(nodeGeo, nodeMat);
  points.frustumCulled = false;
  scene.add(points);

  // ── arêtes ──
  const L = LINKS.length;
  const lp = new Float32Array(L * 6), lc = new Float32Array(L * 6);
  const lt = new Float32Array(L * 2), lph = new Float32Array(L * 2), ld = new Float32Array(L * 2);
  linkGeo = new THREE.BufferGeometry();
  linkGeo.setAttribute('position', new THREE.BufferAttribute(lp, 3));
  linkGeo.setAttribute('aColor', new THREE.BufferAttribute(lc, 3));
  linkGeo.setAttribute('aT', new THREE.BufferAttribute(lt, 1));
  linkGeo.setAttribute('aPhase', new THREE.BufferAttribute(lph, 1));
  linkGeo.setAttribute('aDim', new THREE.BufferAttribute(ld, 1));
  for (let i = 0; i < L; i++) {
    const [s, t] = LINKS[i];
    const a = NODES[s].p, b = NODES[t].p;
    lp[i * 6] = a[0]; lp[i * 6 + 1] = a[1]; lp[i * 6 + 2] = a[2];
    lp[i * 6 + 3] = b[0]; lp[i * 6 + 4] = b[1]; lp[i * 6 + 5] = b[2];
    lt[i * 2] = 0; lt[i * 2 + 1] = 1;
    const ph = (i * 0.6180339887) % 1;
    lph[i * 2] = ph; lph[i * 2 + 1] = ph;
  }
  linkGeo.computeBoundingSphere();

  linkMat = new THREE.ShaderMaterial({
    uniforms: {
      uTime: { value: 0 }, uPulse: { value: 1 }, uBase: { value: 0.14 },
    },
    vertexShader: LINK_VERT, fragmentShader: LINK_FRAG,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
  lines = new THREE.LineSegments(linkGeo, linkMat);
  lines.frustumCulled = false;
  scene.add(lines);

  recolor();
  buildLegend();
  applyCamera();
  document.getElementById('boot').classList.add('gone');
  setTimeout(() => document.getElementById('boot')?.remove(), 700);
}

// ── Couleurs et filtres ────────────────────────────────────────────────────
let colors = [];
function recolor() {
  const keys = groupList();
  colors = palette(keys.length);
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
    lc.setXYZ(i * 2 + 1, b.r, b.g, b.b);   // dégradé le long du fil
  }
  lc.needsUpdate = true;
  applyDim();
}

function applyDim() {
  const nd = nodeGeo.getAttribute('aDim');
  const ld = linkGeo.getAttribute('aDim');
  for (let i = 0; i < NODES.length; i++) {
    let d = hidden.has(groupKey(NODES[i])) ? 1 : 0;
    if (!d && focusIdx >= 0 && i !== focusIdx && !neighbours.has(i)) d = 1;
    nd.setX(i, d);
  }
  for (let i = 0; i < LINKS.length; i++) {
    const [s, t, inf] = LINKS[i];
    let d = 0;
    if (!state.links) d = 1;
    else if (inf && !state.inferred) d = 1;
    else if (hidden.has(groupKey(NODES[s])) || hidden.has(groupKey(NODES[t]))) d = 1;
    else if (focusIdx >= 0 && s !== focusIdx && t !== focusIdx) d = 1;
    ld.setX(i * 2, d); ld.setX(i * 2 + 1, d);
  }
  nd.needsUpdate = true; ld.needsUpdate = true;
}

function buildLegend() {
  const keys = groupList();
  const counts = new Array(keys.length).fill(0);
  for (const n of NODES) counts[groupKey(n)]++;
  const order = keys.map((k, i) => i).sort((a, b) => counts[b] - counts[a]).slice(0, 60);
  const box = document.getElementById('legend');
  box.innerHTML = '';
  for (const i of order) {
    const d = document.createElement('div');
    d.className = 'lg' + (hidden.has(i) ? ' off' : '');
    const c = colors[i];
    d.innerHTML = `<span class="dot" style="background:#${c.getHexString()};color:#${c.getHexString()}"></span>
                   <span class="nm">${esc(keys[i])}</span><span class="cnt">${counts[i]}</span>`;
    d.onclick = () => {
      hidden.has(i) ? hidden.delete(i) : hidden.add(i);
      d.classList.toggle('off');
      applyDim();
    };
    box.appendChild(d);
  }
}

const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// ── Panneau d'inspection ───────────────────────────────────────────────────
function select(i) {
  focusIdx = i;
  neighbours = new Set(adjacency[i].map(a => a[0]));
  applyDim();

  const n = NODES[i];
  document.getElementById('info').classList.add('show');
  document.getElementById('i-label').textContent = n.l;
  document.getElementById('i-file').textContent = n.f || '—';
  document.getElementById('i-tags').innerHTML =
    `<span class="tag grad">${esc(DATA.repos[n.r])}</span>` +
    `<span class="tag">${esc(DATA.types[n.t])}</span>` +
    `<span class="tag">${esc(DATA.comms[n.c])}</span>` +
    `<span class="tag">${n.d} liens</span>`;

  const list = adjacency[i].slice().sort((a, b) => NODES[b[0]].d - NODES[a[0]].d);
  document.getElementById('i-n').textContent = `(${adjacency[i].length})`;
  const box = document.getElementById('i-cx');
  box.innerHTML = '';
  for (const [j, li] of list.slice(0, 80)) {
    const o = NODES[j];
    const inf = LINKS[li][2];
    const row = document.createElement('div');
    row.className = 'cx';
    row.innerHTML = `<span class="ar">${LINKS[li][0] === i ? '→' : '←'}</span>
      <span class="nm">${esc(o.l)}<br><span class="rl">${esc(o.f || DATA.comms[o.c])}${inf ? ' · inféré' : ''}</span></span>`;
    row.onclick = () => { select(j); flyTo(j); };
    box.appendChild(row);
  }
}

function clearSelection() {
  focusIdx = -1; neighbours = null;
  document.getElementById('info').classList.remove('show');
  applyDim();
}

function flyTo(i) {
  const n = NODES[i];
  const to = new THREE.Vector3(n.p[0], n.p[1], n.p[2]);
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

// ── Interface ──────────────────────────────────────────────────────────────
document.getElementById('close').onclick = clearSelection;
addEventListener('keydown', e => { if (e.key === 'Escape') clearSelection(); });

document.getElementById('mode').onchange = e => {
  colorMode = e.target.value; hidden.clear(); recolor(); buildLegend();
};

// Cherche dans le libellé ET le nom de fichier : le brandbook s'appelle
// « Brand Book Bony… » côté nœud mais brandbook.pdf côté fichier, et personne
// ne devine laquelle des deux graphies taper.
document.getElementById('q').oninput = e => {
  const q = e.target.value.trim().toLowerCase();
  if (q.length < 2) return;
  let best = -1, bestScore = 1e9;
  for (let i = 0; i < NODES.length; i++) {
    const n = NODES[i];
    const pl = n.l.toLowerCase().indexOf(q);
    const pf = (n.f || '').toLowerCase().indexOf(q);
    // un libellé qui matche prime sur un nom de fichier, et un match en tête
    // de chaîne prime sur un match au milieu
    let score = 1e9;
    if (pl >= 0) score = pl;
    else if (pf >= 0) score = 100 + pf;
    if (score < bestScore || (score === bestScore && best >= 0 && n.d > NODES[best].d)) {
      bestScore = score; best = i;
    }
  }
  if (best >= 0) { select(best); flyTo(best); }
};

function toggle(id, key, after) {
  const el = document.getElementById(id);
  el.onclick = () => {
    state[key] = state[key] ? 0 : 1;
    el.classList.toggle('on', !!state[key]);
    after && after();
  };
}
toggle('sw-pulse', 'pulse');
toggle('sw-links', 'links', applyDim);
toggle('sw-inf', 'inferred', applyDim);
toggle('sw-spin', 'spin');

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
  if (nodeMat) nodeMat.uniforms.uScale.value = innerHeight * 0.55;
});

// ── Boucle ─────────────────────────────────────────────────────────────────
let last = performance.now(), fpsAcc = 0, fpsN = 0, guard = 0;
const fpsEl = document.getElementById('fps');

function loop(now) {
  requestAnimationFrame(loop);
  const dt = Math.min((now - last) / 1000, 0.1); last = now;

  if (linkMat) {
    linkMat.uniforms.uTime.value += dt;
    // l'impulsion s'éteint en douceur plutôt que de disparaître d'un coup
    const target = state.pulse && state.links ? 1 : 0;
    const u = linkMat.uniforms.uPulse;
    u.value += (target - u.value) * Math.min(1, dt * 6);
  }

  if (state.spin && !drag) {
    idle += dt;
    if (idle > 1.2) { cam.theta += cam.spin * dt; applyCamera(); }
  }

  renderer.render(scene, camera);

  // ── garde-fou performance : on dégrade avant que ça rame ──
  fpsAcc += dt; fpsN++;
  if (fpsAcc >= 0.5) {
    const fps = fpsN / fpsAcc;
    fpsEl.textContent = Math.round(fps) + ' i/s';
    fpsEl.style.color = fps < 30 ? '#f75632' : fps < 50 ? '#c1348c' : '';
    if (fps < 26 && guard < 2) {
      guard++;
      if (guard === 1) {
        renderer.setPixelRatio(1);
        document.documentElement.style.setProperty('--glass-blur', '11px');
      } else {
        if (nodeMat) nodeMat.uniforms.uBoost.value = 0.78;
        if (linkMat) linkMat.uniforms.uBase.value = 0.03;
      }
    }
    fpsAcc = 0; fpsN = 0;
  }
}

build().then(() => requestAnimationFrame(loop)).catch(err => {
  document.getElementById('boot').innerHTML =
    `<div class="t">ECU</div><div class="s" style="color:#f75632;max-width:420px;text-align:center">
     Échec du chargement : ${esc(err.message)}</div>`;
  console.error(err);
});
