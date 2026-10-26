import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  endReasonAt,
  InvalidTripEndData,
  shouldClearLocations,
  tripEndInputFromData,
} from "./tripEnd";

initializeApp();

const REGION = "asia-east1";

/**
 * Deletes every 找人地圖 snapshot under the trip. Admin SDK bypasses rules
 * so one member's pin cannot block cleanup. Idempotent.
 */
async function clearMemberLocations(db: Firestore, tripId: string): Promise<number> {
  const snap = await db.collection("trips").doc(tripId).collection("locations").get();
  let batch = db.batch();
  let ops = 0;
  let total = 0;
  for (const location of snap.docs) {
    batch.delete(location.ref);
    ops += 1;
    total += 1;
    if (ops === 400) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
  return total;
}

/**
 * Every five minutes, re-read each open trip and end it when the current
 * `expectedReturnAt` (or, if unset, endDate 23:59 in `timeZone`) has passed.
 * Changing 預計回程時間 needs no separate scheduler job: the next run sees
 * the new value. `planning` and `active` both end so location pins cannot
 * outlive the trip.
 */
export const endExpiredTrips = onSchedule(
  {
    schedule: "every 5 minutes",
    region: REGION,
    timeZone: "UTC",
    timeoutSeconds: 120,
    memory: "256MiB",
    retryCount: 0,
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const open = await db.collection("trips").where("status", "in", ["planning", "active"]).get();
    for (const trip of open.docs) {
      try {
        const ended = await db.runTransaction(async (tx) => {
          const fresh = await tx.get(trip.ref);
          const data = fresh.data();
          if (!data) return false;
          let reason;
          try {
            reason = endReasonAt(tripEndInputFromData(data), now);
          } catch (error) {
            if (error instanceof InvalidTripEndData) {
              logger.error("skip trip with unreadable end fields", {
                tripId: trip.id,
                message: error.message,
              });
              return false;
            }
            throw error;
          }
          if (!reason) return false;
          tx.update(trip.ref, {
            status: "ended",
            endReason: reason,
            endedAt: now,
            updatedAt: FieldValue.serverTimestamp(),
          });
          return true;
        });
        if (!ended) continue;
        const removed = await clearMemberLocations(db, trip.id);
        logger.info("trip ended", { tripId: trip.id, removed });
      } catch (error) {
        logger.error("failed to end trip", { tripId: trip.id, error });
      }
    }
  },
);

/** Manual end (leader/deputy) and the scheduled end both land here. */
export const clearLocationsWhenTripEnds = onDocumentUpdated(
  {
    document: "trips/{tripId}",
    region: REGION,
  },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;
    if (!shouldClearLocations(before.get("status"), after.get("status"))) return;
    const db = getFirestore();
    const removed = await clearMemberLocations(db, event.params.tripId);
    logger.info("cleared locations after end", { tripId: event.params.tripId, removed });
  },
);
