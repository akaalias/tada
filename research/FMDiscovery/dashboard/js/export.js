// Export a pipeline diagram to PNG. The on-screen SVG uses foreignObject HTML for
// node text, which taints a canvas (so toBlob fails). So we build a self-contained,
// foreignObject-free SVG (native <text>) with the title + model-call count + diagram
// + legend, then rasterise it to PNG.

import { callCount, isAdapter, callLabels } from './util.js';
import { layoutPipe } from './pipeline.js';

const execType = d => d.model ? ['FM', '#111111']
  : (d.kind === 'input' || d.kind === 'output') ? ['User', '#9b998c']
  : ['Swift', '#6b6a60'];

const xml = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
// Single-quote the family names: this string is interpolated inside a double-quoted
// SVG font-family attribute, so double quotes here would break the XML and the
// rasterised <img> would silently fail to load.
const FONT = "'Palatino','Palatino Linotype',Georgia,serif";

function wrap(s, maxChars) {
  const words = String(s).split(/\s+/), lines = []; let cur = '';
  for (const w of words) {
    if ((cur + ' ' + w).trim().length > maxChars) { if (cur) lines.push(cur); cur = w; }
    else cur = (cur ? cur + ' ' : '') + w;
  }
  if (cur) lines.push(cur);
  return lines;
}

function buildExportSVG(spec) {
  const { nodes, edges } = layoutPipe(spec);
  const LANEW = 220, STEPH = 116, NODEW = 160, NODEH = 72, PADX = 16, PADY = 16;
  const ADW = 132, ADH = 46;
  const PW = 160, PH = 74, PVGAP = 30, PSTEPH = PH + PVGAP, ADGAP = 52;
  const adapterNodes = nodes.filter(n => n.adapterName);
  const hasAdapter = adapterNodes.length > 0;
  const prov = (hasAdapter && Array.isArray(spec.adapterTraining)) ? spec.adapterTraining : [];
  const useChain = prov.length > 0;
  const LEFTPAD = useChain ? PW + ADGAP : (hasAdapter ? ADW + ADGAP : 0);
  const byId = {}; nodes.forEach(n => byId[n.id] = n);
  const totalLanes = Math.max(1, ...nodes.map(n => n.rows));
  const maxCol = Math.max(0, ...nodes.map(n => n.col));
  const CHAINLEN = prov.length + 1;
  const anchorCol = hasAdapter ? Math.min(...adapterNodes.map(n => n.col)) : 0;
  const YSHIFT = useChain ? Math.max(0, (CHAINLEN - 1) * PSTEPH + PH / 2 - NODEH / 2 - anchorCol * STEPH) : 0;
  const diagW = PADX * 2 + LEFTPAD + totalLanes * LANEW;
  const diagH = PADY * 2 + YSHIFT + maxCol * STEPH + NODEH;

  const fmCount = spec.stages.reduce((a, st) => a + callCount(st), 0);
  const adapter = spec.stages.some(isAdapter);
  const title = (spec.summary || 'pipeline') + '  ·  ' + fmCount + ' on-device model call' + (fmCount === 1 ? '' : 's') + (adapter ? '  ·  LoRA adapter' : '');

  // Right-hand explanation column (hypothesis → method → result), mirroring the
  // browser's left-rule asides, so the PNG carries the same context as the screen.
  const EXP_W = 380, EXP_GAP = 22, EXP_WRAP = 54;
  const ebDefs = [
    spec.hypothesis ? { h: 'Hypothesis — the bet', c: '#6b6a60', text: spec.hypothesis } : null,
    spec.technique ? { h: 'Method — how we test it', c: '#8a6a1e', text: spec.technique } : null,
    spec.result ? { h: 'Result — what happened', c: '#111111', text: spec.result } : null,
  ].filter(Boolean);
  const hasExplain = ebDefs.length > 0;
  let explainH = 0;
  const ebLaid = ebDefs.map(b => {
    const lines = wrap(b.text, EXP_WRAP);
    const bh = 46 + (lines.length - 1) * 17;
    const top = explainH;
    explainH += bh + 14;
    return { ...b, lines, bh, top };
  });
  if (hasExplain) explainH -= 14;   // drop the trailing inter-block gap

  const MARGIN = 22, HEAD = 40, LEGEND = 52, CREDIT = 16;   // two-line legend + attribution
  const OY = MARGIN + HEAD;
  const contentH = Math.max(diagH, hasExplain ? PADY + explainH : 0);
  const W = hasExplain ? MARGIN * 2 + diagW + EXP_GAP + EXP_W : Math.max(diagW, 820) + MARGIN * 2;
  const H = OY + contentH + LEGEND + CREDIT + MARGIN;
  const OX = hasExplain ? MARGIN : MARGIN + Math.max(0, (W - MARGIN * 2 - diagW) / 2);
  const pos = id => {
    const n = byId[id], laneOff = (totalLanes - n.rows) / 2;
    const x = OX + PADX + LEFTPAD + (laneOff + n.row) * LANEW, y = OY + PADY + YSHIFT + n.col * STEPH;
    return { x, y, topx: x + NODEW / 2, topy: y, botx: x + NODEW / 2, boty: y + NODEH };
  };

  let s = `<rect width="${W}" height="${H}" fill="#fffff8"/>`;
  s += `<text x="${MARGIN}" y="${MARGIN + 19}" font-family="${FONT}" font-size="15" font-weight="700" fill="#111111">${xml(title)}</text>`;
  s += `<defs>` +
    `<marker id="exa" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#9b998c"/></marker>` +
    `<marker id="exg" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#8a6a1e"/></marker></defs>`;

  for (const e of edges) {
    const a = pos(e.from), b = pos(e.to), ty = b.topy - 5, my = (a.boty + ty) / 2;
    s += `<path d="M${a.botx},${a.boty} C${a.botx},${my} ${b.topx},${my} ${b.topx},${ty}" fill="none" stroke="#d9d5c3" stroke-width="1.5" marker-end="url(#exa)"/>`;
  }
  // adapter + training chain (top-down column feeding the FM call)
  if (useChain) {
    const anchor = adapterNodes.reduce((a, b) => (a.col <= b.col ? a : b));
    const ap = pos(anchor.id), colX = OX + PADX, fmCenterY = ap.y + NODEH / 2;
    const chain = prov.map((st, i) => ({ type: 'prov', st, i })).concat([{ type: 'adapter', name: anchor.adapterName }]);
    const L = chain.length;
    const nodeY = i => fmCenterY - PH / 2 - (L - 1 - i) * PSTEPH;
    for (let i = 0; i < L - 1; i++) {           // vertical dashed connectors
      const x = colX + PW / 2;
      s += `<path d="M${x},${nodeY(i) + PH} L${x},${nodeY(i + 1) - 5}" fill="none" stroke="#8a6a1e" stroke-width="1.5" stroke-dasharray="4 3" marker-end="url(#exg)"/>`;
    }
    const adTopY = nodeY(L - 1), fy = adTopY + PH / 2, fx0 = colX + PW, tx = ap.x - 5, ty = fmCenterY, mx = (fx0 + tx) / 2;
    s += `<path d="M${fx0},${fy} C${mx},${fy} ${mx},${ty} ${tx},${ty}" fill="none" stroke="#8a6a1e" stroke-width="1.5" stroke-dasharray="4 3" marker-end="url(#exg)"/>`;
    chain.forEach((c, i) => {
      const y = nodeY(i), isAd = c.type === 'adapter';
      s += `<rect x="${colX}" y="${y}" width="${PW}" height="${PH}" rx="8" fill="${isAd ? '#f3ead0' : '#faf6e4'}" stroke="#8a6a1e" stroke-width="${isAd ? 2 : 1.5}"${isAd ? '' : ' stroke-dasharray="3 2"'}/>`;
      const kind = isAd ? 'LORA ADAPTER' : (c.st.title || '').toUpperCase();
      s += `<text x="${colX + 9}" y="${y + 17}" font-family="${FONT}" font-size="9.5" font-weight="800" fill="${isAd ? '#8a6a1e' : '#6f5618'}">${xml(kind)}</text>`;
      const subLines = isAd ? [c.name] : wrap(c.st.sub || '', 24).slice(0, 2);
      subLines.forEach((ln, k) => { s += `<text x="${colX + 9}" y="${y + 34 + k * 14}" font-family="${FONT}" font-size="11" fill="#33312b">${xml(ln)}</text>`; });
      if (!isAd) {
        const bw = (c.st.by || '').length * 5.4 + 9;
        s += `<rect x="${colX + PW - bw - 7}" y="${y + 7}" width="${bw}" height="13" rx="3" fill="#6f5618"/>`;
        s += `<text x="${colX + PW - bw / 2 - 7}" y="${y + 16.5}" font-family="${FONT}" font-size="8" font-weight="800" fill="#fffff8" text-anchor="middle">${xml(c.st.by || '')}</text>`;
      }
    });
  } else if (hasAdapter) {
    for (const n of adapterNodes) {
      const p = pos(n.id), ax = p.x - ADGAP - ADW, ay = p.y + (NODEH - ADH) / 2;
      const fx = ax + ADW, fy = ay + ADH / 2, tx = p.x - 5, ty = p.y + NODEH / 2, mx = (fx + tx) / 2;
      s += `<path d="M${fx},${fy} C${mx},${fy} ${mx},${ty} ${tx},${ty}" fill="none" stroke="#8a6a1e" stroke-width="1.5" stroke-dasharray="4 3" marker-end="url(#exg)"/>`;
      s += `<rect x="${ax}" y="${ay}" width="${ADW}" height="${ADH}" rx="8" fill="#f3ead0" stroke="#8a6a1e" stroke-width="2"/>`;
      s += `<text x="${ax + 9}" y="${ay + 16}" font-family="${FONT}" font-size="9.5" font-weight="800" fill="#8a6a1e">LORA ADAPTER</text>`;
      s += `<text x="${ax + 9}" y="${ay + 31}" font-family="${FONT}" font-size="11" fill="#33312b">${xml(n.adapterName)}</text>`;
    }
  }
  for (const n of nodes) {
    const p = pos(n.id), [blab, bcol] = execType(n);
    s += `<rect x="${p.x}" y="${p.y}" width="${NODEW}" height="${NODEH}" rx="8" fill="#fffff8" stroke="${bcol}" stroke-width="2"/>`;
    s += `<text x="${p.x + 9}" y="${p.y + 18}" font-family="${FONT}" font-size="9.5" font-weight="800" fill="${bcol}">${xml((n.title || '').toUpperCase())}</text>`;
    wrap(n.sub || '', 25).slice(0, 3).forEach((ln, i) => {
      s += `<text x="${p.x + 9}" y="${p.y + 33 + i * 14}" font-family="${FONT}" font-size="11" fill="#33312b">${xml(ln)}</text>`;
    });
    const bw = blab.length * 5.7 + 9;
    s += `<rect x="${p.x + NODEW - bw - 6}" y="${p.y + 6}" width="${bw}" height="13" rx="3" fill="${bcol}"/>`;
    s += `<text x="${p.x + NODEW - bw / 2 - 6}" y="${p.y + 16}" font-family="${FONT}" font-size="8" font-weight="800" fill="#fffff8" text-anchor="middle">${xml(blab)}</text>`;
  }

  // explanation blocks, to the right of the diagram
  if (hasExplain) {
    const ex = OX + diagW + EXP_GAP, ey0 = OY + PADY;
    for (const b of ebLaid) {
      const by = ey0 + b.top;
      s += `<rect x="${ex}" y="${by}" width="${EXP_W}" height="${b.bh}" rx="3" fill="#ffffff" stroke="#ece9da" stroke-width="1"/>`;
      s += `<rect x="${ex}" y="${by}" width="2.5" height="${b.bh}" fill="${b.c}"/>`;
      s += `<text x="${ex + 15}" y="${by + 16}" font-family="${FONT}" font-size="11" font-weight="800" fill="${b.c}">${xml(b.h.toUpperCase())}</text>`;
      b.lines.forEach((ln, i) => { s += `<text x="${ex + 15}" y="${by + 34 + i * 17}" font-family="${FONT}" font-size="13" fill="#33312b">${xml(ln)}</text>`; });
    }
  }

  const ly = OY + contentH + 22;
  s += `<text x="${MARGIN}" y="${ly}" font-family="${FONT}" font-size="11" fill="#6b6a60">Node colour = who runs it:  ` +
    `<tspan fill="#111111" font-weight="700">FM</tspan> model call · ` +
    `<tspan fill="#6b6a60" font-weight="700">Swift</tspan> deterministic code · ` +
    `<tspan fill="#9b998c" font-weight="700">User</tspan> input/output · ` +
    `<tspan fill="#8a6a1e" font-weight="700">LoRA</tspan> adapter</text>`;
  s += `<text x="${MARGIN}" y="${ly + 16}" font-family="${FONT}" font-size="11" fill="#6b6a60">` +
    `ochre dashed chain = how it was <tspan fill="#6f5618" font-weight="700">trained</tspan> (dev-time).   Vertical = parallel, horizontal = sequential.</text>`;
  // faint copyleft attribution, bottom-left ("All Rights Reversed" = the classic copyleft pun)
  s += `<text x="${MARGIN}" y="${OY + contentH + LEGEND + 12}" font-family="${FONT}" font-size="10" fill="#c7c3b4">ↄ Copyleft 2026 Alexis Rondeau &amp; Claude Code — All Rights <tspan font-style="italic">Reversed</tspan></text>`;

  return { svg: `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${s}</svg>`, W, H };
}

export async function downloadPipePNG(spec, label) {
  const { svg, W, H } = buildExportSVG(spec);
  const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml;charset=utf-8' }));
  try {
    const img = new Image();
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });
    const scale = 2;
    const canvas = document.createElement('canvas');
    canvas.width = W * scale; canvas.height = H * scale;
    const ctx = canvas.getContext('2d');
    ctx.scale(scale, scale);
    ctx.drawImage(img, 0, 0);
    await new Promise(res => canvas.toBlob(b => {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(b);
      a.download = label + '-pipeline.png';
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1500);
      res();
    }, 'image/png'));
  } finally {
    URL.revokeObjectURL(url);
  }
}

// Download the experiment write-up as a formatted Markdown file: title + metadata,
// the hypothesis/method/result asides, then the full program-log write-up.
export function downloadWriteupMD(spec, tried, label) {
  const fmCount = spec ? spec.stages.reduce((a, st) => a + callCount(st), 0) : 0;
  const adapter = spec ? spec.stages.some(isAdapter) : false;
  const title = (spec && spec.summary) || label;
  let md = `# ${title}\n\n`;
  md += `_${label} · ${fmCount} on-device model call${fmCount === 1 ? '' : 's'}${adapter ? ' · LoRA adapter' : ''}_\n`;
  if (spec && spec.hypothesis) md += `\n## Hypothesis — the bet\n\n${spec.hypothesis}\n`;
  if (spec && spec.technique) md += `\n## Method — how we test it\n\n${spec.technique}\n`;
  if (spec && spec.result) md += `\n## Result — what happened\n\n${spec.result}\n`;
  if (tried) md += `\n## Full write-up\n\n${tried}\n`;
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([md], { type: 'text/markdown;charset=utf-8' }));
  a.download = label + '-writeup.md';
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1500);
}
