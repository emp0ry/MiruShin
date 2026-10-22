export const RELEASE_PAGE = 'https://github.com/emp0ry/MiruShin/releases/latest';
export const RELEASE_API = 'https://api.github.com/repos/emp0ry/MiruShin/releases/latest';
export const DOWNLOAD_PATTERNS = {
    'windows-setup': /^MiruShin-windows-v[\d.]+-setup\.exe$/i,
    'windows-msi': /^MiruShin-windows-v[\d.]+-setup\.msi$/i,
    'windows-portable': /^MiruShin-windows-v[\d.]+-portable\.zip$/i,
    macos: /^MiruShin-macos-v[\d.]+\.dmg$/i,
    'linux-appimage': /^MiruShin-linux-v[\d.]+\.AppImage$/i,
    'linux-deb': /^MiruShin-linux-v[\d.]+\.deb$/i,
    'linux-targz': /^MiruShin-linux-v[\d.]+\.tar\.gz$/i,
    android: /^MiruShin-android-v[\d.]+\.apk$/i,
    ios: /^MiruShin-ios-v[\d.]+\.ipa$/i,
} as const;
export type DownloadKey = keyof typeof DOWNLOAD_PATTERNS;
export interface DownloadAsset { name: string; url: string; size: number }
export interface Release { label: string; url: string; assets: Partial<Record<DownloadKey, DownloadAsset>> }

function officialURL(value: unknown, download = false): string | null {
    if (typeof value !== 'string') return null;
    try {
        const url = new URL(value);
        if (url.origin !== 'https://github.com' || url.username || url.password || url.search || url.hash) return null;
        const prefix = download ? '/emp0ry/MiruShin/releases/download/' : '/emp0ry/MiruShin/releases/tag/';
        return url.pathname.startsWith(prefix) && url.pathname.length > prefix.length ? url.href : null;
    } catch { return null; }
}

/** A failed/missing asset stays a real release-page destination, never a guessed binary. */
export function parseRelease(value: unknown): Release | null {
    if (!value || typeof value !== 'object') return null;
    const data = value as Record<string, unknown>;
    const url = officialURL(data.html_url);
    if (!url || data.draft === true || data.prerelease === true || typeof data.tag_name !== 'string' || !/^v?\d+(?:\.\d+){1,3}$/.test(data.tag_name)) return null;
    const assets: Release['assets'] = {};
    if (Array.isArray(data.assets)) for (const candidate of data.assets) {
        if (!candidate || typeof candidate !== 'object') continue;
        const asset = candidate as Record<string, unknown>;
        const download = officialURL(asset.browser_download_url, true);
        if (!download || typeof asset.name !== 'string' || typeof asset.size !== 'number' || !Number.isSafeInteger(asset.size) || asset.size <= 0 || asset.state !== 'uploaded') continue;
        const parts = new URL(download).pathname.split('/');
        let filename: string;
        try { filename = decodeURIComponent(parts.at(-1)!); } catch { continue; }
        if (filename !== asset.name || parts.at(-2) !== data.tag_name) continue;
        for (const key of Object.keys(DOWNLOAD_PATTERNS) as DownloadKey[]) if (DOWNLOAD_PATTERNS[key].test(asset.name) && !assets[key]) assets[key] = { name: asset.name, url: download, size: asset.size };
    }
    return { label: data.tag_name, url, assets };
}

export function formatSize(bytes: number): string {
    return `${(bytes / 1_000_000).toFixed(bytes < 100_000_000 ? 1 : 0)} MB`;
}

export function mountReleases(root: HTMLElement) {
    const lifetime = new AbortController();
    let requested = false;
    async function resolve() {
        if (requested) return;
        requested = true;
        const status = root.querySelector<HTMLElement>('[data-release-status]')!;
        status.textContent = 'Checking the latest official release…';
        try {
            const response = await fetch(RELEASE_API, {
                headers: { Accept: 'application/vnd.github+json' },
                signal: AbortSignal.any([lifetime.signal, AbortSignal.timeout(6500)]),
            });
            if (!response.ok) throw new Error('Release unavailable');
            const release = parseRelease(await response.json());
            if (!release) throw new Error('Invalid release');
            if (lifetime.signal.aborted) return;
            document.querySelectorAll<HTMLElement>('[data-release-label]').forEach(node => { node.textContent = release.label; });
            root.querySelectorAll<HTMLAnchorElement>('[data-download]').forEach(link => {
                const asset = release.assets[link.dataset.download as DownloadKey];
                link.href = asset?.url ?? release.url;
                const size = link.querySelector<HTMLElement>('[data-file-size]')!;
                size.textContent = asset ? formatSize(asset.size) : 'Release page';
                link.setAttribute('aria-label', asset ? `Download ${asset.name}, ${formatSize(asset.size)}` : `View release for ${link.querySelector('strong')?.textContent}`);
                link.querySelector('.file-arrow')!.textContent = asset ? '↓' : '↗';
            });
            status.textContent = `Latest stable release · ${release.label}`;
            root.dataset.release = 'resolved';
        } catch {
            if (lifetime.signal.aborted) return;
            status.textContent = 'Live check unavailable. Download links open the official release page.';
            root.dataset.release = 'fallback';
        }
    }
    const observer = new IntersectionObserver(entries => {
        if (entries.some(entry => entry.isIntersecting)) { observer.disconnect(); void resolve(); }
    }, { rootMargin: '600px' });
    observer.observe(root);
    return { destroy() { lifetime.abort(); observer.disconnect(); } };
}
