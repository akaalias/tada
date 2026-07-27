// §4 "How we evolved our champion": the mined experiment-lineage graph, reused
// verbatim from lineage.js (same data, same rendering, same hover isolation) —
// centre-scrolled to the champion on load, but not pre-isolated: the graph
// starts fully lit, same as hovering nothing on the standalone lineage page.
import { load, render } from './lineage.js';

const CHAMPION = 'exp056';

load().then(data => render(data, { scrollTo: CHAMPION }))
  .catch(e => { const el = document.getElementById('diagram'); if (el) el.innerHTML = '<p class="muted" style="font-size:14px">failed to load lineage data.</p>'; });
