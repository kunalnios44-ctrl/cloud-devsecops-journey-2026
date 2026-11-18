"""Small HTTP demo service used by the NORDIC NEXUS container example."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import socket


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path not in {"/", "/health"}:
            self.send_error(404, "Not found")
            return

        payload = {
            "status": "ok",
            "service": "nordic-nexus-demo",
            "environment": os.getenv("APP_ENV", "development"),
            "region": os.getenv("CLOUD_REGION", "not-configured"),
            "instance": socket.gethostname(),
        }
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string: str, *args: object) -> None:
        print(f"[http] {self.address_string()} - {format_string % args}")


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", int(os.getenv("PORT", "8080"))), HealthHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
