#!/usr/bin/env python3
"""En falsk Xtream Codes-leverandør for testene (bare oppdiktede kanaler).

    python3 tools/fake_xtream.py --port 8899
    python3 tools/fake_xtream.py --port 8898 --kanaler 25000 --kategorier 450

Innlogging test/test. player_api.php svarer med abonnement, kategorier, kanaler og programinfo (base64, rundt nå);
/live/test/test/<id>.m3u8 sendes videre til Apples eksempelstrøm, unntatt kanal 90, som svarer 404.

M3U: /liste.m3u er en M3U-liste (oppdiktede kanaler i egne grupper, en uten gruppe, en film som hoppes over) med
TV-guiden /guide.xml.gz (XMLTV, gzip, programmene heter «… fra guiden»); /strom/<id>.m3u8 sendes videre til
eksempelstrømmen. /get.php?username=test&password=test er Xtream-lista som M3U (en Xtream-lenke).

Med --kanaler lages en stor liste som hos en ekte leverandør: mange kategorier etter land og slag, eventkanaler
(«18:30 Lag - Lag | Liga») uten programinfo, noen vanlige kanaler uten programinfo, og logoer med hver sin adresse.
"""
import argparse
import base64
import gzip
import json
import os
import re
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
    # samme kanal som 1 i en annen utgave: slås sammen med den når en egen strøm gjelder for Fjordkanalen
    (91, "Fjordkanalen HD", "9"),
]

LOGOS = {1: (0xF2, 0xB5, 0x44), 11: (0x4F, 0xA3, 0xFF), 41: (0x5C, 0xC9, 0x8B)}

# filmer og serier (oppdiktede): 501 og 503 spilles som HLS (Apples avspiller), 502 er mkv (VLC: en oppdiktet film på
# 30 sekunder med to lydspor og norske undertekster, tools/testdata/stormnatt.mkv); alt annet svarer 404. 505 har
# merker i navnet («[PRE] [2026]») og 4K, HDR og 5.1 i get_vod_info (merkene på plakaten og siden).
VOD_CATEGORIES = [("31", "Norske filmer"), ("32", "Dokumentarer")]
MOVIES = [
    (501, "Fyret i nord (2021)", "31", "m3u8", "7.4"),
    (502, "Stormnatt (2019)", "31", "mkv", "6.1"),
    (503, "Kysten fra lufta", "32", "m3u8", "8.0"),
    (505, "Fjordlys [PRE] [2026]", "32", "mkv", "6.8"),
]
SERIES_CATEGORIES = [("41", "Norske serier")]
SERIES = [(9001, "Losene", "41", "2020-09-01", "7.9")]
EPISODES = {9001: {1: ["Utløpet", "Tåka", "Fyrvokteren"], 2: ["Vinterstorm", "Hjem"]}}

# M3U-lista: (tvg-id, tvg-name, navn, gruppe, sti, logo). Nordlys Sport 1 har ingen tvg-id (finnes i guiden etter
# navnet), Villmark ingen gruppe («Uten kategori»), og Kystnytt 24 er en .ts-strøm fra en Xtream-server (appen prøver
# den som HLS først).
M3U_LIST = [
    ("fjord.no", "Fjordkanalen", "Fjordkanalen", "Kyst og fjord", "/strom/1.m3u8", 1),
    ("kyst.no", "", "Kystnytt 24", "Kyst og fjord", "/live/test/test/2.ts", None),
    ("", "", "Nordlys Sport 1", "Sport", "/strom/11.m3u8", 11),
    ("villmark.no", "", "Villmark", "", "/strom/41.m3u8", 41),
    ("", "", "Kanal uten guide", "Sport", "/strom/13.m3u8", None),
]
GUIDE_CHANNELS = [("fjord.no", "Fjordkanalen"), ("kyst.no", "Kystnytt 24"), ("sport1.no", "Nordlys Sport 1"),
                  ("villmark.no", "Villmark")]
GUIDE_TITLES = ["Morgensending fra guiden", "Kveldsnytt fra guiden", "Dokumentar fra guiden", "Sporten fra guiden",
                "Været fra guiden"]


def m3u_list(host):
    lines = [f'#EXTM3U url-tvg="http://{host}/guide.xml.gz"']
    for tvg_id, tvg_name, name, group, path, logo in M3U_LIST:
        attrs = f'tvg-id="{tvg_id}"'
        if tvg_name:
            attrs += f' tvg-name="{tvg_name}"'
        if logo:
            attrs += f' tvg-logo="http://{host}/logo/{logo}.png"'
        if group:
            attrs += f' group-title="{group}"'
        lines += [f"#EXTINF:-1 {attrs},{name}", f"http://{host}{path}"]
    lines += ['#EXTINF:-1 group-title="Filmer",Fyret i nord (2021)', f"http://{host}/movie/test/test/501.mkv"]
    return ("\n".join(lines) + "\n").encode()


def xtream_m3u(host):
    """Xtream-lista som M3U (get.php): det samme som player_api.php gir."""
    names = dict(CATEGORIES)
    lines = ["#EXTM3U"]
    for cid, name, cat in CHANNELS:
        lines += [f'#EXTINF:-1 tvg-id="kanal{cid}" tvg-name="{name}" group-title="{names[cat]}",{name}',
                  f"http://{host}/live/{USER}/{PASSWORD}/{cid}.ts"]
    return ("\n".join(lines) + "\n").encode()


def xmltv(now):
    """TV-guiden: programmer fra to timer før nå til tolv timer etter, med tittel og beskrivelse."""
    stamp = lambda t: time.strftime("%Y%m%d%H%M%S +0000", time.gmtime(t))
    out = ['<?xml version="1.0" encoding="UTF-8"?>', '<tv generator-info-name="fyrlys-test">']
    for cid, name in GUIDE_CHANNELS:
        out.append(f'  <channel id="{cid}"><display-name lang="no">{name}</display-name></channel>')
    for n, (cid, name) in enumerate(GUIDE_CHANNELS):
        t = int(now // 1800 * 1800) - 7200
        i = n
        while t < now + 12 * 3600:
            length = LENGTHS[i % len(LENGTHS)] * 60
            title = GUIDE_TITLES[i % len(GUIDE_TITLES)]
            out.append(f'  <programme start="{stamp(t)}" stop="{stamp(t + length)}" channel="{cid}">'
                       f'<title lang="no">{title}</title><desc lang="no">{title} på {name} &amp; et oppdiktet '
                       f'program til testene.</desc></programme>')
            t += length
            i += 1
    out.append("</tv>")
    return "\n".join(out).encode()


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
# kanal-id → logoen den har (i den store lista: én av de tre, men hver kanal med sin egen adresse)
LOGO_OF = {cid: cid for cid in LOGOS}
# kanalene uten epg_channel_id (eventkanaler og noen vanlige i den store lista)
NO_EPG = set()

COUNTRIES = ["Norge", "Sverige", "Danmark", "Finland", "Island", "Storbritannia", "Tyskland", "Frankrike", "Spania",
             "Italia", "Polen", "Nederland", "Portugal", "Hellas", "Canada"]
KINDS = ["", " Sport", " Film", " Barn", " Nyheter", " Dokumentar", " Musikk", " Events", " 4K", " Serier"]
TEAMS = ["Bergby", "Fjordheim", "Nordvik", "Sørhavn", "Austbø", "Vestli", "Lysaker", "Midtbyen", "Elvedal", "Skogås"]


def make_big(channels, categories):
    """En stor, oppdiktet liste: kategoriene etter land og slag, kanalene i blokker per kategori."""
    global CATEGORIES, CHANNELS
    cats = []
    for i in range(categories):
        country = COUNTRIES[i % len(COUNTRIES)]
        kind = KINDS[(i // len(COUNTRIES)) % len(KINDS)]
        round_ = i // (len(COUNTRIES) * len(KINDS))
        cats.append((str(100 + i), f"{country}{kind}" + (f" {round_ + 1}" if round_ else "")))
    chans = []
    for i in range(channels):
        cid = 1000 + i
        cat_id, cat_name = cats[i * categories // channels]
        if ("Events" in cat_name or "Sport" in cat_name) and i % 3 == 0:
            hour, minute = 12 + i % 10, (i * 5) % 60
            name = (f"{hour:02d}:{minute:02d} {TEAMS[i % 10]} - {TEAMS[(i * 7 + 3) % 10]} | "
                    f"Eksempelligaen {i % 12 + 1}")
            NO_EPG.add(cid)
        else:
            name = f"{cat_name.split()[0][:3].upper()} Kanal {i} HD"
            if i % 5 == 0:
                NO_EPG.add(cid)
        if i % 4:
            LOGO_OF[cid] = list(LOGOS)[cid % len(LOGOS)]
        chans.append((cid, name, cat_id))
    CATEGORIES, CHANNELS = cats, chans


def b64(text):
    return base64.b64encode(text.encode()).decode()


def programs(cid, cat, now):
    """Programmer fra to timer før nå til tolv timer etter, likt for samme kanal."""
    t = int(now // 1800 * 1800) - 7200 - (cid % 3) * 600
    titles = TITLES.get(cat, ["Nyhetene", "Dokumentar", "Filmkveld", "Serie", "Sportsnytt", "Magasinet"])
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


def history(cid, cat, now):
    """TV-arkivet: programmer fra to døgn før nå til litt etter, med has_archive (hvert sjuende mangler)."""
    t = int(now // 1800 * 1800) - 2 * 86400
    titles = TITLES.get(cat, ["Nyhetene", "Dokumentar", "Filmkveld", "Serie", "Sportsnytt", "Magasinet"])
    out = []
    i = cid
    while t < now + 3600:
        length = LENGTHS[i % len(LENGTHS)] * 60
        title = titles[i % len(titles)]
        out.append({
            "id": str(i), "epg_id": str(cid), "title": b64(title),
            "description": b64(f"{title} på kanal {cid}. Et oppdiktet program i arkivet."),
            "start_timestamp": str(t), "stop_timestamp": str(t + length),
            "has_archive": 0 if i % 7 == 0 else 1,
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

    def file(self, data, kind):
        """En fil med Range (VLC spoler med det)."""
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
                    "stream_icon": f"http://{host}/logo/{cid}.png" if cid in LOGO_OF else "",
                    "epg_channel_id": None if cid in NO_EPG else f"kanal{cid}", "category_id": c,
                    "tv_archive": 1 if cid in (1, 11) else 0, "tv_archive_duration": 7 if cid in (1, 11) else 0,
                } for n, (cid, name, c) in enumerate(CHANNELS) if cat is None or cat == c])
            if action == "get_vod_categories":
                return self.json([{"category_id": c, "category_name": n, "parent_id": 0} for c, n in VOD_CATEGORIES])
            if action == "get_series_categories":
                return self.json([{"category_id": c, "category_name": n, "parent_id": 0}
                                  for c, n in SERIES_CATEGORIES])
            if action == "get_vod_streams":
                cat = q.get("category_id")
                return self.json([{
                    "num": i + 1, "name": name, "stream_type": "movie", "stream_id": mid, "stream_icon": "",
                    "rating": rating, "added": str(int(now) - i * 86400), "category_id": c,
                    "container_extension": ext,
                } for i, (mid, name, c, ext, rating) in enumerate(MOVIES) if cat is None or cat == c])
            if action == "get_vod_info":
                mid = int(q.get("vod_id", "0"))
                for m, name, c, ext, rating in MOVIES:
                    if m == mid:
                        info = {"plot": f"En oppdiktet film om {name.split(' (')[0].split(' [')[0].lower()}.",
                                "genre": "Drama", "duration": "01:32:00", "rating": rating,
                                "releasedate": "2021-03-04", "cast": "Kari Nordmann, Ola Nordmann",
                                "video": {"height": 1080, "codec_name": "h264"},
                                "audio": {"codec_name": "aac", "channels": 2}}
                        if m == 505:
                            info.update({"age": "12", "country": "Norge", "releasedate": "2026-01-01",
                                         "video": {"height": 2160, "codec_name": "hevc", "color_transfer": "smpte2084"},
                                         "audio": {"codec_name": "eac3", "channels": 6}})
                        return self.json({"info": info,
                                          "movie_data": {"stream_id": m, "name": name, "container_extension": ext}})
                return self.json({"info": [], "movie_data": {}})
            if action == "get_series":
                cat = q.get("category_id")
                return self.json([{"series_id": sid, "name": name, "cover": "", "category_id": c,
                                   "releaseDate": date, "rating": rating}
                                  for sid, name, c, date, rating in SERIES if cat is None or cat == c])
            if action == "get_series_info":
                sid = int(q.get("series_id", "0"))
                seasons = EPISODES.get(sid, {})
                return self.json({
                    "info": {"name": "Losene", "plot": "En oppdiktet serie om losene langs kysten.", "genre": "Drama",
                             "releaseDate": "2020-09-01", "rating": "7.9"},
                    "episodes": {str(season): [{
                        "id": str(sid * 100 + season * 10 + n + 1), "episode_num": n + 1, "title": title,
                        "container_extension": "m3u8", "season": season,
                        "info": {"plot": f"Episode {n + 1}: {title.lower()}.", "duration": "44 min"},
                    } for n, title in enumerate(titles)] for season, titles in seasons.items()},
                })
            if action == "get_simple_data_table":
                cid = int(q.get("stream_id", "0"))
                if cid not in (1, 11):
                    return self.json({"epg_listings": []})
                return self.json({"epg_listings": history(cid, CATEGORY_OF.get(cid), now)})
            if action == "get_short_epg":
                cid = int(q.get("stream_id", "0"))
                cat = CATEGORY_OF.get(cid)
                if cat is None or cat == "9" or cid in NO_EPG:
                    return self.json({"epg_listings": []})
                limit = int(q.get("limit", "4"))
                listing = [p for p in programs(cid, cat, now) if int(p["stop_timestamp"]) > now][:limit]
                return self.json({"epg_listings": listing})
            return self.json([])

        if url.path == "/liste.m3u":
            return self.send(200, m3u_list(host), "audio/x-mpegurl")
        if url.path == "/guide.xml.gz":
            return self.send(200, gzip.compress(xmltv(time.time())), "application/gzip")
        if url.path == "/guide.xml":
            return self.send(200, xmltv(time.time()), "application/xml")
        if url.path == "/get.php":
            if q.get("username") != USER or q.get("password") != PASSWORD:
                return self.send(401, b"", "text/plain")
            return self.send(200, xtream_m3u(host), "audio/x-mpegurl")
        if len(parts) == 2 and parts[0] == "strom":
            cid = parts[1].split(".")[0]
            if parts[1].endswith(".m3u8") and cid.isdigit() and int(cid) in CATEGORY_OF and cid != "90":
                return self.send(302, b"", "text/plain", {"Location": SAMPLE})
            return self.send(404, b"", "text/plain")

        if len(parts) == 2 and parts[0] == "logo":
            cid = int(parts[1].split(".")[0]) if parts[1].split(".")[0].isdigit() else 0
            if cid in LOGO_OF:
                return self.send(200, LOGO_PNG[LOGO_OF[cid]], "image/png")
            return self.send(404, b"", "text/plain")

        if len(parts) == 6 and parts[0] == "timeshift":
            if parts[1] != USER or parts[2] != PASSWORD:
                return self.send(401, b"", "text/plain")
            if parts[5].endswith(".m3u8"):
                return self.send(302, b"", "text/plain", {"Location": SAMPLE})
            return self.send(404, b"", "text/plain")

        if len(parts) == 4 and parts[0] in ("movie", "series"):
            if parts[1] != USER or parts[2] != PASSWORD:
                return self.send(401, b"", "text/plain")
            if parts[3].endswith(".m3u8") and parts[3].split(".")[0] != "502":
                return self.send(302, b"", "text/plain", {"Location": SAMPLE})
            if parts[0] == "movie" and parts[3] == "502.mkv":
                return self.file(MKV, "video/x-matroska")
            return self.send(404, b"", "text/plain")

        if len(parts) == 4 and parts[0] == "live":
            if parts[1] != USER or parts[2] != PASSWORD:
                return self.send(401, b"", "text/plain")
            cid = parts[3].split(".")[0]
            if cid == "90" or not cid.isdigit() or int(cid) not in CATEGORY_OF:
                return self.send(404, b"", "text/plain")
            return self.send(302, b"", "text/plain", {"Location": SAMPLE})

        self.send(404, b"", "text/plain")


CATEGORY_OF = {}

with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "testdata", "stormnatt.mkv"), "rb") as f:
    MKV = f.read()


def main():
    global CATEGORY_OF
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8899)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--kanaler", type=int, default=0, help="en stor, oppdiktet liste med så mange kanaler")
    parser.add_argument("--kategorier", type=int, default=450)
    args = parser.parse_args()
    if args.kanaler:
        make_big(args.kanaler, args.kategorier)
    CATEGORY_OF = {cid: c for cid, _, c in CHANNELS}
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Falsk Xtream-leverandør på http://{args.host}:{args.port} (test/test, {len(CHANNELS)} kanaler i "
          f"{len(CATEGORIES)} kategorier)", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
