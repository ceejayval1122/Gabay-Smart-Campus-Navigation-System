#!/usr/bin/env python3
"""
Simple HTTP server for handling Supabase auth redirects
Run this script during development to handle email confirmation redirects
"""

import http.server
import socketserver
import webbrowser
import os
from urllib.parse import urlparse, parse_qs

PORT = 3001
DIRECTORY = "web"

class AuthHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)
    
    def do_GET(self):
        # Parse the URL to extract hash fragments
        parsed = urlparse(self.path)
        
        if parsed.path == '/' or parsed.path == '/#':
            # Serve the auth callback page with hash fragments
            self.path = '/auth-callback.html'
            # Add the hash fragment to the response
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            
            # Read the HTML file
            try:
                with open(os.path.join(DIRECTORY, 'auth-callback.html'), 'r') as f:
                    content = f.read()
                
                # If there's a hash fragment, modify the JavaScript to handle it
                if parsed.fragment:
                    # Replace the window.location.hash in the script
                    content = content.replace(
                        'const urlParams = new URLSearchParams(window.location.hash.substring(1));',
                        f'const urlParams = new URLSearchParams("{parsed.fragment}");'
                    )
                
                self.wfile.write(content.encode())
                return
            except FileNotFoundError:
                self.send_error(404, "File not found")
                return
        else:
            # Handle other requests normally
            super().do_GET()

def start_server():
    """Start the HTTP server"""
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    
    with socketserver.TCPServer(("", PORT), AuthHandler) as httpd:
        print(f"🚀 Auth server running at http://localhost:{PORT}")
        print(f"📁 Serving files from: {DIRECTORY}/")
        print("🔗 Supabase will redirect here after email confirmation")
        print("⏹️  Press Ctrl+C to stop the server")
        print()
        
        # Open browser automatically
        try:
            webbrowser.open(f'http://localhost:{PORT}')
            print("🌐 Opened browser automatically")
        except:
            print("⚠️  Could not open browser automatically")
        
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n⏹️  Server stopped")

if __name__ == "__main__":
    start_server()
