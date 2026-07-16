import 'package:flutter/material.dart';

import '../app_snack_bar.dart';
import '../services/settings_service.dart';

/// A card dialog displayed in the center of the screen for configuring
/// auto-login credentials and LLM captcha recognition settings.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.settingsService});

  final SettingsService settingsService;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _llmBaseUrlController = TextEditingController();
  final _llmApiKeyController = TextEditingController();
  final _llmModelController = TextEditingController();

  String _captchaMode = 'ocr';
  bool _loading = true;
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await widget.settingsService.loadAll();
      if (!mounted) return;
      _usernameController.text = settings.username;
      _passwordController.text = settings.password;
      _llmBaseUrlController.text = settings.llmBaseUrl;
      _llmApiKeyController.text = settings.llmApiKey;
      _llmModelController.text = settings.llmModel;
      setState(() {
        _captchaMode = settings.captchaMode;
      });
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, '加载保存设置失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _saving = true;
    });
    try {
      await widget.settingsService.saveAll(AutoLoginSettings(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        llmBaseUrl: _llmBaseUrlController.text.trim(),
        llmApiKey: _llmApiKeyController.text.trim(),
        llmModel: _llmModelController.text.trim(),
        captchaMode: _captchaMode,
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, '保存失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _llmBaseUrlController.dispose();
    _llmApiKeyController.dispose();
    _llmModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '设置',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // --- Account Section ---
                    _buildSectionHeader(
                      icon: Icons.person_outline,
                      title: '账号信息',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: '学号 / 工号',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // --- Captcha Section ---
                    _buildSectionHeader(
                      icon: Icons.abc_outlined,
                      title: '验证码识别方式',
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'ocr',
                            label: Text('内置 OCR'),
                            icon: Icon(Icons.center_focus_strong_outlined),
                          ),
                          ButtonSegment<String>(
                            value: 'vlm',
                            label: Text('云端 VLM'),
                            icon: Icon(Icons.cloud_outlined),
                          ),
                        ],
                        selected: {_captchaMode},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            _captchaMode = newSelection.first;
                          });
                        },
                      ),
                    ),
                    if (_captchaMode == 'vlm') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _llmBaseUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Base URL',
                          prefixIcon: Icon(Icons.link),
                          hintText: 'https://api.openai.com',
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _llmApiKeyController,
                        obscureText: _obscureApiKey,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          prefixIcon: const Icon(Icons.key_outlined),
                          hintText: 'sk-...',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureApiKey = !_obscureApiKey;
                              });
                            },
                            icon: Icon(
                              _obscureApiKey
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _llmModelController,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          prefixIcon: Icon(Icons.psychology_outlined),
                          hintText: 'auto',
                        ),
                        keyboardType: TextInputType.text,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // --- Save ---
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveSettings,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('保存设置'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
