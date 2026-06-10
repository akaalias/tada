// Autoresearch loop diagram — a static SVG (no data fetch) shared by report.html
// and onboarding.html. Five automated steps orbit the judge at the centre;
// the human supervisor feeds in from the side (rust). Matches the Tufte tokens in
// tufte.css (var(--ink) / --muted / --faint / --rule / --accent), so it inherits
// each page's colours. Injects into every element with class "autoresearch-loop".

const C = { x: 370, y: 255 }, R = 165;
const pt = (deg, r = R) => ({
  x: C.x + r * Math.cos(deg * Math.PI / 180),
  y: C.y + r * Math.sin(deg * Math.PI / 180),
});

// The five steps, placed clockwise from the top (pentagon vertices 72° apart).
// lx/ty/dy position the two-line label relative to the node; anchor sets its side.
const STEPS = [
  { deg: -90, n: 1, t: 'READ',        d: ['the run log +', "the judge's failure notes"], anchor: 'middle', lx: 0,   ty: -54, dy: -37 },
  { deg: -18, n: 2, t: 'HYPOTHESIZE', d: ['one hypothesis —', 'pick a single lever'],     anchor: 'start',  lx: 24,  ty: -3,  dy: 15 },
  { deg:  54, n: 3, t: 'IMPLEMENT',   d: ['edit the mutable', 'agent, then build'],        anchor: 'start',  lx: 18,  ty: 17,  dy: 35 },
  { deg: 126, n: 4, t: 'EVALUATE',    d: ['run all 30 cases', 'through the judge'],        anchor: 'end',    lx: -18, ty: 17,  dy: 35 },
  { deg: 198, n: 5, t: 'LOG',         d: ['score 0–1; keep the', 'best, else discard'],    anchor: 'end',    lx: -24, ty: -3,  dy: 15 },
];

const f = n => (Math.round(n * 100) / 100);

function arcs() {
  // One arrowed arc per gap between consecutive steps, clockwise (increasing angle),
  // inset 14° each end so the arrowheads clear the numbered nodes.
  let out = '';
  for (const s of STEPS) {
    const a = pt(s.deg + 13), b = pt(s.deg + 65);
    out += `<path d="M${f(a.x)} ${f(a.y)} A${R} ${R} 0 0 1 ${f(b.x)} ${f(b.y)}" `
         + `fill="none" stroke="var(--muted)" stroke-width="1.4" marker-end="url(#arw)"/>`;
  }
  return out;
}

function nodes() {
  let out = '';
  for (const s of STEPS) {
    const p = pt(s.deg);
    const lx = p.x + s.lx, ty = p.y + s.ty, dy = p.y + s.dy;
    out += `
      <text x="${f(lx)}" y="${f(ty)}" text-anchor="${s.anchor}"
            font-size="13" letter-spacing="0.6" font-weight="600" fill="var(--ink)">${s.t}</text>
      <text x="${f(lx)}" y="${f(dy)}" text-anchor="${s.anchor}" font-size="12.5" fill="var(--muted)">
        <tspan x="${f(lx)}">${s.d[0]}</tspan>
        <tspan x="${f(lx)}" dy="15">${s.d[1]}</tspan>
      </text>
      <circle cx="${f(p.x)}" cy="${f(p.y)}" r="13" fill="var(--paper)" stroke="var(--ink)" stroke-width="1.3"/>
      <text x="${f(p.x)}" y="${f(p.y + 4)}" text-anchor="middle" font-size="13"
            font-feature-settings="'lnum' 1" fill="var(--ink)">${s.n}</text>`;
  }
  return out;
}

const evalP = pt(126);                       // EVALUATE node — links to the judge

const SVG = `
<svg viewBox="0 0 760 520" style="width:100%;height:auto;max-width:760px;display:block;margin:0 auto"
     font-family="Palatino,Georgia,serif" role="img"
     aria-label="The autoresearch loop: read, hypothesize, implement, evaluate, log — orbiting the judge, supervised by a human.">
  <defs>
    <marker id="arw" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0 0 L10 5 L0 10 z" fill="var(--muted)"/>
    </marker>
    <marker id="arwA" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0 0 L10 5 L0 10 z" fill="var(--accent)"/>
    </marker>
    <marker id="arwF" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M0 0 L10 5 L0 10 z" fill="var(--faint)"/>
    </marker>
  </defs>

  ${arcs()}
  ${nodes()}

  <!-- dashed link: EVALUATE is scored by the judge at the centre -->
  <path d="M285 376 L351 301" fill="none" stroke="var(--faint)"
        stroke-width="1.2" stroke-dasharray="3 4" marker-end="url(#arwF)"/>
  <text x="336" y="350" text-anchor="start" font-size="11.5" font-style="italic" fill="var(--faint)">
    <tspan x="336">scored</tspan><tspan x="336" dy="14">by</tspan></text>

  <!-- the judge at the centre: everything orbits the unchanging evaluator -->
  <line x1="302" y1="226" x2="438" y2="226" stroke="var(--ink)" stroke-width="1.4"/>
  <line x1="302" y1="293" x2="438" y2="293" stroke="var(--ink)" stroke-width="1.4"/>
  <text x="370" y="247" text-anchor="middle" font-size="13" letter-spacing="0.6" font-weight="600" fill="var(--ink)">THE JUDGE</text>
  <text x="370" y="266" text-anchor="middle" font-size="12.5" fill="var(--muted)">30 gold tasks · Sonnet judge</text>
  <text x="370" y="284" text-anchor="middle" font-size="12.5" font-style="italic" fill="var(--accent)">never changes</text>

  <!-- human supervisor feeds direction into HYPOTHESIZE (rust = human input) -->
  <text x="624" y="116" text-anchor="middle" font-size="13" letter-spacing="0.6" font-weight="600" fill="var(--accent)">HUMAN SUPERVISOR</text>
  <text x="624" y="135" text-anchor="middle" font-size="12" fill="var(--muted)">
    <tspan x="624">steers levers · gives feedback</tspan>
    <tspan x="624" dy="15">runs the manual fine-tuning track</tspan>
  </text>
  <path d="M620 172 Q556 174 538 195" fill="none" stroke="var(--accent)" stroke-width="1.3" marker-end="url(#arwA)"/>
  <circle cx="624" cy="168" r="4.5" fill="var(--accent)"/>

  <!-- caption inside the frame: who drives the cycle -->
  <text x="370" y="475" text-anchor="middle" font-size="13" font-style="italic" fill="var(--muted)">
    The cycle runs autonomously — Claude Code, one experiment per turn.</text>
</svg>`;

for (const el of document.querySelectorAll('.autoresearch-loop')) el.innerHTML = SVG;
