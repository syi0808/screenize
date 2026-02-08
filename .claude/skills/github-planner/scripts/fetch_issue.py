# /// script
# requires-python = ">=3.10"
# ///
"""Fetch GitHub issue details using gh CLI and output structured JSON."""

import json
import re
import subprocess
import sys


def parse_issue_input(raw: str) -> tuple[str | None, str]:
    """Parse issue input into (repo, issue_number).

    Accepts:
      - https://github.com/owner/repo/issues/123
      - owner/repo#123
      - #123 or 123 (uses current repo)
    """
    raw = raw.strip()

    # Full URL
    url_match = re.match(
        r"https?://github\.com/([^/]+/[^/]+)/issues/(\d+)", raw
    )
    if url_match:
        return url_match.group(1), url_match.group(2)

    # owner/repo#number
    short_match = re.match(r"([^/]+/[^#]+)#(\d+)", raw)
    if short_match:
        return short_match.group(1), short_match.group(2)

    # Just a number, optionally with #
    num_match = re.match(r"#?(\d+)$", raw)
    if num_match:
        return None, num_match.group(1)

    print(f"Error: Cannot parse issue reference: {raw}", file=sys.stderr)
    sys.exit(1)


def fetch_issue(repo: str | None, number: str) -> dict:
    """Fetch issue details via gh CLI."""
    fields = "number,title,body,state,labels,assignees,milestone,createdAt,updatedAt,author,comments"

    cmd = ["gh", "issue", "view", number, "--json", fields]
    if repo:
        cmd.extend(["-R", repo])

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except FileNotFoundError:
        print("Error: gh CLI not found. Install from https://cli.github.com/", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error fetching issue: {e.stderr.strip()}", file=sys.stderr)
        sys.exit(1)

    return json.loads(result.stdout)


def format_output(data: dict) -> dict:
    """Format issue data for consumption."""
    labels = [lb["name"] for lb in data.get("labels", [])]
    comments = []
    for c in data.get("comments", []):
        comments.append({
            "author": c.get("author", {}).get("login", "unknown"),
            "body": c.get("body", ""),
            "createdAt": c.get("createdAt", ""),
        })

    return {
        "number": data["number"],
        "title": data["title"],
        "body": data.get("body", ""),
        "state": data.get("state", ""),
        "labels": labels,
        "author": data.get("author", {}).get("login", "unknown"),
        "assignees": [a["login"] for a in data.get("assignees", [])],
        "milestone": (data.get("milestone") or {}).get("title"),
        "createdAt": data.get("createdAt", ""),
        "updatedAt": data.get("updatedAt", ""),
        "comments": comments,
        "commentCount": len(comments),
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: fetch_issue.py <issue_url_or_number>", file=sys.stderr)
        print("Examples:", file=sys.stderr)
        print("  fetch_issue.py 123", file=sys.stderr)
        print("  fetch_issue.py https://github.com/owner/repo/issues/123", file=sys.stderr)
        print("  fetch_issue.py owner/repo#123", file=sys.stderr)
        sys.exit(1)

    repo, number = parse_issue_input(sys.argv[1])
    data = fetch_issue(repo, number)
    output = format_output(data)
    print(json.dumps(output, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
