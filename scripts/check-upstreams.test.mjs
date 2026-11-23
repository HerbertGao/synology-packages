import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

import {
  compareSemver,
  findOpenTrackingIssue,
  issueSyncAction,
  markdownReport,
  monitorProcessExitCode,
  parseLock,
  parseSpksrcPkgVers,
  releaseLagMessage,
  shouldSyncTrackingIssue,
  sortUpstreamRows,
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

test("monitorProcessExitCode does not fail after default-branch sync", () => {
  assert.equal(monitorProcessExitCode(true, ["spksrc: 403"]), 0);
  assert.equal(monitorProcessExitCode(false, ["spksrc: 403"]), 1);
  assert.equal(monitorProcessExitCode(false, []), 0);
});

test("release lag still opens the issue when other fetches errored", () => {
  const releaseUpdates = [
    "`OpenList`: GitHub latest is `4.2.11` (pinned `4.2.10`).",
  ];
  const monitorErrors = ["spksrc: 403 Forbidden"];
  assert.equal(issueSyncAction(releaseUpdates, monitorErrors), "open");
  assert.equal(monitorProcessExitCode(true, monitorErrors), 0);
});

test("shouldSyncTrackingIssue only on the default branch", () => {
  assert.equal(
    shouldSyncTrackingIssue(
      true,
      "refs/heads/master",
      "master",
    ),
    true,
  );
  assert.equal(
    shouldSyncTrackingIssue(
      true,
      "refs/heads/cursor/feature",
      "master",
    ),
    false,
  );
  assert.equal(shouldSyncTrackingIssue(false, "refs/heads/master", "master"), false);
  assert.equal(shouldSyncTrackingIssue(true, "refs/heads/master", undefined), false);
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

test("sortUpstreamRows follows manifest watch order", () => {
  const rows = [
    { id: "spksrc", name: "SynoCommunity spksrc", local: "abc", upstream: "def" },
    { id: "openlist_frontend", name: "OpenList Frontend", local: "1", upstream: "1" },
    { id: "openlist", name: "OpenList", local: "1", upstream: "2" },
  ];
  const ordered = sortUpstreamRows(rows, manifest.watches);
  assert.deepEqual(
    ordered.map((row) => row.id),
    ["openlist", "openlist_frontend", "spksrc"],
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

test("report body is stable when upstreamRows arrive out of order", () => {
  const { parsed } = validate(lock, manifest);
  const args = {
    parsed,
    releaseUpdates: [],
    spksrcUpdates: [],
    errors: [],
    generatedAt: "2026-01-01T00:00:00.000Z",
  };
  const rowsA = [
    { id: "openlist", name: "OpenList", local: "4.2.10", upstream: "4.2.10" },
    {
      id: "openlist_frontend",
      name: "OpenList Frontend",
      local: "4.2.10",
      upstream: "4.2.10",
    },
    {
      id: "spksrc",
      name: "SynoCommunity spksrc",
      local: "f29cd8b7e080",
      upstream: "deadbeef0000",
      pinnedCommit: lock.spksrc.commit,
      upstreamCommit: "deadbeef0000000000000000000000000000000000",
    },
  ];
  const rowsB = [...rowsA].toReversed();
  const reportA = markdownReport({
    ...args,
    upstreamRows: sortUpstreamRows(rowsA, manifest.watches),
  });
  const reportB = markdownReport({
    ...args,
    upstreamRows: sortUpstreamRows(rowsB, manifest.watches),
  });
  assert.equal(
    trackingReportFingerprint(reportA),
    trackingReportFingerprint(reportB),
  );
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