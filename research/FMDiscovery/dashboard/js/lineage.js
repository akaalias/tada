// Dual-arc lineage comparison: one shared run-order axis, automatic parent edges
// arced on the left, hand-mined edges on the right, disagreements highlighted.
// Loads ../results/lineage_auto.json (node objects + champion edges) and
// ../results/lineage_prose.json (mined edges, possibly multi-parent, with relation).

const KIND = { inference: '#9b998c', sft: '#8a6a1e', orpo: '#8c2f1f', grpo: '#3f6e6e', gad: '#5a4b8a' };
const REL = {                                  // mined-edge relation → [colour, dash]
  'warm-start': ['#8a6a1e', null], 'uses-adapter': ['#8a6a1e', '4 3'],
  'builds-on': ['#6b6a60', null], 'compares-to': ['#bdb8a6', '2 4'],
};
const bust = () => '?t=' + (window.__t || (window.__t = String(performance.now() | 0)));

async function load() {
  const [auto, prose] = await Promise.all([
    fetch('../results/lineage_auto.json' + bust()).then(r => r.json()),
    fetch('../results/lineage_prose.json' + bust()).then(r => r.json()).catch(() => null),
  ]);
  return { auto, prose };
}

function render({ auto, prose }) {
  const nodes = auto.nodes.slice().sort((a, b) => a.index - b.index);
  const yOf = {}; nodes.forEach((n, i) => yOf[n.label] = i);

  // parent maps. auto: single parent per child. prose: possibly several, with relation.
  const autoParent = {};
  auto.edges.forEach(e => { autoParent[e.to] = e.from; });
  const proseParents = {};                       // child -> [{from, relation, confidence}]
  (prose?.edges || []).forEach(e => { (proseParents[e.to] = proseParents[e.to] || []).push(e); });

  // agreement: a child agrees if the automatic parent is among the mined parents.
  const children = nodes.map(n => n.label).filter(l => autoParent[l] || proseParents[l]);
  const judged = children.filter(l => autoParent[l] && proseParents[l]);   // both have an opinion
  const agree = judged.filter(l => proseParents[l].some(e => e.from === autoParent[l]));
  const disagree = judged.filter(l => !proseParents[l].some(e => e.from === autoParent[l]));
  const onlyProse = children.filter(l => !autoParent[l] && proseParents[l]);

  // ---- stats ----
  const pct = judged.length ? Math.round(100 * agree.length / judged.length) : 0;
  document.getElementById('stats').innerHTML =
    `<span><b>${nodes.length}</b> experiments</span>` +
    `<span>automatic edges <b>${auto.edges.length}</b></span>` +
    `<span>mined edges <b>${(prose?.edges || []).length}</b></span>` +
    `<span>parent agreement <b>${agree.length}/${judged.length}</b> (${pct}%)</span>` +
    `<span class="${disagree.length ? 'warn' : ''}">disagreements <b>${disagree.length}</b></span>` +
    (prose ? '' : '<span class="warn">lineage_prose.json not found yet — mined side is empty</span>');

  // ---- legend ----
  document.getElementById('legend').innerHTML =
    Object.entries(KIND).map(([k, c]) => `<span><i style="background:${c}"></i>${k}</span>`).join('') +
    ' &nbsp; ' +
    Object.entries(REL).map(([k, [c, d]]) =>
      `<span><i class="line" style="border-top-style:${d ? 'dashed' : 'solid'};border-top-color:${c}"></i>${k}</span>`).join('') +
    '<span class="warn"><i class="line" style="border-top-color:#8c2f1f"></i>automatic edge that disagrees</span>';

  // ---- diagram ----
  const ROW = 22, TOP = 14, CX = 540, LBLX = CX, GUT = 360, RX = CX + 250;
  const H = TOP + nodes.length * ROW + 14, W = 1100;
  const tip = document.getElementById('tip');
  const showTip = (e, html) => { tip.innerHTML = html; tip.style.left = (e.clientX + 12) + 'px'; tip.style.top = (e.clientY + 12) + 'px'; tip.style.opacity = 1; };
  const hideTip = () => { tip.style.opacity = 0; };

  const svg = d3.select('#diagram').html('').append('svg').attr('width', W).attr('height', H).attr('viewBox', `0 0 ${W} ${H}`);
  const y = i => TOP + i * ROW + ROW / 2;

  // arc generator: vertical endpoints at anchor x, bulging out to the side
  const arc = (yp, yc, ax, dir) => {
    const bulge = 26 + 0.16 * Math.abs(yc - yp) * ROW / ROW;     // grows with span
    const cx = ax + dir * bulge;
    return `M${ax},${yp} C${cx},${yp} ${cx},${yc} ${ax},${yc}`;
  };

  // left arcs — automatic
  const gL = svg.append('g');
  Object.entries(autoParent).forEach(([child, parent]) => {
    const bad = disagree.includes(child);
    gL.append('path').attr('fill', 'none')
      .attr('stroke', bad ? '#8c2f1f' : '#c9c6b6').attr('stroke-width', bad ? 1.8 : 1)
      .attr('d', arc(y(yOf[parent]), y(yOf[child]), LBLX - 10, -1))
      .on('mousemove', e => showTip(e, `auto: <b>${child}</b> ← ${parent}${bad ? ' <span class="warn">(disagrees)</span>' : ''}`))
      .on('mouseleave', hideTip);
  });

  // right arcs — mined
  const gR = svg.append('g');
  (prose?.edges || []).forEach(e => {
    const [c, dash] = REL[e.relation] || ['#6b6a60', null];
    gR.append('path').attr('fill', 'none').attr('stroke', c).attr('stroke-width', e.relation === 'warm-start' ? 2 : 1.5)
      .attr('stroke-dasharray', dash)
      .attr('d', arc(y(yOf[e.from]), y(yOf[e.to]), LBLX + 10, 1))
      .on('mousemove', ev => showTip(ev, `mined: <b>${e.to}</b> ← ${e.from}<br>${e.relation} · ${e.confidence || ''}<br><span style="color:#cbc8ba">${e.evidence || ''}</span>`))
      .on('mouseleave', hideTip);
  });

  // node rows (labels + kind dot + quality), drawn on top
  const gN = svg.append('g').selectAll('g').data(nodes).join('g')
    .attr('transform', (d, i) => `translate(0,${y(i)})`);
  gN.append('circle').attr('cx', LBLX - 150).attr('r', 4).attr('fill', d => KIND[d.kind] || '#9b998c');
  gN.append('text').attr('x', LBLX - 140).attr('y', 4).attr('font-size', 12)
    .attr('font-weight', d => disagree.includes(d.label) ? 700 : 400)
    .attr('fill', d => disagree.includes(d.label) ? '#8c2f1f' : '#111111').text(d => d.label);
  gN.append('text').attr('x', LBLX + 150).attr('y', 4).attr('font-size', 11).attr('text-anchor', 'end')
    .attr('fill', '#9b998c').attr('font-variant-numeric', 'tabular-nums')
    .text(d => d.quality.toFixed(3) + (d.kept ? ' ★' : ''));

  // ---- disagreement list ----
  const fmtP = l => proseParents[l] ? proseParents[l].map(e => `${e.from} (${e.relation})`).join(', ') : '—';
  document.getElementById('diffs').innerHTML =
    `<h3>Where the automatic guess is wrong (${disagree.length})</h3><ul>` +
    disagree.map(l => `<li><code>${l}</code> — automatic says <code>${autoParent[l]}</code>, actually <b>${fmtP(l)}</b></li>`).join('') +
    `</ul>` +
    (onlyProse.length ? `<h3>Edges only the mined lineage has (${onlyProse.length})</h3><ul>` +
      onlyProse.map(l => `<li><code>${l}</code> ← <b>${fmtP(l)}</b></li>`).join('') + `</ul>` : '');
}

load().then(render).catch(e => { document.getElementById('stats').innerHTML = '<span class="warn">failed to load lineage data: ' + e + '</span>'; });
