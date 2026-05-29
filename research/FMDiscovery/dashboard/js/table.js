// The experiment table. Rows are click-to-expand (detail rendered lazily).

import { renderDetail } from './detail.js';
import { esc } from './util.js';

export function fillTable(runs, expanded, costs) {
  const tb = document.querySelector('#tbl tbody');
  tb.innerHTML = '';
  [...runs].reverse().forEach(r => {
    const tr = document.createElement('tr');
    tr.className = 'row-main' + (expanded.has(r.label) ? ' open' : '');
    tr.innerHTML = `<td>${r.index}</td><td><span class="caret">▸</span> ${r.label}</td>`
      + `<td>${(r.subset || 'full')}-${r.n || ''}</td>`
      + `<td class="q">${r.quality.toFixed(3)}</td>`
      + `<td>${Math.round(r.specPass * 100)}%</td>`
      + `<td>${r.wins}/${r.ties}/${r.losses}</td>`
      + `<td class="q">${costs[r.label] != null ? '$' + costs[r.label].toFixed(2) : '<span class="disc">—</span>'}</td>`
      + `<td>${esc(r.note || '')} <span class="${r.kept ? 'kept' : 'disc'}">${r.kept ? 'kept' : 'discarded'}</span></td>`;
    const det = document.createElement('tr'); det.className = 'detail';
    const cell = document.createElement('td'); cell.colSpan = 8;
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
