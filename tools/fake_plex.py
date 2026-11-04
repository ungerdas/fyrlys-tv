#!/usr/bin/env python3
"""En falsk Plex til testene: plex.tv (koden til plex.tv/link og serverne på kontoen) og en Plex-server med
oppdiktede filmer og serier, på samme port. Nøkkelen er «test-token».

- POST /api/v2/pins gir koden FYRL; GET /api/v2/pins/<id> gir nøkkelen fra og med tredje gang (som om den er skrevet
  inn på plex.tv/link imens).
- /api/v2/resources: serveren «Hjemmekino» med en tilkobling på hjemmenettet som ikke svarer (port 9) og en utenfra
  som er denne serveren (Fyrlys skal finne den som svarer), og en spiller som ikke er en server.
- Serveren: bibliotekene Filmer (movie), Serier (show) og Musikk (artist), filmene 1001–1003 (1003 svarer 404),
  serien 2001 med to sesonger, «Fortsett å se», radene på Hjem (/hubs/promoted: «Nytt fra Kystkanalen» med episoder,
  «Nylig lagt til» med filmer og en sesong, og hele raden under /hubs/home/recentlyAdded, «Se alle»), søket
  (/hubs/search), flere på en gang (/library/metadata/1001,2001: favorittene), plakatene (ensfargede PNG) og filene
  (tools/testdata/stormnatt.mkv, med Range), og /:/timeline og /:/scrobble (skrives i loggen).
- Episodene 2102 og 2103 har markører (introen og rulleteksten til slutt, på sekundene i testfilmen på 30 s) og en
  engelsk undertekstfil ved siden av (/library/streams/77.srt; fila har norske undertekster inni selv).
- «Mer som dette» (/hubs/metadata/<id>/related) for filmene: de andre filmene.
- /:/scrobble og /:/unscrobble merker filmen 1002 som sett og ikke sett (de andre står som de er, så testene som
  spiller dem, ikke endrer det de andre testene venter).

Bruk: python3 tools/fake_plex.py [--port 8897]
"""

import argparse
import json
import os
import re
import struct
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

TOKEN = "test-token"
PIN = {"id": 4242, "code": "FYRL", "polls": 0}

with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "testdata", "stormnatt.mkv"), "rb") as f:
    MKV = f.read()


def poster(rgb, size=(120, 180)):
    """En ensfarget plakat med en lysere stripe (uten bibliotek)."""
    w, h = size
    rows = []
    light = tuple(min(255, c + 70) for c in rgb)
    for y in range(h):
        color = light if h * 0.62 <= y < h * 0.7 else rgb
        rows.append(b"\0" + bytes(color) * w)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))


COLORS = [(0x2B, 0x4C, 0x7E), (0x8C, 0x3B, 0x2E), (0x2E, 0x6B, 0x4F), (0x6B, 0x4A, 0x8C), (0x8C, 0x7A, 0x2E)]


def media(rid, ext="mkv"):
    return [{"container": ext, "Part": [{"key": f"/library/parts/{rid}/1700000000/file.{ext}", "container": ext}]}]


MOVIES = [
    {"ratingKey": "1001", "type": "movie", "title": "Nordlys over fjorden", "year": 2022, "audienceRating": 8.1,
     "summary": "En oppdiktet film om en fyrvokter som ser nordlyset for første gang.", "duration": 30000,
     "viewOffset": 12000, "Genre": [{"tag": "Drama"}], "Role": [{"tag": "Kari Fyr"}, {"tag": "Ola Strand"}],
     "Director": [{"tag": "Ingrid Lykt"}], "Media": media(1001)},
    {"ratingKey": "1002", "type": "movie", "title": "Fjordbyen", "year": 2020, "audienceRating": 6.9,
     "summary": "Oppdiktet dokumentar om en by ved fjorden.", "duration": 30000, "viewCount": 1,
     "Genre": [{"tag": "Dokumentar"}], "Media": media(1002)},
    {"ratingKey": "1003", "type": "movie", "title": "Kystlinjen", "year": 2019, "rating": 7.2,
     "summary": "Fila finnes ikke på serveren.", "duration": 5400000, "Media": media(1003, "avi")},
]
SHOW = {"ratingKey": "2001", "type": "show", "title": "Fyrvokterne", "year": 2021, "audienceRating": 7.7,
        "summary": "Oppdiktet serie om to fyrvoktere langs kysten.", "leafCount": 4, "viewedLeafCount": 1,
        "childCount": 2, "Genre": [{"tag": "Drama"}]}
EPISODES = [
    {"ratingKey": "2101", "type": "episode", "title": "Første natt", "parentIndex": 1, "index": 1, "viewCount": 1},
    {"ratingKey": "2102", "type": "episode", "title": "Stormvarsel", "parentIndex": 1, "index": 2, "viewOffset": 9000},
    {"ratingKey": "2103", "type": "episode", "title": "Tåkeluren", "parentIndex": 1, "index": 3},
    {"ratingKey": "2201", "type": "episode", "title": "Vinteren", "parentIndex": 2, "index": 1},
]
for e in EPISODES:
    e.update({"summary": f"Oppdiktet episode: {e['title']}.", "duration": 30000, "grandparentRatingKey": "2001",
              "grandparentTitle": "Fyrvokterne", "grandparentThumb": "/library/metadata/2001/thumb/1",
              "grandparentArt": "/library/metadata/2001/art/1", "Media": media(e["ratingKey"])})
# markørene (millisekunder) og undertekstene: de norske inni fila, og en engelsk fil ved siden av
MARKERS = {
    "2102": [{"type": "credits", "startTimeOffset": 20000, "endTimeOffset": 30000, "final": True}],
    "2103": [{"type": "intro", "startTimeOffset": 2000, "endTimeOffset": 9000},
             {"type": "credits", "startTimeOffset": 22000, "endTimeOffset": 30000, "final": True}],
}
SUBTITLE = b"1\n00:00:01,000 --> 00:00:29,000\nOppdiktet engelsk undertekst\n"
for e in EPISODES:
    if e["ratingKey"] in MARKERS:
        e["Marker"] = MARKERS[e["ratingKey"]]
        e["Media"][0]["Part"][0]["Stream"] = [
            {"id": 1, "streamType": 1, "codec": "h264"},
            {"id": 2, "streamType": 3, "codec": "srt", "index": 3, "languageCode": "nor", "displayTitle": "Norsk"},
            {"id": 77, "streamType": 3, "codec": "srt", "key": "/library/streams/77", "languageCode": "eng",
             "displayTitle": "English (SRT External)"},
        ]
for i, m in enumerate(MOVIES + [SHOW]):
    m["thumb"] = f"/library/metadata/{m['ratingKey']}/thumb/1"
    m["art"] = f"/library/metadata/{m['ratingKey']}/art/1"
    m["addedAt"] = 1700000000 - i * 1000
    m["librarySectionID"] = 2 if m["type"] == "show" else 1
METADATA = {m["ratingKey"]: m for m in MOVIES + [SHOW] + EPISODES}


class Handler(BaseHTTPRequestHandler):
    server_version = "FakePlex/1"

    def log_message(self, fmt, *args):
        print("[plex]", fmt % args, flush=True)

    def send(self, code, body=b"", kind="application/json", headers=None):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def json(self, data, code=200):
        self.send(code, json.dumps(data).encode())

    def container(self, **fields):
        self.json({"MediaContainer": {"size": len(fields.get("Metadata", fields.get("Directory", []))), **fields}})

    def file(self, data, kind):
        m = re.fullmatch(r"bytes=(\d*)-(\d*)", self.headers.get("Range", "").strip())
        if not m or not (m.group(1) or m.group(2)):
            return self.send(200, data, kind, {"Accept-Ranges": "bytes"})
        if m.group(1):
            start = int(m.group(1))
            end = min(int(m.group(2)) if m.group(2) else len(data) - 1, len(data) - 1)
        else:
            start, end = max(0, len(data) - int(m.group(2))), len(data) - 1
        if start >= len(data) or start > end:
            return self.send(416, b"", kind, {"Content-Range": f"bytes */{len(data)}"})
        return self.send(206, data[start:end + 1], kind,
                         {"Accept-Ranges": "bytes", "Content-Range": f"bytes {start}-{end}/{len(data)}"})

    def do_HEAD(self):
        self.do_GET()

    def do_POST(self):
        if urlparse(self.path).path == "/api/v2/pins":
            PIN["polls"] = 0
            return self.json({"id": PIN["id"], "code": PIN["code"], "authToken": None}, 201)
        self.send(404)

    def token(self, q):
        return self.headers.get("X-Plex-Token") or q.get("X-Plex-Token", "")

    def do_GET(self):
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        path = url.path

        # ── plex.tv ──
        if path == f"/api/v2/pins/{PIN['id']}":
            PIN["polls"] += 1
            return self.json({"id": PIN["id"], "code": PIN["code"],
                              "authToken": TOKEN if PIN["polls"] >= 3 else None})
        if path == "/api/v2/resources":
            if self.token(q) != TOKEN:
                return self.send(401)
            port = self.server.server_address[1]
            return self.json([
                {"name": "Stuespiller", "provides": "player", "clientIdentifier": "spiller", "accessToken": TOKEN,
                 "connections": []},
                {"name": "Hjemmekino", "provides": "server", "clientIdentifier": "falsk-server", "owned": True,
                 "accessToken": TOKEN, "connections": [
                     {"protocol": "http", "uri": "http://127.0.0.1:9", "local": True, "relay": False},
                     {"protocol": "http", "uri": f"http://127.0.0.1:{port}", "local": False, "relay": False}]},
            ])

        # ── serveren ──
        if self.token(q) != TOKEN:
            return self.send(401)
        if path == "/identity":
            return self.container(machineIdentifier="falsk-server")
        if path == "/library/sections":
            return self.container(Directory=[{"key": "1", "type": "movie", "title": "Filmer"},
                                             {"key": "2", "type": "show", "title": "Serier"},
                                             {"key": "3", "type": "artist", "title": "Musikk"}])
        if path == "/library/sections/1/all":
            return self.container(Metadata=MOVIES)
        if path == "/library/sections/2/all":
            return self.container(Metadata=[SHOW])
        if path == "/library/sections/3/all":
            return self.container(Metadata=[])
        if path == "/hubs/promoted" or path.startswith("/hubs/sections/"):
            # Hjem: en samling med nye episoder, nylig lagt til (filmer og en sesong), og rader som skal hoppes over
            season = {"ratingKey": "2100", "type": "season", "title": "Sesong 1", "parentRatingKey": "2001",
                      "parentTitle": "Fyrvokterne", "parentThumb": "/library/metadata/2001/thumb/1",
                      "librarySectionID": 2}
            return self.container(Hub=[
                {"title": "Fortsett å se", "hubIdentifier": "home.continueWatching", "type": "mixed",
                 "Metadata": [METADATA["1001"]]},
                {"title": "Nytt fra Kystkanalen", "hubIdentifier": "custom.collection.2.77", "type": "episode",
                 "Metadata": [METADATA["2102"], METADATA["2103"]]},
                {"title": "Nylig lagt til", "hubIdentifier": "home.recentlyAdded", "type": "mixed",
                 "key": "/hubs/home/recentlyAdded?type=1", "more": True,
                 "Metadata": [METADATA["1001"], METADATA["1002"], season]},
                {"title": "Spillelister", "hubIdentifier": "home.playlists", "type": "playlist",
                 "Directory": [{"title": "Favoritter", "key": "/playlists/1"}]},
            ])
        if path == "/hubs/continueWatching/items":
            return self.container(Metadata=[METADATA["2102"], METADATA["1001"]])
        if path == "/hubs/home/recentlyAdded":
            # hele raden («Se alle»): også filmen som ikke står i raden på Hjem
            return self.container(Metadata=MOVIES + [SHOW])
        m = re.fullmatch(r"/hubs/metadata/(\d+)/related", path)
        if m:
            if m.group(1) not in METADATA or METADATA[m.group(1)]["type"] != "movie":
                return self.container(Hub=[])
            return self.container(Hub=[{"title": "Mer som dette", "hubIdentifier": "movie.similar", "type": "movie",
                                        "Metadata": [x for x in MOVIES if x["ratingKey"] != m.group(1)]}])
        if path == "/library/streams/77.srt":
            return self.send(200, SUBTITLE, "text/plain; charset=utf-8")
        if path == "/hubs/search":
            words = q.get("query", "").lower().split()
            hits = [m for m in MOVIES + [SHOW] + EPISODES if words and all(w in m["title"].lower() for w in words)]
            return self.container(Hub=[{"type": kind, "hubIdentifier": kind,
                                        "Metadata": [m for m in hits if m["type"] == kind]}
                                       for kind in ("movie", "show", "episode")])
        m = re.fullmatch(r"/library/metadata/([\d,]+)(/allLeaves)?", path)
        if m and all(k in METADATA for k in m.group(1).split(",")):
            if m.group(2):
                return self.container(Metadata=[e for e in EPISODES if e["grandparentRatingKey"] == m.group(1)])
            return self.container(Metadata=[METADATA[k] for k in m.group(1).split(",")])
        if path == "/photo/:/transcode":
            n = int(re.sub(r"\D", "", q.get("url", "0"))[:4] or 0)
            return self.send(200, poster(COLORS[n % len(COLORS)]), "image/png")
        m = re.fullmatch(r"/library/parts/(\d+)/\d+/file\.(\w+)", path)
        if m:
            if m.group(2) == "mkv":
                return self.file(MKV, "video/x-matroska")
            return self.send(404)
        if path in ("/:/timeline", "/:/scrobble", "/:/unscrobble"):
            print("[plex] rapport:", path, json.dumps(q, ensure_ascii=False), flush=True)
            item = METADATA.get(q.get("key", ""))
            # bare filmen 1002 (testene av «Merk som sett»), så det de andre testene venter, står
            if path != "/:/timeline" and item and item["ratingKey"] == "1002":
                if path == "/:/scrobble":
                    item["viewCount"] = 1
                    item.pop("viewOffset", None)
                else:
                    item.pop("viewCount", None)
            return self.send(200, b"", "text/plain")
        self.send(404)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8897)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Falsk Plex på http://{args.host}:{args.port} (nøkkelen {TOKEN})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
