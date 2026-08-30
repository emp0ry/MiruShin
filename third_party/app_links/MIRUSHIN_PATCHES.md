# MiruShin app_links patches

This directory is `app_links` 7.0.0, the newest release compatible with
MiruShin's Dart 3.11 SDK.

MiruShin backports the following upstream fixes from 7.1.2/7.2.1 without
raising the Flutter or Dart toolchain floor:

- Windows cold-start `initialLink`/`latestLink` initialization (`2a2dce8`).
- Bounded, same-executable `WM_COPYDATA` handling (`237357f`).
- Correct UTF-8 `COPYDATASTRUCT.cbData` sizing (`3b7e6be`).
- Removal of Android intent/URI debug logs (`c65c353`, `d1ec7f6`).

The Windows payload is additionally capped at MiruShin's 4096-byte external
activation limit (plus the terminating null byte). MiruShin also corrects the
upstream sender-handle plumbing so the executable check examines the forwarding
process rather than the receiving window.
