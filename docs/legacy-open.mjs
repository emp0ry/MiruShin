import { canonicalMediaUrl, parseLegacyTarget } from './link-routing.mjs';

const status = document.getElementById('status');
const button = document.getElementById('open-in-mirushin');
const parameters = new URLSearchParams(location.search);
const keys = [...parameters.keys()];
const values = parameters.getAll('target');
const parsed =
  keys.length === 1 && keys[0] === 'target' && values.length === 1
    ? parseLegacyTarget(values[0])
    : null;

if (!parsed) {
  status.textContent = 'This MiruShin link is invalid.';
} else if (parsed.kind === 'media') {
  location.replace(canonicalMediaUrl(parsed.route));
} else {
  button.href = parsed.target;
  button.hidden = false;
  status.textContent =
    'MiruShin should open automatically. Use the button if your browser asks for confirmation.';
  let shouldAttempt = true;
  try {
    const key = `mirushin-opened:${parsed.target}`;
    shouldAttempt = sessionStorage.getItem(key) !== '1';
    if (shouldAttempt) sessionStorage.setItem(key, '1');
  } catch (_) {
    // Storage can be blocked; this module itself runs only once per page load.
  }
  if (shouldAttempt) {
    setTimeout(() => {
      location.href = parsed.target;
    }, 120);
  }
}
