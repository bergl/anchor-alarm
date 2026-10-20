import { describe, expect, it } from 'vitest';

import {
  ABANDONED_AFTER_MS,
  buildMessage,
  collectTokens,
  deadTokens,
  formatClock,
  LOST_CONTACT_AFTER_MS,
  mostImportant,
  noticesForUpdate,
  staleDecision,
  WatchView,
} from '../../src/logic';

const t0 = new Date('2026-10-20T12:00:00Z');
const at = (ms: number) => new Date(t0.getTime() + ms);

const safe: WatchView = {
  boatName: 'Kestrel',
  state: 'safe',
  reasons: [],
  ringing: false,
  distanceM: 30,
  radiusM: 50,
  updatedAt: t0,
  endedAt: null,
};

describe('noticesForUpdate', () => {
  it('notifies when ringing starts', () => {
    const after = { ...safe, state: 'alarm', reasons: ['drag'], ringing: true, updatedAt: at(5000) };
    expect(noticesForUpdate(safe, after)).toEqual([{ kind: 'alarm', reason: 'drag' }]);
  });

  it('notifies a new alarm reason while already ringing', () => {
    const ringing = { ...safe, state: 'alarm', reasons: ['drag'], ringing: true };
    const after = { ...ringing, reasons: ['drag', 'gpsLost'], updatedAt: at(5000) };
    expect(noticesForUpdate(ringing, after)).toEqual([{ kind: 'alarm', reason: 'gpsLost' }]);
  });

  it('notifies a new alarm reason while snoozed (not ringing)', () => {
    const snoozed = { ...safe, state: 'alarm', reasons: ['drag'], ringing: false };
    const after = { ...snoozed, reasons: ['drag', 'criticalBattery'] };
    expect(noticesForUpdate(snoozed, after)).toEqual([{ kind: 'alarm', reason: 'criticalBattery' }]);
  });

  it('does not repeat while the same alarm keeps ringing', () => {
    const ringing = { ...safe, state: 'alarm', reasons: ['drag'], ringing: true };
    expect(noticesForUpdate(ringing, { ...ringing, distanceM: 80, updatedAt: at(5000) })).toEqual([]);
  });

  it('re-notifies when the alarm rings again after a snooze', () => {
    const snoozed = { ...safe, state: 'alarm', reasons: ['drag'], ringing: false };
    expect(noticesForUpdate(snoozed, { ...snoozed, ringing: true })).toEqual([
      { kind: 'alarm', reason: 'drag' },
    ]);
  });

  it('ignores warnings', () => {
    const after = { ...safe, state: 'warning', reasons: ['nearEdge', 'gpsPoor', 'lowBattery'] };
    expect(noticesForUpdate(safe, after)).toEqual([]);
  });

  it('notifies the end of the watch, and nothing else', () => {
    const after = { ...safe, ringing: true, reasons: ['drag'], endedAt: at(1000) };
    expect(noticesForUpdate(safe, after)).toEqual([{ kind: 'ended' }]);
  });

  it('is silent for updates of an ended watch', () => {
    const ended = { ...safe, endedAt: t0 };
    expect(noticesForUpdate(ended, { ...ended, ringing: true, reasons: ['drag'] })).toEqual([]);
  });

  it('reports contact restored when the boat writes after a lost-contact notice', () => {
    const lost = { ...safe, lostContactNotifiedAt: at(4 * 60_000) };
    const after = { ...lost, updatedAt: at(10 * 60_000) };
    expect(noticesForUpdate(lost, after)).toEqual([{ kind: 'contactRestored' }]);
  });

  it('does not report contact restored for the server marking lost contact', () => {
    const before = { ...safe };
    const after = { ...safe, lostContactNotifiedAt: at(4 * 60_000) };
    expect(noticesForUpdate(before, after)).toEqual([]);
  });
});

describe('staleDecision', () => {
  it('is none while fresh', () => {
    expect(staleDecision(safe, at(LOST_CONTACT_AFTER_MS - 1))).toBe('none');
  });
  it('notifies once after 3 minutes', () => {
    expect(staleDecision(safe, at(LOST_CONTACT_AFTER_MS))).toBe('notify');
    const notified = { ...safe, lostContactNotifiedAt: at(LOST_CONTACT_AFTER_MS) };
    expect(staleDecision(notified, at(30 * 60_000))).toBe('none');
  });
  it('notifies again after the boat came back and went silent again', () => {
    const w = { ...safe, updatedAt: at(10 * 60_000), lostContactNotifiedAt: at(4 * 60_000) };
    expect(staleDecision(w, at(14 * 60_000))).toBe('notify');
  });
  it('abandons after 48 h', () => {
    expect(staleDecision(safe, at(ABANDONED_AFTER_MS))).toBe('abandon');
  });
  it('ignores ended watches', () => {
    expect(staleDecision({ ...safe, endedAt: t0 }, at(ABANDONED_AFTER_MS))).toBe('none');
  });
});

describe('buildMessage', () => {
  it('builds a high-priority alarm on the anchor_alarm channel, time-sensitive on iOS', () => {
    const w = { ...safe, state: 'alarm', reasons: ['drag'], ringing: true, distanceM: 62.4 };
    const m = buildMessage({ kind: 'alarm', reason: 'drag' }, 'w1', w, t0);
    expect(m.notification.title).toBe('Anchor alarm: Kestrel is dragging');
    expect(m.notification.body).toBe('62 m from the anchor (alarm at 50 m).');
    expect(m.android.priority).toBe('high');
    expect(m.android.notification.channelId).toBe('anchor_alarm');
    expect(m.android.notification.sound).toBe('default');
    expect(m.apns.headers['apns-priority']).toBe('10');
    expect(m.apns.payload.aps['interruption-level']).toBe('time-sensitive');
    expect(m.apns.payload.aps.sound).toBe('default');
    expect(m.data).toMatchObject({
      watchId: 'w1',
      state: 'alarm',
      reason: 'drag',
      distanceM: '62',
      kind: 'alarm',
    });
    for (const v of Object.values(m.data)) expect(typeof v).toBe('string');
  });

  it('builds a lost-contact message with the boat-local time', () => {
    const w = { ...safe, updatedAt: new Date('2026-10-20T12:05:00Z'), tzOffsetMin: 120 };
    const m = buildMessage({ kind: 'lostContact' }, 'w1', w, t0);
    expect(m.notification.title).toBe('Lost contact with Kestrel');
    expect(m.notification.body).toContain('Last update 14:05');
    expect(m.android.priority).toBe('high');
  });

  it('builds a normal-priority "ended" message without sound', () => {
    const m = buildMessage({ kind: 'ended' }, 'w1', { ...safe, boatName: '' }, t0);
    expect(m.notification.title).toBe('Anchor watch ended on your boat');
    expect(m.android.priority).toBe('normal');
    expect(m.android.notification.sound).toBeUndefined();
    expect(m.android.notification.channelId).toBe('anchor_info');
    expect(m.apns.payload.aps.sound).toBeUndefined();
  });
});

describe('tokens', () => {
  it('finds unregistered and invalid tokens only', () => {
    expect(
      deadTokens(['a', 'b', 'c', 'd'], [
        { success: true },
        { success: false, errorCode: 'messaging/registration-token-not-registered' },
        { success: false, errorCode: 'messaging/internal-error' },
        { success: false, errorCode: 'messaging/invalid-registration-token' },
      ]),
    ).toEqual(['b', 'd']);
  });

  it('dedupes tokens across watchers', () => {
    expect(collectTokens([{ uid: 'u1', tokens: ['a', 'b'] }, { uid: 'u2', tokens: ['b', ''] }])).toEqual(['a', 'b']);
  });
});

describe('helpers', () => {
  it('formats the clock with an offset', () => {
    expect(formatClock(new Date('2026-10-20T23:30:00Z'), 90)).toBe('01:00');
    expect(formatClock(new Date('2026-10-20T23:30:00Z'))).toBe('23:30');
  });
  it('orders alarm reasons by importance', () => {
    expect(mostImportant(['criticalBattery', 'drag'])).toBe('drag');
    expect(mostImportant(['criticalBattery', 'gpsLost'])).toBe('gpsLost');
  });
});
