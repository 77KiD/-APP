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
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  Timestamp,
  writeBatch,
  type Firestore,
} from "firebase/firestore";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  throw new Error(
    'FIRESTORE_EMULATOR_HOST is not set. From the repo root: npx firebase emulators:exec --project demo-app --only firestore "npm --prefix rules-tests test"',
  );
}

const [host, portText] = emulatorHost.split(":");
const rulesPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../firestore.rules");

const leader = "leader-1";
const member = "member-1";
const deputy = "deputy-1";
const outsider = "outsider-1";
const tripId = "trip-1";

let testEnv: RulesTestEnvironment;

function utcMidnightYearsAgo(yearsAgo: number, dayOffset = 0): Timestamp {
  const now = new Date();
  return Timestamp.fromDate(
    new Date(Date.UTC(now.getUTCFullYear() - yearsAgo, now.getUTCMonth(), now.getUTCDate() + dayOffset)),
  );
}

function db(uid: string): Firestore {
  return testEnv.authenticatedContext(uid).firestore();
}

function profile(birthdate: Timestamp, displayName: string) {
  return {
    birthdate,
    displayName,
    photoUrl: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function tripBody(leaderId: string) {
  return {
    schemaVersion: 1,
    title: "京都自由行",
    leaderId,
    status: "planning" as const,
    startDate: "2030-01-01",
    endDate: "2030-01-05",
    timeZone: "Asia/Tokyo",
    expectedReturnAt: Timestamp.fromDate(new Date("2030-01-05T03:00:00Z")),
    generalTransport: "transit",
    returnTransport: "新幹線",
    returnFlight: { summary: "CI 100", flightNumber: "CI100" },
    startedAt: null,
    endedAt: null,
    endReason: null,
    invitesOpen: true,
    invitesResetAt: null,
  };
}

function aboutOneHourFromNow(): Timestamp {
  return Timestamp.fromMillis(Date.now() + 58 * 60 * 1000);
}

function creatorRoleFor(uid: string): "leader" | "deputy" | "member" {
  if (uid === deputy) return "deputy";
  if (uid === member) return "member";
  return "leader";
}

function inviteDoc(
  createdBy: string,
  expiresAt: Timestamp | null = aboutOneHourFromNow(),
  creatorRole: "leader" | "deputy" | "member" = creatorRoleFor(createdBy),
) {
  return {
    tripId,
    tripTitle: "京都自由行",
    createdBy,
    creatorRole,
    active: true,
    expiresAt,
    createdAt: serverTimestamp(),
  };
}

function newTrip(leaderId: string) {
  return {
    ...tripBody(leaderId),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function leaderMember(displayName: string, isMinor = false) {
  return {
    role: "leader",
    isMinor,
    displayName,
    photoUrl: null,
    inviteCode: null,
    joinedAt: serverTimestamp(),
  };
}

function joiningMember(displayName: string, inviteCode: string, isMinor: boolean) {
  return {
    role: "member",
    isMinor,
    displayName,
    photoUrl: null,
    inviteCode,
    joinedAt: serverTimestamp(),
  };
}

async function seedOpenTrip(): Promise<void> {
  const createdAt = Timestamp.fromDate(new Date("2026-01-01T00:00:00Z"));
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const admin = ctx.firestore();
    const people: Array<[string, string]> = [
      [leader, "領隊"],
      [member, "成員"],
      [deputy, "副隊"],
      [outsider, "外人"],
    ];
    for (const [uid, displayName] of people) {
      await setDoc(doc(admin, `users/${uid}`), {
        birthdate: utcMidnightYearsAgo(30),
        displayName,
        photoUrl: null,
        createdAt,
        updatedAt: createdAt,
      });
    }
    await setDoc(doc(admin, `trips/${tripId}`), {
      ...tripBody(leader),
      createdAt,
      updatedAt: createdAt,
    });
    const roster: Array<[string, string]> = [
      [leader, "leader"],
      [member, "member"],
      [deputy, "deputy"],
    ];
    for (const [uid, role] of roster) {
      await setDoc(doc(admin, `trips/${tripId}/members/${uid}`), {
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

describe("registration under 13", () => {
  it("allows a profile on the 13th birthday and rejects the day before", async () => {
    const uid = "teen";
    const exactly13 = utcMidnightYearsAgo(13);
    await assertSucceeds(setDoc(doc(db(uid), `users/${uid}`), profile(exactly13, "剛好十三")));
    const saved = await assertSucceeds(getDoc(doc(db(uid), `users/${uid}`)));
    assert.equal(saved.get("birthdate").toMillis(), exactly13.toMillis());

    const younger = "child";
    await assertFails(
      setDoc(doc(db(younger), `users/${younger}`), profile(utcMidnightYearsAgo(13, 1), "未滿十三")),
    );
  });

  it("accepts a Feb 29, 2012 birthdate (13th birthday rolled to 2025-03-01)", async () => {
    const uid = "leap";
    const birth = Timestamp.fromDate(new Date(Date.UTC(2012, 1, 29)));
    await assertSucceeds(setDoc(doc(db(uid), `users/${uid}`), profile(birth, "閏日")));
  });

  it("rejects a future birthdate, a non-midnight timestamp, and birthdate edits", async () => {
    const uid = "adult";
    await assertFails(
      setDoc(doc(db(uid), `users/${uid}`), profile(utcMidnightYearsAgo(0, 1), "未來")),
    );
    await assertFails(
      setDoc(
        doc(db(uid), `users/${uid}`),
        profile(Timestamp.fromDate(new Date(Date.UTC(1990, 0, 1, 8))), "有時間"),
      ),
    );
    const birth = utcMidnightYearsAgo(30);
    await assertSucceeds(setDoc(doc(db(uid), `users/${uid}`), profile(birth, "成人")));
    await assertFails(
      updateDoc(doc(db(uid), `users/${uid}`), {
        birthdate: utcMidnightYearsAgo(10),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(uid), `users/${uid}`), {
        displayName: "新名字",
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(doc(db(uid), `users/${uid}`)));
  });

  it("hides birthdate from every other user", async () => {
    const uid = "adult";
    await assertSucceeds(setDoc(doc(db(uid), `users/${uid}`), profile(utcMidnightYearsAgo(30), "成人")));
    await assertFails(getDoc(doc(db("other"), `users/${uid}`)));
    await assertFails(setDoc(doc(testEnv.unauthenticatedContext().firestore(), `users/${uid}`), profile(utcMidnightYearsAgo(30), "成人")));
  });
});

describe("trip membership isolation", () => {
  it("creates a trip, invite, and membership, and blocks non-members", async () => {
    const host = "host";
    const guest = "guest";
    const stranger = "stranger";

    await assertSucceeds(setDoc(doc(db(host), `users/${host}`), profile(utcMidnightYearsAgo(30), "隊長")));
    await assertFails(setDoc(doc(db("ghost"), "trips/ghost-trip"), newTrip("ghost")));
    await assertSucceeds(setDoc(doc(db(host), `trips/${tripId}`), newTrip(host)));
    await assertSucceeds(getDoc(doc(db(host), `trips/${tripId}`)));
    await assertSucceeds(setDoc(doc(db(host), `trips/${tripId}/members/${host}`), leaderMember("隊長")));
    await assertSucceeds(setDoc(doc(db(host), "invites/JOINCODE1"), inviteDoc(host)));
    await assertSucceeds(
      setDoc(doc(db(host), `users/${host}/tripRefs/${tripId}`), {
        tripId,
        role: "leader",
        tripTitle: "京都自由行",
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(getDocs(collection(db(host), "trips")));
    await assertFails(getDocs(collection(db(host), "invites")));

    await assertSucceeds(
      setDoc(doc(db(guest), `users/${guest}`), profile(utcMidnightYearsAgo(18, 1), "十七歲")),
    );
    await assertSucceeds(getDoc(doc(db(guest), "invites/JOINCODE1")));
    await assertFails(getDoc(doc(db(guest), `trips/${tripId}`)));
    await assertFails(
      setDoc(doc(db(guest), `trips/${tripId}/members/${guest}`), {
        ...joiningMember("十七歲", "JOINCODE1", true),
        role: "leader",
      }),
    );
    await assertFails(
      setDoc(doc(db(guest), `trips/${tripId}/members/${guest}`), {
        ...joiningMember("十七歲", "JOINCODE1", true),
        inviteCode: "MISSING1",
      }),
    );
    await assertFails(
      setDoc(doc(db(guest), `trips/${tripId}/members/${guest}`), joiningMember("十七歲", "JOINCODE1", false)),
    );
    await assertSucceeds(
      setDoc(doc(db(guest), `trips/${tripId}/members/${guest}`), joiningMember("十七歲", "JOINCODE1", true)),
    );
    await assertSucceeds(getDoc(doc(db(guest), `trips/${tripId}`)));
    await assertSucceeds(
      setDoc(doc(db(guest), `users/${guest}/tripRefs/${tripId}`), {
        tripId,
        role: "member",
        tripTitle: "京都自由行",
        updatedAt: serverTimestamp(),
      }),
    );
    const ownRefs = await assertSucceeds(getDocs(collection(db(guest), `users/${guest}/tripRefs`)));
    assert.equal(ownRefs.size, 1);
    await assertFails(getDocs(collection(db(host), `users/${guest}/tripRefs`)));

    await assertSucceeds(setDoc(doc(db(stranger), `users/${stranger}`), profile(utcMidnightYearsAgo(30), "外人")));
    await assertFails(getDoc(doc(db(stranger), `trips/${tripId}`)));
    await assertFails(getDoc(doc(db(stranger), `trips/${tripId}/members/${host}`)));
    await assertFails(getDoc(doc(db(stranger), `trips/${tripId}/itinerary/2030-01-02`)));
    await assertFails(getDoc(doc(db(stranger), `trips/${tripId}/locations/${guest}`)));
    await assertFails(getDoc(doc(testEnv.unauthenticatedContext().firestore(), `trips/${tripId}`)));
    await assertFails(getDoc(doc(db("nobody"), "invites/JOINCODE1")));
  });

  it("rejects revoked, expired, and not-yet-valid invites", async () => {
    const host = "host";
    const guest = "guest";
    await assertSucceeds(setDoc(doc(db(host), `users/${host}`), profile(utcMidnightYearsAgo(30), "隊長")));
    await assertSucceeds(setDoc(doc(db(host), `trips/${tripId}`), newTrip(host)));
    await assertSucceeds(setDoc(doc(db(host), `trips/${tripId}/members/${host}`), leaderMember("隊長")));
    await assertFails(
      setDoc(doc(db(host), "invites/PASTCODE"), inviteDoc(host, Timestamp.fromDate(new Date("2020-01-01T00:00:00Z")))),
    );
    await assertFails(setDoc(doc(db(host), "invites/NULLCODE"), inviteDoc(host, null)));
    await assertSucceeds(setDoc(doc(db(host), "invites/JOINCODE1"), inviteDoc(host)));
    await assertSucceeds(
      updateDoc(doc(db(host), "invites/JOINCODE1"), { active: false }),
    );
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "invites/EXPIRED1"), {
        tripId,
        tripTitle: "京都自由行",
        createdBy: host,
        creatorRole: "leader",
        active: true,
        expiresAt: Timestamp.fromDate(new Date("2020-01-01T00:00:00Z")),
        createdAt: Timestamp.fromDate(new Date("2020-01-01T00:00:00Z")),
      });
    });
    await assertSucceeds(setDoc(doc(db(guest), `users/${guest}`), profile(utcMidnightYearsAgo(30), "客人")));
    await assertFails(
      setDoc(doc(db(guest), `trips/${tripId}/members/${guest}`), joiningMember("客人", "JOINCODE1", false)),
    );
    await assertFails(
      setDoc(doc(db(guest), `trips/${tripId}/members/${guest}`), joiningMember("客人", "EXPIRED1", false)),
    );
    await assertFails(
      updateDoc(doc(db(guest), "invites/JOINCODE1"), { active: true }),
    );
  });
});

describe("leader and deputy permissions", () => {
  beforeEach(async () => {
    await seedOpenTrip();
  });

  it("lets members edit planning fields and blocks direct return-time and transport edits", async () => {
    const trip = doc(db(member), `trips/${tripId}`);
    await assertSucceeds(updateDoc(trip, { title: "改名", updatedAt: serverTimestamp() }));

    const patches = [
      { expectedReturnAt: Timestamp.fromDate(new Date("2091-06-01T00:00:00Z")) },
      { generalTransport: "drive" },
      { returnTransport: "巴士" },
      { returnFlight: { summary: "CI 200", flightNumber: "CI200" } },
    ];
    for (const patch of patches) {
      await assertFails(updateDoc(doc(db(member), `trips/${tripId}`), { ...patch, updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(doc(db(leader), `trips/${tripId}`), { ...patch, updatedAt: serverTimestamp() }));
    }
    await assertSucceeds(
      updateDoc(doc(db(deputy), `trips/${tripId}`), {
        generalTransport: "walk",
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("blocks a past 預計回程時間 and allows clearing it", async () => {
    await assertFails(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        expectedReturnAt: Timestamp.fromDate(new Date("2020-01-01T00:00:00Z")),
        updatedAt: serverTimestamp(),
      }),
    );
    const fresh = await assertSucceeds(getDoc(doc(db(leader), `trips/${tripId}`)));
    assert.equal(fresh.get("expectedReturnAt").toMillis(), Timestamp.fromDate(new Date("2030-01-05T03:00:00Z")).toMillis());
    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        expectedReturnAt: null,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("lets only the leader start, then locks 回程機票", async () => {
    await assertFails(
      updateDoc(doc(db(deputy), `trips/${tripId}`), {
        status: "active",
        startedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        status: "active",
        startedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        returnFlight: { summary: "BR 100", flightNumber: "BR100" },
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db(member), `trips/${tripId}`), {
        returnFlight: { summary: "BR 100", flightNumber: "BR100" },
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(deputy), `trips/${tripId}`), {
        expectedReturnAt: Timestamp.fromDate(new Date("2092-01-01T00:00:00Z")),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("lets the leader assign a deputy and stops members promoting themselves", async () => {
    await assertFails(
      updateDoc(doc(db(member), `trips/${tripId}/members/${member}`), { role: "leader" }),
    );
    await assertFails(
      updateDoc(doc(db(leader), `trips/${tripId}/members/${member}`), { role: "leader" }),
    );
    await assertFails(
      updateDoc(doc(db(deputy), `trips/${tripId}/members/${member}`), { role: "member" }),
    );
    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}/members/${member}`), { role: "deputy" }),
    );
  });

  it("keeps isMinor tied to the account birthdate", async () => {
    const minor = "minor-1";
    const createdAt = Timestamp.fromDate(new Date("2026-01-01T00:00:00Z"));
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(doc(admin, `users/${minor}`), {
        birthdate: utcMidnightYearsAgo(18, 1),
        displayName: "未成年",
        photoUrl: null,
        createdAt,
        updatedAt: createdAt,
      });
      await setDoc(doc(admin, `trips/${tripId}/members/${minor}`), {
        role: "member",
        isMinor: true,
        displayName: "未成年",
        photoUrl: null,
        inviteCode: "JOINCODE1",
        joinedAt: createdAt,
      });
    });
    await assertFails(
      updateDoc(doc(db(minor), `trips/${tripId}/members/${minor}`), {
        displayName: "小孩",
        isMinor: false,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(minor), `trips/${tripId}/members/${minor}`), {
        displayName: "小孩",
        isMinor: true,
      }),
    );
    await assertFails(
      updateDoc(doc(db(leader), `trips/${tripId}/members/${minor}`), {
        role: "deputy",
        isMinor: false,
      }),
    );
  });

  it("lets a leader or deputy end the whole trip and then hides locations", async () => {
    const locationPin = (sentAt: Timestamp) => ({
      latitude: 35.0116,
      longitude: 135.7681,
      sentAt,
      receivedAt: serverTimestamp(),
      photoUrl: null,
    });
    await assertSucceeds(
      setDoc(
        doc(db(member), `trips/${tripId}/locations/${member}`),
        locationPin(Timestamp.fromDate(new Date(Date.now() - 10 * 60 * 1000))),
      ),
    );
    await assertSucceeds(getDoc(doc(db(leader), `trips/${tripId}/locations/${member}`)));
    await assertFails(
      setDoc(
        doc(db(member), `trips/${tripId}/locations/${leader}`),
        locationPin(Timestamp.fromDate(new Date(Date.now() - 10 * 60 * 1000))),
      ),
    );
    await assertFails(getDoc(doc(db(outsider), `trips/${tripId}/locations/${member}`)));
    await assertFails(
      setDoc(
        doc(db(member), `trips/${tripId}/locations/${member}`),
        locationPin(Timestamp.fromDate(new Date(Date.now() - 8 * 24 * 60 * 60 * 1000))),
      ),
    );

    await assertFails(
      updateDoc(doc(db(member), `trips/${tripId}`), {
        status: "ended",
        endReason: "leader_manual",
        endedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        status: "ended",
        endReason: "expected_return",
        endedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(deputy), `trips/${tripId}`), {
        status: "ended",
        endReason: "leader_manual",
        endedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(getDoc(doc(db(leader), `trips/${tripId}/locations/${member}`)));
    await assertFails(
      setDoc(
        doc(db(member), `trips/${tripId}/locations/${member}`),
        locationPin(Timestamp.fromDate(new Date(Date.now() - 10 * 60 * 1000))),
      ),
    );
  });
});

describe("change requests", () => {
  beforeEach(async () => {
    await seedOpenTrip();
  });

  it("lets a member file a request without changing the trip, and only leader or deputy decide it", async () => {
    const pendingRequest = (expiresAt: Timestamp | null) => ({
      type: "expected_return_at",
      status: "pending",
      proposerId: member,
      payload: { expectedReturnAt: Timestamp.fromDate(new Date("2091-01-02T00:00:00Z")) },
      createdAt: serverTimestamp(),
      expiresAt,
      decidedBy: null,
      decidedAt: null,
    });
    await assertFails(
      setDoc(
        doc(db(outsider), `trips/${tripId}/requests/req-1`),
        pendingRequest(Timestamp.fromDate(new Date(Date.now() + 15 * 60 * 1000))),
      ),
    );
    await assertFails(
      setDoc(
        doc(db(member), `trips/${tripId}/requests/too-long`),
        pendingRequest(Timestamp.fromDate(new Date(Date.now() + 2 * 60 * 60 * 1000))),
      ),
    );

    const memberDb = db(member);
    const sneaky = writeBatch(memberDb);
    sneaky.set(
      doc(memberDb, `trips/${tripId}/requests/req-1`),
      pendingRequest(Timestamp.fromDate(new Date(Date.now() + 15 * 60 * 1000))),
    );
    sneaky.update(doc(memberDb, `trips/${tripId}`), {
      expectedReturnAt: Timestamp.fromDate(new Date("2091-01-02T00:00:00Z")),
      updatedAt: serverTimestamp(),
    });
    await assertFails(sneaky.commit());

    await assertSucceeds(
      setDoc(
        doc(db(member), `trips/${tripId}/requests/req-1`),
        pendingRequest(Timestamp.fromDate(new Date(Date.now() + 15 * 60 * 1000))),
      ),
    );
    const unchanged = await assertSucceeds(getDoc(doc(db(leader), `trips/${tripId}`)));
    assert.equal(
      unchanged.get("expectedReturnAt").toMillis(),
      Timestamp.fromDate(new Date("2030-01-05T03:00:00Z")).toMillis(),
    );
    await assertFails(
      updateDoc(doc(db(member), `trips/${tripId}/requests/req-1`), {
        status: "approved",
        decidedBy: member,
        decidedAt: serverTimestamp(),
      }),
    );

    const leaderDb = db(leader);
    const approval = writeBatch(leaderDb);
    approval.update(doc(leaderDb, `trips/${tripId}/requests/req-1`), {
      status: "approved",
      decidedBy: leader,
      decidedAt: serverTimestamp(),
    });
    approval.update(doc(leaderDb, `trips/${tripId}`), {
      expectedReturnAt: Timestamp.fromDate(new Date("2091-01-02T00:00:00Z")),
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(approval.commit());
  });

  it("rolls back approval when the proposed 預計回程時間 is already past", async () => {
    await assertSucceeds(
      setDoc(doc(db(member), `trips/${tripId}/requests/req-past`), {
        type: "expected_return_at",
        status: "pending",
        proposerId: member,
        payload: { expectedReturnAt: Timestamp.fromDate(new Date("2091-01-02T00:00:00Z")) },
        createdAt: serverTimestamp(),
        expiresAt: null,
        decidedBy: null,
        decidedAt: null,
      }),
    );
    const deputyDb = db(deputy);
    const batch = writeBatch(deputyDb);
    batch.update(doc(deputyDb, `trips/${tripId}/requests/req-past`), {
      status: "approved",
      decidedBy: deputy,
      decidedAt: serverTimestamp(),
    });
    batch.update(doc(deputyDb, `trips/${tripId}`), {
      expectedReturnAt: Timestamp.fromDate(new Date("2020-01-01T00:00:00Z")),
      updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
    const pending = await assertSucceeds(getDoc(doc(db(leader), `trips/${tripId}/requests/req-past`)));
    assert.equal(pending.get("status"), "pending");
  });
});

describe("itinerary conflict and history", () => {
  beforeEach(async () => {
    await seedOpenTrip();
  });

  it("keeps the newest corrected clientSavedAt and rejects non-members", async () => {
    const dayPath = `trips/${tripId}/itinerary/2030-01-02`;
    const firstSaved = Timestamp.fromDate(new Date(Date.now() - 60_000));
    const stops = [{ place_id: "ChIJkyoto", name: "清水寺", order: 0 }];
    const day = (clientSavedAt: Timestamp, updatedBy: string, nextStops = stops) => ({
      date: "2030-01-02",
      stops: nextStops,
      backupStops: [],
      clientSavedAt,
      updatedBy,
      updatedAt: serverTimestamp(),
    });
    await assertFails(setDoc(doc(db(outsider), dayPath), day(firstSaved, member)));
    await assertSucceeds(setDoc(doc(db(member), dayPath), day(firstSaved, member)));
    await assertSucceeds(setDoc(doc(db(member), dayPath), day(firstSaved, member)));
    await assertFails(
      setDoc(doc(db(leader), dayPath), day(Timestamp.fromDate(new Date(Date.now() - 86_400_000)), leader)),
    );
    await assertSucceeds(
      setDoc(doc(db(leader), dayPath), day(Timestamp.fromDate(new Date(Date.now() - 5_000)), leader, [])),
    );
    await assertFails(
      setDoc(doc(db(leader), `trips/${tripId}/itinerary/2030-01-03`), {
        ...day(Timestamp.fromDate(new Date(Date.now() + 60 * 60 * 1000)), leader),
        date: "2030-01-03",
      }),
    );

    const history = `trips/${tripId}/itineraryHistory/h1`;
    await assertSucceeds(
      setDoc(doc(db(leader), history), {
        dayId: "2030-01-02",
        snapshot: { stops, clientSavedAt: firstSaved },
        clientSavedAt: firstSaved,
        updatedBy: member,
        recordedBy: leader,
        outcome: "superseded",
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(updateDoc(doc(db(leader), history), { outcome: "lost" }));
    await assertFails(getDoc(doc(db(outsider), history)));
    await assertSucceeds(getDoc(doc(db(member), history)));
  });

  it("caps a day at 5 stops", async () => {
    const stops = (count: number) =>
      Array.from({ length: count }, (_, order) => ({ place_id: `p${order}`, name: "景點", order }));
    const base = (count: number) => ({
      date: "2030-01-04",
      stops: stops(count),
      backupStops: [],
      clientSavedAt: Timestamp.fromDate(new Date(Date.now() - 5_000)),
      updatedBy: member,
      updatedAt: serverTimestamp(),
    });
    await assertFails(setDoc(doc(db(member), `trips/${tripId}/itinerary/2030-01-04`), base(6)));
    await assertSucceeds(setDoc(doc(db(member), `trips/${tripId}/itinerary/2030-01-04`), base(5)));
  });
});

describe("places, votes, sync anchors", () => {
  beforeEach(async () => {
    await seedOpenTrip();
  });

  it("keeps places and votes inside the trip", async () => {
    const place = (coordinatesCachedAt: Timestamp) => ({
      place_id: "ChIJkyoto",
      name: "清水寺",
      proposedBy: member,
      latitude: 34.9949,
      longitude: 135.785,
      coordinatesCachedAt,
      replacesPlaceId: null,
      kind: "proposal",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await assertFails(setDoc(doc(db(outsider), `trips/${tripId}/places/k1`), place(Timestamp.fromDate(new Date()))));
    await assertSucceeds(setDoc(doc(db(member), `trips/${tripId}/places/k1`), place(Timestamp.fromDate(new Date()))));
    await assertFails(
      setDoc(
        doc(db(member), `trips/${tripId}/places/stale`),
        place(Timestamp.fromDate(new Date(Date.now() - 31 * 24 * 60 * 60 * 1000))),
      ),
    );
    await assertSucceeds(
      setDoc(doc(db(leader), `trips/${tripId}/places/k1/votes/${leader}`), {
        value: 1,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db(leader), `trips/${tripId}/places/k1/votes/${member}`), {
        value: -1,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db(member), `trips/${tripId}/places/k1/votes/${member}`), {
        value: 2,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(getDoc(doc(db(outsider), `trips/${tripId}/places/k1`)));
  });

  it("stores a sync anchor only for the signed-in user", async () => {
    const anchor = doc(db(leader), `users/${leader}/syncAnchors/pixel-8`);
    await assertSucceeds(
      setDoc(anchor, {
        phoneWallClockAtSync: Timestamp.fromDate(new Date()),
        elapsedRealtimeAtSyncMs: 50_000,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(getDoc(doc(db(outsider), `users/${leader}/syncAnchors/pixel-8`)));
    await assertFails(
      setDoc(doc(db(leader), `users/${leader}/syncAnchors/pixel-8`), {
        phoneWallClockAtSync: Timestamp.fromDate(new Date()),
        elapsedRealtimeAtSyncMs: -1,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("lets members read handover and soloNotices but not write them yet", async () => {
    await assertSucceeds(getDocs(collection(db(member), `trips/${tripId}/handover`)));
    await assertFails(setDoc(doc(db(member), `trips/${tripId}/handover/h1`), { status: "pending" }));
    await assertSucceeds(getDocs(collection(db(member), `trips/${tripId}/soloNotices`)));
    await assertFails(setDoc(doc(db(leader), `trips/${tripId}/soloNotices/s1`), { memberId: leader }));
    await assertFails(getDocs(collection(db(outsider), `trips/${tripId}/handover`)));
  });
});

describe("invite expiry and invitesOpen", () => {
  beforeEach(async () => {
    await seedOpenTrip();
  });

  async function register(uid: string): Promise<void> {
    await assertSucceeds(setDoc(doc(db(uid), `users/${uid}`), profile(utcMidnightYearsAgo(30), uid)));
  }

  function join(uid: string, code: string) {
    return setDoc(doc(db(uid), `trips/${tripId}/members/${uid}`), joiningMember(uid, code, false));
  }

  it("lets every member mint a code, and one code can be used by several people", async () => {
    await assertSucceeds(setDoc(doc(db(member), "invites/MEMBERCD1"), inviteDoc(member)));
    await assertSucceeds(setDoc(doc(db(deputy), "invites/DEPUTYCD1"), inviteDoc(deputy)));
    await assertSucceeds(setDoc(doc(db(leader), "invites/LEADERCD1"), inviteDoc(leader)));
    const minted = await assertSucceeds(getDoc(doc(db(leader), "invites/MEMBERCD1")));
    assert.equal(minted.get("creatorRole"), "member");
    await assertFails(setDoc(doc(db(outsider), "invites/OUTSIDER1"), inviteDoc(outsider)));
    await assertFails(setDoc(doc(db(member), "invites/FAKELEAD1"), inviteDoc(member, aboutOneHourFromNow(), "leader")));
    await assertFails(setDoc(doc(db(deputy), "invites/FAKEMEMB1"), inviteDoc(deputy, aboutOneHourFromNow(), "member")));
    await assertFails(updateDoc(doc(db(member), "invites/MEMBERCD1"), { active: false }));

    await register("guest-a");
    await register("guest-b");
    await register("guest-c");
    await assertSucceeds(join("guest-a", "MEMBERCD1"));
    await assertSucceeds(join("guest-b", "MEMBERCD1"));
    await assertSucceeds(join("guest-c", "DEPUTYCD1"));

    const tooLate = Timestamp.fromMillis(Date.now() + 61 * 60 * 1000);
    const tooSoon = Timestamp.fromMillis(Date.now() + 30 * 60 * 1000);
    await assertFails(setDoc(doc(db(member), "invites/TOOLATE01"), inviteDoc(member, tooLate)));
    await assertFails(setDoc(doc(db(member), "invites/TOOSOON01"), inviteDoc(member, tooSoon)));
  });

  it("judges expiry from request.time, including a stretched expiresAt", async () => {
    const now = Date.now();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(doc(admin, "invites/STILLGOOD"), {
        tripId,
        tripTitle: "京都自由行",
        createdBy: member,
        creatorRole: "member",
        active: true,
        expiresAt: Timestamp.fromMillis(now + 30 * 60 * 1000),
        createdAt: Timestamp.fromMillis(now - 20 * 60 * 1000),
      });
      await setDoc(doc(admin, "invites/PASTEXP1"), {
        tripId,
        tripTitle: "京都自由行",
        createdBy: leader,
        creatorRole: "leader",
        active: true,
        expiresAt: Timestamp.fromMillis(now - 60 * 1000),
        createdAt: Timestamp.fromMillis(now - 50 * 60 * 1000),
      });
      await setDoc(doc(admin, "invites/STRETCH01"), {
        tripId,
        tripTitle: "京都自由行",
        createdBy: deputy,
        creatorRole: "deputy",
        active: true,
        expiresAt: Timestamp.fromMillis(now + 30 * 60 * 1000),
        createdAt: Timestamp.fromMillis(now - 61 * 60 * 1000),
      });
    });

    await register("hour-guest");
    await assertSucceeds(join("hour-guest", "STILLGOOD"));
    await register("past-guest");
    await assertFails(join("past-guest", "PASTEXP1"));
    await register("long-guest");
    await assertFails(join("long-guest", "STRETCH01"));
  });

  it("closes invites by killing only member codes, while officer codes keep their hour", async () => {
    await assertSucceeds(setDoc(doc(db(member), "invites/MEMBERCD1"), inviteDoc(member)));
    await assertSucceeds(setDoc(doc(db(leader), "invites/LEADERCD1"), inviteDoc(leader)));
    await assertSucceeds(setDoc(doc(db(deputy), "invites/DEPUTYCD1"), inviteDoc(deputy)));
    await register("before-guest");
    await assertSucceeds(join("before-guest", "LEADERCD1"));

    const trip = `trips/${tripId}`;
    await assertFails(
      updateDoc(doc(db(member), trip), {
        invitesOpen: false,
        invitesResetAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db(deputy), trip), {
        invitesOpen: false,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db(deputy), trip), {
        invitesOpen: false,
        invitesResetAt: Timestamp.fromDate(new Date("2030-01-01T00:00:00Z")),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(leader), trip), {
        invitesOpen: false,
        invitesResetAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );

    const closed = await assertSucceeds(getDoc(doc(db(leader), trip)));
    assert.equal(closed.get("invitesOpen"), false);
    const resetAt = closed.get("invitesResetAt") as Timestamp;
    assert.ok(Math.abs(Date.now() - resetAt.toMillis()) < 2 * 60 * 1000);

    await register("after-guest");
    await assertFails(join("after-guest", "MEMBERCD1"));
    await register("leader-guest");
    await assertSucceeds(join("leader-guest", "LEADERCD1"));
    await register("deputy-guest");
    await assertSucceeds(join("deputy-guest", "DEPUTYCD1"));
    await assertFails(setDoc(doc(db(member), "invites/MEMBERCD2"), inviteDoc(member)));
    await assertSucceeds(setDoc(doc(db(leader), "invites/LEADERCD2"), inviteDoc(leader)));
    await assertSucceeds(setDoc(doc(db(deputy), "invites/DEPUTYCD2"), inviteDoc(deputy)));
    await register("after-guest-2");
    await assertSucceeds(join("after-guest-2", "LEADERCD2"));
    await register("after-guest-3");
    await assertSucceeds(join("after-guest-3", "DEPUTYCD2"));
  });

  it("uses creatorRole from mint time, so a later promotion does not save a member code", async () => {
    await assertSucceeds(setDoc(doc(db(member), "invites/MEMBERCD1"), inviteDoc(member)));
    await assertSucceeds(setDoc(doc(db(deputy), "invites/DEPUTYCD1"), inviteDoc(deputy)));
    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}/members/${member}`), { role: "deputy" }),
    );
    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}/members/${deputy}`), { role: "member" }),
    );
    await assertSucceeds(
      updateDoc(doc(db(leader), `trips/${tripId}`), {
        invitesOpen: false,
        invitesResetAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );

    await register("role-guest");
    await assertFails(join("role-guest", "MEMBERCD1"));
    await assertSucceeds(join("role-guest", "DEPUTYCD1"));
    await assertFails(setDoc(doc(db(deputy), "invites/DEPUTYCD2"), inviteDoc(deputy, aboutOneHourFromNow(), "member")));
    await assertSucceeds(setDoc(doc(db(member), "invites/MEMBERCD2"), inviteDoc(member, aboutOneHourFromNow(), "deputy")));
    await register("role-guest-2");
    await assertSucceeds(join("role-guest-2", "MEMBERCD2"));
  });

  it("keeps the member-code cutoff after invites reopen, and a later close kills member codes minted in between", async () => {
    await assertSucceeds(setDoc(doc(db(member), "invites/MEMBERCD1"), inviteDoc(member)));
    await assertSucceeds(setDoc(doc(db(leader), "invites/LEADERCD1"), inviteDoc(leader)));
    const trip = `trips/${tripId}`;
    await assertSucceeds(
      updateDoc(doc(db(leader), trip), {
        invitesOpen: false,
        invitesResetAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    const firstReset = (await assertSucceeds(getDoc(doc(db(leader), trip)))).get("invitesResetAt") as Timestamp;
    await assertSucceeds(setDoc(doc(db(deputy), "invites/DEPUTYCD2"), inviteDoc(deputy)));

    await assertFails(
      updateDoc(doc(db(deputy), trip), {
        invitesOpen: true,
        invitesResetAt: null,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(deputy), trip), {
        invitesOpen: true,
        updatedAt: serverTimestamp(),
      }),
    );
    const reopened = await assertSucceeds(getDoc(doc(db(leader), trip)));
    assert.equal(reopened.get("invitesOpen"), true);
    assert.equal((reopened.get("invitesResetAt") as Timestamp).toMillis(), firstReset.toMillis());

    await register("old-guest");
    await assertFails(join("old-guest", "MEMBERCD1"));
    await register("leader-still");
    await assertSucceeds(join("leader-still", "LEADERCD1"));
    await register("deputy-still");
    await assertSucceeds(join("deputy-still", "DEPUTYCD2"));

    await assertSucceeds(setDoc(doc(db(member), "invites/MEMBERCD3"), inviteDoc(member)));
    await register("new-guest");
    await assertSucceeds(join("new-guest", "MEMBERCD3"));

    await assertSucceeds(
      updateDoc(doc(db(deputy), trip), {
        invitesOpen: false,
        invitesResetAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    const secondReset = (await assertSucceeds(getDoc(doc(db(leader), trip)))).get("invitesResetAt") as Timestamp;
    assert.ok(secondReset.toMillis() > firstReset.toMillis());

    await register("killed-guest");
    await assertFails(join("killed-guest", "MEMBERCD3"));
    await assertFails(join("killed-guest", "MEMBERCD1"));
    await assertSucceeds(join("killed-guest", "DEPUTYCD2"));
    await register("leader-still-2");
    await assertSucceeds(join("leader-still-2", "LEADERCD1"));
    await assertFails(setDoc(doc(db(member), "invites/MEMBERCD4"), inviteDoc(member)));
    await assertSucceeds(setDoc(doc(db(deputy), "invites/DEPUTYCD3"), inviteDoc(deputy)));
    await register("fresh-guest");
    await assertSucceeds(join("fresh-guest", "DEPUTYCD3"));
  });
});

describe("clock probe", () => {
  it("lets only the owner write and read t equal to request.time", async () => {
    const uid = "probe-owner";
    const path = `clockProbes/${uid}`;
    const localBefore = Date.now();
    await assertSucceeds(setDoc(doc(db(uid), path), { t: serverTimestamp() }));
    const saved = await assertSucceeds(getDoc(doc(db(uid), path)));
    const serverT = saved.get("t") as Timestamp;
    assert.deepEqual(Object.keys(saved.data() ?? {}), ["t"]);
    assert.ok(Math.abs(serverT.toMillis() - localBefore) < 2 * 60 * 1000);
    const offsetMs = serverT.toMillis() - Date.now();
    assert.ok(Math.abs(offsetMs) < 2 * 60 * 1000);

    await assertSucceeds(updateDoc(doc(db(uid), path), { t: serverTimestamp() }));
    await assertFails(setDoc(doc(db("fresh-probe"), "clockProbes/fresh-probe"), { t: Timestamp.fromMillis(Date.now()) }));
    await assertFails(setDoc(doc(db(uid), path), { t: Timestamp.fromMillis(Date.now()) }));
    await assertFails(setDoc(doc(db(uid), path), { t: serverTimestamp(), extra: true }));
    await assertFails(updateDoc(doc(db(uid), path), { note: "no" }));
    await assertFails(deleteDoc(doc(db(uid), path)));
    await assertFails(getDocs(collection(db(uid), "clockProbes")));

    await assertFails(getDoc(doc(db("other-probe"), path)));
    await assertFails(setDoc(doc(db("other-probe"), path), { t: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(db("other-probe"), "clockProbes/other-probe"), { t: serverTimestamp() }));
    await assertFails(getDoc(doc(db(uid), "clockProbes/other-probe")));

    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, path)));
    await assertFails(setDoc(doc(anon, path), { t: serverTimestamp() }));
  });
});
