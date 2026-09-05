import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/login_models.dart';
import '../models/nju_course.dart';
import '../models/nju_semester.dart';
import '../models/school_type.dart';
import 'auth_service.dart';
import 'calendar_import_metadata.dart';

class UndergradSemesterOptions {
  const UndergradSemesterOptions({
    required this.currentSemesterId,
    required this.currentSemesterName,
    required this.semesters,
  });

  final String currentSemesterId;
  final String currentSemesterName;
  final List<NjuSemester> semesters;

  NjuSemester? get matchingCurrentSemester {
    for (final semester in semesters) {
      if (semester.id == currentSemesterId) {
        return semester;
      }
    }
    return null;
  }

  bool get hasMatchingCurrentSemester => matchingCurrentSemester != null;

  NjuSemester? get currentSemester {
    final matching = matchingCurrentSemester;
    if (matching != null) {
      return matching;
    }
    return semesters.isEmpty ? null : semesters.first;
  }
}

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
        return _fetchUndergrad(
          dio,
          studentId: session.username,
          includeFinalExams: includeFinalExams,
        );
      case SchoolType.graduate:
        return _fetchGraduate(dio, studentId: session.username);
    }
  }

  Future<UndergradSemesterOptions> fetchUndergradSemesterOptions(
    SessionInfo session,
  ) async {
    final dio = await _authService.buildAuthenticatedDio(session);
    final current = await _fetchUndergradCurrentSemester(dio);
    final semesters = await _fetchUndergradSemesterList(
      dio,
      currentSemesterId: current.$1,
    );

    if (semesters.isEmpty) {
      throw Exception('本科-学期列表接口未返回可用学期。');
    }

    return UndergradSemesterOptions(
      currentSemesterId: current.$1,
      currentSemesterName: current.$2,
      semesters: semesters,
    );
  }

  Future<ScheduleBundle> fetchUndergradScheduleForSemester(
    SessionInfo session, {
    required String semesterId,
    required String semesterName,
    required DateTime semesterStart,
    required DateTime semesterEnd,
    bool includeFinalExams = true,
  }) async {
    final dio = await _authService.buildAuthenticatedDio(session);
    return _fetchUndergradForSemester(
      dio,
      semesterId: semesterId,
      semesterName: semesterName,
      semesterStart: semesterStart,
      semesterEnd: semesterEnd,
      studentId: session.username,
      includeFinalExams: includeFinalExams,
    );
  }

  Future<ScheduleBundle> _fetchUndergrad(
    Dio dio, {
    required String studentId,
    required bool includeFinalExams,
  }) async {
    final current = await _fetchUndergradCurrentSemester(dio);
    final allSemesterRows = await _fetchUndergradSemesterRows(dio);
    final semesterRow = allSemesterRows.firstWhere(
      (row) => _undergradSemesterIdFromRow(row) == current.$1,
      orElse: () => throw Exception('未找到当前学期的起始日期。'),
    );
    final semester = NjuSemester.fromUndergradRow(
      semesterRow,
      currentSemesterId: current.$1,
    );

    return _fetchUndergradForSemester(
      dio,
      semesterId: semester.id,
      semesterName: current.$2,
      semesterStart: semester.start,
      semesterEnd: semester.end,
      studentId: studentId,
      includeFinalExams: includeFinalExams,
    );
  }

  Future<(String, String)> _fetchUndergradCurrentSemester(Dio dio) async {
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
    return NjuSemester.currentUndergradIdAndName(semesterRows.first);
  }

  Future<List<NjuSemester>> _fetchUndergradSemesterList(
    Dio dio, {
    required String? currentSemesterId,
  }) async {
    final allSemesterRows = await _fetchUndergradSemesterRows(dio);
    return allSemesterRows
        .map(
          (row) => NjuSemester.fromUndergradRow(
            row,
            currentSemesterId: currentSemesterId,
          ),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchUndergradSemesterRows(
      Dio dio) async {
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
    return allSemesterRows;
  }

  String _undergradSemesterIdFromRow(Map<String, dynamic> row) {
    final year = '${row['XN'] ?? ''}'.trim();
    final term = '${row['XQ'] ?? ''}'.trim();
    return '$year-$term';
  }

  Future<ScheduleBundle> _fetchUndergradForSemester(
    Dio dio, {
    required String semesterId,
    required String semesterName,
    required DateTime semesterStart,
    required DateTime semesterEnd,
    required String studentId,
    required bool includeFinalExams,
  }) async {
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

    // “其他信息” belongs to the course-list model used by the visible table,
    // not to the structured weekly-schedule model above.
    final courseListResp = await dio.post<dynamic>(
      'https://ehallapp.nju.edu.cn/jwapp/sys/wdkb/modules/xskcb/cxxskclb.do',
      data: {
        'XNXQDM': semesterId,
        'pageSize': '9999',
        'pageNumber': '1',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final courseListData = _ensureJsonMap(
      courseListResp.data,
      apiName: '本科-课程列表接口',
    );
    final courseListRows = _readRows(
      courseListData,
      ['datas', 'cxxskclb', 'rows'],
    );

    var examRows = <Map<String, dynamic>>[];
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
      examRows = _readRows(
        examsData,
        ['datas', 'cxxsksap', 'rows'],
      );
    }

    final metadataById = <String, Map<String, dynamic>>{};
    final scheduleRowsById = <String, List<Map<String, dynamic>>>{};
    final listRowsById = <String, List<Map<String, dynamic>>>{};
    final examRowsById = <String, List<Map<String, dynamic>>>{};

    for (final scheduleRow in courseRows) {
      final metadata =
          _mergeUndergradCourseMetadata(scheduleRow, courseListRows);
      final courseId = _undergradCourseId(metadata);
      metadataById[courseId] = metadata;
      scheduleRowsById.putIfAbsent(courseId, () => []).add(scheduleRow);
    }
    for (final listRow in courseListRows) {
      final metadata = _mergeUndergradCourseMetadata(listRow, courseRows);
      final courseId = _undergradCourseId(metadata);
      metadataById.putIfAbsent(courseId, () => metadata);
      listRowsById.putIfAbsent(courseId, () => []).add(listRow);
    }
    for (final examRow in examRows) {
      final metadata = _mergeUndergradCourseMetadata(
        examRow,
        metadataById.values.toList(),
      );
      final courseId = _undergradCourseId(metadata);
      metadataById.putIfAbsent(courseId, () => metadata);
      examRowsById.putIfAbsent(courseId, () => []).add(examRow);
    }

    final courses = <NjuCourse>[];
    for (final entry in metadataById.entries) {
      final courseId = entry.key;
      final metadata = entry.value;
      final details = _undergradCourseDetails(metadata, studentId);
      final sessions = <NjuCourseEvent>[
        for (final row in scheduleRowsById[courseId] ?? const [])
          ..._mapUndergradCourse(
            row,
            semesterStart,
            semesterId,
            courseId,
            details,
          ),
      ];
      final midtermExams = <NjuCourseEvent>[];
      final midtermImportKeys = <String>{};
      for (final row in listRowsById[courseId] ?? const []) {
        for (final event in _mapUndergradMidtermExams(
          row,
          semesterId,
          courseId,
          details,
        )) {
          if (midtermImportKeys.add(event.importKey)) {
            midtermExams.add(event);
          }
        }
      }
      final finalExams = <NjuCourseEvent>[
        for (final row in examRowsById[courseId] ?? const [])
          if (_mapUndergradExam(
            row,
            semesterId,
            courseId,
            details,
          )
              case final event?)
            event,
      ];
      courses.add(
        NjuCourse(
          id: courseId,
          details: details,
          sessions: sessions,
          midtermExams: midtermExams,
          finalExams: finalExams,
        ),
      );
    }

    return ScheduleBundle(
      semesterId: semesterId,
      semesterName: semesterName,
      semesterStart: semesterStart,
      semesterEnd: semesterEnd,
      courses: courses,
    );
  }

  Future<ScheduleBundle> _fetchGraduate(
    Dio dio, {
    required String studentId,
  }) async {
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
    final rawSemesterAnchor = _parseDateTime('${currentSemester['KBKFRQ']}');
    // 研究生接口中的 KBKFRQ 更像“课表开放/锚点日期”，不一定正好是周一。
    // 先归一化到该周周一，再叠加 XQ(周几) 与 ZCBH(周次)，避免整体 weekday 固定偏移。
    final semesterStart = _normalizeWeekAnchorToMonday(rawSemesterAnchor);

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

    final detailsById = <String, NjuCourseDetails>{};
    final sessionsById = <String, List<NjuCourseEvent>>{};
    for (final row in mergedRows) {
      final details = _graduateCourseDetails(row, studentId);
      final courseId = _graduateCourseId(row);
      detailsById.putIfAbsent(courseId, () => details);
      sessionsById.putIfAbsent(courseId, () => []).addAll(
            _mapGraduateCourse(
              row,
              semesterStart,
              semesterId,
              courseId,
              details,
            ),
          );
    }
    final courses = [
      for (final entry in detailsById.entries)
        NjuCourse(
          id: entry.key,
          details: entry.value,
          sessions: sessionsById[entry.key] ?? const [],
        ),
    ];

    return ScheduleBundle(
      semesterId: semesterId,
      semesterName: semesterName,
      semesterStart: semesterStart,
      semesterEnd: semesterStart,
      courses: courses,
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

  List<Map<String, dynamic>> _mergeGraduateRows(
      List<Map<String, dynamic>> rows) {
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
        final canMerge = '${last['BJMC']}' == '${row['BJMC']}' &&
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
    String semesterId,
    String courseId,
    NjuCourseDetails details,
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
    final title = details.courseName;
    final location = _stringOrNull(row['JASMC']);
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
        semesterId: semesterId,
        importKey: importKey,
        details: details,
        extraLines: const [],
      );
      events.add(
        NjuCourseEvent(
          title: title,
          start: start,
          end: end,
          location: location,
          description: description,
          importKey: importKey,
          courseId: courseId,
          kind: NjuCourseEventKind.session,
        ),
      );
    }
    return events;
  }

  NjuCourseEvent? _mapUndergradExam(
    Map<String, dynamic> row,
    String semesterId,
    String courseId,
    NjuCourseDetails details,
  ) {
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

    final title = '${details.courseName}期末考试';
    final location = _stringOrNull(row['JASMC']);
    final importKey =
        _buildImportKey('undergrad_exam', title, start, end, location);

    return NjuCourseEvent(
      title: title,
      start: start,
      end: end,
      location: location,
      importKey: importKey,
      description: _buildDescription(
        semesterId: semesterId,
        importKey: importKey,
        details: details,
        extraLines: const [],
      ),
      courseId: courseId,
      kind: NjuCourseEventKind.finalExam,
    );
  }

  Map<String, dynamic> _mergeUndergradCourseMetadata(
    Map<String, dynamic> listRow,
    List<Map<String, dynamic>> scheduleRows,
  ) {
    final courseCode =
        _stringOrNull(listRow['KCH']) ?? _stringOrNull(listRow['KCDM']);
    final className = _stringOrNull(listRow['JXBMC']);
    for (final scheduleRow in scheduleRows) {
      final scheduleCourseCode = _stringOrNull(scheduleRow['KCH']) ??
          _stringOrNull(scheduleRow['KCDM']);
      final scheduleClassName = _stringOrNull(scheduleRow['JXBMC']);
      final sameCourse = courseCode != null && scheduleCourseCode == courseCode;
      final sameClass = className != null && scheduleClassName == className;
      if (sameCourse || sameClass) {
        final merged = Map<String, dynamic>.from(listRow);
        for (final entry in scheduleRow.entries) {
          if (_stringOrNull(merged[entry.key]) == null) {
            merged[entry.key] = entry.value;
          }
        }
        return merged;
      }
    }
    return listRow;
  }

  String _undergradCourseId(Map<String, dynamic> row) {
    final courseCode = _stringOrNull(row['KCH']) ?? _stringOrNull(row['KCDM']);
    final className = _stringOrNull(row['JXBMC']);
    final courseName = _stringOrNull(row['KCM']) ?? className ?? '未命名课程';
    return [courseCode ?? courseName, className ?? '']
        .where((value) => value.isNotEmpty)
        .join('|');
  }

  NjuCourseDetails _undergradCourseDetails(
    Map<String, dynamic> row,
    String studentId,
  ) {
    final className = _stringOrNull(row['JXBMC']);
    return NjuCourseDetails(
      studentId: studentId,
      courseName: _stringOrNull(row['KCM']) ?? className ?? '未命名课程',
      courseCode: _stringOrNull(row['KCH']) ?? _stringOrNull(row['KCDM']),
      credits: _stringOrNull(row['XF']),
      teacher: _stringOrNull(row['JSHS']) ??
          _stringOrNull(row['SKJS']) ??
          _stringOrNull(row['ZJJSXM']),
      className: className,
      studentClasses: _stringOrNull(row['SKBJ']),
    );
  }

  List<NjuCourseEvent> _mapUndergradMidtermExams(
    Map<String, dynamic> row,
    String semesterId,
    String courseId,
    NjuCourseDetails details,
  ) {
    final title = '${details.courseName}期中考试';
    final events = <NjuCourseEvent>[];

    // The field code behind the page's “其他信息” column is not stable or
    // documented. Restricting discovery to scalar values that contain the
    // explicit tag avoids guessing a field name and does not treat arbitrary
    // dates elsewhere in the row as exams.
    final taggedValues = _scalarTexts(row)
        .where((value) => _normalizeOtherInfo(value).contains('期中考试'))
        .toSet();

    for (final rawText in taggedValues) {
      for (final exam in _parseMidtermExamText(rawText)) {
        final importKey = _buildImportKey(
          'undergrad_midterm_exam|$courseId',
          title,
          exam.start,
          exam.end,
          exam.location,
        );
        events.add(
          NjuCourseEvent(
            title: title,
            start: exam.start,
            end: exam.end,
            location: exam.location,
            importKey: importKey,
            description: _buildDescription(
              semesterId: semesterId,
              importKey: importKey,
              details: details,
              extraLines: const [],
            ),
            courseId: courseId,
            kind: NjuCourseEventKind.midtermExam,
          ),
        );
      }
    }
    return events;
  }

  List<({DateTime start, DateTime end, String? location, String rawText})>
      _parseMidtermExamText(String rawText) {
    final normalized = _normalizeOtherInfo(rawText);
    final tagPattern = RegExp(r'【\s*期中考试\s*】\s*[：:]?');
    final tags = tagPattern.allMatches(normalized).toList();
    final exams =
        <({DateTime start, DateTime end, String? location, String rawText})>[];

    for (var index = 0; index < tags.length; index++) {
      final sectionStart = tags[index].start;
      final sectionEnd =
          index + 1 < tags.length ? tags[index + 1].start : normalized.length;
      final section = normalized.substring(sectionStart, sectionEnd).trim();
      final timeMatch = RegExp(
        r'时间\s*[：:]\s*(\d{4})-(\d{1,2})-(\d{1,2})\s+'
        r'(\d{1,2})[：:](\d{2})\s*[-–—~～至]\s*'
        r'(\d{1,2})[：:](\d{2})',
      ).firstMatch(section);
      if (timeMatch == null) continue;

      final parts = [
        for (var group = 1; group <= 7; group++)
          int.tryParse(timeMatch.group(group) ?? ''),
      ];
      if (parts.any((part) => part == null)) continue;
      final year = parts[0]!;
      final month = parts[1]!;
      final day = parts[2]!;
      final startHour = parts[3]!;
      final startMinute = parts[4]!;
      final endHour = parts[5]!;
      final endMinute = parts[6]!;
      if (startHour > 23 ||
          endHour > 23 ||
          startMinute > 59 ||
          endMinute > 59) {
        continue;
      }

      final start = DateTime(
        year,
        month,
        day,
        startHour,
        startMinute,
      );
      // DateTime normalizes invalid calendar dates, so compare the components
      // to reject values such as February 30 instead of silently shifting them.
      if (start.year != year || start.month != month || start.day != day) {
        continue;
      }
      final end = DateTime(year, month, day, endHour, endMinute);
      if (!end.isAfter(start)) continue;

      final locationMatch = RegExp(
        r'地点\s*[：:]\s*([^\n]*)',
      ).firstMatch(section);
      final location = _stringOrNull(locationMatch?.group(1));
      exams.add((
        start: start,
        end: end,
        location: location,
        rawText: rawText,
      ));
    }
    return exams;
  }

  Iterable<String> _scalarTexts(dynamic value) sync* {
    if (value is Map) {
      for (final nested in value.values) {
        yield* _scalarTexts(nested);
      }
      return;
    }
    if (value is Iterable) {
      for (final nested in value) {
        yield* _scalarTexts(nested);
      }
      return;
    }
    if (value != null) {
      yield value.toString();
    }
  }

  String _normalizeOtherInfo(String value) {
    var text = value
        .replaceAll(
          RegExp(r'&lt;\s*/?\s*br\s*/?\s*&gt;', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'<\s*/?\s*br\s*/?\s*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(r'\r\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    // The API sometimes returns HTML-escaped display text. Decoding after
    // preserving break tags handles values such as &#12304;期中考试&#12305;.
    text = html_parser.parseFragment(text).text ?? text;
    return text.trim();
  }

  List<NjuCourseEvent> _mapGraduateCourse(
    Map<String, dynamic> row,
    DateTime semesterStart,
    String semesterId,
    String courseId,
    NjuCourseDetails details,
  ) {
    final startTime = _hhmmToHourMinute(_toInt(row['KSSJ']));
    final endTime = _hhmmToHourMinute(_toInt(row['JSSJ']));
    final weekBitmap = '${row['ZCBH'] ?? ''}';
    final weekday = _toInt(row['XQ']);
    final title = details.courseName;
    final eventLocation = _stringOrNull(row['JASMC']);
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
        eventLocation,
      );
      final description = _buildDescription(
        semesterId: semesterId,
        importKey: importKey,
        details: details,
        extraLines: [
          if (remark != null && remark.isNotEmpty) '选课备注：$remark',
        ],
      );
      events.add(
        NjuCourseEvent(
          title: title,
          start: start,
          end: end,
          location: eventLocation,
          description: description,
          importKey: importKey,
          courseId: courseId,
          kind: NjuCourseEventKind.session,
        ),
      );
    }
    return events;
  }

  String _graduateCourseId(Map<String, dynamic> row) {
    final courseCode = _stringOrNull(row['KCDM']);
    final className = _stringOrNull(row['BJMC']);
    final courseName = _stringOrNull(row['KCMC']) ?? className ?? '未命名课程';
    return [courseCode ?? courseName, className ?? '']
        .where((value) => value.isNotEmpty)
        .join('|');
  }

  NjuCourseDetails _graduateCourseDetails(
    Map<String, dynamic> row,
    String studentId,
  ) {
    final className = _stringOrNull(row['BJMC']);
    return NjuCourseDetails(
      studentId: studentId,
      courseName: _stringOrNull(row['KCMC']) ?? className ?? '未命名课程',
      courseCode: _stringOrNull(row['KCDM']),
      credits: _stringOrNull(row['XF']),
      teacher: _stringOrNull(row['JSXM']),
      className: className,
      studentClasses: _stringOrNull(row['SKBJ']),
    );
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

  String? _formatListField(String? value) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    return text.replaceAllMapped(
      RegExp(r'([,，])\s*'),
      (match) => '${match.group(1)}\n',
    );
  }

  String _buildDescription({
    required String semesterId,
    required String importKey,
    required NjuCourseDetails details,
    required List<String> extraLines,
  }) {
    final formattedTeacher = _formatListField(details.teacher);
    final formattedStudentClasses = _formatListField(details.studentClasses);
    final courseParts = [
      if (details.courseCode case final courseCode?) courseCode,
      if (details.credits case final credits?) '$credits学分',
    ];
    final detailLines = [
      '[${details.studentId}的课程]',
      '课程：${courseParts.join('，')}',
      '教师：${formattedTeacher ?? ''}',
      '班级：${details.className ?? ''}',
      if (formattedStudentClasses != null)
        '上课班级：$formattedStudentClasses',
      ...extraLines,
    ];

    return CalendarImportMetadata.buildDescription(
      semesterId: semesterId,
      importKey: importKey,
      detailLines: detailLines,
    );
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

  DateTime _normalizeWeekAnchorToMonday(DateTime anchor) {
    final dateOnly = DateTime(anchor.year, anchor.month, anchor.day);
    return dateOnly.subtract(Duration(days: anchor.weekday - DateTime.monday));
  }

  (int, int) _hhmmToHourMinute(int value) {
    final hour = value ~/ 100;
    final minute = value % 100;
    return (hour, minute);
  }
}
