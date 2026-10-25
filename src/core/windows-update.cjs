const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const {atomicJSON} = require('./safe-files.cjs');
const run = promisify(execFile);
const powershell = () => path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
async function helper(dataDir) {
  const bytes = await fs.readFile(path.join(__dirname, '..', 'update-helper.ps1'));
  const digest = crypto.createHash('sha256').update(bytes).digest('hex');
  const file = path.join(dataDir, 'updates', `helper-${digest}.ps1`);
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, bytes);
  return file;
}
async function installationFormat(dataDir, executable = process.execPath) {
  const file = await helper(dataDir);
  const {stdout} = await run(powershell(), ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned', '-File', file, '-ProbeExe', executable], {windowsHide: true, timeout: 15000});
  const format = stdout.trim();
  if (!['msi', 'zip'].includes(format)) throw new Error('Não foi possível identificar a instalação do launcher.');
  return format;
}
async function startUpdate(update, dataDir, {executable = process.execPath, parentId = process.pid, parentStarted = new Date(Date.now() - process.uptime() * 1000).toISOString()} = {}) {
  const script = await helper(dataDir), root = path.join(dataDir, 'updates');
  const id = crypto.randomUUID(), job = path.join(root, id); await fs.mkdir(job);
  const plan = {schema: 1, version: update.version, format: update.format, file: update.file, sha256: update.sha256, size: update.size, executable, parentId, parentStarted, job};
  const planFile = path.join(job, 'plan.json'); await atomicJSON(planFile, plan);
  try {
    // ShellExecute through Start-Process creates an independent hidden Windows worker.
    // Direct detached PowerShell exits early; an attached worker dies with Electron.
    await run(powershell(), ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned', '-File', script, '-LaunchPlan', planFile], {windowsHide: true, timeout: 190000});
    const ready = JSON.parse(await fs.readFile(path.join(job, 'ready.json'), 'utf8'));
    if (!ready.ready) throw new Error('O atualizador não confirmou a preparação.');
    return true;
  } catch (error) {
    await fs.writeFile(path.join(job, 'cancel'), 'cancelled');
    throw new Error('O atualizador não pôde preparar a instalação. A versão atual foi preservada.');
  }
}
module.exports = {installationFormat, startUpdate};
