---
name: github-pr-ops
description: >-
  Use this skill when posting, editing, or managing GitHub PR comments and reviews.
  Triggers: post inline comments, post review, post general PR comment, edit a PR comment,
  list unresolved review threads, reply to review threads, post feedback on a PR.
---

# GitHub PR Operations

Shell script and conventions for operating on GitHub PRs from Claude Code.

**Script location:** `${CLAUDE_SKILL_DIR}/gh-pr.sh` — substituted when this skill loads, so the examples below are runnable as written. The script is not on `PATH`; invoke it by that full path, never as a bare `gh-pr.sh`.

All subcommands auto-detect the current PR from the working directory. Override with `--pr <number>`.

---

## Conventions

### Inline comments over general comments

Prefer inline comments attached to a specific file and line. Only use general PR comments for truly overarching concerns that aren't specific to any file or line (e.g., "this PR is missing a test strategy" or cross-cutting naming issues).

### Bundle inline comments into one review

Use `post-review` to create a single review containing all inline threads atomically. Do not create N separate single-thread reviews.

### Review events

- `COMMENT` (default) — General feedback, no approval signal
- `REQUEST_CHANGES` — Only when explicitly asked to block the PR
- `APPROVE` — Never without explicit user confirmation

### Line numbers

Inline comment `line` values are **absolute file line numbers in the HEAD version** (after changes), not diff hunk offsets. `side: RIGHT` (the default) refers to the head/post-change version. Use `side: LEFT` only when commenting on deleted lines.

---

## Subcommands

### `post-review` — Create a review with inline comments

```bash
"${CLAUDE_SKILL_DIR}/gh-pr.sh" post-review \
  [--event COMMENT|REQUEST_CHANGES] \
  [--body-file summary.md] \
  --threads threads.json
```

Write inline comment threads to a JSON file first:

```json
[
  {
    "body": "Comment with `inline code` and **markdown**",
    "path": "src/main.py",
    "line": 42
  },
  {
    "body": "Multi-line range comment",
    "path": "src/utils.py",
    "line": 10,
    "startLine": 8
  }
]
```

`side` defaults to `RIGHT`. Only specify `"side": "LEFT"` for deleted-line comments.

### `post-comment` — Post a general PR comment

```bash
"${CLAUDE_SKILL_DIR}/gh-pr.sh" post-comment --body-file comment.md
```

Only use for overarching concerns. See conventions above.

### `edit-comment` — Edit an existing comment

```bash
"${CLAUDE_SKILL_DIR}/gh-pr.sh" edit-comment --id IC_xxx... --body-file updated.md
```

Accepts `IC_` (general comment) or `PRRC_` (inline review comment) Node IDs. Auto-detects which mutation to use.

### `get-threads` — List unresolved review threads

```bash
"${CLAUDE_SKILL_DIR}/gh-pr.sh" get-threads
```

Returns each thread's Node ID (`PRRT_...`), file path and line, and full conversation (opening comment + all replies). Node IDs are needed to reply to and resolve threads.

**Threads vs comments:** A thread starts with one inline comment and may accumulate replies. The total comment count on a PR may exceed the thread count when threads have replies. `get-threads` always returns one entry per thread — read all replies to understand the current state of the request before acting, since the opening comment may have been refined or superseded by later replies.

---

## The Escaping Rule

**Never** pass markdown content through shell expansion (`$(...)`, heredocs, `-f body=`). Backticks and special characters get escaped and render as literal `\``.

**Always:**
1. Write the body to a temp file (e.g., `/tmp/comment.md`)
2. Pass the file to a script subcommand via `--body-file`

The scripts handle all JSON encoding internally via `jq --rawfile`.

---

## Replying to and resolving threads

Reply and resolve in one atomic request, using the thread's `PRRT_...` Node ID from `get-threads`:

```bash
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) { comment { id } }
  resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } }
}' -f threadId="PRRT_..." -f body="Done. Switched to a parameterized query."
```

Keep replies short and name the specific change.

---

## Getting a comment's Node ID

If you only have a REST API comment ID (integer), get the Node ID:

```bash
# General PR/issue comment
gh api repos/OWNER/REPO/issues/comments/REST_ID --jq '.node_id'

# Inline review comment
gh api repos/OWNER/REPO/pulls/PR_NUM/comments/REST_ID --jq '.node_id'
```
