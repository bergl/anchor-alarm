import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/models.dart';
import 'notification_service.dart';

/// Android channel ids. Channel settings (importance, sound, DnD bypass) are
/// fixed by Android once a channel exists; change the id to change them.
abstract final class NotificationChannels {
  static const alarm = 'anchor_alarm';
  static const warning = 'anchor_warning';
  static const info = 'anchor_info';
}

/// iOS notification category carrying the "Silence" action.
const _iosAlarmCategory = 'anchor_alarm_category';

/// Small notification icon (white anchor vector drawable in android/res).
const _androidIcon = 'ic_stat_anchor';

/// System notifications via flutter_local_notifications (Android, iOS, web).
///
/// * Android: alarm channel with max importance, alarm audio usage, full-screen
///   intent (turns the screen on and opens the app over the lock screen),
///   DnD bypass when the user granted notification-policy access; warning
///   channel high importance; info channel default.
/// * iOS: time-sensitive interruption level for alarms (breaks through Focus
///   modes when the user allows time-sensitive notifications for the app).
/// * Web: browser notifications through the plugin's service worker. Actions
///   only work in Chromium browsers; permission must be requested from a
///   user gesture.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _actions = StreamController<String>.broadcast();
  bool _initialized = false;
  bool _available = true;
  String? _pendingLaunchAction;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static int _idFor(AlertReason reason) => 100 + reason.index;
  static const _infoId = 1;

  @override
  Stream<String> get actions {
    // Deliver a launch-from-notification action to the first listener (it
    // happens before the UI subscribes).
    final pending = _pendingLaunchAction;
    if (pending != null) {
      _pendingLaunchAction = null;
      scheduleMicrotask(() => _actions.add(pending));
    }
    return _actions.stream;
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final darwin = DarwinInitializationSettings(
        // Permissions are requested explicitly via requestPermission().
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            _iosAlarmCategory,
            actions: [
              DarwinNotificationAction.plain(
                NotificationActions.silence,
                'Silence',
                options: const {DarwinNotificationActionOption.foreground},
              ),
            ],
          ),
        ],
      );
      final ok = await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings(_androidIcon),
          iOS: darwin,
          macOS: darwin,
          web: const WebInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      if (ok == false) _available = false;

      if (_isAndroid) await _createAndroidChannels();

      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _pendingLaunchAction = _actionOf(response);
      }
    } catch (e) {
      debugPrint('LocalNotificationService.init failed: $e');
      _available = false;
    }
  }

  Future<void> _createAndroidChannels() async {
    final android = _android;
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationChannels.alarm,
        'Anchor alarm',
        description: 'Anchor dragging, GPS lost, critical battery',
        importance: Importance.max,
        // Only effective if notification-policy (DnD) access was granted
        // before the channel was created; see requestDndAccess().
        bypassDnd: true,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        showBadge: true,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationChannels.warning,
        'Anchor warnings',
        description: 'Near the edge of the swing circle, poor GPS, low battery',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationChannels.info,
        'Anchor watch info',
        description: 'Watch started, resumed and similar information',
        importance: Importance.defaultImportance,
      ),
    );
  }

  /// Android only: opens the "Do Not Disturb access" settings. If access is
  /// granted, the alarm channel is recreated so that it bypasses DnD.
  /// Returns whether access is granted.
  Future<bool> requestDndAccess() async {
    final android = _android;
    if (android == null) return false;
    try {
      if (await android.hasNotificationPolicyAccess() != true) {
        await android.requestNotificationPolicyAccess();
      }
      final granted = await android.hasNotificationPolicyAccess() == true;
      if (granted) {
        await android.deleteNotificationChannel(channelId: NotificationChannels.alarm);
        await _createAndroidChannels();
      }
      return granted;
    } catch (e) {
      debugPrint('requestDndAccess failed: $e');
      return false;
    }
  }

  void _onResponse(NotificationResponse r) {
    _actions.add(_actionOf(r));
  }

  static String _actionOf(NotificationResponse r) {
    final id = r.actionId;
    if (id != null && id.isNotEmpty) return id;
    return NotificationActions.open;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_initialized) await init();
    try {
      if (_isAndroid) {
        final android = _android;
        final granted = await android?.requestNotificationsPermission() ?? true;
        // Android 14+: full-screen intents need a separate special-access
        // grant for apps that are not alarm clocks / dialers. This opens the
        // settings page only when not yet granted.
        try {
          await android?.requestFullScreenIntentPermission();
        } catch (_) {}
        return granted;
      }
      if (_isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      if (kIsWeb) {
        final web = _plugin.resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>();
        if (web == null) return false;
        if (web.permissionStatus == WebNotificationPermission.granted) return true;
        return await web.requestNotificationsPermission() ?? false;
      }
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
    return false;
  }

  NotificationDetails _alarmDetails() => NotificationDetails(
        android: const AndroidNotificationDetails(
          NotificationChannels.alarm,
          'Anchor alarm',
          channelDescription: 'Anchor dragging, GPS lost, critical battery',
          icon: _androidIcon,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          channelBypassDnd: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          visibility: NotificationVisibility.public,
          ticker: 'Anchor alarm',
          actions: [
            AndroidNotificationAction(
              NotificationActions.silence,
              'Silence',
              // Brings the app to the foreground so the main isolate handles
              // the action (silences the in-app siren).
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
          categoryIdentifier: _iosAlarmCategory,
          threadIdentifier: 'anchor_alarm',
        ),
        web: const WebNotificationDetails(
          requireInteraction: true,
          renotify: true,
          actions: [WebNotificationAction(action: NotificationActions.silence, title: 'Silence')],
        ),
      );

  NotificationDetails _warningDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.warning,
          'Anchor warnings',
          channelDescription: 'Near the edge of the swing circle, poor GPS, low battery',
          icon: _androidIcon,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.status,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.active,
          threadIdentifier: 'anchor_alarm',
        ),
        web: WebNotificationDetails(renotify: true),
      );

  NotificationDetails _infoDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.info,
          'Anchor watch info',
          channelDescription: 'Watch started, resumed and similar information',
          icon: _androidIcon,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: false,
          interruptionLevel: InterruptionLevel.passive,
        ),
        web: WebNotificationDetails(),
      );

  @override
  Future<void> showAlert({required AlertReason reason, required String title, required String body}) async {
    if (!_initialized) await init();
    if (!_available) return;
    try {
      await _plugin.show(
        id: _idFor(reason),
        title: title,
        body: body,
        notificationDetails: reason.isAlarm ? _alarmDetails() : _warningDetails(),
        payload: reason.name,
      );
    } catch (e) {
      debugPrint('showAlert failed: $e');
    }
  }

  @override
  Future<void> showInfo({required String title, required String body}) async {
    if (!_initialized) await init();
    if (!_available) return;
    try {
      await _plugin.show(id: _infoId, title: title, body: body, notificationDetails: _infoDetails());
    } catch (e) {
      debugPrint('showInfo failed: $e');
    }
  }

  @override
  Future<void> cancelAlert(AlertReason reason) async {
    if (!_available) return;
    try {
      await _plugin.cancel(id: _idFor(reason));
    } catch (e) {
      debugPrint('cancelAlert failed: $e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_available) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('cancelAll failed: $e');
    }
  }
}
