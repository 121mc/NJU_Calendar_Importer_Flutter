import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Uses an OpenAI-compatible multimodal LLM to recognize captcha images.
class CaptchaSolverService {
  CaptchaSolverService({
    required this.baseUrl,
    required this.apiKey,
    this.model = 'auto',
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  /// Sends the captcha image bytes to the LLM and returns the recognized text.
  Future<String> solveCaptcha(Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);

    // Normalize baseUrl: remove trailing slash, ensure /chat/completions
    String endpoint = baseUrl.trimRight();
    if (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    if (!endpoint.endsWith('/chat/completions')) {
      final versionRegExp = RegExp(r'/v[0-9]+$');
      if (versionRegExp.hasMatch(endpoint)) {
        endpoint = '$endpoint/chat/completions';
      } else {
        endpoint = '$endpoint/v1/chat/completions';
      }
    }

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));

    print('[CaptchaSolverService] Sending request to endpoint: $endpoint');
    print('[CaptchaSolverService] Model: $model');

    try {
      final response = await dio.post<Map<String, dynamic>>(
        endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode({
          'model': model.isEmpty ? 'auto' : model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text':
                      '请识别这张验证码图片中的字符。验证码通常由4-6个字母或数字组成。'
                      '请只输出验证码字符本身，不要输出任何其他内容、标点或解释。',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,$base64Image',
                  },
                },
              ],
            },
          ],
          'max_tokens': 20,
          'temperature': 0.0,
        }),
      );

      print('[CaptchaSolverService] Response status: ${response.statusCode}');
      print('[CaptchaSolverService] Response data: ${response.data}');

      final data = response.data;
      if (data == null) {
        throw Exception('LLM 返回为空');
      }

      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('LLM 未返回有效结果');
      }

      final message = choices[0]['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String? ?? '';

      // Clean up: remove whitespace, quotes, and other non-alphanumeric chars
      final cleaned = content.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

      if (cleaned.isEmpty) {
        throw Exception('LLM 未能识别验证码内容');
      }

      return cleaned;
    } on DioException catch (e) {
      print('[CaptchaSolverService] DioException: $e');
      if (e.response != null) {
        print('[CaptchaSolverService] DioException Response status: ${e.response?.statusCode}');
        print('[CaptchaSolverService] DioException Response headers: ${e.response?.headers}');
        print('[CaptchaSolverService] DioException Response data: ${e.response?.data}');
      }
      rethrow;
    } catch (e) {
      print('[CaptchaSolverService] Unexpected error: $e');
      rethrow;
    }
  }
}
