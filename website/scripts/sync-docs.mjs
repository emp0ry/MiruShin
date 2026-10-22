import { readdir, readFile, mkdir, copyFile, writeFile, rm } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
const output = resolve('dist'), destination = resolve('../docs');
const manifest = resolve('pages-files.json');
async function files(directory, prefix = '') {
    const result = [];
    for (const entry of await readdir(directory, { withFileTypes: true })) {
        const name = join(prefix, entry.name);
        if (entry.isDirectory()) result.push(...await files(join(directory, entry.name), name));
        else result.push(name);
    }
    return result;
}
const next = await files(output);
let previous = [];
try { previous = JSON.parse(await readFile(manifest, 'utf8')); } catch {}
for (const file of previous) {
    if (!file.startsWith('site/') && !['index.html','privacy.html','legal.html','404.html'].includes(file)) throw new Error('Unmanaged output path');
    if (!next.includes(file)) await rm(resolve(destination, file), { force: true });
}
for (const file of next) {
    const target = resolve(destination, file);
    if (!target.startsWith(destination + '/')) throw new Error('Invalid output path');
    await mkdir(dirname(target), { recursive: true }); await copyFile(resolve(output, file), target);
}
await writeFile(manifest, JSON.stringify(next.sort(), null, 2) + '\n');
console.log(`Synced ${next.length} website files to docs; installer source, app opener and legacy assets retained.`);
// Include retained public endpoints in the preview without ever writing stale
// copies back to docs (source.json is updated independently by release automation).
const retained = ['CNAME','.nojekyll','open.html','source.json','robots.txt','sitemap.xml','site.webmanifest'];
for(const entry of await readdir(resolve(destination,'assets'),{withFileTypes:true})) {
    if(entry.isFile() && /\.(?:png|ico)$/.test(entry.name)) retained.push(`assets/${entry.name}`);
}
for(const file of retained) {
    await mkdir(dirname(resolve(output,file)),{recursive:true});
    await copyFile(resolve(destination,file),resolve(output,file));
}
