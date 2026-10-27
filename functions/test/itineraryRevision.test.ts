import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { correctedClientSavedAtMs, type SyncAnchor } from "../src/clockCorrection";
import {
  applyItineraryRevision,
  decideItineraryRevision,
  historyDocId,
  shouldRestoreOver,
  type HistoryWrite,
  type ItineraryFields,
} from "../src/itineraryRevision";

const anchor: SyncAnchor = {
  updatedAtMs: 1_000_000_000_000,
  phoneWallClockAtSyncMs: 1_000_000_000_000 + 3_600_000,
  elapsedRealtimeAtSyncMs: 50_000,
};

const tenMs = correctedClientSavedAtMs(anchor, {
  elapsedRealtimeNowMs: anchor.elapsedRealtimeAtSyncMs + 60 * 60 * 1000,
  phoneWallClockNowMs: 0,
});
const nineMs = correctedClientSavedAtMs(anchor, {
  elapsedRealtimeNowMs: anchor.elapsedRealtimeAtSyncMs + 59 * 60 * 1000,
  phoneWallClockNowMs: 0,
});

const backups = [
  { place_id: "backup-a", name: "備選甲", order: 0 },
  { place_id: "backup-b", name: "備選乙", order: 1 },
];

function at(ms: number) {
  return { toMillis: () => ms };
}

function day(partial: Partial<ItineraryFields> & { clientSavedAtMs: number }): ItineraryFields {
  return {
    date: "2030-01-02",
    stops: partial.stops ?? [{ place_id: "stop", name: "清水寺", order: 0 }],
    backupStops: partial.backupStops ?? backups,
    clientSavedAt: at(partial.clientSavedAtMs),
    updatedBy: partial.updatedBy ?? "editor",
    updatedAt: partial.updatedAt ?? at(partial.clientSavedAtMs),
    serverRestored: partial.serverRestored,
  };
}

describe("decideItineraryRevision", () => {
  it("keeps the later corrected save when an older offline edit arrives after it", () => {
    const newer = day({ clientSavedAtMs: tenMs, updatedBy: "ten", backupStops: backups });
    const older = day({
      clientSavedAtMs: nineMs,
      updatedBy: "nine",
      stops: [{ place_id: "other", name: "其他", order: 0 }],
      backupStops: [],
    });
    const decision = decideItineraryRevision(newer, older);
    assert.equal(decision.kind, "record");
    if (decision.kind !== "record") return;
    assert.equal(decision.outcome, "lost");
    assert.equal(decision.restore?.serverRestored, true);
    assert.deepEqual(decision.restore?.backupStops, backups);
    assert.equal(decision.restore?.updatedBy, "ten");
    assert.deepEqual(decision.archived.backupStops, []);
    assert.equal(decision.archived.updatedBy, "nine");
  });

  it("archives the previous version when the incoming corrected save is newer", () => {
    const older = day({ clientSavedAtMs: nineMs, updatedBy: "nine", backupStops: backups });
    const newer = day({
      clientSavedAtMs: tenMs,
      updatedBy: "ten",
      stops: [{ place_id: "later", name: "十點", order: 0 }],
      backupStops: backups,
    });
    const decision = decideItineraryRevision(older, newer);
    assert.equal(decision.kind, "record");
    if (decision.kind !== "record") return;
    assert.equal(decision.outcome, "superseded");
    assert.equal(decision.restore, null);
    assert.deepEqual(decision.archived.backupStops, backups);
    assert.equal(decision.archived.updatedBy, "nine");
  });

  it("ignores the marker-clearing write so a restore does not loop", () => {
    const restored = day({ clientSavedAtMs: tenMs, serverRestored: true });
    assert.equal(decideItineraryRevision(day({ clientSavedAtMs: nineMs }), restored).kind, "clearMarker");
    const cleared = day({ clientSavedAtMs: tenMs });
    assert.equal(decideItineraryRevision(restored, cleared).kind, "noop");
  });

  it("writes no history for the first create, an identical resend, or an equal timestamp that already matches", () => {
    const created = day({ clientSavedAtMs: tenMs });
    assert.equal(decideItineraryRevision(null, created).kind, "noop");
    assert.equal(decideItineraryRevision(created, created).kind, "noop");
    assert.equal(decideItineraryRevision(created, null).kind, "noop");
  });

  it("keeps the incoming write when corrected clientSavedAt is equal", () => {
    const existing = day({ clientSavedAtMs: tenMs, updatedBy: "first", stops: [{ place_id: "a", name: "甲", order: 0 }] });
    const incoming = day({ clientSavedAtMs: tenMs, updatedBy: "second", stops: [{ place_id: "b", name: "乙", order: 0 }] });
    const decision = decideItineraryRevision(existing, incoming);
    assert.equal(decision.kind, "record");
    if (decision.kind !== "record") return;
    assert.equal(decision.outcome, "superseded");
    assert.equal(decision.restore, null);
    assert.equal(decision.archived.updatedBy, "first");
  });
});

describe("shouldRestoreOver", () => {
  it("restores only while the stored day is still the losing edit", () => {
    const winner = day({ clientSavedAtMs: tenMs, updatedBy: "ten", backupStops: backups });
    const loser = day({
      clientSavedAtMs: nineMs,
      updatedBy: "nine",
      stops: [{ place_id: "old", name: "九點", order: 0 }],
      backupStops: [],
    });
    assert.equal(shouldRestoreOver(loser, loser), true);
    assert.equal(shouldRestoreOver(winner, loser), false);
    assert.equal(shouldRestoreOver(null, loser), false);
    assert.equal(shouldRestoreOver({ ...loser, serverRestored: true }, loser), true);
  });
});

describe("applyItineraryRevision", () => {
  it("is idempotent on the event id and preserves backupStops of the winning edit", async () => {
    const history = new Map<string, HistoryWrite>();
    const days: ItineraryFields[] = [];
    let clears = 0;
    const run = () =>
      applyItineraryRevision({
        eventId: "projects/demo/events/evt-1",
        dayId: "2030-01-02",
        recordedBy: "server",
        before: day({ clientSavedAtMs: tenMs, updatedBy: "ten", backupStops: backups }),
        after: day({
          clientSavedAtMs: nineMs,
          updatedBy: "nine",
          stops: [{ place_id: "old", name: "九點", order: 0 }],
          backupStops: [],
        }),
        createHistory: async (id, data) => {
          if (history.has(id)) {
            const error = new Error("exists") as Error & { code: string };
            error.code = "already-exists";
            throw error;
          }
          history.set(id, data);
        },
        writeDay: async (data) => {
          days.push(data);
        },
        clearMarker: async () => {
          clears += 1;
        },
      });

    assert.equal(await run(), "restored");
    assert.equal(await run(), "restored");
    assert.equal(history.size, 1);
    assert.equal(historyDocId("projects/demo/events/evt-1"), "projects_demo_events_evt-1");
    const archived = history.get("projects_demo_events_evt-1");
    assert.equal(archived?.outcome, "lost");
    assert.equal(archived?.recordedBy, "server");
    assert.deepEqual(archived?.snapshot.backupStops, []);
    assert.equal(archived?.snapshot.updatedBy, "nine");
    assert.equal(days.length, 2);
    assert.deepEqual(days[0]?.backupStops, backups);
    assert.equal(days[0]?.updatedBy, "ten");
    assert.equal(days[0]?.serverRestored, true);
    assert.equal(clears, 0);

    const restored = days[0];
    if (!restored) throw new Error("missing restore");
    assert.equal(
      await applyItineraryRevision({
        eventId: "evt-clear",
        dayId: "2030-01-02",
        recordedBy: "server",
        before: day({ clientSavedAtMs: nineMs, updatedBy: "nine", backupStops: [] }),
        after: restored,
        createHistory: async () => {
          throw new Error("history should not be written while clearing the marker");
        },
        writeDay: async () => {
          throw new Error("day should not be rewritten while clearing the marker");
        },
        clearMarker: async () => {
          clears += 1;
        },
      }),
      "clearMarker",
    );
    assert.equal(clears, 1);
  });
});
