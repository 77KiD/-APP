/**
 * Offline save-time correction (ADR 0004). The Flutter client applies this
 * formula; docs/data-model.md 「離線同步」 is the contract these tests lock.
 *
 * offsetMs = anchor.updatedAtMs - anchor.phoneWallClockAtSyncMs
 * If the device was not rebooted (elapsedRealtime still monotonic):
 *   clientSavedAtMs = anchor.updatedAtMs + (elapsedNow - elapsedAtSync)
 * If elapsedRealtime reset (reboot):
 *   clientSavedAtMs = phoneWallClockNowMs + offsetMs
 */

export type SyncAnchor = {
  /** Server `updatedAt` of users/{uid}/syncAnchors/{deviceId}, in epoch ms. */
  updatedAtMs: number;
  /** Phone wall clock sent with that sync, in epoch ms. */
  phoneWallClockAtSyncMs: number;
  /** Android SystemClock.elapsedRealtime() at that sync, in ms. */
  elapsedRealtimeAtSyncMs: number;
};

export type ClockSample = {
  elapsedRealtimeNowMs: number;
  phoneWallClockNowMs: number;
};

export function clockOffsetMs(anchor: SyncAnchor): number {
  return anchor.updatedAtMs - anchor.phoneWallClockAtSyncMs;
}

export function deviceRebootedSinceSync(anchor: SyncAnchor, sample: ClockSample): boolean {
  return sample.elapsedRealtimeNowMs < anchor.elapsedRealtimeAtSyncMs;
}

/** Last-write-wins on corrected clientSavedAt. An equal timestamp keeps the incoming write. */
export function incomingCorrectedSaveWins(incomingMs: number, existingMs: number): boolean {
  return incomingMs >= existingMs;
}

export function correctedClientSavedAtMs(anchor: SyncAnchor, sample: ClockSample): number {
  if (!deviceRebootedSinceSync(anchor, sample)) {
    return anchor.updatedAtMs + (sample.elapsedRealtimeNowMs - anchor.elapsedRealtimeAtSyncMs);
  }
  return sample.phoneWallClockNowMs + clockOffsetMs(anchor);
}
