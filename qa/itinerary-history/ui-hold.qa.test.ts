import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  initialHold,
  onSnapshot,
  onTick,
  RESTORE_HOLD_TIMEOUT_MS,
  shouldShowOlderEditNotice,
  type ItinerarySnapshot,
} from "./uiHold.ts";

function snap(ms: number, name: string, updatedBy: string): ItinerarySnapshot {
  return {
    clientSavedAtMs: ms,
    stops: [{ name }],
    backupStops: [{ name: "備選" }],
    updatedBy,
  };
}

describe("T25-11 hold until restore", () => {
  it("keeps the newer screen when an older clientSavedAt arrives", () => {
    const newer = snap(2_000, "新", "b");
    let state = initialHold(newer);
    state = onSnapshot(state, snap(1_000, "舊", "a"), 10_000);
    assert.equal(state.displayed.updatedBy, "b");
    assert.equal(state.held?.pending.updatedBy, "a");
    assert.equal(state.restoreFailed, false);
    state = onSnapshot(state, newer, 10_500);
    assert.equal(state.displayed.updatedBy, "b");
    assert.equal(state.held, null);
  });
});

describe("T25-12 restore timeout", () => {
  it("does not stay held once the timeout passes", () => {
    const newer = snap(2_000, "新", "b");
    let state = onSnapshot(initialHold(newer), snap(1_000, "舊", "a"), 0);
    state = onTick(state, RESTORE_HOLD_TIMEOUT_MS - 1);
    assert.equal(state.displayed.updatedBy, "b");
    assert.equal(state.restoreFailed, false);
    state = onTick(state, RESTORE_HOLD_TIMEOUT_MS);
    assert.equal(state.displayed.updatedBy, "a");
    assert.equal(state.held, null);
    assert.equal(state.restoreFailed, true);
  });
});

describe("T25-13 lost-edit notice", () => {
  it("shows the notice only to the latest lost recordedBy", () => {
    const history = [
      { outcome: "lost" as const, recordedBy: "a", createdAtMs: 1 },
      { outcome: "superseded" as const, recordedBy: "c", createdAtMs: 3 },
      { outcome: "lost" as const, recordedBy: "a", createdAtMs: 2 },
    ];
    assert.equal(shouldShowOlderEditNotice("a", history), true);
    assert.equal(shouldShowOlderEditNotice("b", history), false);
    assert.equal(shouldShowOlderEditNotice("c", history), false);
    assert.equal(shouldShowOlderEditNotice("a", [{ outcome: "superseded", recordedBy: "a", createdAtMs: 1 }]), false);
  });
});
