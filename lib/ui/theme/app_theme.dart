import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// Colours the anchor watch uses for states, rings and map markers.
/// Night mode keeps everything in dim reds to preserve night vision.
@immutable
class AnchorColors extends ThemeExtension<AnchorColors> {
  const AnchorColors({
    required this.safe,
    required this.warning,
    required this.alarm,
    required this.neutral,
    required this.onState,
    required this.boat,
    required this.anchor,
    required this.track,
    required this.mapBackground,
    required this.night,
  });

  final Color safe;
  final Color warning;
  final Color alarm;

  /// Draft rings and inactive state.
  final Color neutral;

  /// Text drawn on top of a state colour.
  final Color onState;
  final Color boat;
  final Color anchor;
  final Color track;

  /// Map background when no base map is shown.
  final Color mapBackground;
  final bool night;

  Color forState(WatchState? s) => switch (s) {
        WatchState.safe => safe,
        WatchState.warning => warning,
        WatchState.alarm => alarm,
        _ => neutral,
      };

  static AnchorColors of(BuildContext context) =>
      Theme.of(context).extension<AnchorColors>() ?? AppTheme._dayColors;

  @override
  AnchorColors copyWith({
    Color? safe,
    Color? warning,
    Color? alarm,
    Color? neutral,
    Color? onState,
    Color? boat,
    Color? anchor,
    Color? track,
    Color? mapBackground,
    bool? night,
  }) =>
      AnchorColors(
        safe: safe ?? this.safe,
        warning: warning ?? this.warning,
        alarm: alarm ?? this.alarm,
        neutral: neutral ?? this.neutral,
        onState: onState ?? this.onState,
        boat: boat ?? this.boat,
        anchor: anchor ?? this.anchor,
        track: track ?? this.track,
        mapBackground: mapBackground ?? this.mapBackground,
        night: night ?? this.night,
      );

  @override
  AnchorColors lerp(AnchorColors? other, double t) {
    if (other == null) return this;
    return AnchorColors(
      safe: Color.lerp(safe, other.safe, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      alarm: Color.lerp(alarm, other.alarm, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      onState: Color.lerp(onState, other.onState, t)!,
      boat: Color.lerp(boat, other.boat, t)!,
      anchor: Color.lerp(anchor, other.anchor, t)!,
      track: Color.lerp(track, other.track, t)!,
      mapBackground: Color.lerp(mapBackground, other.mapBackground, t)!,
      night: t < 0.5 ? night : other.night,
    );
  }
}

abstract final class AppTheme {
  static const navy = Color(0xFF0B2545);
  static const teal = Color(0xFF13807A);

  static const _dayColors = AnchorColors(
    safe: Color(0xFF2E7D32),
    warning: Color(0xFFF9A825),
    alarm: Color(0xFFD32F2F),
    neutral: teal,
    onState: Colors.white,
    boat: navy,
    anchor: Color(0xFF8D2B0B),
    track: Color(0xFF1565C0),
    mapBackground: Color(0xFFB3D4E5),
    night: false,
  );

  // Night: no whites, no blues/greens. Distinguish states by brightness and words.
  static const nightRed = Color(0xFFB71C1C);
  static const nightRedBright = Color(0xFFFF5252);
  static const nightRedDim = Color(0xFF5C1010);
  static const _nightText = Color(0xFFC62828);

  static const _nightColors = AnchorColors(
    safe: Color(0xFF4A0E0E),
    warning: Color(0xFF8E1A1A),
    alarm: Color(0xFFD32F2F),
    neutral: Color(0xFF6D1B1B),
    onState: Color(0xFFFF8A80),
    boat: Color(0xFFE53935),
    anchor: Color(0xFFC62828),
    track: Color(0xFF7F1D1D),
    mapBackground: Colors.black,
    night: true,
  );

  static ThemeData day() {
    final scheme = ColorScheme.fromSeed(
      seedColor: navy,
      primary: navy,
      secondary: teal,
      brightness: Brightness.light,
    );
    return _base(scheme).copyWith(extensions: const [_dayColors]);
  }

  /// Dark navy theme for "system dark" when the user has not chosen night.
  static ThemeData dusk() {
    final scheme = ColorScheme.fromSeed(
      seedColor: navy,
      secondary: teal,
      brightness: Brightness.dark,
    );
    return _base(scheme).copyWith(
      extensions: [
        _dayColors.copyWith(
          boat: const Color(0xFF90CAF9),
          mapBackground: const Color(0xFF0B1A2A),
          onState: Colors.black,
          safe: const Color(0xFF66BB6A),
          warning: const Color(0xFFFFCA28),
          alarm: const Color(0xFFEF5350),
          neutral: const Color(0xFF4DB6AC),
        ),
      ],
    );
  }

  static ThemeData night() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: nightRed,
      onPrimary: Colors.black,
      primaryContainer: nightRedDim,
      onPrimaryContainer: nightRedBright,
      secondary: Color(0xFF8E1A1A),
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFF2A0707),
      onSecondaryContainer: _nightText,
      tertiary: Color(0xFF8E1A1A),
      onTertiary: Colors.black,
      error: nightRedBright,
      onError: Colors.black,
      surface: Colors.black,
      onSurface: _nightText,
      onSurfaceVariant: Color(0xFF9A2323),
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Color(0xFF0A0101),
      surfaceContainer: Color(0xFF120202),
      surfaceContainerHigh: Color(0xFF180303),
      surfaceContainerHighest: Color(0xFF200404),
      outline: Color(0xFF5C1010),
      outlineVariant: Color(0xFF3A0A0A),
      inverseSurface: Color(0xFF5C1010),
      onInverseSurface: Colors.black,
      inversePrimary: nightRedDim,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: Colors.black,
      extensions: const [_nightColors],
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 6,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    );
  }
}
