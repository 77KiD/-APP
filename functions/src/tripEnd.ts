/**
 * When a trip auto-ends. Reads the current `expectedReturnAt` (the editable
 * 預計回程時間). If it is set, that instant wins over 結束日 23:59.
 * If it is null, the trip ends at endDate 23:59:00 in `timeZone`.
 * See docs/data-model.md 「旅程自動結束」.
 */

export type AutoEndReason = "expected_return" | "end_date";

export type TripEndInput = {
  status: string;
  endDate: string;
  timeZone: string;
  expectedReturnAt: Date | null;
};

export class InvalidTripEndData extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidTripEndData";
  }
}

const OPEN_STATUSES = new Set(["planning", "active"]);

export function shouldClearLocations(
  beforeStatus: string | undefined,
  afterStatus: string | undefined,
): boolean {
  return beforeStatus !== "ended" && afterStatus === "ended";
}

function assertCalendarDate(date: string): { year: number; month: number; day: number } {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (!match) {
    throw new InvalidTripEndData(`endDate is not YYYY-MM-DD: ${date}`);
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const probe = new Date(Date.UTC(year, month - 1, day));
  if (
    probe.getUTCFullYear() !== year ||
    probe.getUTCMonth() !== month - 1 ||
    probe.getUTCDate() !== day
  ) {
    throw new InvalidTripEndData(`endDate is not a calendar date: ${date}`);
  }
  return { year, month, day };
}

function zoneOffsetMs(instant: Date, timeZone: string): number {
  let formatter: Intl.DateTimeFormat;
  let formatted: Intl.DateTimeFormatPart[];
  try {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    formatted = formatter.formatToParts(instant);
  } catch {
    throw new InvalidTripEndData(`invalid timeZone: ${timeZone}`);
  }
  const parts: Record<string, string> = {};
  for (const part of formatted) {
    if (part.type !== "literal") parts[part.type] = part.value;
  }
  let year = Number(parts.year);
  let month = Number(parts.month);
  let day = Number(parts.day);
  let hour = Number(parts.hour);
  if (hour === 24) {
    hour = 0;
    const rolled = new Date(Date.UTC(year, month - 1, day) + 24 * 60 * 60 * 1000);
    year = rolled.getUTCFullYear();
    month = rolled.getUTCMonth() + 1;
    day = rolled.getUTCDate();
  }
  const asUtc = Date.UTC(year, month - 1, day, hour, Number(parts.minute), Number(parts.second));
  return asUtc - instant.getTime();
}

/** Wall-clock `date` + `time` in an IANA zone, as a UTC instant. */
export function zonedLocalToUtc(date: string, time: string, timeZone: string): Date {
  const { year, month, day } = assertCalendarDate(date);
  if (!/^\d{2}:\d{2}:\d{2}$/.test(time)) {
    throw new InvalidTripEndData(`time is not HH:mm:ss: ${time}`);
  }
  const [hour, minute, second] = time.split(":").map(Number);
  if (hour > 23 || minute > 59 || second > 59) {
    throw new InvalidTripEndData(`time is not HH:mm:ss: ${time}`);
  }
  let utc = Date.UTC(year, month - 1, day, hour, minute, second);
  for (let i = 0; i < 3; i += 1) {
    const offset = zoneOffsetMs(new Date(utc), timeZone);
    const adjusted = Date.UTC(year, month - 1, day, hour, minute, second) - offset;
    if (adjusted === utc) break;
    utc = adjusted;
  }
  return new Date(utc);
}

/** 結束日當天 23:59:00 in the trip's timezone. */
export function endOfTripDayUtc(endDate: string, timeZone: string): Date {
  return zonedLocalToUtc(endDate, "23:59:00", timeZone);
}

/**
 * Returns why the trip should auto-end at `now`, or null if it should stay open.
 * Throws InvalidTripEndData when stored fields cannot be interpreted — callers
 * skip that trip instead of guessing.
 */
export function endReasonAt(trip: TripEndInput, now: Date): AutoEndReason | null {
  if (trip.status === "ended") return null;
  if (!OPEN_STATUSES.has(trip.status)) {
    throw new InvalidTripEndData(`unknown status: ${trip.status}`);
  }
  if (trip.expectedReturnAt) {
    if (Number.isNaN(trip.expectedReturnAt.getTime())) {
      throw new InvalidTripEndData("expectedReturnAt is invalid");
    }
    return now.getTime() >= trip.expectedReturnAt.getTime() ? "expected_return" : null;
  }
  const deadline = endOfTripDayUtc(trip.endDate, trip.timeZone);
  return now.getTime() >= deadline.getTime() ? "end_date" : null;
}

type MaybeTimestamp = { toDate: () => Date };

function isTimestampLike(value: unknown): value is MaybeTimestamp {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { toDate?: unknown }).toDate === "function"
  );
}

export function tripEndInputFromData(data: Record<string, unknown>): TripEndInput {
  if (typeof data.status !== "string") {
    throw new InvalidTripEndData("status missing");
  }
  if (typeof data.endDate !== "string" || typeof data.timeZone !== "string") {
    throw new InvalidTripEndData("endDate or timeZone missing");
  }
  const raw = data.expectedReturnAt;
  let expectedReturnAt: Date | null = null;
  if (raw != null) {
    if (!isTimestampLike(raw)) {
      throw new InvalidTripEndData("expectedReturnAt is not a timestamp");
    }
    const date = raw.toDate();
    if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
      throw new InvalidTripEndData("expectedReturnAt is not a timestamp");
    }
    expectedReturnAt = date;
  }
  return {
    status: data.status,
    endDate: data.endDate,
    timeZone: data.timeZone,
    expectedReturnAt,
  };
}
