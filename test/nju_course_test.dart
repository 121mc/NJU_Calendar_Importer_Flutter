import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/nju_course.dart';

void main() {
  NjuCourseEvent event(String title, DateTime start, NjuCourseEventKind kind) {
    return NjuCourseEvent(
      title: title,
      start: start,
      end: start.add(const Duration(hours: 1)),
      location: null,
      description: '',
      importKey: title,
      courseId: 'CS101|数据结构-001',
      kind: kind,
    );
  }

  test('course owns sessions, exams, and reserved schedule-change fields', () {
    final details = NjuCourseDetails(
      studentId: 'student',
      courseName: '数据结构',
      courseCode: 'CS101',
      credits: '3',
      teacher: '张老师',
      className: '数据结构-001',
      studentClasses: '计科一班',
    );
    final course = NjuCourse(
      id: 'CS101|数据结构-001',
      details: details,
      sessions: [
        event('数据结构', DateTime(2026, 3, 2, 8), NjuCourseEventKind.session),
      ],
      midtermExams: [
        event(
          '数据结构期中考试',
          DateTime(2026, 4, 25, 10, 30),
          NjuCourseEventKind.midtermExam,
        ),
      ],
      finalExams: [
        event(
          '数据结构期末考试',
          DateTime(2026, 6, 22, 10, 30),
          NjuCourseEventKind.finalExam,
        ),
      ],
    );

    expect(course.details, same(details));
    expect(course.events, hasLength(3));
    expect(course.addedClasses, isEmpty);
    expect(course.rescheduledClasses, isEmpty);
    expect(course.cancelledClasses, isEmpty);

    final bundle = ScheduleBundle(
      semesterId: '2025-2026-2',
      semesterName: '2025-2026学年 第2学期',
      semesterStart: DateTime(2026, 3, 2),
      semesterEnd: DateTime(2026, 7, 5),
      courses: [course],
    );
    expect(bundle.events, hasLength(3));
    expect(bundle.courseCount, 1);
    expect(bundle.examCount, 2);
  });

  test('schedule change placeholder preserves structured and raw values', () {
    const change = NjuRescheduledClass(
      week: 3,
      weekday: DateTime.wednesday,
      startSection: 7,
      endSection: 8,
      roomChange: NjuRoomChange(
        originalRoom: '教105',
        newRoom: '新教207',
      ),
      rawText: '【调课】(第3周 周三 7-8节 教105) 临时调整教室为(新教207)',
    );

    expect(change.week, 3);
    expect(change.timeChange, isNull);
    expect(change.roomChange?.originalRoom, '教105');
    expect(change.roomChange?.newRoom, '新教207');
    expect(change.teacherChange, isNull);
  });
}
