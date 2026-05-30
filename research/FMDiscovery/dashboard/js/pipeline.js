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
  const PW = 134, PH = 50, PGAP = 30;                          // training-provenance chain nodes
  const hasAdapter = nodes.some(n => n.adapterName);
  // Provenance chain (Sonnet corpus -> format -> fine-tune) that produced the adapter.
  const prov = (hasAdapter && Array.isArray(spec.adapterTraining)) ? spec.adapterTraining : [];
  const PROVPAD = prov.length ? prov.length * (PW + PGAP) : 0;
  const LEFTPAD = (hasAdapter ? ADW + ADGAP : 0) + PROVPAD;    // room on the left for adapter + its provenance
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
  arrowMarker(uid + 'arrow', '#94a3b8');       // main flow
  arrowMarker(uid + 'arrowGold', '#ca8a04');   // adapter feed

  // main-flow edges (vertical: depth → depth), arrowhead pointing into the target
  svg.append('g').selectAll('path.flow').data(edges).join('path').attr('class', 'flow')
    .attr('fill', 'none').attr('stroke', '#cbd5e1').attr('stroke-width', 1.5).attr('marker-end', 'url(#' + uid + 'arrow)')
    .attr('d', d => { const a = pos(d.from), b = pos(d.to), ty = b.topy - 5, my = (a.boty + ty) / 2; return 'M' + a.botx + ',' + a.boty + ' C' + a.botx + ',' + my + ' ' + b.topx + ',' + my + ' ' + b.topx + ',' + ty; });

  // adapter side-nodes: gold weights artifact feeding INTO their FM node (edge from the left)
  const adapterNodes = nodes.filter(n => n.adapterName);
  const adX = n => pos(n.id).x - ADGAP - ADW, adY = n => pos(n.id).y + (NODEH - ADH) / 2;
  svg.append('g').selectAll('path.feed').data(adapterNodes).join('path').attr('class', 'feed')
    .attr('fill', 'none').attr('stroke', '#ca8a04').attr('stroke-width', 1.5).attr('stroke-dasharray', '4 3').attr('marker-end', 'url(#' + uid + 'arrowGold)')
    .attr('d', n => { const p = pos(n.id), ax = adX(n) + ADW, ay = adY(n) + ADH / 2, tx = p.x - 5, ty = p.y + NODEH / 2, mx = (ax + tx) / 2; return 'M' + ax + ',' + ay + ' C' + mx + ',' + ay + ' ' + mx + ',' + ty + ' ' + tx + ',' + ty; });
  const ag = svg.append('g').selectAll('g.adapter').data(adapterNodes).join('g')
    .attr('transform', n => 'translate(' + adX(n) + ',' + adY(n) + ')');
  ag.append('rect').attr('width', ADW).attr('height', ADH).attr('rx', 8).attr('fill', '#fffbeb').attr('stroke', '#ca8a04').attr('stroke-width', 2);
  const afo = ag.append('foreignObject').attr('x', 0).attr('y', 4).attr('width', ADW).attr('height', ADH - 6);
  const abox = afo.append('xhtml:div').attr('class', 'nodebox');
  abox.append('xhtml:div').attr('class', 'nb-kind').style('color', '#ca8a04').text('LoRA ADAPTER');
  abox.append('xhtml:div').attr('class', 'nb-sub').text(n => n.adapterName);
  ag.on('mousemove', (e, n) => showTip(e, 'LoRA adapter “' + esc(n.adapterName) + '” — fine-tuned weights feeding this on-device call')).on('mouseleave', hideTip);

  // training-provenance chain: how the adapter was MADE (dev-time). Drawn as a
  // gold dashed chain to the LEFT of the (topmost) adapter node, flowing into it:
  //   [gold corpus] ⇢ [format] ⇢ [fine-tune] ⇢ ADAPTER ⇢ FM call
  if (prov.length && adapterNodes.length) {
    const anchor = adapterNodes.reduce((a, b) => (pos(a.id).y <= pos(b.id).y ? a : b));
    const aPos = pos(anchor.id), aLeft = adX(anchor);          // adapter node's left edge
    const provY = adY(anchor) + (ADH - PH) / 2;                // vertically centre on the adapter
    const stepX = i => aLeft - PGAP - PW - (prov.length - 1 - i) * (PW + PGAP);

    // gold dashed connectors: step→step, and last step→adapter
    const connectors = [];
    for (let i = 0; i < prov.length - 1; i++) connectors.push([stepX(i) + PW, stepX(i + 1)]);
    connectors.push([stepX(prov.length - 1) + PW, aLeft]);     // into the adapter node
    svg.append('g').selectAll('path.prov').data(connectors).join('path').attr('class', 'prov')
      .attr('fill', 'none').attr('stroke', '#ca8a04').attr('stroke-width', 1.5).attr('stroke-dasharray', '4 3')
      .attr('marker-end', 'url(#' + uid + 'arrowGold)')
      .attr('d', d => { const y = provY + PH / 2, x0 = d[0], x1 = d[1] - 5; return 'M' + x0 + ',' + y + ' L' + x1 + ',' + y; });

    const pg = svg.append('g').selectAll('g.prov-node').data(prov.map((s, i) => ({ s, i }))).join('g')
      .attr('transform', d => 'translate(' + stepX(d.i) + ',' + provY + ')');
    pg.append('rect').attr('width', PW).attr('height', PH).attr('rx', 8)
      .attr('fill', '#fffef5').attr('stroke', '#ca8a04').attr('stroke-width', 1.5).attr('stroke-dasharray', '3 2');
    const pfo = pg.append('foreignObject').attr('x', 0).attr('y', 3).attr('width', PW).attr('height', PH - 4);
    const pbox = pfo.append('xhtml:div').attr('class', 'nodebox');
    pbox.append('xhtml:div').attr('class', 'nb-kind').style('color', '#a16207').text(d => (d.s.title || '').toUpperCase());
    pbox.append('xhtml:div').attr('class', 'nb-sub').text(d => d.s.sub || '');
    // small actor badge (Sonnet / Python / Toolkit) — who produces this artifact
    const pbw = d => (d.s.by || '').length * 5.2 + 8;
    const pbg = pg.append('g').attr('transform', d => 'translate(' + (PW - pbw(d) - 6) + ',6)');
    pbg.append('rect').attr('width', d => pbw(d)).attr('height', 12).attr('rx', 3).attr('fill', '#a16207');
    pbg.append('text').attr('x', d => pbw(d) / 2).attr('y', 9.5).attr('text-anchor', 'middle').attr('font-size', 7.5)
      .attr('font-weight', 800).attr('fill', '#fff').text(d => d.s.by || '');
    pg.on('mousemove', (e, d) => showTip(e, '<b>' + esc(d.s.title) + '</b> · ' + esc(d.s.by) + ' (dev-time)<span class="t-note">' + esc(d.s.sub) + '</span>')).on('mouseleave', hideTip);
  }

  // main nodes
  const g = svg.append('g').selectAll('g.node').data(nodes).join('g')
    .attr('transform', d => { const p = pos(d.id); return 'translate(' + p.x + ',' + p.y + ')'; });
  // CONSISTENT colour by EXECUTION TYPE (same across every experiment): the node's
  // border/label/badge colour says WHO runs it; the specific stage kind is the text.
  //   FM = on-device model call (pink) · Swift = deterministic code (orange) · User = input (slate)
  const execType = d => d.model ? ['FM', '#db2777']
    : (d.kind === 'input' || d.kind === 'output') ? ['User', '#64748b']   // user-facing boundary
    : ['Swift', '#ea580c'];
  g.append('rect').attr('width', NODEW).attr('height', NODEH).attr('rx', 8).attr('fill', '#fff')
    .attr('stroke', d => execType(d)[1]).attr('stroke-width', 2);
  const fo = g.append('foreignObject').attr('x', 0).attr('y', 4).attr('width', NODEW).attr('height', NODEH - 6);
  const box = fo.append('xhtml:div').attr('class', 'nodebox');
  box.append('xhtml:div').attr('class', 'nb-kind').style('color', d => execType(d)[1]).text(d => (d.title || '').toUpperCase());
  box.append('xhtml:div').attr('class', 'nb-sub').text(d => d.sub || '');
  const bwid = t => t.length * 5.7 + 9;
  const bg = g.append('g').attr('transform', d => 'translate(' + (NODEW - bwid(execType(d)[0]) - 6) + ',6)');
  bg.append('rect').attr('width', d => bwid(execType(d)[0])).attr('height', 13).attr('rx', 3).attr('fill', d => execType(d)[1]);
  bg.append('text').attr('x', d => bwid(execType(d)[0]) / 2).attr('y', 10).attr('text-anchor', 'middle').attr('font-size', 8)
    .attr('font-weight', 800).attr('fill', '#fff').text(d => execType(d)[0]);
  g.on('mousemove', (e, d) => showTip(e, esc(d.full))).on('mouseleave', hideTip);
}
