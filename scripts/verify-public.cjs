const fs = require('node:fs/promises');
const path = require('node:path');
const {ROOT} = require('./common.cjs');
const {text} = require('../src/core/network.cjs');
const {verifySigned} = require('../src/core/safe-files.cjs');

(async () => {
  const base = 'https://raw.githubusercontent.com/VagJr/project-craft-launcher/main/channel';
  const [envelope, key, html] = await Promise.all([
    text(base + '/stable.signed.json').then(JSON.parse),
    fs.readFile(path.join(ROOT, 'release-public-key.pem'), 'utf8'),
    text('https://project-craft-fps.vercel.app')
  ]);
  const release = verifySigned(envelope.payload, envelope.signature, key);
  const urls = [release.pack.url];
  if (release.launcher?.enabled === true) urls.push(release.launcher.url);
  for (const url of urls) {
    const response = await fetch(url, {method: 'HEAD', signal: AbortSignal.timeout(30000)});
    if (!response.ok) throw new Error(`Download indisponível: ${response.status}`);
    console.log(JSON.stringify({file: new URL(url).pathname.split('/').at(-1), status: response.status}));
  }
  if (!html.includes('id="downloads"')) throw new Error('Área de downloads ausente.');
  if (release.launcher?.enabled !== true && !html.includes('DOWNLOAD SUSPENSO')) throw new Error('Aviso de suspensão ausente.');
  console.log(JSON.stringify({publicSite: true, version: release.version, signatureVerified: true, launcherEnabled: release.launcher?.enabled === true}));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
