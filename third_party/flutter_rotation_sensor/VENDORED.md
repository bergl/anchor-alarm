# Vendored flutter_rotation_sensor 0.4.0

Copied from pub.dev (MIT, see LICENSE) with one change: the `web` plugin
registration is removed from `pubspec.yaml`.

Why: on web the plugin's `registerWith` constructs an `AbsoluteOrientationSensor`
eagerly. Where the page is not allowed motion sensors (an embedding iframe, a
sandboxed preview, some privacy settings) that throws a `SecurityError` inside
Flutter's generated plugin registrant, before `main()` runs, and the app never
starts. Anchor Alarm does not use the compass on web (`NoHeadingSource`), so the
web implementation is simply not registered. Android and iOS are unchanged.

Remove this copy once upstream creates the sensor lazily.
