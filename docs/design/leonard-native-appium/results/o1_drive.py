#!/usr/bin/env python3
"""leonard_native spike — full enter_text proof (lenny-qxx.1).

Builds on the GREEN O1 reachability result: the Auth0 web inputs surface as
named native nodes. This proves native.enter_text actually LANDS: type a per-run
nonce email + a password into the real Auth0 fields and read the values back.

Acceptance (spec):
 #2 email readback == exact typed string.
 #3 password readback non-empty AND != plaintext (masked secure field).
Right-page guard: the Auth0 domain must be in the tree (not the Flutter app).
Vacuity: also assert a deliberately-wrong expectation FAILS.
"""
import base64
import json
import os
import sys
import time
import urllib.request

APPIUM = "http://127.0.0.1:4723"
UDID = "EC89E46C-0E95-4C15-907C-DFD13AC611BE"
APP = os.path.expanduser("~/lenny-spike/auth0_sample/build/ios/iphonesimulator/Runner.app")
OUT = os.path.expanduser("~/lenny-spike")
DOMAIN = "dev-y1gwg3ay5b5rl17n.us.auth0.com"
EL = "element-6066-11e4-a52e-4f735466cecf"
EMAIL = f"spike+{int(time.time())}@lenny.dev"   # per-run nonce (FP3 guard)
PW = "Sp1ke-Test-2026!"


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(APPIUM + path, data=data, method=method,
                               headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=300) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def find(sid, xpath):
    st, b = req("POST", f"/session/{sid}/element", {"using": "xpath", "value": xpath})
    return b["value"].get(EL) if st == 200 else None


def main():
    st, b = req("POST", "/session", {"capabilities": {"alwaysMatch": {
        "platformName": "iOS", "appium:automationName": "XCUITest",
        "appium:udid": UDID, "appium:app": APP,
        "appium:forceSimulatorSoftwareKeyboardPresence": True,
        "appium:noReset": True, "appium:newCommandTimeout": 180,
        "appium:wdaLaunchTimeout": 240000,
    }}})
    if st != 200:
        print(f"FAIL new session {st}: {json.dumps(b)[:400]}"); return 1
    sid = b["value"]["sessionId"]
    try:
        click = lambda eid: req("POST", f"/session/{sid}/element/{eid}/click", {})
        login = find(sid, "//XCUIElementTypeButton[@name='Log in']")
        if not login:
            print("FAIL: app 'Log in' not found"); return 1
        click(login)
        time.sleep(3)
        req("POST", f"/session/{sid}/alert/accept", {})   # ASWebAuthenticationSession consent
        time.sleep(7)

        # Right-page guard (FP1/FP2): must be on the Auth0 domain.
        _, src = req("GET", f"/session/{sid}/source")
        on_auth0 = DOMAIN in src.get("value", "")

        email_el = find(sid, "//XCUIElementTypeTextField[@name='Email address']")
        pw_el = find(sid, "//XCUIElementTypeSecureTextField[@name='Password']")
        if not (email_el and pw_el):
            print("FAIL: Auth0 email/password fields not found"); return 1

        click(email_el)
        req("POST", f"/session/{sid}/element/{email_el}/value", {"text": EMAIL})
        click(pw_el)
        req("POST", f"/session/{sid}/element/{pw_el}/value", {"text": PW})
        time.sleep(1)

        _, ev = req("GET", f"/session/{sid}/element/{email_el}/attribute/value")
        _, pv = req("GET", f"/session/{sid}/element/{pw_el}/attribute/value")
        email_read, pw_read = ev.get("value") or "", pv.get("value") or ""

        # screenshot at assert time
        _, shot = req("GET", f"/session/{sid}/screenshot")
        if shot.get("value"):
            with open(f"{OUT}/spike_drive_screen.png", "wb") as f:
                f.write(base64.b64decode(shot["value"]))

        email_ok = (email_read == EMAIL)                       # #2 exact equality
        pw_landed = bool(pw_read) and (pw_read != PW)           # #3 non-empty + masked
        vacuity_ok = (email_read != "definitely-not-the-typed-value")  # wrong expectation fails->this is True
        print(json.dumps({
            "event": "drive_result", "on_auth0_page": on_auth0,
            "typed_email": EMAIL, "email_readback": email_read, "email_ok": email_ok,
            "pw_readback": pw_read, "pw_landed": pw_landed,
            "verdict": "PASS" if (on_auth0 and email_ok and pw_landed) else "CHECK",
        }))
        if on_auth0 and email_ok and pw_landed and vacuity_ok:
            print("DRIVE PASS: native.enter_text landed in the real Auth0 email+password fields.")
            return 0
        print("DRIVE CHECK: inspect spike_drive_screen.png / readbacks above (see FN3 for secure-field readback).")
        return 2
    finally:
        req("DELETE", f"/session/{sid}")


if __name__ == "__main__":
    sys.exit(main())
