const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {newer, approvedUpdate, verifyUpdate} = require('../src/core/launcher-update.cjs');

function manifest() {
  return {launcher: {enabled: true, version: '1.2.0', format: 'msi',
    url: 'https://github.com/VagJr/project-craft-launcher/releases/download/v1.2.0/ProjectCraft-Setup-1.2.0-x64.msi',
    sha256: 'a'.repeat(64), size: 1024}};
}

test('atualização exige versão superior, disponibilidade explícita e MSI oficial com hash', () => {
  assert.equal(newer('1.10.0', '1.9.0'), true);
  assert.equal(newer('1.1.0', '1.1.0'), false);
  assert.equal(newer('1.0.9', '1.1.0'), false);
  const m = manifest();
  assert.equal(approvedUpdate(m, '1.1.0').version, '1.2.0');
  m.launcher.enabled = false;
  assert.equal(approvedUpdate(m, '1.1.0'), null);
  delete m.launcher.enabled;
  assert.equal(approvedUpdate(m, '1.1.0'), null);
  m.launcher.enabled = true;
  m.launcher.url = 'https://example.com/setup.msi';
  assert.throws(() => approvedUpdate(m, '1.1.0'));
  m.launcher.url = manifest().launcher.url;
  delete m.launcher.sha256;
  assert.throws(() => approvedUpdate(m, '1.1.0'));
});

test('instalador é conferido de novo imediatamente antes da abertura', async t => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'craft-update-'));
  t.after(() => fs.rm(dir, {recursive: true, force: true}));
  const file = path.join(dir, 'update.msi');
  await fs.writeFile(file, 'installer');
  const sha256 = crypto.createHash('sha256').update('installer').digest('hex');
  await verifyUpdate({file, sha256});
  await fs.writeFile(file, 'alterado');
  await assert.rejects(verifyUpdate({file, sha256}), /alterado/);
});
