// Simplified "tapestry" for §3 of the report: every experiment's pipeline rendered
// as bare nodes-and-arrows — no text, no card. Every dot is drawn at one fixed scale
// (so they read as small-multiples), but each diagram keeps its NATURAL width and
// height — single-shot chains are thin, ensembles fan wide, adapter runs carry a gold
// training side-column. Filled dots are on-device model calls tinted by lever family;
// hollow dots are deterministic Swift steps or the user in/out boundary; the gold
// left column is the dev-time chain that trained the LoRA adapter.
import { fetchRuns, fetchTypes, fetchProvenance } from './js/api.js';
import { layoutPipe } from './js/pipeline.js';
import { provenanceSteps } from './js/util.js';

const FAMILY = {
  'Inference-Time':         '#9b998c',  // --faint, no weight change
  'Supervised Fine-Tuning': '#8a6a1e',  // --ochre
  'Preference (ORPO)':      '#8c2f1f',  // --accent
};
const EDGE = '#cdc8b6', HOLLOW = '#bdb8a6', PAPER = '#fffff8';
const GOLD = '#8a6a1e', GOLDLINE = '#c2a25a';   // adapter training chain

// One fixed unit grid for every tile → equal scale. Width/height are free to vary.
const SCALE = 1.1;                       // px per unit
const R = 4.6, SY = 18, LANEW = 15, PADX = 6, PADY = 8, FEED = 14;
// Fold only very long pipelines, and show plenty of the chain first so it still reads
// as long: keep the head and tail rows, ellipsis for the middle.
const FOLD_AT = 14, KEEP_HEAD = 9, KEEP_TAIL = 6, ELL_GAP = 1.6;

const pipeCache = {};
async function pipe(label) {
  if (pipeCache[label] !== undefined) return pipeCache[label];
  try {
    const r = await fetch(`../results/pipelines/${label}.json?t=` + Date.now());
    pipeCache[label] = r.ok ? await r.json() : null;
  } catch (e) { pipeCache[label] = null; }
  return pipeCache[label];
}

function diagramSVG(spec, fill, steps, uid) {
  const { nodes, edges } = layoutPipe(spec);
  if (!nodes.length) return '';
  const lanes = Math.max(1, ...nodes.map(n => n.rows));
  const maxCol = Math.max(0, ...nodes.map(n => n.col));
  const f = v => v.toFixed(1);

  // fold long chains
  const fold = nodes.length > FOLD_AT && maxCol >= KEEP_HEAD + KEEP_TAIL;
  const tailMin = maxCol - KEEP_TAIL + 1;
  const kept = nodes.filter(n => !fold || n.col <= KEEP_HEAD - 1 || n.col >= tailMin);
  const vc = n => (!fold || n.col <= KEEP_HEAD - 1) ? n.col : (KEEP_HEAD - 1) + ELL_GAP + 1 + (n.col - tailMin);

  // adapter training side-column (gold): provenance steps + the adapter, feeding the FM node
  const adapterNodes = kept.filter(n => n.adapterName);
  const hasChain = adapterNodes.length > 0 && steps && steps.length > 0;
  const L = hasChain ? steps.length + 1 : 0;
  const anchor = hasChain ? adapterNodes.reduce((a, b) =>
    (b.col < a.col || (b.col === a.col && b.row < a.row)) ? b : a) : null;

  const LEFTPAD = hasChain ? LANEW + FEED : 0;
  const YSHIFT = hasChain ? Math.max(0, (L - 1 - vc(anchor)) * SY) : 0;
  const byId = {}; nodes.forEach(n => byId[n.id] = n);
  const cx = n => PADX + R + LEFTPAD + ((lanes - n.rows) / 2 + n.row) * LANEW;
  const cy = n => PADY + R + YSHIFT + vc(n) * SY;
  const maxVC = Math.max(0, ...kept.map(vc));
  const VW = PADX * 2 + 2 * R + LEFTPAD + (lanes - 1) * LANEW;
  const VH = PADY * 2 + 2 * R + YSHIFT + maxVC * SY;

  const seg = (x1, y1, x2, y2, m) => `<line x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}" marker-end="url(#${m}${uid})"/>`;
  const keptIds = new Set(kept.map(n => n.id));
  const flow = edges.filter(e => keptIds.has(e.from) && keptIds.has(e.to))
    .map(e => { const a = byId[e.from], b = byId[e.to]; return seg(cx(a), cy(a) + R, cx(b), cy(b) - R - 1.5, 'ar'); });

  let ellipsis = '';
  if (fold) {
    const hn = kept.find(n => n.col === KEEP_HEAD - 1), tn = kept.find(n => n.col === tailMin);
    const ex = cx(hn), ey = (cy(hn) + cy(tn)) / 2;
    flow.push(seg(cx(hn), cy(hn) + R, ex, ey - 4.6, 'ar'));
    flow.push(seg(ex, ey + 4.6, cx(tn), cy(tn) - R - 1.5, 'ar'));
    ellipsis = [-3.4, 0, 3.4].map(d => `<circle cx="${f(ex)}" cy="${f(ey + d)}" r="1" fill="${HOLLOW}"/>`).join('');
  }

  let train = '';
  if (hasChain) {
    const ax = PADX + R, aY = cy(anchor), nodeY = i => aY - (L - 1 - i) * SY;
    for (let i = 0; i < L - 1; i++)
      train += seg(ax, nodeY(i) + R, ax, nodeY(i + 1) - R - 1.5, 'ag');
    train += seg(ax + R, aY, cx(anchor) - R - 1.5, aY, 'ag');           // feed into FM node
    for (let i = 0; i < L; i++) {
      const y = nodeY(i);
      train += i === L - 1
        ? `<circle cx="${f(ax)}" cy="${f(y)}" r="${R}" fill="${GOLD}"/>`
        : `<circle cx="${f(ax)}" cy="${f(y)}" r="${R - 0.6}" fill="${PAPER}" stroke="${GOLD}" stroke-width="1.1"/>`;
    }
  }

  const dots = kept.map(n => n.model
    ? `<circle cx="${f(cx(n))}" cy="${f(cy(n))}" r="${R}" fill="${fill}"/>`
    : `<circle cx="${f(cx(n))}" cy="${f(cy(n))}" r="${R - 0.6}" fill="${PAPER}" stroke="${HOLLOW}" stroke-width="1.1"/>`).join('');

  const marker = (id, color) => `<marker id="${id}${uid}" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M0,1.5 L8.5,5 L0,8.5" fill="none" stroke="${color}" stroke-width="2"/></marker>`;
  const svg = `<svg width="${f(VW * SCALE)}" height="${f(VH * SCALE)}" viewBox="0 0 ${f(VW)} ${f(VH)}" style="display:block">`
    + `<defs>${marker('ar', EDGE)}${marker('ag', GOLDLINE)}</defs>`
    + `<g stroke="${EDGE}" stroke-width="1.2" fill="none">${flow.join('')}</g>`
    + `<g stroke="${GOLDLINE}" stroke-width="1.2" fill="none">${train}</g>`
    + ellipsis + dots + `</svg>`;
  return { svg, w: VW * SCALE, h: VH * SCALE };
}

// Skyline bin-packing: place each tile (in run order) into the lowest gap it fits,
// flowing like a Pinterest mosaic in both width and height. Positions only — sizes
// are known up front, so no DOM measurement / reflow.
function pack(items, CW, gap) {
  let sky = [{ x: 0, w: CW, y: 0 }];
  const pos = [];
  for (const it of items) {
    const w = Math.min(it.w + gap, CW), h = it.h + gap;
    let best = null;
    for (const s of sky) {
      const x = s.x;
      if (x + w > CW + 0.5) continue;
      let y = 0, rem = w;
      for (const t of sky) {                       // max skyline height across the span
        if (t.x + t.w <= x) continue;
        if (t.x >= x + w) break;
        y = Math.max(y, t.y); rem -= Math.min(t.x + t.w, x + w) - Math.max(t.x, x);
      }
      if (rem > 0.5) continue;                      // span runs off the right edge
      if (!best || y < best.y - 0.5 || (Math.abs(y - best.y) < 0.5 && x < best.x)) best = { x, y };
    }
    if (!best) best = { x: 0, y: Math.max(...sky.map(s => s.y)) };
    pos.push({ x: best.x, y: best.y });
    sky = raise(sky, best.x, w, best.y + h);
  }
  return { pos, totalH: Math.max(...sky.map(s => s.y)) - gap };
}

function raise(sky, x0, w, y) {
  const x1 = x0 + w, out = [];
  for (const s of sky) {
    const a = s.x, b = s.x + s.w;
    if (b <= x0 || a >= x1) { out.push(s); continue; }
    if (a < x0) out.push({ x: a, w: x0 - a, y: s.y });
    out.push({ x: Math.max(a, x0), w: Math.min(b, x1) - Math.max(a, x0), y });
    if (b > x1) out.push({ x: x1, w: b - x1, y: s.y });
  }
  out.sort((a, b) => a.x - b.x);
  const merged = [out[0]];
  for (let k = 1; k < out.length; k++) {
    const last = merged[merged.length - 1];
    if (Math.abs(last.y - out[k].y) < 0.01 && Math.abs(last.x + last.w - out[k].x) < 0.01) last.w += out[k].w;
    else merged.push(out[k]);
  }
  return merged;
}

const GAP = 16;

async function render() {
  const el = document.getElementById('tapestry');
  if (!el) return;
  const [runs, types, prov] = await Promise.all([fetchRuns(), fetchTypes(), fetchProvenance()]);
  if (!runs.length) { el.innerHTML = '<p class="muted" style="font-size:14px">Run the dashboard server to load the diagrams.</p>'; return; }

  const items = (await Promise.all(runs.map(async (r, i) => {
    const spec = await pipe(r.label);
    if (!spec) return null;
    const fill = FAMILY[types[r.label]] || FAMILY['Inference-Time'];
    const adapterStage = (spec.stages || []).find(s => s.knobs && s.knobs.model);
    const steps = adapterStage ? provenanceSteps(prov, adapterStage.knobs.model) : null;
    const { svg, w, h } = diagramSVG(spec, fill, steps, i);
    return { w, h, html: `<div class="tap-cell" title="${r.label} · ${types[r.label] || ''} · quality ${(r.quality).toFixed(2)}, coverage ${r.coverage}">${svg}</div>` };
  }))).filter(Boolean);

  el.innerHTML = items.map(it => it.html).join('');
  const nodes = [...el.children];
  const layout = () => {
    const CW = el.clientWidth || Math.round(window.innerWidth * 0.66);
    const { pos, totalH } = pack(items, CW, GAP);
    pos.forEach((p, i) => { nodes[i].style.left = p.x + 'px'; nodes[i].style.top = p.y + 'px'; });
    el.style.height = totalH + 'px';
  };
  layout();
  let t; window.addEventListener('resize', () => { clearTimeout(t); t = setTimeout(layout, 120); });
}

render();
