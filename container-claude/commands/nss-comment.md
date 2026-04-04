---
name: nss-comment
description: Generate a proposed Bugzilla comment for a security bug. Reads all reports, existing Bugzilla comments, the LOG, and worktree state, then drafts a terse comment cataloguing new insights and progress. Use when the user says "/nss-comment BUGNUM" or similar.
version: 1.0.0
---

# NSS Bug Comment

Generate a proposed Bugzilla comment for: $ARGUMENTS

Follow each phase below in order. Be terse throughout — this is a comment-drafting tool, not an analysis tool. If anything is ambiguous or unclear, **stop and ask the user** before continuing.

**Before starting**, record the wall-clock start time:
```sh
date -u +%s
```

---

## Phase 0: Read the Bug

### 0a. Parse arguments

Parse `$ARGUMENTS` to extract a bug number. Accepted forms: `1234567`, `bug-1234567`, `bug 1234567`. If `$ARGUMENTS` is empty, use the latest folder under `/workspaces/nss-dev/bugs/` sorted by name.

Set `BUGNUM` to the bug number.

### 0b. Locate the bug folder

```sh
BUG_DIR=$(ls -d /workspaces/nss-dev/bugs/*${BUGNUM}*/ 2>/dev/null | head -1)
```

If no match is found, **stop and ask the user** to fetch the bug data first.

### 0c. Check for existing proposed comments

```sh
ls "$BUG_DIR/proposed-comments.md" 2>/dev/null
```

If `proposed-comments.md` already exists, read it in full and **ask the user** whether they want to remove it before proceeding. If they say yes, delete it and continue as if it didn't exist. If they say no, **stop** — do not overwrite or append without explicit permission. The new comment will always be written as the sole content of `proposed-comments.md`, replacing any previous version.

---

## Phase 1: Gather All Context

Read all of the following. Do this yourself — do NOT delegate to subagents.

### 1a. Bug input

- `$BUG_DIR/input/bug.md` — bug metadata (title, severity, status, priority)
- `$BUG_DIR/input/comments.md` — all existing Bugzilla comments (the conversation so far)
- All files in `$BUG_DIR/input/attachments/` — patches, test cases, crash logs

### 1b. Reports

Read every file in `$BUG_DIR/reports/`:
```sh
ls "$BUG_DIR/reports/" 2>/dev/null
```

Read each report in full. These contain the analysis, triage, bugfix, review, and other findings that the comment should draw from.

### 1c. Activity log

Read `$BUG_DIR/LOG.md` in full. This is the chronological record of all work done on the bug.

### 1d. Previously proposed comments

If `proposed-comments.md` existed and the user chose to keep it in 0c, you should have stopped. If the user chose to remove it, it's gone — proceed without it.

### 1e. Worktree and branch state

Check for worktrees and exchange branches related to this bug:

```sh
# Active worktrees
git -C /workspaces/nss-dev/nss worktree list 2>/dev/null | grep -i "$BUGNUM"

# Exchange branches
git -C /workspaces/nss-dev/.nss-exchange.git branch --list "*${BUGNUM}*" 2>/dev/null
```

If a worktree exists, check its branch and recent commits:
```sh
# Substitute the actual worktree path from the previous output
cd <worktree-path>
git log --oneline -10
git diff --stat HEAD
```

If an exchange branch exists, check what it contains:
```sh
git -C /workspaces/nss-dev/.nss-exchange.git log --oneline -10 <branch-name>
```

---

## Phase 2: Determine What's New

Compare the existing Bugzilla comments (`input/comments.md`) against the reports, log, and worktree state. Identify what information is **new** — i.e., not already present in the Bugzilla thread.

New information typically falls into these categories:

1. **Triage findings** — confirmed severity, exploitability assessment, attack surface analysis
2. **Root cause analysis** — if deeper than what the original report provided
3. **Fix status** — a patch exists, what it does, test results
4. **Review results** — patch was reviewed, sanitizer results, fuzzing results
5. **Systemic findings** — related patterns found elsewhere in the codebase
6. **Scope refinements** — narrowing or widening the attack surface, correcting earlier assessments

If there is **nothing new** beyond what the Bugzilla thread already contains, **stop and tell the user** there is nothing to comment on.

---

## Phase 3: Ask for Clarification if Needed

Before drafting, check for ambiguity:

- If the triage and bugfix reports disagree on severity or root cause, **ask the user** which is correct.
- If it's unclear whether a fix has been finalized or is still in progress, **ask the user**.
- If the LOG.md contains entries that suggest the user has opinions or corrections not reflected in reports, **ask the user** what they want included.
- If you're unsure what level of detail is appropriate (e.g., whether to include specific code references), **ask the user**.

If nothing is ambiguous, proceed directly to Phase 4.

---

## Phase 4: Draft the Comment

Write a Bugzilla comment that is:

- **Terse.** Bugzilla security bug comments should be concise and to the point. No preamble, no filler.
- **Structured.** Use short labeled sections only where they aid clarity. Don't over-structure a comment that's only a few sentences.
- **Factual.** State findings, not opinions. Cite specific functions, files, and line numbers where relevant.
- **Incremental.** Only cover what's new since the last Bugzilla comment. Don't restate the bug report or prior analysis.
- **Appropriate for the audience.** Mozilla security engineers who know NSS. Don't explain what ASAN is or how TLS works.

### Comment structure guidelines

For a **triage-only** update (no fix yet):
- Confirmed severity and why (one sentence)
- Key findings that refine the original report (attack surface, exploitability constraints, affected configurations)
- Any scope changes (wider or narrower than initially reported)

For a **fix available** update:
- One-line summary of the fix approach
- Test results (gtests pass, sanitizer-clean, fuzzing results if available)
- Branch name where the patch lives
- Any caveats or follow-up needed

For a **combined triage + fix** update:
- Brief severity confirmation
- Fix summary
- Test results
- Branch name

### Tone

Match the tone of existing comments in `input/comments.md`. Typically direct and technical. No greetings, no sign-offs, no pleasantries. If existing comments use a particular style (e.g., bullet points vs. prose), match it.

---

## Phase 5: Write Output

### 5a. Write the proposed comment

Write to `$BUG_DIR/proposed-comments.md`, replacing any existing content (the user already approved removal in Phase 0c if the file existed).

Format:

```markdown
# Proposed Comment for Bug NNNNNN

<the drafted comment text, exactly as it should be posted to Bugzilla>
```

### 5b. Present the comment for review

After writing the file, display the full text of the proposed comment to the user. Tell them:
- The file path where it was saved
- That they should review and edit before posting to Bugzilla
- If there are any caveats or things you were uncertain about, flag them explicitly

### 5c. Update the log

Append a one-line entry to `$BUG_DIR/LOG.md`:

```
- YYYY-MM-DD HH:MM UTC — /nss-comment: drafted proposed Bugzilla comment (<brief description of what the comment covers>)
```

Use `date -u` for the timestamp:
```sh
NOW=$(date -u +"%Y-%m-%d %H:%M UTC")
echo "- $NOW — /nss-comment: drafted proposed Bugzilla comment (<brief description>)" >> "$BUG_DIR/LOG.md"
```

---

## Notes

- This command is **read-only with respect to code**. It does not modify any source files or worktrees. It only writes to `proposed-comments.md` and appends to `LOG.md`.
- If the user asks for changes to the drafted comment, edit `proposed-comments.md` directly and show the updated version.
- The comment is **not posted automatically**. The user will review it and post it manually to Bugzilla.
