import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { anniversaryUtc, isAtLeast13, isAtLeastAge, isMinor } from "../src/age";

function utc(year: number, monthIndex: number, day: number, hour = 0, minute = 0, second = 0): Date {
  return new Date(Date.UTC(year, monthIndex, day, hour, minute, second));
}

describe("anniversaryUtc", () => {
  it("moves a Feb 29 birthday to March 1 when the anniversary year is not a leap year", () => {
    const birth = utc(2016, 1, 29);
    assert.equal(anniversaryUtc(birth, 13).toISOString(), "2029-03-01T00:00:00.000Z");
  });

  it("keeps Feb 29 when the anniversary year is a leap year", () => {
    const birth = utc(2012, 1, 29);
    assert.equal(anniversaryUtc(birth, 4).toISOString(), "2016-02-29T00:00:00.000Z");
  });
});

describe("isAtLeastAge", () => {
  const leapBaby = utc(2016, 1, 29);

  it("treats the 13th birthday as the first moment of March 1 after a non-leap anniversary", () => {
    assert.equal(isAtLeastAge(leapBaby, utc(2029, 1, 28, 23, 59, 59), 13), false);
    assert.equal(isAtLeast13(leapBaby, utc(2029, 2, 1)), true);
  });

  it("uses the real Feb 29 when that anniversary exists", () => {
    const birth = utc(2012, 1, 29);
    assert.equal(isAtLeastAge(birth, utc(2016, 1, 28, 23, 59, 59), 4), false);
    assert.equal(isAtLeastAge(birth, utc(2016, 1, 29), 4), true);
  });

  it("rejects a birthdate in the future", () => {
    assert.equal(isAtLeast13(utc(2030, 0, 1), utc(2026, 9, 26)), false);
  });
});

describe("isMinor", () => {
  it("is false from the 18th birthday and true the day before", () => {
    const birth = utc(2008, 9, 26);
    assert.equal(isMinor(birth, utc(2026, 9, 25, 23, 59, 59)), true);
    assert.equal(isMinor(birth, utc(2026, 9, 26)), false);
  });
});
