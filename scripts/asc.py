#!/usr/bin/env python3
"""App Store Connect API helper for Webby's local scripts (same key as Cinefin's Tools/).

    python3 scripts/asc.py next-build    # one more than the highest build on App Store Connect
    python3 scripts/asc.py builds        # recent builds and their processing state

Uses the API key in ~/Downloads; the key never leaves this Mac.
"""
import base64, json, os, subprocess, sys, time, urllib.request, urllib.error

KEY_ID = "83W34R3JB7"
ISSUER_ID = "8be62f06-e439-49eb-8d87-0546945e8386"
KEY_PATH = os.path.expanduser(f"~/Downloads/AuthKey_{KEY_ID}.p8")
BUNDLE_ID = "au.leybourne.webby"
OPENSSL = "/usr/bin/openssl"
API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(sig: bytes) -> bytes:
    """ECDSA signature: DER SEQUENCE(r, s) -> the 64-byte r||s that JWT ES256 wants."""
    i = 2 if sig[1] < 0x80 else 2 + (sig[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert sig[i] == 0x02
        n = sig[i + 1]
        out += sig[i + 2:i + 2 + n].lstrip(b"\0").rjust(32, b"\0")
        i += 2 + n
    return out


def token() -> str:
    now = int(time.time())
    head = b64url(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    body = b64url(json.dumps({"iss": ISSUER_ID, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    sig = subprocess.run([OPENSSL, "dgst", "-sha256", "-sign", KEY_PATH], input=f"{head}.{body}".encode(),
                         capture_output=True, check=True).stdout
    return f"{head}.{body}.{b64url(der_to_raw(sig))}"


def api(method: str, path: str, payload=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(payload).encode() if payload else None,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"Apple API error {e.code}: {e.read().decode()[:600]}")


def app_id():
    apps = api("GET", f"/apps?filter[bundleId]={BUNDLE_ID}&limit=1")["data"]
    if not apps:
        sys.exit(f"No app with bundle ID {BUNDLE_ID} on App Store Connect. Create it at "
                 "appstoreconnect.apple.com > Apps > + (platform tvOS) first.")
    return apps[0]["id"]


def builds():
    return api("GET", f"/builds?filter[app]={app_id()}&sort=-uploadedDate&limit=20")["data"]


if __name__ == "__main__":
    if not os.path.exists(KEY_PATH):
        sys.exit(f"Can't find {KEY_PATH}")
    cmd = sys.argv[1] if len(sys.argv) > 1 else "builds"
    if cmd == "next-build":
        versions = [int(b["attributes"]["version"]) for b in builds() if b["attributes"]["version"].isdigit()]
        print(max(versions, default=0) + 1)
    elif cmd == "builds":
        for b in builds():
            a = b["attributes"]
            print(f"build {a['version']}: {a['processingState']} (uploaded {a['uploadedDate'][:16]})")
    else:
        sys.exit(__doc__)
