import SwiftUI
import SwiftData
import WebKit

// MARK: - SwiftUI host

/// Force-directed graph of the entire knowledge base. Runs inside a transparent WKWebView so the
/// canvas inherits SwiftUI's light/dark background; the CSS palette flips via
/// `prefers-color-scheme`. Node clicks bridge back to the host through a `(String) -> Void`
/// callback — callers decide what to do with the wiki-relative path.
struct KnowledgeGraphView: View {
    @Environment(\.appServices) private var appServices
    @Environment(\.colorScheme) private var colorScheme
    @Query private var allTasks: [TodoTask]
    @State private var dataJSON: String? = nil
    @State private var taskStatesJSON: String = "{}"
    @State private var refreshTick: Int = 0

    let onNodeClick: (String) -> Void

    var body: some View {
        ZStack {
            if let json = dataJSON {
                GraphWebView(dataJSON: json, taskStatesJSON: taskStatesJSON,
                             refreshTick: refreshTick, onNodeClick: onNodeClick)
            } else {
                ProgressView("Building graph…")
                    .controlSize(.small)
                    .foregroundColor(.secondary)
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .knowledgeBaseUpdated)) { _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        guard let kb = appServices?.knowledgeBase else { return }
        // Graph shows only tasks that still exist and aren't archived. Wiki
        // folders for deleted or archived tasks linger on disk — filter them out.
        let liveTaskIds = Set(allTasks.filter { $0.status != .archived }.map(\.id.uuidString))
        let data = await kb.buildGraphData().keepingTasks(in: liveTaskIds)
        // Top-level task node colour reflects the owning task's live state.
        var states: [String: String] = [:]
        for task in allTasks {
            states[task.id.uuidString] = GraphTaskState(task: task).rawValue
        }
        guard let dataBytes = try? JSONEncoder().encode(data),
              let dataStr = String(data: dataBytes, encoding: .utf8),
              let statesBytes = try? JSONEncoder().encode(states),
              let statesStr = String(data: statesBytes, encoding: .utf8) else { return }
        dataJSON = dataStr
        taskStatesJSON = statesStr
        refreshTick &+= 1
    }
}

// MARK: - WKWebView wrapper

private struct GraphWebView: NSViewRepresentable {
    let dataJSON: String
    let taskStatesJSON: String
    let refreshTick: Int
    let onNodeClick: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "tada")
        let webView = WKWebView(frame: .zero, configuration: config)
        // Transparent web view so SwiftUI's light/dark background shows through.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        context.coordinator.webView = webView
        loadGraph(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastRenderedTick != refreshTick {
            context.coordinator.lastRenderedTick = refreshTick
            loadGraph(into: webView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onClick: onNodeClick) }

    private func loadGraph(into webView: WKWebView) {
        let html = Self.htmlTemplate
            .replacingOccurrences(of: "__TADA_DATA_JSON__", with: dataJSON)
            .replacingOccurrences(of: "__TADA_TASK_STATES_JSON__", with: taskStatesJSON)
        webView.loadHTMLString(html, baseURL: URL(string: "https://tada.local/"))
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onClick: (String) -> Void
        weak var webView: WKWebView?
        var lastRenderedTick: Int = -1

        init(onClick: @escaping (String) -> Void) { self.onClick = onClick }

        func userContentController(_ uc: WKUserContentController, didReceive msg: WKScriptMessage) {
            guard let dict = msg.body as? [String: Any],
                  let kind = dict["kind"] as? String else { return }
            switch kind {
            case "nodeClick":
                if let id = dict["id"] as? String { onClick(id) }
            default:
                break
            }
        }
    }

    // MARK: - HTML template (Tufte-styled, dark-mode aware via prefers-color-scheme)

    /// Self-contained HTML. The body is transparent so the underlying SwiftUI surface (which
    /// already respects appearance) is the background. Foreground colours flip via
    /// `prefers-color-scheme: dark`. Forces are tuned for Obsidian-style circular clustering:
    /// strong charge repulsion to spread clusters out, relaxed link distances so tasks and their
    /// sub-tasks stay grouped with breathing room, settling into a roughly circular envelope.
    private static let htmlTemplate: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      :root {
        --ink: #1a1a1a;
        --muted: #6b6864;
        --rule: rgba(20,18,14,0.22);
        --state-discovery: #c8762a;
        --state-execution: #2f6fce;
        --state-completed: #1f9d78;
        --node-entity: #8f8c87;
        --hover: #b54923;
      }
      @media (prefers-color-scheme: dark) {
        :root {
          --ink: #ededed;
          --muted: #989590;
          --rule: rgba(255,255,255,0.18);
          --state-discovery: #e8a04f;
          --state-execution: #5e9bf2;
          --state-completed: #3fc9a3;
          --node-entity: #807d79;
          --hover: #e08562;
        }
      }
      html, body { margin: 0; padding: 0; background: transparent; height: 100%; overflow: hidden; }
      body { font-family: 'Iowan Old Style','Palatino','Charter','Georgia',serif; color: var(--ink); }
      #graph { position: absolute; inset: 0; }
      .legend {
        position: absolute; left: 16px; bottom: 14px; font-size: 11px;
        font-family: -apple-system, system-ui, 'Helvetica Neue', sans-serif;
        color: var(--muted); letter-spacing: 0.02em;
        display: flex; gap: 18px; align-items: center; pointer-events: none;
      }
      .legend .swatch { display: inline-block; width: 8px; height: 8px; border-radius: 50%;
        margin-right: 6px; vertical-align: middle; }
      .empty {
        position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
        color: var(--muted); font-style: italic; font-size: 14px;
      }
    </style>
    <script src="https://unpkg.com/force-graph@1.43.4/dist/force-graph.min.js"></script>
    </head>
    <body>
      <div id="graph"></div>
      <div class="legend">
        <span><span class="swatch" style="background: var(--state-discovery);"></span>Discovery</span>
        <span><span class="swatch" style="background: var(--state-execution);"></span>Execution</span>
        <span><span class="swatch" style="background: var(--state-completed);"></span>Completed</span>
        <span><span class="swatch" style="background: var(--node-entity);"></span>Entity</span>
      </div>
      <script>
        const data = __TADA_DATA_JSON__;
        // Map of task UUID → state key: "discovery" | "execution" | "completed".
        const taskStates = __TADA_TASK_STATES_JSON__;
        const el = document.getElementById('graph');
        const readPalette = () => {
          const cs = getComputedStyle(document.documentElement);
          return {
            ink: cs.getPropertyValue('--ink').trim(),
            muted: cs.getPropertyValue('--muted').trim(),
            rule: cs.getPropertyValue('--rule').trim(),
            discovery: cs.getPropertyValue('--state-discovery').trim(),
            execution: cs.getPropertyValue('--state-execution').trim(),
            completed: cs.getPropertyValue('--state-completed').trim(),
            entity: cs.getPropertyValue('--node-entity').trim(),
            hover: cs.getPropertyValue('--hover').trim(),
          };
        };
        let palette = readPalette();
        // Re-read palette if the system flips appearance.
        const themeMQ = window.matchMedia('(prefers-color-scheme: dark)');
        themeMQ.addEventListener('change', () => { palette = readPalette(); if (window.__Graph) window.__Graph.refresh(); });

        if (!data.nodes || data.nodes.length === 0) {
          const empty = document.createElement('div');
          empty.className = 'empty';
          empty.textContent = 'No notes yet — your wiki will appear here once you complete sub-tasks.';
          document.body.appendChild(empty);
        } else {
          // Colour reflects state: a top-level task takes the colour of its
          // owning task's live state; sub-tasks are always completed (emerald)
          // for now; entities are a neutral grey.
          const stateColor = (s) => s === 'discovery' ? palette.discovery
                                  : s === 'execution' ? palette.execution
                                  : palette.completed;
          const nodeColor = (n) => {
            if (n.kind === 'entity') return palette.entity;
            if (n.kind === 'subTask') return palette.completed;
            const state = taskStates[n.taskId];
            return state ? stateColor(state) : palette.entity;
          };

          // Node size scales with degree (in + out). Compute once up front. Same base radius
          // per kind (top-level task / entity vs sub-task), then sqrt-scaled by degree so a node
          // with 16 connections is ~4× the area of an isolated one, not 16×.
          const degree = new Map();
          // Adjacency: nodeId → Set of directly connected nodeIds, used to
          // highlight a hovered node's immediate neighbourhood.
          const neighbors = new Map();
          data.nodes.forEach(n => { degree.set(n.id, 0); neighbors.set(n.id, new Set()); });
          data.links.forEach(l => {
            const s = typeof l.source === 'object' ? l.source.id : l.source;
            const t = typeof l.target === 'object' ? l.target.id : l.target;
            degree.set(s, (degree.get(s) || 0) + 1);
            degree.set(t, (degree.get(t) || 0) + 1);
            neighbors.get(s) && neighbors.get(s).add(t);
            neighbors.get(t) && neighbors.get(t).add(s);
          });
          const nodeSize = (n) => {
            const base = n.kind === 'subTask' ? 1.6 : 2.4;
            const d = degree.get(n.id) || 0;
            return base + Math.sqrt(d) * 0.9;
          };

          // Entities stay circles; tasks and sub-tasks are drawn as rounded
          // rectangles. `r` is the sizing radius — the square is 2r per side.
          const traceNode = (node, ctx) => {
            const r = nodeSize(node);
            ctx.beginPath();
            if (node.kind === 'entity') {
              ctx.arc(node.x, node.y, r, 0, 2 * Math.PI);
            } else {
              ctx.roundRect(node.x - r, node.y - r, r * 2, r * 2, r * 0.55);
            }
          };

          // Multiplies an #rrggbb colour toward black (factor < 1 darkens).
          const darken = (hex, factor) => {
            const h = hex.replace('#', '');
            const f = h.length === 3 ? h.split('').map(c => c + c).join('') : h;
            const ch = i => Math.round(parseInt(f.substr(i, 2), 16) * factor);
            return `rgb(${ch(0)},${ch(2)},${ch(4)})`;
          };

          // Returns `color` with `alpha` applied. Accepts #rgb / #rrggbb or rgb()/rgba().
          const withAlpha = (color, alpha) => {
            if (color.startsWith('#')) {
              const h = color.replace('#', '');
              const f = h.length === 3 ? h.split('').map(c => c + c).join('') : h;
              const ch = i => parseInt(f.substr(i, 2), 16);
              return `rgba(${ch(0)},${ch(2)},${ch(4)},${alpha})`;
            }
            const n = color.match(/[\\d.]+/g) || [0, 0, 0];
            return `rgba(${n[0]},${n[1]},${n[2]},${alpha})`;
          };
          // Parses #rgb / #rrggbb / rgb() / rgba() to an [r,g,b,a] array.
          const parseColor = (color) => {
            if (color.startsWith('#')) {
              const h = color.replace('#', '');
              const f = h.length === 3 ? h.split('').map(c => c + c).join('') : h;
              const v = i => parseInt(f.substr(i, 2), 16);
              return [v(0), v(2), v(4), 1];
            }
            const n = (color.match(/[\\d.]+/g) || [0, 0, 0]).map(Number);
            return [n[0] || 0, n[1] || 0, n[2] || 0, n[3] == null ? 1 : n[3]];
          };
          // Per-frame easing factor for hover highlight transitions (~0.3s in/out).
          const HL_EASE = 0.2;

          // --- Task-folder cluster backgrounds -------------------------------------------
          // Andrew's monotone-chain convex hull. Returns the hull vertices, or the input
          // points unchanged for a degenerate (fewer than 3 distinct/collinear) set.
          const convexHull = (pts) => {
            if (pts.length < 3) return pts.slice();
            const p = pts.slice().sort((a, b) => a.x - b.x || a.y - b.y);
            const cross = (o, a, b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
            const lower = [];
            for (const pt of p) {
              while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], pt) <= 0) lower.pop();
              lower.push(pt);
            }
            const upper = [];
            for (let i = p.length - 1; i >= 0; i--) {
              const pt = p[i];
              while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], pt) <= 0) upper.pop();
              upper.push(pt);
            }
            lower.pop(); upper.pop();
            const h = lower.concat(upper);
            return h.length >= 3 ? h : pts.slice();
          };

          // Groups: task folders get one blob each (convex hull); entities get one
          // blob per connected component using metaballs for organic shapes.
          const folderGroups = (() => {
            const groups = [];
            // Task folders: group by path prefix (non-entities only).
            const byFolder = new Map();
            data.nodes.forEach(n => {
              if (n.kind === 'entity') return;
              const folder = n.id.split('/').slice(0, 2).join('/');
              if (!byFolder.has(folder)) byFolder.set(folder, []);
              byFolder.get(folder).push(n);
            });
            byFolder.forEach(nodes => {
              if (nodes.length < 2) return;
              const top = nodes.find(n => n.kind === 'topLevelTask') || nodes[0];
              groups.push({ nodes, top, pad: Math.max(...nodes.map(nodeSize)) + 9, isEntity: false });
            });
            // Entity clusters: find connected components via BFS.
            const entities = data.nodes.filter(n => n.kind === 'entity');
            if (entities.length >= 2) {
              const visited = new Set();
              const findComponent = (start) => {
                const component = [];
                const queue = [start.id];
                visited.add(start.id);
                while (queue.length > 0) {
                  const id = queue.shift();
                  const node = data.nodes.find(n => n.id === id);
                  if (node) component.push(node);
                  const adj = neighbors.get(id) || new Set();
                  for (const nid of adj) {
                    if (!visited.has(nid)) {
                      visited.add(nid);
                      queue.push(nid);
                    }
                  }
                }
                return component;
              };
              for (const e of entities) {
                if (visited.has(e.id)) continue;
                const component = findComponent(e);
                const entitiesInComponent = component.filter(n => n.kind === 'entity');
                if (entitiesInComponent.length >= 2) {
                  groups.push({
                    nodes: entitiesInComponent,
                    top: entitiesInComponent[0],
                    pad: Math.max(...entitiesInComponent.map(nodeSize)) + 9,
                    isEntity: true
                  });
                }
              }
            }
            return groups;
          })();

          // DBSCAN-style spatial clustering: groups nearby points into clusters.
          // Returns array of point arrays, one per cluster.
          const spatialCluster = (pts, eps) => {
            const clusters = [];
            const visited = new Set();
            const getNeighbors = (p) => pts.filter(q => q !== p && Math.hypot(q.x - p.x, q.y - p.y) <= eps);

            for (const p of pts) {
              if (visited.has(p)) continue;
              visited.add(p);
              const neighbors = getNeighbors(p);
              const cluster = [p];
              const queue = [...neighbors];
              while (queue.length > 0) {
                const q = queue.shift();
                if (visited.has(q)) continue;
                visited.add(q);
                cluster.push(q);
                const qNeighbors = getNeighbors(q);
                queue.push(...qNeighbors.filter(n => !visited.has(n)));
              }
              clusters.push(cluster); // Include all clusters, even single nodes
            }
            return clusters;
          };

          // Draws a soft rounded wrapper behind each cluster. Task folders use convex
          // hull; entity clusters use spatial clustering for organic sub-groups.
          const drawFolderGroups = (ctx) => {
            for (const g of folderGroups) {
              const pts = g.nodes.filter(n => n.x != null && n.y != null);
              if (pts.length < 2) continue;
              // Entity groups: spatially cluster and draw separate hulls for each
              if (g.isEntity) {
                const eps = g.pad * 4; // Distance threshold for clustering (larger = more connected)
                const clusters = spatialCluster(pts, eps);
                for (const cluster of clusters) {
                  ctx.beginPath();
                  if (cluster.length === 1) {
                    // Single node: draw a circle
                    ctx.arc(cluster[0].x, cluster[0].y, g.pad, 0, 2 * Math.PI);
                  } else if (cluster.length === 2) {
                    // Two nodes: capsule shape
                    const a = cluster[0], b = cluster[1];
                    const ang = Math.atan2(b.y - a.y, b.x - a.x);
                    ctx.arc(b.x, b.y, g.pad, ang - Math.PI / 2, ang + Math.PI / 2);
                    ctx.arc(a.x, a.y, g.pad, ang + Math.PI / 2, ang + 3 * Math.PI / 2);
                  } else {
                    // 3+ nodes: padded convex hull
                    const hull = convexHull(cluster);
                    const n = hull.length;
                    let cx = 0, cy = 0;
                    for (const p of hull) { cx += p.x; cy += p.y; }
                    cx /= n; cy /= n;
                    const norm = [];
                    for (let i = 0; i < n; i++) {
                      const a = hull[i], b = hull[(i + 1) % n];
                      let nx = b.y - a.y, ny = -(b.x - a.x);
                      const L = Math.hypot(nx, ny) || 1;
                      nx /= L; ny /= L;
                      if (((a.x + b.x) / 2 - cx) * nx + ((a.y + b.y) / 2 - cy) * ny < 0) { nx = -nx; ny = -ny; }
                      norm.push({ x: nx, y: ny });
                    }
                    const STEPS = 6;
                    let started = false;
                    for (let i = 0; i < n; i++) {
                      const v = hull[i];
                      const a0 = Math.atan2(norm[(i - 1 + n) % n].y, norm[(i - 1 + n) % n].x);
                      const a1 = Math.atan2(norm[i].y, norm[i].x);
                      let da = a1 - a0;
                      while (da > Math.PI) da -= 2 * Math.PI;
                      while (da < -Math.PI) da += 2 * Math.PI;
                      for (let k = 0; k <= STEPS; k++) {
                        const ang = a0 + da * (k / STEPS);
                        const px = v.x + g.pad * Math.cos(ang);
                        const py = v.y + g.pad * Math.sin(ang);
                        if (!started) { ctx.moveTo(px, py); started = true; } else ctx.lineTo(px, py);
                      }
                    }
                  }
                  ctx.closePath();
                  ctx.fillStyle = withAlpha(nodeColor(g.top), 0.1);
                  ctx.fill();
                }
                continue;
              }
              // Task folders: also use spatial clustering for sub-groups
              const eps = g.pad * 4;
              const clusters = spatialCluster(pts, eps);
              for (const cluster of clusters) {
                ctx.beginPath();
                if (cluster.length === 1) {
                  ctx.arc(cluster[0].x, cluster[0].y, g.pad, 0, 2 * Math.PI);
                } else if (cluster.length === 2) {
                  const a = cluster[0], b = cluster[1];
                  const ang = Math.atan2(b.y - a.y, b.x - a.x);
                  ctx.arc(b.x, b.y, g.pad, ang - Math.PI / 2, ang + Math.PI / 2);
                  ctx.arc(a.x, a.y, g.pad, ang + Math.PI / 2, ang + 3 * Math.PI / 2);
                } else {
                  const hull = convexHull(cluster);
                  const n = hull.length;
                  let cx = 0, cy = 0;
                  for (const p of hull) { cx += p.x; cy += p.y; }
                  cx /= n; cy /= n;
                  const norm = [];
                  for (let i = 0; i < n; i++) {
                    const a = hull[i], b = hull[(i + 1) % n];
                    let nx = b.y - a.y, ny = -(b.x - a.x);
                    const L = Math.hypot(nx, ny) || 1;
                    nx /= L; ny /= L;
                    if (((a.x + b.x) / 2 - cx) * nx + ((a.y + b.y) / 2 - cy) * ny < 0) { nx = -nx; ny = -ny; }
                    norm.push({ x: nx, y: ny });
                  }
                  const STEPS = 6;
                  let started = false;
                  for (let i = 0; i < n; i++) {
                    const v = hull[i];
                    const a0 = Math.atan2(norm[(i - 1 + n) % n].y, norm[(i - 1 + n) % n].x);
                    const a1 = Math.atan2(norm[i].y, norm[i].x);
                    let da = a1 - a0;
                    while (da > Math.PI) da -= 2 * Math.PI;
                    while (da < -Math.PI) da += 2 * Math.PI;
                    for (let k = 0; k <= STEPS; k++) {
                      const ang = a0 + da * (k / STEPS);
                      const px = v.x + g.pad * Math.cos(ang);
                      const py = v.y + g.pad * Math.sin(ang);
                      if (!started) { ctx.moveTo(px, py); started = true; } else ctx.lineTo(px, py);
                    }
                  }
                }
                ctx.closePath();
                ctx.fillStyle = withAlpha(nodeColor(g.top), 0.1);
                ctx.fill();
              }
            }
          };

          let hoverId = null;
          // With a node hovered: that node + its neighbours stay at full strength,
          // the edges touching it are emphasised, everything else fades back.
          const nodeHighlighted = (node) =>
            hoverId == null || node.id === hoverId
            || (neighbors.get(hoverId) && neighbors.get(hoverId).has(node.id));
          const linkHighlighted = (link) => {
            if (hoverId == null) return true;
            const s = typeof link.source === 'object' ? link.source.id : link.source;
            const t = typeof link.target === 'object' ? link.target.id : link.target;
            return s === hoverId || t === hoverId;
          };

          const Graph = ForceGraph()(el)
            .graphData(data)
            .backgroundColor('rgba(0,0,0,0)')
            .nodeId('id')
            // Title is drawn on-canvas below the hovered node (see nodeCanvasObject);
            // the built-in cursor-following tooltip is disabled.
            .nodeLabel(() => '')
            .nodeRelSize(1)
            // Keep repainting after the simulation cools, otherwise the hover
            // label only updates when a zoom/pan happens to trigger a redraw.
            .autoPauseRedraw(false)
            .linkColor(link => {
              // Links invisible by default, only show on hover
              const target = parseColor(
                hoverId == null ? 'rgba(0,0,0,0)'
                : linkHighlighted(link) ? withAlpha(palette.ink, 0.5)
                                        : 'rgba(0,0,0,0)');
              const cur = link.__col || (link.__col = target.slice());
              for (let i = 0; i < 4; i++) cur[i] += (target[i] - cur[i]) * HL_EASE;
              return `rgba(${cur[0]|0},${cur[1]|0},${cur[2]|0},${cur[3].toFixed(3)})`;
            })
            .linkWidth(link => {
              const target = hoverId != null && linkHighlighted(link) ? 1.4 : 0;
              link.__w = link.__w == null ? target : link.__w + (target - link.__w) * HL_EASE;
              return link.__w;
            })
            .linkCurvature(0.18)
            .cooldownTicks(180)
            .d3AlphaDecay(0.018)
            .d3VelocityDecay(0.4)
            // High warmup so the first painted frame is already spread out,
            // rather than the user watching a tight blob relax.
            .warmupTicks(120)
            .onNodeHover(n => { hoverId = n ? n.id : null; el.style.cursor = n ? 'pointer' : 'default'; })
            .onNodeClick(n => {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tada) {
                window.webkit.messageHandlers.tada.postMessage({ kind: 'nodeClick', id: n.id });
              }
            })
            .nodeCanvasObject((node, ctx) => {
              const base = nodeColor(node);
              // Ease per-node dim / hover levels so the highlight fades in and
              // out instead of snapping when the cursor enters or leaves.
              const dimTarget = hoverId != null && !nodeHighlighted(node) ? 1 : 0;
              const hovTarget = node.id === hoverId ? 1 : 0;
              node.__dim = node.__dim == null ? dimTarget : node.__dim + (dimTarget - node.__dim) * HL_EASE;
              node.__hov = node.__hov == null ? hovTarget : node.__hov + (hovTarget - node.__hov) * HL_EASE;
              const dim = node.__dim, hov = node.__hov;
              traceNode(node, ctx);
              // Hovered node eases toward its darkened tint; everything else
              // eases between full colour and 12% alpha as it dims.
              ctx.fillStyle = hov > 0.01 ? darken(base, 1 - 0.4 * hov)
                                         : withAlpha(base, 1 - 0.88 * dim);
              ctx.fill();
              if (node.kind !== 'entity') {
                // Slightly darker, thick border on task / sub-task cards.
                ctx.lineWidth = Math.max(0.7, nodeSize(node) * 0.4);
                ctx.strokeStyle = withAlpha(darken(base, 0.7 - 0.28 * hov), 1 - 0.88 * dim);
                ctx.stroke();
              }
            })
            .nodeCanvasObjectMode(() => 'replace')
            // Hit area = the whole node shape, so hover fires anywhere on it
            // rather than only the tiny default dot at its centre.
            .nodePointerAreaPaint((node, color, ctx) => {
              traceNode(node, ctx);
              ctx.fillStyle = color;
              ctx.fill();
            })
            // Task-folder cluster wrappers are drawn first, behind links and nodes.
            .onRenderFramePre((ctx) => { drawFolderGroups(ctx); })
            // The hovered node's title is drawn in a post pass — after every
            // node — so it is never painted over by a neighbouring node.
            .onRenderFramePost((ctx, globalScale) => {
              if (!hoverId) return;
              const node = data.nodes.find(n => n.id === hoverId);
              if (!node || !node.title || node.x == null) return;
              const r = nodeSize(node);
              const fontSize = 12 / globalScale;
              ctx.font = `${fontSize}px -apple-system, system-ui, 'Helvetica Neue', sans-serif`;
              ctx.textAlign = 'center';
              ctx.textBaseline = 'middle';
              const padX = 6 / globalScale;
              const padY = 4 / globalScale;
              const boxW = ctx.measureText(node.title).width + padX * 2;
              const boxH = fontSize + padY * 2;
              const boxX = node.x - boxW / 2;
              // Label sits above the node, clear of its circle.
              const boxY = node.y - r - 2 / globalScale - boxH;
              // Label background uses the hovered node's darkened colour.
              ctx.fillStyle = darken(nodeColor(node), 0.6);
              ctx.beginPath();
              ctx.roundRect(boxX, boxY, boxW, boxH, 3 / globalScale);
              ctx.fill();
              ctx.fillStyle = '#ffffff';
              ctx.fillText(node.title, node.x, boxY + boxH / 2);
            });

          // Force tuning for Obsidian-style clusters:
          //   - Strong charge → wide separation between unrelated clusters
          //   - Tight, strict parent links → tasks form starbursts with their sub-tasks
          //   - Looser entity / related links → soft pull, no rigidity
          //   - Gentle radial force → keeps the overall envelope roughly circular
          const linkForce = Graph.d3Force('link');
          if (linkForce) {
            linkForce
              .distance(22)
              .strength(l => l.kind === 'parent' ? 1.0 : (l.kind === 'related' ? 0.15 : 0.25));
          }
          const charge = Graph.d3Force('charge');
          if (charge) charge.strength(n => n.kind === 'topLevelTask' ? -260 : (n.kind === 'entity' ? -160 : -90));

          // Pull every node toward the origin so otherwise-disconnected task clusters can't
          // drift apart — link distance can't help there, since most clusters share no edges.
          // force-graph's bundle doesn't expose d3's forceRadial, so this is a hand-rolled
          // gravity force (same shape as d3.forceX/forceY centred on 0,0).
          const gravityStrength = 0.2;
          let gravityNodes = [];
          const gravity = (alpha) => {
            for (const n of gravityNodes) {
              n.vx -= n.x * gravityStrength * alpha;
              n.vy -= n.y * gravityStrength * alpha;
            }
          };
          gravity.initialize = (nodes) => { gravityNodes = nodes; };
          Graph.d3Force('gravity', gravity);

          // Initial fit. Re-fit once when the engine cools down so the user always sees the
          // whole graph on open, regardless of how long the simulation takes.
          let fitted = false;
          Graph.onEngineStop(() => {
            if (!fitted) { Graph.zoomToFit(600, 60); fitted = true; }
          });
          // Fallback in case onEngineStop is delayed.
          setTimeout(() => { if (!fitted) { Graph.zoomToFit(600, 60); fitted = true; } }, 2500);

          window.__Graph = Graph;
          window.addEventListener('resize', () => {
            Graph.width(window.innerWidth).height(window.innerHeight);
          });
        }
      </script>
    </body>
    </html>
    """
}
