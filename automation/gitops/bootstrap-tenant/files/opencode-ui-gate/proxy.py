#!/usr/bin/env python3
"""Reverse proxy in front of OpenCode's embedded web UI.

OpenCode 1.19's browser UI keeps an *open projects* list in localStorage and
does not auto-adopt the server working directory (upstream #37096 / #44216;
fix still open as #55230). Agent sessions created by AAP live under /app, so
a fresh browser shows "No projects open" / empty sidebar even though
GET /session returns them.

This proxy injects a small bootstrap into text/html responses so /app is
registered as an open project, and sends bare "/" to the /app workspace URL.
API/SSE/WebSocket traffic is forwarded unchanged — AAP should keep talking to
the opencode Service directly, not through this gate.
"""
from __future__ import annotations

import asyncio
import base64
import os
import re
from urllib.parse import urlsplit

UPSTREAM = os.environ.get("OPENCODE_UPSTREAM", "http://127.0.0.1:4096")
LISTEN_HOST = os.environ.get("GATE_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("GATE_LISTEN_PORT", "8080"))
PROJECT_DIR = os.environ.get("OPENCODE_PROJECT_DIR", "/app")

_parts = urlsplit(UPSTREAM)
UP_HOST = _parts.hostname or "127.0.0.1"
UP_PORT = _parts.port or (443 if _parts.scheme == "https" else 80)
UP_SSL = _parts.scheme == "https"

DIR_B64 = (
    base64.b64encode(PROJECT_DIR.encode())
    .decode()
    .replace("+", "-")
    .replace("/", "_")
    .rstrip("=")
)

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "proxy-connection",
}


def build_boot_js() -> str:
    dir_js = PROJECT_DIR.replace("\\", "\\\\").replace("'", "\\'")
    return (
        '<script data-lightwell-opencode-gate="1">\n'
        "(function(){\n"
        "  try {\n"
        "    var KEY='opencode.global.dat:server';\n"
        f"    var DIR='{dir_js}';\n"
        "    var st=JSON.parse(localStorage.getItem(KEY)||"
        '\'{"list":[],"projects":{"local":[]},"lastProject":{},"recentlyClosed":{}}\');\n'
        "    st.projects=st.projects||{local:[]};\n"
        "    st.projects.local=Array.isArray(st.projects.local)?st.projects.local:[];\n"
        "    if(!st.projects.local.some(function(p){return p&&p.worktree===DIR;})){\n"
        "      st.projects.local.push({worktree:DIR,expanded:true});\n"
        "    } else {\n"
        "      st.projects.local=st.projects.local.map(function(p){\n"
        "        return (p&&p.worktree===DIR)?Object.assign({},p,{expanded:true}):p;\n"
        "      });\n"
        "    }\n"
        "    if(!st.lastProject||!st.lastProject.local) st.lastProject={local:DIR};\n"
        "    localStorage.setItem(KEY,JSON.stringify(st));\n"
        "    var layout=JSON.parse(localStorage.getItem('opencode.global.dat:layout')||'{}');\n"
        "    layout.sidebar=Object.assign({},layout.sidebar||{},{opened:true});\n"
        "    localStorage.setItem('opencode.global.dat:layout',JSON.stringify(layout));\n"
        "    if(location.pathname==='/'&&!sessionStorage.getItem('lw-oc-boot')){\n"
        "      sessionStorage.setItem('lw-oc-boot','1');\n"
        f"      location.replace('/{DIR_B64}');\n"
        "    }\n"
        "  } catch(e) {}\n"
        "})();\n"
        "</script>"
    )


BOOT_JS = build_boot_js()


async def _pipe(src: asyncio.StreamReader, dst: asyncio.StreamWriter) -> None:
    try:
        while True:
            chunk = await src.read(65536)
            if not chunk:
                break
            dst.write(chunk)
            await dst.drain()
    except (asyncio.CancelledError, ConnectionError, BrokenPipeError):
        pass
    finally:
        try:
            dst.close()
        except Exception:
            pass


async def _websocket_tunnel(
    client_reader: asyncio.StreamReader,
    client_writer: asyncio.StreamWriter,
    req_line: bytes,
    header_block: bytes,
) -> None:
    up_reader, up_writer = await asyncio.open_connection(UP_HOST, UP_PORT, ssl=UP_SSL or None)
    up_writer.write(req_line + header_block)
    await up_writer.drain()
    t1 = asyncio.create_task(_pipe(client_reader, up_writer))
    t2 = asyncio.create_task(_pipe(up_reader, client_writer))
    done, pending = await asyncio.wait({t1, t2}, return_when=asyncio.FIRST_COMPLETED)
    for t in pending:
        t.cancel()
    for t in done:
        try:
            t.result()
        except Exception:
            pass


async def _read_status_and_headers(
    reader: asyncio.StreamReader,
) -> tuple[str, dict[str, str]]:
    raw = await reader.readuntil(b"\r\n\r\n")
    head = raw[: -4]
    lines = head.split(b"\r\n")
    status = lines[0].decode("latin1")
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if b":" not in line:
            continue
        k, _, v = line.partition(b":")
        headers[k.decode("latin1").strip().lower()] = v.decode("latin1").strip()
    return status, headers


async def _handle(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter) -> None:
    try:
        req_line = await client_reader.readline()
        if not req_line:
            return
        header_block = await client_reader.readuntil(b"\r\n\r\n")
        headers_raw = header_block[:-4] if header_block.endswith(b"\r\n\r\n") else header_block
        headers: dict[str, str] = {}
        for line in headers_raw.split(b"\r\n"):
            if not line or b":" not in line:
                continue
            k, _, v = line.partition(b":")
            headers[k.decode("latin1").strip().lower()] = v.decode("latin1").strip()

        if headers.get("upgrade", "").lower() == "websocket":
            await _websocket_tunnel(client_reader, client_writer, req_line, header_block)
            return

        content_length = int(headers.get("content-length", "0") or "0")
        body = b""
        if content_length:
            body = await client_reader.readexactly(content_length)
        elif headers.get("transfer-encoding", "").lower() == "chunked":
            while True:
                line = await client_reader.readline()
                size = int(line.strip() or b"0", 16)
                if size == 0:
                    await client_reader.readline()
                    break
                body += await client_reader.readexactly(size)
                await client_reader.readline()

        fwd_headers = []
        for line in headers_raw.split(b"\r\n"):
            if not line or b":" not in line:
                continue
            k, _, v = line.partition(b":")
            lk = k.decode("latin1").strip().lower()
            if lk in HOP_BY_HOP or lk == "host":
                continue
            fwd_headers.append(b"%s: %s\r\n" % (k, v.lstrip()))
        fwd_headers.append(b"Host: %s:%d\r\n" % (UP_HOST.encode(), UP_PORT))
        fwd_headers.append(b"Connection: close\r\n")
        if body and "content-length" not in headers:
            fwd_headers.append(b"Content-Length: %d\r\n" % len(body))

        up_reader, up_writer = await asyncio.open_connection(UP_HOST, UP_PORT, ssl=UP_SSL or None)
        up_writer.write(req_line)
        for h in fwd_headers:
            up_writer.write(h)
        up_writer.write(b"\r\n")
        if body:
            up_writer.write(body)
        await up_writer.drain()

        status_line, resp_headers = await _read_status_and_headers(up_reader)
        ctype = resp_headers.get("content-type", "")
        is_html = "text/html" in ctype

        if is_html:
            chunks: list[bytes] = []
            cl = resp_headers.get("content-length")
            if cl:
                chunks.append(await up_reader.readexactly(int(cl)))
            else:
                while True:
                    chunk = await up_reader.read(65536)
                    if not chunk:
                        break
                    chunks.append(chunk)
            raw = b"".join(chunks)
            encoding = resp_headers.get("content-encoding", "").lower()
            if encoding in ("gzip", "br", "deflate"):
                out = raw
            else:
                text = raw.decode("utf-8", errors="surrogateescape")
                if "data-lightwell-opencode-gate" in text:
                    out = raw
                elif re.search(r"</head>", text, re.I):
                    text = re.sub(r"</head>", BOOT_JS + "</head>", text, count=1, flags=re.I)
                    out = text.encode("utf-8", errors="surrogateescape")
                elif re.search(r"</body>", text, re.I):
                    text = re.sub(r"</body>", BOOT_JS + "</body>", text, count=1, flags=re.I)
                    out = text.encode("utf-8", errors="surrogateescape")
                else:
                    out = raw + BOOT_JS.encode()

            client_writer.write((status_line + "\r\n").encode("latin1"))
            for k, v in resp_headers.items():
                lk = k.lower()
                if lk in HOP_BY_HOP or lk in ("content-length", "content-encoding"):
                    continue
                client_writer.write(f"{k}: {v}\r\n".encode("latin1"))
            client_writer.write(f"Content-Length: {len(out)}\r\n".encode("latin1"))
            client_writer.write(b"Connection: close\r\n\r\n")
            client_writer.write(out)
            await client_writer.drain()
            up_writer.close()
            return

        client_writer.write((status_line + "\r\n").encode("latin1"))
        for k, v in resp_headers.items():
            if k.lower() in HOP_BY_HOP:
                continue
            client_writer.write(f"{k}: {v}\r\n".encode("latin1"))
        client_writer.write(b"Connection: close\r\n\r\n")
        await client_writer.drain()
        while True:
            chunk = await up_reader.read(65536)
            if not chunk:
                break
            client_writer.write(chunk)
            await client_writer.drain()
        up_writer.close()
    except Exception:
        try:
            client_writer.write(
                b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            )
            await client_writer.drain()
        except Exception:
            pass
    finally:
        try:
            client_writer.close()
            await client_writer.wait_closed()
        except Exception:
            pass


async def main() -> None:
    server = await asyncio.start_server(_handle, LISTEN_HOST, LISTEN_PORT)
    sockets = ", ".join(str(s.getsockname()) for s in server.sockets or [])
    print(
        f"opencode-ui-gate listening on {sockets} -> {UPSTREAM} (project={PROJECT_DIR})",
        flush=True,
    )
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
