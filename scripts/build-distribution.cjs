const {execFileSync} = require('node:child_process');
const builder = require.resolve('electron-builder/cli.js');
for (const target of ['msi', 'zip']) {
  execFileSync(process.execPath, [builder, '--win', target, '--publish', 'never'], {stdio: 'inherit', windowsHide: true});
}
