/**
 * Firestore + FCM side of the functions. Everything takes the Firestore
 * instance and a [Sender] so the emulator tests can run it directly.
 */
import { FieldValue, Firestore, Timestamp } from 'firebase-admin/firestore';
import type { Messaging } from 'firebase-admin/messaging';

import {
  buildMessage,
  collectTokens,
  deadTokens,
  Notice,
  noticesForUpdate,
  PushMessage,
  SendResult,
  staleDecision,
  WatchView,
  WatcherTokens,
} from './logic';

export const WATCHES = 'watches';
export const WATCHERS = 'watchers';
/** Emulator only: where [outboxSender] records the messages it "sends". */
export const OUTBOX = 'emulatorOutbox';

export interface Sender {
  /** Sends [message] to each token; one result per token, same order. */
  send(message: PushMessage, tokens: string[]): Promise<SendResult[]>;
}

/** Real FCM via the Admin SDK (HTTP v1, one request per token). */
export function fcmSender(messaging: Messaging): Sender {
  return {
    async send(message, tokens) {
      if (tokens.length === 0) return [];
      const res = await messaging.sendEachForMulticast({ ...message, tokens });
      return res.responses.map((r) => ({ success: r.success, errorCode: r.error?.code }));
    },
  };
}

/**
 * Emulator stand-in for FCM (the emulator suite has no messaging emulator):
 * writes each message to `emulatorOutbox`. Tokens starting with `dead-`
 * fail as unregistered so token clean-up can be tested.
 */
export function outboxSender(db: Firestore): Sender {
  return {
    async send(message, tokens) {
      const results: SendResult[] = [];
      for (const token of tokens) {
        if (token.startsWith('dead-')) {
          results.push({ success: false, errorCode: 'messaging/registration-token-not-registered' });
          continue;
        }
        await db.collection(OUTBOX).add({ token, message, at: FieldValue.serverTimestamp() });
        results.push({ success: true });
      }
      return results;
    },
  };
}

function toDate(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  return null;
}

/** Firestore data → the plain view the decision code works on. */
export function toView(data: FirebaseFirestore.DocumentData | undefined): WatchView {
  const d = data ?? {};
  return {
    boatName: typeof d.boatName === 'string' ? d.boatName : null,
    state: typeof d.state === 'string' ? d.state : null,
    reasons: Array.isArray(d.reasons) ? d.reasons.filter((r: unknown) => typeof r === 'string') : [],
    ringing: d.ringing === true,
    distanceM: typeof d.distanceM === 'number' ? d.distanceM : null,
    radiusM: typeof d.radiusM === 'number' ? d.radiusM : null,
    updatedAt: toDate(d.updatedAt),
    endedAt: toDate(d.endedAt),
    lostContactNotifiedAt: toDate(d.lostContactNotifiedAt),
    tzOffsetMin: typeof d.tzOffsetMin === 'number' ? d.tzOffsetMin : null,
  };
}

/** Sends [notice] to every watcher of [watchId]; removes dead tokens. Returns tokens sent to. */
export async function notifyWatchers(
  db: Firestore,
  sender: Sender,
  watchId: string,
  watch: WatchView,
  notice: Notice,
  now: Date = new Date(),
): Promise<number> {
  const watchRef = db.collection(WATCHES).doc(watchId);
  const snap = await watchRef.collection(WATCHERS).get();
  const watchers: WatcherTokens[] = snap.docs.map((d) => ({
    uid: d.id,
    tokens: Array.isArray(d.get('fcmTokens')) ? (d.get('fcmTokens') as unknown[]).filter((t): t is string => typeof t === 'string') : [],
  }));
  const tokens = collectTokens(watchers);
  if (tokens.length === 0) return 0;

  const results = await sender.send(buildMessage(notice, watchId, watch, now), tokens);
  const dead = deadTokens(tokens, results);
  if (dead.length > 0) {
    const batch = db.batch();
    for (const w of watchers) {
      const remove = w.tokens.filter((t) => dead.includes(t));
      if (remove.length > 0) {
        batch.update(watchRef.collection(WATCHERS).doc(w.uid), {
          fcmTokens: FieldValue.arrayRemove(...remove),
        });
      }
    }
    await batch.commit();
  }
  return tokens.length;
}

/** onDocumentUpdated('watches/{watchId}') body. Returns the notices sent. */
export async function handleWatchUpdate(
  db: Firestore,
  sender: Sender,
  watchId: string,
  beforeData: FirebaseFirestore.DocumentData | undefined,
  afterData: FirebaseFirestore.DocumentData | undefined,
  now: Date = new Date(),
): Promise<Notice[]> {
  if (!afterData) return [];
  const before = toView(beforeData);
  const after = toView(afterData);
  const sent: Notice[] = [];
  for (const notice of noticesForUpdate(before, after)) {
    if (notice.kind === 'contactRestored') {
      // Clear the flag; only the update that actually clears it notifies.
      const ref = db.collection(WATCHES).doc(watchId);
      const cleared = await db.runTransaction(async (t) => {
        const cur = await t.get(ref);
        if (cur.get('lostContactNotifiedAt') == null) return false;
        t.update(ref, { lostContactNotifiedAt: null });
        return true;
      });
      if (!cleared) continue;
    }
    await notifyWatchers(db, sender, watchId, after, notice, now);
    sent.push(notice);
  }
  return sent;
}

/**
 * Scheduled check: active watches whose last update is older than 3 minutes
 * get one "Lost contact" push (marked with `lostContactNotifiedAt`); watches
 * silent for 48 h are ended. Returns the ids notified and abandoned.
 */
export async function checkStaleWatches(
  db: Firestore,
  sender: Sender,
  now: Date = new Date(),
): Promise<{ notified: string[]; abandoned: string[] }> {
  const cutoff = Timestamp.fromMillis(now.getTime() - 3 * 60 * 1000);
  const stale = await db
    .collection(WATCHES)
    .where('endedAt', '==', null)
    .where('updatedAt', '<', cutoff)
    .get();
  const notified: string[] = [];
  const abandoned: string[] = [];
  for (const doc of stale.docs) {
    // Decide again inside a transaction so overlapping runs notify once and
    // a boat that just came back is not reported lost.
    const decision = await db.runTransaction(async (t) => {
      const cur = await t.get(doc.ref);
      const view = toView(cur.data());
      const d = staleDecision(view, now);
      if (d === 'notify') {
        t.update(doc.ref, { lostContactNotifiedAt: Timestamp.fromDate(now) });
      } else if (d === 'abandon') {
        t.update(doc.ref, {
          endedAt: cur.get('updatedAt') ?? Timestamp.fromDate(now),
          ringing: false,
          endedReason: 'abandoned',
        });
      }
      return { d, view };
    });
    if (decision.d === 'notify') {
      await notifyWatchers(db, sender, doc.id, decision.view, { kind: 'lostContact' }, now);
      notified.push(doc.id);
    } else if (decision.d === 'abandon') {
      abandoned.push(doc.id);
    }
  }
  return { notified, abandoned };
}
