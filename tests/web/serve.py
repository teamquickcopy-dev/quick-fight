"""Static server for the web build that serves brotli/gzip like Caddy will in production.
Usage: python3 tests/web/serve.py build/web 8060"""
import gzip, http.server, sys, os

try:
    import brotli
except ImportError:
    brotli = None

ROOT, PORT = sys.argv[1], int(sys.argv[2])
CACHE = {}
TYPES = {".wasm": "application/wasm", ".js": "application/javascript", ".pck": "application/octet-stream",
         ".html": "text/html", ".png": "image/png"}


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/":
            path = "/index.html"
        f = os.path.join(ROOT, path.lstrip("/"))
        if not os.path.isfile(f):
            return self.send_error(404)
        ext = os.path.splitext(f)[1]
        accept = self.headers.get("Accept-Encoding", "")
        enc = "br" if brotli and "br" in accept else ("gzip" if "gzip" in accept else "")
        key = (f, enc)
        if key not in CACHE:
            data = open(f, "rb").read()
            if enc == "br" and ext != ".png":
                data = brotli.compress(data, quality=11)
            elif enc == "gzip" and ext != ".png":
                data = gzip.compress(data, 9)
            else:
                enc = ""
            CACHE[key] = (data, enc)
        data, enc = CACHE[key]
        self.send_response(200)
        self.send_header("Content-Type", TYPES.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if enc:
            self.send_header("Content-Encoding", enc)
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


# Precompress up front (brotli at quality 11 on the 43 MB engine takes a while) so timing runs measure transfer only.
for name in os.listdir(ROOT):
    for enc in (["br"] if brotli else []) + ["gzip"]:
        f = os.path.join(ROOT, name)
        if os.path.isfile(f) and not name.endswith(".png"):
            data = open(f, "rb").read()
            CACHE[(f, enc)] = (brotli.compress(data, quality=11) if enc == "br" else gzip.compress(data, 9), enc)
print("ready", flush=True)
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
