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
                _autoFillDone = false;
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
    if (!widget.hasCredentials) {
      debugPrint('[WebLoginPage] Auto-fill skipped: no credentials in settings');
      if (mounted) {
        setState(() => _status = '自动填充已跳过：未配置账号密码');
      }
      return;
    }
    if (_autoFillDone || _autoFilling) {
      debugPrint('[WebLoginPage] Auto-fill skipped: done=$_autoFillDone, filling=$_autoFilling');
      return;
    }
    _autoFilling = true;
    _captchaSolving = false;

    if (mounted) {
      setState(() => _status = '正在执行自动登录流程…');
    }

    final startTime = DateTime.now();
    bool autofillSuccess = false;
    String? solvedCaptchaText;
    bool captchaRequired = false;

    // Task 1: Autofill username & password
    Future<bool> doAutofill() async {
      debugPrint('[WebLoginPage] Parallel: doAutofill started');
      try {
        const maxAttempts = 20; // 20 attempts * 50ms = 1.0s max
        for (int attempt = 0; attempt < maxAttempts; attempt++) {
          if (!mounted || _done) return false;

          // Check if username input is available in DOM
          final checkResult = await _controller.runJavaScriptReturningResult('''
            (function() {
              var allUserInputs = document.querySelectorAll('input[name="username"]');
              var visibleCount = 0;
              for (var i = 0; i < allUserInputs.length; i++) {
                var el = allUserInputs[i];
                if (el.offsetParent !== null || (el.offsetWidth > 0 && el.offsetHeight > 0)) {
                  visibleCount++;
                }
              }
              return visibleCount > 0;
            })();
          ''');

          final hasVisibleInput = checkResult.toString().trim() == 'true';
          if (!hasVisibleInput) {
            // Activate password login form
            await _controller.runJavaScript('''
              (function() {
                if (typeof showTabHeadAndDiv === 'function') {
                  try { showTabHeadAndDiv('userNameLogin', 1); } catch(e) {}
                }
                var pwdDiv = document.getElementById('pwdLoginDiv');
                if (pwdDiv && pwdDiv.style.display === 'none') {
                  pwdDiv.style.display = '';
                }
                var lv = document.getElementById('loginViewDiv');
                if (lv && lv.children.length === 0 && pwdDiv) {
                  lv.innerHTML = pwdDiv.innerHTML;
                }
              })();
            ''');
            await Future.delayed(const Duration(milliseconds: 50));
            continue;
          }

          // Visible input found! Fill username and password
          final fillResult = await _controller.runJavaScriptReturningResult('''
            (function() {
              var filled = 0;
              var uVal = '${_escapeJs(widget.autoFillUsername ?? '')}';
              var pVal = '${_escapeJs(widget.autoFillPassword ?? '')}';
              
              // Fill all username inputs
              document.querySelectorAll('input[name="username"]').forEach(function(el) {
                el.value = uVal;
                el.dispatchEvent(new Event('input',  {bubbles:true}));
                el.dispatchEvent(new Event('change', {bubbles:true}));
                el.dispatchEvent(new Event('blur',   {bubbles:true}));
                filled++;
              });

              // Fill all password inputs
              document.querySelectorAll('input[name="userPassword"]').forEach(function(el) {
                el.value = pVal;
                el.dispatchEvent(new Event('input',  {bubbles:true}));
                el.dispatchEvent(new Event('change', {bubbles:true}));
              });

              var pwdById = document.getElementById('password');
              if (pwdById && pwdById.type === 'password') {
                pwdById.value = pVal;
                pwdById.dispatchEvent(new Event('input',  {bubbles:true}));
                pwdById.dispatchEvent(new Event('change', {bubbles:true}));
              }

              // Trigger checkUserCaptcha
              if (typeof checkUserCaptcha === 'function') {
                try { checkUserCaptcha(); } catch(e) {}
              }

              return filled;
            })();
          ''');

          final count = int.tryParse(fillResult.toString().replaceAll('"', '').trim()) ?? 0;
          if (count > 0) {
            debugPrint('[WebLoginPage] Parallel: Autofill completed successfully. Filled $count inputs.');
            autofillSuccess = true;
            _autoFillDone = true;
            if (mounted) {
              setState(() {
                _status = '账号密码已自动填充。';
              });
            }
            return true;
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
      } catch (e) {
        debugPrint('[WebLoginPage] Error in doAutofill: $e');
      }
      return false;
    }

    // Task 2: Poll captcha and solve it with LLM
    Future<void> doCaptchaSolving() async {
      debugPrint('[WebLoginPage] Parallel: doCaptchaSolving started. hasLlmConfig=${widget.hasLlmConfig}');
      DateTime? autofillCompleteTime;
      const pollInterval = Duration(milliseconds: 50);
      final totalTimeout = widget.hasLlmConfig ? const Duration(seconds: 8) : const Duration(seconds: 2);

      while (mounted && !_done) {
        final now = DateTime.now();
        if (now.difference(startTime) > totalTimeout) {
          debugPrint('[WebLoginPage] Parallel captcha: timeout reached');
          break;
        }

        // Check if captcha is visible
        final visCheck = await _controller.runJavaScriptReturningResult('''
          (function() {
            var divs = document.querySelectorAll('#captchaDiv');
            var isVisible = false;
            for (var i = 0; i < divs.length; i++) {
              var cd = divs[i];
              if (cd.offsetWidth > 0 && cd.offsetHeight > 0) {
                isVisible = true;
                break;
              }
            }
            if (!isVisible) return 'hidden';

            // Try to extract image base64 if LLM is enabled
            if (${widget.hasLlmConfig}) {
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
                if (visibleImg) {
                  var src = visibleImg.src || '';
                  // Ensure the src has a query parameter (indicating it's the dynamic captcha, not a placeholder)
                  if (src.indexOf('?') === -1) {
                    return 'visible_loading';
                  }

                  // Check if this src has already been solved/processed in this session
                  if (window._lastCaptchaSrc === src) {
                    return 'already_processed';
                  }

                  if (visibleImg.complete && (visibleImg.naturalWidth || visibleImg.width) > 0) {
                    var canvas = document.createElement('canvas');
                    canvas.width = visibleImg.naturalWidth || visibleImg.width;
                    canvas.height = visibleImg.naturalHeight || visibleImg.height;
                    var ctx = canvas.getContext('2d');
                    ctx.drawImage(visibleImg, 0, 0);
                    var dataUrl = canvas.toDataURL('image/png');
                    
                    // Mark as processed
                    window._lastCaptchaSrc = src;
                    
                    return 'base64:' + dataUrl.substring(dataUrl.indexOf(',') + 1);
                  }
                }
              } catch(e) {}
              return 'visible_loading';
            }
            return 'visible';
          })();
        ''');

        final statusStr = visCheck.toString().replaceAll('"', '').trim();
        if (statusStr.startsWith('base64:')) {
          captchaRequired = true;
          final base64Image = statusStr.substring(7);
          debugPrint('[WebLoginPage] Parallel captcha: Image loaded, base64 length = ${base64Image.length}');
          
          if (mounted) {
            setState(() {
              _status = '检测到验证码，正在使用 LLM 识别…';
              _captchaSolving = true;
            });
          }

          try {
            final imageBytes = Uint8List.fromList(base64Decode(base64Image));
            final solver = CaptchaSolverService(
              baseUrl: widget.llmBaseUrl!,
              apiKey: widget.llmApiKey!,
              model: widget.llmModel ?? 'auto',
            );
            solvedCaptchaText = await solver.solveCaptcha(imageBytes);
            debugPrint('[WebLoginPage] Parallel captcha: Solved text = $solvedCaptchaText');
            break; // Solved!
          } catch (e) {
            debugPrint('[WebLoginPage] Error during LLM captcha solving: $e');
            if (mounted) {
              setState(() {
                _status = '验证码识别出错：$e，请手动输入。';
              });
            }
            break; // Stop polling on solver error
          } finally {
            _captchaSolving = false;
          }
        } else if (statusStr == 'already_processed') {
          debugPrint('[WebLoginPage] Parallel captcha: already processed this image src');
          break;
        } else if (statusStr == 'visible_loading') {
          captchaRequired = true;
          // Captcha is visible but image is not loaded yet, keep polling
          debugPrint('[WebLoginPage] Parallel captcha: Visible but image loading...');
        } else if (statusStr == 'visible') {
          // Captcha is visible but LLM is not enabled
          captchaRequired = true;
          debugPrint('[WebLoginPage] Parallel captcha: Visible but LLM config is disabled');
          break;
        } else {
          // Captcha is hidden
          if (_autoFillDone) {
            autofillCompleteTime ??= DateTime.now();
            final waitDuration = widget.hasLlmConfig 
                ? const Duration(milliseconds: 1000) 
                : const Duration(milliseconds: 500);
            if (DateTime.now().difference(autofillCompleteTime) > waitDuration) {
              debugPrint('[WebLoginPage] Parallel captcha: No captcha required after wait post-autofill.');
              break;
            }
          }
        }

        await Future.delayed(pollInterval);
      }
    }

    try {
      // Run both in parallel
      await Future.wait([
        doAutofill(),
        doCaptchaSolving(),
      ]);

      if (!mounted || _done) return;

      if (autofillSuccess) {
        if (captchaRequired) {
          if (solvedCaptchaText != null && solvedCaptchaText!.isNotEmpty) {
            if (mounted) {
              setState(() {
                _status = '已识别验证码 ($solvedCaptchaText)，正在自动登录…';
              });
            }
            final c = _escapeJs(solvedCaptchaText!);
            await _controller.runJavaScript('''
              (function() {
                document.querySelectorAll('input[name="captcha"]').forEach(function(el) {
                  el.value = '$c';
                  el.dispatchEvent(new Event('input',  {bubbles:true}));
                  el.dispatchEvent(new Event('change', {bubbles:true}));
                });
              })();
            ''');
            await Future.delayed(const Duration(milliseconds: 150));
            await _clickLogin();
          } else {
            if (mounted) {
              setState(() {
                _status = '请手动输入验证码并点击登录。';
              });
            }
          }
        } else {
          // No captcha required
          if (mounted) {
            setState(() {
              _status = '无需验证码，正在自动登录…';
            });
          }
          await _clickLogin();
        }
      } else {
        if (mounted) {
          setState(() {
            _status = '自动填充账号密码失败，请手动输入。';
          });
        }
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
              trailing: _captchaSolving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : null,
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
