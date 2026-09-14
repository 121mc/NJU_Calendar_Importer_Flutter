import 'package:dio/dio.dart';

class HolidayRule {
  HolidayRule(this.holiday, this.makeup);
  final DateTime holiday;
  final DateTime? makeup;

  static DateTime parseDate(dynamic value) {
    final text = '$value';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      throw const FormatException('调休日期格式错误');
    }
    final date = DateTime.parse(text);
    if (date.toIso8601String().substring(0, 10) != text) {
      throw const FormatException('调休日期无效');
    }
    return date;
  }
}

class HolidayService {
  HolidayService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://calendar.121mc.net',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ));
  final Dio _dio;

  Future<List<HolidayRule>> fetch(String semesterId) async {
    try {
      final response = await _dio.get<dynamic>('/api/holidays',
          queryParameters: {'semester': semesterId});
      final data = response.data;
      if (data is! Map ||
          data['semester'] != semesterId ||
          data['rules'] is! List) {
        throw const FormatException('调休响应格式错误');
      }
      final rules = <HolidayRule>[];
      final dates = <DateTime>{};
      for (final row in data['rules'] as List) {
        final holiday = HolidayRule.parseDate(row['holiday']);
        final makeup =
            row['makeup'] == null ? null : HolidayRule.parseDate(row['makeup']);
        if (!dates.add(holiday) || (makeup != null && !dates.add(makeup))) {
          throw const FormatException('调休日期重复或冲突');
        }
        rules.add(HolidayRule(holiday, makeup));
      }
      return rules;
    } catch (_) {
      throw Exception('调休信息获取失败，请稍后重试，未导入可能不完整的课表。');
    }
  }
}
