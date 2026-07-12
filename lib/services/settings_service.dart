import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages user-configurable settings for auto-login and LLM captcha recognition.
class SettingsService {
  static const _storage = FlutterSecureStorage();

  static const _keyUsername = 'settings_username';
  static const _keyPassword = 'settings_password';
  static const _keyLlmBaseUrl = 'settings_llm_base_url';
  static const _keyLlmApiKey = 'settings_llm_api_key';
  static const _keyLlmModel = 'settings_llm_model';

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

  Future<String> getLlmBaseUrl() async {
    try {
      return await _storage.read(key: _keyLlmBaseUrl) ?? '';
    } catch (_) {
      try {
        await _storage.delete(key: _keyLlmBaseUrl);
      } catch (_) {}
      return '';
    }
  }

  Future<String> getLlmApiKey() async {
    try {
      return await _storage.read(key: _keyLlmApiKey) ?? '';
    } catch (_) {
      try {
        await _storage.delete(key: _keyLlmApiKey);
      } catch (_) {}
      return '';
    }
  }

  Future<String> getLlmModel() async {
    try {
      return await _storage.read(key: _keyLlmModel) ?? 'auto';
    } catch (_) {
      try {
        await _storage.delete(key: _keyLlmModel);
      } catch (_) {}
      return 'auto';
    }
  }

  Future<void> setUsername(String value) async =>
      await _storage.write(key: _keyUsername, value: value);

  Future<void> setPassword(String value) async =>
      await _storage.write(key: _keyPassword, value: value);

  Future<void> setLlmBaseUrl(String value) async =>
      await _storage.write(key: _keyLlmBaseUrl, value: value);

  Future<void> setLlmApiKey(String value) async =>
      await _storage.write(key: _keyLlmApiKey, value: value);

  Future<void> setLlmModel(String value) async =>
      await _storage.write(key: _keyLlmModel, value: value);

  Future<AutoLoginSettings> loadAll() async {
    final results = await Future.wait([
      getUsername(),
      getPassword(),
      getLlmBaseUrl(),
      getLlmApiKey(),
      getLlmModel(),
    ]);
    return AutoLoginSettings(
      username: results[0],
      password: results[1],
      llmBaseUrl: results[2],
      llmApiKey: results[3],
      llmModel: results[4],
    );
  }

  Future<void> saveAll(AutoLoginSettings settings) async {
    await Future.wait([
      setUsername(settings.username),
      setPassword(settings.password),
      setLlmBaseUrl(settings.llmBaseUrl),
      setLlmApiKey(settings.llmApiKey),
      setLlmModel(settings.llmModel),
    ]);
  }
}

class AutoLoginSettings {
  const AutoLoginSettings({
    this.username = '',
    this.password = '',
    this.llmBaseUrl = '',
    this.llmApiKey = '',
    this.llmModel = 'auto',
  });

  final String username;
  final String password;
  final String llmBaseUrl;
  final String llmApiKey;
  final String llmModel;

  bool get hasCredentials => username.isNotEmpty || password.isNotEmpty;
  bool get hasLlmConfig => llmBaseUrl.isNotEmpty && llmApiKey.isNotEmpty;
}
