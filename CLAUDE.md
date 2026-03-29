# NSS Dev Container — Host Project

This repo defines a reproducible, sandboxed dev container for working on
Mozilla NSS/NSPR with Claude Code. The container gives Claude a full C/C++
build environment it can explore and modify freely without affecting the host.

## Directory Layout

| Directory | Purpose | In container? |
|---|---|---|
| `.devcontainer/` | Dockerfile, devcontainer.json, post-create script | ro at `/workspaces/config/` |
| `container-claude/` | CLAUDE.md and `.claude/` skills/commands for use inside the container | rw at `/workspaces/nss-dev/.claude/` |
| `bugs/` | Bug context fetched from Bugzilla (not tracked in git) | rw at `/workspaces/nss-dev/bugs/` |
| `host-tools/` | Scripts that run on the host only (bz-fetch, envrc setup) | **no** |

## Host Tools

- `host-tools/bz-fetch.py <bug-id>` — fetch a Bugzilla bug (with comments, attachments, Phabricator diffs) into `bugs/bug-<id>/` as markdown for Claude to read inside the container.
- `host-tools/setup-envrc.sh` — interactively populate `.envrc` with API keys (`ANTHROPIC_API_KEY`, `BUGZILLA_API_KEY`, `PHABRICATOR_API_TOKEN`).

## Workflow

1. Run `host-tools/setup-envrc.sh` once to configure API keys.
2. Fetch bug context: `host-tools/bz-fetch.py 1234567`
3. Open the dev container. Claude Code is pre-installed and pre-configured inside.
4. Claude sees `CLAUDE.md` (via symlink), the `.claude/` commands directory, bug data in `bugs/`, and the full NSS/NSPR source — everything it needs to investigate and work on a bug.

## Design Principles

- **Reproducible** — the container is defined entirely by `.devcontainer/`; volumes persist NSS/NSPR source across rebuilds.
- **Sandboxed** — Claude operates in the container with full permissions but no access to the host filesystem beyond what is explicitly mounted.
- **Host/container separation** — tooling that talks to external APIs (Bugzilla, Phabricator) runs on the host; the container is purely a build/analysis environment.
