#!/usr/bin/env node
/**
 * Update exactly one entry in docs/packages.json from built SPK files + manifest.
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
const args = parseArgs(process.argv.slice(2));
const manifest = JSON.parse(fs.readFileSync(args.manifest, 'utf8'));
const catalogPath = path.join(process.cwd(), 'docs/packages.json');
const doc = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));

const idx = doc.packages.findIndex((p) => p.package === manifest.catalog_package);
if (idx < 0) {
  console.error(`catalog package not found: ${manifest.catalog_package}`);
  process.exit(1);
}

const spkPath = findSpk(args.spkDir, manifest.primary_spk);
const hashes = fileHashes(spkPath);
const repo = args.repo.replace(/^https:\/\/github.com\//, '');
const link =
  `https://github.com/${repo}/releases/download/${manifest.tag}/${path.basename(spkPath)}`;

const next = { ...doc.packages[idx] };
next.version = manifest.version;
next.link = link;
next.md5 = hashes.md5;
next.sha256 = hashes.sha256;
next.size = hashes.size;

doc.packages[idx] = next;
fs.writeFileSync(catalogPath, `${JSON.stringify(doc, null, 2)}\n`);

function findSpk(dir, basename) {
  const direct = path.join(dir, basename);
  if (fs.existsSync(direct)) return direct;
  const hits = [];
  walk(dir, (p) => {
    if (path.basename(p) === basename) hits.push(p);
  });
  if (hits.length !== 1) {
    console.error(`expected one ${basename}, found ${hits.length}`);
    process.exit(1);
  }
  return hits[0];
}

function walk(root, cb) {
  for (const ent of fs.readdirSync(root, { withFileTypes: true })) {
    const p = path.join(root, ent.name);
    if (ent.isDirectory()) walk(p, cb);
    else cb(p);
  }
}

function fileHashes(file) {
  const buf = fs.readFileSync(file);
  return {
    md5: crypto.createHash('md5').update(buf).digest('hex'),
    sha256: crypto.createHash('sha256').update(buf).digest('hex'),
    size: buf.length,
  };
}

function parseArgs(argv) {
  const out = { spkDir: '.', repo: 'HerbertGao/synology-packages' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--manifest') out.manifest = argv[++i];
    else if (argv[i] === '--spk-dir') out.spkDir = argv[++i];
    else if (argv[i] === '--repo') out.repo = argv[++i];
  }
  if (!out.manifest) {
    console.error('usage: --manifest path --spk-dir dir [--repo owner/name]');
    process.exit(2);
  }
  return out;
}