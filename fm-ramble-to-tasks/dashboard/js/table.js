// The program table. Rows are click-to-expand (detail rendered lazily).

import { renderDetail } from './detail.js';
import { esc } from './util.js';

// Who ran the program. human = interactive Claude driving the manual
// adapter-training track; agent = the autonomous headless Claude in run.sh.
const OPERATORS = {
  human: { label: 'Interactive', cls: 'op-human', title: 'Claude Opus, interactive session — manual track (adapter training: corpus, LoRA, export, eval)' },
  agent: { label: 'Autonomous', cls: 'op-agent', title: 'Headless Claude via run.sh — one in-context program per autonomous sample' },
};
const opBadge = op => {
  const o = OPERATORS[op];
  return o ? `<span class="op-badge ${o.cls}" title="${o.title}">${o.label}</span>`
           : '<span class="disc">—</span>';
};

// Which lever the program uses. Inference-Time = no weight change (prompt /
// decoding / RAG / topology); the others run on a LoRA adapter, distinguished by
// how that adapter was trained (imitation vs preference). See gen_types.py.
const TYPES = {
  'Inference-Time':         { short: 'Inference', cls: 'ty-infer', title: 'Inference-time only — prompt / decoding / RAG / topology. No weight change.' },
  'Supervised Fine-Tuning': { short: 'SFT',       cls: 'ty-sft',   title: 'Runs on a LoRA adapter trained by imitation (supervised fine-tuning) on Sonnet gold.' },
  'Preference (ORPO)':      { short: 'ORPO',      cls: 'ty-orpo',  title: 'Runs on a LoRA adapter trained on chosen/rejected preference pairs (ORPO).' },
  'Reinforcement (GRPO)':   { short: 'GRPO',      cls: 'ty-grpo',  title: 'Runs on a LoRA adapter trained by RL (GRPO) against the Sonnet rubric reward — group-relative advantages over the model\'s own judged drafts.' },
  'Distillation (GAD)':     { short: 'GAD',       cls: 'ty-gad',   title: 'Runs on a LoRA adapter trained by Generative Adversarial Distillation — reward is a discriminator trained to tell Sonnet gold sets from the model\'s own drafts.' },
};
const typeBadge = t => {
  const o = TYPES[t];
  return o ? `<span class="ty-badge ${o.cls}" title="${o.title}">${o.short}</span>`
           : '<span class="disc">—</span>';
};

// ms -> "45s" / "1m30s" / "1h02m". Dash when unknown (e.g. a manual run).
const fmtDur = ms => {
  if (ms == null || !(ms >= 0)) return '<span class="disc">—</span>';
  const s = Math.round(ms / 1000);
  if (s < 60) return s + 's';
  const m = Math.floor(s / 60), rs = s % 60;
  if (m < 60) return rs ? `${m}m${String(rs).padStart(2, '0')}s` : `${m}m`;
  const h = Math.floor(m / 60), rm = m % 60;
  return `${h}h${String(rm).padStart(2, '0')}m`;
};

// Clickable parent labels ("exp002 · exp003") or "root". Each opens that row.
const lineageCell = parents =>
  (parents && parents.length)
    ? parents.map(p => `<a class="lin-link" href="#exp-${esc(p)}" data-target="${esc(p)}" title="Open ${esc(p)}">${esc(p)}</a>`).join('<span class="lin-sep">·</span>')
    : '<span class="disc">root</span>';

// Open a row by label (used by the lineage links): expand its detail, flash, scroll.
function openRow(label, expanded) {
  const tr = document.getElementById('exp-' + label);
  if (!tr) return;
  const det = tr.nextElementSibling;
  if (det && det.classList.contains('detail') && !expanded.has(label)) {
    expanded.add(label);
    det.style.display = '';
    tr.classList.add('open');
    renderDetail(label, det.querySelector('td'));
  }
  tr.classList.add('row-flash');
  setTimeout(() => tr.classList.remove('row-flash'), 1800);
  tr.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

export function fillTable(runs, expanded, costs, operators = {}, types = {}, lineage = {}, durations = {}) {
  const tb = document.querySelector('#tbl tbody');
  tb.innerHTML = '';
  [...runs].reverse().forEach(r => {
    const tr = document.createElement('tr');
    tr.id = 'exp-' + r.label;
    tr.className = 'row-main' + (expanded.has(r.label) ? ' open' : '') + (r.kept ? ' kept-row' : '');
    const parents = (lineage[r.label] && lineage[r.label].parents) || [];
    tr.innerHTML = `<td>${r.index}</td><td><span class="caret">▸</span> ${r.label}</td>`
      + `<td class="lin-cell">${lineageCell(parents)}</td>`
      + `<td>${opBadge(operators[r.label])}</td>`
      + `<td>${typeBadge(types[r.label])}</td>`
      + `<td>${(r.subset || 'full')}-${r.n || ''}</td>`
      + `<td>${Math.round(r.specPass * 100)}%</td>`
      + `<td>${r.wins}/${r.ties}/${r.losses}</td>`
      + `<td class="q">${costs[r.label] != null ? '$' + costs[r.label].toFixed(2) : '<span class="disc">—</span>'}</td>`
      + `<td class="dur">${fmtDur(durations[r.label])}</td>`
      + `<td class="q">${r.fitness.toFixed(3)}</td>`
      + `<td><div class="move-cell"><span class="move-note">${esc(r.note || '')}${r.infeasible && r.infeasibleReason ? ` <span class="invalid-why" title="${esc(r.infeasibleReason)}">⚠ ${esc(r.infeasibleReason)}</span>` : ''}</span>`
      + (r.pivot ? '<span class="status-badge sb-pivot" title="Patience-driven pivot — a fresh direction taken after a no-improvement streak (elite dropped).">Pivot</span>' : '')
      + `<span class="status-badge ${r.infeasible ? 'sb-invalid' : r.kept ? 'sb-kept' : 'sb-disc'}">${r.infeasible ? 'Infeasible' : r.kept ? 'Kept' : 'Discarded'}</span></div></td>`;
    const det = document.createElement('tr'); det.className = 'detail';
    const cell = document.createElement('td'); cell.colSpan = 12;
    det.appendChild(cell);
    det.style.display = expanded.has(r.label) ? '' : 'none';
    if (expanded.has(r.label)) renderDetail(r.label, cell);
    tr.addEventListener('click', () => {
      if (expanded.has(r.label)) { expanded.delete(r.label); det.style.display = 'none'; tr.classList.remove('open'); }
      else { expanded.add(r.label); det.style.display = ''; tr.classList.add('open'); renderDetail(r.label, cell); }
    });
    // Lineage links open the parent row instead of toggling this one.
    tr.querySelectorAll('.lin-link').forEach(a => {
      a.addEventListener('click', e => { e.preventDefault(); e.stopPropagation(); openRow(a.dataset.target, expanded); });
    });
    tb.appendChild(tr); tb.appendChild(det);
  });
}
