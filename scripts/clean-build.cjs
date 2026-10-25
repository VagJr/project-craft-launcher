const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const run = promisify(execFile);
const {hashFile} = require('../src/core/safe-files.cjs');
const ROOT = path.resolve(__dirname, '..');

async function files(dir, prefix = '') {
  const result = [];
  for (const entry of await fs.readdir(dir, {withFileTypes: true})) {
    if (entry.isSymbolicLink()) throw new Error('Link inesperado na fonte.');
    const name = path.posix.join(prefix, entry.name);
    if (entry.isDirectory()) result.push(...await files(path.join(dir, entry.name), name));
    else result.push(name);
  }
  return result;
}

async function main() {
  const pkg = require('../package.json');
  const work = path.join(ROOT, '.local', 'clean-build', `${pkg.version}-${crypto.randomUUID()}`);
  const output = path.join(ROOT, 'build', pkg.version);
  await fs.mkdir(work, {recursive: true});
  const inputs = ['package.json', 'package-lock.json', 'release-public-key.pem',
    ...await files(path.join(ROOT, 'src'), 'src'), ...await files(path.join(ROOT, 'assets'), 'assets')];
  const source = [];
  for (const file of inputs.sort()) {
    const dest = path.join(work, file);
    await fs.mkdir(path.dirname(dest), {recursive: true});
    await fs.copyFile(path.join(ROOT, file), dest);
    source.push({file, sha256: await hashFile(dest)});
  }
  async function command(name, args, log) {
    try {
      const result = await run(name, args, {cwd: work, windowsHide: true, maxBuffer: 16 * 1024 ** 2});
      await fs.writeFile(path.join(work, log), result.stdout + result.stderr);
      return result.stdout;
    } catch (error) {
      await fs.writeFile(path.join(work, log), (error.stdout || '') + (error.stderr || ''));
      throw error;
    }
  }
  const npm = process.env.npm_execpath;
  if (!npm) throw new Error('Execute por npm run build:clean.');
  console.log('Instalando dependências travadas em pasta nova, sem scripts automáticos.');
  await command(process.execPath, [npm, 'ci', '--ignore-scripts', '--no-audit', '--no-fund'], 'npm-ci.log');
  console.log('Verificando assinaturas de procedência dos pacotes npm.');
  await command(process.execPath, [npm, 'audit', 'signatures'], 'npm-signatures.log');
  const audit = JSON.parse(await command(process.execPath, [npm, 'audit', '--json'], 'npm-audit.json'));
  if (audit.metadata?.vulnerabilities?.total !== 0) throw new Error('A auditoria de dependências precisa de revisão.');

  console.log('Baixando Electron oficial e conferindo SHA-256 publicado pelo fornecedor.');
  const electronRequire = require('node:module').createRequire(path.join(work, 'node_modules', 'electron', 'package.json'));
  const electronGet = electronRequire('@electron/get');
  const version = pkg.devDependencies.electron;
  const archive = await electronGet.downloadArtifact({version, artifactName: 'electron', platform: 'win32', arch: 'x64'});
  const filename = `electron-v${version}-win32-x64.zip`;
  const sumsURL = `https://github.com/electron/electron/releases/download/v${version}/SHASUMS256.txt`;
  const response = await fetch(sumsURL, {signal: AbortSignal.timeout(60000)});
  if (!response.ok) throw new Error('Não foi possível obter checksums oficiais.');
  const sums = await response.text();
  const line = sums.split('\n').find(line => line.trim().split(/\s+/)[1]?.replace(/^\*/, '') === filename);
  const expected = line?.trim().split(/\s+/)[0];
  const actual = await hashFile(archive);
  if (!expected) throw new Error('Checksum do arquivo não encontrado na lista oficial.');
  if (expected !== actual) throw new Error('O runtime Electron diverge do checksum oficial.');
  await fs.writeFile(path.join(work, 'electron-SHASUMS256.txt'), sums);
  await command(process.execPath, [path.join(work, 'node_modules', 'electron', 'install.js')], 'electron-install.log');
  console.log('Gerando MSI padrão do Windows e arquivo ZIP.');
  const builder = path.join(work, 'node_modules', 'electron-builder', 'cli.js');
  // Independent runs keep target-specific installer options out of the ZIP configuration.
  await command(process.execPath, [builder, '--win', 'msi', '--publish', 'never'], 'builder-msi.log');
  await command(process.execPath, [builder, '--win', 'zip', '--publish', 'never'], 'builder-zip.log');
  await fs.mkdir(output, {recursive: true});
  await fs.cp(path.join(work, 'build'), output, {recursive: true});
  const artifacts = [];
  for (const file of await fs.readdir(output)) {
    if (!/\.(msi|zip)$/.test(file)) continue;
    artifacts.push({file, sha256: await hashFile(path.join(output, file)), size: (await fs.stat(path.join(output, file))).size});
  }
  const report = {version: pkg.version, builtAt: new Date().toISOString(), node: process.version,
    work, source, upstream: {url: sumsURL, archive: filename, sha256: actual},
    npm: {vulnerabilities: audit.metadata.vulnerabilities, signaturesLog: path.join(work, 'npm-signatures.log')}, artifacts};
  await fs.writeFile(path.join(output, 'BUILD-PROVENANCE.json'), JSON.stringify(report, null, 2) + '\n');
  await fs.writeFile(path.join(output, 'SHA256SUMS.txt'), artifacts.map(a => `${a.sha256}  ${a.file}`).join('\n') + '\n');
  console.log(`Build rastreável pronta em ${output}`);
}

main().catch(error => { console.error(error.message); if (error.stdout) console.error(error.stdout.slice(-4000)); if (error.stderr) console.error(error.stderr.slice(-4000)); process.exitCode = 1; });
