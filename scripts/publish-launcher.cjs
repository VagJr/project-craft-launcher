const fs = require('node:fs/promises');
const path = require('node:path');
const {ROOT, gh, signed, pushFiles} = require('./common.cjs');
const {hashFile} = require('../src/core/safe-files.cjs');
const {assertPublicReady} = require('./release-policy.cjs');

async function publishLauncher({publish = false, allowUnsigned = false} = {}) {
  const version = require('../package.json').version, tag = `v${version}`;
  const dir = path.join(ROOT, 'build', version);
  const security = publish ? await assertPublicReady(ROOT, version, {allowUnsigned}) : null;
  let release;
  try { release = JSON.parse(await gh(['release', 'view', tag, '--json', 'isDraft'])); } catch {}
  if (release && !release.isDraft) throw new Error('Versão já pública. Gere uma nova versão.');
  const notes = path.join(dir, 'RELEASE-NOTES.md');
  await fs.writeFile(notes, `Project Craft Launcher ${version}\n\nInstalador MSI padrão do Windows e edição ZIP. Instala Java 17, Forge e o pacote oficial, com atualizações verificadas, reparo e identidade visual do Project Craft.\n\nEsta versão foi reconstruída em pasta limpa, com dependências travadas, procedência npm e checksum oficial do Electron. O MSI, o ZIP e os arquivos extraídos passaram na verificação local do Microsoft Defender em 25/10/2026. Os resultados e hashes desta compilação estão em SECURITY-CHECKS.json e BUILD-PROVENANCE.json. Veja os hashes em SHA256SUMS.txt.\n\n${allowUnsigned ? 'Publicação sem certificado de publicador, autorizada pelo responsável pelo projeto. O Windows pode mostrar avisos de aplicativo desconhecido. A verificação local não garante ausência de alertas em outras máquinas.' : 'Distribuição com assinatura válida de publicador e verificação local.'}\n\nO antigo instalador 1.0.1 continua retirado após alerta Program:Win32/Contebrew.A!ml. Não execute nem libere o arquivo anterior. Não há confirmação de falso positivo.\n\nAs atualizações do jogo são automáticas ao preparar/jogar. A atualização do launcher é baixada e conferida por assinatura do canal e SHA-256; sua instalação é apresentada pelo Windows após confirmação.\n\nO jogo sempre abre no menu inicial. O pacote 0.9.3 oferece cadastro por nick na tela do jogo e preserva as identidades Microsoft existentes; o acesso continua sujeito à whitelist.\n\nSite: https://project-craft-fps.vercel.app/#downloads\nDiscord: https://discord.gg/vZYuuR6KUG\n`);
  if (!release) await gh(['release', 'create', tag, '--draft', '--title', `Project Craft Launcher ${version}`, '--notes-file', notes]);
  else await gh(['release', 'edit', tag, '--notes-file', notes]);
  const msi = `ProjectCraft-Setup-${version}-x64.msi`;
  const zip = `ProjectCraft-${version}-x64.zip`;
  const assets = [msi, zip, 'SHA256SUMS.txt', 'BUILD-PROVENANCE.json'];
  if (security) {
    const {publicReady, ...publicReport} = security;
    publicReport.publication = {unsignedApprovedByOwner: allowUnsigned};
    await fs.writeFile(path.join(dir, 'SECURITY-CHECKS.json'), JSON.stringify(publicReport, null, 2) + '\n');
    assets.push('SECURITY-CHECKS.json');
  }
  await gh(['release', 'upload', tag, ...assets.map(f => path.join(dir, f)), '--clobber']);
  if (!publish) {
    console.log('Candidato enviado como rascunho privado. Downloads públicos continuam suspensos.');
    return;
  }
  const manifest = JSON.parse(await fs.readFile(path.join(ROOT, 'channel', 'stable.json'), 'utf8'));
  manifest.launcher = {enabled: true, status: 'published', version, format: 'msi', publisherSigned: !allowUnsigned,
    notice: allowUnsigned ? 'Sem certificado de publicador. O Windows pode mostrar avisos de aplicativo desconhecido.' : '',
    url: `https://github.com/VagJr/project-craft-launcher/releases/download/${tag}/${msi}`,
    sha256: await hashFile(path.join(dir, msi)), size: (await fs.stat(path.join(dir, msi))).size,
    zip: {url: `https://github.com/VagJr/project-craft-launcher/releases/download/${tag}/${zip}`,
      sha256: await hashFile(path.join(dir, zip)), size: (await fs.stat(path.join(dir, zip))).size}};
  await gh(['release', 'edit', tag, '--draft=false', '--latest']);
  await signed('stable', manifest);
  await pushFiles(['channel'], `Publica launcher ${version} validado e assinado`);
  console.log('Launcher publicado e canal assinado atualizado.');
}

if (require.main === module) publishLauncher({publish: process.argv.includes('--publish'), allowUnsigned: process.argv.includes('--allow-unsigned')}).catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = {publishLauncher};
