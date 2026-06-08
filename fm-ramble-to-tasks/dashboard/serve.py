#!/usr/bin/env python3
"""Dev server for the dashboard, with caching disabled so refreshes always show the
latest results. Serves from the package root (fm-ramble-to-tasks) so /dashboard,
/results, and /gold all resolve.

Usage: python3 dashboard/serve.py [port]   (default 8766)
"""
import http.server, socketserver, os, sys

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8766


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        super().end_headers()
    def log_message(self, *a):  # quiet
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("", PORT), NoCacheHandler) as httpd:
    print(f"dashboard (no-cache) on http://localhost:{PORT}/dashboard/")
    httpd.serve_forever()
