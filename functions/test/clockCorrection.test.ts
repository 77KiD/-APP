import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  clockOffsetMs,
  correctedClientSavedAtMs,
  incomingCorrectedSaveWins,
  type SyncAnchor,
} from "../src/clockCorrection";

/**
 * Numbers copied from docs/data-model.md 「離線同步」.
 * Phone wall clock is 1 hour ahead of the server at sync.
 */
const anchor: SyncAnchor = {
  updatedAtMs: 1_000_000_000_000,
  phoneWallClockAtSyncMs: 1_000_000_000_000 + 3_600_000,
  elapsedRealtimeAtSyncMs: 50_000,
};

describe("correctedClientSavedAtMs", () => {
  it("records offset as server time minus the phone wall clock", () => {
    assert.equal(clockOffsetMs(anchor), -3_600_000);
  });

  it("uses elapsedRealtime while the device has not rebooted, ignoring a wrong wall clock", () => {
    const saved = correctedClientSavedAtMs(anchor, {
      elapsedRealtimeNowMs: 80_000,
      phoneWallClockNowMs: 1_000_000_999_999,
    });
    assert.equal(saved, 1_000_000_030_000);
  });

  it("falls back to phone wall clock plus the last offset after reboot", () => {
    const saved = correctedClientSavedAtMs(anchor, {
      elapsedRealtimeNowMs: 1_000,
      phoneWallClockNowMs: 1_000_000_100_000,
    });
    assert.equal(saved, 999_996_500_000);
  });

  it("lets the earlier edit win when it syncs later (ADR 0004 10:00 vs 09:00)", () => {
    const ten = correctedClientSavedAtMs(anchor, {
      elapsedRealtimeNowMs: anchor.elapsedRealtimeAtSyncMs + 60 * 60 * 1000,
      phoneWallClockNowMs: 0,
    });
    const nine = correctedClientSavedAtMs(anchor, {
      elapsedRealtimeNowMs: anchor.elapsedRealtimeAtSyncMs + 59 * 60 * 1000,
      phoneWallClockNowMs: 0,
    });
    assert.ok(ten > nine);
    assert.equal(incomingCorrectedSaveWins(ten, nine), true);
    assert.equal(incomingCorrectedSaveWins(nine, ten), false);
    assert.equal(incomingCorrectedSaveWins(ten, ten), true);
  });
});
