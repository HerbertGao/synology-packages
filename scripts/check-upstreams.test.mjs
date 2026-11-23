import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

import {
  compareSemver,
  findOpenTrackingIssue,
  issueSyncAction,
  markdownReport,
  parseLock,
  parseSpksrcPkgVers,
  releaseLagMessage,
  spksrcDriftMessage,
  syncTrackingIssue,
  trackingReportFingerprint,
  validate,
  versionFromArtifactUrl,
} from "./check-upstreams.mjs";

const root = resolve(import.meta.dirname, "..");
const manifest = JSON.parse(
  readFileSync(resolve(root, "packages/openlist/upstreams.json"), "utf8"),
);
const lock = JSON.parse(
  readFileSync(resolve(root, "packages/openlist/upstream.lock.json"), "utf8"),
);

test("parses versions from lock artifact URLs", () => {
  assert.equal(
    versionFromArtifactUrl(lock.artifacts.openlist_source.url),
    "4.2.10",
  );
  assert.equal(
    versionFromArtifactUrl(lock.artifacts.openlist_frontend.url),
    "4.2.10",
  );
});

test("compareSemver orders release tags", () => {
  assert.equal(compareSemver("4.2.9", "4.2.10"), -1);
  assert.equal(compareSemver("4.2.10", "4.2.10"), 0);
  assert.equal(compareSemver("4.3.0", "4.2.10"), 1);
});

test("--validate passes for the current lock and manifest", () => {
  const { errors } = validate(lock, manifest);
  assert.deepEqual(errors, []);
});

test("issueSyncAction mirrors pi-extensions boundaries", () => {
  assert.equal(issueSyncAction(["release"], []), "open");
  assert.equal(issueSyncAction([], []), "close");
  assert.equal(issueSyncAction([], ["fetch failed"]), "unchanged");
  assert.equal(issueSyncAction(["release"], ["fetch failed"]), "open");
});

test("formats release and spksrc lag copy", () => {
  assert.equal(
    releaseLagMessage("OpenList", "4.2.10", "4.2.11"),
    "`OpenList`: GitHub latest is `4.2.11` (pinned `4.2.10`).",
  );
  assert.match(
    spksrcDriftMessage("a".repeat(40), "b".repeat(40), "4.2.7"),
    /PKG_VERS = 4\.2\.7/,
  );
});

test("markdownReport shows local vs upstream table", () => {
  const { parsed } = validate(lock, manifest);
  const body = markdownReport({
    parsed,
    releaseUpdates: [
      "`OpenList`: GitHub latest is `4.2.11` (pinned `4.2.10`).",
    ],
    spksrcUpdates: [],
    upstreamRows: [
      {
        id: "openlist",
        name: "OpenList",
        local: "4.2.10",
        upstream: "4.2.11",
      },
    ],
    errors: [],
    generatedAt: "2026-01-01T00:00:00.000Z",
  });
  assert.match(body, /<!-- upstream-monitor -->/);
  assert.match(body, /\| OpenList \| `4\.2\.10` \| `4\.2\.11` \|/);
  assert.match(body, /Generated: 2026-01-01T00:00:00.000Z/);
  assert.doesNotMatch(body, /Generated: 2026-02-01/);
});

test("parseLock derives watch entries from the manifest", () => {
  const parsed = parseLock(lock, manifest);
  assert.equal(parsed.openlistVersion, "4.2.10");
  assert.equal(parsed.entries.length, manifest.watches.length);
  const openlist = parsed.entries.find((entry) => entry.id === "openlist");
  assert.equal(openlist?.localVersion, "4.2.10");
  const spksrc = parsed.entries.find((entry) => entry.id === "spksrc");
  assert.equal(spksrc?.pinnedCommit, lock.spksrc.commit);
});

test("parseSpksrcPkgVers reads PKG_VERS", () => {
  const text = "PKG_NAME = OpenList\nPKG_VERS = 4.2.7\n";
  assert.equal(parseSpksrcPkgVers(text), "4.2.7");
});

test("tracking fingerprint ignores Generated timestamp", () => {
  const a = "Generated: 2026-01-01T00:00:00.000Z\n\nsame";
  const b = "Generated: 2026-02-01T00:00:00.000Z\n\nsame";
  assert.equal(trackingReportFingerprint(a), trackingReportFingerprint(b));
});

test("findOpenTrackingIssue ignores PRs and other titles", () => {
  const open = {
    number: 2,
    title: "chore: upstream updates available",
    state: "open",
  };
  assert.equal(findOpenTrackingIssue([open]), open);
  assert.equal(
    findOpenTrackingIssue([{ ...open, pull_request: {} }]),
    undefined,
  );
});

test("syncTrackingIssue skips PATCH when report unchanged", async () => {
  const report = "Generated: 2026-01-01T00:00:00.000Z\n\nreport";
  const open = {
    number: 5,
    title: "chore: upstream updates available",
    state: "open",
    body: "Generated: 2025-12-01T00:00:00.000Z\n\nreport",
  };
  const calls = [];
  const request = async (path, init = {}) => {
    calls.push({ path, init });
    if (path.includes("?state=open")) return [open];
    throw new Error(`Unexpected request: ${path}`);
  };
  const result = await syncTrackingIssue(
    "owner/repo",
    report,
    "open",
    request,
  );
  assert.equal(result, undefined);
  assert.equal(calls.length, 1);
});

test("syncTrackingIssue closes an open tracking issue", async () => {
  const open = {
    number: 9,
    title: "chore: upstream updates available",
    state: "open",
  };
  const calls = [];
  const request = async (path, init = {}) => {
    calls.push({ path, init });
    if (path.includes("?state=open")) return [open];
    if (init.method === "PATCH") return { ...open, state: "closed" };
    throw new Error(`Unexpected request: ${path}`);
  };
  await syncTrackingIssue("owner/repo", "report", "close", request);
  assert.deepEqual(JSON.parse(calls[1].init.body), {
    body: "report",
    state: "closed",
    state_reason: "completed",
  });
});