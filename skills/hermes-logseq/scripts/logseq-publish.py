#!/usr/bin/env python3
"""Write a page to the mxjxn-logseq-notes graph and push to GitHub.

Usage:
  python3 logseq-publish.py --title "2026-07-07 - Cryptoart Report" --tags "#farcaster #cryptoart" --content "Body content here..."
  echo "content" | python3 logseq-publish.py --title "2026-07-07 - Job Search" --tags "#jobs"

The script:
1. Pulls latest from GitHub (captures your desktop writes)
2. Creates/overwrites the page in /pages/
3. Commits and pushes

Set LOGSEQ_NOTES_DIR env var to override default (/root/mxjxn-logseq-notes).
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

NOTES_DIR = os.environ.get("LOGSEQ_NOTES_DIR", os.path.expanduser("~/mxjxn-logseq-notes"))
PAGES_DIR = os.path.join(NOTES_DIR, "pages")
COMMIT_AUTHOR = "Hermes Agent <hermes@mxjxn.com>"


def git(*args, check=True, capture=True):
    """Run a git command in the notes directory."""
    result = subprocess.run(
        ["git", "-C", NOTES_DIR] + list(args),
        capture_output=True,
        text=True,
        check=False,
    )
    if check and result.returncode != 0:
        print(f"[logseq-publish] git error: {' '.join(args)}\n{result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result


def build_page(title: str, content: str, tags: str, published: bool = True) -> str:
    """Build a Logseq markdown page with YAML frontmatter and tab-indented blocks.

    Logseq formatting rules (learned from user's edits):
    - Page properties: YAML frontmatter with --- delimiters
    - Top-level content blocks: \\- (escaped dash so Logseq renders as bullet, not property)
    - Child blocks: \\t- (tab + dash)
    - Grandchild blocks: \\t\\t- (double tab + dash)
    - Great-grandchild: \\t\\t\\t- etc.
    - Hashtags go at the END of each block line: text here #tag1 #tag2
    - Page references use [[brackets]] inline
    - Empty lines between sections use a lone \\- (empty bullet)
    - Do NOT use spaces for indentation — only tabs
    """
    lines = []
    # YAML frontmatter — Logseq only keeps title here; tags go in content blocks
    lines.append("---")
    lines.append(f"title: {title}")
    lines.append("---")
    lines.append("")
    # Content: preserve tab indentation from input
    if content.strip():
        for raw_line in content.strip().split("\n"):
            if raw_line.strip() == "":
                lines.append("-")
                continue
            # Count leading tabs to determine indent level
            stripped = raw_line.lstrip("\t")
            tab_count = len(raw_line) - len(stripped)
            # Build the prefix: escaped dash at top level, plain dash for children
            if tab_count == 0:
                prefix = "- "
            else:
                prefix = "\t" * tab_count + "- "
            # Strip leading spaces/tabs from content part, preserve the rest
            lines.append(prefix + stripped.strip())
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Publish a page to Logseq graph")
    parser.add_argument("--title", required=True, help="Page title (e.g. '2026-07-07 - Cryptoart Report')")
    parser.add_argument("--tags", default="", help="Space-separated tags (e.g. '#farcaster #cryptoart')")
    parser.add_argument("--no-publish", action="store_true", help="Set published: false")
    parser.add_argument("--content", default=None, help="Page body content")
    args = parser.parse_args()

    # Read content from stdin if not provided via --content
    content = args.content
    if content is None:
        if not sys.stdin.isatty():
            content = sys.stdin.read()
        else:
            content = ""

    # Validate notes dir
    if not os.path.isdir(NOTES_DIR):
        print(f"[logseq-publish] Error: {NOTES_DIR} is not a directory", file=sys.stderr)
        sys.exit(1)

    # Build page content
    page = build_page(args.title, content, args.tags, published=not args.no_publish)

    # Ensure pages dir exists
    os.makedirs(PAGES_DIR, exist_ok=True)

    # Write page
    safe_filename = args.title.replace("/", "___") + ".md"
    filepath = os.path.join(PAGES_DIR, safe_filename)
    with open(filepath, "w") as f:
        f.write(page)

    # Git: pull first to get any desktop changes
    git("pull", "--rebase", check=False)  # Don't fail if no remote changes

    # Git: add, commit, push
    git("add", "-A")
    # Check if there are changes to commit
    status = git("status", "--porcelain")
    if not status.stdout.strip():
        print(f"[logseq-publish] No changes to commit for '{args.title}'")
        return

    git("commit", "--author", COMMIT_AUTHOR, "-m", f"logseq: {args.title}")
    git("push")

    print(f"[logseq-publish] Published: {safe_filename}")


if __name__ == "__main__":
    main()
