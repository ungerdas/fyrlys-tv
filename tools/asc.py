#!/usr/bin/env python3
"""App Store Connect fra GitHub Actions (uten Mac og uten Xcode-konto), med API-nøkkelen i miljøet:
ASC_KEY_PATH (.p8-fila), ASC_KEY_ID, ASC_ISSUER_ID og APPLE_TEAM_ID. Valgfritt DIST_KEY_PATH: en privat RSA-nøkkel
(hemmeligheten DIST_KEY) for et distribusjonssertifikat som beholdes fra bygg til bygg. Uten den lages et sertifikat
per kjøring, og det trekkes tilbake etterpå (Apple sender en e-post om det hver gang).

    python3 tools/asc.py check                  sjekker nøkkelen, app-id-en og appen i App Store Connect, og legger
                                                til iOS og macOS i appen første gang (Apple TV, iPhone, iPad og
                                                Mac er én app)
    python3 tools/asc.py prepare <mappe>        finner eller lager distribusjonssertifikatet og lager en App
                                                Store-profil per plattform for denne kjøringen (nøkkel, sertifikat,
                                                profiler og ExportOptions-tvOS.plist/-iOS.plist/-macOS.plist, der
                                                eksporten laster bygget rett opp til App Store Connect; for Mac også
                                                sertifikatet til installasjonspakken)
    python3 tools/asc.py cleanup <mappe>        sletter profilene, og trekker tilbake sertifikatet hvis det ble laget
                                                bare for denne kjøringen (uten DIST_KEY_PATH)
    python3 tools/asc.py builds                 de siste byggene i App Store Connect og om de er klare for TestFlight
    python3 tools/asc.py wait <byggnummer>      venter (høyst 25 min) til bygget for plattformene dukker opp i App
                                                Store Connect (ASC_PLATFORMS, f.eks. «TV_OS IOS», ellers alle);
                                                når det er ferdig behandlet, legges det til de eksterne
                                                testgruppene og sendes til Apples beta-gjennomgang, med avsnittet
                                                fra CHANGELOG.md som «Hva skal testes» (ikke med
                                                EKSTERN_TESTFLIGHT=0; feiler det, bare en advarsel)

Skriver aldri ut nøkler eller tokens. Bare standardbiblioteket og openssl.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "no.fyrlys.tv"
APP_NAME = "Fyrlys"
OPENSSL = "/usr/bin/openssl" if Path("/usr/bin/openssl").exists() else "openssl"
# plattformene: navnet i filene, profiltypen og plattformen i App Store Connect
PLATFORMS = [("tvOS", "TVOS_APP_STORE", "TV_OS"), ("iOS", "IOS_APP_STORE", "IOS"),
             ("macOS", "MAC_APP_STORE", "MAC_OS")]
# Mac (fra 0.2.2) er valgfri: feiler noe for den, lastes Apple TV og iPhone/iPad opp likevel
OPTIONAL = {"macOS"}
# utvidelsene i appen per plattform (app-id og navn): Top Shelf på Apple TV, widgeten på iPhone og iPad
EXTENSIONS = {"tvOS": [("no.fyrlys.tv.topshelf", "Fyrlys Top Shelf")],
              "iOS": [("no.fyrlys.tv.widget", "Fyrlys Widget")]}


def env(name):
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"{name} mangler")
    return value


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    """ECDSA-signaturen fra openssl (DER: SEQUENCE av to INTEGER) → r || s, 32 + 32 byte, som JWT vil ha."""
    assert der[0] == 0x30, "ukjent signatur"
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert der[i] == 0x02, "ukjent signatur"
        length = der[i + 1]
        value = der[i + 2:i + 2 + length].lstrip(b"\0")
        out += value.rjust(32, b"\0")
        i += 2 + length
    return out


def token(key_path, key_id, issuer, now=None):
    now = int(now or time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run([OPENSSL, "dgst", "-sha256", "-sign", key_path], input=signing_input,
                         capture_output=True, check=True).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


class Asc:
    def __init__(self):
        self.key_path = env("ASC_KEY_PATH")
        self.key_id = env("ASC_KEY_ID")
        self.issuer = env("ASC_ISSUER_ID")
        self._token = None
        self._made = 0

    def request(self, method, path, body=None, tries=3):
        """Svaret fra App Store Connect. Svarer ikke Apple (tidsavbrudd, brutt forbindelse) eller svarer med 5xx,
        prøves det igjen (bygg 44 stoppet på et tidsavbrudd da profilen skulle lages)."""
        for attempt in range(tries):
            if not self._token or time.time() - self._made > 600:
                self._token = token(self.key_path, self.key_id, self.issuer)
                self._made = time.time()
            data = json.dumps(body).encode() if body is not None else None
            req = urllib.request.Request(API + path, data=data, method=method, headers={
                "Authorization": f"Bearer {self._token}", "Content-Type": "application/json"})
            last = attempt + 1 >= tries
            try:
                with urllib.request.urlopen(req, timeout=90) as res:
                    raw = res.read()
                    return res.status, (json.loads(raw) if raw else {})
            except urllib.error.HTTPError as e:
                raw = e.read()
                if e.code in (500, 502, 503, 504) and not last:
                    print(f"{method} {path.split('?')[0]}: HTTP {e.code}, prøver igjen", file=sys.stderr)
                    time.sleep(10 * (attempt + 1))
                    continue
                try:
                    return e.code, json.loads(raw)
                except ValueError:
                    return e.code, {}
            except (TimeoutError, ConnectionError, urllib.error.URLError) as e:
                if last:
                    sys.exit(f"{method} {path.split('?')[0]}: Apple svarte ikke ({e})")
                print(f"{method} {path.split('?')[0]}: {e}, prøver igjen", file=sys.stderr)
                time.sleep(10 * (attempt + 1))

    def call(self, method, path, body=None, ok=(200, 201, 204)):
        code, res = self.request(method, path, body)
        if code not in ok:
            sys.exit(f"{method} {path.split('?')[0]}: HTTP {code} {errors(res)}")
        return res


def errors(res):
    return "; ".join(f"{e.get('title', '')}: {e.get('detail', '')}" for e in res.get("errors", [])) or "(uten forklaring)"


def data(kind, attributes, relationships=None):
    d = {"type": kind, "attributes": attributes}
    if relationships:
        d["relationships"] = relationships
    return {"data": d}


def bundle_id(asc, identifier=BUNDLE_ID):
    found = asc.call("GET", f"/v1/bundleIds?filter[identifier]={identifier}&limit=50")
    for row in found.get("data", []):
        if row["attributes"]["identifier"] == identifier:
            return row
    return None


def ensure_bundle_id(asc, identifier, name):
    row = bundle_id(asc, identifier)
    if not row:
        row = asc.call("POST", "/v1/bundleIds", data("bundleIds", {
            "identifier": identifier, "name": name, "platform": "IOS"}))["data"]
        print(f"::notice title=app-id::Registrerte {identifier}")
    return row


def check():
    asc = Asc()
    code, res = asc.request("GET", "/v1/apps?filter[bundleId]=" + BUNDLE_ID)
    if code == 401:
        sys.exit("App Store Connect avviste nøkkelen (401): sjekk ASC_KEY_ID, ASC_ISSUER_ID og ASC_KEY_P8")
    if code == 403:
        sys.exit(f"Nøkkelen har ikke tilgang (403): den må ha rollen Admin. {errors(res)}")
    if code != 200:
        sys.exit(f"App Store Connect svarte HTTP {code}: {errors(res)}")
    if not bundle_id(asc):
        sys.exit(f"App-id-en {BUNDLE_ID} er ikke registrert (developer.apple.com → Identifiers)")
    apps = [a for a in res.get("data", []) if a["attributes"].get("bundleId") == BUNDLE_ID]
    if not apps:
        sys.exit(f"Ingen app med {BUNDLE_ID} i App Store Connect (Apps → + → New App, tvOS)")
    print(f"Nøkkelen virker, og appen «{apps[0]['attributes'].get('name')}» finnes i App Store Connect")
    ensure_platform(asc, apps[0]["id"], "IOS")
    if not ensure_platform(asc, apps[0]["id"], "MAC_OS", required=False):
        github_env("MAC_OS_READY", "0")
    # iCloud (nøkkel–verdi-lagringen, for favorittene på alle enhetene): signeringen tar den med bare når den er på
    if ensure_capability(asc, bundle_id(asc)["id"], "ICLOUD",
                         [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}]):
        github_env("ICLOUD_KVS", "1")


def github_env(name, value):
    path = os.environ.get("GITHUB_ENV")
    if path:
        with open(path, "a") as f:
            f.write(f"{name}={value}\n")


def ensure_capability(asc, bundle, kind, settings=None):
    """Slår på tjenesten [kind] for app-id-en (profilene som lages etterpå, får den med). Sant hvis den er på."""
    code, res = asc.request("GET", f"/v1/bundleIds/{bundle}/bundleIdCapabilities?limit=200")
    if code == 200 and any(r["attributes"].get("capabilityType") == kind for r in res.get("data", [])):
        return True
    attrs = {"capabilityType": kind}
    if settings:
        attrs["settings"] = settings
    code, res = asc.request("POST", "/v1/bundleIdCapabilities", data("bundleIdCapabilities", attrs, {
        "bundleId": {"data": {"type": "bundleIds", "id": bundle}}}))
    if code not in (200, 201):
        print(f"::warning title=app-id::Fikk ikke slått på {kind} for {BUNDLE_ID}: HTTP {code} {errors(res)}; "
              "bygget lages uten")
        return False
    print(f"::notice title=app-id::Slo på {kind} for {BUNDLE_ID}")
    return True


def ensure_platform(asc, app, platform, required=True):
    """Legger plattformen til i appen (en App Store-versjon for den), så bygg for den kan lastes opp til samme app.
    Sant når den er der."""
    versions = asc.call("GET", f"/v1/apps/{app}/appStoreVersions?limit=200").get("data", [])
    if any(v["attributes"].get("platform") == platform for v in versions):
        return True
    code, res = asc.request("POST", "/v1/appStoreVersions", data("appStoreVersions", {
        "platform": platform, "versionString": "1.0"}, {"app": {"data": {"type": "apps", "id": app}}}))
    if code not in (200, 201):
        message = (f"Fikk ikke lagt {platform} til appen i App Store Connect: HTTP {code} {errors(res)} "
                   "(legg den til for hånd: appen → + ved plattformene)")
        if required:
            sys.exit(message)
        print(f"::warning title={platform}::{message}")
        return False
    print(f"::notice title=App Store Connect::La til {platform} i appen")
    return True


def export_options(folder, manual_profile=None, file="ExportOptions.plist", extra=None, installer=None):
    team = env("APPLE_TEAM_ID")
    if manual_profile:
        profiles = {BUNDLE_ID: manual_profile, **(extra or {})}
        entries = "".join(f"<key>{k}</key><string>{v}</string>" for k, v in profiles.items())
        signing = ("<key>signingStyle</key><string>manual</string>"
                   "<key>signingCertificate</key><string>Apple Distribution</string>"
                   f"<key>provisioningProfiles</key><dict>{entries}</dict>")
        if installer:
            # Mac: pakken som lastes opp, signeres med installasjonssertifikatet (typen fra navnet på det)
            signing += f"<key>installerSigningCertificate</key><string>{installer}</string>"
    else:
        signing = "<key>signingStyle</key><string>automatic</string>"
    Path(folder).mkdir(parents=True, exist_ok=True)
    (Path(folder) / file).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>{team}</string>
  {signing}
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict></plist>
''')


def prepare(folder):
    asc = Asc()
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    os.chmod(folder, 0o700)
    state = {"profiles": []}
    save = lambda: (folder / "state.json").write_text(json.dumps(state))  # noqa: E731

    row = bundle_id(asc)
    if not row:
        row = asc.call("POST", "/v1/bundleIds", data("bundleIds", {
            "identifier": BUNDLE_ID, "name": APP_NAME, "platform": "IOS"}))["data"]
        print(f"Registrerte app-id-en {BUNDLE_ID}")

    # nøkkelen (RSA, PKCS#1 som «security import -f openssl» leser): den faste fra DIST_KEY, ellers en ny
    key, csr = folder / "distribution.key", folder / "distribution.csr"
    kept = os.environ.get("DIST_KEY_PATH", "").strip()
    rsa_key(kept or None, key)

    def certificate(kind, title, out, state_key):
        """Sertifikatet av typen [kind] for nøkkelen: det fra før (med DIST_KEY), ellers et nytt."""
        cert = find_certificate(asc, key, kind) if kept else None
        # som merknad på bygget (loggen kan ikke leses fra Claude-økta)
        if cert:
            print(f"::notice title=sertifikat::Bruker {title} fra før (utløper "
                  f"{cert['attributes'].get('expirationDate')})")
        else:
            if not csr.exists():
                subprocess.run([OPENSSL, "req", "-new", "-key", str(key), "-out", str(csr), "-subj",
                                f"/CN={APP_NAME} CI/O={env('APPLE_TEAM_ID')}"], check=True, capture_output=True)
            cert = asc.call("POST", "/v1/certificates", data("certificates", {
                "certificateType": kind, "csrContent": csr.read_text()}))["data"]
            if kept:
                print(f"::notice title=sertifikat::Laget {title} som beholdes til neste bygg (utløper "
                      f"{cert['attributes'].get('expirationDate')})")
            else:
                # trekkes tilbake av cleanup
                state[state_key] = cert["id"]
                save()
                print(f"Laget {title} for denne kjøringen (utløper {cert['attributes'].get('expirationDate')})")
        (folder / out).write_bytes(base64.b64decode(cert["attributes"]["certificateContent"]))
        return cert

    cert = certificate("DISTRIBUTION", "distribusjonssertifikatet", "distribution.cer", "certificate")

    run = f"{os.environ.get('GITHUB_RUN_ID', int(time.time()))}-{os.environ.get('GITHUB_RUN_ATTEMPT', 1)}"

    def make_profile(bundle_row, name, kind):
        code, res = asc.request("POST", "/v1/profiles", data("profiles", {"name": name, "profileType": kind}, {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_row["id"]}},
            "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
        }))
        if code in (200, 201):
            profile = res["data"]
        else:
            # et forsøk som gikk ut på tid, kan ha laget profilen likevel (navnet er det samme): bruk den
            found = asc.call("GET", "/v1/profiles?filter[name]=" + urllib.parse.quote(name)).get("data", [])
            if not found:
                sys.exit(f"POST /v1/profiles: HTTP {code} {errors(res)}")
            profile = found[0]
        state["profiles"].append({"id": profile["id"], "name": name})
        save()
        suffix = "provisionprofile" if kind.startswith("MAC") else "mobileprovision"
        (folder / f"{profile['attributes']['uuid']}.{suffix}").write_bytes(
            base64.b64decode(profile["attributes"]["profileContent"]))
        print(f"Laget App Store-profilen «{name}»")

    for platform, kind, store in PLATFORMS:
        if store == "MAC_OS" and os.environ.get("MAC_OS_READY") == "0":
            print("::warning title=macOS::Mac er ikke lagt til appen i App Store Connect; bygget lastes ikke opp")
            continue
        try:
            installer = None
            if store == "MAC_OS":
                certificate("MAC_INSTALLER_DISTRIBUTION", "installasjonssertifikatet for Mac", "installer.cer",
                            "installer")
                installer = certificate_kind(folder / "installer.cer")
            name = f"{APP_NAME} CI {run} {platform}"
            make_profile(row, name, kind)
            extra = {}
            for identifier, title in EXTENSIONS.get(platform, []):
                ext_name = f"{name} {identifier.rsplit('.', 1)[-1]}"
                make_profile(ensure_bundle_id(asc, identifier, title), ext_name, kind)
                extra[identifier] = ext_name
            export_options(folder, manual_profile=name, file=f"ExportOptions-{platform}.plist", extra=extra,
                           installer=installer)
        except SystemExit as stop:
            if platform not in OPTIONAL:
                raise
            print(f"::warning title={platform}::{stop}; bygget for {platform} lastes ikke opp")


def certificate_kind(path):
    """Typen fra navnet på sertifikatet («3rd Party Mac Developer Installer: Navn (TEAM)» → delen før kolon, så navnet
    ikke havner i loggene); xcodebuild finner identiteten med den."""
    res = subprocess.run([OPENSSL, "x509", "-inform", "DER", "-in", str(path), "-noout", "-subject",
                          "-nameopt", "multiline,utf8"], capture_output=True)
    for line in res.stdout.decode(errors="replace").splitlines():
        line = line.strip()
        if line.startswith("commonName"):
            return line.split("=", 1)[1].strip().split(":", 1)[0].strip()
    return "3rd Party Mac Developer Installer"


def rsa_key(source, out):
    """Skriver nøkkelen i [source] (PKCS#1 eller PKCS#8, også med CRLF), eller en ny (RSA 2048), som PKCS#1 til [out]."""
    tmp = Path(str(out) + ".tmp")
    if source:
        tmp.write_bytes(Path(source).read_bytes().replace(b"\r", b""))
    else:
        subprocess.run([OPENSSL, "genrsa", "-out", str(tmp), "2048"], check=True, capture_output=True)
    os.chmod(tmp, 0o600)
    res = subprocess.run([OPENSSL, "rsa", "-in", str(tmp), "-out", str(out)], capture_output=True)
    if res.returncode != 0:
        tmp.unlink()
        sys.exit("Nøkkelen i DIST_KEY er ikke en privat RSA-nøkkel (lag den med «openssl genrsa -out fyrlys-dist.key "
                 "2048» og lim inn hele fila, med BEGIN- og END-linjene)")
    if "BEGIN RSA PRIVATE KEY" not in out.read_text():  # OpenSSL 3 skriver PKCS#8 uten -traditional
        subprocess.run([OPENSSL, "rsa", "-in", str(tmp), "-out", str(out), "-traditional"], check=True,
                       capture_output=True)
    tmp.unlink()
    os.chmod(out, 0o600)


def modulus(args, data=None):
    res = subprocess.run([OPENSSL] + args + ["-noout", "-modulus"], input=data, capture_output=True)
    text = res.stdout.decode(errors="replace").strip()
    return text.split("=", 1)[1].upper() if res.returncode == 0 and "=" in text else None


def find_certificate(asc, key, kind="DISTRIBUTION"):
    """Sertifikatet av typen [kind] hos Apple med samme offentlige nøkkel som [key]. Går det ut innen to uker, trekkes
    det tilbake (en gang i året), så prepare lager et nytt."""
    mine = modulus(["rsa", "-in", str(key)])
    soon = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(time.time() + 14 * 86400))
    rows = asc.call("GET", f"/v1/certificates?filter[certificateType]={kind}&limit=200").get("data", [])
    for row in rows:
        content = row["attributes"].get("certificateContent")
        if not content or modulus(["x509", "-inform", "DER"], base64.b64decode(content)) != mine:
            continue
        if (row["attributes"].get("expirationDate") or "") > soon:
            return row
        code, res = asc.request("DELETE", f"/v1/certificates/{row['id']}")
        print(f"::notice title=sertifikat::Sertifikatet fra før går snart ut og ble trukket tilbake (HTTP {code}); "
              "lager et nytt")
    return None


def cleanup(folder):
    path = Path(folder) / "state.json"
    if not path.exists():
        return
    asc = Asc()
    state = json.loads(path.read_text())
    failed = False
    for profile in state.get("profiles", []):
        code, res = asc.request("DELETE", f"/v1/profiles/{profile['id']}")
        if code not in (204, 404):
            print(f"::warning::Profilen {profile['name']} ble ikke slettet: HTTP {code} {errors(res)}")
            failed = True
    for field in ("certificate", "installer"):
        if not state.get(field):
            continue
        code, res = asc.request("DELETE", f"/v1/certificates/{state[field]}")
        if code not in (204, 404):
            print(f"::warning::Sertifikatet ({field}) ble ikke trukket tilbake: HTTP {code} {errors(res)}")
            failed = True
    if not failed:
        print("::notice title=opprydding::" + ("Slettet profilene og trakk tilbake sertifikatet fra denne kjøringen"
              if state.get("certificate") else "Slettet profilene (sertifikatet beholdes til neste bygg)"))
    sys.exit(1 if failed else 0)


def builds():
    """De siste byggene, om de er ferdig behandlet, og testgruppene, som merknader i GitHub Actions."""
    asc = Asc()
    apps = asc.call("GET", "/v1/apps?filter[bundleId]=" + BUNDLE_ID).get("data", [])
    apps = [a for a in apps if a["attributes"].get("bundleId") == BUNDLE_ID]
    if not apps:
        sys.exit(f"Ingen app med {BUNDLE_ID} i App Store Connect")
    app = apps[0]["id"]
    res = asc.call("GET", f"/v1/builds?filter[app]={app}&sort=-uploadedDate&limit=10"
                          "&include=preReleaseVersion,buildBetaDetail")
    included = {(i["type"], i["id"]): i for i in res.get("included", [])}
    lines = []
    for b in res.get("data", []):
        a = b["attributes"]
        rel = b.get("relationships", {})
        version = included.get(("preReleaseVersions", (rel.get("preReleaseVersion", {}).get("data") or {}).get("id")))
        detail = included.get(("buildBetaDetails", (rel.get("buildBetaDetail", {}).get("data") or {}).get("id")))
        lines.append(" ".join([
            f"{(version or {}).get('attributes', {}).get('version', '?')} ({a.get('version')})",
            (version or {}).get("attributes", {}).get("platform", ""),
            f"behandling: {a.get('processingState')}",
            f"intern test: {(detail or {}).get('attributes', {}).get('internalBuildState', '?')}",
            f"lastet opp {a.get('uploadedDate', '')[:16]}",
            "utløpt" if a.get("expired") else "",
        ]).strip())
    if not lines:
        lines.append("Ingen bygg i App Store Connect ennå")
    groups = asc.call("GET", f"/v1/apps/{app}/betaGroups?limit=20").get("data", [])
    lines.append("Testgrupper: " + (", ".join(
        f"{g['attributes'].get('name')} ({'intern' if g['attributes'].get('isInternalGroup') else 'ekstern'})"
        for g in groups) or "ingen"))
    for line in lines:
        print(line)
    print("::notice title=App Store Connect::" + "%0A".join(lines))


def app_id(asc):
    apps = asc.call("GET", "/v1/apps?filter[bundleId]=" + BUNDLE_ID).get("data", [])
    apps = [a for a in apps if a["attributes"].get("bundleId") == BUNDLE_ID]
    if not apps:
        sys.exit(f"Ingen app med {BUNDLE_ID} i App Store Connect")
    return apps[0]["id"]


def wait(number, minutes=25):
    """Venter til bygget med [number] finnes i App Store Connect for alle plattformene (og helst er ferdig behandlet)."""
    asc = Asc()
    app = app_id(asc)
    wanted = os.environ.get("ASC_PLATFORMS", "").split() or [store for _, _, store in PLATFORMS]
    deadline = time.time() + minutes * 60
    states = {}
    ids = {}
    while time.time() < deadline:
        res = asc.call("GET", f"/v1/builds?filter[app]={app}&filter[version]={number}&include=preReleaseVersion"
                              "&limit=10")
        versions = {i["id"]: i for i in res.get("included", []) if i["type"] == "preReleaseVersions"}
        states = {}
        ids = {}
        for build in res.get("data", []):
            pre = (build.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}).get("id")
            platform = versions.get(pre, {}).get("attributes", {}).get("platform", "?")
            states[platform] = build["attributes"].get("processingState")
            ids[platform] = build["id"]
        if all(p in states and states[p] != "PROCESSING" for p in wanted):
            break
        time.sleep(30)
    lines = [f"Bygg {number} ({p}): {states.get(p, 'kom ikke fram')}" for p in wanted]
    print("::notice title=App Store Connect::" + "%0A".join(lines))
    missing = [p for p in wanted if p not in states]
    if missing:
        sys.exit(f"Bygg {number} kom ikke fram til App Store Connect for {', '.join(missing)} på {minutes} minutter "
                 "(se e-posten fra App Store Connect)")
    bad = [p for p in wanted if states[p] in ("FAILED", "INVALID")]
    if bad:
        sys.exit(f"App Store Connect avviste bygg {number} for {', '.join(bad)}; grunnen står i e-posten fra App Store "
                 "Connect")
    if os.environ.get("EKSTERN_TESTFLIGHT", "1") != "0":
        ready = {p: ids[p] for p in wanted if states.get(p) == "VALID"}
        try:
            share_external(asc, app, ready)
        except SystemExit as stop:
            print(f"::warning title=ekstern TestFlight::{stop}")


def whats_new(path=Path(__file__).resolve().parent.parent / "CHANGELOG.md"):
    """Det første avsnittet i CHANGELOG.md (den nye versjonen) som ren tekst, høyst 4000 tegn."""
    try:
        text = path.read_text()
    except OSError:
        return ""
    sections = text.split("\n## ")
    if len(sections) < 2:
        return ""
    body = sections[1].split("\n", 1)[1] if "\n" in sections[1] else ""
    body = body.replace("**", "").replace("*", "").replace("`", "")
    lines = [line.strip() for line in body.strip().splitlines()]
    # punktene på én linje hver (i fila er de brutt over flere)
    out = []
    for line in lines:
        if line.startswith("- ") or not out:
            out.append(line)
        elif line:
            out[-1] += " " + line
    return "\n".join(out)[:4000]


def share_external(asc, app, builds):
    """Byggene (plattform → id) til de eksterne testgruppene, med «Hva skal testes», og til beta-gjennomgangen."""
    if not builds:
        return
    code, res = asc.request("GET", f"/v1/betaGroups?filter[app]={app}&filter[isInternalGroup]=false&limit=50")
    if code != 200:
        sys.exit(f"fant ikke testgruppene: HTTP {code} {errors(res)}")
    groups = [(g["id"], None) for g in res.get("data", [])]
    if not groups:
        print("::notice title=ekstern TestFlight::Ingen eksterne testgrupper; bygget er bare for de interne")
        return
    note = whats_new()
    done = []
    for platform, build in builds.items():
        if note:
            code, res = asc.request("GET", f"/v1/builds/{build}/betaBuildLocalizations")
            found = res.get("data", []) if code == 200 else []
            if found:
                for loc in found:
                    asc.request("PATCH", f"/v1/betaBuildLocalizations/{loc['id']}",
                                {"data": {"type": "betaBuildLocalizations", "id": loc["id"],
                                          "attributes": {"whatsNew": note}}})
            else:
                for locale in ("no", "nb", "en-US"):
                    code, res = asc.request("POST", "/v1/betaBuildLocalizations", data(
                        "betaBuildLocalizations", {"locale": locale, "whatsNew": note},
                        {"build": {"data": {"type": "builds", "id": build}}}))
                    if code in (200, 201):
                        break
        for group, _ in groups:
            code, res = asc.request("POST", f"/v1/betaGroups/{group}/relationships/builds",
                                    {"data": [{"type": "builds", "id": build}]})
            if code not in (200, 201, 204):
                print(f"::warning title=ekstern TestFlight::{platform}: kunne ikke legge bygget til en ekstern "
                      f"gruppe: HTTP {code} {errors(res)}")
        code, res = asc.request("POST", "/v1/betaAppReviewSubmissions", data(
            "betaAppReviewSubmissions", {}, {"build": {"data": {"type": "builds", "id": build}}}))
        # 409: sendt fra før (eller en gjennomgang pågår)
        if code in (200, 201):
            done.append(f"{platform}: sendt til gjennomgang")
        elif code == 409:
            done.append(f"{platform}: {errors(res)}")
        else:
            done.append(f"{platform}: gjennomgangen feilet (HTTP {code} {errors(res)})")
    # bare antallet: navnene på gruppene skal ikke i de offentlige loggene
    print(f"::notice title=ekstern TestFlight::Lagt til {len(groups)} ekstern(e) testgruppe(r)%0A" + "%0A".join(done))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    command = sys.argv[1]
    if command == "check":
        check()
    elif command == "prepare" and len(sys.argv) == 3:
        prepare(sys.argv[2])
    elif command == "cleanup" and len(sys.argv) == 3:
        cleanup(sys.argv[2])
    elif command == "builds":
        builds()
    elif command == "wait" and len(sys.argv) == 3:
        wait(sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
