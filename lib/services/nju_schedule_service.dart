import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/login_models.dart';
import '../models/nju_course.dart';
import '../models/school_type.dart';
import 'auth_service.dart';

class NjuScheduleService {
  NjuScheduleService(this._authService);

  final AuthService _authService;

  Future<ScheduleBundle> fetchCurrentSemesterSchedule(
    SessionInfo session, {
    bool includeFinalExams = true,
  }) async {
    final dio = await _authService.buildAuthenticatedDio(session);
    switch (session.schoolType) {
      case SchoolType.undergrad:
        return _fetchUndergrad(dio, includeFinalExams: includeFinalExams);
      case SchoolType.graduate:
        return _fetchGraduate(dio);
    }
  }

  Future<ScheduleBundle> _fetchUndergrad(
    Dio dio, {
    required bool includeFinalExams,
  }) async {
    final currentSemesterResp = await dio.get<dynamic>(
      'https://ehallapp.nju.edu.cn/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do',
    );
    final currentSemesterData = _ensureJsonMap(
      currentSemesterResp.data,
      apiName: '本科-当前学期接口',
    );
    final semesterRows = _readRows(
      currentSemesterData,
      ['datas', 'dqxnxq', 'rows'],
    );
    if (semesterRows.isEmpty) {
      throw Exception('本科-当前学期接口未返回 rows。可能是登录态失效，或接口结构发生变化。');
    }
    final semesterRow = semesterRows.first;
    final semesterId = '${semesterRow['DM']}';
    final semesterName = '${semesterRow['MC'] ?? semesterId}';

    final allSemesterResp = await dio.get<dynamic>(
      'https://ehallapp.nju.edu.cn/jwapp/sys/wdkb/modules/jshkcb/cxjcs.do',
    );
    final allSemesterData = _ensureJsonMap(
      allSemesterResp.data,
      apiName: '本科-学期列表接口',
    );
    final allSemesterRows = _readRows(
      allSemesterData,
      ['datas', 'cxjcs', 'rows'],
    );
    final semesterMeta = allSemesterRows.firstWhere(
      (row) => '${row['XN']}-${row['XQ']}' == semesterId,
      orElse: () => throw Exception('未找到当前学期的起始日期。'),
    );
    final semesterStart =
        _parseDateOnly('${semesterMeta['XQKSRQ']}'.substring(0, 10));

    final coursesResp = await dio.post<dynamic>(
      'https://ehallapp.nju.edu.cn/jwapp/sys/wdkb/modules/xskcb/cxxszhxqkb.do',
      data: {
        'XNXQDM': semesterId,
        'pageSize': '9999',
        'pageNumber': '1',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final coursesData = _ensureJsonMap(
      coursesResp.data,
      apiName: '本科-课表接口',
    );
    final courseRows = _readRows(
      coursesData,
      ['datas', 'cxxszhxqkb', 'rows'],
    );

    final events = <NjuCourseEvent>[];
    for (final row in courseRows) {
      events.addAll(_mapUndergradCourse(row, semesterStart));
    }

    var examCount = 0;
    if (includeFinalExams) {
      final examsResp = await dio.post<dynamic>(
        'https://ehallapp.nju.edu.cn/jwapp/sys/studentWdksapApp/WdksapController/cxxsksap.do',
        data: {
          'requestParamStr': jsonEncode({
            'XNXQDM': semesterId,
            '*order': '-KSRQ,-KSSJMS',
          }),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final examsData = _ensureJsonMap(
        examsResp.data,
        apiName: '本科-考试接口',
      );
      final examRows = _readRows(
        examsData,
        ['datas', 'cxxsksap', 'rows'],
      );
      examCount = examRows.length;
      for (final row in examRows) {
        final event = _mapUndergradExam(row);
        if (event != null) {
          events.add(event);
        }
      }
    }

    events.sort((a, b) => a.start.compareTo(b.start));

    return ScheduleBundle(
      semesterName: semesterName,
      events: events,
      courseCount: courseRows.length,
      examCount: examCount,
    );
  }

  Future<ScheduleBundle> _fetchGraduate(Dio dio) async {
    final semesterResp = await dio.post<dynamic>(
      'https://ehallapp.nju.edu.cn/gsapp/sys/wdkbapp/modules/xskcb/kfdxnxqcx.do',
    );
    final semesterData = _ensureJsonMap(
      semesterResp.data,
      apiName: '研究生-学期接口',
    );
    final semesterRows = _readRows(
      semesterData,
      ['datas', 'kfdxnxqcx', 'rows'],
    );
    final cutoff = DateTime.now().add(const Duration(days: 14));
    final eligible = semesterRows.where((row) {
      final start = _parseDateTime('${row['KBKFRQ']}');
      return !start.isAfter(cutoff);
    }).toList();
    if (eligible.isEmpty) {
      throw Exception('研究生课表接口没有返回可用学期。');
    }
    eligible.sort(
      (a, b) => _parseDateTime('${a['KBKFRQ']}')
          .compareTo(_parseDateTime('${b['KBKFRQ']}')),
    );
    final currentSemester = eligible.last;
    final semesterId = '${currentSemester['XNXQDM']}';
    final semesterName = '${currentSemester['XNXQDM_DISPLAY'] ?? semesterId}';
    final semesterStart = _parseDateTime('${currentSemester['KBKFRQ']}');

    final coursesResp = await dio.post<dynamic>(
      'https://ehallapp.nju.edu.cn/gsapp/sys/wdkbapp/modules/xskcb/xspkjgcx.do',
      data: {'XNXQDM': semesterId, 'XH': ''},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final coursesData = _ensureJsonMap(
      coursesResp.data,
      apiName: '研究生-排课结果接口',
    );
    final rawRows = _readRows(coursesData, ['datas', 'xspkjgcx', 'rows']);
    final mergedRows = _mergeGraduateRows(rawRows);

    final courseListResp = await dio.post<dynamic>(
      'https://ehallapp.nju.edu.cn/gsapp/sys/wdkbapp/modules/xskcb/xsjxrwcx.do?_=1765716674587',
      data: {
        'XNXQDM': semesterId,
        'XH': '',
        'pageNumber': '1',
        'pageSize': '100',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final courseListData = _ensureJsonMap(
      courseListResp.data,
      apiName: '研究生-教学任务接口',
    );
    final courseListRows = _readRows(
      courseListData,
      ['datas', 'xsjxrwcx', 'rows'],
    );
    final courseIdToCampus = <String, String>{
      for (final row in courseListRows)
        '${row['KCDM']}': '${row['XQDM_DISPLAY'] ?? ''}',
    };

    final events = <NjuCourseEvent>[];
    for (final row in mergedRows) {
      events.addAll(
        _mapGraduateCourse(
          row,
          semesterStart,
          courseIdToCampus['${row['KCDM']}'],
        ),
      );
    }
    events.sort((a, b) => a.start.compareTo(b.start));

    return ScheduleBundle(
      semesterName: semesterName,
      events: events,
      courseCount: mergedRows.length,
      examCount: 0,
    );
  }

  Map<String, dynamic> _ensureJsonMap(
    dynamic raw, {
    required String apiName,
  }) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }

    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    if (raw is String) {
      final text = raw.trim();

      if (text.isEmpty) {
        throw Exception('$apiName 返回空字符串。');
      }

      final lower = text.toLowerCase();
      if (lower.startsWith('<!doctype html') ||
          lower.startsWith('<html') ||
          lower.contains('<body') ||
          lower.contains('<head')) {
        final preview = text.replaceAll('\n', ' ').replaceAll('\r', ' ');
        throw Exception(
          '$apiName 返回的是 HTML 页面，不是 JSON。通常表示登录态失效、未正确跳转到目标应用，或接口被重定向。前120字符：${preview.substring(0, preview.length > 120 ? 120 : preview.length)}',
        );
      }

      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        throw Exception('$apiName 返回的 JSON 根节点不是对象，而是 ${decoded.runtimeType}。');
      } catch (e) {
        final preview = text.replaceAll('\n', ' ').replaceAll('\r', ' ');
        throw Exception(
          '$apiName 返回的是字符串，但无法解析成 JSON。前120字符：${preview.substring(0, preview.length > 120 ? 120 : preview.length)}；原始错误：$e',
        );
      }
    }

    throw Exception('$apiName 返回了不支持的类型：${raw.runtimeType}');
  }

  List<Map<String, dynamic>> _mergeGraduateRows(List<Map<String, dynamic>> rows) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final key = '${row['BJMC'] ?? ''}';
      grouped.putIfAbsent(key, () => []).add(Map<String, dynamic>.from(row));
    }

    final merged = <Map<String, dynamic>>[];
    for (final group in grouped.values) {
      group.sort((a, b) {
        final xqCompare = _toInt(a['XQ']).compareTo(_toInt(b['XQ']));
        if (xqCompare != 0) return xqCompare;
        return _toInt(a['KSJCDM']).compareTo(_toInt(b['KSJCDM']));
      });

      for (final row in group) {
        if (merged.isEmpty) {
          merged.add(Map<String, dynamic>.from(row));
          continue;
        }
        final last = merged.last;
        final canMerge =
            '${last['BJMC']}' == '${row['BJMC']}' &&
            _toInt(last['XQ']) == _toInt(row['XQ']) &&
            '${last['ZCBH']}' == '${row['ZCBH']}' &&
            '${last['JASMC']}' == '${row['JASMC']}' &&
            '${last['KCDM']}' == '${row['KCDM']}' &&
            _toInt(last['JSJCDM']) + 1 == _toInt(row['KSJCDM']);

        if (canMerge) {
          last['JSJCDM'] = row['JSJCDM'];
          last['JSSJ'] = row['JSSJ'];
        } else {
          merged.add(Map<String, dynamic>.from(row));
        }
      }
    }

    return merged;
  }

  List<NjuCourseEvent> _mapUndergradCourse(
    Map<String, dynamic> row,
    DateTime semesterStart,
  ) {
    final ksjc = _toInt(row['KSJC']);
    final jsjc = _toInt(row['JSJC']);
    if (ksjc <= 0 || jsjc <= 0) return const [];

    const startTimes = [
      [8, 0],
      [9, 0],
      [10, 10],
      [11, 10],
      [14, 0],
      [15, 0],
      [16, 10],
      [17, 10],
      [18, 30],
      [19, 30],
      [20, 30],
      [21, 30],
      [22, 30],
    ];
    const endTimes = [
      [8, 50],
      [9, 50],
      [11, 0],
      [12, 0],
      [14, 50],
      [15, 50],
      [17, 0],
      [18, 0],
      [19, 20],
      [20, 20],
      [21, 20],
      [22, 20],
      [23, 20],
    ];

    if (ksjc > startTimes.length || jsjc > endTimes.length) {
      return const [];
    }

    final weekday = _toInt(row['SKXQ']);
    final weekBitmap = '${row['SKZC'] ?? ''}';
    final title = '${row['KCM'] ?? '未命名课程'}';
    final location = _stringOrNull(row['JASMC']);
    final teacher = _stringOrNull(row['JSHS']) ?? _stringOrNull(row['SKJS']);
    final className = _stringOrNull(row['JXBMC']);
    final studentClasses = _stringOrNull(row['SKBJ']);
    final campus = _stringOrNull(row['XXXQDM_DISPLAY']);

    final events = <NjuCourseEvent>[];
    for (var i = 0; i < weekBitmap.length; i++) {
      if (weekBitmap[i] != '1') continue;
      final date = semesterStart.add(Duration(days: i * 7 + weekday - 1));
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        startTimes[ksjc - 1][0],
        startTimes[ksjc - 1][1],
      );
      final end = DateTime(
        date.year,
        date.month,
        date.day,
        endTimes[jsjc - 1][0],
        endTimes[jsjc - 1][1],
      );
      final importKey = _buildImportKey(
        'undergrad',
        title,
        start,
        end,
        location,
      );
      final description = _buildDescription(
        importKey: importKey,
        schoolLabel: '南京大学本科生',
        teacher: teacher,
        className: className,
        campus: campus,
        extraLines: [
          if (studentClasses != null && studentClasses.isNotEmpty) '上课班级：$studentClasses',
        ],
      );
      events.add(
        NjuCourseEvent(
          title: title,
          start: start,
          end: end,
          location: location,
          description: description,
          importKey: importKey,
        ),
      );
    }
    return events;
  }

  NjuCourseEvent? _mapUndergradExam(Map<String, dynamic> row) {
    final dateText = _stringOrNull(row['KSRQ']);
    final startText = _stringOrNull(row['KSKSSJ']);
    final endText = _stringOrNull(row['KSJSSJ']);
    if (dateText == null || startText == null || endText == null) {
      return null;
    }
    final date = _parseDateOnly(dateText);
    final startParts = startText.split(':');
    final endParts = endText.split(':');
    if (startParts.length != 2 || endParts.length != 2) return null;

    final start = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(startParts[0]),
      int.parse(startParts[1]),
    );
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(endParts[0]),
      int.parse(endParts[1]),
    );

    final title = '${row['KCM'] ?? '未命名课程'}期末考试';
    final location = _stringOrNull(row['JASMC']);
    final teacher = _stringOrNull(row['ZJJSXM']);
    final importKey = _buildImportKey('undergrad_exam', title, start, end, location);

    return NjuCourseEvent(
      title: title,
      start: start,
      end: end,
      location: location,
      importKey: importKey,
      description: _buildDescription(
        importKey: importKey,
        schoolLabel: '南京大学本科生',
        teacher: teacher,
        className: null,
        campus: null,
        extraLines: const ['类型：期末考试'],
      ),
    );
  }

  List<NjuCourseEvent> _mapGraduateCourse(
    Map<String, dynamic> row,
    DateTime semesterStart,
    String? campus,
  ) {
    final startTime = _hhmmToHourMinute(_toInt(row['KSSJ']));
    final endTime = _hhmmToHourMinute(_toInt(row['JSSJ']));
    final weekBitmap = '${row['ZCBH'] ?? ''}';
    final weekday = _toInt(row['XQ']);
    final title = '${row['KCMC'] ?? row['BJMC'] ?? '未命名课程'}';
    final location = _stringOrNull(row['JASMC']);
    final teacher = _stringOrNull(row['JSXM']);
    final remark = _stringOrNull(row['XKBZ']);

    final events = <NjuCourseEvent>[];
    for (var i = 0; i < weekBitmap.length; i++) {
      if (weekBitmap[i] != '1') continue;
      final date = semesterStart.add(Duration(days: i * 7 + weekday - 1));
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        startTime.$1,
        startTime.$2,
      );
      final end = DateTime(
        date.year,
        date.month,
        date.day,
        endTime.$1,
        endTime.$2,
      );
      final importKey = _buildImportKey(
        'graduate',
        title,
        start,
        end,
        location,
      );
      final description = _buildDescription(
        importKey: importKey,
        schoolLabel: '南京大学研究生',
        teacher: teacher,
        className: _stringOrNull(row['BJMC']),
        campus: campus,
        extraLines: [
          if (remark != null && remark.isNotEmpty) '选课备注：$remark',
        ],
      );
      events.add(
        NjuCourseEvent(
          title: title,
          start: start,
          end: end,
          location: location,
          description: description,
          importKey: importKey,
        ),
      );
    }
    return events;
  }

  String _buildImportKey(
    String prefix,
    String title,
    DateTime start,
    DateTime end,
    String? location,
  ) {
    final raw =
        '$prefix|$title|${start.toIso8601String()}|${end.toIso8601String()}|${location ?? ''}';
    return sha1.convert(utf8.encode(raw)).toString();
  }

  String _buildDescription({
    required String importKey,
    required String schoolLabel,
    required String? teacher,
    required String? className,
    required String? campus,
    required List<String> extraLines,
  }) {
    return [
      '[NJU_SCHEDULE_IMPORT]',
      'import_key=$importKey',
      '学校：$schoolLabel',
      if (teacher != null && teacher.isNotEmpty) '教师：$teacher',
      if (className != null && className.isNotEmpty) '班级：$className',
      if (campus != null && campus.isNotEmpty) '校区：$campus',
      ...extraLines,
    ].join('\n');
  }

  List<Map<String, dynamic>> _readRows(
    Map<String, dynamic>? data,
    List<String> path,
  ) {
    dynamic current = data;
    for (final key in path) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else {
        current = null;
        break;
      }
    }
    if (current is List) {
      return current.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  int _toInt(dynamic value) => int.tryParse('$value') ?? 0;

  String? _stringOrNull(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  DateTime _parseDateOnly(String text) {
    final clean = text.trim().substring(0, 10);
    return DateTime.parse(clean);
  }

  DateTime _parseDateTime(String text) {
    return DateTime.parse(text.replaceFirst(' ', 'T'));
  }

  (int, int) _hhmmToHourMinute(int value) {
    final hour = value ~/ 100;
    final minute = value % 100;
    return (hour, minute);
  }
}