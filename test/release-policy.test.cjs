const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const {assertPublicReady} = require('../scripts/release-policy.cjs');

test('publicação recusa assinatura ausente, detecção e artefato alterado após a análise', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'craft-security-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const dir = path.join(root, 'build', '1.1.0');
  const reportDir = path.join(root, '.local', 'security');
  await fs.mkdir(dir, {recursive: true});
  await fs.mkdir(reportDir, {recursive: true});
  const file = 'setup.msi';
  await fs.writeFile(path.join(dir, file), 'candidate');
  await fs.writeFile(path.join(root, 'source.cjs'), 'source');
  await fs.writeFile(path.join(dir, 'BUILD-PROVENANCE.json'), JSON.stringify({version:'1.1.0',source:[{file:'source.cjs',sha256:crypto.createHash('sha256').update('source').digest('hex')}]}));
  const report = {version: '1.1.0', publicReady: false, localScanPassed: true,
    signatures: [{status: 'NotSigned'}], files: [],
    scans: [{file, clean: true, sha256: crypto.createHash('sha256').update('candidate').digest('hex')}]};
  async function save() { await fs.writeFile(path.join(reportDir, 'release-1.1.0.json'), JSON.stringify(report)); }
  await save();
  await assert.rejects(assertPublicReady(root, '1.1.0'), /publicador/);
  await assertPublicReady(root, '1.1.0', {allowUnsigned: true});
  report.publicReady = true;
  report.signatures[0].status = 'Valid';
  report.localScanPassed = false;
  await save();
  await assert.rejects(assertPublicReady(root, '1.1.0'));
  await assert.rejects(assertPublicReady(root, '1.1.0', {allowUnsigned: true}));
  report.localScanPassed = true;
  await save();
  await assertPublicReady(root, '1.1.0');
  await fs.writeFile(path.join(root, 'source.cjs'), 'changed');
  await assert.rejects(assertPublicReady(root, '1.1.0'), /fonte mudou/);
  await fs.writeFile(path.join(root, 'source.cjs'), 'source');
  await fs.writeFile(path.join(dir, file), 'tampered');
  await assert.rejects(assertPublicReady(root, '1.1.0'), /verificação/);
});
