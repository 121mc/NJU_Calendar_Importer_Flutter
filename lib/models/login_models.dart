import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import 'school_type.dart';

class LoginPreparation {
  LoginPreparation({
    required this.dio,
    required this.cookieJar,
    required this.hiddenFields,
    required this.captchaBytes,
  });

  final Dio dio;
  final CookieJar cookieJar;
  final Map<String, String> hiddenFields;
  final Uint8List captchaBytes;
}

class StoredCookie {
  const StoredCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    required this.secure,
    required this.httpOnly,
    this.expiresIso8601,
  });

  final String name;
  final String value;
  final String? domain;
  final String? path;
  final bool secure;
  final bool httpOnly;
  final String? expiresIso8601;

  factory StoredCookie.fromIoCookie(Cookie cookie) {
    return StoredCookie(
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain,
      path: cookie.path,
      secure: cookie.secure,
      httpOnly: cookie.httpOnly,
      expiresIso8601: cookie.expires?.toIso8601String(),
    );
  }

  Cookie toIoCookie() {
    final cookie = Cookie(name, value);
    if (domain != null && domain!.isNotEmpty) {
      cookie.domain = domain!;
    }
    if (path != null && path!.isNotEmpty) {
      cookie.path = path!;
    }
    cookie.secure = secure;
    cookie.httpOnly = httpOnly;
    if (expiresIso8601 != null && expiresIso8601!.isNotEmpty) {
      cookie.expires = DateTime.tryParse(expiresIso8601!);
    }
    return cookie;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'secure': secure,
        'httpOnly': httpOnly,
        'expiresIso8601': expiresIso8601,
      };

  factory StoredCookie.fromJson(Map<String, dynamic> json) {
    return StoredCookie(
      name: json['name'] as String? ?? '',
      value: json['value'] as String? ?? '',
      domain: json['domain'] as String?,
      path: json['path'] as String?,
      secure: json['secure'] as bool? ?? false,
      httpOnly: json['httpOnly'] as bool? ?? false,
      expiresIso8601: json['expiresIso8601'] as String?,
    );
  }
}

class SessionInfo {
  const SessionInfo({
    required this.username,
    required this.schoolType,
    required this.cookiesByBaseUrl,
  });

  final String username;
  final SchoolType schoolType;
  final Map<String, List<StoredCookie>> cookiesByBaseUrl;

  bool get hasEhallAppCookies {
    return (cookiesByBaseUrl['https://ehallapp.nju.edu.cn'] ?? const [])
        .isNotEmpty;
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'schoolType': schoolType.name,
        'cookiesByBaseUrl': cookiesByBaseUrl.map(
          (key, value) => MapEntry(
            key,
            value.map((cookie) => cookie.toJson()).toList(),
          ),
        ),
      };

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    final rawCookies = json['cookiesByBaseUrl'];
    if (rawCookies is Map) {
      return SessionInfo(
        username: json['username'] as String? ?? '已登录用户',
        schoolType: SchoolType.values.byName(
          json['schoolType'] as String? ?? SchoolType.undergrad.name,
        ),
        cookiesByBaseUrl: rawCookies.map(
          (key, value) => MapEntry(
            '$key',
            ((value as List?) ?? const [])
                .map((item) => StoredCookie.fromJson(
                    Map<String, dynamic>.from(item as Map)))
                .where((cookie) => cookie.name.isNotEmpty)
                .toList(),
          ),
        ),
      );
    }

    // 兼容旧版只保存 CASTGC 的缓存格式。
    final oldCastgc = json['castgc'] as String?;
    final schoolType = SchoolType.values.byName(
      json['schoolType'] as String? ?? SchoolType.undergrad.name,
    );
    if (oldCastgc != null && oldCastgc.isNotEmpty) {
      return SessionInfo(
        username: json['username'] as String? ?? '已登录用户',
        schoolType: schoolType,
        cookiesByBaseUrl: {
          'https://authserver.nju.edu.cn': [
            StoredCookie(
              name: 'CASTGC',
              value: oldCastgc,
              domain: 'authserver.nju.edu.cn',
              path: '/',
              secure: true,
              httpOnly: true,
            ),
          ],
        },
      );
    }

    throw const FormatException('无法解析 SessionInfo。');
  }
}
