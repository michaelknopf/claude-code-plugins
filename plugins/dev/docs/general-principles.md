# General Coding Principles

## Workflow

- **Never commit or push directly to `main`.** If you make changes with main checked out, create a new branch before committing.
- **Make every change in a worktree, on a branch — never in the primary clone.** This applies to any change that modifies files, however small; read-only work (investigating, running tests) can happen in the primary clone. Create one from the primary clone with `git worktree add .worktrees/<branch> -b <branch>`, make sure `.worktrees/` is git-ignored, and run the project's setup in it (`uv sync`, `pnpm install`, copying untracked local config, etc.), since a fresh worktree has none of it. Remove it with `git worktree remove <path>` when done; `git worktree list` recovers paths.
- **Do not leave deprecated code behind.** We don't need it for backwards compatibility or for future reference. Delete it and update consumers to use the updated implementation.
- **Merge with `gh pr merge --squash`, then clean up locally.** Do *not* pass `--delete-branch`: it makes `gh` try to check out the default branch locally, which fails because the primary clone already holds it (`fatal: 'main' is already used by worktree`). The merge itself still lands, but `gh` exits non-zero and skips its cleanup — so the error looks like a failed merge and isn't one. Skip the flag, then remove the worktree and delete the merged branch yourself.
- When creating PRs, do NOT add a "Test plan" section.
- Never run write operations against cloud infrastructure without explicit permission from the user!
- Comments are a liability, not a default. Write one only when it carries a *why* the code cannot, then keep it as short as possible. See `comment-principles.md`.

## Design & Style

- Prefer object-oriented patterns over module-level functions and global variables. Closures with bound state are acceptable as a lightweight alternative to single-method classes.
- Composition over inheritance.
- Don't create wrapper methods that add abstraction without providing value (e.g., simplifying the interface, adding logic, or improving clarity). However, sometimes wrapper methods are necessary for intentional indirection, like "controllers → services → data access."
- Keep components small and focused on one topic and one level of abstraction. Decompose large components (files/classes/functions etc.) into standalone, self-sufficient components that work together.
- **Levels of abstraction:** Structure code in hierarchical layers where high-level functions orchestrate by calling lower-level functions, which may in turn call even lower-level functions. Each function should operate at a single level of abstraction - don't mix high-level orchestration with low-level implementation details in the same function. If a function needs to perform a low-level operation, delegate it to a helper method or collaborator class. This creates code that reads like a summary at the top level, where you can drill down into details as needed.
- Deeply nested indentation is a sign of poor abstraction. Find ways to break the code up into smaller functions.
- Use strict types and generic types whenever possible.
- Do not "deconstruct" objects into local variables unless the full expression referencing the attr is long and/or repeated often. For example, just use `obj.attr` instead of creating `attr = obj.attr`, unless it's necessary for readability or performance.
