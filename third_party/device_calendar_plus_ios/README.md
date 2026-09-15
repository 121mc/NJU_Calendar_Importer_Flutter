# Local iOS calendar plugin patch

Based on device_calendar_plus_ios 0.3.5 from
https://github.com/bullet-to/device_calendar_plus (MIT; see LICENSE).

EventKit queries and mutations run on one serial DispatchQueue. Results,
including validation errors, return on the main queue. Permission requests,
settings and EventKit view controllers keep main-thread dispatch. Lazy services
are initialized on the main thread before dispatching data operations.

The root pubspec selects this local package. Review the dispatch patch when
upgrading upstream. Native compilation and device performance must be verified
on macOS with Xcode; they cannot be validated from the Windows workspace.
