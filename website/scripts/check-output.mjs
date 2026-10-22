import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
const read=path=>readFileSync(path,'utf8');
const hash=value=>createHash('sha256').update(value).digest('hex');
const pages=['index','privacy','legal','404'];
const main=read('dist/index.html');
const ids=[...main.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);
assert.equal(ids.length,new Set(ids).size,'No duplicate IDs');
for(const id of ['top','main','features','experience','downloads','responsibility'])assert(ids.includes(id),`Preserve #${id}`);
assert.equal((main.match(/data-download="/g)||[]).length,9,'All nine package destinations stay in HTML');
assert.equal((main.match(/id="download-[^"]+"/g)||[]).length,5,'Five platform panels');
for(const name of ['windows-setup','windows-msi','windows-portable','macos','linux-appimage','linux-deb','linux-targz','android','ios'])assert(main.includes(`data-download="${name}" href="https://github.com/emp0ry/MiruShin/releases/latest"`),'A download must have a no-script/network fallback');
assert(!/id="(?:screen|download)-[^"]+"[^>]*\bhidden/.test(main),'Without JavaScript screenshots and platforms remain accessible');
const normalize=s=>s.replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim();
for(const name of ['privacy','legal']) {
 const body=read(`dist/${name}.html`).match(/<article class="document-copy">([\s\S]*?)<\/article>/)[1];
 assert.equal(normalize(body),normalize(read(`design/${name}-body.html`)),`Preserve published ${name} wording`);
}
const baseline=JSON.parse(read('design/baseline.json'));
for(const file of ['source.json','open.html','CNAME','robots.txt','sitemap.xml'])assert.equal(hash(readFileSync(resolve('../docs',file))),baseline[file],`Do not rewrite retained ${file}`);
const routing=read('dist/404.html').match(/<script>([\s\S]*?)<\/script>/)[1];
assert.equal(hash(routing),baseline['404-routing'],'Preserve validated clean-media route bridge');
for(const name of pages) {
 const html=read(`dist/${name}.html`);
 assert(!/@include/.test(html),'Resolve template includes');
 assert.equal((html.match(/<h1\b/g)||[]).length,1,`${name}: one primary heading`);
 assert(html.includes('class="page-scroll"'),'Retain clipped native scrollport');
 assert(html.includes('https://mirushin.emp0ry.com/'),'Canonical product domain');
 for(const tag of ['description','og:title','og:image','og:image:width','og:image:height','og:image:alt','twitter:card','theme-color'])assert(html.includes(`="${tag}"`),`${name}: metadata ${tag}`);
 const policy=html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)[1];
 assert(!/unsafe-inline|unsafe-eval/.test(policy),'No unrestricted inline executable scripts');
 for(const [,body]of html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g))assert(policy.includes(`'sha256-${createHash('sha256').update(body).digest('base64')}'`),'Exact inline script CSP hash');
 for(const [,asset]of html.matchAll(/(?:src|href)="(\/(?!\/)[^"?#]+)"/g))assert(existsSync(resolve('dist',asset.slice(1))),`${name}: missing ${asset}`);
 for(const [,anchor]of html.matchAll(/href="#([^"]+)"/g))assert(html.includes(`id="${anchor}"`),`${name}: missing anchor ${anchor}`);
 for(const [,link]of html.matchAll(/(<a\b[^>]*target="_blank"[^>]*>)/g))assert(/rel="[^"]*noopener/.test(link),'External tabs need noopener');
 assert(!/fonts\.googleapis\.com|fonts\.gstatic\.com/.test(html),'Self-hosted font only');
}
const js=readFileSync(resolve('dist',main.match(/src="(\/site\/build\/[^" ]+\.js)"/)[1].slice(1)),'utf8');
assert(js.includes('G-QY5L70VTTG'),'Retain the original GA4 property');
assert(js.includes('mirushin.emp0ry.com')&&js.includes('https:'),'Analytics retains the production-host gate');
const png=readFileSync('dist/assets/social-preview.png');assert.equal(png.readUInt32BE(16),1200);assert.equal(png.readUInt32BE(20),630);
const manifest=JSON.parse(read('dist/site.webmanifest'));
for(const icon of manifest.icons)assert(existsSync(resolve('dist',icon.src)),`Manifest icon missing ${icon.src}`);
for(const file of JSON.parse(read('pages-files.json')))assert(readFileSync(resolve('dist',file)).equals(readFileSync(resolve('../docs',file))),`Docs output drift ${file}`);
console.log('Production output: pages, metadata, CSP, 9 download fallbacks, preserved policy text, app-link bridge/source feed/domain, local fonts and matching Pages output pass.');
