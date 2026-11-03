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
    'FIRESTORE_EMULATOR_HOST is not set. From the repo root: npx firebase emulators:exec --project demo-app --only firestore "npm --prefix rules-tests test"',
  );
}

const [host, portText] = emulatorHost.split(":");
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const rulesPath = path.join(repoRoot, "firestore.rules");
const adrPath = path.join(repoRoot, "docs/adr/0010-行程版本定案與旅程限制.md");

const leader = "span-leader";
const tripId = "span-trip";

let testEnv: RulesTestEnvironment;

function db(uid: string): Firestore {
  return testEnv.authenticatedContext(uid).firestore();
}

function utcMidnightYearsAgo(yearsAgo: number): Timestamp {
  const now = new Date();
  return Timestamp.fromDate(
    new Date(Date.UTC(now.getUTCFullYear() - yearsAgo, now.getUTCMonth(), now.getUTCDate())),
  );
}

function profile() {
  return {
    birthdate: utcMidnightYearsAgo(30),
    displayName: "領隊",
    photoUrl: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

// Asia/Taipei is UTC+8 year round. Local 00:30 is 16:30 on the previous UTC date.
function taipeiHalfPastMidnight(localDate: string): Timestamp {
  return Timestamp.fromDate(new Date(`${localDate}T00:30:00+08:00`));
}

function tripCreate(
  startDate: string,
  endDate: string,
  expectedReturnAt: Timestamp | null = null,
) {
  return {
    schemaVersion: 1,
    title: "台北跨夜",
    leaderId: leader,
    status: "planning" as const,
    startDate,
    endDate,
    timeZone: "Asia/Taipei",
    expectedReturnAt,
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

async function seedTrip(
  startDate: string,
  endDate: string,
  expectedReturnAt: Timestamp | null = null,
): Promise<void> {
  const createdAt = Timestamp.fromDate(new Date("2026-11-01T00:00:00Z"));
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const admin = ctx.firestore();
    await setDoc(doc(admin, `trips/${tripId}`), {
      ...tripCreate(startDate, endDate, expectedReturnAt),
      createdAt,
      updatedAt: createdAt,
    });
    await setDoc(doc(admin, `trips/${tripId}/members/${leader}`), {
      role: "leader",
      isMinor: false,
      displayName: "領隊",
      photoUrl: null,
      inviteCode: null,
      joinedAt: createdAt,
    });
  });
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
  await assertSucceeds(setDoc(doc(db(leader), `users/${leader}`), profile()));
});

describe("ADR 0010 inclusive 30-day trip span", () => {
  it("matches the ADR 0010 wording: 30 days inclusive, endDate - startDate <= 29", () => {
    const adr = readFileSync(adrPath, "utf8");
    assert.match(adr, /30 天含出發日與結束日/);
    assert.match(adr, /結束日期減出發日期最多 29 天/);
    assert.match(adr, /建立和修改時都由權限規則檢查/);
    assert.match(adr, /`2030-01-01` 到 `2030-01-30` 可以，到 `2030-01-31` 不行/);
    assert.match(adr, /含頭含尾 30 天（日期差最多 29 天）/);
  });

  it("allows create of 2030-01-01 through 2030-01-30", async () => {
    await assertSucceeds(
      setDoc(doc(db(leader), "trips/create-30"), tripCreate("2030-01-01", "2030-01-30")),
    );
    const saved = await assertSucceeds(getDoc(doc(db(leader), "trips/create-30")));
    assert.equal(saved.get("startDate"), "2030-01-01");
    assert.equal(saved.get("endDate"), "2030-01-30");
  });

  it("allows update to 2030-01-01 through 2030-01-30", async () => {
    await seedTrip("2030-01-01", "2030-01-05");
    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        endDate: "2030-01-30",
        updatedAt: serverTimestamp(),
      }),
    );
    const saved = await assertSucceeds(getDoc(doc(db(leader), `trips/${tripId}`)));
    assert.equal(saved.get("endDate"), "2030-01-30");
  });

  it("denies create of 2030-01-01 through 2030-01-31", async () => {
    await assertFails(
      setDoc(doc(db(leader), "trips/create-31"), tripCreate("2030-01-01", "2030-01-31")),
    );
  });

  it("denies update to 2030-01-01 through 2030-01-31", async () => {
    await seedTrip("2030-01-01", "2030-01-05");
    await assertFails(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        endDate: "2030-01-31",
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("allows a same-day trip on create", async () => {
    await assertSucceeds(
      setDoc(doc(db(leader), "trips/create-same"), tripCreate("2030-01-01", "2030-01-01")),
    );
  });

  it("allows a same-day trip on update", async () => {
    await seedTrip("2030-01-01", "2030-01-05");
    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        endDate: "2030-01-01",
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("denies create when the end date is before the start date", async () => {
    await assertFails(
      setDoc(doc(db(leader), "trips/create-backwards"), tripCreate("2030-01-10", "2030-01-09")),
    );
  });

  it("denies update when the end date is before the start date", async () => {
    await seedTrip("2030-01-01", "2030-01-05");
    await assertFails(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        startDate: "2030-01-06",
        updatedAt: serverTimestamp(),
      }),
    );
  });

  // Review date is 2026-11-03. 2027-05-03 is six months later.
  // May 3 through June 1 is 30 days inclusive (difference of 29).
  it("allows create of a 30-day span starting about six months ahead", async () => {
    await assertSucceeds(
      setDoc(doc(db(leader), "trips/create-future"), tripCreate("2027-05-03", "2027-06-01")),
    );
    const saved = await assertSucceeds(getDoc(doc(db(leader), "trips/create-future")));
    assert.equal(saved.get("startDate"), "2027-05-03");
    assert.equal(saved.get("endDate"), "2027-06-01");
  });

  it("allows update to a 30-day span starting about six months ahead", async () => {
    await seedTrip("2030-01-01", "2030-01-05");
    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        startDate: "2027-05-03",
        endDate: "2027-06-01",
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("does not let a Taipei midnight stored as the previous UTC day change create", async () => {
    const localJan31Midnight = taipeiHalfPastMidnight("2030-01-31");
    assert.equal(localJan31Midnight.toDate().toISOString(), "2030-01-30T16:30:00.000Z");

    await assertSucceeds(
      setDoc(
        doc(db(leader), "trips/midnight-allow"),
        tripCreate("2030-01-01", "2030-01-30", localJan31Midnight),
      ),
    );
    const allowed = await assertSucceeds(getDoc(doc(db(leader), "trips/midnight-allow")));
    assert.equal(allowed.get("startDate"), "2030-01-01");
    assert.equal(allowed.get("endDate"), "2030-01-30");
    assert.equal(allowed.get("timeZone"), "Asia/Taipei");

    await assertFails(
      setDoc(
        doc(db(leader), "trips/midnight-deny"),
        tripCreate("2030-01-01", "2030-01-31", localJan31Midnight),
      ),
    );

    const localSameDayMidnight = taipeiHalfPastMidnight("2030-01-15");
    assert.equal(localSameDayMidnight.toDate().toISOString(), "2030-01-14T16:30:00.000Z");
    await assertSucceeds(
      setDoc(
        doc(db(leader), "trips/midnight-same"),
        tripCreate("2030-01-15", "2030-01-15", localSameDayMidnight),
      ),
    );
  });

  it("does not let a Taipei midnight stored as the previous UTC day change update", async () => {
    const localJan31Midnight = taipeiHalfPastMidnight("2030-01-31");
    await seedTrip("2030-01-01", "2030-01-05", localJan31Midnight);

    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        endDate: "2030-01-30",
        updatedAt: serverTimestamp(),
      }),
    );
    const allowed = await assertSucceeds(getDoc(doc(db(leader), `trips/${tripId}`)));
    assert.equal(allowed.get("endDate"), "2030-01-30");
    assert.equal(allowed.get("expectedReturnAt").toDate().toISOString(), "2030-01-30T16:30:00.000Z");

    await assertFails(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        endDate: "2030-01-31",
        updatedAt: serverTimestamp(),
      }),
    );
  });
});
