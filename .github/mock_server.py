"""Stand-in for the Site Manager deploy service, used by the test workflow.

Knows two keys: "site-token", a site key for test/site, and "ns-token", a
namespace key for test. Checks the upload is a readable tar archive and
answers like the real service.
"""
import io
import json
import sys
import tarfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

KEYS = {"Bearer site-token": "site", "Bearer ns-token": ""}


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        url = urlparse(self.path)
        if url.path != "/deploy":
            return self.reply(404, {"error": "not found"})
        key_site = KEYS.get(self.headers.get("Authorization"))
        if key_site is None:
            return self.reply(401, {"error": "deploy key rejected: key has been revoked or replaced"})
        requested = parse_qs(url.query).get("site", [""])[0]
        if key_site == "" and requested == "":
            return self.reply(400, {"error": "this key covers a whole namespace: name the site to deploy"})
        if key_site and requested not in ("", key_site):
            return self.reply(403, {"error": "this key does not cover the requested site"})
        try:
            with tarfile.open(fileobj=io.BytesIO(body)) as tar:
                files = [m for m in tar.getmembers() if m.isfile()]
        except tarfile.TarError as e:
            return self.reply(400, {"error": f"corrupt archive: {e}"})
        self.reply(200, {"namespace": "test", "site": key_site or requested, "files": len(files), "bytes": sum(m.size for m in files)})

    def reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8080), Handler).serve_forever()
