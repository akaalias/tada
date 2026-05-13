import SwiftUI
import WebKit

// MARK: - SwiftUI host

/// Force-directed graph of the entire knowledge base. Runs inside a transparent WKWebView so the
/// canvas inherits SwiftUI's light/dark background; the CSS palette flips via
/// `prefers-color-scheme`. Node clicks bridge back to the host through a `(String) -> Void`
/// callback — callers decide what to do with the wiki-relative path.
struct KnowledgeGraphView: View {
    @Environment(\.appServices) private var appServices
    @Environment(\.colorScheme) private var colorScheme
    @State private var dataJSON: String? = nil
    @State private var refreshTick: Int = 0

    let onNodeClick: (String) -> Void

    var body: some View {
        ZStack {
            if let json = dataJSON {
                GraphWebView(dataJSON: json, refreshTick: refreshTick, onNodeClick: onNodeClick)
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
        let data = await kb.buildGraphData()
        if let bytes = try? JSONEncoder().encode(data),
           let str = String(data: bytes, encoding: .utf8) {
            dataJSON = str
            refreshTick &+= 1
        }
    }
}

// MARK: - WKWebView wrapper

private struct GraphWebView: NSViewRepresentable {
    let dataJSON: String
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
        let html = Self.htmlTemplate.replacingOccurrences(of: "__TADA_DATA_JSON__", with: dataJSON)
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
    /// strong charge repulsion to spread clusters out, tight parent-link distance so a task and
    /// its notes form a starburst, and the natural settling produces a roughly circular envelope.
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
        --node-task: #3a3a3a;
        --node-note: #6e6c69;
        --node-entity: #161616;
        --hover: #b54923;
      }
      @media (prefers-color-scheme: dark) {
        :root {
          --ink: #ededed;
          --muted: #989590;
          --rule: rgba(255,255,255,0.18);
          --node-task: #c8c8c5;
          --node-note: #7a7773;
          --node-entity: #ededed;
          --hover: #e08562;
        }
      }
      html, body { margin: 0; padding: 0; background: transparent; height: 100%; overflow: hidden; }
      body { font-family: 'Iowan Old Style','Palatino','Charter','Georgia',serif; color: var(--ink); }
      #graph { position: absolute; inset: 0; }
      .legend {
        position: absolute; left: 16px; bottom: 14px; font-size: 11px;
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
        <span><span class="swatch" style="background: var(--node-task);"></span>Task</span>
        <span><span class="swatch" style="background: var(--node-note);"></span>Note</span>
        <span><span class="swatch" style="background: var(--node-entity);"></span>Entity</span>
      </div>
      <script>
        const data = __TADA_DATA_JSON__;
        const el = document.getElementById('graph');
        const readPalette = () => {
          const cs = getComputedStyle(document.documentElement);
          return {
            ink: cs.getPropertyValue('--ink').trim(),
            muted: cs.getPropertyValue('--muted').trim(),
            rule: cs.getPropertyValue('--rule').trim(),
            task: cs.getPropertyValue('--node-task').trim(),
            note: cs.getPropertyValue('--node-note').trim(),
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
          const nodeColor = (n) => n.kind === 'entity' ? palette.entity
                                : n.kind === 'task'   ? palette.task
                                                       : palette.note;

          // Node size scales with degree (in + out). Compute once up front. Same shape per kind
          // (task/entity vs note) just smaller base radius, then sqrt-scaled by degree so a node
          // with 16 connections is ~4× the area of an isolated one, not 16×.
          const degree = new Map();
          data.nodes.forEach(n => degree.set(n.id, 0));
          data.links.forEach(l => {
            const s = typeof l.source === 'object' ? l.source.id : l.source;
            const t = typeof l.target === 'object' ? l.target.id : l.target;
            degree.set(s, (degree.get(s) || 0) + 1);
            degree.set(t, (degree.get(t) || 0) + 1);
          });
          const nodeSize = (n) => {
            const base = n.kind === 'note' ? 1.6 : 2.4;
            const d = degree.get(n.id) || 0;
            return base + Math.sqrt(d) * 0.9;
          };

          // Threshold above which note labels appear. Tasks + entities still need a higher
          // bar than before so the canvas stays calm until the user zooms in.
          const LABEL_ZOOM = { task: 1.8, entity: 1.8, note: 4.2 };
          const isLabelVisibleOnCanvas = (n, scale) => scale > (LABEL_ZOOM[n.kind] || 4.2);

          let hoverId = null;

          // Track the current zoom so the hover tooltip can suppress itself when the canvas
          // already paints the label at that zoom level.
          let currentScale = 1;
          const Graph = ForceGraph()(el)
            .graphData(data)
            .backgroundColor('rgba(0,0,0,0)')
            .nodeId('id')
            // Suppress the built-in tooltip when the canvas-painted label is already visible.
            .nodeLabel(n => isLabelVisibleOnCanvas(n, currentScale) ? '' : n.title)
            .nodeRelSize(1)
            .linkColor(() => palette.rule)
            .linkWidth(0.6)
            .linkCurvature(0.18)
            .cooldownTicks(180)
            .d3AlphaDecay(0.018)
            .d3VelocityDecay(0.4)
            .warmupTicks(40)
            .onZoom(({ k }) => { currentScale = k; })
            .onNodeHover(n => { hoverId = n ? n.id : null; el.style.cursor = n ? 'pointer' : 'default'; })
            .onNodeClick(n => {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tada) {
                window.webkit.messageHandlers.tada.postMessage({ kind: 'nodeClick', id: n.id });
              }
            })
            .nodeCanvasObject((node, ctx, globalScale) => {
              const r = nodeSize(node);
              ctx.beginPath();
              ctx.arc(node.x, node.y, r, 0, 2 * Math.PI);
              ctx.fillStyle = node.id === hoverId ? palette.hover : nodeColor(node);
              ctx.fill();
              if (isLabelVisibleOnCanvas(node, globalScale) && node.title) {
                ctx.font = `${10 / Math.min(globalScale, 1.4)}px Iowan Old Style, Palatino, Georgia, serif`;
                ctx.fillStyle = node.id === hoverId ? palette.hover : palette.muted;
                ctx.textAlign = 'left';
                ctx.textBaseline = 'middle';
                ctx.fillText(node.title, node.x + r + 4, node.y);
              }
            })
            .nodeCanvasObjectMode(() => 'replace');

          // Force tuning for Obsidian-style clusters:
          //   - Strong charge → wide separation between unrelated clusters
          //   - Tight, strict parent links → tasks form starbursts with their notes
          //   - Looser entity / related links → soft pull, no rigidity
          //   - Gentle radial force → keeps the overall envelope roughly circular
          const linkForce = Graph.d3Force('link');
          if (linkForce) {
            linkForce
              .distance(l => l.kind === 'parent' ? 22 : (l.kind === 'related' ? 90 : 70))
              .strength(l => l.kind === 'parent' ? 1.0 : (l.kind === 'related' ? 0.15 : 0.25));
          }
          const charge = Graph.d3Force('charge');
          if (charge) charge.strength(n => n.kind === 'task' ? -260 : (n.kind === 'entity' ? -160 : -90));

          if (window.d3 && window.d3.forceRadial) {
            // Keep loosely-attached nodes (entities + relateds) on a generous outer ring so the
            // whole graph reads as a circle. Tasks float freely in the middle.
            const radial = window.d3.forceRadial(260, 0, 0).strength(n => n.kind === 'task' ? 0 : 0.04);
            Graph.d3Force('radial', radial);
          }

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
