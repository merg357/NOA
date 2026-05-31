#!/usr/bin/env python3
"""
Prepare a Google Play tester email-list CSV.

Google Play Console accepts CSV uploads for email-list testers, but the Android
Publisher API testers resource only supports Google Groups. This helper covers
the no-Workspace fallback: give it real tester Google Account emails and it
writes the one-email-per-line, no-BOM CSV Play Console expects.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


EMAIL_RE = re.compile(r"^[^@\s,]+@[^@\s,]+\.[^@\s,]+$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a Play Console tester email CSV.")
    parser.add_argument("emails", nargs="*", help="Tester email addresses.")
    parser.add_argument("--input", help="Optional file with emails separated by newlines, commas, spaces, or semicolons.")
    parser.add_argument("--output", default="google-play-testers.csv", help="Output CSV path.")
    parser.add_argument("--min-count", type=int, default=12, help="Minimum tester count to enforce.")
    return parser.parse_args()


def split_emails(raw: str) -> list[str]:
    return [item.strip() for item in re.split(r"[\s,;]+", raw) if item.strip()]


def main() -> None:
    args = parse_args()
    emails: list[str] = []

    if args.input:
        emails.extend(split_emails(Path(args.input).read_text(errors="ignore")))
    emails.extend(args.emails)

    normalized: list[str] = []
    seen: set[str] = set()
    bad: list[str] = []
    for email in emails:
        value = email.strip().lower()
        if not value:
            continue
        if not EMAIL_RE.match(value):
            bad.append(email)
            continue
        if value not in seen:
            seen.add(value)
            normalized.append(value)

    if bad:
        print("ERROR: Invalid email addresses:", file=sys.stderr)
        for email in bad:
            print(f"  - {email}", file=sys.stderr)
        sys.exit(1)

    if len(normalized) < args.min_count:
        print(
            f"ERROR: Need at least {args.min_count} tester emails; got {len(normalized)}.",
            file=sys.stderr,
        )
        print("Use 15+ to leave room for opt-out or inactive testers.", file=sys.stderr)
        sys.exit(1)

    output = Path(args.output)
    output.write_text("\n".join(normalized) + "\n", encoding="utf-8")
    print(f"Wrote {len(normalized)} tester emails to {output}")
    print("Format: one email per line, no commas, UTF-8 without BOM.")


if __name__ == "__main__":
    main()
