// All data fetching. Caches successful results; never caches a miss, so a fetch
// that lands mid-write self-heals on the next refresh.

const bust = () => '?t=' + Date.now();

export async function fetchRuns() {
  try {
    const t = await (await fetch('../results/runs.jsonl' + bust())).text();
    return t.trim().split('\n').filter(Boolean).map(JSON.parse);
  } catch (e) { return []; }
}

export async function fetchCosts() {
  try { return await (await fetch('../results/costs.json' + bust())).json(); }
  catch (e) { return {}; }
}

export async function fetchOperators() {
  try { return await (await fetch('../results/operators.json' + bust())).json(); }
  catch (e) { return {}; }
}

const pipeCache = {};
export async function fetchPipe(label) {
  if (pipeCache[label] !== undefined) return pipeCache[label];
  try {
    const r = await fetch(`../results/pipelines/${label}.json` + bust());
    if (!r.ok) return null;                 // don't cache a miss
    const j = await r.json();
    pipeCache[label] = j;
    return j;
  } catch (e) { return null; }
}

const goldCache = {};
export async function fetchGold(id) {
  if (goldCache[id] !== undefined) return goldCache[id];
  try {
    const r = await fetch(`../gold/${id}.json` + bust());
    if (!r.ok) return null;
    goldCache[id] = (await r.json()).gold;
    return goldCache[id];
  } catch (e) { return null; }
}

const resultsCache = {};
export async function fetchResults(label) {
  if (resultsCache[label]) return resultsCache[label];
  try {
    const j = await (await fetch(`../results/${label}.json` + bust())).json();
    resultsCache[label] = j;
    return j;
  } catch (e) { return null; }
}

let programText = null;
export async function programLine(label) {
  if (programText === null) {
    try { programText = await (await fetch('../program.md' + bust())).text(); }
    catch (e) { programText = ''; }
  }
  const e = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const m = programText.match(new RegExp('^\\s*-\\s.*\\b' + e + '\\b.*$', 'mi'));
  return m ? m[0].replace(/^\s*-\s*/, '').replace(/\*\*/g, '') : '';
}
