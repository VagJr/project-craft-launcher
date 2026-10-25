const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const {spawn,execFile}=require('node:child_process');const {promisify}=require('node:util');
const {installationFormat,startUpdate}=require('../src/core/windows-update.cjs');
(async()=>{
 const launcher=path.resolve(__dirname,'..'),ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 await promisify(execFile)(ps,['-NoProfile','-ExecutionPolicy','RemoteSigned','-File',path.join(__dirname,'prepare-updater-e2e.ps1')],{windowsHide:true});
 const fixture=JSON.parse((await fs.readFile(path.join(launcher,'.local/updater-e2e.json'),'utf8')).replace(/^\uFEFF/,''));
 const {root,executable,dataDir}=fixture,bytes=await fs.readFile(fixture.package),sha256=crypto.createHash('sha256').update(bytes).digest('hex');
 const file=path.join(dataDir,'updates',sha256+'.zip'),format=await installationFormat(dataDir,executable);if(format!=='zip')throw new Error('Fixture not portable');await fs.copyFile(fixture.package,file);
 const before=await fs.readFile(executable),parent=spawn(executable,[],{windowsHide:true,stdio:'ignore'}),exited=new Promise((resolve,reject)=>{parent.on('exit',resolve);parent.on('error',reject)});if(!parent.pid)throw new Error('Fixture did not start');
 try {
  if(!await startUpdate({version:'1.2.0',format,file,sha256,size:bytes.length},dataDir,{executable,parentId:parent.pid,parentStarted:new Date().toISOString()}))throw new Error('No ready handshake');
  if(!(await fs.readFile(executable)).equals(before))throw new Error('Changed while old version running');
  await fs.writeFile(path.join(root,'app/stop'),'stop');await exited;
  const deadline=Date.now()+20000;let restarted=false;while(Date.now()<deadline){try{restarted=await fs.readFile(path.join(root,'app/restarted.txt'),'utf8')==='1.2.0';if(restarted)break}catch{}await new Promise(resolve=>setTimeout(resolve,250))}
  if(!restarted)throw new Error('New version did not restart');
  if(await fs.readFile(path.join(root,'app/resources/app.asar'),'utf8')!=='new-payload')throw new Error('Wrong payload');
  if(await fs.readFile(path.join(root,'app/personal-notes.txt'),'utf8')!=='keep-user-file'||await fs.readFile(path.join(dataDir,'preferences.json'),'utf8')!=='keep-settings'||await fs.readFile(path.join(dataDir,'account.secure'),'utf8')!=='fake-encrypted-account')throw new Error('Personal data changed');
  if(!JSON.parse(await fs.readFile(path.join(dataDir,'updates/result.json'),'utf8')).success)throw new Error('Update not successful');
  const sourceFiles={};for(const name of ['src/core/auto-update.cjs','src/core/windows-update.cjs','src/update-helper.ps1','src/main.cjs'])sourceFiles[name]=crypto.createHash('sha256').update(await fs.readFile(path.join(launcher,name))).digest('hex');
  const report={passed:true,version:'1.2.0',nativeWindows:true,realVersionedExecutables:true,sourceVersion:'1.1.1',targetVersion:'1.2.0',oldProcessWaited:true,readyHandshake:true,survivesParentExit:true,filesUpdated:true,automaticRelaunch:true,personalFilesPreserved:true,accountAndPreferencesPreserved:true,unicodePaths:root.includes('Ágil'),sourceFiles,fixtureRoot:root};
  await fs.writeFile(path.join(launcher,'../docs/launcher-1.2.0-native-upgrade.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 } finally { await fs.writeFile(path.join(root,'app/stop'),'stop').catch(()=>{}); }
})().catch(error=>{console.error(error.message);process.exitCode=1});
