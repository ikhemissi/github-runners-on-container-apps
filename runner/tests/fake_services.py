"""A fake of the services the entrypoint calls, for offline tests: the Container Apps managed identity endpoint, Key
Vault and the GitHub REST API. It records every request (JSON lines) and answers like the real services.

    python3 fake_services.py <private key file> <request log> <port file> [--fail-github]

With --fail-github, every GitHub call answers 500 (to test the retries)."""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

KEY_FILE, REQUEST_LOG, PORT_FILE = sys.argv[1:4]
FAIL_GITHUB = "--fail-github" in sys.argv

IDENTITY_HEADER = "test-identity-header"
VAULT_TOKEN = "test-vault-token"
INSTALLATION_TOKEN = "test-installation-token"
JIT_CONFIG = "test-jit-config"


class FakeServices(BaseHTTPRequestHandler):
    def do_GET(self):
        self.answer()

    def do_POST(self):
        self.answer()

    def do_DELETE(self):
        self.answer()

    def answer(self):
        url = urlparse(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        self.record(url, body)
        status, response = self.route(url.path, parse_qs(url.query))
        payload = b"" if status == 204 else json.dumps(response).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def route(self, path, query):
        authorization = self.headers.get("Authorization", "")
        if path == "/msi/token":
            if self.headers.get("X-IDENTITY-HEADER") != IDENTITY_HEADER:
                return 401, {"error": "missing identity header"}
            return 200, {"access_token": VAULT_TOKEN, "resource": query["resource"][0]}
        if path == "/secrets/registrar":
            if authorization != f"Bearer {VAULT_TOKEN}":
                return 401, {"error": "bad vault token"}
            with open(KEY_FILE) as key:
                return 200, {"value": key.read()}
        if FAIL_GITHUB:
            return 500, {"message": "fake failure"}
        if path.startswith("/app/installations/") and path.endswith("/access_tokens"):
            return 201, {"token": INSTALLATION_TOKEN}
        if path.endswith("/actions/runners/generate-jitconfig"):
            if authorization != f"Bearer {INSTALLATION_TOKEN}":
                return 401, {"message": "bad installation token"}
            return 201, {"runner": {"id": 7}, "encoded_jit_config": JIT_CONFIG}
        if self.command == "DELETE" and path.endswith("/actions/runners/7"):
            if authorization != f"Bearer {INSTALLATION_TOKEN}":
                return 401, {"message": "bad installation token"}
            return 204, {}
        return 404, {"message": "not found"}

    def record(self, url, body):
        entry = {
            "method": self.command,
            "path": url.path,
            "query": parse_qs(url.query),
            "authorization": self.headers.get("Authorization", ""),
            "identity_header": self.headers.get("X-IDENTITY-HEADER", ""),
            "api_version": self.headers.get("X-GitHub-Api-Version", ""),
            "body": json.loads(body) if body else None,
        }
        with open(REQUEST_LOG, "a") as log:
            log.write(json.dumps(entry) + "\n")

    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), FakeServices)
with open(PORT_FILE, "w") as port_file:
    port_file.write(str(server.server_address[1]))
server.serve_forever()
