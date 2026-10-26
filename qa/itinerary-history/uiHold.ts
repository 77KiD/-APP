/** Contract for the #25 client. The Flutter app does not use this module yet. */

export type ItinerarySnapshot = {
  clientSavedAtMs: number;
  stops: unknown;
  backupStops: unknown;
  updatedBy: string;
};

export type HoldState = {
  displayed: ItinerarySnapshot;
  /** Older snapshot kept off-screen until restore or timeout. */
  held: { sinceMs: number; pending: ItinerarySnapshot } | null;
  restoreFailed: boolean;
};

export const RESTORE_HOLD_TIMEOUT_MS = 5_000;

export function initialHold(displayed: ItinerarySnapshot): HoldState {
  return { displayed, held: null, restoreFailed: false };
}

/** Incoming listener event. An older clientSavedAt does not replace the screen. */
export function onSnapshot(state: HoldState, incoming: ItinerarySnapshot, nowMs: number): HoldState {
  if (incoming.clientSavedAtMs >= state.displayed.clientSavedAtMs) {
    return { displayed: incoming, held: null, restoreFailed: false };
  }
  return {
    displayed: state.displayed,
    held: { sinceMs: state.held?.sinceMs ?? nowMs, pending: incoming },
    restoreFailed: false,
  };
}

/** Clock tick. If the restore never arrives, leave the hold and show the server document. */
export function onTick(state: HoldState, nowMs: number, timeoutMs = RESTORE_HOLD_TIMEOUT_MS): HoldState {
  if (!state.held) return state;
  if (nowMs - state.held.sinceMs < timeoutMs) return state;
  return {
    displayed: state.held.pending,
    held: null,
    restoreFailed: true,
  };
}

export type HistoryEntry = {
  outcome: "superseded" | "lost";
  recordedBy: string;
  createdAtMs: number;
};

/** Only the author of the latest lost row sees the offline-edit notice. */
export function shouldShowOlderEditNotice(uid: string, history: HistoryEntry[]): boolean {
  const lost = history.filter((entry) => entry.outcome === "lost");
  if (lost.length === 0) return false;
  const latest = lost.reduce((best, entry) => (entry.createdAtMs >= best.createdAtMs ? entry : best));
  return latest.recordedBy === uid;
}
