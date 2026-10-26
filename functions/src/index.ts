import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type DocumentData, type Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentUpdated, onDocumentWrittenWithAuthContext } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { applyItineraryRevision, shouldRestoreOver, type ItineraryFields } from "./itineraryRevision";
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

function readSavedAt(value: unknown): { toMillis(): number } | null {
  if (!value || typeof value !== "object" || !("toMillis" in value)) return null;
  if (typeof (value as { toMillis?: unknown }).toMillis !== "function") return null;
  return value as { toMillis(): number };
}

function readItinerary(data: DocumentData | undefined): ItineraryFields | null {
  if (!data) return null;
  return {
    date: typeof data.date === "string" ? data.date : "",
    stops: Array.isArray(data.stops) ? data.stops : [],
    backupStops: Array.isArray(data.backupStops) ? data.backupStops : [],
    clientSavedAt: readSavedAt(data.clientSavedAt),
    updatedBy: typeof data.updatedBy === "string" ? data.updatedBy : "",
    updatedAt: data.updatedAt,
    serverRestored: data.serverRestored === true,
  };
}

/**
 * Archives the losing itinerary version. Clients never write itineraryHistory.
 * An older corrected clientSavedAt is rolled back so last-write-wins survives
 * an offline edit that syncs late. The auth-context trigger supplies the
 * writer uid (`recordedBy`); v2 `onDocumentWritten` does not. `serverRestored`
 * stops the rollback write from being archived again. History doc id is the
 * event id. The restore transaction re-reads the day and skips the write when
 * the document is no longer the losing version.
 */
export const recordItineraryRevision = onDocumentWrittenWithAuthContext(
  {
    document: "trips/{tripId}/itinerary/{dayId}",
    region: REGION,
  },
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.exists ? readItinerary(change.before.data()) : null;
    const after = change.after.exists ? readItinerary(change.after.data()) : null;
    const db = getFirestore();
    const tripId = event.params.tripId;
    const dayId = event.params.dayId;
    const dayRef = db.collection("trips").doc(tripId).collection("itinerary").doc(dayId);
    const recordedBy = event.authId || "server";

    const result = await applyItineraryRevision({
      eventId: event.id,
      dayId,
      recordedBy,
      before,
      after,
      createHistory: async (id, data) => {
        await db.collection("trips").doc(tripId).collection("itineraryHistory").doc(id).create({
          ...data,
          createdAt: FieldValue.serverTimestamp(),
        });
      },
      writeDay: async (data) => {
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(dayRef);
          const current = snap.exists ? readItinerary(snap.data()) : null;
          if (!shouldRestoreOver(current, after)) return;
          tx.set(dayRef, {
            date: data.date,
            stops: data.stops,
            backupStops: data.backupStops,
            clientSavedAt: data.clientSavedAt,
            updatedBy: data.updatedBy,
            updatedAt: data.updatedAt ?? FieldValue.serverTimestamp(),
            serverRestored: true,
          });
        });
      },
      clearMarker: async () => {
        await dayRef.update({ serverRestored: FieldValue.delete() });
      },
    });
    logger.info("itinerary revision", { tripId, dayId, result });
  },
);
