import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/nju_course.dart';
import 'package:nju_calendar_importer_flutter/services/ics_export_service.dart';

ScheduleBundle _makeBundle({List<NjuCourseEvent> events = const []}) {
  return ScheduleBundle(
    semesterId: '2025-2026-2',
    semesterName: '2025-2026学年 第2学期',
    semesterStart: DateTime(2026, 3, 2),
    semesterEnd: DateTime(2026, 7, 5, 23, 59, 59, 999),
    courseCount: 1,
    examCount: 0,
    events: events,
  );
}

NjuCourseEvent _makeEvent({
  String title = 'Data Structures',
  DateTime? start,
  DateTime? end,
  String? location = 'A101',
  String? description,
  String importKey = 'abc123',
}) {
  return NjuCourseEvent(
    title: title,
    start: start ?? DateTime(2026, 3, 4, 8, 0),
    end: end ?? DateTime(2026, 3, 4, 9, 40),
    location: location,
    description: description ??
        '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2\nimport_key=abc123\n教师：Alice\n班级：CS2024',
    importKey: importKey,
  );
}

void main() {
  late IcsExportService service;

  setUp(() {
    service = IcsExportService();
  });

  test('VCALENDAR envelope is well-formed', () {
    final ics = service.generateIcsContent(_makeBundle());

    expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(ics, contains('VERSION:2.0\r\n'));
    expect(ics, contains('PRODID:-//NJU Calendar Importer//NJU Schedule//ZH\r\n'));
    expect(ics, contains('CALSCALE:GREGORIAN\r\n'));
    expect(ics, contains('METHOD:PUBLISH\r\n'));
  });

  test('VTIMEZONE block for Asia/Shanghai is present', () {
    final ics = service.generateIcsContent(_makeBundle());

    expect(ics, contains('BEGIN:VTIMEZONE\r\n'));
    expect(ics, contains('TZID:Asia/Shanghai\r\n'));
    expect(ics, contains('BEGIN:STANDARD\r\n'));
    expect(ics, contains('DTSTART:19700101T000000\r\n'));
    expect(ics, contains('TZOFFSETFROM:+0800\r\n'));
    expect(ics, contains('TZOFFSETTO:+0800\r\n'));
    expect(ics, contains('TZNAME:CST\r\n'));
    expect(ics, contains('END:STANDARD\r\n'));
    expect(ics, contains('END:VTIMEZONE\r\n'));
  });

  test('X-WR-CALNAME and X-WR-TIMEZONE are set', () {
    final ics = service.generateIcsContent(_makeBundle());

    expect(ics, contains('X-WR-CALNAME:2025-2026学年 第2学期\r\n'));
    expect(ics, contains('X-WR-TIMEZONE:Asia/Shanghai\r\n'));
  });

  test('each event produces a VEVENT with correct fields', () {
    final bundle = _makeBundle(events: [
      _makeEvent(),
      _makeEvent(
        title: 'Operating Systems',
        start: DateTime(2026, 3, 5, 10, 0),
        end: DateTime(2026, 3, 5, 11, 40),
        location: 'B202',
        importKey: 'def456',
      ),
    ]);

    final ics = service.generateIcsContent(bundle);

    // Two VEVENT blocks
    expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
    expect('END:VEVENT'.allMatches(ics).length, 2);

    // First event
    expect(ics, contains('UID:abc123@nju-calendar-importer'));
    expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260304T080000'));
    expect(ics, contains('DTEND;TZID=Asia/Shanghai:20260304T094000'));
    expect(ics, contains('SUMMARY:Data Structures'));
    expect(ics, contains('LOCATION:A101'));
    expect(ics, contains('STATUS:CONFIRMED'));

    // Second event
    expect(ics, contains('UID:def456@nju-calendar-importer'));
    expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260305T100000'));
    expect(ics, contains('DTEND;TZID=Asia/Shanghai:20260305T114000'));
    expect(ics, contains('SUMMARY:Operating Systems'));
    expect(ics, contains('LOCATION:B202'));
  });

  test('metadata markers are stripped from DESCRIPTION', () {
    final bundle = _makeBundle(events: [
      _makeEvent(description:
          '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2\nimport_key=abc123\n教师：Alice\n班级：CS2024'),
    ]);

    final ics = service.generateIcsContent(bundle);

    // Should NOT contain metadata markers in the output
    expect(ics, isNot(contains('[NJU_CALENDAR_IMPORTER]')));
    expect(ics, isNot(contains('semester_id=')));
    expect(ics, isNot(contains('import_key=')));

    // SHOULD contain the human-readable lines
    expect(ics, contains('教师：Alice'));
    expect(ics, contains('班级：CS2024'));
  });

  test('legacy marker is also stripped from DESCRIPTION', () {
    final bundle = _makeBundle(events: [
      _makeEvent(description:
          '[NJU_SCHEDULE_IMPORT]\nimport_key=old\n课程：Math'),
    ]);

    final ics = service.generateIcsContent(bundle);

    expect(ics, isNot(contains('[NJU_SCHEDULE_IMPORT]')));
    expect(ics, contains('课程：Math'));
  });

  test('LOCATION is omitted when null', () {
    final bundle = _makeBundle(events: [
      _makeEvent(location: null),
    ]);

    final ics = service.generateIcsContent(bundle);

    expect(ics, isNot(contains('LOCATION:')));
  });

  test('LOCATION is omitted when blank', () {
    final bundle = _makeBundle(events: [
      _makeEvent(location: '   '),
    ]);

    final ics = service.generateIcsContent(bundle);

    expect(ics, isNot(contains('LOCATION:')));
  });

  test('DESCRIPTION is omitted when only metadata is present', () {
    final bundle = _makeBundle(events: [
      _makeEvent(description:
          '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2\nimport_key=abc123'),
    ]);

    final ics = service.generateIcsContent(bundle);

    expect(ics, isNot(contains('DESCRIPTION:')));
  });

  test('empty events list produces valid VCALENDAR with zero VEVENTs', () {
    final bundle = _makeBundle(events: const []);

    final ics = service.generateIcsContent(bundle);

    expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(ics, isNot(contains('BEGIN:VEVENT')));
  });

  test('event with blank title is skipped', () {
    final bundle = _makeBundle(events: [
      _makeEvent(title: '   '),
      _makeEvent(title: 'Valid Course'),
    ]);

    final ics = service.generateIcsContent(bundle);

    expect('BEGIN:VEVENT'.allMatches(ics).length, 1);
    expect(ics, contains('SUMMARY:Valid Course'));
  });

  test('special characters in text are escaped', () {
    final bundle = _makeBundle(events: [
      _makeEvent(
        title: 'Cryptography, Security; & "Math"',
        location: 'Room A,B',
        description: 'Line1\nLine2',
      ),
    ]);

    final ics = service.generateIcsContent(bundle);

    expect(ics, contains('SUMMARY:Cryptography\\, Security\\; & \\"Math\\"'));
    expect(ics, contains('LOCATION:Room A\\,B'));
  });
}
