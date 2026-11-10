# Fix loop: run a command and fix it until it passes

**Command to run (verbatim):** `<COMMAND>`

## Your Role

You orchestrate an autonomous Opus→Sonnet loop to diagnose and fix failures until the command succeeds or becomes blocked. Each iteration is visible to the user so they can follow along.

## Agent Selection

This loop uses different diagnostic agents based on the type of error:

| Error Type | Agent                   | Why |
|------------|-------------------------|-----|
| Type errors (mypy, pyright) | `dev:type-fix-planner` | Applies type safety principles |
| All other errors | `dev:fix-diagnostician`     | General-purpose debugging |

**Type error detection patterns:**
- Command contains: `mypy`, `pyright`, `--strict`, `--check`
- Output contains: `error:` with type-related messages like `Incompatible`, `has no attribute`, `Missing return`, `Argument of type`

## Execution Steps

### 1. Initial Run

Run the command exactly as provided:
```bash
<COMMAND>
```

If exit code is 0 → success, you're done. Otherwise, proceed to the fix loop.

### 2. Fix Loop (max 10 attempts)

For each attempt (1 through 10):

#### A. Diagnose (with agent selection)

**Detect if this is a type error:**

Check the error output for patterns indicating type errors:
- Command (`<COMMAND>`) contains: `mypy`, `pyright`, `--strict`, `--check`
- Error output contains: `error:` with type-related messages like `Incompatible`, `has no attribute`, `Missing return`, `Argument of type`

**Select the appropriate diagnostician:**

- **Type errors detected** → Spawn `dev:type-fix-planner` agent (opus) - applies type safety principles
- **Other errors** → Spawn `dev:fix-diagnostician` agent (opus) - general debugging

**Inputs to pass to the selected agent:**
- Target command: `<COMMAND>`
- Error output: Full output from the failed command
- Attempt number: Current iteration (1-indexed)
- Attempt history: Summary of previous attempts and what was tried

Both agents return a structured plan with these sections:
- `### Root Cause` (type-fix-planner also includes `### Principles Applied`)
- `### Fix Plan`
- `### Status` — either `CONTINUE` or `BLOCKED: <reason>`
- `### Blockers` (if any)

**CRITICAL: Output the full diagnosis plan verbatim.** After receiving the Task result, you MUST include the complete plan text in your next response message — this is how the user sees it. Do not summarize, truncate, or skip any part of the plan. Format it as:

```
---
## Attempt {N} / 10: Diagnosis

{full opus plan output}
---
```

#### B. Check for Blockers

Parse the `### Status` section from the opus plan:
- If `BLOCKED: <reason>` → stop the loop, report the blocker to the user
- If `CONTINUE` → proceed to implementation

#### C. Implement Fixes with Sonnet

Spawn a sonnet implementation agent (use `Task` tool with `subagent_type: "general-purpose"`, `model: "sonnet"`) with the full opus plan. The agent should:
- Read the relevant files
- Apply the changes described in the `### Fix Plan` section
- Not run the command (you'll do that next)

#### D. Re-run the Command

Run `<COMMAND>` again with Bash.

- If exit code 0 → success! Break out of the loop.
- If still failing → record this attempt in the history and continue to next iteration

#### E. Track Attempt

Record:
- Attempt number
- What was diagnosed (root cause summary)
- What was changed (brief summary of fixes applied)
- New error output (if still failing)

If you've reached 10 attempts, stop.

### 3. Report Summary

After the loop completes (success, blocked, or max attempts), report:

**On Success:**
- Number of attempts needed
- Summary of all fixes applied across all attempts
- Any follow-up recommendations (tests to add, refactoring, etc.)

**On Blocked:**
- Why it's blocked (from opus diagnosis)
- What needs to happen to unblock
- Summary of what was tried

**On Max Attempts:**
- Final error output
- Summary of all attempts and what was tried
- Highest-leverage next steps to investigate

## Guidelines

- **Output each opus plan verbatim in your response** — the user can ONLY see the plan if you include the full text in your message. Never summarize, truncate, or omit any section. This is the primary value of this loop.
- **Don't wait for approval** — the loop runs autonomously unless the user interrupts.
- **Track attempts carefully** — avoid repeating the same failed approach.
- **Be concise in summaries** — focus on what changed and what matters next.
- **Stop early if blocked** — don't waste attempts on something that needs external action.

## Example Flow

```
Running command: npm run build

Command failed with exit code 1.

---
## Attempt 1 / 10: Diagnosis

### Root Cause
...opus diagnosis...

### Fix Plan
1. ...
2. ...

### Status
CONTINUE
---

Implementing fixes...

Running command: npm run build

Command failed with exit code 1.

---
## Attempt 2 / 10: Diagnosis

### Root Cause
...opus diagnosis...

### Fix Plan
1. ...

### Status
CONTINUE
---

Implementing fixes...

Running command: npm run build

Success! The command passed on attempt 2.

Summary:
- Attempt 1: Fixed type error in UserService
- Attempt 2: Added missing import in AuthMiddleware

Follow-up recommendations:
- Add unit tests for the error handling path in AuthMiddleware
```
