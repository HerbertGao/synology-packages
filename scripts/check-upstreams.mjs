#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const defaultManifestPath = resolve(root, "packages/openlist/upstreams.json");

export const issueTitle = "chore: upstream updates available";

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new Error(`Could not parse ${path}: ${error.message}`, {
      cause: error,
    });
  }
}

export function githubSlug(repository) {
  let url;
  try {
    url = new URL(repository);
  } catch (error) {
    throw new Error(`Invalid GitHub repository URL: ${repository}`, {
      cause: error,
    });
  }
  if (url.hostname !== "github.com") {
    throw new Error(`Not a GitHub URL: ${repository}`);
  }
  const parts = url.pathname
    .replace(/\.git$/, "")
    .split("/")
    .filter(Boolean);
  if (parts.length !== 2) {
    throw new Error(`Invalid GitHub repository: ${repository}`);
  }
  return `${parts[0]}/${parts[1]}`;
}

/** @param {string} version */
export function parseSemver(version) {
  const match =
    /^v?(\d+)\.(\d+)\.(\d+)(?:[.+-].*)?$/i.exec(version.trim());
  if (!match) return undefined;
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

/**
 * @param {string} a
 * @param {string} b
 * @returns {-1 | 0 | 1 | undefined}
 */
export function compareSemver(a, b) {
  const pa = parseSemver(a);
  const pb = parseSemver(b);
  if (!pa || !pb) return undefined;
  for (let i = 0; i < 3; i += 1) {
    if (pa[i] < pb[i]) return -1;
    if (pa[i] > pb[i]) return 1;
  }
  return 0;
}

/** @param {string} url */
export function versionFromArtifactUrl(url) {
  const patterns = [
    /\/tags\/v?(\d+\.\d+\.\d+)/i,
    /\/releases\/download\/v?(\d+\.\d+\.\d+)/i,
    /OpenList-(\d+\.\d+\.\d+)\./i,
    /openlist-frontend-dist-v(\d+\.\d+\.\d+)/i,
  ];
  for (const pattern of patterns) {
    const match = pattern.exec(url);
    if (match) return match[1];
  }
  return undefined;
}

/**
 * @param {Record<string, unknown>} lock
 * @param {{ watches: unknown[] }} manifest
 */
export function parseLock(lock, manifest) {
  const watches = manifest.watches ?? [];
  const entries = [];

  for (const watch of watches) {
    if (typeof watch !== "object" || watch === null) continue;
    const w = /** @type {Record<string, string>} */ (watch);
    const base = {
      id: w.id,
      name: w.name,
      repository: w.repository,
      watch: w.watch,
    };

    if (w.watch === "github_release") {
      const localVersion =
        w.lockVersionField && lock[w.lockVersionField] !== undefined
          ? String(lock[w.lockVersionField])
          : undefined;
      const artifact =
        w.artifactKey && lock.artifacts?.[w.artifactKey] !== undefined
          ? lock.artifacts[w.artifactKey]
          : undefined;
      const artifactVersion =
        artifact && typeof artifact.url === "string"
          ? versionFromArtifactUrl(artifact.url)
          : undefined;
      entries.push({
        ...base,
        localVersion: localVersion ?? artifactVersion,
        artifactVersion,
        artifactUrl: artifact?.url,
      });
    } else if (w.watch === "spksrc_baseline") {
      const spksrc = lock[w.lockSpksrcField ?? "spksrc"];
      entries.push({
        ...base,
        pinnedCommit:
          spksrc && typeof spksrc.commit === "string" ? spksrc.commit : undefined,
        spksrcNote:
          spksrc && typeof spksrc.note === "string" ? spksrc.note : undefined,
        makefilePath: w.makefilePath ?? "cross/openlist/Makefile",
      });
    }
  }

  return {
    openlistVersion: String(lock.openlist_version ?? ""),
    entries,
  };
}

/**
 * @param {Record<string, unknown>} lock
 * @param {{ watches: unknown[], lock?: string }} manifest
 */
export function validate(lock, manifest) {
  const errors = [];
  const parsed = parseLock(lock, manifest);

  if (!lock.openlist_version) {
    errors.push("upstream.lock.json must set openlist_version");
  }
  if (!lock.spksrc?.commit) {
    errors.push("upstream.lock.json must set spksrc.commit");
  }
  if (!/^[0-9a-f]{40}$/.test(String(lock.spksrc?.commit ?? ""))) {
    errors.push("spksrc.commit must be a full 40-character SHA");
  }
  for (const key of ["openlist_source", "openlist_frontend"]) {
    if (!lock.artifacts?.[key]?.url) {
      errors.push(`artifacts.${key}.url is required`);
    }
  }

  for (const watch of manifest.watches ?? []) {
    const w = /** @type {Record<string, string>} */ (watch);
    try {
      githubSlug(w.repository);
    } catch (error) {
      errors.push(error instanceof Error ? error.message : String(error));
    }
    if (w.watch === "github_release") {
      const entry = parsed.entries.find((item) => item.id === w.id);
      if (!entry?.localVersion) {
        errors.push(`${w.name} has no local version in the lock file`);
      }
      const fromUrl = entry?.artifactVersion;
      if (
        fromUrl &&
        entry?.localVersion &&
        compareSemver(fromUrl, entry.localVersion) !== 0
      ) {
        errors.push(
          `${w.name} artifact URL version \`${fromUrl}\` does not match lock \`${entry.localVersion}\``,
        );
      }
    }
  }

  return { errors, parsed };
}

export function normalizedTrackingReport(report) {
  return report.replace(/^Generated: .*$/m, "").trimEnd();
}

export function trackingReportFingerprint(report) {
  return createHash("sha256")
    .update(normalizedTrackingReport(report))
    .digest("hex");
}

/**
 * @param {string[]} releaseUpdates
 * @param {string[]} errors
 */
export function issueSyncAction(releaseUpdates, errors) {
  if (releaseUpdates.length > 0) return "open";
  if (errors.length > 0) return "unchanged";
  return "close";
}

export function findOpenTrackingIssue(issues) {
  return issues.find(
    (candidate) =>
      !candidate.pull_request &&
      candidate.title === issueTitle &&
      candidate.state === "open",
  );
}

export function markdownReport({
  parsed,
  releaseUpdates,
  spksrcUpdates,
  upstreamRows,
  errors,
  generatedAt = new Date().toISOString(),
}) {
  const lines = [
    "<!-- upstream-monitor -->",
    "# OpenList upstream monitor",
    "",
    `Generated: ${generatedAt}`,
    "",
    "Digest verification and SPK bumps are **not** automated here. After maintainer review, run `./scripts/verify-upstream-digests.sh` in a draft PR and publish only with explicit authorization.",
    "",
    "## Local vs upstream",
    "",
    "| Component | Local pin | Upstream (live) |",
    "| --- | --- | --- |",
  ];

  for (const row of upstreamRows) {
    lines.push(
      `| ${row.name} | \`${row.local}\` | \`${row.upstream}\` |`,
    );
  }

  const spksrc = upstreamRows.find((row) => row.id === "spksrc");
  if (spksrc) {
    lines.push(
      "",
      "### spksrc baseline (informational)",
      "",
      spksrc.spksrcNote ? `- Lock note: ${spksrc.spksrcNote}` : "",
      `- Pinned commit: \`${spksrc.pinnedCommit ?? "?"}\``,
      `- Default-branch tip: \`${spksrc.upstreamCommit ?? "?"}\``,
      spksrc.upstreamRecipeVersion
        ? `- \`cross/openlist/Makefile\` \`PKG_VERS\` on tip: \`${spksrc.upstreamRecipeVersion}\``
        : "",
      "- A newer spksrc commit does **not** by itself require bumping OpenList in this overlay.",
    );
  }

  lines.push("", "## Release updates", "");
  if (releaseUpdates.length === 0) {
    lines.push("No newer OpenList or Frontend releases detected.");
  } else {
    for (const update of releaseUpdates) lines.push(`- ${update}`);
  }

  lines.push("", "## spksrc drift", "");
  if (spksrcUpdates.length === 0) {
    lines.push("Pinned spksrc commit still matches default-branch tip.");
  } else {
    for (const update of spksrcUpdates) lines.push(`- ${update}`);
  }

  if (errors.length > 0) {
    lines.push("", "## Monitor errors", "");
    for (const error of errors) lines.push(`- ${error}`);
  }

  return `${lines.filter((line) => line !== undefined).join("\n")}\n`;
}

export function releaseLagMessage(name, localVersion, upstreamVersion) {
  return `\`${name}\`: GitHub latest is \`${upstreamVersion}\` (pinned \`${localVersion}\`).`;
}

export function spksrcDriftMessage(pinnedCommit, tipCommit, recipeVersion) {
  const short = (sha) => sha.slice(0, 12);
  const parts = [
    `[spksrc](https://github.com/SynoCommunity/spksrc/compare/${pinnedCommit}...${tipCommit}) default branch moved (pinned \`${short(pinnedCommit)}\`, tip \`${short(tipCommit)}\`).`,
  ];
  if (recipeVersion) {
    parts.push(`Upstream \`cross/openlist/Makefile\` on tip sets \`PKG_VERS = ${recipeVersion}\`.`);
  }
  return parts.join(" ");
}

function githubHeaders() {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "synology-packages-openlist-upstream-monitor",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }
  return headers;
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, options);
  if (!response.ok) {
    const body = await response.text();
    throw new Error(
      `${response.status} ${response.statusText}: ${body.slice(0, 200)}`,
    );
  }
  return response.json();
}

async function githubRequest(path, init = {}) {
  return fetchJson(`https://api.github.com${path}`, {
    ...init,
    headers: {
      ...githubHeaders(),
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers,
    },
  });
}

export async function latestGitHubReleaseVersion(slug) {
  try {
    const release = await fetchJson(
      `https://api.github.com/repos/${slug}/releases/latest`,
      { headers: githubHeaders() },
    );
    const tag = release?.tag_name;
    if (typeof tag !== "string") {
      throw new Error("release has no tag_name");
    }
    return tag.replace(/^v/i, "");
  } catch (error) {
    if (!(error instanceof Error) || !error.message.startsWith("404")) {
      throw error;
    }
  }
  const tags = await fetchJson(
    `https://api.github.com/repos/${slug}/tags?per_page=1`,
    { headers: githubHeaders() },
  );
  const name = tags?.[0]?.name;
  if (typeof name !== "string") {
    throw new Error(`No releases or tags for ${slug}`);
  }
  return name.replace(/^v/i, "");
}

export async function latestDefaultBranchCommit(slug) {
  const ref = await fetchJson(
    `https://api.github.com/repos/${slug}/commits?per_page=1`,
    { headers: githubHeaders() },
  );
  const sha = ref?.[0]?.sha;
  if (typeof sha !== "string") {
    throw new Error(`No default-branch commit for ${slug}`);
  }
  return sha;
}

export function parseSpksrcPkgVers(makefileText) {
  const match = /^PKG_VERS\s*=\s*(\d+\.\d+\.\d+)/m.exec(makefileText);
  return match ? match[1] : undefined;
}

export async function fetchSpksrcMakefile(slug, path, ref) {
  const encoded = path
    .split("/")
    .map((part) => encodeURIComponent(part))
    .join("/");
  const file = await fetchJson(
    `https://api.github.com/repos/${slug}/contents/${encoded}?ref=${encodeURIComponent(ref)}`,
    { headers: githubHeaders() },
  );
  if (typeof file.content !== "string" || file.encoding !== "base64") {
    throw new Error(`Unexpected contents payload for ${path}`);
  }
  return Buffer.from(file.content, "base64").toString("utf8");
}

async function findOpenTrackingIssueInRepository(repository, request) {
  for (let page = 1; ; page += 1) {
    // Pagination is sequential so the lookup stops as soon as it finds a match.
    // oxlint-disable-next-line no-await-in-loop
    const issues = await request(
      `/repos/${repository}/issues?state=open&per_page=100&page=${page}`,
    );
    const issue = findOpenTrackingIssue(issues);
    if (issue || issues.length < 100) return issue;
  }
}

export async function syncTrackingIssue(
  repository,
  report,
  action,
  request = githubRequest,
) {
  const issue = await findOpenTrackingIssueInRepository(repository, request);

  if (action === "open") {
    const body = JSON.stringify({ title: issueTitle, body: report });
    if (issue) {
      if (
        typeof issue.body === "string" &&
        normalizedTrackingReport(issue.body) ===
          normalizedTrackingReport(report)
      ) {
        return;
      }
      const updated = await request(
        `/repos/${repository}/issues/${issue.number}`,
        { method: "PATCH", body },
      );
      if (updated.state === "open") return updated.number;
    }
    const created = await request(`/repos/${repository}/issues`, {
      method: "POST",
      body,
    });
    return created.number;
  }
  if (action === "close" && issue) {
    await request(`/repos/${repository}/issues/${issue.number}`, {
      method: "PATCH",
      body: JSON.stringify({
        body: report,
        state: "closed",
        state_reason: "completed",
      }),
    });
  }
}

async function syncIssue(report, action) {
  const repository = process.env.GITHUB_REPOSITORY;
  if (!process.env.GITHUB_TOKEN || !repository) {
    throw new Error("--sync-issue requires GITHUB_TOKEN and GITHUB_REPOSITORY");
  }
  return syncTrackingIssue(repository, report, action);
}

async function main() {
  const validateOnly = process.argv.includes("--validate");
  const shouldSyncIssue = process.argv.includes("--sync-issue");
  const manifestPath = process.env.UPSTREAMS_MANIFEST ?? defaultManifestPath;
  const manifest = readJson(manifestPath);
  const lockPath = resolve(root, manifest.lock ?? "packages/openlist/upstream.lock.json");
  const lock = readJson(lockPath);
  const { errors, parsed } = validate(lock, manifest);

  if (validateOnly) {
    if (errors.length > 0) throw new Error(errors.join("\n"));
    process.stdout.write(
      `Validated OpenList lock (${parsed.openlistVersion}) and ${parsed.entries.length} watch entries.\n`,
    );
    return;
  }

  const releaseUpdates = [];
  const spksrcUpdates = [];
  const upstreamRows = [];
  const monitorErrors = [...errors];

  await Promise.all(
    parsed.entries.map(async (entry) => {
      const slug = githubSlug(entry.repository);
      if (entry.watch === "github_release") {
        const localVersion = entry.localVersion ?? "?";
        try {
          const upstreamVersion = await latestGitHubReleaseVersion(slug);
          upstreamRows.push({
            id: entry.id,
            name: entry.name,
            local: localVersion,
            upstream: upstreamVersion,
          });
          const cmp = compareSemver(localVersion, upstreamVersion);
          if (cmp === undefined) {
            monitorErrors.push(
              `${entry.name}: cannot compare \`${localVersion}\` vs \`${upstreamVersion}\``,
            );
          } else if (cmp < 0) {
            releaseUpdates.push(
              releaseLagMessage(entry.name, localVersion, upstreamVersion),
            );
          }
        } catch (error) {
          monitorErrors.push(
            `${entry.name}: ${error instanceof Error ? error.message : String(error)}`,
          );
          upstreamRows.push({
            id: entry.id,
            name: entry.name,
            local: localVersion,
            upstream: "unknown",
          });
        }
        return;
      }

      if (entry.watch === "spksrc_baseline") {
        const pinned = entry.pinnedCommit ?? "";
        try {
          const tip = await latestDefaultBranchCommit(slug);
          let recipeVersion;
          try {
            const makefile = await fetchSpksrcMakefile(
              slug,
              entry.makefilePath,
              tip,
            );
            recipeVersion = parseSpksrcPkgVers(makefile);
          } catch (error) {
            monitorErrors.push(
              `spksrc Makefile: ${error instanceof Error ? error.message : String(error)}`,
            );
          }
          upstreamRows.push({
            id: entry.id,
            name: entry.name,
            local: pinned.slice(0, 12),
            upstream: tip.slice(0, 12),
            pinnedCommit: pinned,
            upstreamCommit: tip,
            spksrcNote: entry.spksrcNote,
            upstreamRecipeVersion: recipeVersion,
          });
          if (tip !== pinned) {
            spksrcUpdates.push(
              spksrcDriftMessage(pinned, tip, recipeVersion),
            );
          }
        } catch (error) {
          monitorErrors.push(
            `spksrc: ${error instanceof Error ? error.message : String(error)}`,
          );
        }
      }
    }),
  );

  releaseUpdates.sort((a, b) => a.localeCompare(b));
  spksrcUpdates.sort((a, b) => a.localeCompare(b));
  monitorErrors.sort((a, b) => a.localeCompare(b));

  const report = markdownReport({
    parsed,
    releaseUpdates,
    spksrcUpdates,
    upstreamRows,
    errors: monitorErrors,
  });
  process.stdout.write(report);

  if (shouldSyncIssue) {
    await syncIssue(
      report,
      issueSyncAction(releaseUpdates, monitorErrors),
    );
  }
  if (monitorErrors.length > 0) process.exitCode = 1;
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}