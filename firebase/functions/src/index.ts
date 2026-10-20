/**
 * Anchor Alarm remote monitoring — Cloud Functions (2nd gen).
 *
 * - onWatchUpdated: pushes alarms (drag, GPS lost, critical battery), "watch
 *   ended" and "contact restored" to everyone monitoring the watch.
 * - checkLostContact: every 5 minutes, pushes "Lost contact" once for active
 *   watches that stopped updating, and ends watches silent for 48 h.
 *
 * Region must match the Firestore database location (see FIREBASE_SETUP.md).
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';

import { checkStaleWatches, fcmSender, handleWatchUpdate, outboxSender, Sender } from './notify';

export const REGION = 'europe-west1';

setGlobalOptions({ region: REGION, maxInstances: 10 });

initializeApp();

let sender: Sender | undefined;
function getSender(): Sender {
  // The emulator suite has no FCM emulator; record messages instead.
  sender ??= process.env.FUNCTIONS_EMULATOR === 'true'
    ? outboxSender(getFirestore())
    : fcmSender(getMessaging());
  return sender;
}

export const onWatchUpdated = onDocumentUpdated('watches/{watchId}', async (event) => {
  const change = event.data;
  if (!change) return;
  const sent = await handleWatchUpdate(
    getFirestore(),
    getSender(),
    event.params.watchId,
    change.before.data(),
    change.after.data(),
  );
  if (sent.length > 0) {
    logger.info('watch notices sent', { watchId: event.params.watchId, notices: sent });
  }
});

export const checkLostContact = onSchedule(
  { schedule: 'every 5 minutes', timeZone: 'Etc/UTC', retryCount: 0 },
  async () => {
    const res = await checkStaleWatches(getFirestore(), getSender());
    if (res.notified.length > 0 || res.abandoned.length > 0) {
      logger.info('lost-contact check', res);
    }
  },
);
