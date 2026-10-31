#!/usr/bin/env python3
"""En falsk Xtream Codes-leverandør for testene (bare oppdiktede kanaler).

    python3 tools/fake_xtream.py --port 8899

Innlogging test/test. player_api.php svarer med abonnement, kategorier, kanaler og programinfo (base64, rundt nå);
/live/test/test/<id>.m3u8 sendes videre til Apples eksempelstrøm, unntatt kanal 90, som svarer 404.
"""
import argparse
import base64
import json
import struct
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

SAMPLE = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
USER, PASSWORD = "test", "test"

CATEGORIES = [
    ("1", "Nyheter"),
    ("2", "Sport"),
    ("3", "Film og serier"),
    ("4", "Barn"),
    ("5", "Natur og vitenskap"),
    ("6", "Tom kategori"),
    ("9", "Test"),
]

CHANNELS = [
    (1, "Fjordkanalen", "1"),
    (2, "Kystnytt 24", "1"),
    (3, "Nordlys Nyheter HD", "1"),
    (4, "Morgen-TV", "1"),
    (5, "Bylivet", "1"),
    (11, "Nordlys Sport 1", "2"),
    (12, "Nordlys Sport 2", "2"),
    (13, "Fjellsport HD", "2"),
    (14, "18:30 Bergby IL - Fjordheim FK | Eksempelligaen", "2"),
    (15, "20:00 Nordvik - Sørhavn | Eksempelcupen", "2"),
    (21, "Kinokanalen", "3"),
    (22, "Seriekanalen", "3"),
    (23, "Klassikerkanalen", "3"),
    (31, "Barnekanalen", "4"),
    (32, "Tegnefilmkanalen", "4"),
    (41, "Villmark", "5"),
    (42, "Havet", "5"),
    (43, "Rommet", "5"),
    (90, "Kanal uten signal", "9"),
]

LOGOS = {1: (0xF2, 0xB5, 0x44), 11: (0x4F, 0xA3, 0xFF), 41: (0x5C, 0xC9, 0x8B)}

TITLES = {
    "1": ["Nyhetene", "Været", "Dagsrevyen", "Debatt", "Kveldsnytt", "Nyhetsmorgen"],
    "2": ["Studio sport", "Høydepunkter", "Direkte: fotball", "Sportsnytt", "Magasinet"],
    "3": ["Film: Fyret", "Serie: Havnen", "Film: Nattlys", "Serie: Øya", "Kortfilmer"],
    "4": ["Tegnefilm", "Barnetimen", "Eventyr", "Sang og lek"],
    "5": ["Dokumentar: Kysten", "Fjellet", "Dyrelivet", "Stjernehimmelen", "Havdyp"],
    "9": ["Test"],
}
LENGTHS = [30, 60, 45, 90, 30, 60, 25, 50]


def png(rgb, size=(240, 140)):
    """En enkel logo: en sirkel i fargen og en strek under (uten bibliotek)."""
    w, h = size
    rows = []
    cx, cy, r = w // 2, h // 2 - 12, 34
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            inside = (x - cx) ** 2 + (y - cy) ** 2 <= r * r
            bar = h - 40 <= y < h - 26 and 50 <= x < w - 50
            row += bytes(rgb + (255,)) if inside or bar else b"\0\0\0\0"
        rows.append(bytes(row))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    head = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", head) + chunk(b"IDAT", zlib.compress(b"".join(rows)))
            + chunk(b"IEND", b""))


LOGO_PNG = {cid: png(rgb) for cid, rgb in LOGOS.items()}


def b64(text):
    return base64.b64encode(text.encode()).decode()


def programs(cid, cat, now):
    """Programmer fra to timer før nå til tolv timer etter, likt for samme kanal."""
    t = int(now // 1800 * 1800) - 7200 - (cid % 3) * 600
    titles = TITLES.get(cat, ["Program"])
    out = []
    i = cid
    while t < now + 12 * 3600:
        length = LENGTHS[i % len(LENGTHS)] * 60
        title = titles[i % len(titles)]
        out.append({
            "id": str(i), "epg_id": str(cid), "lang": "no",
            "title": b64(title),
            "description": b64(f"{title} på kanal {cid}. Et oppdiktet program til testene."),
            "start": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(t)),
            "end": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(t + length)),
            "start_timestamp": str(t), "stop_timestamp": str(t + length),
        })
        t += length
        i += 1
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "FakeXtream/1"

    def log_message(self, fmt, *args):
        print("[falsk]", fmt % args, flush=True)

    def send(self, code, body=b"", kind="application/json", headers=None):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def json(self, data):
        self.send(200, json.dumps(data).encode())

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        parts = [p for p in url.path.split("/") if p]
        host = self.headers.get("Host", "127.0.0.1")

        if url.path == "/player_api.php":
            if q.get("username") != USER or q.get("password") != PASSWORD:
                return self.json({"user_info": {"auth": 0}})
            action = q.get("action")
            now = time.time()
            if action is None:
                return self.json({
                    "user_info": {"username": USER, "auth": 1, "status": "Active",
                                  "exp_date": str(int(now) + 90 * 86400), "max_connections": "1",
                                  "active_cons": "0"},
                    "server_info": {"timestamp_now": int(now), "timezone": "Europe/Oslo"},
                })
            if action == "get_live_categories":
                return self.json([{"category_id": cid, "category_name": name, "parent_id": 0}
                                  for cid, name in CATEGORIES])
            if action == "get_live_streams":
                cat = q.get("category_id")
                return self.json([{
                    "num": n + 1, "name": name, "stream_type": "live", "stream_id": cid,
                    "stream_icon": f"http://{host}/logo/{cid}.png" if cid in LOGO_PNG else "",
                    "epg_channel_id": f"kanal{cid}", "category_id": c,
                    "tv_archive": 1 if cid in (1, 11) else 0, "tv_archive_duration": 7 if cid in (1, 11) else 0,
                } for n, (cid, name, c) in enumerate(CHANNELS) if cat is None or cat == c])
            if action == "get_short_epg":
                cid = int(q.get("stream_id", "0"))
                cat = next((c for i, _, c in CHANNELS if i == cid), None)
                if cat is None or cat == "9":
                    return self.json({"epg_listings": []})
                limit = int(q.get("limit", "4"))
                listing = [p for p in programs(cid, cat, now) if int(p["stop_timestamp"]) > now][:limit]
                return self.json({"epg_listings": listing})
            return self.json([])

        if len(parts) == 2 and parts[0] == "logo":
            cid = int(parts[1].split(".")[0]) if parts[1].split(".")[0].isdigit() else 0
            if cid in LOGO_PNG:
                return self.send(200, LOGO_PNG[cid], "image/png")
            return self.send(404, b"", "text/plain")

        if len(parts) == 4 and parts[0] == "live":
            if parts[1] != USER or parts[2] != PASSWORD:
                return self.send(401, b"", "text/plain")
            cid = parts[3].split(".")[0]
            if cid == "90" or not any(str(i) == cid for i, _, _ in CHANNELS):
                return self.send(404, b"", "text/plain")
            return self.send(302, b"", "text/plain", {"Location": SAMPLE})

        self.send(404, b"", "text/plain")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8899)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Falsk Xtream-leverandør på http://{args.host}:{args.port} (test/test)", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
