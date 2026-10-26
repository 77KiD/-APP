/**
 * Age checks shared with firestore.rules and docs/data-model.md 「年齡」.
 * Birthdates are UTC-midnight calendar dates. Feb 29 rolls to March 1
 * when the anniversary year is not a leap year.
 */

export function isLeapYear(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

/** UTC calendar date `years` after `birthdate`. */
export function anniversaryUtc(birthdate: Date, years: number): Date {
  const year = birthdate.getUTCFullYear() + years;
  const month = birthdate.getUTCMonth();
  const day = birthdate.getUTCDate();
  if (month === 1 && day === 29 && !isLeapYear(year)) {
    return new Date(Date.UTC(year, 2, 1));
  }
  return new Date(Date.UTC(year, month, day));
}

export function isAtLeastAge(birthdate: Date, now: Date, years: number): boolean {
  if (Number.isNaN(birthdate.getTime()) || birthdate.getTime() > now.getTime()) {
    return false;
  }
  return now.getTime() >= anniversaryUtc(birthdate, years).getTime();
}

/** 未成年：已能註冊者一律以 18 歲判斷（ADR 0007）。 */
export function isMinor(birthdate: Date, now: Date): boolean {
  return !isAtLeastAge(birthdate, now, 18);
}

export function isAtLeast13(birthdate: Date, now: Date): boolean {
  return isAtLeastAge(birthdate, now, 13);
}
