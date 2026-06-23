import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/login_models.dart';
import 'package:nju_calendar_importer_flutter/models/nju_semester.dart';
import 'package:nju_calendar_importer_flutter/models/school_type.dart';
import 'package:nju_calendar_importer_flutter/services/auth_service.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_import_metadata.dart';
import 'package:nju_calendar_importer_flutter/services/nju_schedule_service.dart';
import 'package:nju_calendar_importer_flutter/services/storage_service.dart';

class FakeAuthService extends AuthService {
  FakeAuthService(this._dio) : super(StorageService());

  final Dio _dio;

  @override
  Future<Dio> buildAuthenticatedDio(SessionInfo session) async => _dio;
}

void main() {
  SessionInfo undergradSession() => const SessionInfo(
        username: 'student',
        schoolType: SchoolType.undergrad,
        cookiesByBaseUrl: {},
      );

  SessionInfo graduateSession() => const SessionInfo(
        username: 'student',
        schoolType: SchoolType.graduate,
        cookiesByBaseUrl: {},
      );

  test('fetches undergrad semesters and marks current semester', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/dqxnxq.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'dqxnxq': {
                        'rows': [
                          {'DM': '2025-2026-2', 'MC': '2025-2026学年 第2学期'},
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/cxjcs.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxjcs': {
                        'rows': [
                          {
                            'XN': '2026-2027',
                            'XQ': '1',
                            'XQKSRQ': '2026-08-24 00:00:00',
                            'ZZC': 20,
                          },
                          {
                            'XN': '2025-2026',
                            'XQ': '2',
                            'XQKSRQ': '2026-03-02 00:00:00',
                            'ZZC': 18,
                          },
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

    final service = NjuScheduleService(FakeAuthService(dio));
    final result =
        await service.fetchUndergradSemesterOptions(undergradSession());

    expect(result.currentSemesterId, '2025-2026-2');
    expect(result.semesters.length, 2);
    expect(result.semesters.first.id, '2026-2027-1');
    expect(result.semesters[1].id, '2025-2026-2');
    expect(result.semesters[1].isCurrent, isTrue);
  });

  test('current undergrad fetch ignores malformed non-current semester rows',
      () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/dqxnxq.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'dqxnxq': {
                        'rows': [
                          {'DM': '2025-2026-2', 'MC': '2025-2026学年 第2学期'},
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/cxjcs.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxjcs': {
                        'rows': [
                          {
                            'XN': '2024-2025',
                            'XQ': '1',
                            'XQKSRQ': '',
                            'ZZC': 18,
                          },
                          {
                            'XN': '2025-2026',
                            'XQ': '2',
                            'XQKSRQ': '2026-03-02 00:00:00',
                            'ZZC': 18,
                          },
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/cxxszhxqkb.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxxszhxqkb': {
                        'rows': <Map<String, dynamic>>[],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/cxxsksap.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxxsksap': {
                        'rows': <Map<String, dynamic>>[],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

    final service = NjuScheduleService(FakeAuthService(dio));
    final bundle = await service.fetchCurrentSemesterSchedule(
      undergradSession(),
    );

    expect(bundle.semesterId, '2025-2026-2');
  });

  test('undergrad semester options falls back to first semester', () {
    final firstSemester = NjuSemester(
      id: '2026-2027-1',
      name: '2026-2027学年 第1学期',
      year: '2026-2027',
      term: '1',
      start: DateTime(2026, 8, 24),
      end: DateTime(2027, 1, 11).subtract(const Duration(milliseconds: 1)),
      isCurrent: false,
    );
    final secondSemester = NjuSemester(
      id: '2025-2026-2',
      name: '2025-2026学年 第2学期',
      year: '2025-2026',
      term: '2',
      start: DateTime(2026, 3, 2),
      end: DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
      isCurrent: false,
    );
    final options = UndergradSemesterOptions(
      currentSemesterId: '2025-2026-3',
      currentSemesterName: '2025-2026学年 暑期',
      semesters: [firstSemester, secondSemester],
    );

    expect(options.currentSemester, same(firstSemester));
  });

  test('selected undergrad semester id is submitted to course and exam APIs',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);

            if (options.path.endsWith('/cxxszhxqkb.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxxszhxqkb': {
                        'rows': <Map<String, dynamic>>[],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/cxxsksap.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxxsksap': {
                        'rows': <Map<String, dynamic>>[],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

    final service = NjuScheduleService(FakeAuthService(dio));
    final semester = (await service.fetchUndergradScheduleForSemester(
      undergradSession(),
      semesterId: '2025-2026-1',
      semesterName: '2025-2026学年 第1学期',
      semesterStart: DateTime(2025, 8, 25),
      semesterEnd:
          DateTime(2026, 1, 12).subtract(const Duration(milliseconds: 1)),
      includeFinalExams: true,
    ));

    expect(semester.semesterId, '2025-2026-1');
    expect(semester.events, isEmpty);

    final courseRequest = requests.firstWhere(
      (request) => request.path.endsWith('/cxxszhxqkb.do'),
    );
    expect(courseRequest.data['XNXQDM'], '2025-2026-1');

    final examRequest = requests.firstWhere(
      (request) => request.path.endsWith('/cxxsksap.do'),
    );
    final examPayload =
        jsonDecode(examRequest.data['requestParamStr'] as String)
            as Map<String, dynamic>;
    expect(examPayload['XNXQDM'], '2025-2026-1');
  });

  test('undergrad generated descriptions use importer metadata', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/cxxszhxqkb.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxxszhxqkb': {
                        'rows': [
                          {
                            'KSJC': 1,
                            'JSJC': 2,
                            'SKXQ': 1,
                            'SKZC': '1',
                            'KCM': '数据结构',
                            'JASMC': '仙林教学楼101',
                            'JSHS': '张三 13812345678',
                            'JXBMC': '数据结构-001',
                            'SKBJ': '计科一班',
                            'XXXQDM_DISPLAY': '仙林校区',
                          },
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/cxxsksap.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxxsksap': {
                        'rows': [
                          {
                            'KSRQ': '2025-12-29',
                            'KSKSSJ': '09:00',
                            'KSJSSJ': '11:00',
                            'KCM': '数据结构',
                            'JASMC': '逸夫楼201',
                            'ZJJSXM': '李四',
                          },
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

    final service = NjuScheduleService(FakeAuthService(dio));
    final bundle = await service.fetchUndergradScheduleForSemester(
      undergradSession(),
      semesterId: '2025-2026-1',
      semesterName: '2025-2026学年 第1学期',
      semesterStart: DateTime(2025, 8, 25),
      semesterEnd:
          DateTime(2026, 1, 12).subtract(const Duration(milliseconds: 1)),
    );

    final course = bundle.events.firstWhere((event) => event.title == '数据结构');
    expect(course.description, contains(CalendarImportMetadata.currentMarker));
    expect(course.description, contains('semester_id=2025-2026-1'));
    expect(course.description, contains('import_key='));
    expect(course.description, contains('学校：本科生'));
    expect(course.description, contains('教师：张三'));
    expect(course.description, contains('上课班级：计科一班'));

    final exam = bundle.events.firstWhere(
      (event) => event.title == '数据结构期末考试',
    );
    expect(exam.description, contains(CalendarImportMetadata.currentMarker));
    expect(exam.description, contains('semester_id=2025-2026-1'));
    expect(exam.description, contains('import_key='));
    expect(exam.description, contains('学校：本科生'));
    expect(exam.description, contains('教师：李四'));
    expect(exam.description, contains('类型：期末考试'));
  });

  test('graduate generated descriptions use importer metadata', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/kfdxnxqcx.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'kfdxnxqcx': {
                        'rows': [
                          {
                            'XNXQDM': '2020-2021-1',
                            'XNXQDM_DISPLAY': '2020-2021学年 第1学期',
                            'KBKFRQ': '2020-09-07 00:00:00',
                          },
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/xspkjgcx.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'xspkjgcx': {
                        'rows': [
                          {
                            'BJMC': '高级算法班',
                            'XQ': 1,
                            'KSJCDM': 1,
                            'JSJCDM': 2,
                            'JASMC': '仙林教学楼201',
                            'KCDM': 'GRAD101',
                            'KSSJ': 800,
                            'JSSJ': 950,
                            'ZCBH': '1',
                            'KCMC': '高级算法',
                            'JSXM': '王五',
                            'XKBZ': '请带教材',
                          },
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.contains('/xsjxrwcx.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'xsjxrwcx': {
                        'rows': [
                          {
                            'KCDM': 'GRAD101',
                            'XQDM_DISPLAY': '鼓楼校区',
                          },
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

    final service = NjuScheduleService(FakeAuthService(dio));
    final bundle = await service.fetchCurrentSemesterSchedule(
      graduateSession(),
    );

    expect(bundle.semesterId, '2020-2021-1');
    expect(bundle.events, hasLength(1));
    final description = bundle.events.single.description;
    expect(description, contains(CalendarImportMetadata.currentMarker));
    expect(description, contains('semester_id=2020-2021-1'));
    expect(description, contains('import_key='));
    expect(description, contains('学校：研究生'));
    expect(description, contains('教师：王五'));
    expect(description, contains('班级：高级算法班'));
    expect(description, contains('校区：鼓楼校区'));
    expect(description, contains('选课备注：请带教材'));
  });
}
