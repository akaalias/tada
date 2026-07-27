// Mined experiment lineage: the hand-mined parent→child edges (lineage_prose.json)
// over the 96 runs, on a horizontal run-order axis with arcs above. Node facts
// (index / quality / kept / kind) come from lineage_auto.json — it doubles as the
// experiment table; only its EDGES are ignored here. Hover a node to isolate its
// ancestry (every parent back to the root) and pop a card (title + hypothesis/
// method/result) anchored at the node, lazy-loaded from its pipeline spec.

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

export async function load() {
  const [auto, prose, prov] = await Promise.all([
    fetch('../results/lineage_auto.json' + bust()).then(r => r.json()),   // node facts only
    fetch('../results/lineage_prose.json' + bust()).then(r => r.json()),
    fetchProvenance(),                                                    // adapter training chains
  ]);
  return { auto, prose, prov };
}

// opts.focus: a run label to pre-isolate (trace its ancestry) and centre-scroll
// to on load — used to land on the champion without requiring a hover.
export function render({ auto, prose, prov }, opts = {}) {
  const nodes = auto.nodes.slice().sort((a, b) => a.index - b.index);
  const yOf = {}; nodes.forEach((n, i) => yOf[n.label] = i);
  const edges = prose.edges.filter(e => e.from in yOf && e.to in yOf);

  // parent adjacency for hover isolation (ancestry only)
  const parents = {};
  edges.forEach(e => { (parents[e.to] = parents[e.to] || []).push(e.from); });

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

  // transitive closure up the parent links (all ancestors)
  const climb = (start, adj) => {
    const out = new Set(), stack = [...(adj[start] || [])];
    while (stack.length) { const n = stack.pop(); if (out.has(n)) continue; out.add(n); (adj[n] || []).forEach(m => stack.push(m)); }
    return out;
  };

  // hover a node → light up ONLY its ancestry: every parent back to the root, going
  // backwards up the family tree. Descendants (forward) stay dimmed. Immediate parents
  // stay strongest so the node still pops.
  const isolate = label => {
    const anc = climb(label, parents);
    const lineage = new Set([label, ...anc]);
    const direct = new Set([label, ...(parents[label] || [])]);
    paths.forEach(({ e, p }) => {
      const touches = e.to === label;                                       // immediate parent edge (into the node)
      const inAnc   = anc.has(e.from) && (e.to === label || anc.has(e.to));  // an upward edge on a path to a root
      const w = REL[e.relation]?.[2] || 1.4;
      if (touches)        p.attr('opacity', 0.98).attr('stroke-width', w + 0.6);   // immediate parent
      else if (inAnc)     p.attr('opacity', 0.6).attr('stroke-width', w + 0.3);    // distant ancestor
      else                p.attr('opacity', 0.05).attr('stroke-width', w);          // off (incl. all descendants)
    });
    lbl.attr('fill', d => d.label === label || direct.has(d.label) ? '#111111'   // hovered + immediate parents
                        : lineage.has(d.label) ? '#6b6a60'                       // distant ancestors
                        : '#cbc8ba')                                             // unrelated / descendants
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

  // ---- pivotal-path table: the curated runs that moved the needle toward the best
  // verified result (exp056). Hovering a row lights up that run's lineage in the graph
  // above — same isolation as a node hover, but no popover. ----
  const PIVOTAL = [
    ['baseline',       'Raw on-device FM, no scaffolding — the starting line.'],
    ['exp003',         'Single FM call with RAG few-shot exemplars. First new best.'],
    ['exp011',         'Contrastive good-vs-bad few-shot. The inference base a dozen later probes built on.'],
    ['adapter_e1',     'First LoRA fine-tune on Sonnet gold — the decisive jump (+0.08).'],
    ['adapter_v2a_e1', 'Doubled the training corpus (312→619 examples). The SFT champion that warm-started every RL run.'],
    ['exp046',         'Over-generate 8 questions, then dedup to 7, on the champion adapter. Best inference topology.'],
    ['exp056',         'Refined exp046’s redundancy drop — the best verified result.'],
  ];
  const nodeOf = {}; nodes.forEach(n => nodeOf[n.label] = n);
  const diagramEl = document.getElementById('diagram');
  const scrollToNode = label => {                          // reveal the node if it's scrolled out of view
    if (!(label in yOf)) return;
    diagramEl.scrollTo({ left: x(yOf[label]) - diagramEl.clientWidth / 2, behavior: 'smooth' });
  };
  const pivHost = document.getElementById('pivotal');
  if (pivHost) {
    const rows = PIVOTAL.filter(([l]) => l in nodeOf).map(([l, why]) => {
      const n = nodeOf[l];
      return `<tr data-label="${l}"${l === 'exp056' ? ' class="best"' : ''}>` +
        `<td class="num">${n.index}</td>` +
        `<td class="lbl"><span class="dot" style="background:${KIND[n.kind] || '#9b998c'}"></span>${esc(l)}</td>` +
        `<td class="num">${n.quality.toFixed(3)}</td>` +
        `<td>${esc(why)}</td></tr>`;
    }).join('');
    pivHost.innerHTML =
      '<h2>The path to the best result</h2>' +
      '<p class="psub">Seven runs that carried the score from the raw model (0.307) to our best verified result (exp056, 0.44). ' +
      'Hover a row to light up that run’s lineage in the graph above. ' +
      '(exp032 scored higher at 0.498 but leaked gold answers into its eval, so it’s disqualified.)</p>' +
      '<table class="piv-tbl"><thead><tr><th>#</th><th>Experiment</th><th>Quality</th><th>Why it mattered</th></tr></thead>' +
      `<tbody>${rows}</tbody></table>`;
    pivHost.querySelectorAll('tbody tr').forEach(tr => {
      const label = tr.getAttribute('data-label');
      tr.addEventListener('mouseenter', () => { isolate(label); scrollToNode(label); });
      tr.addEventListener('mouseleave', () => restore());
    });
  }

  // pre-focus a run (e.g. the champion) on load, without waiting for a hover —
  // used for deep-linking (lineage.html?focus=). opts.scrollTo centres the view
  // on a run WITHOUT isolating its ancestry — used when the report embeds this
  // diagram unfocused, just scrolled to the champion.
  if (opts.focus && opts.focus in yOf) { isolate(opts.focus); scrollToNode(opts.focus); }
  else if (opts.scrollTo && opts.scrollTo in yOf) { scrollToNode(opts.scrollTo); }
}
