import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/login_models.dart';
import '../models/school_type.dart';
import '../services/auth_service.dart';

class WebLoginPage extends StatefulWidget {
  const WebLoginPage({
    super.key,
    required this.schoolType,
    required this.authService,
    required this.usernameHint,
  });

  final SchoolType schoolType;
  final AuthService authService;
  final String usernameHint;

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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
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
            if (!mounted || _done) return;

            setState(() {
              _currentUrl = url;
            });

            // 只在真正进入目标系统后再检查，不在 auth 页面反复检查
            if (_isTargetArea(url)) {
              await _tryCompleteFromCookies(url);
            } else if (_isAuthPage(url)) {
              if (mounted) {
                setState(() {
                  _status = '请继续在统一认证页面中完成登录。';
                });
              }
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _initializing
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _initializing ? null : _manualComplete,
                      icon: const Icon(Icons.login),
                      label: const Text('我已完成登录'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
