// 下载锁定的实验材料并在忽略目录解包，生成不访问网络的 CodeMirror 浏览器包。
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'note_by_agent/entry/src/main/resources/rawfile/web-editor-demo');
const cache = path.join(root, 'note_by_agent/build/verification/web-editor-build');
const versions = {
  '@codemirror/state': '6.5.2', '@codemirror/view': '6.36.5', '@codemirror/commands': '6.8.1',
  '@codemirror/language': '6.11.0', '@lezer/common': '1.2.3', '@lezer/highlight': '1.2.1',
  '@lezer/lr': '1.4.2', '@marijn/find-cluster-break': '1.0.2',
  'style-mod': '4.1.2', 'w3c-keyname': '2.2.8', '@esbuild/win32-x64': '0.25.5'
};
const download = url => fetch(url, { signal: AbortSignal.timeout(30000) });
async function main() {
  fs.mkdirSync(cache, { recursive: true });
  const lock = [];
  const licenses = [];
  const lockPath = path.join(output, 'dependencies.lock.json');
  const previousLock = fs.existsSync(lockPath) ? JSON.parse(fs.readFileSync(lockPath, 'utf8')) : [];
  for (const [name, version] of Object.entries(versions)) {
    const tarball = path.join(cache, name.replace(/[\/ @]/g, '_') + '.tgz');
    const destination = path.join(cache, 'node_modules', name);
    const metadataUrl = `https://registry.npmjs.org/${name}/${version}`;
    const offline = process.argv.includes('--offline');
    let metadata;
    let bytes;
    if (offline) {
      metadata = JSON.parse(fs.readFileSync(path.join(destination, 'package.json'), 'utf8'));
      if (metadata.version !== version) throw new Error('Cached version mismatch');
      metadata.dist = { tarball: `https://registry.npmjs.org/${name}/-/${name.split('/').pop()}-${version}.tgz` };
      bytes = fs.readFileSync(tarball);
    } else {
      const response = await download(metadataUrl);
      if (!response.ok) throw new Error(`${metadataUrl}: ${response.status}`);
      metadata = await response.json();
      const tarResponse = await download(metadata.dist.tarball);
      if (!tarResponse.ok) throw new Error(`Download failed: ${name}`);
      bytes = Buffer.from(await tarResponse.arrayBuffer());
    }
    for (const dependency of Object.keys(metadata.dependencies || {})) {
      if (!versions[dependency]) throw new Error(`Unpinned dependency: ${dependency}`);
    }
    const integrity = `sha512-${crypto.createHash('sha512').update(bytes).digest('base64')}`;
    if (metadata.dist.integrity && metadata.dist.integrity !== integrity) throw new Error(`Integrity mismatch: ${name}`);
    const pinned = previousLock.find(item => item.name === name && item.version === version);
    if (pinned && pinned.integrity !== integrity) throw new Error(`Lock integrity mismatch: ${name}`);
    fs.writeFileSync(tarball, bytes);
    fs.mkdirSync(destination, { recursive: true });
    execFileSync('tar', ['-xzf', tarball, '-C', destination, '--strip-components=1']);
    const licenseFile = ['LICENSE', 'LICENSE.txt', 'LICENSE.md'].map(file => path.join(destination, file)).find(file => fs.existsSync(file));
    let license;
    if (licenseFile) license = fs.readFileSync(licenseFile, 'utf8');
    else if (name === '@esbuild/win32-x64') {
      if (!offline) {
        const licenseResponse = await download(`https://registry.npmjs.org/esbuild/-/esbuild-${version}.tgz`);
        if (!licenseResponse.ok) throw new Error('esbuild license download failed');
        const licenseTarball = path.join(cache, 'esbuild-license.tgz');
        fs.writeFileSync(licenseTarball, Buffer.from(await licenseResponse.arrayBuffer()));
        execFileSync('tar', ['-xzf', licenseTarball, '-C', cache]);
      }
      license = fs.readFileSync(path.join(cache, 'package/LICENSE.md'), 'utf8');
    } else throw new Error(`License missing: ${name}`);
    licenses.push(`${name}@${version}\n${license}`);
    lock.push({ name, version, tarball: metadata.dist.tarball, integrity, dependencies: metadata.dependencies || {} });
  }
  const entry = path.join(cache, 'probe.js');
  fs.copyFileSync(path.join(output, 'probe.js'), entry);
  fs.copyFileSync(path.join(output, 'performance.js'), path.join(cache, 'performance.js'));
  execFileSync(path.join(cache, 'node_modules/@esbuild/win32-x64/esbuild.exe'), [entry, '--bundle', '--format=iife', '--target=es2020', '--legal-comments=inline', `--outfile=${path.join(output, 'probe.bundle.js')}`], { stdio: 'inherit' });
  fs.writeFileSync(path.join(output, 'dependencies.lock.json'), JSON.stringify(lock, null, 2) + '\n');
  fs.writeFileSync(path.join(output, 'THIRD_PARTY_LICENSES.txt'), licenses.join('\n\n--------------------\n\n'));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
