import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { after, before, beforeEach, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  serverTimestamp,
  Timestamp,
  type Firestore,
} from "firebase/firestore";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  throw new Error(
    'FIRESTORE_EMULATOR_HOST is not set. From integration/rules-contract: npx firebase emulators:exec --project demo-app --only firestore "npm test"',
  );
}

const [host, portText] = emulatorHost.split(":");
const rulesPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../firestore.rules",
);

const leader = "leader-1";
const member = "member-1";
const guest = "guest-1";
const other = "other-1";
const tripId = "trip-1";
const leaderCode = "LEAD2345";
const memberCode = "MEMB2345";

let testEnv: RulesTestEnvironment;

function utcMidnightYearsAgo(yearsAgo: number): Timestamp {
  const now = new Date();
  return Timestamp.fromDate(
    new Date(Date.UTC(now.getUTCFullYear() - yearsAgo, now.getUTCMonth(), now.getUTCDate())),
  );
}

function db(uid: string): Firestore {
  return testEnv.authenticatedContext(uid).firestore();
}

function profile(displayName: string) {
  return {
    birthdate: utcMidnightYearsAgo(30),
    displayName,
    photoUrl: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function newTrip(leaderId: string) {
  return {
    schemaVersion: 1,
    title: "京都自由行",
    leaderId,
    status: "planning",
    startDate: "2030-01-01",
    endDate: "2030-01-05",
    timeZone: "Asia/Taipei",
    expectedReturnAt: null,
    generalTransport: null,
    returnTransport: null,
    returnFlight: null,
    startedAt: null,
    endedAt: null,
    endReason: null,
    invitesOpen: true,
    invitesResetAt: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function aboutOneHourFromNow(): Timestamp {
  return Timestamp.fromMillis(Date.now() + 58 * 60 * 1000);
}

function inviteDoc(createdBy: string, creatorRole: "leader" | "deputy" | "member") {
  return {
    tripId,
    tripTitle: "京都自由行",
    createdBy,
    creatorRole,
    active: true,
    expiresAt: aboutOneHourFromNow(),
    createdAt: serverTimestamp(),
  };
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-app",
    firestore: {
      rules: readFileSync(rulesPath, "utf8"),
      host,
      port: Number(portText),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

describe("client payload accepted by the data model", () => {
  it("accepts leaderId, invites, and clockProbes, and keeps member codes dead after reopen", async () => {
    await assertSucceeds(setDoc(doc(db(leader), `users/${leader}`), profile("領隊")));
    await assertSucceeds(setDoc(doc(db(member), `users/${member}`), profile("成員")));
    await assertSucceeds(setDoc(doc(db(guest), `users/${guest}`), profile("客人")));
    await assertSucceeds(setDoc(doc(db(other), `users/${other}`), profile("另一位")));

    await assertSucceeds(setDoc(doc(db(leader), `trips/${tripId}`), newTrip(leader)));
    await assertSucceeds(
      setDoc(doc(db(leader), `trips/${tripId}/members/${leader}`), {
        role: "leader",
        isMinor: false,
        displayName: "領隊",
        photoUrl: null,
        inviteCode: null,
        joinedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      setDoc(doc(db(leader), `users/${leader}/tripRefs/${tripId}`), {
        tripId,
        role: "leader",
        tripTitle: "京都自由行",
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(setDoc(doc(db(leader), `invites/${leaderCode}`), inviteDoc(leader, "leader")));
    await assertSucceeds(
      setDoc(doc(db(member), `trips/${tripId}/members/${member}`), {
        role: "member",
        isMinor: false,
        displayName: "成員",
        photoUrl: null,
        inviteCode: leaderCode,
        joinedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(setDoc(doc(db(member), `invites/${memberCode}`), inviteDoc(member, "member")));

    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        invitesOpen: false,
        invitesResetAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db(guest), `trips/${tripId}/members/${guest}`), {
        role: "member",
        isMinor: false,
        displayName: "客人",
        photoUrl: null,
        inviteCode: memberCode,
        joinedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      setDoc(doc(db(guest), `trips/${tripId}/members/${guest}`), {
        role: "member",
        isMinor: false,
        displayName: "客人",
        photoUrl: null,
        inviteCode: leaderCode,
        joinedAt: serverTimestamp(),
      }),
    );

    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        invitesOpen: true,
        updatedAt: serverTimestamp(),
      }),
    );
    const reopened = await getDoc(doc(db(leader), `trips/${tripId}`));
    assert.equal(reopened.data()?.invitesOpen, true);
    assert.ok(reopened.data()?.invitesResetAt);
    await assertFails(
      setDoc(doc(db(other), `trips/${tripId}/members/${other}`), {
        role: "member",
        isMinor: false,
        displayName: "另一位",
        photoUrl: null,
        inviteCode: memberCode,
        joinedAt: serverTimestamp(),
      }),
    );
  });

  it("rejects the old captainId and publicInvite payload", async () => {
    await assertSucceeds(setDoc(doc(db(leader), `users/${leader}`), profile("領隊")));
    await assertFails(
      setDoc(doc(db(leader), `trips/${tripId}`), {
        captainId: leader,
        title: "京都自由行",
        publicInvite: true,
        inviteCode: leaderCode,
        memberIds: [leader],
        status: "planning",
        startDate: "2030-01-01",
        endDate: "2030-01-05",
        timeZone: "Asia/Taipei",
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db(leader), `inviteCodes/${leaderCode}`), {
        tripId,
        createdBy: leader,
        issuerRole: "captain",
        createdAt: serverTimestamp(),
        expiresAt: aboutOneHourFromNow(),
      }),
    );
  });

  it("reads server time from clockProbes/{uid}.t and rejects _meta/clock", async () => {
    await assertSucceeds(
      setDoc(doc(db(leader), `clockProbes/${leader}`), { t: serverTimestamp() }),
    );
    const probe = await getDoc(doc(db(leader), `clockProbes/${leader}`));
    assert.ok(probe.data()?.t instanceof Timestamp);
    const server = (probe.data()?.t as Timestamp).toDate();
    const offsetMs = server.getTime() - Date.now();
    assert.ok(Math.abs(offsetMs) < 60_000);

    await assertFails(
      setDoc(doc(db(leader), `clockProbes/${leader}`), { t: Timestamp.now() }),
    );
    await assertFails(getDoc(doc(db(member), `clockProbes/${leader}`)));
    await assertFails(
      setDoc(doc(db(leader), "_meta/clock"), { now: serverTimestamp() }),
    );
  });
});
