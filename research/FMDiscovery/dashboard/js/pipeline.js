// The d3 pipeline graph: turns a pipeline spec into a top-down node-link diagram.
// Parallel stages (ensemble) fan out horizontally; sequential multi-call stages
// (e.g. a tournament) chain downward. Every model call is its own node.

import { esc, KINDC, callCount, isAdapter, callLabels } from './util.js';

export function pipeSummary(spec) {
  if (!spec || !spec.stages) return '';
  const fmCount = spec.stages.reduce((a, s) => a + callCount(s), 0);
  const adapter = spec.stages.some(isAdapter);
  return spec.summary
    ? `<div class="pipe-sum">${esc(spec.summary)} <span style="color:#94a3b8;font-weight:400">· ${fmCount} on-device model call${fmCount === 1 ? '' : 's'}${adapter ? ' · <b style="color:#ca8a04">LoRA adapter</b>' : ''}</span></div>`
    : '';
}

// Build {nodes, edges, cols}. col = pipeline depth (→ y, downward); row = parallel
// lane (→ x). Each node carries a human-readable `sub` and a `full` tooltip.
export function layoutPipe(spec) {
  const stages = spec.stages || [];
  const nodes = [], edges = [], info = [];
  let col = 0;
  stages.forEach((s, si) => {
    const n = callCount(s), kind = s.kind, labels = callLabels(s);
    // The adapter is a weights input to a model call — carry its name so the
    // renderer can draw it as a separate node feeding into the FM node.
    const adapterName = (s.knobs && s.knobs.model) || (isAdapter(s) ? 'LoRA' : null);
    if (kind === 'ensemble' && n > 1) {                 // parallel fan
      const ids = [];
      for (let r = 0; r < n; r++) {
        const id = si + '_' + r; ids.push(id);
        nodes.push({ id, col, row: r, rows: n, kind, adapterName, model: true, title: 'generate', sub: labels[r] || ('#' + (r + 1)), full: kind + ': ' + (s.text || '') + ' (' + (labels[r] || '') + ')' });
      }
      info.push({ entry: ids, exit: ids }); col += 1;
    } else if (n > 1) {                                 // sequential chain
      const ids = [];
      for (let k = 0; k < n; k++) {
        const id = si + '_' + k; ids.push(id);
        nodes.push({ id, col: col + k, row: 0, rows: 1, kind, adapterName, model: true, title: kind, sub: labels[k] || (kind + ' ' + (k + 1)), full: kind + ' call ' + (k + 1) + '/' + n + ': ' + (labels[k] || '') + ' — ' + (s.text || '') });
        if (k > 0) edges.push({ from: si + '_' + (k - 1), to: id });
      }
      info.push({ entry: [ids[0]], exit: [ids[n - 1]] }); col += n;
    } else {                                            // single node
      const id = si + '_0';
      nodes.push({ id, col, row: 0, rows: 1, kind, adapterName, model: n > 0, title: kind, sub: s.text || '', full: kind + ': ' + (s.text || '') });
      info.push({ entry: [id], exit: [id] }); col += 1;
    }
  });
  for (let i = 0; i < info.length - 1; i++)
    info[i].exit.forEach(a => info[i + 1].entry.forEach(b => edges.push({ from: a, to: b })));
  return { nodes, edges, cols: col };
}

export function renderPipeD3(spec, el) {
  if (!spec || !spec.stages || !el || !window.d3) return;
  const { nodes, edges } = layoutPipe(spec);
  const LANEW = 220, STEPH = 116, NODEW = 160, NODEH = 72, PADX = 16, PADY = 16;
  const ADW = 132, ADH = 46, ADGAP = 44;                       // adapter side-node
  const hasAdapter = nodes.some(n => n.adapterName);
  const LEFTPAD = hasAdapter ? ADW + ADGAP : 0;                // room on the left for adapter nodes
  const byId = {}; nodes.forEach(n => byId[n.id] = n);
  const totalLanes = Math.max(1, ...nodes.map(n => n.rows));
  const maxCol = Math.max(0, ...nodes.map(n => n.col));
  const W = PADX * 2 + LEFTPAD + totalLanes * LANEW, H = PADY * 2 + maxCol * STEPH + NODEH;
  const pos = id => {
    const n = byId[id], laneOff = (totalLanes - n.rows) / 2;
    const x = PADX + LEFTPAD + (laneOff + n.row) * LANEW, y = PADY + n.col * STEPH;
    return { x, y, topx: x + NODEW / 2, topy: y, botx: x + NODEW / 2, boty: y + NODEH };
  };
  el.innerHTML = '';
  const svg = d3.select(el).append('svg').attr('width', W).attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);

  // arrowhead markers (define once; one per edge colour)
  const defs = svg.append('defs');
  const arrowMarker = (id, color) => defs.append('marker')
    .attr('id', id).attr('viewBox', '0 0 10 10').attr('refX', 8).attr('refY', 5)
    .attr('markerWidth', 7).attr('markerHeight', 7).attr('orient', 'auto')
    .append('path').attr('d', 'M0,0 L10,5 L0,10 z').attr('fill', color);
  arrowMarker('arrow', '#94a3b8');       // main flow
  arrowMarker('arrowGold', '#ca8a04');   // adapter feed

  // main-flow edges (vertical: depth → depth), arrowhead pointing into the target
  svg.append('g').selectAll('path.flow').data(edges).join('path').attr('class', 'flow')
    .attr('fill', 'none').attr('stroke', '#cbd5e1').attr('stroke-width', 1.5).attr('marker-end', 'url(#arrow)')
    .attr('d', d => { const a = pos(d.from), b = pos(d.to), ty = b.topy - 5, my = (a.boty + ty) / 2; return 'M' + a.botx + ',' + a.boty + ' C' + a.botx + ',' + my + ' ' + b.topx + ',' + my + ' ' + b.topx + ',' + ty; });

  // adapter side-nodes: gold weights artifact feeding INTO their FM node (edge from the left)
  const adapterNodes = nodes.filter(n => n.adapterName);
  const adX = n => pos(n.id).x - ADGAP - ADW, adY = n => pos(n.id).y + (NODEH - ADH) / 2;
  svg.append('g').selectAll('path.feed').data(adapterNodes).join('path').attr('class', 'feed')
    .attr('fill', 'none').attr('stroke', '#ca8a04').attr('stroke-width', 1.5).attr('stroke-dasharray', '4 3').attr('marker-end', 'url(#arrowGold)')
    .attr('d', n => { const p = pos(n.id), ax = adX(n) + ADW, ay = adY(n) + ADH / 2, tx = p.x - 5, ty = p.y + NODEH / 2, mx = (ax + tx) / 2; return 'M' + ax + ',' + ay + ' C' + mx + ',' + ay + ' ' + mx + ',' + ty + ' ' + tx + ',' + ty; });
  const ag = svg.append('g').selectAll('g.adapter').data(adapterNodes).join('g')
    .attr('transform', n => 'translate(' + adX(n) + ',' + adY(n) + ')');
  ag.append('rect').attr('width', ADW).attr('height', ADH).attr('rx', 8).attr('fill', '#fffbeb').attr('stroke', '#ca8a04');
  ag.append('rect').attr('width', ADW).attr('height', 3).attr('fill', '#ca8a04');
  const afo = ag.append('foreignObject').attr('x', 0).attr('y', 4).attr('width', ADW).attr('height', ADH - 6);
  const abox = afo.append('xhtml:div').attr('class', 'nodebox');
  abox.append('xhtml:div').attr('class', 'nb-kind').style('color', '#ca8a04').text('LoRA ADAPTER');
  abox.append('xhtml:div').attr('class', 'nb-sub').text(n => n.adapterName);
  ag.append('title').text(n => 'LoRA adapter "' + n.adapterName + '" — fine-tuned weights feeding this on-device call');

  // main nodes
  const g = svg.append('g').selectAll('g.node').data(nodes).join('g')
    .attr('transform', d => { const p = pos(d.id); return 'translate(' + p.x + ',' + p.y + ')'; });
  g.append('rect').attr('width', NODEW).attr('height', NODEH).attr('rx', 8).attr('fill', '#fff').attr('stroke', '#e2e8f0');
  g.append('rect').attr('width', NODEW).attr('height', 3).attr('fill', d => KINDC[d.kind] || '#64748b');
  const fo = g.append('foreignObject').attr('x', 0).attr('y', 4).attr('width', NODEW).attr('height', NODEH - 6);
  const box = fo.append('xhtml:div').attr('class', 'nodebox');
  box.append('xhtml:div').attr('class', 'nb-kind').style('color', d => KINDC[d.kind] || '#64748b').text(d => (d.title || '').toUpperCase());
  box.append('xhtml:div').attr('class', 'nb-sub').text(d => d.sub || '');
  // FM badge only for model calls WITHOUT an adapter (adapter-backed calls show the adapter node instead).
  const badge = g.filter(d => d.model && !d.adapterName).append('g').attr('transform', 'translate(' + (NODEW - 24) + ',6)');
  badge.append('rect').attr('width', 18).attr('height', 12).attr('rx', 3).attr('fill', '#db2777');
  badge.append('text').attr('x', 9).attr('y', 9.5).attr('text-anchor', 'middle').attr('font-size', 8)
    .attr('font-weight', 800).attr('fill', '#fff').text('FM');
  g.append('title').text(d => d.full);
}
