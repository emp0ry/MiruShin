import test from 'node:test';
import assert from 'node:assert/strict';
import { parseRelease, DOWNLOAD_PATTERNS, formatSize } from '../src/core/releases.ts';

const names = ['MiruShin-windows-v2.9.22-setup.exe','MiruShin-windows-v2.9.22-setup.msi','MiruShin-windows-v2.9.22-portable.zip','MiruShin-macos-v2.9.22.dmg','MiruShin-linux-v2.9.22.AppImage','MiruShin-linux-v2.9.22.deb','MiruShin-linux-v2.9.22.tar.gz','MiruShin-android-v2.9.22.apk','MiruShin-ios-v2.9.22.ipa'];
const fixture = () => ({ tag_name:'v2.9.22',html_url:'https://github.com/emp0ry/MiruShin/releases/tag/v2.9.22',draft:false,prerelease:false,
    assets:names.map(name=>({name,size:12345678,state:'uploaded',browser_download_url:`https://github.com/emp0ry/MiruShin/releases/download/v2.9.22/${name}`})) });

test('all nine published package formats map to their own canonical downloads',()=>{
    const release=parseRelease(fixture())!;
    assert.equal(release.label,'v2.9.22');
    assert.equal(Object.keys(release.assets).length,9);
    for(const key of Object.keys(DOWNLOAD_PATTERNS) as (keyof typeof DOWNLOAD_PATTERNS)[]) {
        assert(DOWNLOAD_PATTERNS[key].test(release.assets[key]!.name));
        assert(release.assets[key]!.url.endsWith(release.assets[key]!.name));
    }
});
test('partial releases leave missing platforms on the release page without guessing binaries',()=>{
    const data=fixture();data.assets=data.assets.slice(-1);
    const release=parseRelease(data)!;
    assert.equal(Object.keys(release.assets).length,1);assert(release.assets.ios);assert.equal(release.assets.macos,undefined);
    assert.equal(release.url,data.html_url);
});
test('untrusted destinations, wrong tags, malformed payloads and unfinished assets cannot become downloads',()=>{
    for(const url of ['https://evil.example/fake.ipa','https://github.com.attacker.example/emp0ry/MiruShin/releases/download/v2.9.22/x','https://github.com/other/MiruShin/releases/download/v2.9.22/x','javascript:alert(1)','https://user:pass@github.com/emp0ry/MiruShin/releases/download/v2.9.22/x']) {
        const data=fixture();data.assets[0].browser_download_url=url;
        assert.equal(parseRelease(data)!.assets['windows-setup'],undefined);
    }
    for(const change of [{state:'new'},{size:-1},{size:Infinity},{browser_download_url:'https://github.com/emp0ry/MiruShin/releases/download/v2.9.21/MiruShin-windows-v2.9.22-setup.exe'}]) {
        const data=fixture();Object.assign(data.assets[0],change);assert.equal(parseRelease(data)!.assets['windows-setup'],undefined);
    }
    for(const change of [{draft:true},{prerelease:true},{tag_name:'<unsafe>'},{html_url:'https://evil.example/releases/tag/v2.9.22'}])assert.equal(parseRelease({...fixture(),...change}),null);
    for(const value of [null,undefined,[],42,'release',{}])assert.equal(parseRelease(value),null);
});
test('a malformed filename URL does not prevent valid platforms from resolving',()=>{
    const data=fixture();data.assets[0].browser_download_url='https://github.com/emp0ry/MiruShin/releases/download/v2.9.22/%ZZ';
    assert.doesNotThrow(()=>parseRelease(data));assert(parseRelease(data)?.assets.ios);
});
test('file sizes use consistent decimal megabytes',()=>{assert.equal(formatSize(31946213),'31.9 MB');assert.equal(formatSize(228683695),'229 MB');});
