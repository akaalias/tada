// Bootstrap for lineage.html: load the data and render the full page (graph +
// legend + pivotal-path table). Supports deep-linking to a run via ?focus=<label>,
// which pre-traces its ancestry and centres the diagram on it without a hover.
import { load, render } from './lineage.js';

const params = new URLSearchParams(location.search);
load().then(data => render(data, { focus: params.get('focus') }))
  .catch(e => { document.getElementById('notes').innerHTML = '<span class="warn">failed to load lineage data: ' + e + '</span>'; });
