// The experiment table. Rows are click-to-expand (detail rendered lazily).

import { renderDetail } from './detail.js';
import { esc } from './util.js';

// Who ran the experiment. human = interactive Claude driving the manual
// adapter-training track; agent = the autonomous headless Claude in run.sh.
const OPERATORS = {
  human: { label: 'Interactive', cls: 'op-human', title: 'Claude Opus, interactive session — manual track (adapter training: corpus, LoRA, export, eval)' },
  agent: { label: 'Autonomous', cls: 'op-agent', title: 'Headless Claude via run.sh — one in-context experiment per autonomous iteration' },
};
const opBadge = op => {
  const o = OPERATORS[op];
  return o ? `<span class="op-badge ${o.cls}" title="${o.title}">${o.label}</span>`
           : '<span class="disc">—</span>';
};

export function fillTable(runs, expanded, costs, operators = {}) {
  const tb = document.querySelector('#tbl tbody');
  tb.innerHTML = '';
  [...runs].reverse().forEach(r => {
    const tr = document.createElement('tr');
    tr.className = 'row-main' + (expanded.has(r.label) ? ' open' : '') + (r.kept ? ' kept-row' : '');
    tr.innerHTML = `<td>${r.index}</td><td><span class="caret">▸</span> ${r.label}</td>`
      + `<td>${opBadge(operators[r.label])}</td>`
      + `<td>${(r.subset || 'full')}-${r.n || ''}</td>`
      + `<td class="q">${r.quality.toFixed(3)}</td>`
      + `<td>${Math.round(r.specPass * 100)}%</td>`
      + `<td>${r.wins}/${r.ties}/${r.losses}</td>`
      + `<td class="q">${costs[r.label] != null ? '$' + costs[r.label].toFixed(2) : '<span class="disc">—</span>'}</td>`
      + `<td>${r.kept ? '<span class="rowdot" title="kept improvement"></span>' : ''}${esc(r.note || '')} <span class="${r.kept ? 'kept' : 'disc'}">${r.kept ? 'kept' : 'discarded'}</span></td>`;
    const det = document.createElement('tr'); det.className = 'detail';
    const cell = document.createElement('td'); cell.colSpan = 9;
    det.appendChild(cell);
    det.style.display = expanded.has(r.label) ? '' : 'none';
    if (expanded.has(r.label)) renderDetail(r.label, cell);
    tr.addEventListener('click', () => {
      if (expanded.has(r.label)) { expanded.delete(r.label); det.style.display = 'none'; tr.classList.remove('open'); }
      else { expanded.add(r.label); det.style.display = ''; tr.classList.add('open'); renderDetail(r.label, cell); }
    });
    tb.appendChild(tr); tb.appendChild(det);
  });
}
