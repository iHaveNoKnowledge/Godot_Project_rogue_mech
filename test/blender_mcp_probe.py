"""Send arbitrary Blender Python code to blender-mcp addon (localhost:9876).

Usage: python test/blender_mcp_probe.py "import bpy; print(len(bpy.data.objects))"
"""
import json
import socket
import sys


def send_code(code: str, host: str = "127.0.0.1", port: int = 9876) -> str:
    with socket.create_connection((host, port), timeout=8) as s:
        cmd = {"type": "execute_code", "params": {"code": code}}
        s.sendall(json.dumps(cmd).encode("utf-8"))
        s.settimeout(20)
        chunks = []
        while True:
            try:
                data = s.recv(65536)
            except socket.timeout:
                break
            if not data:
                break
            chunks.append(data)
            try:
                json.loads(b"".join(chunks).decode("utf-8"))
                break  # got a complete JSON response
            except Exception:
                continue
        return b"".join(chunks).decode("utf-8", "replace")


if __name__ == "__main__":
    code = sys.argv[1] if len(sys.argv) > 1 else "import bpy; print(len(bpy.data.objects))"
    print(send_code(code))
