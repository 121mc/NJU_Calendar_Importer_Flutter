import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/nju_semester.dart';

void main() {
  test('parses undergrad normal semester row into id name and range', () {
    final semester = NjuSemester.fromUndergradRow(
      {
        'XN': '2025-2026',
        'XQ': '2',
        'XQKSRQ': '2026-03-02 00:00:00',
        'ZZC': 18,
      },
      currentSemesterId: '2025-2026-2',
    );

    expect(semester.id, '2025-2026-2');
    expect(semester.name, '2025-2026学年 第2学期');
    expect(semester.year, '2025-2026');
    expect(semester.term, '2');
    expect(semester.start, DateTime(2026, 3, 2));
    expect(semester.end,
        DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)));
    expect(semester.isCurrent, isTrue);
  });

  test('parses undergrad summer semester row with summer display name', () {
    final semester = NjuSemester.fromUndergradRow(
      {
        'XN': '2025-2026',
        'XQ': '3',
        'XQKSRQ': '2026-07-06 00:00:00',
        'ZZC': 4,
      },
      currentSemesterId: '2025-2026-2',
    );

    expect(semester.id, '2025-2026-3');
    expect(semester.name, '2025-2026学年 暑期');
    expect(semester.start, DateTime(2026, 7, 6));
    expect(semester.end,
        DateTime(2026, 8, 3).subtract(const Duration(milliseconds: 1)));
    expect(semester.isCurrent, isFalse);
  });

  test('parses current semester row id and name', () {
    final current = NjuSemester.currentUndergradIdAndName({
      'DM': '2025-2026-2',
      'MC': '2025-2026学年 第2学期',
    });

    expect(current.$1, '2025-2026-2');
    expect(current.$2, '2025-2026学年 第2学期');
  });

  test('parses undergrad first semester row with first term display name', () {
    final semester = NjuSemester.fromUndergradRow(
      {
        'XN': '2025-2026',
        'XQ': '1',
        'XQKSRQ': '2025-09-01 00:00:00',
        'ZZC': 18,
      },
      currentSemesterId: null,
    );

    expect(semester.id, '2025-2026-1');
    expect(semester.name, '2025-2026学年 第1学期');
  });

  test('parses unknown undergrad term with numbered fallback display name', () {
    final semester = NjuSemester.fromUndergradRow(
      {
        'XN': '2025-2026',
        'XQ': '4',
        'XQKSRQ': '2026-08-03 00:00:00',
        'ZZC': 1,
      },
      currentSemesterId: null,
    );

    expect(semester.id, '2025-2026-4');
    expect(semester.name, '2025-2026学年 第4学期');
  });
}
