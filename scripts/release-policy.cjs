const fs = require('node:fs/promises');
const path = require('node:path');
const {hashFile} = require('../src/core/safe-files.cjs');

async function assertPublicReady(root, version, {allowUnsigned = false} = {}) {
  const report = JSON.parse((await fs.readFile(path.join(root, '.local', 'security', `release-${version}.json`), 'utf8')).replace(/^\uFEFF/, ''));
  const allowed = allowUnsigned ? ['Valid', 'NotSigned'] : ['Valid'];
  if (report.version !== version || (!allowUnsigned && !report.publicReady) || !report.localScanPassed ||
      !report.signatures?.length || report.signatures.some(s => !allowed.includes(s.status))) {
    throw new Error('Publicação bloqueada: faltam verificações limpas e assinatura válida de publicador no MSI e no aplicativo.');
  }
  const dir = path.join(root, 'build', version);
  for (const record of report.scans.filter(s => s.sha256)) {
    if (!record.clean || await hashFile(path.join(dir, record.file)) !== record.sha256) {
      throw new Error('O artefato não corresponde à verificação de segurança.');
    }
  }
  for (const record of report.files) {
    if (await hashFile(path.join(dir, 'win-unpacked', record.file)) !== record.sha256) {
      throw new Error('O aplicativo foi alterado após a verificação.');
    }
  }
  return report;
}

module.exports = {assertPublicReady};
