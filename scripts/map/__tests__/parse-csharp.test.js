'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

// Validate the committed bundle, not the source - this is the artifact the user ships.
const runner = require('../runner.js');
const MAP_RUN = path.join(__dirname, '..', 'map-run.sh');
const CSHARP_FIXTURE = path.join(__dirname, '..', '__fixtures__', 'Sample.cs');

test('loads the bundled web-tree-sitter + C# grammar and parses clean', async () => {
  const { tree } = await runner.parseFile(CSHARP_FIXTURE, 'c_sharp');
  assert.strictEqual(tree.rootNode.type, 'compilation_unit');
  assert.strictEqual(tree.rootNode.hasError, false, 'C# fixture should parse with no errors');
  assert.ok(tree.rootNode.namedChildCount > 0, 'parse tree should have named children');
});

test('file -> language detection resolves the six curated extensions', () => {
  assert.strictEqual(runner.detectLanguage('a.cs'), 'c_sharp');
  assert.strictEqual(runner.detectLanguage('a.ts'), 'typescript');
  assert.strictEqual(runner.detectLanguage('a.tsx'), 'tsx');
  assert.strictEqual(runner.detectLanguage('a.java'), 'java');
  assert.strictEqual(runner.detectLanguage('a.py'), 'python');
  assert.strictEqual(runner.detectLanguage('a.js'), 'javascript');
  // an unmapped extension degrades to the floor, no content sniffing
  assert.strictEqual(runner.detectLanguage('a.rs'), 'floor');
});

test('enumerate honors .gitignore with no .git, skips hidden and binary', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'craftmap-enum-'));
  try {
    fs.writeFileSync(path.join(dir, '.gitignore'), 'ignored.txt\n');
    fs.writeFileSync(path.join(dir, 'kept.cs'), 'class C {}\n');
    fs.writeFileSync(path.join(dir, 'ignored.txt'), 'should be ignored\n');
    fs.writeFileSync(path.join(dir, '.hidden'), 'hidden\n');
    fs.writeFileSync(path.join(dir, 'bin.dat'), Buffer.from([0x00, 0x01, 0x02, 0x00, 0x42]));

    const files = runner.enumerate(dir);
    assert.ok(files.includes('kept.cs'), 'normal tracked-style file is enumerated');
    assert.ok(!files.includes('ignored.txt'), '.gitignore honored without a .git dir');
    assert.ok(!files.includes('.hidden'), 'hidden files skipped');
    assert.ok(!files.includes('bin.dat'), 'binary files filtered out');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('map-run.sh parses C# end-to-end and reports the grammar tier', () => {
  const out = execFileSync('bash', [MAP_RUN, 'parse', CSHARP_FIXTURE], { encoding: 'utf8' });
  const result = JSON.parse(out);
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.tier, 'grammar');
  assert.strictEqual(result.language, 'c_sharp');
  assert.strictEqual(result.hasError, false);
});

test('map-run.sh degrades to the floor signal when node is absent, exit 0', () => {
  // PATH with coreutils but no node -> command -v node fails -> floor, never an error.
  const out = execFileSync('bash', [MAP_RUN, 'parse', CSHARP_FIXTURE], {
    encoding: 'utf8',
    env: { PATH: '/usr/bin:/bin' },
  });
  const result = JSON.parse(out);
  assert.strictEqual(result.tier, 'floor');
  assert.strictEqual(result.reason, 'node-missing');
});
