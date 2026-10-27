/**
 * Client contract for #25. These checks fail on this branch: the Flutter
 * writer still clears backupStops, still writes itineraryHistory, and has
 * no restore hold or older-edit notice yet.
 */
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

function dartSources(dir: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = path.join(dir, entry);
    if (statSync(full).isDirectory()) files.push(...dartSources(full));
    else if (entry.endsWith(".dart")) files.push(full);
  }
  return files;
}

function functionBody(source: string, name: string): string {
  const start = source.indexOf(`Future<void> ${name}`);
  assert.notEqual(start, -1, `${name} missing`);
  const next = source.indexOf("\n  Future<", start + 1);
  return source.slice(start, next === -1 ? source.length : next);
}

describe("T25 frontend product code", () => {
  it("T25-1 does not clear backupStops on an itinerary write", () => {
    const source = readFileSync(
      path.join(root, "app/lib/features/trip/data/firestore_trip_remote.dart"),
      "utf8",
    );
    const body = functionBody(source, "upsertItineraryDay");
    assert.equal(
      body.includes("backupStops: const <Map<String, dynamic>>[]"),
      false,
      "upsertItineraryDay still writes an empty backupStops list",
    );
  });

  it("T25-11 and T25-13 exist in the client", () => {
    const combined = dartSources(path.join(root, "app/lib")).map((file) => readFileSync(file, "utf8")).join("\n");
    assert.equal(combined.includes("你的離線修改比較舊"), true, "client has no older-edit notice");
    assert.equal(/restoreFailed|還原沒有完成/.test(combined), true, "client has no restore-timeout fallback");
  });

  it("T25-2 client sync does not write itineraryHistory", () => {
    const source = readFileSync(
      path.join(root, "app/lib/features/trip/data/firestore_trip_remote.dart"),
      "utf8",
    );
    const body = functionBody(source, "upsertRevision");
    assert.equal(
      body.includes("FirestorePaths.itineraryHistory"),
      false,
      "upsertRevision still writes itineraryHistory, which rules now reject",
    );
  });
});
