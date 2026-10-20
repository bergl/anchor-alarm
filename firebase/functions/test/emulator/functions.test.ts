/**
 * Functions integration tests against the emulator suite: the Firestore
 * trigger runs in the Functions emulator (FCM is replaced by the outbox
 * sender there), the scheduled check is called directly.
 * Run with `npm run test:emulator`.
 */
import { deleteApp, getApps, initializeApp } from 'firebase-admin/app';
import { Firestore, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import { PushMessage, SendResult } from '../../src/logic';
import { checkStaleWatches, OUTBOX, Sender } from '../../src/notify';

const PROJECT = 'demo-anchor-alarm';
const KEY = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
let db: Firestore;

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('Run via `npm run test:emulator` (needs the Firestore emulator).');
  }
  db = getFirestore(initializeApp({ projectId: PROJECT }, 'functions-test'));
});

afterAll(async () => {
  await Promise.all(getApps().map((a) => deleteApp(a)));
});

async function clear() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  await fetch(`http://${host}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, {
    method: 'DELETE',
  });
}

beforeEach(clear);

function watchDoc(extra: Record<string, unknown> = {}) {
  return {
    ownerUid: 'owner',
    shareKey: KEY,
    boatName: 'Kestrel',
    anchor: { lat: 43.5, lon: 16.4 },
    radiusM: 50,
    warningRadiusM: 45,
    boat: { lat: 43.5001, lon: 16.4001, accuracyM: 5 },
    state: 'safe',
    reasons: [],
    ringing: false,
    distanceM: 12,
    updatedAt: Timestamp.now(),
    startedAt: Timestamp.now(),
    endedAt: null,
    tzOffsetMin: 0,
    ...extra,
  };
}

async function seed(id: string, extra: Record<string, unknown> = {}, tokens = ['tok-a', 'dead-b']) {
  const ref = db.collection('watches').doc(id);
  await ref.set(watchDoc(extra));
  await ref.collection('watchers').doc('alice').set({
    key: KEY,
    fcmTokens: tokens,
    platform: 'android',
    addedAt: Timestamp.now(),
  });
  return ref;
}

async function waitFor<T>(f: () => Promise<T | undefined>, timeoutMs = 20_000): Promise<T> {
  const end = Date.now() + timeoutMs;
  for (;;) {
    const v = await f();
    if (v !== undefined) return v;
    if (Date.now() > end) throw new Error('timed out');
    await new Promise((r) => setTimeout(r, 250));
  }
}

async function outbox(watchId: string, kind: string) {
  const s = await db.collection(OUTBOX).get();
  return s.docs
    .map((d) => d.data() as { token: string; message: PushMessage })
    .filter((m) => m.message.data.watchId === watchId && m.message.data.kind === kind);
}

class RecordingSender implements Sender {
  sent: { message: PushMessage; tokens: string[] }[] = [];
  async send(message: PushMessage, tokens: string[]): Promise<SendResult[]> {
    this.sent.push({ message, tokens });
    return tokens.map(() => ({ success: true }));
  }
}

describe('onWatchUpdated (functions emulator)', () => {
  it('pushes the alarm to watchers and removes dead tokens', async () => {
    const ref = await seed('t-alarm');
    await ref.update({ state: 'alarm', reasons: ['drag'], ringing: true, distanceM: 63, updatedAt: Timestamp.now() });
    const msgs = await waitFor(async () => {
      const m = await outbox('t-alarm', 'alarm');
      return m.length > 0 ? m : undefined;
    });
    expect(msgs.map((m) => m.token)).toEqual(['tok-a']);
    const m = msgs[0].message;
    expect(m.data.reason).toBe('drag');
    expect(m.data.distanceM).toBe('63');
    expect(m.android.priority).toBe('high');
    expect(m.android.notification.channelId).toBe('anchor_alarm');
    expect(m.apns.payload.aps['interruption-level']).toBe('time-sensitive');
    await waitFor(async () => {
      const w = await ref.collection('watchers').doc('alice').get();
      return (w.get('fcmTokens') as string[]).includes('dead-b') ? undefined : true;
    });
  });

  it('does not push warnings or repeated updates of the same alarm', async () => {
    const ref = await seed('t-quiet', {}, ['tok-q']);
    await ref.update({ state: 'warning', reasons: ['nearEdge'], updatedAt: Timestamp.now() });
    await ref.update({ distanceM: 47, updatedAt: Timestamp.now() });
    // An "ended" afterwards proves the trigger ran; nothing else may be there.
    await ref.update({ endedAt: Timestamp.now(), updatedAt: Timestamp.now() });
    await waitFor(async () => ((await outbox('t-quiet', 'ended')).length > 0 ? true : undefined));
    expect(await outbox('t-quiet', 'alarm')).toEqual([]);
  });

  it('reports contact restored once and clears the flag', async () => {
    const ref = await seed('t-restore', {
      updatedAt: Timestamp.fromMillis(Date.now() - 10 * 60_000),
      lostContactNotifiedAt: Timestamp.fromMillis(Date.now() - 5 * 60_000),
    }, ['tok-r']);
    await ref.update({ updatedAt: Timestamp.now(), distanceM: 13 });
    await waitFor(async () => ((await outbox('t-restore', 'contactRestored')).length > 0 ? true : undefined));
    await waitFor(async () => ((await ref.get()).get('lostContactNotifiedAt') == null ? true : undefined));
    expect(await outbox('t-restore', 'contactRestored')).toHaveLength(1);
  });
});

describe('checkStaleWatches (Firestore emulator)', () => {
  it('notifies lost contact once, ignores fresh and ended watches, ends abandoned ones', async () => {
    const now = new Date();
    const ago = (min: number) => Timestamp.fromMillis(now.getTime() - min * 60_000);
    await seed('t-stale', { updatedAt: ago(5) }, ['tok-s']);
    await seed('t-fresh', { updatedAt: ago(1) }, ['tok-f']);
    await seed('t-ended', { updatedAt: ago(30), endedAt: ago(29) }, ['tok-e']);
    await seed('t-old', { updatedAt: ago(49 * 60) }, ['tok-o']);

    const sender = new RecordingSender();
    const res = await checkStaleWatches(db, sender, now);
    expect(res.notified).toEqual(['t-stale']);
    expect(res.abandoned).toEqual(['t-old']);
    expect(sender.sent).toHaveLength(1);
    expect(sender.sent[0].tokens).toEqual(['tok-s']);
    expect(sender.sent[0].message.notification.title).toBe('Lost contact with Kestrel');

    const stale = await db.collection('watches').doc('t-stale').get();
    expect(stale.get('lostContactNotifiedAt')).toBeInstanceOf(Timestamp);
    const old = await db.collection('watches').doc('t-old').get();
    expect(old.get('endedAt')).toBeInstanceOf(Timestamp);
    expect(old.get('endedReason')).toBe('abandoned');

    // A minute later: t-stale was already reported, t-fresh is still fresh.
    const again = await checkStaleWatches(db, sender, new Date(now.getTime() + 60_000));
    expect(again.notified).toEqual([]);
    expect(sender.sent).toHaveLength(1);
  });
});
