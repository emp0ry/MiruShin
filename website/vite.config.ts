import { defineConfig } from 'vite';
import { resolve } from 'node:path';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

export default defineConfig(({ command }) => ({
    root: resolve('src'), publicDir: resolve('src/public'),
    build: { outDir: resolve('dist'), emptyOutDir: true, assetsDir: 'site/build',
        rollupOptions: { input: Object.fromEntries(['index','privacy','legal','404'].map(name => [name, resolve(`src/${name}.html`)])) } },
    plugins: [{ name: 'site-partials', transformIndexHtml: { order: 'pre', handler(html) {
        return html.replace(/<!-- @include ([a-z-]+) -->/g, (_, name) => readFileSync(resolve(`src/${name}.html`), 'utf8'));
    } } }, { name: 'site-csp', transformIndexHtml: { order: 'post', handler(html) {
        if (command !== 'build') return html;
        const hashes = [...html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)]
            .map(([, body]) => `'sha256-${createHash('sha256').update(body).digest('base64')}'`);
        const policy = ["default-src 'self'", "base-uri 'self'", "object-src 'none'", "form-action 'none'",
            `script-src 'self' ${hashes.join(' ')} https://www.googletagmanager.com https://www.google-analytics.com`,
            "style-src 'self'", "font-src 'self'", "img-src 'self' data: https://www.googletagmanager.com https://*.google-analytics.com",
            "connect-src 'self' https://api.github.com https://*.google-analytics.com https://*.googletagmanager.com https://analytics.google.com",
            "frame-src 'none'", "upgrade-insecure-requests"].join('; ');
        return html.replace('<meta charset="utf-8">', `<meta charset="utf-8">\n<meta http-equiv="Content-Security-Policy" content="${policy}">`);
    } } }],
    server: { host: '127.0.0.1', port: 5175, strictPort: true },
    preview: { host: '127.0.0.1', port: 4175, strictPort: true },
}));
