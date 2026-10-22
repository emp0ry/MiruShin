import './styles.css';
import { mountReleases } from './core/releases';
import { mountMark } from './core/mark';
import { mountAnchorNavigation } from './core/anchor-navigation';

document.documentElement.classList.remove('no-js');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const reducedMotion = reduced.matches || new URLSearchParams(location.search).has('reduce-motion');
document.documentElement.classList.toggle('reduce-motion', reducedMotion);
document.documentElement.dataset.motion = reducedMotion ? 'reduced' : 'full';
const events = new AbortController(), options = { signal: events.signal };
const page = document.querySelector<HTMLElement>('.page-scroll')!;
if (location.pathname === '/' || location.pathname === '/index.html') {
    document.querySelectorAll<HTMLAnchorElement>('a[href^="/#"]').forEach(link => { link.setAttribute('href',link.hash); });
}
const navigation = mountAnchorNavigation(page);
reduced.addEventListener('change', () => location.reload(), options);
document.querySelectorAll('[data-year]').forEach(node => { node.textContent = String(new Date().getFullYear()); });

function mountTabs(selector: string) {
    const tablist = document.querySelector<HTMLElement>(selector);
    if (!tablist) return;
    const tabs = [...tablist.querySelectorAll<HTMLButtonElement>('[role=tab]')];
    function select(index: number, focus = false) {
        tabs.forEach((tab, i) => {
            tab.setAttribute('aria-selected', String(i === index));
            tab.tabIndex = i === index ? 0 : -1;
            document.getElementById(tab.getAttribute('aria-controls')!)!.hidden = i !== index;
        });
        if (focus) tabs[index].focus({ preventScroll: true });
    }
    tabs.forEach((tab, index) => {
        tab.addEventListener('click', () => select(index), options);
        tab.addEventListener('keydown', event => {
            let next = index;
            if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
            else if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
            else if (event.key === 'Home') next = 0;
            else if (event.key === 'End') next = tabs.length - 1;
            else return;
            event.preventDefault(); select(next, true);
        }, options);
    });
    select(0);
}
mountTabs('.screenshot-tabs'); mountTabs('.platform-tabs');

const toggle = document.querySelector<HTMLButtonElement>('.menu-toggle')!;
const menu = document.querySelector<HTMLDialogElement>('#site-menu')!;
const viewer = document.querySelector<HTMLDialogElement>('#image-viewer')!;
let previousFocus: HTMLElement | null = null;
let navigationTarget: HTMLElement | null = null;
function open(dialog: HTMLDialogElement) {
    previousFocus = document.activeElement as HTMLElement;
    dialog.showModal(); page.classList.add('is-locked');
    dialog.querySelector<HTMLElement>('h2')!.focus({ preventScroll: true });
    if (dialog === menu) toggle.setAttribute('aria-expanded', 'true');
}
for (const dialog of [menu, viewer]) {
    dialog.querySelector('[data-close]')!.addEventListener('click', () => dialog.close(), options);
    dialog.addEventListener('close', () => {
        page.classList.remove('is-locked');
        if (dialog === menu) toggle.setAttribute('aria-expanded', 'false');
        if (navigationTarget) {
            navigationTarget.setAttribute('tabindex', '-1');
            navigationTarget.focus({ preventScroll: true }); navigationTarget = null;
        } else previousFocus?.focus({ preventScroll: true });
    }, options);
    dialog.addEventListener('click', event => {
        if (event.target !== dialog) return;
        const r = dialog.getBoundingClientRect();
        if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) dialog.close();
    }, options);
    dialog.addEventListener('keydown', event => {
        if (event.key !== 'Tab') return;
        const controls = [...dialog.querySelectorAll<HTMLElement>('button,a[href]')];
        const first = controls[0], last = controls.at(-1)!;
        if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog.querySelector('h2'))) { event.preventDefault(); last.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }, options);
}
toggle.addEventListener('click', () => open(menu), options);
menu.querySelectorAll<HTMLAnchorElement>('a').forEach(link => link.addEventListener('click', () => {
    if (link.origin === location.origin && link.pathname === location.pathname && link.hash) navigationTarget = document.getElementById(decodeURIComponent(link.hash.slice(1)));
    page.classList.remove('is-locked'); menu.close();
}, options));
document.querySelectorAll<HTMLAnchorElement>('.screenshot-link').forEach(link => link.addEventListener('click', event => {
    if (event.button || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const image = link.querySelector<HTMLImageElement>('img')!;
    event.preventDefault();
    const large = document.querySelector<HTMLImageElement>('#viewer-image')!;
    large.src = link.href; large.alt = image.alt;
    document.querySelector('#image-title')!.textContent = link.dataset.imageTitle ?? 'MiruShin';
    open(viewer);
}, options));
document.querySelector<HTMLButtonElement>('.copy-button')?.addEventListener('click', async event => {
    const button = event.currentTarget as HTMLButtonElement;
    const status = document.querySelector<HTMLElement>('.copy-status')!;
    try {
        await navigator.clipboard.writeText('https://mirushin.emp0ry.com/source.json');
        if (events.signal.aborted) return;
        button.textContent = 'Copied'; status.textContent = 'Official source URL copied.';
    } catch { status.classList.remove('sr-only'); status.textContent = 'Select and copy the source URL above.'; }
}, options);

const markHost = document.querySelector<HTMLElement>('#mark-field');
const mark = markHost ? mountMark(markHost, reducedMotion) : null;
const downloadHost = document.querySelector<HTMLElement>('#downloads');
const releases = downloadHost ? mountReleases(downloadHost) : null;

// Website analytics retain the existing property and exclude local development.
if (location.protocol === 'https:' && ['mirushin.emp0ry.com'].includes(location.hostname)) {
    const w = window as typeof window & { dataLayer?: unknown[]; gtag?: (...args: unknown[]) => void };
    w.dataLayer ??= [];
    w.gtag ??= function () { w.dataLayer!.push(arguments); };
    w.gtag('js', new Date()); w.gtag('config', 'G-QY5L70VTTG');
    const script = document.createElement('script');
    script.async = true; script.src = 'https://www.googletagmanager.com/gtag/js?id=G-QY5L70VTTG';
    document.head.append(script);
}

const metrics: PerformanceObserver[] = [];
let cls = 0;
document.documentElement.dataset.cls = '0';
try {
    const observer = new PerformanceObserver(list => { for (const entry of list.getEntries()) document.documentElement.dataset.lcp = entry.startTime.toFixed(1); });
    observer.observe({ type: 'largest-contentful-paint', buffered: true }); metrics.push(observer);
} catch {}
try {
    const observer = new PerformanceObserver(list => {
        for (const entry of list.getEntries()) { const shift = entry as PerformanceEntry & { hadRecentInput: boolean; value: number }; if (!shift.hadRecentInput) cls += shift.value; }
        document.documentElement.dataset.cls = cls.toFixed(4);
    }); observer.observe({ type: 'layout-shift', buffered: true }); metrics.push(observer);
} catch {}
if (import.meta.hot) import.meta.hot.dispose(() => {
    events.abort(); mark?.destroy(); releases?.destroy(); navigation.destroy(); metrics.forEach(observer => observer.disconnect());
    for (const dialog of [menu,viewer]) if (dialog.open) dialog.close();
    page.classList.remove('is-locked');
});
