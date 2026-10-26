/**
 * Independent checks for PR #26. Rules and the revision function run against
 * the Firestore emulator. Live trigger checks run only when the Functions
 * emulator is also up, so a replayed event id is not mixed with a real trigger.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createConnection } from "node:net";
import path from "node:path";
import { after, before, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, Timestamp as AdminTimestamp, getFirestore, type DocumentData, type Firestore as AdminFirestore } from "firebase-admin/firestore";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  setDoc,
  updateDoc,
  serverTimestamp,
  Timestamp,
  type Firestore,
} from "firebase/firestore";
import {
  applyItineraryRevision,
  historyDocId,
  shouldRestoreOver,
  type HistoryWrite,
  type ItineraryFields,
} from "../../functions/src/itineraryRevision.ts";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  throw new Error(
    'FIRESTORE_EMULATOR_HOST is not set. Example: npx firebase emulators:exec --project demo-app --only firestore "npm --prefix qa/itinerary-history run test:emulator"',
  );
}

const [host, portText] = emulatorHost.split(":");
const port = Number(portText);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const rules = readFileSync(path.join(root, "firestore.rules"), "utf8");
const projectId = "demo-app";

const leader = "qa-leader";
const member = "qa-member";
const outsider = "qa-outsider";

let testEnv: RulesTestEnvironment;
let adminDb: AdminFirestore;
let functionsEmulator = false;

function client(uid: string): Firestore {
  return testEnv.authenticatedContext(uid).firestore();
}

function savedAt(msAgo: number): Timestamp {
  return Timestamp.fromMillis(Date.now() - msAgo);
}

function dayDoc(dayId: string, updatedBy: string, clientSavedAt: Timestamp, backupStops: unknown[], stops = [{ place_id: "p", name: "景點", order: 0 }]) {
  return {
    date: dayId,
    stops,
    backupStops,
    clientSavedAt,
    updatedBy,
    updatedAt: serverTimestamp(),
  };
}

function asFields(data: DocumentData | undefined): ItineraryFields | null {
  if (!data) return null;
  const saved = data.clientSavedAt;
  return {
    date: typeof data.date === "string" ? data.date : "",
    stops: Array.isArray(data.stops) ? data.stops : [],
    backupStops: Array.isArray(data.backupStops) ? data.backupStops : [],
    clientSavedAt: saved && typeof saved.toMillis === "function" ? saved : null,
    updatedBy: typeof data.updatedBy === "string" ? data.updatedBy : "",
    updatedAt: data.updatedAt,
    serverRestored: data.serverRestored === true,
  };
}

async function seedTrip(tripId: string): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const createdAt = Timestamp.fromDate(new Date("2026-01-01T00:00:00Z"));
    await setDoc(doc(db, `trips/${tripId}`), {
      status: "planning",
      leaderId: leader,
      createdAt,
      updatedAt: createdAt,
    });
    for (const [uid, role] of [[leader, "leader"], [member, "member"]] as const) {
      await setDoc(doc(db, `trips/${tripId}/members/${uid}`), {
        role,
        isMinor: false,
        displayName: uid,
        photoUrl: null,
        inviteCode: role === "leader" ? null : "JOINCODE1",
        joinedAt: createdAt,
      });
    }
  });
}

function portOpen(checkPort: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = createConnection({ host: "127.0.0.1", port: checkPort });
    const done = (open: boolean) => {
      socket.removeAllListeners();
      socket.destroy();
      resolve(open);
    };
    socket.setTimeout(400);
    socket.once("connect", () => done(true));
    socket.once("timeout", () => done(false));
    socket.once("error", () => done(false));
  });
}

async function historyDocs(tripId: string) {
  const snap = await adminDb.collection("trips").doc(tripId).collection("itineraryHistory").get();
  return snap.docs.map((item) => ({ id: item.id, ...item.data() }));
}

async function waitFor(predicate: () => Promise<boolean>, timeoutMs: number, label: string): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`timed out waiting for ${label}`);
}

before(async () => {
  functionsEmulator = await portOpen(5001);
  initializeApp({ projectId });
  adminDb = getFirestore();
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules, host, port },
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe("T25 rules", () => {
  const tripId = "qa-rules";

  before(async () => {
    await testEnv.clearFirestore();
    await seedTrip(tripId);
  });

  it("T25-2 and T25-3 reject client history writes and hide history from non-members", async () => {
    const historyPath = `trips/${tripId}/itineraryHistory/evt_1`;
    const saved = savedAt(60_000);
    const history = {
      dayId: "2030-01-02",
      snapshot: { stops: [], backupStops: [{ place_id: "a", name: "備選甲", order: 0 }], clientSavedAt: saved, updatedBy: member },
      clientSavedAt: saved,
      updatedBy: member,
      recordedBy: member,
      outcome: "lost",
      createdAt: saved,
    };
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), historyPath), history);
    });

    await assertFails(setDoc(doc(client(member), `trips/${tripId}/itineraryHistory/client-write`), history));
    await assertFails(updateDoc(doc(client(leader), historyPath), { outcome: "superseded" }));
    await assertFails(deleteDoc(doc(client(leader), historyPath)));
    await assertFails(getDoc(doc(client(outsider), historyPath)));
    await assertFails(getDocs(collection(client(outsider), `trips/${tripId}/itineraryHistory`)));
    const stored = await assertSucceeds(getDoc(doc(client(member), historyPath)));
    assert.equal(stored.get("outcome"), "lost");
  });

  it("T25-4 accepts an older clientSavedAt instead of rejecting it in rules", async () => {
    const dayId = "2030-01-02";
    const dayPath = `trips/${tripId}/itinerary/${dayId}`;
    const backups = [{ place_id: "a", name: "備選甲", order: 0 }];
    await assertSucceeds(setDoc(doc(client(member), dayPath), dayDoc(dayId, member, savedAt(5_000), backups)));
    await assertSucceeds(setDoc(doc(client(leader), dayPath), dayDoc(dayId, leader, savedAt(86_400_000), [])));
    if (!functionsEmulator) {
      const stored = await assertSucceeds(getDoc(doc(client(member), dayPath)));
      assert.equal(stored.get("updatedBy"), leader);
    }
  });
});

describe("T25 function simulation without a second trigger", () => {
  const tripId = "qa-sim";
  const dayId = "2030-02-02";
  const dayRef = () => adminDb.collection("trips").doc(tripId).collection("itinerary").doc(dayId);

  before(async () => {
    if (functionsEmulator) return;
    await testEnv.clearFirestore();
    await seedTrip(tripId);
  });

  async function applyOnce(eventId: string, before: ItineraryFields | null, after: ItineraryFields | null, recordedBy: string) {
    return applyItineraryRevision({
      eventId,
      dayId,
      recordedBy,
      before,
      after,
      createHistory: async (id, data: HistoryWrite) => {
        await adminDb.collection("trips").doc(tripId).collection("itineraryHistory").doc(id).create({
          ...data,
          createdAt: new Date(),
        });
      },
      writeDay: async (data) => {
        await adminDb.runTransaction(async (tx) => {
          const snap = await tx.get(dayRef());
          const current = snap.exists ? asFields(snap.data()) : null;
          if (!shouldRestoreOver(current, after)) return;
          tx.set(dayRef(), {
            date: data.date,
            stops: data.stops,
            backupStops: data.backupStops,
            clientSavedAt: data.clientSavedAt,
            updatedBy: data.updatedBy,
            updatedAt: data.updatedAt ?? new Date(),
            serverRestored: true,
          });
        });
      },
      clearMarker: async () => {
        await dayRef().update({ serverRestored: FieldValue.delete() });
      },
    });
  }

  it("T25-6 T25-7 T25-8 restore once, skip serverRestored, and ignore a duplicate event", async () => {
    if (functionsEmulator) return;
    const backups = [{ place_id: "a", name: "備選甲", order: 0 }];
    const newer = AdminTimestamp.fromMillis(2_000);
    const older = AdminTimestamp.fromMillis(1_000);
    await dayRef().set({
      date: dayId,
      stops: [{ place_id: "new", name: "新", order: 0 }],
      backupStops: backups,
      clientSavedAt: newer,
      updatedBy: member,
      updatedAt: newer,
    });
    const before = asFields((await dayRef().get()).data());
    await dayRef().set({
      date: dayId,
      stops: [{ place_id: "old", name: "舊", order: 0 }],
      backupStops: [],
      clientSavedAt: older,
      updatedBy: leader,
      updatedAt: older,
    });
    const after = asFields((await dayRef().get()).data());
    const eventId = "projects/demo/events/evt-lost";
    assert.equal(await applyOnce(eventId, before, after, leader), "restored");
    assert.equal(await applyOnce(eventId, before, after, leader), "restored");

    const restored = asFields((await dayRef().get()).data());
    assert.equal(restored?.serverRestored, true);
    assert.equal(restored?.updatedBy, member);
    assert.equal(Array.isArray(restored?.backupStops) && restored?.backupStops.length, 1);

    assert.equal(await applyOnce("evt-clear", after, restored, "server"), "clearMarker");
    const clearedRaw = (await dayRef().get()).data();
    assert.equal(clearedRaw?.serverRestored, undefined);
    const cleared = asFields(clearedRaw);
    assert.equal(await applyOnce("evt-after-clear", restored, cleared, "server"), "noop");

    const rows = await historyDocs(tripId);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.id, historyDocId(eventId));
    assert.equal(rows[0]?.outcome, "lost");
    assert.equal(rows[0]?.recordedBy, leader);
  });

  it("T25-5 and T25-10 record superseded, including an equal clientSavedAt", async () => {
    if (functionsEmulator) return;
    const equalDay = "2030-02-03";
    const ref = adminDb.collection("trips").doc(tripId).collection("itinerary").doc(equalDay);
    const when = AdminTimestamp.fromMillis(5_000);
    await ref.set({
      date: equalDay,
      stops: [{ place_id: "a", name: "甲", order: 0 }],
      backupStops: [{ place_id: "b", name: "備選", order: 0 }],
      clientSavedAt: when,
      updatedBy: "first",
      updatedAt: when,
    });
    const before = asFields((await ref.get()).data());
    await ref.set({
      date: equalDay,
      stops: [{ place_id: "c", name: "乙", order: 0 }],
      backupStops: [{ place_id: "b", name: "備選", order: 0 }],
      clientSavedAt: when,
      updatedBy: "second",
      updatedAt: when,
    });
    const after = asFields((await ref.get()).data());
    const result = await applyItineraryRevision({
      eventId: "evt-tie",
      dayId: equalDay,
      recordedBy: "second",
      before,
      after,
      createHistory: async (id, data) => {
        await adminDb.collection("trips").doc(tripId).collection("itineraryHistory").doc(id).create({
          ...data,
          createdAt: new Date(),
        });
      },
      writeDay: async () => {
        throw new Error("equal clientSavedAt must keep the later upload");
      },
      clearMarker: async () => {
        throw new Error("equal clientSavedAt is not a restore");
      },
    });
    assert.equal(result, "recorded");
    const row = await adminDb.collection("trips").doc(tripId).collection("itineraryHistory").doc("evt-tie").get();
    assert.equal(row.get("outcome"), "superseded");
    assert.equal(row.get("updatedBy"), "first");
    const current = asFields((await ref.get()).data());
    assert.equal(current?.updatedBy, "second");
  });
});

describe("T25 live function trigger", () => {
  const tripId = "qa-live";

  before(async () => {
    if (!functionsEmulator) return;
    await testEnv.clearFirestore();
    await seedTrip(tripId);
  });

  async function watch(dayPath: string, uid: string): Promise<{ stop: () => void; seen: string[] }> {
    const seen: string[] = [];
    const unsubscribe = onSnapshot(doc(client(uid), dayPath), (snap) => {
      if (!snap.exists()) return;
      seen.push(`${snap.get("updatedBy")}:${snap.get("clientSavedAt")?.toMillis?.() ?? "?"}:restored=${snap.get("serverRestored") === true}`);
    });
    return { stop: unsubscribe, seen };
  }

  it("T25-6 and T25-9 restore the newer day and record whether listeners saw the older write", async () => {
    if (!functionsEmulator) return;
    const dayId = "2030-03-03";
    const dayPath = `trips/${tripId}/itinerary/${dayId}`;
    const backups = [{ place_id: "a", name: "備選甲", order: 0 }];
    const newer = savedAt(5_000);
    const older = savedAt(86_400_000);
    await assertSucceeds(setDoc(doc(client(member), dayPath), dayDoc(dayId, member, newer, backups, [{ place_id: "new", name: "新", order: 0 }])));
    const watcher = await watch(dayPath, leader);
    await assertSucceeds(setDoc(doc(client(leader), dayPath), dayDoc(dayId, leader, older, [], [{ place_id: "old", name: "舊", order: 0 }])));

    await waitFor(async () => {
      const snap = await adminDb.collection("trips").doc(tripId).collection("itinerary").doc(dayId).get();
      return snap.get("updatedBy") === member && snap.get("serverRestored") !== true;
    }, 15_000, "restore and marker clear");
    await new Promise((resolve) => setTimeout(resolve, 1_000));
    watcher.stop();

    const stored = await adminDb.collection("trips").doc(tripId).collection("itinerary").doc(dayId).get();
    assert.equal(stored.get("updatedBy"), member);
    assert.equal(stored.get("backupStops").length, 1);
    assert.equal(stored.get("serverRestored"), undefined);
    const rows = await historyDocs(tripId);
    const lost = rows.filter((row) => row.outcome === "lost");
    const sawOlder = watcher.seen.some((line) => line.startsWith(`${leader}:`));
    console.log(`T25-9 listener sequence: ${watcher.seen.join(" | ") || "(empty)"}`);
    console.log(`T25-9 saw older version before restore: ${sawOlder}`);
    console.log(`T25-9 recordedBy: ${String(lost[0]?.recordedBy)}`);
    console.log(`T25-9 history: ${JSON.stringify(rows.map((row) => ({ id: row.id, outcome: row.outcome, recordedBy: row.recordedBy })))}`);
    assert.equal(lost.length, 1, `history rows: ${JSON.stringify(rows.map((row) => ({ id: row.id, outcome: row.outcome, recordedBy: row.recordedBy })))}`);
    // Firestore emulator v1.19.8 always sets ce-authid to this placeholder for
    // v2 auth-context events (FunctionsEmulatorEventPublisher). It never
    // forwards request.auth.uid. Production Eventarc does. "server" would mean
    // the trigger dropped the auth context entirely.
    const emulatorAuthPlaceholder = "fake-auth-id@gmail.com";
    const recordedBy = lost[0]?.recordedBy;
    assert.notEqual(recordedBy, "server");
    assert.equal(
      recordedBy === leader || recordedBy === emulatorAuthPlaceholder,
      true,
      `recordedBy should be the losing uid or the emulator auth placeholder, got ${String(recordedBy)}`,
    );
    assert.equal(watcher.seen.at(-1)?.startsWith(`${member}:`), true, `listener stayed on ${watcher.seen.at(-1)}`);
  });

  it("T25-5 keeps the later clientSavedAt and archives the earlier one as superseded", async () => {
    if (!functionsEmulator) return;
    const dayId = "2030-03-04";
    const dayPath = `trips/${tripId}/itinerary/${dayId}`;
    const backups = [{ place_id: "b", name: "備選乙", order: 0 }];
    await assertSucceeds(setDoc(doc(client(leader), dayPath), dayDoc(dayId, leader, savedAt(86_400_000), [], [{ place_id: "old", name: "舊", order: 0 }])));
    await assertSucceeds(setDoc(doc(client(member), dayPath), dayDoc(dayId, member, savedAt(5_000), backups, [{ place_id: "new", name: "新", order: 0 }])));
    await waitFor(async () => {
      const rows = await historyDocs(tripId);
      return rows.some((row) => row.outcome === "superseded" && row.dayId === dayId);
    }, 15_000, "superseded history");
    await new Promise((resolve) => setTimeout(resolve, 800));
    const stored = await adminDb.collection("trips").doc(tripId).collection("itinerary").doc(dayId).get();
    assert.equal(stored.get("updatedBy"), member);
    assert.equal(stored.get("backupStops").length, 1);
    const rows = (await historyDocs(tripId)).filter((row) => row.dayId === dayId);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.outcome, "superseded");
  });
});
