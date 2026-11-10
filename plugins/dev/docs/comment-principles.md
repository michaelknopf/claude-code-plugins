# Comment & Docstring Principles

## The test

A comment exists to prevent a future reader from making a mistake or misunderstanding the code. But comments cost the reader time and risk adding noise, so they're not free. **If you can't name the specific mistake or misunderstanding the comment is there to prevent, do not write it.**

Name it concretely, to yourself, before you write: *a reader would delete this clause*, *a reader would assume this retries*, *a reader would call this before the lock is held*. If the answer is "it explains what's going on," there is no mistake, and the comment is costing the reader time to buy nothing.

Most code needs no comment. That is the expected outcome, not a gap.

## Write the conclusion, not the reasoning

When you work out a tricky piece of code, you generate a lot of explanation: alternatives weighed, consequences enumerated, ordering argued. That text is scaffolding for your own thinking. The reader needs the load-bearing fact — usually one or two sentences — not the derivation that produced it.

The tell is prose that reads like someone talking themselves through a decision: a `WHY we do it this way:` heading, a numbered list of reasons, a `Cost:` paragraph, an argument with an imagined objector. Whatever real fact is buried in there survives compression; the deliberation around it should come down before you finish, the way scaffolding comes down once the building stands.

```python
# 15 lines explaining why the cap is 2, walking through the provider's
# rate-limit window, how the client's backoff interacts with it, and the
# latency cost of each attempt...
MAX_RETRIES = 2
```

```python
# Retries count against the same rate-limit window, so a third attempt can only
# fail — and each one adds a second to a user-facing request.
MAX_RETRIES = 2
```

## Write from the reader's position, not the diff's

The reader has never seen the change you are making. They see one state of the code, with no before. So prose that points at the diff — *previously*, *used to*, *until now*, *this PR*, *now that we*, *is now* — names a mistake only the author could have made, and reads to everyone else as noise about a change nobody remembers.

Describe what is true, not what changed. `# The dispatcher's SELECT that read this was removed in this PR` becomes `# Dead column: no reader, no writer.` Git holds the history; the comment holds the state.

This is also the main way comments go stale. A comment anchored to a moment is wrong as soon as the moment passes, and nothing flags the drift.

## Don't restate the code

A comment that says what the next line plainly does makes a reader who understood the code stop and re-check whether they missed something. `# Initialize the database engine` above `db_engine = create_engine(...)` prevents nothing.

The same applies to docstring `Args:` blocks. A typed signature already tells the reader that `user_id: str` is the user's id. Document a parameter only when it carries a constraint or meaning the type cannot — a unit, a required ordering, a value the callee treats specially. Otherwise leave it out.

## Point at the source of truth; don't copy it

A comment that hardcodes an external value — a timeout, a queue's retry count, a vendor console setting — is wrong the moment someone changes it where it actually lives, and nothing will catch it. Name where the value lives instead of restating it, and keep the reasoning that made it matter.

The same holds for anything you reference. A pointer only helps if the reader can follow it: name the file, the doc path, or the ticket. `# See the "Retry Storms" investigation` and `# see trace <id>` name a mistake but withhold the means to avoid it, which leaves the reader worse off than silence.

If the same fact is explained in more than one place, the copies will disagree eventually. Explain it where it belongs and point at that.

**Prose about code in another module is the most likely thing you write to become false.** A comment describing the file it sits in gets corrected when that file changes. One describing a worker's behavior, a queue's type, an infrastructure value, or another service's auth posture does not — the code moves, the comment stays, and nothing fails. Prefer naming the thing precisely enough to grep over restating what it does, and when you must describe it, describe the contract you depend on rather than its implementation.

There are always going to be exceptions, so use your judgement. For example, if a list is an enumeration, it's understandable that every point won't be high value, but might be there for completeness.

## Docstrings

Same test, with two specifics.

**This is internal code, and the reader can always open the body.** So a docstring is not there to substitute for the implementation — it earns its place only when reading it beats reading the code: when the body is long or intricate enough that a one-line summary genuinely saves the trip, or when it states something the body cannot show, like a caller's obligation or a guarantee callers rely on. A short helper whose body is as quick to read as a description of it needs nothing. `public` versus `_private` is not the test; how much work the docstring actually saves is.

**A module docstring is an orientation, not a design memo.** One short paragraph on the module's job and how it fits. Architecture, protocols, and multi-paragraph rationale belong in the repo's docs; when a fitting doc exists, point at it rather than restating it.

## Calibration

These are defaults, not absolutes. A comment that prevents a production incident, a security hole, or data loss earns more room than one that prevents a moment of confusion — write what that costs.

Where the code is genuinely surprising and none of the above quite fits, use your judgment. The failure mode this document is correcting is far too much prose, so when you're unsure, the better guess is less.

## Reviewing your own work

Before you finish, reread every comment and docstring you added and ask: *is this comment valuable enough to justify its existence?* Cut the ones where the honest answer is no — including the ones that took effort to write.
