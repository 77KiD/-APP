import { incomingCorrectedSaveWins } from "./clockCorrection";

/** Day fields the revision trigger compares. `clientSavedAt` is already corrected (ADR 0004). */
export type ItineraryFields = {
  date: string;
  stops: unknown[];
  backupStops: unknown[];
  clientSavedAt: { toMillis(): number } | null;
  updatedBy: string;
  updatedAt?: unknown;
  serverRestored?: boolean;
};

export type HistoryWrite = {
  dayId: string;
  snapshot: {
    stops: unknown[];
    backupStops: unknown[];
    clientSavedAt: { toMillis(): number } | null;
    updatedBy: string;
  };
  clientSavedAt: { toMillis(): number } | null;
  updatedBy: string;
  recordedBy: string;
  outcome: "superseded" | "lost";
};

export type RevisionDecision =
  | { kind: "noop" }
  | { kind: "clearMarker" }
  | { kind: "record"; outcome: "superseded" | "lost"; archived: ItineraryFields; restore: ItineraryFields | null };

function savedAtMs(value: { toMillis(): number } | null | undefined): number | null {
  if (!value || typeof value.toMillis !== "function") return null;
  return value.toMillis();
}

function sameContent(left: ItineraryFields, right: ItineraryFields): boolean {
  return left.date === right.date
    && left.updatedBy === right.updatedBy
    && savedAtMs(left.clientSavedAt) === savedAtMs(right.clientSavedAt)
    && JSON.stringify(left.stops) === JSON.stringify(right.stops)
    && JSON.stringify(left.backupStops) === JSON.stringify(right.backupStops);
}

function withoutMarker(day: ItineraryFields): ItineraryFields {
  return {
    date: day.date,
    stops: day.stops,
    backupStops: day.backupStops,
    clientSavedAt: day.clientSavedAt,
    updatedBy: day.updatedBy,
    updatedAt: day.updatedAt,
  };
}

/**
 * Last-write-wins by corrected clientSavedAt.
 * A newer incoming write is kept and `before` is archived.
 * An older incoming write is archived and `before` is restored with `serverRestored`
 * so the follow-up trigger does not archive it again.
 */
export function decideItineraryRevision(
  before: ItineraryFields | null,
  after: ItineraryFields | null,
): RevisionDecision {
  if (!after) return { kind: "noop" };
  if (after.serverRestored === true) return { kind: "clearMarker" };
  if (!before) return { kind: "noop" };
  if (before.serverRestored === true && sameContent(before, after)) return { kind: "noop" };
  if (sameContent(before, after)) return { kind: "noop" };

  const beforeMs = savedAtMs(before.clientSavedAt);
  const afterMs = savedAtMs(after.clientSavedAt);
  if (beforeMs == null || afterMs == null) return { kind: "noop" };

  if (incomingCorrectedSaveWins(afterMs, beforeMs)) {
    return { kind: "record", outcome: "superseded", archived: withoutMarker(before), restore: null };
  }
  return {
    kind: "record",
    outcome: "lost",
    archived: withoutMarker(after),
    restore: { ...withoutMarker(before), serverRestored: true },
  };
}

/** True while the day document is still the losing write, so a restore will not cover a newer edit. */
export function shouldRestoreOver(current: ItineraryFields | null, loser: ItineraryFields | null): boolean {
  if (!current || !loser) return false;
  return sameContent(current, loser);
}

export function historyDocId(eventId: string): string {
  return eventId.replaceAll("/", "_");
}

export function historyFromDay(dayId: string, recordedBy: string, archived: ItineraryFields, outcome: "superseded" | "lost"): HistoryWrite {
  return {
    dayId,
    snapshot: {
      stops: archived.stops,
      backupStops: archived.backupStops,
      clientSavedAt: archived.clientSavedAt,
      updatedBy: archived.updatedBy,
    },
    clientSavedAt: archived.clientSavedAt,
    updatedBy: archived.updatedBy,
    recordedBy,
    outcome,
  };
}

function isAlreadyExists(error: unknown): boolean {
  const code = (error as { code?: number | string }).code;
  return code === 6 || code === "already-exists" || code === "ALREADY_EXISTS";
}

export async function applyItineraryRevision(args: {
  eventId: string;
  dayId: string;
  recordedBy: string;
  before: ItineraryFields | null;
  after: ItineraryFields | null;
  createHistory: (id: string, data: HistoryWrite) => Promise<void>;
  writeDay: (data: ItineraryFields) => Promise<void>;
  clearMarker: () => Promise<void>;
}): Promise<"noop" | "clearMarker" | "recorded" | "restored"> {
  const decision = decideItineraryRevision(args.before, args.after);
  if (decision.kind === "noop") return "noop";
  if (decision.kind === "clearMarker") {
    await args.clearMarker();
    return "clearMarker";
  }

  try {
    await args.createHistory(
      historyDocId(args.eventId),
      historyFromDay(args.dayId, args.recordedBy, decision.archived, decision.outcome),
    );
  } catch (error) {
    if (!isAlreadyExists(error)) throw error;
  }

  if (decision.restore) {
    await args.writeDay(decision.restore);
    return "restored";
  }
  return "recorded";
}
