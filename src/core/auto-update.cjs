const fs = require('node:fs/promises');
const path = require('node:path');
const {approvedUpdate, downloadUpdate, verifyUpdate} = require('./launcher-update.cjs');
const {atomicJSON} = require('./safe-files.cjs');

class AutoUpdate {
  constructor({version, dataDir, release, format, install, canInstall, emit, now = Date.now, download = downloadUpdate, verify = verifyUpdate}) {
    Object.assign(this, {version, dataDir, release, format, install, canInstall, emit, now, download, verify});
    this.pending = null; this.checking = null; this.applying = null; this.retryAfter = 0; this.handedOff = false;
  }
  get installing() { return this.handedOff || !!this.applying; }
  async initialize() {
    try {
      const result = JSON.parse(await fs.readFile(path.join(this.dataDir, 'updates', 'result.json'), 'utf8'));
      if (!result.success && this.now() - Date.parse(result.finishedAt) < 3600000) {
        this.retryAfter = Date.parse(result.finishedAt) + 3600000;
        this.emit({phase: 'launcher-update-error', message: 'A atualização anterior não foi concluída. O launcher foi preservado; tentaremos novamente mais tarde.'});
      }
    } catch {}
  }
  check({apply = true} = {}) {
    if (this.checking) return this.checking;
    if (this.installing || this.now() < this.retryAfter) return Promise.resolve(false);
    this.checking = this.findUpdate(apply).finally(() => { this.checking = null; });
    return this.checking;
  }
  async findUpdate(apply) {
    try {
      const latest = await this.release();
      if (latest.cached) return false;
      const format = await this.format(), approved = approvedUpdate(latest.manifest, this.version, format);
      if (!approved) { this.pending = null; return false; }
      if (!this.pending || this.pending.sha256 !== approved.sha256) {
        this.emit({phase: 'launcher-update-download', message: 'Baixando a atualização do launcher em segundo plano.'});
        this.pending = await this.download(latest.manifest, this.version, this.dataDir, {format});
      }
      this.emit({phase: 'launcher-update-ready', message: this.canInstall() ? 'Atualização verificada. O launcher será reaberto automaticamente.' : 'Atualização pronta. Será aplicada automaticamente quando o jogo e a preparação terminarem.'});
      if (apply) return await this.idle();
    } catch (error) {
      this.retryAfter = this.now() + 300000;
      this.emit({phase: 'launcher-update-error', message: 'Não foi possível atualizar o launcher agora. Sua versão atual foi mantida.'});
      await this.logError(error);
    }
    return false;
  }
  idle({force = false} = {}) {
    if (this.installing) return this.applying || Promise.resolve(true);
    if (!this.pending || !this.canInstall() || (!force && this.now() < this.retryAfter)) return Promise.resolve(false);
    this.applying = this.apply().finally(() => { this.applying = null; });
    return this.applying;
  }
  async apply() {
    try {
      const latest = await this.release();
      if (latest.cached) throw new Error('A confirmação online da atualização não está disponível.');
      const approved = approvedUpdate(latest.manifest, this.version, this.pending.format);
      if (!approved || approved.sha256 !== this.pending.sha256) { this.pending = null; return false; }
      await this.verify(this.pending);
      if (!this.canInstall()) return false;
      this.emit({phase: 'launcher-update-installing', message: 'Atualizando o launcher. Ele será reaberto em instantes.'});
      const started = await this.install(this.pending);
      if (!started) throw new Error('O atualizador não confirmou a preparação.');
      this.handedOff = true;
      return true;
    } catch (error) {
      this.retryAfter = this.now() + 3600000;
      this.emit({phase: 'launcher-update-error', message: 'A atualização foi adiada. Seus arquivos e o launcher atual foram preservados.'});
      await this.logError(error);
      return false;
    }
  }
  async logError(error) {
    await fs.mkdir(path.join(this.dataDir, 'updates'), {recursive: true});
    await atomicJSON(path.join(this.dataDir, 'updates', 'last-error.json'), {at: new Date(this.now()).toISOString(), message: error.message}).catch(() => {});
  }
}
module.exports = {AutoUpdate};
