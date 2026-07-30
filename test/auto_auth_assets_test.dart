import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled unified-auth script has the customized two-attempt flow',
    () async {
      final script = await rootBundle.loadString(
        'assets/scripts/auto_auth_login.js',
      );

      expect(
        sha256.convert(utf8.encode(script)).toString(),
        '556ac274ae40df926374796d5ced093191a19f1a2b24390a80d380a45673efd6',
      );
      expect(script, contains('solveSliderCaptcha(maxAttempts = 2)'));
      expect(script, contains('submitLoginAndSolveSlider(loginViewDiv)'));
      expect(script.indexOf("typeof window.startLogin === 'function'"),
          lessThan(script.indexOf('return solveSliderCaptcha();')));
      expect(script, contains("return 'touch';"));
      expect(script, contains("'touchmove',"));
      expect(script, contains("'touchend',"));
      expect(script, contains("return 'mouse';"));
      expect(script, isNot(contains('.at(-1)')));
      expect(script, isNot(contains("action: 'solveCaptcha'")));
      expect(script, isNot(contains('captchaImg')));
      expect(script, isNot(contains('ONNX')));
      expect(script, contains('NJU_INVALID_CREDENTIALS'));
      expect(script, contains('NJU_SLIDER_FAILED_TWICE'));
      expect(script, contains("document.addEventListener('submit'"));
      expect(
        script,
        contains("sessionStorage.setItem('nju_slider_login_submitted', '1')"),
      );
      expect(
        script,
        contains('HTMLFormElement.prototype.submit = function'),
      );
      expect(script, contains("existingErrorText.includes('验证码')"));
    },
  );

  test('bundled slider trajectory is the complete recorded path', () async {
    final raw = await rootBundle.loadString('assets/recordings/3.json');
    final points = jsonDecode(raw) as List<dynamic>;

    expect(points, hasLength(829));
    expect(points.first, <String, dynamic>{'x': 0, 'y': 36.333});
    expect(points.last, <String, dynamic>{'x': 504, 'y': -41});
  });
}
