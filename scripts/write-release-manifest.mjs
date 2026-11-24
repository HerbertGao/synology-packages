#!/usr/bin/env node
/**
 * Write .release/<tag>.json for a pending SPK release.
 */
import fs from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
let preserveFrom = null;
let ciHead = null;
const positional = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--preserve-from') {
    preserveFrom = argv[++i];
  } else if (argv[i] === '--ci-head') {
    ciHead = argv[++i];
  } else {
    positional.push(argv[i]);
  }
}

const [pkg, version, tag, ciSha, outRoot = '.'] = positional;
if (!pkg || !version || !tag || !ciSha) {
  console.error(
    'usage: write-release-manifest.mjs <pkg> <version> <tag> <ci_sha> [out-root] [--preserve-from path]',
  );
  process.exit(2);
}

if (pkg !== 'openlist' && pkg !== 'easytier') {
  console.error('pkg must be openlist or easytier');
  process.exit(2);
}

const catalog = pkg === 'openlist' ? 'openlist' : 'EasyTier';
const primary =
  pkg === 'openlist'
    ? `openlist_apollolake-7.3_${version}.spk`
    : `EasyTier_apollolake-7.3_${version}.spk`;
const extra =
  pkg === 'easytier' ? [`EasyTier_kvmx64-7.3_${version}.spk`] : [];

const doc = {
  package: pkg,
  catalog_package: catalog,
  version,
  tag,
  ci_sha: ciSha,
  artifact_sha: ciSha,
  ...(ciHead ? { ci_head: ciHead } : {}),
  prerelease: true,
  make_latest: false,
  ci_workflow: 'synology-packages-ci',
  primary_spk: primary,
  extra_assets: extra,
};

if (preserveFrom) {
  const prev = JSON.parse(fs.readFileSync(preserveFrom, 'utf8'));
  if (typeof prev.prerelease === 'boolean') doc.prerelease = prev.prerelease;
  if (typeof prev.make_latest === 'boolean') doc.make_latest = prev.make_latest;
}

const releaseDir = path.join(outRoot, '.release');
fs.mkdirSync(releaseDir, { recursive: true });
const outPath = path.join(releaseDir, `${tag}.json`);
fs.writeFileSync(outPath, `${JSON.stringify(doc, null, 2)}\n`);
console.log(outPath);