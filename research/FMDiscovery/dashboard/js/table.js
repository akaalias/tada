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

// Which lever the experiment uses. Inference-Time = no weight change (prompt /
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

export function fillTable(runs, expanded, costs, operators = {}, types = {}) {
  const tb = document.querySelector('#tbl tbody');
  tb.innerHTML = '';
  [...runs].reverse().forEach(r => {
    const tr = document.createElement('tr');
    tr.className = 'row-main' + (expanded.has(r.label) ? ' open' : '') + (r.kept ? ' kept-row' : '');
    tr.innerHTML = `<td>${r.index}</td><td><span class="caret">▸</span> ${r.label}</td>`
      + `<td>${opBadge(operators[r.label])}</td>`
      + `<td>${typeBadge(types[r.label])}</td>`
      + `<td>${(r.subset || 'full')}-${r.n || ''}</td>`
      + `<td class="q">${r.quality.toFixed(3)}</td>`
      + `<td>${Math.round(r.specPass * 100)}%</td>`
      + `<td>${r.wins}/${r.ties}/${r.losses}</td>`
      + `<td class="q">${costs[r.label] != null ? '$' + costs[r.label].toFixed(2) : '<span class="disc">—</span>'}</td>`
      + `<td><div class="move-cell"><span class="move-note">${esc(r.note || '')}${r.invalid && r.invalidReason ? ` <span class="invalid-why" title="${esc(r.invalidReason)}">⚠ ${esc(r.invalidReason)}</span>` : ''}</span>`
      + `<span class="status-badge ${r.invalid ? 'sb-invalid' : r.kept ? 'sb-kept' : 'sb-disc'}">${r.invalid ? 'Invalid' : r.kept ? 'Kept' : 'Discarded'}</span></div></td>`;
    const det = document.createElement('tr'); det.className = 'detail';
    const cell = document.createElement('td'); cell.colSpan = 10;
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
