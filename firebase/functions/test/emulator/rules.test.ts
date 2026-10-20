/**
 * Security rules tests (Firestore emulator). Run with `npm run test:emulator`.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

const PROJECT = 'demo-anchor-alarm';
const KEY = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'; // 26 base32 chars
const KEY2 = '234567ABCDEFGHIJKLMNOPQRST';
const now = () => firebase.firestore.FieldValue.serverTimestamp();
const ts = (ms: number) => firebase.firestore.Timestamp.fromMillis(ms);

let env: RulesTestEnvironment;

function watch(owner: string, extra: Record<string, unknown> = {}) {
  return {
    ownerUid: owner,
    shareKey: KEY,
    boatName: 'Kestrel',
    anchor: { lat: 43.5, lon: 16.4 },
    radiusM: 50,
    warningRadiusM: 45,
    boat: { lat: 43.5001, lon: 16.4001, accuracyM: 5 },
    state: 'safe',
    reasons: [],
    ringing: false,
    snoozedUntil: null,
    distanceM: 12,
    updatedAt: now(),
    startedAt: ts(Date.parse('2026-10-20T10:00:00Z')),
    endedAt: null,
    appVersion: '1.0.0+1',
    tzOffsetMin: 120,
    ...extra,
  };
}

function watcher(key = KEY, extra: Record<string, unknown> = {}) {
  return { key, fcmTokens: ['tok-1'], platform: 'android', addedAt: now(), name: 'Phone', ...extra };
}

const db = (uid?: string) =>
  (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

async function seedWatch(id = 'w1', owner = 'owner') {
  await assertSucceeds(db(owner).collection('watches').doc(id).set(watch(owner)));
}

async function join(id = 'w1', uid = 'alice', key = KEY) {
  return db(uid).collection('watches').doc(id).collection('watchers').doc(uid).set(watcher(key));
}

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync(resolve(__dirname, '../../../firestore.rules'), 'utf8') },
  });
});

afterAll(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

describe('watches', () => {
  it('owner creates a valid watch', async () => {
    await seedWatch();
  });

  it('rejects a watch for someone else, unauthenticated or malformed', async () => {
    const ref = (uid?: string) => db(uid).collection('watches').doc('w1');
    await assertFails(ref('mallory').set(watch('owner')));
    await assertFails(ref().set(watch('owner')));
    await assertFails(ref('owner').set(watch('owner', { shareKey: 'short' })));
    await assertFails(ref('owner').set(watch('owner', { shareKey: KEY.toLowerCase() })));
    await assertFails(ref('owner').set(watch('owner', { extra: 1 })));
    await assertFails(ref('owner').set(watch('owner', { updatedAt: ts(Date.now()) })));
    await assertFails(ref('owner').set(watch('owner', { anchor: { lat: 91, lon: 0 } })));
    await assertFails(ref('owner').set(watch('owner', { state: 'panic' })));
    await assertFails(ref('owner').set(watch('owner', { reasons: ['drag', 'aliens'] })));
    await assertFails(ref('owner').set(watch('owner', { radiusM: 'big' })));
    await assertFails(ref('owner').set(watch('owner', { warningRadiusM: 60 })));
    await assertFails(ref('owner').set(watch('owner', { boatName: 'x'.repeat(61) })));
    await assertFails(ref('owner').set(watch('owner', { lostContactNotifiedAt: null })));
  });

  it('only the owner and current watchers can read; nobody can list', async () => {
    await seedWatch();
    await assertSucceeds(db('owner').collection('watches').doc('w1').get());
    await assertFails(db('mallory').collection('watches').doc('w1').get());
    await assertFails(db().collection('watches').doc('w1').get());
    await assertFails(db('owner').collection('watches').get());
    await assertSucceeds(join());
    await assertSucceeds(db('alice').collection('watches').doc('w1').get());
    await assertFails(db('alice').collection('watches').get());
  });

  it('owner updates; watchers and strangers cannot', async () => {
    await seedWatch();
    await assertSucceeds(join());
    const upd = { state: 'alarm', reasons: ['drag'], ringing: true, updatedAt: now() };
    await assertSucceeds(db('owner').collection('watches').doc('w1').update(upd));
    await assertFails(db('alice').collection('watches').doc('w1').update(upd));
    await assertFails(db('mallory').collection('watches').doc('w1').update(upd));
  });

  it('owner cannot touch server fields or hand the watch over', async () => {
    await seedWatch();
    const ref = db('owner').collection('watches').doc('w1');
    await assertFails(ref.update({ lostContactNotifiedAt: ts(Date.now()), updatedAt: now() }));
    await assertFails(ref.update({ ownerUid: 'other', updatedAt: now() }));
    await assertFails(ref.update({ state: 'safe' })); // updatedAt must be the server time
  });

  it('only the owner deletes', async () => {
    await seedWatch();
    await assertSucceeds(join());
    await assertFails(db('alice').collection('watches').doc('w1').delete());
    await assertFails(db('mallory').collection('watches').doc('w1').delete());
    await assertSucceeds(db('owner').collection('watches').doc('w1').delete());
  });
});

describe('write shapes used by the app (FirestoreRemoteStore)', () => {
  it('first publish without a fix, merge updates, and "Stop sharing"', async () => {
    const ref = db('owner').collection('watches').doc('w1');
    // RemoteWatchWrite.toFields() before the first fix + server updatedAt, set(merge).
    await assertSucceeds(ref.set(watch('owner', { boat: null, distanceM: null, snoozedUntil: null }), { merge: true }));
    // Every later publish: the full field set again, merged.
    await assertSucceeds(ref.set(watch('owner', {
      state: 'alarm', reasons: ['drag', 'gpsPoor'], ringing: true,
      snoozedUntil: ts(Date.now() + 120_000), distanceM: 61.5,
    }), { merge: true }));
    // Ending the watch.
    await assertSucceeds(ref.set(watch('owner', { endedAt: ts(Date.now()), state: 'inactive', ringing: false }), { merge: true }));
    // Stop sharing: rotate key + end in one update.
    await assertSucceeds(ref.update({
      shareKey: KEY2, endedAt: ts(Date.now()), ringing: false, state: 'inactive', reasons: [], updatedAt: now(),
    }));
  });

  it('merge publishes still work after the server marked lost contact', async () => {
    await seedWatch();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('watches').doc('w1').update({ lostContactNotifiedAt: ts(Date.now()) });
    });
    await assertSucceeds(
      db('owner').collection('watches').doc('w1').set(watch('owner', { distanceM: 20 }), { merge: true }),
    );
  });

  it('watcher join without a push token or name', async () => {
    await seedWatch();
    await assertSucceeds(
      db('alice').collection('watches').doc('w1').collection('watchers').doc('alice')
        .set({ key: KEY, fcmTokens: [], platform: 'web', addedAt: now() }),
    );
  });
});

describe('watchers', () => {
  it('joins only with the current share key, only for yourself', async () => {
    await seedWatch();
    await assertFails(join('w1', 'alice', KEY2));
    await assertFails(
      db('alice').collection('watches').doc('w1').collection('watchers').doc('bob').set(watcher()),
    );
    await assertFails(join('nope', 'alice'));
    await assertFails(
      db('alice').collection('watches').doc('w1').collection('watchers').doc('alice')
        .set(watcher(KEY, { fcmTokens: Array.from({ length: 11 }, (_, i) => `t${i}`) })),
    );
    await assertFails(
      db('alice').collection('watches').doc('w1').collection('watchers').doc('alice')
        .set(watcher(KEY, { platform: 'toaster' })),
    );
    await assertSucceeds(join());
  });

  it('rotating the share key locks out existing watchers', async () => {
    await seedWatch();
    await assertSucceeds(join());
    await assertSucceeds(
      db('owner').collection('watches').doc('w1').update({ shareKey: KEY2, updatedAt: now() }),
    );
    await assertFails(db('alice').collection('watches').doc('w1').get());
    await assertSucceeds(join('w1', 'bob', KEY2));
    await assertSucceeds(db('bob').collection('watches').doc('w1').get());
  });

  it('a watcher updates only its own push tokens', async () => {
    await seedWatch();
    await assertSucceeds(join());
    await assertSucceeds(join('w1', 'bob'));
    const mine = db('alice').collection('watches').doc('w1').collection('watchers').doc('alice');
    await assertSucceeds(mine.update({ fcmTokens: ['tok-2'] }));
    await assertFails(mine.update({ key: KEY2 }));
    await assertFails(mine.update({ name: 'Renamed' }));
    const bobs = db('alice').collection('watches').doc('w1').collection('watchers').doc('bob');
    await assertFails(bobs.update({ fcmTokens: ['evil'] }));
    await assertFails(bobs.get());
  });

  it('owner lists and removes watchers; a watcher can leave; strangers see nothing', async () => {
    await seedWatch();
    await assertSucceeds(join());
    await assertSucceeds(db('owner').collection('watches').doc('w1').collection('watchers').get());
    await assertFails(db('alice').collection('watches').doc('w1').collection('watchers').get());
    await assertFails(db('mallory').collection('watches').doc('w1').collection('watchers').get());
    await assertSucceeds(
      db('alice').collection('watches').doc('w1').collection('watchers').doc('alice').delete(),
    );
    await assertSucceeds(join('w1', 'bob'));
    await assertSucceeds(
      db('owner').collection('watches').doc('w1').collection('watchers').doc('bob').delete(),
    );
  });
});

describe('other collections', () => {
  it('are closed', async () => {
    await assertFails(db('alice').collection('emulatorOutbox').get());
    await assertFails(db('alice').collection('users').doc('alice').set({ a: 1 }));
  });
});
