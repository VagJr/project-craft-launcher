const path = require('node:path');
const {download} = require('./network.cjs');
const {hashFile} = require('./safe-files.cjs');

function versionParts(value) {
  if (typeof value !== 'string' || !/^\d+\.\d+\.\d+$/.test(value)) return null;
  return value.split('.').map(Number);
}

function newer(candidate, current) {
  const a = versionParts(candidate), b = versionParts(current);
  if (!a || !b) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return a[i] > b[i];
  }
  return false;
}

function approvedUpdate(manifest, current, format = 'msi') {
  const update = manifest.launcher;
  if (update?.enabled !== true || !newer(update.version, current)) return null;
  const expected = `https://github.com/VagJr/project-craft-launcher/releases/download/v${update.version}/ProjectCraft-Setup-${update.version}-x64.msi`;
  if (update.format !== 'msi' || update.url !== expected ||
      !/^[a-f0-9]{64}$/.test(update.sha256) ||
      !Number.isSafeInteger(update.size) || update.size <= 0 || update.size > 512 * 1024 ** 2) {
    throw new Error('A atualização do launcher não tem os dados de verificação necessários.');
  }
  if (format === 'zip') {
    const zip = update.zip;
    const expectedZip = `https://github.com/VagJr/project-craft-launcher/releases/download/v${update.version}/ProjectCraft-${update.version}-x64.zip`;
    if (zip?.url !== expectedZip || !/^[a-f0-9]{64}$/.test(zip.sha256) ||
        !Number.isSafeInteger(zip.size) || zip.size <= 0 || zip.size > 512 * 1024 ** 2) {
      throw new Error('A atualização portátil não tem os dados de verificação necessários.');
    }
    return {...update, ...zip, format: 'zip'};
  }
  if (format !== 'msi') throw new Error('Formato de atualização inválido.');
  return update;
}

async function downloadUpdate(manifest, current, dataDir, {format = 'msi', progress} = {}) {
  const update = approvedUpdate(manifest, current, format);
  if (!update) return null;
  const file = path.join(dataDir, 'updates', `${update.sha256}.${format}`);
  await download(update.url, file, {hash: update.sha256, size: update.size, maxSize: 512 * 1024 ** 2, progress});
  return {...update, file};
}

async function verifyUpdate(update) {
  if (!update || await hashFile(update.file) !== update.sha256) {
    throw new Error('O instalador da atualização foi alterado. Baixe novamente pelo site oficial.');
  }
}

module.exports = {newer, approvedUpdate, downloadUpdate, verifyUpdate};
