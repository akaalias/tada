// Pure helpers + the fixed pipeline visual vocabulary (must match gen_pipeline.py).

export const esc = s => (s || '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
export const truncate = (s, n) => { s = String(s); return s.length > n ? s.slice(0, n - 1) + '…' : s; };
export const cap = s => s.charAt(0).toUpperCase() + s.slice(1);

// Stage kind → colour. Keep in sync with gen_pipeline.py's KINDS vocabulary.
export const KINDC = {
  input: '#64748b', retrieve: '#0891b2', generate: '#2563eb', expand: '#7c3aed',
  select: '#9333ea', critique: '#d97706', ensemble: '#db2777', post: '#059669', output: '#16a34a',
};
// Stage kinds that are on-device model calls.
export const FMK = new Set(['generate', 'expand', 'critique', 'ensemble']);

// How many on-device model calls a stage makes. A model-based select/tournament
// sets knobs.calls; an ensemble's count is knobs.n; deterministic stages = 0.
export const callCount = s => {
  const k = (s && s.knobs) || {};
  const explicit = parseInt(k.calls);
  if (Number.isFinite(explicit) && explicit > 0) return explicit;
  if (!FMK.has(s.kind)) return 0;
  if (s.kind === 'ensemble') { const n = parseInt(k.n); return Number.isFinite(n) && n > 0 ? n : 2; }
  return 1;
};

export const isAdapter = s => /adapter|lora|fine-?tun/i.test(JSON.stringify((s && s.knobs) || {}));

// Resolve an adapter name (e.g. "adapter-v2a-e2", "adapter_e1") to its training
// version family, so we can look up its provenance chain. Dash/underscore agnostic.
export const adapterFamily = name => {
  const n = String(name || '').toLowerCase().replace(/-/g, '_');
  if (n.includes('orpo')) return 'orpo';
  if (n.includes('v2b')) return 'v2b';
  if (n.includes('v2a')) return 'v2a';
  if (n.includes('adapter')) return 'v1';
  return null;
};
// The provenance steps that produced a given adapter, from adapter_provenance.json.
export const provenanceSteps = (prov, name) => {
  const fam = adapterFamily(name);
  return (fam && prov && prov.families && prov.families[fam] && prov.families[fam].steps) || null;
};

// Human-readable label per individual call. Prefer generator-provided call_labels;
// else a comma-list knob matching the count (e.g. temps); else a worded fallback.
export const callLabels = s => {
  const n = callCount(s), k = (s && s.knobs) || {};
  if (Array.isArray(s.call_labels) && s.call_labels.length === n) return s.call_labels;
  for (const [key, val] of Object.entries(k)) {
    const p = String(val).split(',').map(x => x.trim());
    if (p.length === n && n > 1) return p.map(x => `${key}=${x}`);
  }
  const word = { ensemble: 'draft', generate: 'draft', select: 'compare', critique: 'edit pass', expand: 'draft' }[s.kind] || (s.kind + ' call');
  return Array.from({ length: n }, (_, i) => `${word} ${i + 1}`);
};

// Pairwise verdict → [css class, label].
export const pw = p => p === 'fmBetter' ? ['b-win', 'WIN'] : p === 'tie' ? ['b-tie', 'TIE'] : ['b-loss', 'LOSS'];
export const rmean = rb => ((rb.atomicity + rb.specificity + rb.coverage + rb.naturalness + rb.nonRedundancy) / 5).toFixed(1);

export const RUBRIC = [['atomicity', 'atom'], ['specificity', 'spec'], ['coverage', 'cover'], ['naturalness', 'nat'], ['nonRedundancy', 'nonRed']];
export const RUBRIC_DESC = {
  atomicity: 'asks exactly one thing (no "and"/"or")',
  specificity: 'concrete to THIS task, not generic filler',
  coverage: 'the 7 cover the most decision-critical unknowns',
  naturalness: 'reads like a thoughtful human coach',
  nonRedundancy: 'questions do not overlap or repeat',
};
export const rubricChips = rb => RUBRIC.map(([k, short]) =>
  `<span class="chip" title="${cap(k)}: ${RUBRIC_DESC[k]}. 1=poor … 5=excellent">${short} ${rb[k]}</span>`).join('');

// The judge writes "Set A"/"Set B"; show plain names instead.
export const relabelSets = s => (s || '').replace(/\bset a\b/gi, 'Gold (Sonnet)').replace(/\bset b\b/gi, 'On-device');
