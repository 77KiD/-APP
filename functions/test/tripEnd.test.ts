import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  endOfTripDayUtc,
  endReasonAt,
  InvalidTripEndData,
  shouldClearLocations,
  tripEndInputFromData,
  type TripEndInput,
} from "../src/tripEnd";

const taipei: TripEndInput = {
  status: "active",
  endDate: "2026-10-26",
  timeZone: "Asia/Taipei",
  expectedReturnAt: null,
};

describe("endOfTripDayUtc", () => {
  it("is 23:59:00 in Asia/Taipei", () => {
    assert.equal(endOfTripDayUtc("2026-10-26", "Asia/Taipei").toISOString(), "2026-10-26T15:59:00.000Z");
  });

  it("is 23:59:00 in Asia/Tokyo", () => {
    assert.equal(endOfTripDayUtc("2026-10-26", "Asia/Tokyo").toISOString(), "2026-10-26T14:59:00.000Z");
  });

  it("is 23:59:00 in America/New_York during EDT", () => {
    assert.equal(
      endOfTripDayUtc("2026-10-26", "America/New_York").toISOString(),
      "2026-10-27T03:59:00.000Z",
    );
  });
});

describe("endReasonAt", () => {
  it("ends at local 23:59 when 預計回程時間 is unset", () => {
    assert.equal(endReasonAt(taipei, new Date("2026-10-26T15:58:59.999Z")), null);
    assert.equal(endReasonAt(taipei, new Date("2026-10-26T15:59:00.000Z")), "end_date");
  });

  it("uses the current expectedReturnAt even after the end-date deadline", () => {
    const delayed = {
      ...taipei,
      expectedReturnAt: new Date("2026-10-27T00:00:00.000Z"),
    };
    assert.equal(endReasonAt(delayed, new Date("2026-10-26T16:00:00.000Z")), null);
    assert.equal(endReasonAt(delayed, new Date("2026-10-27T00:00:00.000Z")), "expected_return");
  });

  it("follows an edit that pushes 預計回程時間 two hours later", () => {
    const now = new Date("2026-10-26T11:00:00.000Z");
    const early = { ...taipei, expectedReturnAt: new Date("2026-10-26T10:00:00.000Z") };
    const delayed = { ...taipei, expectedReturnAt: new Date("2026-10-26T12:00:00.000Z") };
    assert.equal(endReasonAt(early, now), "expected_return");
    assert.equal(endReasonAt(delayed, now), null);
  });

  it("ends a planning trip the same way as an active trip", () => {
    assert.equal(
      endReasonAt({ ...taipei, status: "planning" }, new Date("2026-10-26T15:59:00.000Z")),
      "end_date",
    );
  });

  it("leaves an already ended trip alone", () => {
    assert.equal(
      endReasonAt(
        { ...taipei, status: "ended", expectedReturnAt: new Date("2020-01-01T00:00:00.000Z") },
        new Date("2026-10-26T16:00:00.000Z"),
      ),
      null,
    );
  });

  it("rejects dates and time zones that cannot be interpreted", () => {
    assert.throws(
      () => endReasonAt({ ...taipei, endDate: "2026-02-31" }, new Date("2026-03-01T00:00:00.000Z")),
      InvalidTripEndData,
    );
    assert.throws(
      () => endReasonAt({ ...taipei, timeZone: "Not/AZone" }, new Date("2026-10-26T16:00:00.000Z")),
      InvalidTripEndData,
    );
  });
});

describe("tripEndInputFromData", () => {
  it("reads a Firestore-style timestamp and treats null as unset", () => {
    const instant = new Date("2026-10-27T00:00:00.000Z");
    const parsed = tripEndInputFromData({
      status: "active",
      endDate: "2026-10-26",
      timeZone: "Asia/Taipei",
      expectedReturnAt: { toDate: () => instant },
    });
    assert.equal(parsed.expectedReturnAt?.toISOString(), instant.toISOString());
    assert.equal(
      tripEndInputFromData({ ...parsed, expectedReturnAt: null }).expectedReturnAt,
      null,
    );
  });

  it("refuses a non-timestamp expectedReturnAt", () => {
    assert.throws(
      () =>
        tripEndInputFromData({
          status: "active",
          endDate: "2026-10-26",
          timeZone: "Asia/Taipei",
          expectedReturnAt: "tomorrow",
        }),
      InvalidTripEndData,
    );
  });
});

describe("shouldClearLocations", () => {
  it("is true only on the transition into ended", () => {
    assert.equal(shouldClearLocations("active", "ended"), true);
    assert.equal(shouldClearLocations("planning", "ended"), true);
    assert.equal(shouldClearLocations("ended", "ended"), false);
    assert.equal(shouldClearLocations("planning", "active"), false);
  });
});
