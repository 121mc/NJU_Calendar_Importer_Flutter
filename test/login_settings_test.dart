import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/school_type.dart';
import 'package:nju_calendar_importer_flutter/pages/settings_dialog.dart';
import 'package:nju_calendar_importer_flutter/services/settings_service.dart';

class FakeSettingsService extends SettingsService {
  AutoLoginSettings initial = const AutoLoginSettings();
  AutoLoginSettings? saved;

  @override
  Future<AutoLoginSettings> loadAll() async => initial;

  @override
  Future<void> saveAll(AutoLoginSettings settings) async {
    saved = settings;
  }
}

Widget _settingsLauncher(FakeSettingsService settingsService) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            showDialog<bool>(
              context: context,
              builder: (_) => SettingsDialog(settingsService: settingsService),
            );
          },
          child: const Text('打开设置'),
        ),
      ),
    ),
  );
}

void main() {
  test('student ID length determines school type', () {
    expect(SchoolType.fromStudentId('123456789'), SchoolType.undergrad);
    expect(SchoolType.fromStudentId('123456789012'), SchoolType.graduate);
    expect(SchoolType.fromStudentId('12345678'), isNull);
    expect(SchoolType.fromStudentId('1234567890'), isNull);
    expect(SchoolType.fromStudentId('12345678A'), isNull);
  });

  testWidgets('invalid student ID shows a check dialog on save',
      (tester) async {
    final settingsService = FakeSettingsService();
    await tester.pumpWidget(_settingsLauncher(settingsService));

    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12345678');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.text('保存登录信息'));
    await tester.pumpAndSettle();

    expect(find.text('请检查学号'), findsOneWidget);
    expect(
      find.textContaining('本科生学号应为 9 位数字，研究生学号应为 12 位数字'),
      findsOneWidget,
    );
    expect(settingsService.saved, isNull);
  });

  testWidgets('valid student ID and password are saved', (tester) async {
    final settingsService = FakeSettingsService();
    await tester.pumpWidget(_settingsLauncher(settingsService));

    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '123456789');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.text('保存登录信息'));
    await tester.pumpAndSettle();

    expect(settingsService.saved?.username, '123456789');
    expect(settingsService.saved?.password, 'password');
    expect(find.byType(SettingsDialog), findsNothing);
  });
}
