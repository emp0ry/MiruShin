#!/usr/bin/env python3
"""Generate an AltStore / SideStore / Feather / LiveContainer compatible source.

All four installers consume the AltStore "source" JSON format. This script
fetches every GitHub Release of the repo, picks the iOS `.ipa` asset out of
each, and emits a single source document (default: ``docs/source.json``) with a
full version history.

The whole document is rebuilt from the live Releases API on every run, so it is
idempotent: publishing, editing, or deleting a release and re-running always
produces a JSON that matches the current state of the Releases page.

Runs both locally (uses the public API; honours ``GITHUB_TOKEN`` if set) and in
CI (``GITHUB_TOKEN`` + ``GITHUB_REPOSITORY`` are provided by Actions).

Usage:
    python3 .github/scripts/gen-altstore-source.py [output_path]
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

# ---------------------------------------------------------------------------
# Static metadata - edit these to change how the source/app present in clients.
# ---------------------------------------------------------------------------

DEFAULT_REPO = "emp0ry/MiruShin"
# Branch the raw asset/icon URLs point at (icon, screenshots).
RAW_BRANCH = "main"

# Only assets whose filename matches this are treated as the iOS build.
IPA_NAME_RE = re.compile(r"\.ipa$", re.IGNORECASE)
# Pull the marketing version out of "MiruShin-ios-v1.7.0.ipa".
IPA_VERSION_RE = re.compile(r"-v(\d+(?:\.\d+){1,3})", re.IGNORECASE)

SOURCE = {
    "name": "MiruShin",
    "identifier": "com.emp0ry.mirushin.source",
    "subtitle": "New way to watch and discover media.",
    "description": (
        "Official AltStore / SideStore / Feather / LiveContainer source for "
        "MiruShin - a cross-platform anime streaming and player app."
    ),
    "website": "https://github.com/emp0ry/MiruShin",
    "tintColor": "8b5cf6",
}

APP = {
    "name": "MiruShin",
    "bundleIdentifier": "com.emp0ry.mirushin",
    "developerName": "emp0ry",
    "subtitle": "New way to watch and discover media.",
    "localizedDescription": (
        "MiruShin takes the familiar feel of AnimeShin and pushes it further "
        "with a cleaner Flutter architecture, real Sora module support, "
        "cross-platform playback, and deeper AniList profile flows. It can "
        "switch between TMDB-driven discovery and AniList-driven catalog views, "
        "then carry that context into your library, watch flow, and player.\n\n"
        "MiruShin is a media player and interface layer. It does not host or "
        "provide any content, and ships no built-in Sora modules."
    ),
    "tintColor": "8b5cf6",
    "category": "entertainment",
    "minOSVersion": "13.0",
    # App icon and screenshots are served straight from the repo via raw URLs.
    "iconURL": f"https://raw.githubusercontent.com/{DEFAULT_REPO}/{RAW_BRANCH}/assets/icons/logo.png",
    "screenshots": [
        f"https://raw.githubusercontent.com/{DEFAULT_REPO}/{RAW_BRANCH}/docs/assets/imgs/mobile_tmdb.png",
        f"https://raw.githubusercontent.com/{DEFAULT_REPO}/{RAW_BRANCH}/docs/assets/imgs/mobile_detail.png",
        f"https://raw.githubusercontent.com/{DEFAULT_REPO}/{RAW_BRANCH}/docs/assets/imgs/mobile_player.png",
    ],
    "appPermissions": {"entitlements": [], "privacy": []},
}


# ---------------------------------------------------------------------------
# GitHub API
# ---------------------------------------------------------------------------


def detect_repo() -> str:
    """owner/repo from the Actions env, else the git remote, else the default."""
    repo = os.environ.get("GITHUB_REPOSITORY")
    if repo:
        return repo
    try:
        url = subprocess.check_output(
            ["git", "config", "--get", "remote.origin.url"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", url)
        if m:
            return m.group(1)
    except Exception:
        pass
    return DEFAULT_REPO


def _next_link(headers) -> str | None:
    link = headers.get("Link")
    if not link:
        return None
    for part in link.split(","):
        m = re.search(r'<([^>]+)>;\s*rel="next"', part.strip())
        if m:
            return m.group(1)
    return None


def fetch_releases(repo: str) -> list[dict]:
    """Every release for the repo, following pagination.

    If ``RELEASES_JSON`` points at a file (e.g. the output of
    ``gh api repos/OWNER/REPO/releases``), it is used instead of calling the
    API - useful for offline regeneration and tests.
    """
    cached = os.environ.get("RELEASES_JSON")
    if cached:
        with open(cached, encoding="utf-8") as f:
            return json.load(f)

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "mirushin-altstore-source",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    url = f"https://api.github.com/repos/{repo}/releases?per_page=100"
    releases: list[dict] = []
    while url:
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req) as resp:
                releases.extend(json.load(resp))
                url = _next_link(resp.headers)
        except urllib.error.HTTPError as e:
            sys.exit(f"GitHub API error {e.code} for {url}: {e.read().decode(errors='replace')}")
    return releases


# ---------------------------------------------------------------------------
# Transform
# ---------------------------------------------------------------------------


def clean_notes(body: str | None, fallback: str) -> str:
    if not body:
        return fallback
    return body.replace("\r\n", "\n").replace("\r", "\n").strip().split("## What's New\n\n")[-1].split("\n\n<details>")[0] or fallback


def build_versions(releases: list[dict]) -> list[dict]:
    """One version entry per non-draft release that ships an iOS .ipa."""
    versions: list[dict] = []
    for rel in releases:
        if rel.get("draft"):
            continue
        ipa = next(
            (a for a in rel.get("assets", []) if IPA_NAME_RE.search(a.get("name", ""))),
            None,
        )
        if not ipa:
            continue

        m = IPA_VERSION_RE.search(ipa["name"])
        version = m.group(1) if m else (rel.get("tag_name", "") or "").lstrip("v")
        if not version:
            continue

        published = rel.get("published_at") or rel.get("created_at") or ""
        date = published[:10] if published else ""

        versions.append(
            {
                "version": version,
                "date": date,
                "localizedDescription": clean_notes(
                    rel.get("body"), f"{APP['name']} {version}"
                ),
                "downloadURL": ipa["browser_download_url"],
                "size": int(ipa.get("size", 0)),
                "minOSVersion": APP["minOSVersion"],
                "_sort": published,
            }
        )

    # Newest first: AltStore treats versions[0] as the installable latest.
    versions.sort(key=lambda v: v.pop("_sort"), reverse=True)
    return versions


def build_source(repo: str, releases: list[dict]) -> dict:
    versions = build_versions(releases)
    if not versions:
        sys.exit("No releases with an iOS .ipa asset were found; nothing to generate.")

    latest = versions[0]

    app = {
        "name": APP["name"],
        "bundleIdentifier": APP["bundleIdentifier"],
        "developerName": APP["developerName"],
        "subtitle": APP["subtitle"],
        "localizedDescription": APP["localizedDescription"],
        "iconURL": APP["iconURL"],
        "tintColor": APP["tintColor"],
        "category": APP["category"],
        "screenshots": APP["screenshots"],
        # Legacy v1 keys mirror the same screenshot list for older clients.
        "screenshotURLs": APP["screenshots"],
        "versions": versions,
        # Legacy top-level fields (pre-`versions` AltStore) point at the latest.
        "version": latest["version"],
        "versionDate": latest["date"],
        "versionDescription": latest["localizedDescription"],
        "downloadURL": latest["downloadURL"],
        "size": latest["size"],
        "minOSVersion": APP["minOSVersion"],
        "appPermissions": APP["appPermissions"],
    }

    return {
        "name": SOURCE["name"],
        "identifier": SOURCE["identifier"],
        "subtitle": SOURCE["subtitle"],
        "description": SOURCE["description"],
        "iconURL": APP["iconURL"],
        "website": SOURCE["website"],
        "tintColor": SOURCE["tintColor"],
        "featuredApps": [APP["bundleIdentifier"]],
        "apps": [app],
        "news": [],
    }


def main() -> None:
    out_path = sys.argv[1] if len(sys.argv) > 1 else "docs/source.json"
    repo = detect_repo()
    source = build_source(repo, fetch_releases(repo))

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(
        f"Wrote {out_path}: {len(source['apps'][0]['versions'])} version(s), "
        f"latest {source['apps'][0]['version']}"
    )


if __name__ == "__main__":
    main()
