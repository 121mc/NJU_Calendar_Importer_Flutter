import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import '../models/login_models.dart';
import '../models/school_type.dart';
import '../services/auth_service.dart';

enum AutomaticLoginFailureType {
  network,
  invalidCredentials,
  sliderFailed,
  other,
}

class AutomaticLoginFailure {
  const AutomaticLoginFailure(this.type, [this.detail = '']);

  final AutomaticLoginFailureType type;
  final String detail;
}

/// Runs the same NJU unified-auth automation used by Auto_Auth_Login inside a
/// WebView. The content script is bundled with app-specific failure handling;
/// this page also provides compatibility implementations for Chrome APIs.
class WebLoginPage extends StatefulWidget {
  const WebLoginPage({
    super.key,
    required this.schoolType,
    required this.authService,
    required this.usernameHint,
    this.autoFillUsername,
    this.autoFillPassword,
    this.backgroundLogin = false,
    this.automaticLogin = true,
    this.embedded = false,
    this.onSession,
    this.onAutomaticLoginFailure,
  });

  final SchoolType schoolType;
  final AuthService authService;
  final String usernameHint;
  final String? autoFillUsername;
  final String? autoFillPassword;

  /// Keeps the official page active behind a progress overlay during login.
  final bool backgroundLogin;

  /// Fills credentials, submits the form, and solves a slider challenge.
  ///
  /// When false, credentials are filled but slider handling and submission
  /// are left entirely to the user.
  final bool automaticLogin;

  /// Builds only the WebView so it can run transparently inside the home page.
  final bool embedded;

  final ValueChanged<SessionInfo>? onSession;
  final ValueChanged<AutomaticLoginFailure>? onAutomaticLoginFailure;

  bool get hasCredentials =>
      autoFillUsername?.isNotEmpty == true &&
      autoFillPassword?.isNotEmpty == true;

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  static const _bridgeName = 'NjuAutoLoginBridge';
  static const _automationAsset = 'assets/scripts/auto_auth_login.js';
  static const _trajectoryAsset = 'assets/recordings/3.json';
  static const _automaticLoginStallTimeout = Duration(seconds: 12);
  static const _maxAutomaticLoginInjections = 2;

  late final WebViewController _controller;

  bool _initializing = true;
  bool _checking = false;
  bool _done = false;
  bool _autoFillDone = false;
  bool _autoFilling = false;
  bool _failureReported = false;
  late bool _showWebContent;

  int _progress = 0;
  String _status = '正在准备网页登录环境…';
  String _currentUrl = '';
  String _lastCheckedUrl = '';
  String? _automationSource;
  String? _trajectoryDataUrl;
  Timer? _automaticLoginTimeout;
  Timer? _automaticLoginStallTimer;
  Timer? _pageLoadTimeout;
  int _automaticLoginInjectionCount = 0;

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

  bool _isAuthPage(String url) =>
      url.contains('authserver.nju.edu.cn/authserver/login');

  @override
  void initState() {
    super.initState();
    _showWebContent = !widget.backgroundLogin;
    if (widget.automaticLogin && widget.onAutomaticLoginFailure != null) {
      _automaticLoginTimeout = Timer(const Duration(minutes: 2), () {
        _reportAutomaticLoginFailure(
          const AutomaticLoginFailure(
            AutomaticLoginFailureType.other,
            '自动登录等待超时',
          ),
        );
      });
    }
    _init();
  }

  Future<void> _init() async {
    if (widget.automaticLogin) {
      try {
        final assets = await Future.wait([
          rootBundle.loadString(_automationAsset),
          rootBundle.loadString(_trajectoryAsset),
        ]);
        _automationSource = assets[0];
        _trajectoryDataUrl =
            'data:application/json;base64,${base64Encode(utf8.encode(assets[1]))}';
      } catch (error) {
        if (mounted) {
          setState(() {
            _status = '加载自动登录脚本失败：$error';
            _showWebContent = true;
          });
        }
      }
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _bridgeName,
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            _startPageLoadTimeout();
            setState(() {
              _currentUrl = url;
              if (_isAuthPage(url)) {
                _status = '统一认证页面加载中…';
                _autoFillDone = false;
                _autoFilling = false;
              } else if (_isTargetArea(url)) {
                _automaticLoginStallTimer?.cancel();
                _status = '已进入目标系统，正在读取登录状态…';
              } else {
                _status = '页面跳转中…';
              }
            });
          },
          onPageFinished: (url) async {
            if (!mounted || _done) return;
            _pageLoadTimeout?.cancel();
            setState(() => _currentUrl = url);

            if (_isAuthPage(url)) {
              if (widget.automaticLogin) {
                await _injectAutoLogin();
              } else {
                await _fillCredentialsOnly();
              }
            } else if (_isTargetArea(url)) {
              await _tryCompleteFromCookies(url);
            }
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) return;
            setState(() {
              _status = '网页加载失败：${error.description}';
              _showWebContent = true;
            });
            if (widget.automaticLogin) {
              _reportAutomaticLoginFailure(
                AutomaticLoginFailure(
                  AutomaticLoginFailureType.network,
                  error.description,
                ),
              );
            }
          },
        ),
      );

    if (mounted) setState(() => _initializing = false);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      await widget.authService.clearWebViewCookies().timeout(
            const Duration(seconds: 3),
          );
    } catch (error) {
      debugPrint('[WebLoginPage] Failed to clear WebView cookies: $error');
    }

    if (mounted) {
      await _controller.loadRequest(Uri.parse(_loginEntryUrl));
    }
  }

  Future<void> _injectAutoLogin() async {
    if (_autoFillDone || _autoFilling || _done || _failureReported) {
      return;
    }
    if (!widget.hasCredentials) {
      if (mounted) {
        setState(() {
          _status = '未配置账号密码，请手动登录。';
          _showWebContent = true;
        });
      }
      return;
    }

    final automationSource = _automationSource;
    final trajectoryDataUrl = _trajectoryDataUrl;
    if (automationSource == null || trajectoryDataUrl == null) {
      if (mounted) {
        setState(() {
          _status = '自动登录资源不可用，请手动登录。';
          _showWebContent = true;
        });
      }
      _reportAutomaticLoginFailure(
        const AutomaticLoginFailure(
          AutomaticLoginFailureType.other,
          '自动登录资源不可用',
        ),
      );
      return;
    }

    if (_automaticLoginInjectionCount >= _maxAutomaticLoginInjections) {
      _reportAutomaticLoginFailure(
        const AutomaticLoginFailure(
          AutomaticLoginFailureType.other,
          '统一认证页面在提交后重置，自动重试仍未恢复',
        ),
      );
      return;
    }

    // A rejected username/password submission reloads the unified-auth page.
    // Persisting this marker in sessionStorage lets the new page distinguish
    // that reload from the initial visit instead of starting another slider
    // attempt from scratch.
    try {
      final result = await _controller.runJavaScriptReturningResult('''
(function () {
  const key = 'nju_slider_login_submitted';
  const submitted = sessionStorage.getItem(key) === '1';
  if (submitted) sessionStorage.removeItem(key);
  return submitted;
})();
''');
      final submitted = result == true ||
          result.toString().replaceAll('"', '').trim().toLowerCase() == 'true';
      if (submitted) {
        if (mounted) {
          setState(() {
            _status = '账号或密码有误。';
            _showWebContent = true;
          });
        }
        _reportAutomaticLoginFailure(
          const AutomaticLoginFailure(
            AutomaticLoginFailureType.invalidCredentials,
            'NJU_INVALID_CREDENTIALS',
          ),
        );
        return;
      }
    } catch (error) {
      debugPrint(
        '[WebLoginPage] Failed to inspect previous login submission: $error',
      );
    }

    _autoFilling = true;
    _automaticLoginInjectionCount += 1;
    if (mounted) setState(() => _status = '正在启动完整自动登录流程…');

    try {
      final bootstrap = _buildChromeCompatibilityLayer(trajectoryDataUrl);
      await _controller.runJavaScript('$bootstrap\n$automationSource');
      _autoFillDone = true;
      _armAutomaticLoginStallTimer();
    } catch (error) {
      debugPrint('[WebLoginPage] Failed to inject automation: $error');
      if (mounted) {
        setState(() {
          _status = '启动自动登录失败：$error';
          _showWebContent = true;
        });
      }
      _reportAutomaticLoginFailure(
        AutomaticLoginFailure(
          AutomaticLoginFailureType.other,
          error.toString(),
        ),
      );
    } finally {
      _autoFilling = false;
    }
  }

  Future<void> _fillCredentialsOnly() async {
    if (_autoFillDone || _autoFilling || _done) return;
    if (!widget.hasCredentials) {
      if (mounted) setState(() => _status = '请手动输入账号密码并完成登录。');
      return;
    }

    _autoFilling = true;
    if (mounted) setState(() => _status = '正在自动填写学号和密码…');

    final username = jsonEncode(widget.autoFillUsername);
    final password = jsonEncode(widget.autoFillPassword);
    try {
      await _controller.runJavaScript('''
(async function () {
  if (window.__njuCredentialsOnlyInjected) return;
  window.__njuCredentialsOnlyInjected = true;

  const sleep = function (ms) {
    return new Promise(function (resolve) { setTimeout(resolve, ms); });
  };
  const setNativeValue = function (element, value) {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype,
      'value'
    ).set;
    element.removeAttribute('readonly');
    element.removeAttribute('disabled');
    setter.call(element, value);
    element.dispatchEvent(new Event('input', {bubbles: true}));
    element.dispatchEvent(new Event('change', {bubbles: true}));
  };
  const notify = function (action, detail) {
    window.$_bridgeName.postMessage(JSON.stringify({
      id: 'credentials-only',
      message: {action: action, detail: detail || ''}
    }));
  };

  try {
    const deadline = Date.now() + 10000;
    let loginView = null;
    let usernameField = null;
    while (Date.now() < deadline && !usernameField) {
      loginView = document.querySelector('#loginViewDiv');
      usernameField = loginView && (
        loginView.querySelector('.m-account #username') ||
        loginView.querySelector('#username')
      );
      if (!usernameField) {
        const passwordTab = document.querySelector('#userNameLogin_a');
        if (passwordTab) passwordTab.click();
        await sleep(100);
      }
    }

    if (!loginView || !usernameField) {
      throw new Error('找不到统一认证账号输入框');
    }
    const passwordField =
      loginView.querySelector('.m-account #password') ||
      loginView.querySelector('#password');
    if (!passwordField) throw new Error('找不到统一认证密码输入框');

    setNativeValue(usernameField, $username);
    setNativeValue(passwordField, $password);
    usernameField.dispatchEvent(new Event('focusout', {bubbles: true}));
    usernameField.dispatchEvent(new Event('blur', {bubbles: true}));
    notify('credentialsOnlyComplete');
  } catch (error) {
    notify('credentialsOnlyFailed', error && error.message || String(error));
  }
})();
''');
      _autoFillDone = true;
    } catch (error) {
      if (mounted) setState(() => _status = '自动填写失败，请手动输入：$error');
    } finally {
      _autoFilling = false;
    }
  }

  String _buildChromeCompatibilityLayer(String trajectoryDataUrl) {
    final settingsJson = jsonEncode({
      'nju_auto_login_pending': true,
      'nju_auth_auto_login': true,
      'nju_page_auto_login': true,
      'nju_username': widget.autoFillUsername,
      'nju_password': widget.autoFillPassword,
      'nju_debug_mode': false,
    });
    final trajectoryJson = jsonEncode(trajectoryDataUrl);

    return '''
(function () {
  if (window.__njuAutoAuthInjected) return;
  window.__njuAutoAuthInjected = true;

  const settings = $settingsJson;
  const trajectoryUrl = $trajectoryJson;
  const pending = new Map();
  let nextRequestId = 1;
  const nativeFetch = window.fetch.bind(window);

  window.fetch = function (resource, options) {
    const url = typeof resource === 'string' ? resource : resource && resource.url;
    if (url === trajectoryUrl) {
      const encoded = trajectoryUrl.substring(trajectoryUrl.indexOf(',') + 1);
      return Promise.resolve(new Response(atob(encoded), {
        status: 200,
        headers: {'Content-Type': 'application/json'}
      }));
    }
    return nativeFetch(resource, options);
  };

  window.__njuFlutterResolve = function (id, response, error) {
    const request = pending.get(id);
    if (!request) return;
    pending.delete(id);
    if (error) request.reject(new Error(String(error)));
    else request.resolve(response);
  };

  const runtime = {
    lastError: null,
    getURL: function (path) {
      return path === 'recordings/3.json' ? trajectoryUrl : path;
    },
    sendMessage: function (message, callback) {
      const id = nextRequestId++;
      const promise = new Promise(function (resolve, reject) {
        pending.set(id, {resolve: resolve, reject: reject});
        window.$_bridgeName.postMessage(JSON.stringify({
          id: id,
          message: message
        }));
      });
      if (typeof callback === 'function') {
        promise.then(function (response) {
          runtime.lastError = null;
          callback(response);
        }).catch(function (error) {
          runtime.lastError = {message: String(error && error.message || error)};
          callback(undefined);
          runtime.lastError = null;
        });
      }
      return promise;
    }
  };

  window.chrome = window.chrome || {};
  window.chrome.runtime = runtime;
  window.chrome.storage = {
    local: {
      get: async function (keys) {
        if (keys == null) return Object.assign({}, settings);
        const requested = typeof keys === 'string' ? [keys] : keys;
        if (Array.isArray(requested)) {
          const result = {};
          requested.forEach(function (key) {
            if (Object.prototype.hasOwnProperty.call(settings, key)) {
              result[key] = settings[key];
            }
          });
          return result;
        }
        const result = Object.assign({}, requested);
        Object.keys(requested).forEach(function (key) {
          if (Object.prototype.hasOwnProperty.call(settings, key)) {
            result[key] = settings[key];
          }
        });
        return result;
      }
    }
  };
})();
''';
  }

  Future<void> _handleBridgeMessage(JavaScriptMessage bridgeMessage) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(bridgeMessage.message);
    } catch (error) {
      debugPrint('[WebLoginPage] Invalid bridge message: $error');
      return;
    }
    if (decoded is! Map) return;

    final id = decoded['id'];
    final rawMessage = decoded['message'];
    if (id == null || rawMessage is! Map) return;
    final message = Map<String, dynamic>.from(rawMessage);
    final action = message['action']?.toString() ?? '';

    try {
      switch (action) {
        case 'contentLog':
          _handleAutomationLog(
            message['msg']?.toString() ?? '',
            message['level']?.toString() ?? 'info',
          );
          await _replyToBridge(id, const <String, dynamic>{});
          break;
        case 'loginComplete':
          _handleLoginCompleteMessage(message);
          await _replyToBridge(id, const <String, dynamic>{});
          break;
        case 'recordSliderCaptchaDebug':
          // Debug recording is deliberately disabled by the compatibility
          // settings, but the extension API remains complete.
          await _replyToBridge(id, const <String, dynamic>{'success': true});
          break;
        case 'credentialsOnlyComplete':
          if (mounted) {
            setState(() {
              _status = '学号和密码已填写，请手动完成验证码并提交。';
            });
          }
          break;
        case 'credentialsOnlyFailed':
          if (mounted) {
            final detail = message['detail']?.toString() ?? '';
            setState(() {
              _status =
                  detail.isEmpty ? '自动填写失败，请手动输入。' : '自动填写失败，请手动输入：$detail';
            });
          }
          break;
        default:
          await _replyToBridge(id, const <String, dynamic>{});
          break;
      }
    } catch (error, stackTrace) {
      debugPrint('[WebLoginPage] Bridge action $action failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _replyToBridge(id, null, error: error.toString());
    }
  }

  void _handleAutomationLog(String message, String level) {
    debugPrint('[NJU Auto Auth][$level] $message');
    if (!mounted || message.isEmpty) return;
    _armAutomaticLoginStallTimer();
    setState(() {
      _status = message;
      if (level == 'error') _showWebContent = true;
    });
  }

  void _handleLoginCompleteMessage(Map<String, dynamic> message) {
    if (!mounted) return;
    final success = message['success'] == true;
    final detail = message['message']?.toString() ?? '';
    setState(() {
      if (success) {
        _status = '统一认证成功，正在进入课表系统…';
      } else {
        _status = detail.isEmpty ? '自动登录失败，请手动处理。' : '自动登录失败：$detail';
        _showWebContent = true;
      }
    });
    if (!success) {
      final type = detail.contains('NJU_INVALID_CREDENTIALS')
          ? AutomaticLoginFailureType.invalidCredentials
          : detail.contains('NJU_SLIDER_FAILED_TWICE')
              ? AutomaticLoginFailureType.sliderFailed
              : AutomaticLoginFailureType.other;
      _reportAutomaticLoginFailure(AutomaticLoginFailure(type, detail));
    }
  }

  void _startPageLoadTimeout() {
    if (!widget.automaticLogin ||
        widget.onAutomaticLoginFailure == null ||
        _failureReported) {
      return;
    }
    _pageLoadTimeout?.cancel();
    _pageLoadTimeout = Timer(const Duration(seconds: 5), () {
      _reportAutomaticLoginFailure(
        const AutomaticLoginFailure(
          AutomaticLoginFailureType.network,
          '学校网页加载超过 5 秒',
        ),
      );
    });
  }

  void _reportAutomaticLoginFailure(AutomaticLoginFailure failure) {
    if (_failureReported || !widget.automaticLogin) return;
    _failureReported = true;
    _automaticLoginTimeout?.cancel();
    _automaticLoginStallTimer?.cancel();
    _pageLoadTimeout?.cancel();
    widget.onAutomaticLoginFailure?.call(failure);
  }

  void _armAutomaticLoginStallTimer() {
    if (!widget.automaticLogin || _failureReported || _done || !mounted) {
      return;
    }
    _automaticLoginStallTimer?.cancel();
    _automaticLoginStallTimer = Timer(_automaticLoginStallTimeout, () {
      if (!mounted || _done || _failureReported || !_isAuthPage(_currentUrl)) {
        return;
      }
      debugPrint(
        '[WebLoginPage] Automatic login stalled on the auth page; retrying injection.',
      );
      _autoFillDone = false;
      _autoFilling = false;
      unawaited(_injectAutoLogin());
    });
  }

  Future<void> _replyToBridge(
    dynamic id,
    Object? response, {
    String? error,
  }) async {
    if (_done) return;
    final script = 'window.__njuFlutterResolve && '
        'window.__njuFlutterResolve(${jsonEncode(id)}, '
        '${jsonEncode(response)}, ${jsonEncode(error)});';
    await _controller.runJavaScript(script);
  }

  Future<void> _tryCompleteFromCookies(String url) async {
    if (_done || _checking || _lastCheckedUrl == url) return;
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
        _finishWithSession(session);
      } else {
        setState(() => _status = '登录成功，正在等待课表系统会话建立…');
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _manualComplete() async {
    if (_done || _checking) return;
    setState(() => _status = '正在检查登录状态…');
    _checking = true;
    try {
      final session = await widget.authService.readSessionFromWebView(
        schoolType: widget.schoolType,
        usernameHint: widget.usernameHint,
      );
      if (!mounted) return;
      if (session == null) {
        setState(() => _status = '尚未检测到有效登录状态，请先完成登录。');
        return;
      }
      _done = true;
      _finishWithSession(session);
    } finally {
      _checking = false;
    }
  }

  void _finishWithSession(SessionInfo session) {
    _automaticLoginTimeout?.cancel();
    _automaticLoginStallTimer?.cancel();
    _pageLoadTimeout?.cancel();
    final callback = widget.onSession;
    if (callback != null) {
      callback(session);
      return;
    }
    Navigator.of(context).pop<SessionInfo>(session);
  }

  @override
  void dispose() {
    _automaticLoginTimeout?.cancel();
    _automaticLoginStallTimer?.cancel();
    _pageLoadTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _initializing
          ? const SizedBox.expand()
          : WebViewWidget(controller: _controller);
    }

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
            tooltip: '检查登录状态',
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
                : Stack(
                    children: [
                      Positioned.fill(
                        child: WebViewWidget(controller: _controller),
                      ),
                      if (!_showWebContent)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.surface,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.sync_lock_outlined,
                                      size: 52,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(height: 20),
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 20),
                                    Text(
                                      _status,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextButton(
                                      onPressed: () {
                                        setState(() => _showWebContent = true);
                                      },
                                      child: const Text('需要手动处理？显示官方登录页'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
