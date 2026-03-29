#!/usr/bin/env python3
"""
Fetch a Mozilla Bugzilla bug (with comments and attachments) and write it
to a directory of markdown files suitable for feeding into an LLM.

Usage:
    bz-fetch.py <bug-number> [output-dir]

Environment:
    BUGZILLA_API_KEY      — Bugzilla API key (optional but recommended to avoid rate limits)
    PHABRICATOR_API_TOKEN — Phabricator Conduit token, required for non-public revisions
                            Obtain from: https://phabricator.services.mozilla.com/settings/panel/apitokens/
"""

import base64
import json
import os
import re
import sys
import textwrap
import urllib.request
import urllib.parse
from datetime import datetime
from pathlib import Path

BASE_URL = "https://bugzilla.mozilla.org/rest"
PHAB_BASE = "https://phabricator.services.mozilla.com"
PHAB_RE = re.compile(r"https://phabricator\.services\.mozilla\.com/(D\d+)")


def api_get(path: str, params: dict = None) -> dict:
    api_key = os.environ.get("BUGZILLA_API_KEY")
    query = params or {}
    if api_key:
        query["api_key"] = api_key
    url = f"{BASE_URL}{path}"
    if query:
        url += "?" + urllib.parse.urlencode(query)
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def fmt_date(iso: str) -> str:
    """Trim timezone noise for readability."""
    return iso.replace("T", " ").replace("Z", " UTC").rstrip()


def write_bug_md(bug: dict, out_dir: Path) -> None:
    flags = bug.get("flags", [])
    flag_lines = "\n".join(
        f"  - {f['name']}: {f['status']} (set by {f['setter']})"
        for f in flags
    ) or "  (none)"

    keywords = ", ".join(bug.get("keywords", [])) or "(none)"
    blocks = ", ".join(str(b) for b in bug.get("blocks", [])) or "(none)"
    depends = ", ".join(str(d) for d in bug.get("depends_on", [])) or "(none)"
    see_also = "\n".join(f"  - {u}" for u in bug.get("see_also", [])) or "  (none)"

    text = f"""\
# Bug {bug['id']}: {bug['summary']}

**URL:** https://bugzilla.mozilla.org/show_bug.cgi?id={bug['id']}

## Metadata

| Field         | Value |
|---------------|-------|
| Status        | {bug['status']} {bug.get('resolution', '').strip()} |
| Priority      | {bug.get('priority', '—')} |
| Severity      | {bug.get('severity', '—')} |
| Product       | {bug['product']} |
| Component     | {bug['component']} |
| Version       | {bug.get('version', '—')} |
| Platform      | {bug.get('platform', '—')} |
| OS            | {bug.get('op_sys', '—')} |
| Reporter      | {bug['creator']} |
| Assigned to   | {bug.get('assigned_to', '—')} |
| QA contact    | {bug.get('qa_contact', '—')} |
| Created       | {fmt_date(bug['creation_time'])} |
| Last modified | {fmt_date(bug['last_change_time'])} |
| Keywords      | {keywords} |
| Blocks        | {blocks} |
| Depends on    | {depends} |

## Flags

{flag_lines}

## See Also

{see_also}

## Whiteboard

{bug.get('whiteboard', '').strip() or '(empty)'}
"""
    (out_dir / "bug.md").write_text(text)


def write_comments_md(comments: list, out_dir: Path) -> None:
    parts = [f"# Comments for Bug {comments[0]['bug_id']}\n" if comments else "# Comments\n"]
    for c in comments:
        author = c["author"]
        when = fmt_date(c["creation_time"])
        num = c["count"]
        is_private = " *(private)*" if c.get("is_private") else ""
        header = f"## Comment {num} — {author} — {when}{is_private}"
        body = c["text"].strip() or "*(no text)*"
        parts.append(f"{header}\n\n{body}\n")
    (out_dir / "comments.md").write_text("\n---\n\n".join(parts))


TEXT_TYPES = {
    "text/plain", "text/x-patch", "text/x-diff", "application/x-patch",
    "application/json", "text/html", "text/css", "text/javascript",
    "application/xml", "text/xml",
}

def is_text(content_type: str) -> bool:
    base = content_type.split(";")[0].strip().lower()
    return base in TEXT_TYPES or base.startswith("text/")


def phab_conduit(method: str, params: dict) -> dict:
    """Call a Phabricator Conduit API method. Requires PHABRICATOR_API_TOKEN."""
    token = os.environ.get("PHABRICATOR_API_TOKEN")
    if not token:
        raise RuntimeError("PHABRICATOR_API_TOKEN not set")
    body = urllib.parse.urlencode({"api.token": token, "output": "json", **params})
    url = f"{PHAB_BASE}/api/{method}"
    req = urllib.request.Request(
        url, data=body.encode(), headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())
    if data.get("error_code"):
        raise RuntimeError(f"Conduit {method}: {data['error_code']} — {data['error_info']}")
    return data["result"]


def fetch_phabricator_diff(revision: str) -> str | None:
    """Fetch the raw diff for a Phabricator revision (e.g. 'D289979').

    Tries the unauthenticated ?download=true endpoint first. If that fails
    (e.g. non-public revision), falls back to the Conduit API using
    PHABRICATOR_API_TOKEN: diff.search to get the latest diffID, then
    getrawdiff to retrieve the content.
    """
    rev_id = int(revision[1:])  # strip leading 'D'

    # Fast path: public download endpoint (no auth needed)
    # Phabricator returns 200 with an HTML login page for non-public revisions,
    # so we must check the Content-Type to distinguish a real diff from a redirect.
    url = f"{PHAB_BASE}/{revision}?download=true"
    req = urllib.request.Request(url, headers={"Accept": "text/plain"})
    try:
        with urllib.request.urlopen(req) as resp:
            ctype = resp.headers.get("Content-Type", "")
            if resp.status == 200 and "text/plain" in ctype:
                return resp.read().decode("utf-8", errors="replace")
            # HTML response (login page) — fall through to Conduit path
    except urllib.error.HTTPError as e:
        if e.code not in (401, 403):
            print(f"  Warning: unexpected HTTP {e.code} fetching {revision}", file=sys.stderr)
            return None
        # Fall through to Conduit path
    except Exception as e:
        print(f"  Warning: could not fetch Phabricator diff for {revision}: {e}", file=sys.stderr)
        return None

    # Conduit path: resolve latest diffID then fetch raw content
    token = os.environ.get("PHABRICATOR_API_TOKEN")
    if not token:
        print(
            f"  Warning: {revision} requires authentication. "
            "Set PHABRICATOR_API_TOKEN to fetch non-public revisions.",
            file=sys.stderr,
        )
        return None

    try:
        # Resolve revision ID → PHID
        rev_result = phab_conduit("differential.revision.search", {
            "constraints[ids][0]": rev_id,
            "limit": "1",
        })
        revisions = rev_result.get("data", [])
        if not revisions:
            print(f"  Warning: revision {revision} not found", file=sys.stderr)
            return None
        rev_phid = revisions[0]["phid"]

        # Get the latest diff for this revision
        result = phab_conduit("differential.diff.search", {
            "constraints[revisionPHIDs][0]": rev_phid,
            "order": "newest",
            "limit": "1",
        })
        diffs = result.get("data", [])
        if not diffs:
            print(f"  Warning: no diffs found for {revision}", file=sys.stderr)
            return None
        diff_id = diffs[0]["id"]
        return phab_conduit("differential.getrawdiff", {"diffID": diff_id})
    except Exception as e:
        print(f"  Warning: Conduit fetch failed for {revision}: {e}", file=sys.stderr)
        return None


def write_attachments(attachments: list, out_dir: Path) -> None:
    att_dir = out_dir / "attachments"
    att_dir.mkdir(exist_ok=True)

    index_lines = [f"# Attachments for Bug {attachments[0]['bug_id']}\n" if attachments else "# Attachments\n"]

    for att in attachments:
        aid = att["id"]
        filename = att.get("file_name", f"attachment-{aid}")
        desc = att.get("description", "").strip()
        ctype = att.get("content_type", "application/octet-stream")
        size = att.get("size", 0)
        author = att.get("creator", "?")
        when = fmt_date(att.get("creation_time", ""))
        obsolete = " *(obsolete)*" if att.get("is_obsolete") else ""
        is_patch = att.get("is_patch", False)

        index_lines.append(
            f"## Attachment {aid}: {filename}{obsolete}\n\n"
            f"- **Description:** {desc or '(none)'}\n"
            f"- **Type:** {ctype}{'  *(patch)*' if is_patch else ''}\n"
            f"- **Size:** {size:,} bytes\n"
            f"- **Author:** {author}\n"
            f"- **Date:** {when}\n"
        )

        raw_data = att.get("data")
        if not raw_data:
            index_lines[-1] += "\n*(no data returned)*\n"
            continue

        try:
            decoded = base64.b64decode(raw_data)
        except Exception as e:
            index_lines[-1] += f"\n*(failed to decode: {e})*\n"
            continue

        # Phabricator revision link — fetch the actual diff
        if ctype == "text/x-phabricator-request":
            url_text = decoded.decode("utf-8", errors="replace").strip()
            m = PHAB_RE.search(url_text)
            if m:
                revision = m.group(1)
                index_lines[-1] += f"- **Phabricator:** {url_text}\n"
                print(f"  Fetching Phabricator diff {revision}...")
                diff = fetch_phabricator_diff(revision)
                if diff:
                    safe_name = re.sub(r"[^\w.\-]", "_", f"{revision}.diff")
                    out_path = att_dir / f"{aid}-{safe_name}"
                    out_path.write_text(diff)
                    index_lines[-1] += f"\n```diff\n{diff}\n```\n"
                else:
                    index_lines[-1] += "\n*(could not fetch diff)*\n"
            else:
                index_lines[-1] += f"\n*(unrecognised phabricator URL: {url_text})*\n"
            continue

        # Save raw file regardless
        safe_name = re.sub(r"[^\w.\-]", "_", filename)
        out_path = att_dir / f"{aid}-{safe_name}"
        out_path.write_bytes(decoded)

        if is_text(ctype) or is_patch:
            try:
                text_content = decoded.decode("utf-8", errors="replace")
                # Inline text content in the index
                fence = "diff" if is_patch or "patch" in ctype or "diff" in ctype else "text"
                index_lines[-1] += f"\n```{fence}\n{text_content}\n```\n"
            except Exception:
                index_lines[-1] += f"\n*saved to `attachments/{out_path.name}`*\n"
        else:
            index_lines[-1] += f"\n*binary file saved to `attachments/{out_path.name}`*\n"

    (att_dir / "index.md").write_text("\n---\n\n".join(index_lines))


def fetch_bug(bug_id: int, out_root: Path) -> None:
    print(f"Fetching bug {bug_id}...")

    bug_data = api_get(f"/bug/{bug_id}")
    if "bugs" not in bug_data or not bug_data["bugs"]:
        sys.exit(f"Error: bug {bug_id} not found")
    bug = bug_data["bugs"][0]

    comment_data = api_get(f"/bug/{bug_id}/comment")
    comments = comment_data.get("bugs", {}).get(str(bug_id), {}).get("comments", [])

    print(f"  {len(comments)} comment(s)")

    att_data = api_get(f"/bug/{bug_id}/attachment", {"include_fields": "_default,data"})
    attachments = att_data.get("bugs", {}).get(str(bug_id), [])
    print(f"  {len(attachments)} attachment(s)")

    out_dir = out_root / f"bug-{bug_id}"
    out_dir.mkdir(parents=True, exist_ok=True)

    write_bug_md(bug, out_dir)
    write_comments_md(comments, out_dir)
    if attachments:
        write_attachments(attachments, out_dir)

    print(f"Written to {out_dir}/")
    print(f"  bug.md, comments.md" + (", attachments/" if attachments else ""))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    try:
        bug_id = int(sys.argv[1])
    except ValueError:
        sys.exit(f"Error: '{sys.argv[1]}' is not a valid bug number")

    default_out = Path(__file__).resolve().parent.parent / "bugs"
    out_root = Path(sys.argv[2]) if len(sys.argv) > 2 else default_out
    fetch_bug(bug_id, out_root)


if __name__ == "__main__":
    main()
