$ErrorActionPreference='Stop'
$root=Join-Path (Split-Path -Parent $PSScriptRoot) ('.local\qa-updater\e2e-'+[guid]::NewGuid().ToString())
$app=Join-Path $root 'app';$next=Join-Path $root 'next';$data=Join-Path $root 'ProjectCraft'
$null=New-Item -ItemType Directory -Path (Join-Path $app 'resources'),(Join-Path $next 'resources'),$data -Force
foreach($version in @('1.1.1','1.2.0')) {
 $name='CraftFixture'+$version.Replace('.','')
 $action=if($version -eq '1.1.1'){'for(int i=0;i<600&&!File.Exists(Path.Combine(root,"stop"));i++)Thread.Sleep(100);'}else{'File.WriteAllText(Path.Combine(root,"restarted.txt"),"1.2.0");'}
 $source=@"
using System;using System.IO;using System.Threading;using System.Reflection;
[assembly:AssemblyVersion("$version.0")][assembly:AssemblyFileVersion("$version.0")][assembly:AssemblyInformationalVersion("$version")]
public class $name { public static void Main(){string root=AppDomain.CurrentDomain.BaseDirectory;$action} }
"@
 $target=if($version -eq '1.1.1'){$app}else{$next}
 Add-Type -TypeDefinition $source -OutputAssembly (Join-Path $target 'Project Craft.exe') -OutputType WindowsApplication
}
[IO.File]::WriteAllText((Join-Path $app 'resources\app.asar'),'old-payload');[IO.File]::WriteAllText((Join-Path $app 'personal-notes.txt'),'keep-user-file')
[IO.File]::WriteAllText((Join-Path $next 'resources\app.asar'),'new-payload');[IO.File]::WriteAllText((Join-Path $data 'preferences.json'),'keep-settings');[IO.File]::WriteAllText((Join-Path $data 'account.secure'),'fake-encrypted-account')
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($next,(Join-Path $root 'update.zip'))
@{root=$root;executable=(Join-Path $app 'Project Craft.exe');package=(Join-Path $root 'update.zip');dataDir=$data}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) '.local\updater-e2e.json') -Encoding UTF8
Write-Output 'Isolated versioned executables prepared'
