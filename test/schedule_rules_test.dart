import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/nju_course.dart';
import 'package:nju_calendar_importer_flutter/services/schedule_rules.dart';
import 'package:nju_calendar_importer_flutter/services/holiday_service.dart';
import 'package:dio/dio.dart';

void main() {
  final anchor = DateTime(2026, 9, 7);
  NjuCourseEvent event(int day,
          {NjuCourseEventKind kind = NjuCourseEventKind.session}) =>
      NjuCourseEvent(
          title: '课程',
          start: DateTime(2026, 9, day, 8),
          end: DateTime(2026, 9, day, 9, 50),
          location: 'A',
          description: 'semester_id=2026-2027-1\nimport_key=old',
          importKey: 'old',
          courseId: 'c',
          kind: kind);
  final holidays = [HolidayRule(DateTime(2026, 9, 7), DateTime(2026, 9, 12))];
  test('holiday moves source and replaces makeup regular schedule', () {
    final result =
        applyScheduleRules([event(7), event(12)], anchor, [], holidays);
    expect(result.single.start, DateTime(2026, 9, 12, 8));
    expect(result.single.description,
        contains('import_key=${result.single.importKey}'));
  });
  test('add-only course uses supplied metadata template', () {
    final changes = parseScheduleChanges(['【加课】(第1周 周一 1-2节)']);
    final result = applyScheduleRules([], anchor, changes, holidays,
        addedClassTemplate: event(7));
    expect(result.single.start.day, 7);
  });
  test('partial section change reports unsupported input', () {
    final changes = parseScheduleChanges(['【停课】(第1周 周一 1-1节)']);
    expect(() => applyScheduleRules([event(7)], anchor, changes, holidays),
        throwsFormatException);
  });
  test('holiday without makeup removes classes', () {
    expect(
        applyScheduleRules([event(7)], anchor, [], [HolidayRule(anchor, null)]),
        isEmpty);
  });
  test('time change wins on holiday and destination holiday', () {
    final changes =
        parseScheduleChanges(['【调课】(第1周 周一 1-2节) 临时调整时间为(第1周 周六 3-4节)']);
    final result = applyScheduleRules([event(7)], anchor, changes, holidays);
    expect(result.single.start, DateTime(2026, 9, 12, 10, 10));
  });
  test('added class survives holiday and makeup day', () {
    for (final day in ['一', '六']) {
      final changes = parseScheduleChanges(['【加课】(第1周 周$day 1-2节)']);
      final result = applyScheduleRules([event(8)], anchor, changes, holidays);
      expect(result.length, 2);
    }
  });
  test('cancel source prevents holiday resurrection', () {
    final changes = parseScheduleChanges(['【停课】(第1周 周一 1-2节) 发生临时停课']);
    expect(applyScheduleRules([event(7)], anchor, changes, holidays), isEmpty);
  });
  test('cancel makeup suppresses moved class', () {
    final changes = parseScheduleChanges(['【停课】(第1周 周六 1-2节) 发生临时停课']);
    expect(applyScheduleRules([event(7)], anchor, changes, holidays), isEmpty);
  });
  test('room change follows holiday and preserves new location', () {
    final changes = parseScheduleChanges(['【调课】(第1周 周一 1-2节 A) 临时调整教室为(B)']);
    final result = applyScheduleRules([event(7)], anchor, changes, holidays);
    expect(result.single.location, 'B');
    expect(result.single.start.day, 12);
  });
  test('teacher commas do not split a change', () {
    final changes = parseScheduleChanges(
        ['【调课】(第1周 周一 1-2节 001,002) 临时调整教师为(新老师),【停课】(第2周 周一 1-2节) 发生临时停课']);
    expect(changes.length, 2);
    expect((changes.first as NjuRescheduledClass).teacherChange!.newTeacher,
        '新老师');
  });
  test('unknown changes fail explicitly', () {
    expect(() => parseScheduleChanges(['【调课】未知格式']), throwsFormatException);
  });
  test('date validation rejects normalized invalid dates', () {
    expect(() => HolidayRule.parseDate('2026-02-30'), throwsFormatException);
  });
  test('holiday request scoped to semester and validates response', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        expect(o.queryParameters, {'semester': '2026-2027-1'});
        expect(o.headers.containsKey('Cookie'), isFalse);
        h.resolve(Response(requestOptions: o, data: {
          'semester': '2026-2027-1',
          'rules': [
            {'holiday': '2026-10-01', 'makeup': '2026-10-10'}
          ]
        }));
      }));
    expect((await HolidayService(dio: dio).fetch('2026-2027-1')).single.makeup,
        DateTime(2026, 10, 10));
  });
  test('failed holiday request prevents incomplete schedule', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.reject(DioException(requestOptions: o))));
    await expectLater(
        HolidayService(dio: dio).fetch('2026-2027-1'), throwsException);
  });
}
