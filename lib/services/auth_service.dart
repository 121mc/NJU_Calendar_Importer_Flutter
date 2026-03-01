import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:webview_cookie_manager_flutter/webview_cookie_manager.dart';

import '../models/login_models.dart';
import '../models/school_type.dart';
import 'storage_service.dart';

class AuthService {
  AuthService(this._storageService);

  final StorageService _storageService;

  static const loginUrl = 'https://authserver.nju.edu.cn/authserver/login';
  static const _authBaseUrl = 'https://authserver.nju.edu.cn';
  static const _ehallBaseUrl = 'https://ehall.nju.edu.cn';
  static const _ehallAppBaseUrl = 'https://ehallapp.nju.edu.cn';

  static const _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  Future<SessionInfo?> restoreSession() => _storageService.readSession();

  Future<void> clearSession() => _storageService.clearSession();

  Future<void> clearWebViewCookies() async {
    final cookieManager = WebviewCookieManager();
    await cookieManager.clearCookies();
  }

  String _appIndexUrlFor(SchoolType schoolType) {
    switch (schoolType) {
      case SchoolType.undergrad:
        return 'https://ehallapp.nju.edu.cn/jwapp/sys/wdkb/*default/index.do';
      case SchoolType.graduate:
        return 'https://ehallapp.nju.edu.cn/gsapp/sys/wdkbapp/*default/index.do';
    }
  }

  Future<SessionInfo> captureSessionFromWebView({
    required SchoolType schoolType,
    String? usernameHint,
  }) async {
    final cookieManager = WebviewCookieManager();

    final authCookies = await _collectCookies(cookieManager, [
      _authBaseUrl,
      loginUrl,
    ]);
    final ehallCookies = await _collectCookies(cookieManager, [
      _ehallBaseUrl,
      schoolType.appShowUrl,
    ]);
    final ehallAppCookies = await _collectCookies(cookieManager, [
      _ehallAppBaseUrl,
      _appIndexUrlFor(schoolType),
    ]);

    if (authCookies.isEmpty) {
      throw Exception('未从 WebView 读取到统一认证 cookie。');
    }
    if (ehallAppCookies.isEmpty) {
      throw Exception('未从 WebView 读取到 ehallapp cookie。请在登录后继续等待，直到真正进入课表应用首页。');
    }

    final session = SessionInfo(
      username: (usernameHint == null || usernameHint.trim().isEmpty)
          ? '已登录用户'
          : usernameHint.trim(),
      schoolType: schoolType,
      cookiesByBaseUrl: {
        _authBaseUrl: authCookies.map(StoredCookie.fromIoCookie).toList(),
        _ehallBaseUrl: ehallCookies.map(StoredCookie.fromIoCookie).toList(),
        _ehallAppBaseUrl:
            ehallAppCookies.map(StoredCookie.fromIoCookie).toList(),
      },
    );
    await _storageService.saveSession(session);
    return session;
  }

  Future<SessionInfo?> readSessionFromWebView({
    required SchoolType schoolType,
    String? usernameHint,
  }) async {
    try {
      return await captureSessionFromWebView(
        schoolType: schoolType,
        usernameHint: usernameHint,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Dio> buildAuthenticatedDio(SessionInfo session) async {
    if (!session.hasEhallAppCookies) {
      throw Exception('当前保存的是旧版登录态，缺少 ehallapp cookie。请先“退出并清空登录态”，再重新通过网页登录。');
    }

    final cookieJar = CookieJar();
    final dio = Dio(
      BaseOptions(
        headers: {
          'User-Agent': _browserUserAgent,
          'Accept': 'application/json, text/plain, */*',
        },
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 25),
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ),
    )..interceptors.add(CookieManager(cookieJar));

    _seedCookies(
      cookieJar,
      _authBaseUrl,
      session.cookiesByBaseUrl[_authBaseUrl] ?? const [],
    );
    _seedCookies(
      cookieJar,
      _ehallBaseUrl,
      session.cookiesByBaseUrl[_ehallBaseUrl] ?? const [],
    );
    _seedCookies(
      cookieJar,
      _ehallAppBaseUrl,
      session.cookiesByBaseUrl[_ehallAppBaseUrl] ?? const [],
    );

    await dio.get<String>(
      _appIndexUrlFor(session.schoolType),
      options: Options(responseType: ResponseType.plain),
    );

    return dio;
  }

  Future<List<Cookie>> _collectCookies(
    WebviewCookieManager cookieManager,
    List<String> urls,
  ) async {
    final byKey = <String, Cookie>{};
    for (final url in urls) {
      final cookies = await cookieManager.getCookies(url);
      for (final cookie in cookies) {
        final key =
            '${cookie.name}|${cookie.domain}|${cookie.path}|${cookie.secure}|${cookie.httpOnly}';
        byKey[key] = cookie;
      }
    }
    return byKey.values.toList();
  }

  void _seedCookies(
    CookieJar cookieJar,
    String baseUrl,
    List<StoredCookie> cookies,
  ) {
    if (cookies.isEmpty) return;
    cookieJar.saveFromResponse(
      Uri.parse(baseUrl),
      cookies.map((cookie) => cookie.toIoCookie()).toList(),
    );
  }
}
