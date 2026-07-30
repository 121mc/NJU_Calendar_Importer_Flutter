import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the credentials used by the automatic NJU login flow.
class SettingsService {
  static const _storage = FlutterSecureStorage();

  static const _keyUsername = 'settings_username';
  static const _keyPassword = 'settings_password';
  static const _legacyCloudKeys = [
    'settings_llm_base_url',
    'settings_llm_api_key',
    'settings_llm_model',
    'settings_captcha_mode',
  ];

  Future<String> getUsername() async {
    try {
      return await _storage.read(key: _keyUsername) ?? '';
    } catch (_) {
      try {
        await _storage.delete(key: _keyUsername);
      } catch (_) {}
      return '';
    }
  }

  Future<String> getPassword() async {
    try {
      return await _storage.read(key: _keyPassword) ?? '';
    } catch (_) {
      try {
        await _storage.delete(key: _keyPassword);
      } catch (_) {}
      return '';
    }
  }

  Future<void> setUsername(String value) async =>
      await _storage.write(key: _keyUsername, value: value);

  Future<void> setPassword(String value) async =>
      await _storage.write(key: _keyPassword, value: value);

  Future<AutoLoginSettings> loadAll() async {
    final results = await Future.wait([
      getUsername(),
      getPassword(),
    ]);
    return AutoLoginSettings(
      username: results[0],
      password: results[1],
    );
  }

  Future<void> saveAll(AutoLoginSettings settings) async {
    await Future.wait([
      setUsername(settings.username),
      setPassword(settings.password),
    ]);
    await _removeLegacyCloudSettings();
  }

  Future<void> _removeLegacyCloudSettings() async {
    for (final key in _legacyCloudKeys) {
      try {
        await _storage.delete(key: key);
      } catch (_) {
        // A storage failure should not prevent automatic login from working.
      }
    }
  }
}

class AutoLoginSettings {
  const AutoLoginSettings({
    this.username = '',
    this.password = '',
  });

  final String username;
  final String password;

  bool get hasCredentials => username.isNotEmpty && password.isNotEmpty;
}
