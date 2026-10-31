#!/usr/bin/env python3
"""App Store Connect fra GitHub Actions (uten Mac og uten Xcode-konto), med API-nøkkelen i miljøet:
ASC_KEY_PATH (.p8-fila), ASC_KEY_ID, ASC_ISSUER_ID og APPLE_TEAM_ID.

    python3 tools/asc.py check                  sjekker nøkkelen, app-id-en og appen i App Store Connect
    python3 tools/asc.py options <mappe>        ExportOptions.plist for skysignering (Apples egne sertifikater)
    python3 tools/asc.py prepare <mappe>        reserve: lager et distribusjonssertifikat og en App Store-profil
                                                for denne kjøringen (nøkkel, sertifikat, profil og ExportOptions)
    python3 tools/asc.py cleanup <mappe>        sletter profilen og trekker tilbake sertifikatet prepare laget

Skriver aldri ut nøkler eller tokens. Bare standardbiblioteket og openssl.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "no.fyrlys.tv"
APP_NAME = "Fyrlys"
OPENSSL = "/usr/bin/openssl" if Path("/usr/bin/openssl").exists() else "openssl"


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

    def request(self, method, path, body=None):
        if not self._token or time.time() - self._made > 600:
            self._token = token(self.key_path, self.key_id, self.issuer)
            self._made = time.time()
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(API + path, data=data, method=method, headers={
            "Authorization": f"Bearer {self._token}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as res:
                raw = res.read()
                return res.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, {}

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


def bundle_id(asc):
    found = asc.call("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE_ID}&limit=50")
    for row in found.get("data", []):
        if row["attributes"]["identifier"] == BUNDLE_ID:
            return row
    return None


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


def export_options(folder, manual_profile=None):
    team = env("APPLE_TEAM_ID")
    if manual_profile:
        signing = ("<key>signingStyle</key><string>manual</string>"
                   "<key>signingCertificate</key><string>Apple Distribution</string>"
                   f"<key>provisioningProfiles</key><dict><key>{BUNDLE_ID}</key><string>{manual_profile}</string></dict>")
    else:
        signing = "<key>signingStyle</key><string>automatic</string>"
    Path(folder).mkdir(parents=True, exist_ok=True)
    (Path(folder) / "ExportOptions.plist").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
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

    # nøkkelen (RSA 2048, PKCS#1 som «security import -f openssl» leser) og forespørselen om sertifikat
    key, csr = folder / "distribution.key", folder / "distribution.csr"
    subprocess.run([OPENSSL, "genrsa", "-out", str(key) + ".tmp", "2048"], check=True, capture_output=True)
    subprocess.run([OPENSSL, "rsa", "-in", str(key) + ".tmp", "-out", str(key)], check=True, capture_output=True)
    if "BEGIN RSA PRIVATE KEY" not in key.read_text():  # OpenSSL 3 skriver PKCS#8 uten -traditional
        subprocess.run([OPENSSL, "rsa", "-in", str(key) + ".tmp", "-out", str(key), "-traditional"], check=True,
                       capture_output=True)
    os.remove(str(key) + ".tmp")
    os.chmod(key, 0o600)
    subprocess.run([OPENSSL, "req", "-new", "-key", str(key), "-out", str(csr), "-subj",
                    f"/CN={APP_NAME} CI/O={env('APPLE_TEAM_ID')}"], check=True, capture_output=True)
    cert = asc.call("POST", "/v1/certificates", data("certificates", {
        "certificateType": "DISTRIBUTION", "csrContent": csr.read_text()}))["data"]
    state["certificate"] = cert["id"]
    save()
    (folder / "distribution.cer").write_bytes(base64.b64decode(cert["attributes"]["certificateContent"]))
    print(f"Laget et distribusjonssertifikat for denne kjøringen (utløper {cert['attributes'].get('expirationDate')})")

    run = f"{os.environ.get('GITHUB_RUN_ID', int(time.time()))}-{os.environ.get('GITHUB_RUN_ATTEMPT', 1)}"
    name = f"{APP_NAME} CI {run}"
    profile = asc.call("POST", "/v1/profiles", data("profiles", {"name": name, "profileType": "TVOS_APP_STORE"}, {
        "bundleId": {"data": {"type": "bundleIds", "id": row["id"]}},
        "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
    }))["data"]
    state["profiles"].append({"id": profile["id"], "name": name})
    save()
    (folder / f"{profile['attributes']['uuid']}.mobileprovision").write_bytes(
        base64.b64decode(profile["attributes"]["profileContent"]))
    export_options(folder, manual_profile=name)
    print(f"Laget App Store-profilen «{name}»")


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
    if state.get("certificate"):
        code, res = asc.request("DELETE", f"/v1/certificates/{state['certificate']}")
        if code not in (204, 404):
            print(f"::warning::Sertifikatet ble ikke trukket tilbake: HTTP {code} {errors(res)}")
            failed = True
    if not failed:
        print("Slettet profilen og trakk tilbake sertifikatet fra denne kjøringen")
    sys.exit(1 if failed else 0)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    command = sys.argv[1]
    if command == "check":
        check()
    elif command == "options" and len(sys.argv) == 3:
        export_options(sys.argv[2])
    elif command == "prepare" and len(sys.argv) == 3:
        prepare(sys.argv[2])
    elif command == "cleanup" and len(sys.argv) == 3:
        cleanup(sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
