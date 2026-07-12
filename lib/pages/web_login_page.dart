import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/login_models.dart';
import '../models/school_type.dart';
import '../services/auth_service.dart';
import '../services/captcha_solver_service.dart';

class WebLoginPage extends StatefulWidget {
  const WebLoginPage({
    super.key,
    required this.schoolType,
    required this.authService,
    required this.usernameHint,
    this.autoFillUsername,
    this.autoFillPassword,
    this.llmBaseUrl,
    this.llmApiKey,
    this.llmModel,
  });

  final SchoolType schoolType;
  final AuthService authService;
  final String usernameHint;

  /// Pre-configured credentials for auto-fill.
  final String? autoFillUsername;
  final String? autoFillPassword;

  /// LLM configuration for automatic captcha solving.
  final String? llmBaseUrl;
  final String? llmApiKey;
  final String? llmModel;

  bool get hasCredentials =>
      (autoFillUsername != null && autoFillUsername!.isNotEmpty) ||
      (autoFillPassword != null && autoFillPassword!.isNotEmpty);

  bool get hasLlmConfig =>
      llmBaseUrl != null &&
      llmBaseUrl!.isNotEmpty &&
      llmApiKey != null &&
      llmApiKey!.isNotEmpty;

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  late final WebViewController _controller;

  bool _initializing = true;
  bool _checking = false;
  bool _done = false;

  int _progress = 0;
  String _status = '正在准备网页登录环境…';
  String _currentUrl = '';
  String _lastCheckedUrl = '';

  bool _autoFillDone = false;
  bool _autoFilling = false;
  bool _captchaSolving = false;

  String get _loginEntryUrl {
    final service = Uri.encodeComponent(widget.schoolType.appShowUrl);
    return '${AuthService.loginUrl}?service=$service';
  }

  bool _isTargetArea(String url) {
    return url.contains('ehall.nju.edu.cn') ||
        url.contains('ehallapp.nju.edu.cn') ||
        url.contains('/appShow') ||
        url.contains('/sys/');
  }

  bool _isAuthPage(String url) {
    return url.contains('authserver.nju.edu.cn');
  }

  /// Escape a string for safe embedding in JS single-quoted strings.
  String _escapeJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    debugPrint('[WebLoginPage] Init: schoolType=${widget.schoolType}, userHint=${widget.usernameHint}, autoFillUser=${widget.autoFillUsername}, autoFillPwdLen=${widget.autoFillPassword?.length ?? 0}, hasLlmConfig=${widget.hasLlmConfig}');
    await widget.authService.clearWebViewCookies();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
            });
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _currentUrl = url;
              if (_isAuthPage(url)) {
                _status = '请在官方统一认证页面中完成登录…';
              } else if (_isTargetArea(url)) {
                _status = '已进入目标系统，正在检测登录态…';
              } else {
                _status = '页面跳转中…';
              }
            });
          },
          onPageFinished: (url) async {
            debugPrint('[WebLoginPage] PageFinished: $url');
            if (!mounted || _done) return;

            setState(() {
              _currentUrl = url;
            });

            if (_isAuthPage(url)) {
              // Show debug info about auto-fill gate conditions
              final gateInfo = 'isAuth=true, '
                  'hasCredentials=${widget.hasCredentials}, '
                  'user="${widget.autoFillUsername}", '
                  'pwdLen=${widget.autoFillPassword?.length ?? 0}, '
                  'done=$_autoFillDone, filling=$_autoFilling';
              debugPrint('[WebLoginPage] GateInfo: $gateInfo');
              if (mounted) {
                setState(() {
                  _status = '认证页已加载 [$gateInfo]';
                });
              }

              // Try auto-fill every time auth page finishes loading
              if (!_autoFillDone && !_autoFilling) {
                _attemptAutoFill();
              } else if (mounted) {
                setState(() {
                  _status = '跳过自动填充: done=$_autoFillDone, filling=$_autoFilling';
                });
              }
            } else if (_isTargetArea(url)) {
              await _tryCompleteFromCookies(url);
            }
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _status = '网页加载失败：${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(_loginEntryUrl));

    if (!mounted) return;
    setState(() {
      _initializing = false;
      _status = '请在下方官方页面中完成统一认证登录。';
    });
  }

  // --------------- Auto-fill logic ---------------

  /// Polls up to [maxAttempts] times until the username input is found and
  /// filled. This handles the race condition where the page's own JS may
  /// not have injected the form into the DOM yet when onPageFinished fires.
  Future<void> _attemptAutoFill() async {
    debugPrint('[WebLoginPage] Attempting auto-fill. hasCredentials=${widget.hasCredentials}, autoFillDone=$_autoFillDone, autoFilling=$_autoFilling');
    // Show why we might skip
    if (!widget.hasCredentials) {
      debugPrint('[WebLoginPage] Auto-fill skipped: no credentials in settings');
      if (mounted) {
        setState(() => _status = '自动填充已跳过：hasCredentials=false '
            '(user="${widget.autoFillUsername}", '
            'pwd=${widget.autoFillPassword == null ? "null" : "len=${widget.autoFillPassword!.length}"})');
      }
      return;
    }
    if (_autoFillDone || _autoFilling) {
      debugPrint('[WebLoginPage] Auto-fill skipped: done=$_autoFillDone, filling=$_autoFilling');
      if (mounted) {
        setState(() => _status = '自动填充已跳过：done=$_autoFillDone, filling=$_autoFilling');
      }
      return;
    }
    _autoFilling = true;

    if (mounted) {
      setState(() => _status = '正在尝试自动填充（user="${widget.autoFillUsername}"）…');
    }

    try {
      const maxAttempts = 15;

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        // Progressive delay: 300, 500, 700, ...
        await Future.delayed(Duration(milliseconds: 300 + attempt * 200));
        if (!mounted || _done || _autoFillDone) return;

        // Step 1: Diagnose current page state and try to activate the form.
        final diagResult = await _controller.runJavaScriptReturningResult('''
          (function() {
            var info = {};
            // Check what elements exist
            info.loginViewDiv = !!document.getElementById('loginViewDiv');
            info.pwdLoginDiv = !!document.getElementById('pwdLoginDiv');
            info.phoneLoginDiv = !!document.getElementById('phoneLoginDiv');
            info.showTabFn = (typeof showTabHeadAndDiv === 'function');

            // Count all username inputs
            var allUserInputs = document.querySelectorAll('input[name="username"]');
            info.totalUsernameInputs = allUserInputs.length;

            // Check how many are visible
            var visibleCount = 0;
            for (var i = 0; i < allUserInputs.length; i++) {
              var el = allUserInputs[i];
              if (el.offsetParent !== null || (el.offsetWidth > 0 && el.offsetHeight > 0)) {
                visibleCount++;
              }
            }
            info.visibleUsernameInputs = visibleCount;

            // Check #loginViewDiv content
            var lv = document.getElementById('loginViewDiv');
            info.loginViewDivChildCount = lv ? lv.children.length : -1;
            info.loginViewDivInnerLength = lv ? lv.innerHTML.length : -1;

            // Check #pwdLoginDiv display
            var pwd = document.getElementById('pwdLoginDiv');
            info.pwdLoginDivDisplay = pwd ? pwd.style.display : 'not-found';
            info.pwdLoginDivHasForm = pwd ? !!pwd.querySelector('form') : false;

            return JSON.stringify(info);
          })();
        ''');

        final diagStr = diagResult.toString().replaceAll('"', '').replaceAll("'", '');
        debugPrint('[WebLoginPage] Attempt $attempt diagnostics: $diagStr');

        if (mounted) {
          setState(() => _status = '诊断[$attempt]: $diagStr');
        }

        // Step 2: Try to activate the password login form.
        // Strategy A: Call the page's own showTabHeadAndDiv function
        // Strategy B: If that doesn't work, directly manipulate DOM visibility
        await _controller.runJavaScript('''
          (function() {
            var lv = document.getElementById('loginViewDiv');
            var hasVisibleInput = false;
            if (lv) {
              var inp = lv.querySelector('input[name="username"]');
              if (inp && (inp.offsetParent !== null || inp.offsetWidth > 0)) {
                hasVisibleInput = true;
              }
            }

            if (!hasVisibleInput) {
              // Strategy A: Use the page's own function
              if (typeof showTabHeadAndDiv === 'function') {
                try { showTabHeadAndDiv('userNameLogin', 1); } catch(e) {}
              }

              // Strategy B: If #loginViewDiv is still empty after a tick,
              // directly move the pwd form content there
              setTimeout(function() {
                var lv2 = document.getElementById('loginViewDiv');
                if (lv2 && lv2.children.length === 0) {
                  var pwdDiv = document.getElementById('pwdLoginDiv');
                  if (pwdDiv) {
                    // Clone the inner content into loginViewDiv
                    lv2.innerHTML = pwdDiv.innerHTML;
                  }
                }
              }, 100);

              // Strategy C: Also ensure pwdLoginDiv itself is not hidden
              // so inputs inside it can have offsetParent
              var pwdDiv = document.getElementById('pwdLoginDiv');
              if (pwdDiv && pwdDiv.style.display === 'none') {
                pwdDiv.style.display = '';
              }
            }
          })();
        ''');

        // Wait for DOM manipulation to complete
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted || _done || _autoFillDone) return;

        // Step 3: Now try to fill ALL username inputs (both visible and
        // invisible). We fill ALL of them because depending on the page state,
        // the "active" form might be in #loginViewDiv OR #pwdLoginDiv.
        final fillResult = await _controller.runJavaScriptReturningResult('''
          (function() {
            var filled = 0;
            var allInputs = document.querySelectorAll('input[name="username"]');
            for (var i = 0; i < allInputs.length; i++) {
              var el = allInputs[i];
              // Fill ALL of them — we don't know which one the page considers
              // the "active" form, and filling a hidden one does no harm.
              el.value = '${_escapeJs(widget.autoFillUsername ?? '')}';
              el.dispatchEvent(new Event('input',  {bubbles:true}));
              el.dispatchEvent(new Event('change', {bubbles:true}));
              el.dispatchEvent(new Event('blur',   {bubbles:true}));
              filled++;
            }

            // Also try #pwdFromId form's username specifically
            var pwdForm = document.getElementById('pwdFromId');
            if (pwdForm) {
              var uInput = pwdForm.querySelector('input[name="username"]');
              if (uInput && uInput.value !== '${_escapeJs(widget.autoFillUsername ?? '')}') {
                uInput.value = '${_escapeJs(widget.autoFillUsername ?? '')}';
                uInput.dispatchEvent(new Event('input',  {bubbles:true}));
                uInput.dispatchEvent(new Event('change', {bubbles:true}));
                filled++;
              }
            }

            return filled;
          })();
        ''');

        final filledCount =
            int.tryParse(fillResult.toString().replaceAll('"', '')) ?? 0;
        debugPrint('[WebLoginPage] Attempt $attempt filledCount: $filledCount');
        if (filledCount == 0) continue; // No inputs found yet — retry

        // Step 4: Fill password into ALL userPassword inputs.
        if (widget.autoFillPassword != null &&
            widget.autoFillPassword!.isNotEmpty) {
          await _controller.runJavaScript('''
            (function() {
              // Fill all userPassword inputs
              var inputs = document.querySelectorAll('input[name="userPassword"]');
              for (var i = 0; i < inputs.length; i++) {
                inputs[i].value = '${_escapeJs(widget.autoFillPassword!)}';
                inputs[i].dispatchEvent(new Event('input',  {bubbles:true}));
                inputs[i].dispatchEvent(new Event('change', {bubbles:true}));
              }

              // Also try by ID
              var pwdById = document.getElementById('password');
              if (pwdById && pwdById.type === 'password') {
                pwdById.value = '${_escapeJs(widget.autoFillPassword!)}';
                pwdById.dispatchEvent(new Event('input',  {bubbles:true}));
                pwdById.dispatchEvent(new Event('change', {bubbles:true}));
              }
            })();
          ''');
        }

        // Step 5: Trigger checkUserCaptcha
        await _controller.runJavaScript('''
          (function() {
            if (typeof checkUserCaptcha === 'function') {
              try { checkUserCaptcha(); } catch(e) {}
            }
          })();
        ''');

        _autoFillDone = true;
        if (mounted) {
          setState(() {
            _status = '已自动填充账号密码（填充了$filledCount个输入框）。';
          });
        }

        // Wait for checkUserCaptcha AJAX + captcha image load
        await Future.delayed(const Duration(milliseconds: 2500));
        if (!mounted || _done) return;

        if (widget.hasLlmConfig) {
          await _solveCaptchaAndLogin();
        } else {
          // If LLM is not configured, check if captcha is visible.
          // If no captcha is needed, we can auto-submit.
          final visResult = await _controller.runJavaScriptReturningResult('''
            (function() {
              var divs = document.querySelectorAll('#captchaDiv');
              for (var i = 0; i < divs.length; i++) {
                var cd = divs[i];
                if (cd.offsetWidth > 0 && cd.offsetHeight > 0) {
                  return 'visible';
                }
              }
              return 'hidden';
            })();
          ''');

          final isCaptchaVisible =
              visResult.toString().replaceAll('"', '') == 'visible';

          if (!isCaptchaVisible) {
            if (mounted) {
              setState(() => _status = '无需验证码，正在自动登录…');
            }
            await _clickLogin();
          } else {
            if (mounted) {
              setState(() => _status = '请手动输入验证码并点击登录。');
            }
          }
        }

        return; // Done — no more retries needed
      }

      // All attempts exhausted without finding the input
      if (mounted) {
        setState(() {
          _status = '自动填充未能找到输入框，请手动输入。';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '自动填充失败：$e';
        });
      }
    } finally {
      _autoFilling = false;
    }
  }

  // --------------- Captcha solving ---------------

  Future<void> _solveCaptchaAndLogin() async {
    debugPrint('[WebLoginPage] Solving captcha...');
    if (_captchaSolving || _done) return;
    _captchaSolving = true;

    try {
      // Check whether any captcha div is visible (not hidden)
      final visResult = await _controller.runJavaScriptReturningResult('''
        (function() {
          var divs = document.querySelectorAll('#captchaDiv');
          for (var i = 0; i < divs.length; i++) {
            var cd = divs[i];
            if (cd.offsetWidth > 0 && cd.offsetHeight > 0) {
              return 'visible';
            }
          }
          return 'hidden';
        })();
      ''');

      final isCaptchaVisible =
          visResult.toString().replaceAll('"', '') == 'visible';
      debugPrint('[WebLoginPage] Captcha visibility: $isCaptchaVisible');

      if (!isCaptchaVisible) {
        if (mounted) {
          setState(() => _status = '未检测到验证码要求，尝试直接登录…');
        }
        await _clickLogin();
        return;
      }

      if (mounted) {
        setState(() => _status = '正在获取验证码图片…');
      }

      final b64Result = await _controller.runJavaScriptReturningResult('''
        (function() {
          try {
            var imgs = document.querySelectorAll('#captchaImg, .captcha-img img');
            var visibleImg = null;
            for (var i = 0; i < imgs.length; i++) {
              var img = imgs[i];
              if (img.offsetWidth > 0 && img.offsetHeight > 0) {
                visibleImg = img;
                break;
              }
            }
            if (visibleImg && visibleImg.complete && (visibleImg.naturalWidth || visibleImg.width) > 0) {
              var canvas = document.createElement('canvas');
              canvas.width = visibleImg.naturalWidth || visibleImg.width;
              canvas.height = visibleImg.naturalHeight || visibleImg.height;
              var ctx = canvas.getContext('2d');
              ctx.drawImage(visibleImg, 0, 0);
              var dataUrl = canvas.toDataURL('image/png');
              return dataUrl.substring(dataUrl.indexOf(',') + 1);
            }
          } catch(e) {}

          try {
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '/authserver/getCaptcha.htl?' + Date.now(), false);
            xhr.overrideMimeType('text/plain; charset=x-user-defined');
            xhr.send(null);
            if (xhr.status === 200) {
              var bin = '';
              var text = xhr.responseText;
              for (var i = 0; i < text.length; i++) {
                bin += String.fromCharCode(text.charCodeAt(i) & 0xff);
              }
              return btoa(bin);
            }
            return 'ERROR: xhr status ' + xhr.status;
          } catch(e) { return 'ERROR: ' + e.toString(); }
        })();
      ''');

      String base64Image = b64Result.toString().replaceAll('"', '').trim();
      debugPrint('[WebLoginPage] Fetched captcha image base64 length: ${base64Image.length}');
      if (base64Image.isEmpty || base64Image == 'null') {
        throw Exception('无法获取验证码图片');
      }
      if (base64Image.startsWith('ERROR')) {
        throw Exception('获取验证码图片错误: $base64Image');
      }

      if (mounted) {
        setState(() => _status = '正在通过 LLM 识别验证码…');
      }

      // Decode and send to LLM
      final imageBytes = Uint8List.fromList(base64Decode(base64Image));
      final solver = CaptchaSolverService(
        baseUrl: widget.llmBaseUrl!,
        apiKey: widget.llmApiKey!,
        model: widget.llmModel ?? 'auto',
      );
      final captchaText = await solver.solveCaptcha(imageBytes);
      debugPrint('[WebLoginPage] Captcha solver result: $captchaText');

      if (!mounted || _done) return;
      setState(() => _status = '验证码识别结果：$captchaText，正在自动登录…');

      // Fill captcha field (all matching inputs)
      final c = _escapeJs(captchaText);
      await _controller.runJavaScript('''
        (function() {
          document.querySelectorAll('input[name="captcha"]').forEach(function(el) {
            el.value = '$c';
            el.dispatchEvent(new Event('input',  {bubbles:true}));
            el.dispatchEvent(new Event('change', {bubbles:true}));
          });
        })();
      ''');

      await Future.delayed(const Duration(milliseconds: 300));
      await _clickLogin();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '验证码自动识别失败：$e\n请手动输入验证码并登录。';
      });
    } finally {
      _captchaSolving = false;
    }
  }

  /// Clicks the login button by calling the page's own startLogin function.
  Future<void> _clickLogin() async {
    debugPrint('[WebLoginPage] Clicking login button');
    await _controller.runJavaScript('''
      (function() {
        var btns = document.querySelectorAll('#login_submit');
        for (var i = 0; i < btns.length; i++) {
          var btn = btns[i];
          if (btn.offsetWidth > 0 || btn.offsetHeight > 0) {
            if (typeof startLogin === 'function') {
              startLogin(btn);
            } else {
              btn.click();
            }
            return;
          }
        }
        // fallback: click any login_submit
        if (btns.length > 0) {
          if (typeof startLogin === 'function') {
            startLogin(btns[0]);
          } else {
            btns[0].click();
          }
        }
      })();
    ''');
    if (mounted) {
      setState(() => _status = '已自动提交登录，等待页面跳转…');
    }
  }

  // --------------- Session detection ---------------

  Future<void> _tryCompleteFromCookies(String url) async {
    if (_done || _checking) return;

    // 同一个 URL 不重复检查，避免认证链条里疯狂触发
    if (_lastCheckedUrl == url) return;
    _lastCheckedUrl = url;

    _checking = true;
    try {
      final session = await widget.authService.readSessionFromWebView(
        schoolType: widget.schoolType,
        usernameHint: widget.usernameHint,
      );

      if (!mounted || _done) return;

      if (session != null) {
        _done = true;
        Navigator.of(context).pop<SessionInfo>(session);
        return;
      }

      setState(() {
        _status = '尚未检测到有效登录态，请继续完成登录。';
      });
    } finally {
      _checking = false;
    }
  }

  Future<void> _manualComplete() async {
    if (_done || _checking) return;

    setState(() {
      _status = '正在手动检查登录态…';
    });

    _checking = true;
    try {
      final session = await widget.authService.readSessionFromWebView(
        schoolType: widget.schoolType,
        usernameHint: widget.usernameHint,
      );

      if (!mounted) return;

      if (session == null) {
        setState(() {
          _status = '还没有检测到有效登录态，请先在网页中完成登录。';
        });
        return;
      }

      _done = true;
      Navigator.of(context).pop<SessionInfo>(session);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.schoolType.shortLabel}网页登录'),
        actions: [
          IconButton(
            tooltip: '刷新页面',
            onPressed: _initializing ? null : _controller.reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '完成登录',
            onPressed: _initializing ? null : _manualComplete,
            icon: const Icon(Icons.check_circle_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              title: Text(_status),
              subtitle: _currentUrl.isEmpty
                  ? null
                  : Text(
                      _currentUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
          Expanded(
            child: _initializing
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
