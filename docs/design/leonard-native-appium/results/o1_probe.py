#!/usr/bin/env python3
"""leonard_native spike — O1 reachability probe (lenny-qxx.1).

The cheapest falsifying experiment: launch the throwaway auth0_flutter sample on
a booted iOS simulator via Appium/XCUITest, tap "Log in" to open the REAL Auth0
Universal Login inside ASWebAuthenticationSession, then dump the OS accessibility
tree and LOOK — do the web email/password inputs surface as XCUIElementType*Field
nodes in NATIVE_APP context? We STOP before SIGN IN (O11); this only answers
reachability, not full drive.

Exit 0 = the a11y tree contains addressable text fields on the Auth0 page (GREEN:
build the full harness). Exit 2 = page reached but NO native fields (RED: pivot to
WEBVIEW context / real device / Android). Exit 1 = infra failure (inconclusive).
"""
import base64
import json
import os
import sys
import time
import urllib.request

APPIUM = os.environ.get("APPIUM_URL", "http://127.0.0.1:4723")
UDID = os.environ.get("UDID", "EC89E46C-0E95-4C15-907C-DFD13AC611BE")
APP = os.environ.get(
    "APP_PATH",
    os.path.expanduser("~/lenny-spike/auth0_sample/build/ios/iphonesimulator/Runner.app"),
)
OUT = os.path.expanduser("~/lenny-spike")
AUTH0_DOMAIN = "dev-y1gwg3ay5b5rl17n.us.auth0.com"
W3C_ELEMENT = "element-6066-11e4-a52e-4f735466cecf"


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(
        APPIUM + path, data=data, method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(r, timeout=300) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def find(sid, xpath):
    st, body = req("POST", f"/session/{sid}/element",
                   {"using": "xpath", "value": xpath})
    if st != 200:
        return None
    return body["value"].get(W3C_ELEMENT)


def click(sid, eid):
    return req("POST", f"/session/{sid}/element/{eid}/click", {})


def main():
    if not os.path.isdir(APP):
        print(f"[O1] FAIL: app not built at {APP}", flush=True)
        return 1
    print(f"[O1] creating XCUITest session on {UDID}", flush=True)
    st, body = req("POST", "/session", {"capabilities": {"alwaysMatch": {
        "platformName": "iOS",
        "appium:automationName": "XCUITest",
        "appium:udid": UDID,
        "appium:app": APP,
        "appium:forceSimulatorSoftwareKeyboardPresence": True,
        "appium:noReset": True,
        "appium:newCommandTimeout": 180,
        "appium:wdaLaunchTimeout": 240000,
    }}})
    if st != 200:
        print(f"[O1] FAIL: new session {st}: {json.dumps(body)[:600]}", flush=True)
        return 1
    sid = body["value"]["sessionId"]
    print(f"[O1] session {sid}", flush=True)
    try:
        btn = find(sid, "//XCUIElementTypeButton[@name='Log in']")
        if not btn:
            print("[O1] FAIL: 'Log in' button not found in app (app didn't launch?)", flush=True)
            return 1
        click(sid, btn)
        print("[O1] tapped Log in; waiting for ASWebAuthenticationSession", flush=True)
        time.sleep(3)
        # The consent sheet ("... Wants to Use ... to Sign In") lives in a SEPARATE
        # system process (SpringBoard), so it is NOT in the app's /source — accept
        # it via the W3C alert endpoint, not an xpath find.
        st_a, ab = req("POST", f"/session/{sid}/alert/accept", {})
        print(f"[O1] alert/accept -> {st_a} {json.dumps(ab)[:160]}", flush=True)
        if st_a != 200:
            cont = find(sid, "//XCUIElementTypeButton[@name='Continue']")
            if cont:
                click(sid, cont)
                print("[O1] tapped Continue (fallback)", flush=True)
        time.sleep(7)  # let the Auth0 web page render in SafariViewService
        # Dump the OS a11y tree + screenshot at the assert point.
        _, src = req("GET", f"/session/{sid}/source")
        xml = src.get("value", "")
        with open(f"{OUT}/spike_source.xml", "w") as f:
            f.write(xml)
        _, shot = req("GET", f"/session/{sid}/screenshot")
        if shot.get("value"):
            with open(f"{OUT}/spike_screen.png", "wb") as f:
                f.write(base64.b64decode(shot["value"]))
        # Analyze.
        n_text = xml.count("XCUIElementTypeTextField")
        n_secure = xml.count("XCUIElementTypeSecureTextField")
        on_auth0 = (AUTH0_DOMAIN in xml) or ("auth0" in xml.lower())
        safari = ("SafariViewService" in xml) or ("SFSafari" in xml)
        print(json.dumps({
            "event": "o1_result",
            "textFields": n_text,
            "secureFields": n_secure,
            "auth0_marker_in_tree": on_auth0,
            "safari_service_in_tree": safari,
            "source_bytes": len(xml),
            "artifacts": [f"{OUT}/spike_source.xml", f"{OUT}/spike_screen.png"],
        }), flush=True)
        # GREEN requires at least the secure (password) field addressable on the page.
        if n_secure >= 1 and n_text >= 1:
            print("[O1] GREEN: native text+secure fields present on the Auth0 surface.", flush=True)
            return 0
        if on_auth0 or safari:
            print("[O1] RED: reached the Auth0/Safari surface but NO native input fields "
                  "in NATIVE_APP — pivot (WEBVIEW context / real device / Android).", flush=True)
            return 2
        print("[O1] INCONCLUSIVE: did not confirm the Auth0 surface — inspect "
              "spike_source.xml / spike_screen.png.", flush=True)
        return 1
    finally:
        req("DELETE", f"/session/{sid}")


if __name__ == "__main__":
    sys.exit(main())
