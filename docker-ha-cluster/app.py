from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import os
import socket

class ProductionHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response_data = {
            "status": "PRODUCTION_LIVE",
            "region": "Denmark-Nordic",
            "handled_by_container": socket.gethostname(),
            "user": os.getenv("USER", "appuser")
        }
        self.wfile.write(json.dumps(response_data).encode())

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), ProductionHandler)
    server.serve_forever()
  
