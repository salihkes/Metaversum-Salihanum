#!/usr/bin/env python
"""
PCK HTTP File Server for Metaversum-Salihanum.

Serves .pck resource packs over HTTP so Godot clients can download them
dynamically based on the server-defined manifest (pck_manifest.json).

The manifest lists packages with versions. Clients compare their local
versions and only download packages whose versions have changed, ensuring
minimal bandwidth usage (delta-at-the-package-level).

Usage:
    1. Place .pck files in the pck_packages/ directory.
    2. Edit pck_manifest.json to list each package with a version string.
    3. When you update a .pck, bump its version in the manifest.
    4. Clients will automatically detect the mismatch and re-download
       only the affected package(s).

Endpoints:
    GET /pck/manifest.json   -> returns the manifest JSON
    GET /pck/<filename>.pck  -> streams the requested .pck file
"""

import asyncio
import os
import json

from constants import PCK_PACKAGES_DIR, PCK_MANIFEST_FILE, PCK_HTTP_SERVER_PORT, EXTERNAL_DOMAIN


def get_pck_manifest():
    """Read the PCK manifest from disk."""
    if not os.path.exists(PCK_MANIFEST_FILE):
        return {"packages": {}}
    try:
        with open(PCK_MANIFEST_FILE, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"[PCK Server] Error reading manifest: {e}")
        return {"packages": {}}


def get_manifest_for_client(use_ssl=True):
    """Get the manifest formatted for client consumption, including download URL.
    
    PCK files are served through the Flask Frontend on port 443 (Cloudflare),
    so the download URL is simply https://domain/pck/ with no extra port.
    """
    manifest = get_pck_manifest()
    manifest["download_base_url"] = f"https://{EXTERNAL_DOMAIN}/pck/"
    return manifest


async def handle_http_request(reader, writer):
    """Handle an incoming HTTP request for PCK file downloads."""
    try:
        # Read the request line
        request_line = await asyncio.wait_for(reader.readline(), timeout=10)
        if not request_line:
            writer.close()
            return

        request_str = request_line.decode('utf-8', errors='replace').strip()
        parts = request_str.split(' ')
        if len(parts) < 3:
            writer.close()
            return

        method, path = parts[0], parts[1]

        # Consume all headers
        while True:
            header_line = await asyncio.wait_for(reader.readline(), timeout=10)
            if header_line in (b'\r\n', b'\n', b''):
                break

        # CORS headers (needed for web exports)
        cors = (
            "Access-Control-Allow-Origin: *\r\n"
            "Access-Control-Allow-Methods: GET, OPTIONS\r\n"
            "Access-Control-Allow-Headers: *\r\n"
        )

        # Handle CORS preflight
        if method == 'OPTIONS':
            writer.write(f'HTTP/1.1 204 No Content\r\n{cors}\r\n'.encode())
            await writer.drain()
            writer.close()
            return

        if method != 'GET':
            writer.write(f'HTTP/1.1 405 Method Not Allowed\r\n{cors}Content-Length: 0\r\n\r\n'.encode())
            await writer.drain()
            writer.close()
            return

        # Route: /pck/*
        if path.startswith('/pck/'):
            filename = path[5:]  # Strip "/pck/"

            # Serve the manifest
            if filename == 'manifest.json':
                manifest = get_pck_manifest()
                body = json.dumps(manifest, indent=2).encode()
                headers = (
                    f'HTTP/1.1 200 OK\r\n'
                    f'{cors}'
                    f'Content-Type: application/json\r\n'
                    f'Content-Length: {len(body)}\r\n'
                    f'Cache-Control: no-cache\r\n'
                    f'\r\n'
                )
                writer.write(headers.encode() + body)
                await writer.drain()
                writer.close()
                return

            # Security: prevent path traversal, only allow .pck files
            filename = os.path.basename(filename)
            if not filename.endswith('.pck'):
                writer.write(f'HTTP/1.1 403 Forbidden\r\n{cors}Content-Length: 0\r\n\r\n'.encode())
                await writer.drain()
                writer.close()
                return

            filepath = os.path.join(PCK_PACKAGES_DIR, filename)

            if os.path.exists(filepath) and os.path.isfile(filepath):
                file_size = os.path.getsize(filepath)
                print(f"[PCK Server] Serving: {filename} ({file_size:,} bytes)")

                headers = (
                    f'HTTP/1.1 200 OK\r\n'
                    f'{cors}'
                    f'Content-Type: application/octet-stream\r\n'
                    f'Content-Length: {file_size}\r\n'
                    f'Content-Disposition: attachment; filename="{filename}"\r\n'
                    f'\r\n'
                )
                writer.write(headers.encode())
                await writer.drain()

                # Stream the file in 64KB chunks
                with open(filepath, 'rb') as f:
                    while True:
                        chunk = f.read(65536)
                        if not chunk:
                            break
                        writer.write(chunk)
                        await writer.drain()

                print(f"[PCK Server] Completed: {filename}")
            else:
                print(f"[PCK Server] File not found: {filename}")
                writer.write(f'HTTP/1.1 404 Not Found\r\n{cors}Content-Length: 0\r\n\r\n'.encode())
        else:
            writer.write(f'HTTP/1.1 404 Not Found\r\n{cors}Content-Length: 0\r\n\r\n'.encode())

        await writer.drain()

    except asyncio.TimeoutError:
        print("[PCK Server] Request timeout")
    except ConnectionResetError:
        pass  # Client disconnected
    except Exception as e:
        print(f"[PCK Server] Error handling request: {e}")
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except:
            pass


async def start_pck_server(ssl_context=None):
    """Start the PCK HTTP file server. Runs forever alongside the game server."""
    # Ensure the packages directory exists
    os.makedirs(PCK_PACKAGES_DIR, exist_ok=True)

    protocol = "https" if ssl_context else "http"

    server = await asyncio.start_server(
        handle_http_request,
        "0.0.0.0",
        PCK_HTTP_SERVER_PORT,
        ssl=ssl_context
    )

    print(f"[PCK Server] Listening on {protocol}://0.0.0.0:{PCK_HTTP_SERVER_PORT}")
    print(f"[PCK Server] Public URL: https://{EXTERNAL_DOMAIN}:{PCK_HTTP_SERVER_PORT}/pck/")

    # Print status of configured packages
    manifest = get_pck_manifest()
    packages = manifest.get("packages", {})
    if packages:
        print(f"[PCK Server] Serving {len(packages)} package(s):")
        for name, info in packages.items():
            filename = info.get("filename", name + ".pck")
            version = info.get("version", "unknown")
            filepath = os.path.join(PCK_PACKAGES_DIR, filename)
            status = "OK" if os.path.exists(filepath) else "MISSING"
            size = ""
            if os.path.exists(filepath):
                size_bytes = os.path.getsize(filepath)
                if size_bytes > 1024 * 1024:
                    size = f" ({size_bytes / (1024*1024):.1f} MB)"
                else:
                    size = f" ({size_bytes / 1024:.1f} KB)"
            print(f"  - {name} v{version} ({filename}) [{status}]{size}")
    else:
        print(f"[PCK Server] No packages configured in {PCK_MANIFEST_FILE}")
        print(f"[PCK Server] To add packages:")
        print(f"  1. Place .pck files in {PCK_PACKAGES_DIR}/")
        print(f"  2. Edit {PCK_MANIFEST_FILE} to register them with versions")

    async with server:
        await server.serve_forever()
