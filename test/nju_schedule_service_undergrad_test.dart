import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/login_models.dart';
import 'package:nju_calendar_importer_flutter/models/school_type.dart';
import 'package:nju_calendar_importer_flutter/services/auth_service.dart';
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
}
