import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/login_models.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();
  static const _keySessionJson = 'nju_session_json';

  Future<void> saveSession(SessionInfo session) async {
    await _storage.write(
      key: _keySessionJson,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<SessionInfo?> readSession() async {
    final raw = await _storage.read(key: _keySessionJson);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SessionInfo.fromJson(decoded);
      }
      if (decoded is Map) {
        return SessionInfo.fromJson(Map<String, dynamic>.from(decoded));
      }
      return null;
    } catch (_) {
      // 兼容旧版存储失败场景：直接清掉旧缓存，避免一直报错
      await clearSession();
      return null;
    }
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _keySessionJson);

    // 顺手清理旧版本遗留键，防止脏数据干扰
    await _storage.delete(key: 'nju_username');
    await _storage.delete(key: 'nju_castgc');
    await _storage.delete(key: 'nju_school_type');
  }
}