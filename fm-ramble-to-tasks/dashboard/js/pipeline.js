// The d3 pipeline graph: turns a pipeline spec into a top-down node-link diagram.
// Parallel stages (ensemble) fan out horizontally; sequential multi-call stages
// (e.g. a tournament) chain downward. Every model call is its own node.

import { esc, KINDC, callCount, isAdapter, callLabels } from './util.js';

let pipeUid = 0;   // unique marker-id namespace per render (avoids cross-SVG <marker> id collisions)

export function pipeSummary(spec) {
  if (!spec || !spec.stages) return '';
  const fmCount = spec.stages.reduce((a, s) => a + callCount(s), 0);
  const adapter = spec.stages.some(isAdapter);
  return spec.summary
    ? `<div class="pipe-sum">${esc(spec.summary)} <span style="color:#9b998c;font-weight:400">· ${fmCount} on-device model call${fmCount === 1 ? '' : 's'}${adapter ? ' · <b style="color:#8a6a1e">LoRA adapter</b>' : ''}</span></div>`
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
  const ADW = 132, ADH = 46;                                   // adapter side-node (fallback, no provenance)
  const PW = 160, PH = 74, PVGAP = 30, PSTEPH = PH + PVGAP;    // vertical training-chain nodes
  const ADGAP = 52;                                            // gap from the left chain column to the pipeline
  const adapterNodes = nodes.filter(n => n.adapterName);
  const hasAdapter = adapterNodes.length > 0;
  // The training chain (Sonnet corpus -> format -> fine-tune -> adapter) that PRODUCED
  // the weights. Drawn TOP-DOWN as a left column (sequential = vertical, like the rest
  // of the diagram), feeding horizontally into the FM call. Falls back to a single side
  // node if no provenance data is available.
  const prov = (hasAdapter && Array.isArray(spec.adapterTraining)) ? spec.adapterTraining : [];
  const useChain = prov.length > 0;
  const LEFTPAD = useChain ? PW + ADGAP : (hasAdapter ? ADW + ADGAP : 0);
  const byId = {}; nodes.forEach(n => byId[n.id] = n);
  const totalLanes = Math.max(1, ...nodes.map(n => n.rows));
  const maxCol = Math.max(0, ...nodes.map(n => n.col));
  // The chain extends UPWARD from the adapter (aligned to its FM node). Shift the whole
  // pipeline down by enough that the topmost chain node never clips above the canvas.
  const CHAINLEN = prov.length + 1;                            // provenance steps + the adapter node
  const anchorCol = hasAdapter ? Math.min(...adapterNodes.map(n => n.col)) : 0;
  const YSHIFT = useChain ? Math.max(0, (CHAINLEN - 1) * PSTEPH + PH / 2 - NODEH / 2 - anchorCol * STEPH) : 0;
  const pos = id => {
    const n = byId[id], laneOff = (totalLanes - n.rows) / 2;
    const x = PADX + LEFTPAD + (laneOff + n.row) * LANEW, y = PADY + YSHIFT + n.col * STEPH;
    return { x, y, topx: x + NODEW / 2, topy: y, botx: x + NODEW / 2, boty: y + NODEH };
  };
  const W = PADX * 2 + LEFTPAD + totalLanes * LANEW, H = PADY * 2 + YSHIFT + maxCol * STEPH + NODEH;
  el.innerHTML = '';
  const svg = d3.select(el).append('svg').attr('width', W).attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);

  // Hover tooltip (SVG <title> gets swallowed by the foreignObject HTML, so use a JS tip).
  const tip = document.getElementById('tip');
  const showTip = (e, html) => { if (tip) { tip.innerHTML = html; tip.style.left = (e.clientX + 12) + 'px'; tip.style.top = (e.clientY + 12) + 'px'; tip.style.opacity = 1; } };
  const hideTip = () => { if (tip) tip.style.opacity = 0; };

  // arrowhead markers — unique ids per render so multiple panels don't collide
  const uid = 'pp' + (++pipeUid) + '-';
  const defs = svg.append('defs');
  const arrowMarker = (id, color) => defs.append('marker')
    .attr('id', id).attr('viewBox', '0 0 10 10').attr('refX', 8).attr('refY', 5)
    .attr('markerWidth', 7).attr('markerHeight', 7).attr('orient', 'auto')
    .append('path').attr('d', 'M0,0 L10,5 L0,10 z').attr('fill', color);
  arrowMarker(uid + 'arrow', '#9b998c');       // main flow (warm faint)
  arrowMarker(uid + 'arrowGold', '#8a6a1e');   // adapter feed (ochre)

  // main-flow edges (vertical: depth → depth), arrowhead pointing into the target
  svg.append('g').selectAll('path.flow').data(edges).join('path').attr('class', 'flow')
    .attr('fill', 'none').attr('stroke', '#d9d5c3').attr('stroke-width', 1.5).attr('marker-end', 'url(#' + uid + 'arrow)')
    .attr('d', d => { const a = pos(d.from), b = pos(d.to), ty = b.topy - 5, my = (a.boty + ty) / 2; return 'M' + a.botx + ',' + a.boty + ' C' + a.botx + ',' + my + ' ' + b.topx + ',' + my + ' ' + b.topx + ',' + ty; });

  // adapter + its training chain. With provenance: a TOP-DOWN left column
  //   [gold corpus] ↓ [format] ↓ [fine-tune] ↓ ADAPTER ⇢ FM call
  // (sequential reads vertically, matching the main pipeline). Without provenance:
  // a single horizontal side-node feeding the FM call from the left.
  if (useChain) {
    const anchor = adapterNodes.reduce((a, b) => (a.col <= b.col ? a : b));
    const aPos = pos(anchor.id), colX = PADX, fmCenterY = aPos.y + NODEH / 2;
    // chain top→bottom: provenance steps, then the adapter node (bottom, beside its FM call)
    const chain = prov.map((s, i) => ({ type: 'prov', s, i })).concat([{ type: 'adapter', name: anchor.adapterName }]);
    const L = chain.length;
    const nodeY = i => fmCenterY - PH / 2 - (L - 1 - i) * PSTEPH;   // i=0 top … i=L-1 adapter (bottom)

    // vertical dashed connectors between consecutive chain nodes
    const vconns = [];
    for (let i = 0; i < L - 1; i++) vconns.push([nodeY(i) + PH, nodeY(i + 1)]);
    svg.append('g').selectAll('path.provv').data(vconns).join('path').attr('class', 'provv')
      .attr('fill', 'none').attr('stroke', '#8a6a1e').attr('stroke-width', 1.5).attr('stroke-dasharray', '4 3').attr('marker-end', 'url(#' + uid + 'arrowGold)')
      .attr('d', d => { const x = colX + PW / 2; return 'M' + x + ',' + d[0] + ' L' + x + ',' + (d[1] - 5); });
    // horizontal dashed feed: adapter (bottom node) → FM node
    const adTopY = nodeY(L - 1), fy = adTopY + PH / 2, fx0 = colX + PW, tx = aPos.x - 5, ty = fmCenterY, mx = (fx0 + tx) / 2;
    svg.append('g').append('path')
      .attr('fill', 'none').attr('stroke', '#8a6a1e').attr('stroke-width', 1.5).attr('stroke-dasharray', '4 3').attr('marker-end', 'url(#' + uid + 'arrowGold)')
      .attr('d', 'M' + fx0 + ',' + fy + ' C' + mx + ',' + fy + ' ' + mx + ',' + ty + ' ' + tx + ',' + ty);

    // chain nodes
    const cg = svg.append('g').selectAll('g.chain').data(chain.map((c, i) => ({ c, i }))).join('g')
      .attr('transform', d => 'translate(' + colX + ',' + nodeY(d.i) + ')');
    cg.append('rect').attr('width', PW).attr('height', PH).attr('rx', 8)
      .attr('fill', d => d.c.type === 'adapter' ? '#f3ead0' : '#faf6e4')
      .attr('stroke', '#8a6a1e').attr('stroke-width', d => d.c.type === 'adapter' ? 2 : 1.5)
      .attr('stroke-dasharray', d => d.c.type === 'adapter' ? null : '3 2');
    const cfo = cg.append('foreignObject').attr('x', 0).attr('y', 4).attr('width', PW).attr('height', PH - 6);
    const cbox = cfo.append('xhtml:div').attr('class', 'nodebox');
    cbox.append('xhtml:div').attr('class', 'nb-kind').style('color', d => d.c.type === 'adapter' ? '#8a6a1e' : '#6f5618')
      .text(d => d.c.type === 'adapter' ? 'LORA ADAPTER' : (d.c.s.title || '').toUpperCase());
    cbox.append('xhtml:div').attr('class', 'nb-sub').text(d => d.c.type === 'adapter' ? d.c.name : (d.c.s.sub || ''));
    // actor badge (Sonnet / Python / Toolkit) on the provenance nodes
    const pbw = by => (by || '').length * 5.4 + 9;
    const pbg = cg.filter(d => d.c.type === 'prov').append('g').attr('transform', d => 'translate(' + (PW - pbw(d.c.s.by) - 7) + ',7)');
    pbg.append('rect').attr('width', d => pbw(d.c.s.by)).attr('height', 13).attr('rx', 3).attr('fill', '#6f5618');
    pbg.append('text').attr('x', d => pbw(d.c.s.by) / 2).attr('y', 10).attr('text-anchor', 'middle').attr('font-size', 8)
      .attr('font-weight', 800).attr('fill', '#fffff8').text(d => d.c.s.by);
    cg.on('mousemove', (e, d) => showTip(e, d.c.type === 'adapter'
      ? 'LoRA adapter “' + esc(d.c.name) + '” — fine-tuned weights feeding this on-device call'
      : '<b>' + esc(d.c.s.title) + '</b> · ' + esc(d.c.s.by) + ' (dev-time)<span class="t-note">' + esc(d.c.s.sub) + '</span>')).on('mouseleave', hideTip);
  } else if (hasAdapter) {
    const adX = n => pos(n.id).x - ADGAP - ADW, adY = n => pos(n.id).y + (NODEH - ADH) / 2;
    // An ensemble shares ONE adapter across its parallel lanes; draw a single box per
    // adapter at the far left (feeding its leftmost call) rather than a duplicate box
    // wedged beside every lane — which crowds the boxes into the main column.
    const repByName = {};
    adapterNodes.forEach(n => { const m = repByName[n.adapterName]; if (!m || n.col < m.col || (n.col === m.col && n.row < m.row)) repByName[n.adapterName] = n; });
    const reps = Object.keys(repByName).map(k => repByName[k]);
    svg.append('g').selectAll('path.feed').data(reps).join('path').attr('class', 'feed')
      .attr('fill', 'none').attr('stroke', '#8a6a1e').attr('stroke-width', 1.5).attr('stroke-dasharray', '4 3').attr('marker-end', 'url(#' + uid + 'arrowGold)')
      .attr('d', n => { const p = pos(n.id), ax = adX(n) + ADW, ay = adY(n) + ADH / 2, tx = p.x - 5, ty = p.y + NODEH / 2, mx = (ax + tx) / 2; return 'M' + ax + ',' + ay + ' C' + mx + ',' + ay + ' ' + mx + ',' + ty + ' ' + tx + ',' + ty; });
    const ag = svg.append('g').selectAll('g.adapter').data(reps).join('g')
      .attr('transform', n => 'translate(' + adX(n) + ',' + adY(n) + ')');
    ag.append('rect').attr('width', ADW).attr('height', ADH).attr('rx', 8).attr('fill', '#f3ead0').attr('stroke', '#8a6a1e').attr('stroke-width', 2);
    const afo = ag.append('foreignObject').attr('x', 0).attr('y', 4).attr('width', ADW).attr('height', ADH - 6);
    const abox = afo.append('xhtml:div').attr('class', 'nodebox');
    abox.append('xhtml:div').attr('class', 'nb-kind').style('color', '#8a6a1e').text('LoRA ADAPTER');
    abox.append('xhtml:div').attr('class', 'nb-sub').text(n => n.adapterName);
    ag.on('mousemove', (e, n) => showTip(e, 'LoRA adapter “' + esc(n.adapterName) + '” — fine-tuned weights feeding this on-device call')).on('mouseleave', hideTip);
  }

  // main nodes
  const g = svg.append('g').selectAll('g.node').data(nodes).join('g')
    .attr('transform', d => { const p = pos(d.id); return 'translate(' + p.x + ',' + p.y + ')'; });
  // CONSISTENT colour by EXECUTION TYPE (same across every experiment): the node's
  // border/label/badge colour says WHO runs it; the specific stage kind is the text.
  //   FM = on-device model call (pink) · Swift = deterministic code (orange) · User = input (slate)
  const execType = d => d.model ? ['FM', '#111111']
    : (d.kind === 'input' || d.kind === 'output') ? ['User', '#9b998c']   // user-facing boundary
    : ['Swift', '#6b6a60'];
  g.append('rect').attr('width', NODEW).attr('height', NODEH).attr('rx', 8).attr('fill', '#fffff8')
    .attr('stroke', d => execType(d)[1]).attr('stroke-width', 2);
  const fo = g.append('foreignObject').attr('x', 0).attr('y', 4).attr('width', NODEW).attr('height', NODEH - 6);
  const box = fo.append('xhtml:div').attr('class', 'nodebox');
  box.append('xhtml:div').attr('class', 'nb-kind').style('color', d => execType(d)[1]).text(d => (d.title || '').toUpperCase());
  box.append('xhtml:div').attr('class', 'nb-sub').text(d => d.sub || '');
  const bwid = t => t.length * 5.7 + 9;
  const bg = g.append('g').attr('transform', d => 'translate(' + (NODEW - bwid(execType(d)[0]) - 6) + ',6)');
  bg.append('rect').attr('width', d => bwid(execType(d)[0])).attr('height', 13).attr('rx', 3).attr('fill', d => execType(d)[1]);
  bg.append('text').attr('x', d => bwid(execType(d)[0]) / 2).attr('y', 10).attr('text-anchor', 'middle').attr('font-size', 8)
    .attr('font-weight', 800).attr('fill', '#fffff8').text(d => execType(d)[0]);
  g.on('mousemove', (e, d) => showTip(e, esc(d.full))).on('mouseleave', hideTip);
  return W;
}
