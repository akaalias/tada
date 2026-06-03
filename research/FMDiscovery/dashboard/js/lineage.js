// Mined experiment lineage: the hand-mined parent→child edges (lineage_prose.json)
// over the 76 runs, on a horizontal run-order axis with arcs above. Node facts
// (index / quality / kept / kind) come from lineage_auto.json — it doubles as the
// experiment table; only its EDGES are ignored here. Hover a node to isolate its
// parents and children and pop a card (title + hypothesis/method/result) anchored
// at the node, lazy-loaded from its pipeline spec.

import { esc, callCount, isAdapter, provenanceSteps } from './util.js';
import { fetchProvenance } from './api.js';
import { diagramSVG } from '../report-tapestry.js';   // the bare-dots §3 tile renderer (incl. LoRA training column)

const KIND = { inference: '#9b998c', sft: '#8a6a1e', orpo: '#8c2f1f', grpo: '#3f6e6e', gad: '#5a4b8a' };
const REL = {                                  // relation → [colour, dash, width, baseOpacity]
  'warm-start':   ['#8a6a1e', null,  2.2, 0.95],
  'builds-on':    ['#6b6a60', null,  1.4, 0.75],
  'uses-adapter': ['#8a6a1e', '4 3', 1.0, 0.32],   // the bulk; dimmed so structure shows
  'compares-to':  ['#bdb8a6', '2 4', 1.0, 0.45],
};
const bust = () => '?t=' + (window.__t || (window.__t = String(performance.now() | 0)));

async function load() {
  const [auto, prose, prov] = await Promise.all([
    fetch('../results/lineage_auto.json' + bust()).then(r => r.json()),   // node facts only
    fetch('../results/lineage_prose.json' + bust()).then(r => r.json()),
    fetchProvenance(),                                                    // adapter training chains
  ]);
  return { auto, prose, prov };
}

function render({ auto, prose, prov }) {
  const nodes = auto.nodes.slice().sort((a, b) => a.index - b.index);
  const yOf = {}; nodes.forEach((n, i) => yOf[n.label] = i);
  const edges = prose.edges.filter(e => e.from in yOf && e.to in yOf);

  // parents/children adjacency for hover isolation
  const parents = {}, kids = {};
  edges.forEach(e => { (kids[e.from] = kids[e.from] || []).push(e.to); (parents[e.to] = parents[e.to] || []).push(e.from); });

  // ---- legend ----
  document.getElementById('legend').innerHTML =
    Object.entries(KIND).map(([k, c]) => `<span><i style="background:${c}"></i>${k}</span>`).join('') +
    ' &nbsp; ' +
    Object.entries(REL).map(([k, [c, d]]) =>
      `<span><i class="line" style="border-top-style:${d ? 'dashed' : 'solid'};border-top-color:${c}"></i>${k}</span>`).join('');

  // ---- diagram (horizontal: run order left→right, arcs above, scroll sideways) ----
  const MX = 40, COL = 26, TOP = 18, ARCH = 360, AXIS = TOP + ARCH, LABELH = 150;
  const W = MX * 2 + (nodes.length - 1) * COL, H = AXIS + LABELH;
  const tip = document.getElementById('tip');
  const showTip = (e, html) => { tip.innerHTML = html; tip.style.left = (e.clientX + 12) + 'px'; tip.style.top = (e.clientY + 12) + 'px'; tip.style.opacity = 1; };
  const hideTip = () => { tip.style.opacity = 0; };
  const x = i => MX + i * COL;

  // per-experiment pipeline spec (lazy, cached) → the popover's title + hypothesis/method/result
  const specCache = {};
  const getSpec = async label => {
    if (!(label in specCache)) {
      try { specCache[label] = await fetch(`../results/pipelines/${label}.json` + bust()).then(r => r.ok ? r.json() : null); }
      catch { specCache[label] = null; }
    }
    return specCache[label];
  };
  const popTitle = (d, spec) => {
    if (!spec) return `${esc(d.label)} · quality ${d.quality.toFixed(3)}${d.kept ? ' · kept ★' : ''}`;
    const fm = spec.stages.reduce((a, s) => a + callCount(s), 0), ad = spec.stages.some(isAdapter);
    return esc((spec.summary || d.label) + ' · ' + fm + ' on-device model call' + (fm === 1 ? '' : 's') + (ad ? ' · LoRA adapter' : ''));
  };
  const popBody = spec => {
    const sec = (cls, h, t) => t ? `<div class="pop-sec"><div class="pop-h ${cls}">${h}</div><p>${esc(t)}</p></div>` : '';
    return sec('hyp', 'Hypothesis — the bet', spec.hypothesis) +
      sec('tech', 'Method — how we test it', spec.technique) +
      sec('res', 'Result — what happened', spec.result);
  };
  // anchor the popover at the node (fixed), clamped to the viewport; render the
  // pipeline diagram beside the hypothesis/method/result.
  const showPop = (anchor, d, spec) => {
    const hasDiag = spec && spec.stages && spec.stages.length;
    tip.innerHTML = `<div class="pop-title">${popTitle(d, spec)}</div>` +
      (spec ? `<div class="pop-grid">${hasDiag ? '<div class="pop-diagram"></div>' : ''}<div class="pop-body">${popBody(spec)}</div></div>` : '');
    tip.style.opacity = 1;
    if (hasDiag) {
      const adapterStage = spec.stages.find(s => s.knobs && s.knobs.model);
      const steps = adapterStage ? provenanceSteps(prov, adapterStage.knobs.model) : null;
      const host = tip.querySelector('.pop-diagram');
      host.innerHTML = diagramSVG(spec, KIND[d.kind] || '#9b998c', steps, 'lin' + d.index);
      const sv = host.querySelector('svg');                 // CONSTANT scale across all tiles → uniform stroke & dot sizes
      if (sv) { const vb = sv.viewBox.baseVal, K = 2.2;
        sv.setAttribute('width', (vb.width * K).toFixed(1)); sv.setAttribute('height', (vb.height * K).toFixed(1)); }
    }
    const r = anchor.getBoundingClientRect(), w = tip.offsetWidth;
    const left = Math.max(8, Math.min(r.left, window.innerWidth - w - 12));
    tip.style.left = left + 'px'; tip.style.top = (r.bottom + 14) + 'px';   // always below the node
  };

  const svg = d3.select('#diagram').html('').append('svg').attr('width', W).attr('height', H).attr('viewBox', `0 0 ${W} ${H}`);

  // arcs anchored on the axis at each node's x, bulging UP (parent ← child)
  const arc = (xp, xc) => {
    const up = AXIS - Math.min(ARCH - 12, 16 + 0.34 * Math.abs(xc - xp));
    return `M${xp},${AXIS} C${xp},${up} ${xc},${up} ${xc},${AXIS}`;
  };
  const gE = svg.append('g');
  const paths = edges.map(e => {
    const [c, dash, wdt, op] = REL[e.relation] || ['#6b6a60', null, 1.4, 0.7];
    const o = op * (e.confidence === 'low' ? 0.5 : 1);
    const p = gE.append('path').attr('fill', 'none').attr('stroke', c).attr('stroke-width', wdt)
      .attr('stroke-dasharray', dash).attr('opacity', o)
      .attr('d', arc(x(yOf[e.from]), x(yOf[e.to])))
      .on('mousemove', ev => showTip(ev, `<div class="tt-title">${e.to} <span class="ar">←</span> ${e.from}</div><div class="tt-meta">${e.relation}${e.confidence ? ' · ' + e.confidence : ''}</div>${e.evidence ? `<div class="tt-ev">${e.evidence}</div>` : ''}`))
      .on('mouseleave', hideTip);
    return { e, p, base: o };
  });

  // nodes: a kind dot on the axis + the label hanging below, rotated
  const gN = svg.append('g').selectAll('g').data(nodes).join('g').attr('transform', (d, i) => `translate(${x(i)},${AXIS})`);
  gN.append('circle').attr('r', d => d.kept ? 4.5 : 3.5).attr('fill', d => KIND[d.kind] || '#9b998c')
    .attr('stroke', d => d.kept ? '#111111' : 'none').attr('stroke-width', 1);
  const lbl = gN.append('text').attr('transform', 'rotate(90)').attr('x', 12).attr('y', 4)
    .attr('font-size', 11.5).attr('fill', '#111111').text(d => d.label);

  // hover a node → isolate edges touching it; dim the rest
  const isolate = label => {
    const near = new Set([label, ...(parents[label] || []), ...(kids[label] || [])]);
    paths.forEach(({ e, p }) => {
      const on = e.from === label || e.to === label;
      p.attr('opacity', on ? 0.98 : 0.05).attr('stroke-width', on ? (REL[e.relation]?.[2] || 1.4) + 0.6 : (REL[e.relation]?.[2] || 1.4));
    });
    lbl.attr('fill', d => near.has(d.label) ? '#111111' : '#cbc8ba')
       .attr('font-weight', d => d.label === label ? 700 : 400);
  };
  const restore = () => {
    paths.forEach(({ p, base, e }) => p.attr('opacity', base).attr('stroke-width', REL[e.relation]?.[2] || 1.4));
    lbl.attr('fill', '#111111').attr('font-weight', 400);
  };
  // trigger only on the experiment label (not the whole column)
  let hovering = null;
  lbl.style('cursor', 'pointer')
    .on('mouseenter', (ev, d) => {
      hovering = d.label; isolate(d.label);
      const circ = ev.currentTarget.parentNode.querySelector('circle');
      getSpec(d.label).then(spec => { if (hovering === d.label) showPop(circ, d, spec); });
    })
    .on('mouseleave', () => { hovering = null; restore(); hideTip(); });

}

load().then(render).catch(e => { document.getElementById('notes').innerHTML = '<span class="warn">failed to load lineage data: ' + e + '</span>'; });
