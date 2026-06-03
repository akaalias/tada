// Mined experiment lineage: the hand-mined parent→child edges (lineage_prose.json)
// over the 76 runs, on a vertical run-order axis with arcs to the right. Node facts
// (index / quality / kept / kind) come from lineage_auto.json — it doubles as the
// experiment table; only its EDGES are ignored here. Hover a node to isolate its
// parents and children.

const KIND = { inference: '#9b998c', sft: '#8a6a1e', orpo: '#8c2f1f', grpo: '#3f6e6e', gad: '#5a4b8a' };
const REL = {                                  // relation → [colour, dash, width, baseOpacity]
  'warm-start':   ['#8a6a1e', null,  2.2, 0.95],
  'builds-on':    ['#6b6a60', null,  1.4, 0.75],
  'uses-adapter': ['#8a6a1e', '4 3', 1.0, 0.32],   // the bulk; dimmed so structure shows
  'compares-to':  ['#bdb8a6', '2 4', 1.0, 0.45],
};
const bust = () => '?t=' + (window.__t || (window.__t = String(performance.now() | 0)));

async function load() {
  const [auto, prose] = await Promise.all([
    fetch('../results/lineage_auto.json' + bust()).then(r => r.json()),   // node facts only
    fetch('../results/lineage_prose.json' + bust()).then(r => r.json()),
  ]);
  return { auto, prose };
}

function render({ auto, prose }) {
  const nodes = auto.nodes.slice().sort((a, b) => a.index - b.index);
  const yOf = {}; nodes.forEach((n, i) => yOf[n.label] = i);
  const edges = prose.edges.filter(e => e.from in yOf && e.to in yOf);

  // parents/children adjacency for hover isolation
  const parents = {}, kids = {};
  edges.forEach(e => { (kids[e.from] = kids[e.from] || []).push(e.to); (parents[e.to] = parents[e.to] || []).push(e.from); });
  const roots = nodes.filter(n => !parents[n.label]).map(n => n.label);
  const multi = nodes.filter(n => (parents[n.label] || []).length > 1).map(n => n.label);

  // ---- stats ----
  const byRel = {}; edges.forEach(e => byRel[e.relation] = (byRel[e.relation] || 0) + 1);
  document.getElementById('stats').innerHTML =
    `<span><b>${nodes.length}</b> experiments</span>` +
    `<span><b>${edges.length}</b> lineage edges</span>` +
    Object.keys(REL).filter(r => byRel[r]).map(r => `<span>${r} <b>${byRel[r]}</b></span>`).join('') +
    `<span><b>${roots.length}</b> roots</span>` +
    `<span><b>${multi.length}</b> multi-parent</span>`;

  // ---- legend ----
  document.getElementById('legend').innerHTML =
    Object.entries(KIND).map(([k, c]) => `<span><i style="background:${c}"></i>${k}</span>`).join('') +
    ' &nbsp; ' +
    Object.entries(REL).map(([k, [c, d]]) =>
      `<span><i class="line" style="border-top-style:${d ? 'dashed' : 'solid'};border-top-color:${c}"></i>${k}</span>`).join('');

  // ---- diagram ----
  const ROW = 22, TOP = 14, AX = 330, W = 1100, NODEW = 300;
  const H = TOP + nodes.length * ROW + 14;
  const tip = document.getElementById('tip');
  const showTip = (e, html) => { tip.innerHTML = html; tip.style.left = (e.clientX + 12) + 'px'; tip.style.top = (e.clientY + 12) + 'px'; tip.style.opacity = 1; };
  const hideTip = () => { tip.style.opacity = 0; };
  const y = i => TOP + i * ROW + ROW / 2;

  const svg = d3.select('#diagram').html('').append('svg').attr('width', W).attr('height', H).attr('viewBox', `0 0 ${W} ${H}`);

  // arcs (parent above → child below), anchored at AX, bulging right
  const arc = (yp, yc) => {
    const cx = AX + Math.min(W - AX - 30, 24 + 0.34 * Math.abs(yc - yp));
    return `M${AX},${yp} C${cx},${yp} ${cx},${yc} ${AX},${yc}`;
  };
  const gE = svg.append('g');
  const paths = edges.map(e => {
    const [c, dash, wdt, op] = REL[e.relation] || ['#6b6a60', null, 1.4, 0.7];
    const o = op * (e.confidence === 'low' ? 0.5 : 1);
    const p = gE.append('path').attr('fill', 'none').attr('stroke', c).attr('stroke-width', wdt)
      .attr('stroke-dasharray', dash).attr('opacity', o)
      .attr('d', arc(y(yOf[e.from]), y(yOf[e.to])))
      .on('mousemove', ev => showTip(ev, `<b>${e.to}</b> ← ${e.from}<br>${e.relation} · ${e.confidence || ''}<br><span style="color:#cbc8ba">${e.evidence || ''}</span>`))
      .on('mouseleave', hideTip);
    return { e, p, base: o };
  });

  // nodes
  const gN = svg.append('g').selectAll('g').data(nodes).join('g').attr('transform', (d, i) => `translate(0,${y(i)})`);
  gN.append('circle').attr('cx', 16).attr('r', 4).attr('fill', d => KIND[d.kind] || '#9b998c');
  const lbl = gN.append('text').attr('x', 28).attr('y', 4).attr('font-size', 12).attr('fill', '#111111').text(d => d.label);
  gN.append('text').attr('x', NODEW).attr('y', 4).attr('font-size', 11).attr('text-anchor', 'end')
    .attr('fill', '#9b998c').attr('font-variant-numeric', 'tabular-nums').text(d => d.quality.toFixed(3) + (d.kept ? ' ★' : ''));

  // hover a node → isolate edges touching it; dim the rest
  const isolate = label => {
    const near = new Set([label, ...(parents[label] || []), ...(kids[label] || [])]);
    paths.forEach(({ e, p, base }) => {
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
  gN.style('cursor', 'pointer')
    .on('mouseenter', (ev, d) => isolate(d.label)).on('mouseleave', restore);

  // ---- roots / multi-parent notes ----
  const fmtP = l => (prose.edges.filter(e => e.to === l).map(e => `${e.from} (${e.relation})`).join(', ')) || '—';
  document.getElementById('notes').innerHTML =
    `<h3>Roots (no mined parent · ${roots.length})</h3><ul>` +
    roots.map(l => `<li><code>${l}</code></li>`).join('') + `</ul>` +
    `<h3>Multiple parents (${multi.length})</h3><ul>` +
    multi.map(l => `<li><code>${l}</code> ← <b>${fmtP(l)}</b></li>`).join('') + `</ul>`;
}

load().then(render).catch(e => { document.getElementById('stats').innerHTML = '<span class="warn">failed to load lineage data: ' + e + '</span>'; });
