// spikes/spike_appium/bin/spike.dart  -- publish_to: none; dep: http ^1.2.0
//
// THROWAWAY de-risk skeleton for a Leonard-shaped native enter_text proof over
// Appium W3C-WebDriver. This is the UN-HARDENED shape as designed; before any
// run, apply the hardening mutations documented in spec.md:
//   - B5: _unwrap must honor HTTP status + non-JSON bodies (throw AppiumError,
//         not FormatException) so find()'s retry guard actually holds.
//   - FN4: readValue must branch iOS attribute/value vs Android attribute/text.
//   - FN3: drop passLanded (length>=pw.length); keep only non-empty && != pw.
//   - FP1/FP2: add a right-page /source machine gate as a hard exit-1 condition.
//   - B6: fix + guard the Android back/keyboard-dismiss route (may 404 on UIA2).
//   - FP3: type a per-run unique nonce email; prefer fresh sim / fullReset.
//   - B8: make bundleId/appPackage/appActivity REQUIRED args (no proprietary defaults).
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class AppiumError implements Exception {
  final String m;
  AppiumError(this.m);
  @override
  String toString() => 'AppiumError: $m';
}

class AppiumSnapshot {
  final String source;
  final String screenshotB64;
  const AppiumSnapshot(this.source, this.screenshotB64);
}

class AppiumBackend {
  final http.Client _c = http.Client();
  final Uri base;
  final String platform;
  String? _sid;
  AppiumBackend(this.base, this.platform);
  Uri _u(String p) => base.resolve(p);

  Future<Map<String, Object?>> _post(String p, Object body) async {
    final r = await _c.post(_u(p),
        headers: {'content-type': 'application/json'}, body: jsonEncode(body));
    return _unwrap(r.body);
  }
  Future<Map<String, Object?>> _get(String p) async =>
      _unwrap((await _c.get(_u(p))).body);

  Map<String, Object?> _unwrap(String b) {
    final j = jsonDecode(b) as Map<String, Object?>;
    final v = j['value'];
    if (v is Map && v['error'] != null) {
      throw AppiumError('${v['error']}: ${v['message']}');
    }
    return j;
  }

  Future<void> connect(Map<String, Object?> caps) async {
    final j = await _post('/session', {
      'capabilities': {'alwaysMatch': caps, 'firstMatch': [<String, Object?>{}]}
    });
    final v = j['value'] as Map<String, Object?>;
    _sid = (v['sessionId'] ?? j['sessionId']) as String;
  }
  Future<void> quit() async {
    if (_sid != null) {
      try {
        await _c.delete(_u('/session/$_sid'));
      } catch (_) {}
    }
  }

  String get _s => _sid ?? (throw AppiumError('no session'));
  Future<void> context(String name) async =>
      _post('/session/$_s/context', {'name': name});

  Future<String?> find(String xpath,
      {Duration timeout = const Duration(seconds: 10),
      bool required = false}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      try {
        final j = await _post('/session/$_s/element',
            {'using': 'xpath', 'value': xpath});
        final v = j['value'] as Map<String, Object?>;
        return v.values.first as String; // element-6066-11e4-a52e-4f735466cecf
      } on AppiumError {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    if (required) throw AppiumError('not found: $xpath');
    return null;
  }
  Future<void> tap(String eid) async =>
      _post('/session/$_s/element/$eid/click', const {});
  Future<void> type(String eid, String text) async {
    await _post('/session/$_s/element/$eid/clear', const {});
    await _post('/session/$_s/element/$eid/value', {'text': text});
  }
  Future<String> readValue(String eid) async {
    final j = await _get('/session/$_s/element/$eid/attribute/value');
    return (j['value'] ?? '').toString();
  }
  Future<AppiumSnapshot> observe() async {
    final src = (await _get('/session/$_s/source'))['value'].toString();
    final shot = (await _get('/session/$_s/screenshot'))['value'].toString();
    return AppiumSnapshot(src, shot);
  }
  Future<void> back() async =>
      _post('/session/$_s/back', const {}); // android keyboard dismiss
}

// ---- recipe selectors (verbatim from LOGIN RECIPE) ----
const iosEmail = "//*[@type='XCUIElementTypeTextField']";
const iosPass = "//*[@type='XCUIElementTypeSecureTextField']";
const iosSignIn = "//*[@name='SIGN IN']";
const iosDone = "//*[@name='Done']";
const iosConsentTitle =
    "//*[@value='“<App Name>” Wants to Use “<tenant-host>” to Sign In']";
const iosContinue = "//*[@name='Continue']";
const andEmail =
    "//android.view.View[@text='Email']/following-sibling::android.widget.EditText";
const andPass =
    "//android.view.View[@text='Password']/../descendant::android.widget.EditText";
const andSignIn = "//android.widget.Button[@text='SIGN IN']";

Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

Future<void> dismissKeyboard(AppiumBackend b, String osVersion) async {
  if (b.platform == 'android') {
    await b.back();
    return;
  }
  if (osVersion.contains('26')) return; // iOS 26 has no Done key
  final done = await b.find(iosDone, timeout: const Duration(seconds: 2));
  if (done != null) await b.tap(done);
}

Future<int> main(List<String> args) async {
  // --platform ios|android --os 17 --email a@b.com --password pw
  // [--device 'iPhone 15 Pro'] [--server http://127.0.0.1:4723]
  final o = _parse(args);
  final b = AppiumBackend(
      Uri.parse(o['server'] ?? 'http://127.0.0.1:4723'), o['platform']!);
  final email = o['email']!, pw = o['password']!, osv = o['os'] ?? '';
  // NOTE: bundleId/appPackage below are reference placeholders -- swap to the
  // throwaway auth0_flutter sample's ids before running.
  final caps = o['platform'] == 'ios'
      ? <String, Object?>{
          'platformName': 'iOS',
          'appium:automationName': 'XCUITest',
          'appium:bundleId': 'com.example.inhouse',
          'appium:platformVersion': osv,
          'appium:deviceName': o['device'] ?? 'iPhone 15 Pro',
          'appium:noReset': true,
          'appium:autoAcceptAlerts': false,
        }
      : <String, Object?>{
          'platformName': 'Android',
          'appium:automationName': 'UiAutomator2',
          'appium:appPackage': 'com.example.app',
          'appium:appActivity': 'com.example.app.MainActivity',
          'appium:appWaitActivity': 'com.example.app.MainActivity',
          'appium:noReset': true,
        };
  try {
    await b.connect(caps);
    await b.context('NATIVE_APP'); // step 1
    await sleep(1000);
    final launch = await b.find(b.platform == 'ios' ? iosSignIn : andSignIn,
        required: true);
    await b.tap(launch!); // opens the hosted Auth0 page
    if (b.platform == 'ios') {
      await sleep(4000);
      final consent =
          await b.find(iosConsentTitle, timeout: const Duration(seconds: 10));
      if (consent != null) {
        final cont =
            await b.find(iosContinue, timeout: const Duration(seconds: 5));
        if (cont != null) await b.tap(cont);
      }
      await sleep(1000);
    } else {
      await sleep(1000);
    }
    // email
    final ef = await b.find(b.platform == 'ios' ? iosEmail : andEmail,
        required: true);
    await b.tap(ef!);
    await b.type(ef, email);
    await dismissKeyboard(b, osv);
    await sleep(1000);
    // password
    final pf = await b.find(b.platform == 'ios' ? iosPass : andPass,
        required: true);
    await b.tap(pf!);
    await b.type(pf, pw);
    await dismissKeyboard(b, osv);
    await sleep(500);
    // ---- ACCEPTANCE: prove text landed BEFORE submitting ----
    final emailVal = await b.readValue(ef);
    final passVal = await b.readValue(pf);
    final snap = await b.observe();
    File('spike_source.xml').writeAsStringSync(snap.source);
    File('spike_screen.png').writeAsBytesSync(base64Decode(snap.screenshotB64));
    final emailOk = emailVal == email;
    // secure field must NOT echo plaintext, but must be non-empty
    final passMasked = passVal != pw && passVal.isNotEmpty;
    final passLanded = passVal.length >= pw.length;
    stdout.writeln(jsonEncode({
      'event': 'spike_result',
      'emailField': emailVal,
      'emailOk': emailOk,
      'passwordMasked': passMasked,
      'passwordLanded': passLanded,
    }));
    final pass = emailOk && passMasked && passLanded;
    await b.quit();
    return pass ? 0 : 1;
  } catch (e) {
    stderr.writeln('FAIL: $e');
    await b.quit();
    return 1;
  }
}

Map<String, String> _parse(List<String> a) {
  final m = <String, String>{};
  for (var i = 0; i < a.length - 1; i += 2) {
    if (a[i].startsWith('--')) m[a[i].substring(2)] = a[i + 1];
  }
  return m;
}
