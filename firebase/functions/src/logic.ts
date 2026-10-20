/**
 * Pure decision code for the remote-monitoring functions: what to notify,
 * what the push message looks like, which tokens to drop. No Firebase
 * imports, so it is unit tested without emulators.
 */

/** Alert reasons as written by the app (Dart `AlertReason.name`). */
export type AlertReason =
  | 'nearEdge'
  | 'drag'
  | 'gpsLost'
  | 'gpsPoor'
  | 'lowBattery'
  | 'criticalBattery';

/** Reasons that ring the alarm on the boat (Dart `AlertReason.isAlarm`). */
export const ALARM_REASONS: readonly AlertReason[] = ['drag', 'gpsLost', 'criticalBattery'];

export type WatchState = 'inactive' | 'safe' | 'warning' | 'alarm';

/** The fields of `watches/{watchId}` the functions look at, with times as Dates. */
export interface WatchView {
  boatName?: string | null;
  state?: WatchState | string | null;
  reasons?: string[] | null;
  ringing?: boolean | null;
  distanceM?: number | null;
  radiusM?: number | null;
  updatedAt?: Date | null;
  endedAt?: Date | null;
  lostContactNotifiedAt?: Date | null;
  /** Boat's UTC offset in minutes, for "last update 14:05". */
  tzOffsetMin?: number | null;
}

export type Notice =
  | { kind: 'alarm'; reason: AlertReason }
  | { kind: 'ended' }
  | { kind: 'lostContact' }
  | { kind: 'contactRestored' };

/** No update for this long → "Lost contact" (the app writes at least every 60 s). */
export const LOST_CONTACT_AFTER_MS = 3 * 60 * 1000;

/** A watch without updates for this long is treated as abandoned and ended. */
export const ABANDONED_AFTER_MS = 48 * 60 * 60 * 1000;

function alarmReasons(w: WatchView): AlertReason[] {
  return (w.reasons ?? []).filter((r): r is AlertReason =>
    (ALARM_REASONS as readonly string[]).includes(r),
  );
}

function time(d: Date | null | undefined): number | null {
  return d ? d.getTime() : null;
}

/**
 * Notices to send for an update of a watch document.
 *
 * - **alarm**: `ringing` went false → true, or an alarm reason (drag, GPS lost,
 *   critical battery) appeared that was not there before. One notice, for the
 *   most important new reason.
 * - **ended**: `endedAt` was set.
 * - **contactRestored**: the boat wrote an update after a lost-contact notice
 *   (the caller clears `lostContactNotifiedAt` transactionally and only sends
 *   when it actually cleared it, so concurrent updates notify once).
 *
 * Warnings (near edge, poor GPS, low battery) are not pushed: the live view
 * shows them, and pushing them would train people to ignore the alarm.
 */
export function noticesForUpdate(before: WatchView, after: WatchView): Notice[] {
  const notices: Notice[] = [];
  if (before.endedAt == null && after.endedAt != null) {
    notices.push({ kind: 'ended' });
    return notices;
  }
  if (after.endedAt != null) return notices;

  const was = new Set(alarmReasons(before));
  const now = alarmReasons(after);
  const added = now.filter((r) => !was.has(r));
  const startedRinging = after.ringing === true && before.ringing !== true;
  if (added.length > 0 || startedRinging) {
    const reason = mostImportant(added.length > 0 ? added : now) ?? 'drag';
    notices.push({ kind: 'alarm', reason });
  }

  const lost = time(after.lostContactNotifiedAt);
  const updated = time(after.updatedAt);
  const prevUpdated = time(before.updatedAt);
  if (lost != null && updated != null && updated > lost && updated !== prevUpdated) {
    notices.push({ kind: 'contactRestored' });
  }
  return notices;
}

/** drag > gpsLost > criticalBattery. */
export function mostImportant(reasons: readonly AlertReason[]): AlertReason | undefined {
  for (const r of ALARM_REASONS) if (reasons.includes(r)) return r;
  return reasons[0];
}

export type StaleDecision = 'none' | 'notify' | 'abandon';

/**
 * What the scheduled check does with an active watch: notify watchers once
 * when the boat has not written for [LOST_CONTACT_AFTER_MS], end it when it
 * has been silent for [ABANDONED_AFTER_MS] (app uninstalled, phone lost).
 */
export function staleDecision(w: WatchView, now: Date): StaleDecision {
  if (w.endedAt != null) return 'none';
  const updated = time(w.updatedAt);
  if (updated == null) return 'none';
  const age = now.getTime() - updated;
  if (age >= ABANDONED_AFTER_MS) return 'abandon';
  if (age < LOST_CONTACT_AFTER_MS) return 'none';
  const notified = time(w.lostContactNotifiedAt);
  if (notified != null && notified >= updated) return 'none';
  return 'notify';
}

/** "14:05" in the boat's time zone (UTC when unknown). */
export function formatClock(d: Date, tzOffsetMin?: number | null): string {
  const local = new Date(d.getTime() + (tzOffsetMin ?? 0) * 60_000);
  const hh = String(local.getUTCHours()).padStart(2, '0');
  const mm = String(local.getUTCMinutes()).padStart(2, '0');
  return `${hh}:${mm}`;
}

function boat(w: WatchView): string {
  const n = (w.boatName ?? '').trim();
  return n.length > 0 ? n : 'your boat';
}

function metres(m: number | null | undefined): string | null {
  return m == null || !Number.isFinite(m) ? null : `${Math.round(m)} m`;
}

export function alarmText(reason: AlertReason, w: WatchView): { title: string; body: string } {
  const name = boat(w);
  const d = metres(w.distanceM);
  const r = metres(w.radiusM);
  switch (reason) {
    case 'drag':
      return {
        title: `Anchor alarm: ${name} is dragging`,
        body: d
          ? `${d} from the anchor${r ? ` (alarm at ${r})` : ''}.`
          : 'The boat left the alarm circle.',
      };
    case 'gpsLost':
      return {
        title: `Anchor alarm: ${name} lost GPS`,
        body: 'The boat has no position fix. Its position is unknown.',
      };
    case 'criticalBattery':
      return {
        title: `Anchor alarm: ${name} battery critical`,
        body: 'The anchor watch phone on board is about to run out of battery.',
      };
    default:
      return { title: `Anchor alarm: ${name}`, body: 'Check the boat.' };
  }
}

/** Android notification channels created by the app (NotificationChannels). */
export const CHANNEL_ALARM = 'anchor_alarm';
export const CHANNEL_WARNING = 'anchor_warning';
export const CHANNEL_INFO = 'anchor_info';

/** FCM message without the target (tokens are added by the sender). */
export interface PushMessage {
  notification: { title: string; body: string };
  data: Record<string, string>;
  android: {
    priority: 'high' | 'normal';
    collapseKey?: string;
    notification: {
      channelId: string;
      sound?: string;
      tag?: string;
      priority?: 'min' | 'low' | 'default' | 'high' | 'max';
      visibility?: 'private' | 'public' | 'secret';
      defaultVibrateTimings?: boolean;
    };
  };
  apns: {
    headers: Record<string, string>;
    payload: { aps: Record<string, unknown> };
  };
}

/**
 * The push message for [notice]. Alarms are high priority on the Android
 * alarm channel (max importance, alarm audio, created by the app) and
 * time-sensitive on iOS (breaks through Focus when allowed).
 */
export function buildMessage(
  notice: Notice,
  watchId: string,
  w: WatchView,
  now: Date = new Date(),
): PushMessage {
  const data: Record<string, string> = {
    type: 'anchorWatch',
    kind: notice.kind,
    watchId,
    state: String(w.state ?? ''),
    reason: notice.kind === 'alarm' ? notice.reason : '',
    distanceM: w.distanceM == null ? '' : String(Math.round(w.distanceM)),
    boatName: boat(w),
  };
  let title: string;
  let body: string;
  let urgent = false;
  let channel = CHANNEL_INFO;
  switch (notice.kind) {
    case 'alarm': {
      ({ title, body } = alarmText(notice.reason, w));
      urgent = true;
      channel = CHANNEL_ALARM;
      break;
    }
    case 'lostContact': {
      const at = w.updatedAt ? formatClock(w.updatedAt, w.tzOffsetMin) : null;
      title = `Lost contact with ${boat(w)}`;
      body = at
        ? `Last update ${at}. The phone on board may be offline or switched off.`
        : 'The phone on board may be offline or switched off.';
      urgent = true;
      channel = CHANNEL_WARNING;
      if (w.updatedAt) data.lastUpdate = String(w.updatedAt.getTime());
      break;
    }
    case 'contactRestored':
      title = `Back in contact with ${boat(w)}`;
      body = 'The boat is sending updates again.';
      break;
    case 'ended':
      title = `Anchor watch ended on ${boat(w)}`;
      body = 'The boat stopped sharing its anchor watch.';
      break;
  }
  data.sentAt = String(now.getTime());

  const androidNotification: PushMessage['android']['notification'] = {
    channelId: channel,
    tag: `${watchId}-${notice.kind}`,
    priority: notice.kind === 'alarm' ? 'max' : urgent ? 'high' : 'default',
    visibility: 'public',
  };
  const aps: Record<string, unknown> = {
    threadId: watchId,
    'interruption-level': urgent ? 'time-sensitive' : 'active',
    // Critical alerts (sound through mute / Do Not Disturb) need the
    // com.apple.developer.usernotifications.critical-alerts entitlement,
    // which Apple grants on request. With it, use for alarms instead:
    //   sound: { critical: true, name: 'default', volume: 1.0 },
    //   'interruption-level': 'critical',
  };
  if (urgent) {
    androidNotification.sound = 'default';
    androidNotification.defaultVibrateTimings = true;
    aps.sound = 'default';
  }

  return {
    notification: { title, body },
    data,
    android: {
      priority: urgent ? 'high' : 'normal',
      collapseKey: `${watchId}-${notice.kind}`,
      notification: androidNotification,
    },
    apns: {
      headers: {
        'apns-priority': urgent ? '10' : '5',
        'apns-push-type': 'alert',
        'apns-collapse-id': `${watchId}-${notice.kind}`.slice(0, 64),
      },
      payload: { aps },
    },
  };
}

/** FCM error codes meaning the token will never work again. */
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

export interface SendResult {
  success: boolean;
  errorCode?: string;
}

/** Tokens to delete, from per-token send results (same order as [tokens]). */
export function deadTokens(tokens: readonly string[], results: readonly SendResult[]): string[] {
  const dead: string[] = [];
  results.forEach((r, i) => {
    if (!r.success && r.errorCode && DEAD_TOKEN_CODES.has(r.errorCode) && tokens[i]) {
      dead.push(tokens[i]);
    }
  });
  return dead;
}

/** One watcher document: who to remove a dead token from. */
export interface WatcherTokens {
  uid: string;
  tokens: string[];
}

/** Unique tokens across watchers (a device that joined twice gets one push). */
export function collectTokens(watchers: readonly WatcherTokens[]): string[] {
  return [...new Set(watchers.flatMap((w) => w.tokens.filter((t) => typeof t === 'string' && t.length > 0)))];
}
