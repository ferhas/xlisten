"""极小 HTTP/HTTPS 转发代理：域名用宿主机 getaddrinfo 解析（Windows 已开 DoH，
能正确解析被明文 DNS 污染的 x.com），供安卓模拟器走它访问 X。
  py tool/doh_proxy.py [port]
"""
import socket
import select
import sys
import threading
from urllib.parse import urlsplit

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8888


def resolve(host, port):
    return socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)[0][4]


def pipe(a, b):
    try:
        while True:
            r, _, _ = select.select([a, b], [], [], 120)
            if not r:
                break
            for s in r:
                data = s.recv(65536)
                if not data:
                    return
                (b if s is a else a).sendall(data)
    except Exception:
        pass
    finally:
        for s in (a, b):
            try:
                s.close()
            except Exception:
                pass


def handle(client):
    try:
        client.settimeout(30)
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = client.recv(4096)
            if not chunk:
                client.close()
                return
            buf += chunk
        head, _, rest = buf.partition(b"\r\n\r\n")
        lines = head.split(b"\r\n")
        method, target, _ = (lines[0].decode("latin1").split() + ["", "", ""])[:3]
        print(f"{method} {target}", flush=True)

        if method.upper() == "CONNECT":
            host, _, port = target.partition(":")
            ip, p = resolve(host, int(port or 443)), int(port or 443)
            remote = socket.create_connection((ip[0], ip[1]), timeout=15)
            client.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
            pipe(client, remote)
        else:
            # 明文 HTTP：target 是绝对 URL，改写成 origin-form 转发
            sp = urlsplit(target)
            host = sp.hostname
            port = sp.port or 80
            path = sp.path or "/"
            if sp.query:
                path += "?" + sp.query
            ip = resolve(host, port)
            remote = socket.create_connection((ip[0], ip[1]), timeout=15)
            new_first = f"{method} {path} HTTP/1.1".encode("latin1")
            remote.sendall(new_first + b"\r\n" + b"\r\n".join(lines[1:]) + b"\r\n\r\n" + rest)
            pipe(client, remote)
    except Exception:
        try:
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
        except Exception:
            pass
        try:
            client.close()
        except Exception:
            pass


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PORT))
    srv.listen(200)
    print(f"DoH-resolving proxy listening on 0.0.0.0:{PORT}", flush=True)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()


if __name__ == "__main__":
    main()
