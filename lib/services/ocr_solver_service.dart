import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

/// Built-in OCR captcha solver using ddddocr (common_old.onnx model)
class OcrSolverService {
  static OrtSession? _session;
  static List<String>? _charset;
  static bool _initializing = false;

  /// Initializes the ONNX session and loads the charset JSON
  static Future<void> init() async {
    if (_session != null && _charset != null) return;
    if (_initializing) {
      while (_initializing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    _initializing = true;
    try {
      final ort = OnnxRuntime();
      _session =
          await ort.createSessionFromAsset('assets/models/common_old.onnx');

      final charsetJsonStr =
          await rootBundle.loadString('assets/models/charset_old.json');
      final List<dynamic> charsetList = jsonDecode(charsetJsonStr);
      _charset = charsetList.cast<String>();
      debugPrint(
          '[OcrSolverService] Initialized successfully. Charset size: ${_charset?.length}');
    } catch (e) {
      debugPrint('[OcrSolverService] Initialization failed: $e');
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  /// Solves the captcha image bytes and returns the recognized text
  static Future<String> solve(Uint8List imageBytes) async {
    await init();
    final session = _session;
    final charset = _charset;
    if (session == null || charset == null) {
      throw Exception('OCR session or charset is not initialized');
    }

    // 1. Decode original image
    final originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      throw Exception('Failed to decode captcha image bytes');
    }

    final int targetHeight = 64;
    // 等比例计算新的宽度
    final int targetWidth =
        (originalImage.width * (targetHeight / originalImage.height)).toInt();

    // 2. 缩放图片，高度强行锁定为 64
    final resizedImage =
        img.copyResize(originalImage, width: targetWidth, height: targetHeight);

    List<double> inputTensorData = [];

    // 3. 遍历像素进行归一化
    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        final pixel = resizedImage.getPixel(x, y);

        // 转灰度 (0.299 R + 0.587 G + 0.114 B)
        double grayscale =
            (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114);

        // 关键归一化: (value / 255.0 - 0.5) / 0.5
        double normalized = (grayscale / 255.0 - 0.5) / 0.5;
        inputTensorData.add(normalized);
      }
    }

    // 4. 构建 Shape 传入 ONNX Session
    final shape = [1, 1, targetHeight, targetWidth];

    // 5. Create input tensor
    final inputTensor = await OrtValue.fromList(inputTensorData, shape);
    final inputs = {'input1': inputTensor};

    Map<String, OrtValue>? outputs;
    try {
      // 6. Run ONNX Session
      outputs = await session.run(inputs);

      final outputTensor = outputs['387'];
      if (outputTensor == null) {
        throw Exception('ONNX model output node (387) is not found');
      }

      // 7. Get output data
      final outputData = await outputTensor.asFlattenedList();

      final int numClasses = charset.length;
      final int seqLen = outputData.length ~/ numClasses;

      if (seqLen == 0) {
        return '';
      }

      // Find argmax for each time step in the sequence
      List<int> predictedIndices = [];
      for (int i = 0; i < seqLen; i++) {
        int argMax = 0;
        double maxVal = (outputData[i * numClasses] as num).toDouble();
        for (int c = 1; c < numClasses; c++) {
          double val = (outputData[i * numClasses + c] as num).toDouble();
          if (val > maxVal) {
            maxVal = val;
            argMax = c;
          }
        }
        predictedIndices.add(argMax);
      }

      // CTC Greedy Decoding (removing duplicates and blank tokens (0))
      List<int> decodedIndices = [];
      int? prevIdx;
      for (int idx in predictedIndices) {
        if (idx != prevIdx) {
          if (idx != 0) {
            decodedIndices.add(idx);
          }
          prevIdx = idx;
        }
      }

      // Map indices to characters
      final buffer = StringBuffer();
      for (int idx in decodedIndices) {
        if (idx >= 0 && idx < charset.length) {
          buffer.write(charset[idx]);
        }
      }

      final result = buffer.toString();
      // Clean up: remove whitespace and non-alphanumeric chars
      final cleaned = result.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      debugPrint('[OcrSolverService] Raw: $result, Cleaned: $cleaned');
      return cleaned;
    } finally {
      // Clean up tensors to prevent native memory leaks
      await inputTensor.dispose();
      if (outputs != null) {
        for (final tensor in outputs.values) {
          await tensor.dispose();
        }
      }
    }
  }

  /// Closes the session if needed
  static Future<void> close() async {
    if (_session != null) {
      await _session!.close();
      _session = null;
    }
  }
}
