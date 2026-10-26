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
  serverTimestamp,
  Timestamp,
  type Firestore,
} from "firebase/firestore";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  throw new Error(
    'FIRESTORE_EMULATOR_HOST is not set. From the repo root: npx firebase emulators:exec --project demo-app --only firestore "npm --prefix rules-tests test"',
  );
}

const [host, portText] = emulatorHost.split(":");
const rulesPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../firestore.rules",
);

const leader = "leader-1";
const tripId = "trip-qa-3";
let testEnv: RulesTestEnvironment;

function db(uid: string): Firestore {
  return testEnv.authenticatedContext(uid).firestore();
}

function yearsAgo(years: number): Timestamp {
  const now = new Date();
  return Timestamp.fromDate(
    new Date(Date.UTC(now.getUTCFullYear() - years, now.getUTCMonth(), now.getUTCDate())),
  );
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

describe("qa #3 gaps against merged rules", () => {
  it("T3-4 rejects a join when the invite code does not exist", async () => {
    const createdAt = Timestamp.fromDate(new Date("2026-01-01T00:00:00Z"));
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(doc(admin, `users/${leader}`), {
        birthdate: yearsAgo(30),
        displayName: "隊長",
        photoUrl: null,
        createdAt,
        updatedAt: createdAt,
      });
      await setDoc(doc(admin, `users/guest-1`), {
        birthdate: yearsAgo(20),
        displayName: "路人",
        photoUrl: null,
        createdAt,
        updatedAt: createdAt,
      });
      await setDoc(doc(admin, `trips/${tripId}`), {
        schemaVersion: 1,
        title: "京都自由行",
        leaderId: leader,
        status: "planning",
        startDate: "2030-01-01",
        endDate: "2030-01-05",
        timeZone: "Asia/Tokyo",
        expectedReturnAt: null,
        generalTransport: null,
        returnTransport: null,
        returnFlight: null,
        startedAt: null,
        endedAt: null,
        endReason: null,
        invitesOpen: true,
        invitesResetAt: null,
        createdAt,
        updatedAt: createdAt,
      });
      await setDoc(doc(admin, `trips/${tripId}/members/${leader}`), {
        role: "leader",
        isMinor: false,
        displayName: "隊長",
        photoUrl: null,
        inviteCode: null,
        joinedAt: createdAt,
      });
    });

    await assertFails(
      setDoc(doc(db("guest-1"), `trips/${tripId}/members/guest-1`), {
        role: "member",
        isMinor: false,
        displayName: "路人",
        photoUrl: null,
        inviteCode: "MISSING01",
        joinedAt: serverTimestamp(),
      }),
    );
  });

  it("T3-18 and T3-19 treat one server hour as request.time < createdAt + 1h", async () => {
    const createdAt = Timestamp.fromDate(new Date("2026-01-01T00:00:00Z"));
    const now = Date.now();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      for (const uid of [leader, "early-guest", "late-guest"]) {
        await setDoc(doc(admin, `users/${uid}`), {
          birthdate: yearsAgo(30),
          displayName: uid,
          photoUrl: null,
          createdAt,
          updatedAt: createdAt,
        });
      }
      await setDoc(doc(admin, `trips/${tripId}`), {
        schemaVersion: 1,
        title: "京都自由行",
        leaderId: leader,
        status: "planning",
        startDate: "2030-01-01",
        endDate: "2030-01-05",
        timeZone: "Asia/Tokyo",
        expectedReturnAt: null,
        generalTransport: null,
        returnTransport: null,
        returnFlight: null,
        startedAt: null,
        endedAt: null,
        endReason: null,
        invitesOpen: true,
        invitesResetAt: null,
        createdAt,
        updatedAt: createdAt,
      });
      await setDoc(doc(admin, `trips/${tripId}/members/${leader}`), {
        role: "leader",
        isMinor: false,
        displayName: "隊長",
        photoUrl: null,
        inviteCode: null,
        joinedAt: createdAt,
      });
      await setDoc(doc(admin, "invites/STILL59M"), {
        tripId,
        tripTitle: "京都自由行",
        createdBy: leader,
        creatorRole: "leader",
        active: true,
        createdAt: Timestamp.fromMillis(now - 59 * 60 * 1000),
        expiresAt: Timestamp.fromMillis(now + 5 * 60 * 1000),
      });
      await setDoc(doc(admin, "invites/EXACT60M"), {
        tripId,
        tripTitle: "京都自由行",
        createdBy: leader,
        creatorRole: "leader",
        active: true,
        createdAt: Timestamp.fromMillis(now - 60 * 60 * 1000 - 5 * 1000),
        expiresAt: Timestamp.fromMillis(now + 5 * 60 * 1000),
      });
    });

    await assertSucceeds(
      setDoc(doc(db("early-guest"), `trips/${tripId}/members/early-guest`), {
        role: "member",
        isMinor: false,
        displayName: "早",
        photoUrl: null,
        inviteCode: "STILL59M",
        joinedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db("late-guest"), `trips/${tripId}/members/late-guest`), {
        role: "member",
        isMinor: false,
        displayName: "晚",
        photoUrl: null,
        inviteCode: "EXACT60M",
        joinedAt: serverTimestamp(),
      }),
    );
  });

  it("lets the owner write clockProbes/{uid}.t with serverTimestamp and blocks another user", async () => {
    const owner = "clock-owner";
    const other = "clock-other";
    const path = `clockProbes/${owner}`;
    await assertSucceeds(setDoc(doc(db(owner), path), { t: serverTimestamp() }));
    const saved = await assertSucceeds(getDoc(doc(db(owner), path)));
    assert.equal(saved.get("t") instanceof Timestamp, true);
    assert.deepEqual(Object.keys(saved.data() ?? {}), ["t"]);
    await assertFails(setDoc(doc(db(other), path), { t: serverTimestamp() }));
    await assertFails(getDoc(doc(db(other), path)));
  });

  it("rejects the Flutter client's trip, user, and inviteCodes payload", async () => {
    const iso = new Date().toISOString();
    await assertFails(
      setDoc(doc(db(leader), `users/${leader}`), {
        displayName: "小美",
        birthday: "2000-01-01",
        photoUrl: null,
        analyticsConsent: false,
        crashlyticsConsent: false,
        consentDecided: false,
        createdAt: iso,
      }),
    );
    await assertFails(
      setDoc(doc(db(leader), `trips/${tripId}`), {
        id: tripId,
        title: "京都自由行",
        captainId: leader,
        startDate: "2030-01-01",
        endDate: "2030-01-05",
        timeZone: "Asia/Taipei",
        expectedReturnAt: "2030-01-05T10:00:00.000Z",
        inviteCode: "CODE01",
        publicInvite: true,
        status: "planning",
        memberIds: [leader],
        createdAt: iso,
        updatedAt: iso,
      }),
    );
    await assertFails(
      setDoc(doc(db(leader), "inviteCodes/CODE01"), {
        code: "CODE01",
        tripId,
        createdBy: leader,
        createdAt: iso,
        expiresAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
      }),
    );
  });
});
