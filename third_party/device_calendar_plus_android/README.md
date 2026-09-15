# Local Android calendar plugin patch

Based on device_calendar_plus_android 0.3.5 from
https://github.com/bullet-to/device_calendar_plus (MIT; see LICENSE).
Only package sources needed by this app are vendored.

Calendar provider reads and writes run on one calendar-io executor.
Permission requests and native activity launches retain main-thread dispatch.
The executor drains accepted work on engine detach without blocking the UI.
Data services retain only application context for queued work.
Dart APIs and import/overwrite behavior are unchanged.

The root pubspec uses this directory to make the fix reproducible without
modifying the Pub cache. Review the dispatch patch and native tests when
upgrading the upstream plugin.
