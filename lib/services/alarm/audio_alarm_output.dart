import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'alarm_output.dart';

/// Loud looping alarm with audioplayers + vibration + wakelock.
///
/// Android: the siren plays on the ALARM stream (usage=alarm,
/// contentType=sonification), so it sounds in silent/vibrate mode, and the
/// alarm stream volume is temporarily raised to maximum through the
/// `anchor_alarm/audio` method channel (restored on stop). The siren requests
/// no audio focus on purpose: with focus, any other app taking focus (a
/// notification sound, a video) would pause the alarm for good.
///
/// iOS: AVAudioSession category `playback` (plays with the silent switch on
/// and in the background thanks to `UIBackgroundModes/audio`), with
/// `duckOthers` so that the session can be activated from the background
/// even while another app is playing (a non-mixable session would fail with
/// `cannotInterruptOthers`), lowering that app's volume instead.
///
/// Web: plain HTML audio. Browsers only allow playback after a user gesture
/// on the page, which the UI provides when the watch is started.
///
/// A watchdog restarts playback if the platform pauses it (phone call,
/// interruption) while the alarm should still be ringing.
class AudioAlarmOutput implements AlarmOutput {
  AudioAlarmOutput();

  static const _volumeChannel = MethodChannel('anchor_alarm/audio');
  static const _knownSounds = {'siren'};

  final AudioPlayer _alarm = AudioPlayer(playerId: 'anchor_alarm_siren');
  final AudioPlayer _chime = AudioPlayer(playerId: 'anchor_alarm_chime');

  bool _ringing = false;
  bool _initialized = false;
  bool _vibrating = false;
  Timer? _vibrationTimer;
  Timer? _watchdog;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static final _alarmContext = AudioContext(
    android: const AudioContextAndroid(
      usageType: AndroidUsageType.alarm,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.none,
      stayAwake: true,
      isSpeakerphoneOn: false,
      audioMode: AndroidAudioMode.normal,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.duckOthers},
    ),
  );

  static final _chimeContext = AudioContext(
    android: const AudioContextAndroid(
      usageType: AndroidUsageType.alarm,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      stayAwake: false,
      isSpeakerphoneOn: false,
      audioMode: AndroidAudioMode.normal,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.duckOthers},
    ),
  );

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      if (!kIsWeb) {
        // On iOS there is a single, global audio session; both contexts are
        // identical there, so setting it once is enough.
        await AudioPlayer.global.setAudioContext(_alarmContext);
        await _alarm.setAudioContext(_alarmContext);
        await _chime.setAudioContext(_chimeContext);
      }
      await _alarm.setReleaseMode(ReleaseMode.loop);
      await _chime.setReleaseMode(ReleaseMode.stop);
      await _alarm.setVolume(1.0);
      await _chime.setVolume(1.0);
      // Preload so the first alarm starts without delay.
      await _alarm.setSource(AssetSource(_assetFor('siren')));
      await _chime.setSource(AssetSource('sounds/chime.wav'));
    } catch (e) {
      debugPrint('AudioAlarmOutput.init: $e');
    }
  }

  String _assetFor(String sound) => 'sounds/${_knownSounds.contains(sound) ? sound : 'siren'}.wav';

  @override
  bool get isRinging => _ringing;

  @override
  Future<void> startAlarm({required String sound, required bool vibrate}) async {
    if (_ringing) return;
    _ringing = true;
    if (!_initialized) await init();

    unawaited(_safe(() => WakelockPlus.enable()));
    if (_isAndroid) {
      await _safe(() => _volumeChannel.invokeMethod<void>('raiseAlarmVolume'));
    }
    if (vibrate) unawaited(_startVibration());

    await _safe(() async {
      await _chime.stop();
      await _alarm.setReleaseMode(ReleaseMode.loop);
      await _alarm.setVolume(1.0);
      await _alarm.play(AssetSource(_assetFor(sound)), volume: 1.0);
    });

    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_ringing && _alarm.state != PlayerState.playing) {
        _safe(() => _alarm.resume());
      }
    });
  }

  @override
  Future<void> stopAlarm() async {
    if (!_ringing) return;
    _ringing = false;
    _watchdog?.cancel();
    _watchdog = null;
    await _stopVibration();
    await _safe(() => _alarm.stop());
    if (_isAndroid) {
      await _safe(() => _volumeChannel.invokeMethod<void>('restoreAlarmVolume'));
    }
    await _safe(() => WakelockPlus.disable());
  }

  @override
  Future<void> chime({required bool vibrate}) async {
    if (_ringing) return; // the alarm already covers it
    if (!_initialized) await init();
    await _safe(() async {
      await _chime.stop();
      await _chime.play(AssetSource('sounds/chime.wav'), volume: 1.0);
    });
    if (vibrate) {
      await _safe(() async {
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(pattern: const [0, 250, 150, 250]);
        }
      });
    }
  }

  // ---------------------------------------------------------------- vibration

  static const _pattern = [0, 800, 400, 800, 400, 1200, 600];
  static const _patternPeriod = Duration(milliseconds: 4200);

  Future<void> _startVibration() async {
    if (_vibrating) return;
    try {
      if (!await Vibration.hasVibrator()) return;
    } catch (_) {
      return;
    }
    _vibrating = true;
    if (_isAndroid) {
      // Native repeat; the plugin uses USAGE_ALARM so it continues with the
      // screen off.
      await _safe(() => Vibration.vibrate(pattern: _pattern, repeat: 1));
      return;
    }
    // iOS / web: re-trigger one cycle per period. (iOS Core Haptics stops
    // while the app is in the background; the sound carries the alarm then.)
    Future<void> once() => _safe(() => Vibration.vibrate(pattern: _pattern));
    await once();
    _vibrationTimer = Timer.periodic(_patternPeriod, (_) {
      if (_vibrating) once();
    });
  }

  Future<void> _stopVibration() async {
    if (!_vibrating) return;
    _vibrating = false;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    await _safe(() => Vibration.cancel());
  }

  static Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('AudioAlarmOutput: $e');
    }
  }
}
