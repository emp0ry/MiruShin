#!/usr/bin/env python3
"""Build the next MiruShin release body from the latest published release."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


WHATS_NEW_HEADING = re.compile(
    r"^##[ \t]+What's[ \t]+New[ \t]*$", re.IGNORECASE | re.MULTILINE
)
PREVIOUS_DETAILS = re.compile(
    r"<details\b[^>]*>\s*"
    r"<summary\b[^>]*>.*?Previous[ \t]+Changelog.*?</summary>"
    r"(?P<history>.*?)"
    r"</details>",
    re.IGNORECASE | re.DOTALL,
)
NEXT_SECTION = re.compile(r"^##[ \t]+", re.MULTILINE)


def normalize_bullets(value: str, label: str) -> str:
    """Normalize workflow text and require a non-empty Markdown bullet list."""
    text = value.replace("\r\n", "\n").replace("\r", "\n").strip()
    # GitHub has no multiline workflow_dispatch input type. Accept literal \n
    # and also recover bullets pasted into a UI that collapses line breaks.
    text = text.replace(r"\n", "\n")
    if "\n" not in text:
        text = re.sub(r"[ \t]+(?=-[ \t]+)", "\n", text)

    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        raise ValueError(f"{label} is empty")
    invalid = [line for line in lines if not re.match(r"^-[ \t]+\S", line)]
    if invalid:
        raise ValueError(
            f"{label} must contain only Markdown bullets beginning with '- ': "
            + repr(invalid[0])
        )
    return "\n".join(lines)


def without_version(history: str, tag: str) -> str:
    """Remove an existing copy of a version section before prepending it."""
    section = re.compile(
        rf"^###[ \t]+{re.escape(tag)}[ \t]*$.*?(?=^###[ \t]+|\Z)",
        re.IGNORECASE | re.MULTILINE | re.DOTALL,
    )
    return section.sub("", history).strip()


def build_release_body(latest_body: str, previous_tag: str, whats_new: str) -> str:
    body = latest_body.replace("\r\n", "\n").replace("\r", "\n").strip()
    heading = WHATS_NEW_HEADING.search(body)
    if heading is None:
        raise ValueError("latest release body has no '## What's New' section")

    details = PREVIOUS_DETAILS.search(body, heading.end())
    next_section = NEXT_SECTION.search(body, heading.end())
    if details is not None and (
        next_section is None or details.start() < next_section.start()
    ):
        current_end = details.start()
        old_history = details.group("history").strip()
        trailing = body[details.end() :].strip()
    else:
        current_end = next_section.start() if next_section is not None else len(body)
        old_history = ""
        trailing = body[current_end:].strip()

    introduction = body[: heading.start()].strip()
    current_notes = normalize_bullets(
        body[heading.end() : current_end], "latest release What's New"
    )
    new_notes = normalize_bullets(whats_new, "whats_new input")

    previous_tag = previous_tag.strip()
    if not previous_tag:
        raise ValueError("previous release tag is empty")
    history_tail = without_version(old_history, previous_tag)
    history = f"### {previous_tag}\n\n{current_notes}"
    if history_tail:
        history += f"\n\n{history_tail}"

    sections = [
        introduction,
        f"## What's New\n\n{new_notes}",
        "<details>\n\n"
        "<summary><h2>Previous Changelog</h2></summary>\n\n"
        f"{history}\n\n"
        "</details>",
    ]
    if trailing:
        sections.append(trailing)
    return "\n\n".join(section for section in sections if section).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--latest-body", type=Path, required=True)
    parser.add_argument("--previous-tag", required=True)
    parser.add_argument("--whats-new", required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = build_release_body(
        args.latest_body.read_text(encoding="utf-8"),
        args.previous_tag,
        args.whats_new,
    )
    args.output.write_text(result, encoding="utf-8")
    print(f"Wrote {args.output} for the release after {args.previous_tag}")


if __name__ == "__main__":
    main()
