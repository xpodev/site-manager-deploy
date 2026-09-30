"""Stand-in for the Site Manager deploy service, used by the test workflow.

Accepts the token "good-token", checks the upload is a readable tar archive,
and answers like the real service.
"""
import io
import json
import sys
import tarfile
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path != "/deploy":
            return self.reply(404, {"error": "not found"})
        if self.headers.get("Authorization") != "Bearer good-token":
            return self.reply(401, {"error": "deploy key rejected: key has been revoked or replaced"})
        try:
            with tarfile.open(fileobj=io.BytesIO(body)) as tar:
                files = [m for m in tar.getmembers() if m.isfile()]
        except tarfile.TarError as e:
            return self.reply(400, {"error": f"corrupt archive: {e}"})
        self.reply(200, {"namespace": "test", "site": "site", "files": len(files), "bytes": sum(m.size for m in files)})

    def reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8080), Handler).serve_forever()
