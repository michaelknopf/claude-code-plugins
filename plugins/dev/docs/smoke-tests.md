# TLDR
Smoke tests validate that a system works in a **realistic environment with real infrastructure** — the thing unit tests, running against mocks, structurally cannot check. Because they're slow and brittle, the governing rule is **less is more**: few tests, each indispensable, each covering a complete flow broadly but shallowly. Depth belongs to unit tests.

> A good smoke test:
> - Validates an **integration point or configuration** that can't be tested in isolation.
> - Covers a **complete flow or lifecycle**, not individual operations.
> - Uses the system's **external interfaces**, not implementation details.
> - Is **deterministic** and resilient to environmental variability.
> - **Cleans up defensively**, both before and after execution.
> - **Identifies itself** clearly to avoid polluting shared resources and metrics.

The measure of a good smoke suite is not comprehensiveness but **precision**.
## Glossary
- **Isolated deployment** — an ephemeral, unshared environment spun up by CI (per-PR or post-merge) solely for testing. Tests have freedom here: they can consume queues and mutate data without affecting anyone.
- **Live environment** — a permanent, shared deployment (staging/prod). Smoke tests here must be constrained: they share the environment with real traffic and must not interfere.
- **Conditional execution** — the practice of running some tests *only* in isolated deployments (e.g. queue-consuming tests) because they'd be destructive in a live one.
# Why smoke tests exist
Smoke tests occupy a distinct role in the testing pyramid. Unlike unit tests — which verify isolated components through mocked dependencies — smoke tests validate that a system functions correctly in a realistic environment with actual infrastructure. They serve two purposes unit tests cannot:
**1. Validating integration points.** When code depends on external components (databases, queues, third-party APIs, file systems), unit tests mock them. Mocks verify your code *would* behave correctly *if* the dependency behaved as expected. Smoke tests verify the **actual integration** works: connection strings are correct, auth is configured, serialization is compatible, and the contract between systems holds.

> **Example — database queries.** A unit test can mock the DB client and assert the right query string is built, but that tells you nothing about whether the query *works*. A smoke test runs the real query against the real database and validates: syntax is valid for the engine, referenced tables/columns/relationships exist, results match known test data, permissions are correct, and pooling/timeouts hold under realistic conditions. The same applies to Elasticsearch, Redis, S3 — anywhere behavior depends on the real implementation, not an interface contract.

**2. Guarding against misconfiguration.** Infrastructure can be provisioned wrong. Env vars can be missing. Feature flags can be in unexpected states. These failure modes exist *only* in deployed environments and can't be caught by unit tests against mocks. Smoke tests catch them before they reach users.
# Deployment contexts
Smoke tests run in two settings with different constraints:
<table>
<tr>
<td>Context</td>
<td>Constraints &amp; purpose</td>
</tr>
<tr>
<td>**Isolated test deployments** (per-PR / post-merge CI)</td>
<td>Ephemeral, unshared. Tests have freedom: consume from queues, write to databases, interact with infra without risk of interfering with production workloads. Purpose: verify the service deploys and passes sanity checks before merge/promotion.</td>
</tr>
<tr>
<td>**Live environments** (staging / prod)</td>
<td>Shared with real traffic. Tests must be constrained — they cannot take actions that interfere with normal operations. Purpose: verify the new deployment is configured correctly and integrates with real dependencies in its actual operating context.</td>
</tr>
</table>
**Conditional execution.** Because of this, some tests should run *only* in isolated deployments. A test that consumes from an output queue is fine in isolation, but in production it would **steal messages from the real consumer**. Design the suite with this split in mind: integration-validation tests may be isolated-only; configuration/health tests should run in both.
# Choosing where a test runs

A smoke suite runs at more than one gate: the isolated CI deployment on a labeled PR and on every post-merge run, then the live environments on promotion. **Which gates a test runs at is carried by the test itself**, as a marker. Nothing else decides it — CI passes a marker expression and pytest selects.

## How a run reaches each gate

The marker decides which tests a gate *selects*; CI mechanics decide whether the gate runs at all.

- **PR (isolated deployment):** only when the PR carries the repo's deploy label — usually `deploy`, but read the `if:` gates in the repo's CI workflow. The label must be on the PR **when the run triggers**: unless the `pull_request` trigger declares `types:` including `labeled`, that event doesn't fire it — adding the label afterwards starts nothing, and `gh run rerun` replays the original label-less payload. Right: `gh pr create --label deploy`. Recovery: close and reopen the PR, or push an empty commit to force a `synchronize`.
- **Post-merge:** automatic on merge to main.
- **Live environments:** the promotion pipeline deploys, then runs the live selection (typically `-m "live and external"`).

Green lies twice at these gates, so verify explicitly:

- **A skipped deploy job still reports the run as `success`.** A green PR check does not mean the deployed path was exercised — check the Deploy and Smoke jobs' conclusions, not the run's.
- **In a live environment's log, CI-only tests must appear as *deselected*, never as skips.** Deselected means the marker expression excluded them at collection. A wall of skips means everything was collected and only a runtime guard stood between the suite and the shared environment — the marker gate failed.

## The CI-only default has to be stated, not defaulted into

An unmarked smoke test runs in the isolated CI deployment and nowhere else. That is the right direction for a default: a test nobody classified never reaches a live environment.

It is also, from the outside, **indistinguishable from a test nobody thought about** — and a test that silently doesn't run reports nothing, forever. Green tells you nothing about it.

Staying unmarked is legitimate and common; most smoke tests should be CI-only. What you want is for that to be *visible* rather than inferred from an absence — for example, a small pytest hook that lists the unmarked smoke tests on every run, as a warning rather than a failure. (`--strict-markers`, which is always on, already catches a marker that is *misspelled*; this surfaces one that is *absent*.)

## The vocabulary

A useful set of four markers, registered in a shared pytest plugin or each repo's `conftest.py`. They are not a ladder — they are two independent axes plus a flag.

| marker | axis | meaning |
| --- | --- | --- |
| `live` | environment reach | Safe against a permanent shared deployment (staging/prod). **This is the promotion gate.** |
| `internal` | network path | Runs against internal, non-public surface — typically over a private network or tunnel. |
| `external` | network path | Runs against the public surface. In some repos this is set by a parametrized client fixture rather than written by hand. |
| `test_only` | flag | Exercises functionality that exists only for testing, so it can never run where those affordances are disabled. |

`internal` / `external` describe *how the test reaches the service*, not *where it is allowed to run*. Check what they already mean in the repo you are in before adding one — the convention is not identical everywhere.

## When a test earns `live`

Every one of these must hold. If you are unsure about any, leave it off — under-promotion costs a gap in coverage, over-promotion costs a broken shared environment.

- **Non-interfering.** It cannot consume, intercept, or mutate anything a real user or a downstream service depends on. Consuming from an output queue is the classic disqualifier: correct in isolation, message theft in production.
- **Self-cleaning, in both directions.** It removes what it created, and it also clears residue from a previous failed run before it starts.
- **Deterministic without test-only affordances.** No test headers, no bypass tokens, no emulator, no seeded fixture data.
- **Identifiable.** Data it creates is recognizable as test data, and its traffic is distinguishable in observability so it does not inflate metrics or trip alerts.
- **Bounded cost per run.** No unbounded agent loops, no metered third-party calls that scale with retries.

## What keeps a test at the CI gate

Any single one of these is enough. Mark it `test_only` where that is the reason; otherwise leave it unmarked once the repo requires an explicit decision elsewhere.

- Needs a test-only endpoint, header, or bypass.
- Needs an emulator or a local stand-in (LocalStack, a Firebase emulator, a container Postgres).
- Consumes from a shared queue, or writes state it cannot fully retract.
- Depends on sandbox credentials that only exist in the test environment.
- Asserts on internal state a deployed environment does not expose.

## Run an expensive test at exactly one gate

The rule that resolves most remaining cases: **a test belongs at the earliest gate that can catch the failure it is looking for, and only there.**

The gates are asking different questions. The isolated CI deployment asks *does this work end to end*. A live environment asks *is this deployment configured correctly and reachable*. A full workflow test that burns model tokens and touches six services answers the first question completely, and re-running it on promotion answers nothing new at triple the cost.

That is why a healthy live set skews toward health checks, auth rejection, CORS, and integration reachability, while workflow, attachment, and lifecycle suites stay at the CI gate. If a suite looks the same at every gate, the tiers are not doing any work.

# Designing effective smoke tests
## Test complete flows, not fragments
A well-designed smoke test validates an entire lifecycle. For a resource API, rather than separate create/read/update/delete tests, write **one** test that exercises the whole CRUD cycle:
1. Create the resource
2. Retrieve it to verify creation
3. Update it
4. Retrieve again to verify the update took effect
5. Delete it
6. Attempt retrieval to confirm deletion (expect a 404)
This validates that all operations work *together*, that state transitions behave, and that the system is properly configured — in a single test.

> **The cost of fragmentation.** Separate tests each duplicate setup: "update" must first create, "delete" must first create, "get" must first create. If the unified test makes 6 API calls, four separate tests might make 16+. The arithmetic is unfavorable:
> - **Longer runs** — more calls, more network + DB latency.
> - **More transient failures** — each call is a chance for a timeout/reset; doubling calls roughly doubles flakiness.
> - **Slower recovery** — a suite that takes twice as long takes twice as long to retry.
> The unified flow isn't just more elegant; it's more reliable.

## Asynchronous processing flows
Many services process work asynchronously — a request arrives, processing happens in the background, results appear later. Smoke tests must accommodate this.
**API-triggered async processing:** submit a request → **poll** a status/results endpoint until complete → verify results → clean up. The key is *polling, not sleeping*: a fixed sleep is either too short (flaky) or too long (wasteful). Poll with a reasonable interval and timeout.
**Queue-to-queue processing (isolated deployments only):** begin listening to the output queue → publish a test message to the input queue → wait for the corresponding output message → verify its contents. This validates the full pipeline but **can only run in isolation** — in a live environment, consuming the output queue would intercept messages meant for downstream services. For live suites, use an alternative: a status API, logs/metrics that confirm processing, or simply omit the test.
## Use external-facing interfaces
Smoke tests should interact through the same interfaces real consumers use — public APIs, message queues, integration points — not internal implementation details.
When a test needs extra control (to force a behavior or verify internal state), first ask whether the **system itself** should expose that capability. Well-designed systems often benefit from observability endpoints, admin APIs, or config options that serve both operations and testability. **Prefer enhancing the system over adding test-only backdoors.** When test hooks are unavoidable, implement them thoughtfully: consider security, ensure they can't be exploited in production, and document their purpose.
## Design for determinism
Flaky tests erode trust — a test that passes and fails without any system change becomes noise, not signal. Design for deterministic results:
- **Avoid timing dependencies.** Poll for completion rather than sleeping a fixed duration.
- **Isolate test data.** Use unique identifiers so resources don't collide with each other or real data.
- **Control the environment.** Where possible, configure the system to behave predictably during tests.
## Be defensive about cleanup
Smoke tests run in shared environments, and a test that fails mid-execution may leave behind resources that interfere with later runs. So tests must clean up not only *after* themselves but also **before** they run: at the start, assume a prior execution may have failed to clean up, and proactively remove any resources the test will create. This makes tests idempotent and repeatable without manual intervention.
## Shared-schema discipline

A smoke test that reaches the database directly runs against a schema **the deployed service is actively using** — and the "ephemeral" test environment is more durable than its name suggests: PR deployments reuse a warm stack across pushes, so rows survive from run to run and from crash to crash. A fresh, empty table was never part of the contract; tests that assumed one were passing by coincidence.

Three rules make a shared, durable schema safe. Each covers the failure the previous one leaves open:

1. **Own your rows.** Every identifier the test creates is per-run unique (a `uuid4` suffix on uids, names, codes). Residue from prior runs or from the service's own traffic can never collide with you — which is what makes re-runs idempotent with no pre-clean at all.
2. **Clean up exactly what you made.** Delete rows, never tables. Track what your sessions persist and purge that, children before parents, including rows the service created *referencing* yours (a row pointing at your per-run uuid can only be yours). A whole-table `DELETE` is blocked by foreign keys from tables you did not declare, and would remove rows the deployment depends on even where it is not.
3. **Assert only within your own data.** No `count(*)` over a table, no equality against a full listing or map. Filter by your identifiers, assert subset rather than equality on anything global. This is the rule that fails silently in review: the cleanup can be perfect while an assertion still assumes it owns the table.

Concurrency follows from the same split: tests in one run are sequential, so the race that matters is **test-versus-service** — the deployed service writes to the same schema while the suite runs. Rules 1 and 3 are what neutralize it: the service cannot guess your identifiers, and you never assert over its rows. A test that runs a table-sweeping job (a reminder scan, a reconciler) may still touch rows it does not own; scope its assertions to your rows and accept the sweep, or do not run it against a shared schema.

Whole-table clearing is legitimate in exactly one place: a test-owned stub table with no inbound foreign keys, whose tests assert on table-wide counts and need an empty table. Nothing the deployed service depends on qualifies.

Reaching the database is part of the same contract. The suite issues **no DDL**: the schema is whatever migrations produced. A suite that built its own schema could never be aimed at a database the service also uses — which is the whole point.

# Being a good citizen
Smoke tests share their environment with other systems. They must not pollute shared resources or distort operational metrics.
- **Identifiable test data.** When a test creates data, make it clearly identifiable as test data (naming conventions, tags, dedicated fields) so other systems can filter it out — preventing contamination of analytics, reports, or downstream processing.
- **Observable as tests.** Include headers, trace IDs, or markers identifying traffic as smoke-test origin, so observability systems can distinguish it from real traffic and tests don't inflate metrics or trigger false alerts.
- **Minimal footprint.** Create only what the test needs, clean up completely, and avoid orphaned data that accumulates over time.
# FAQ
## How is this different from a unit test?
Unit tests verify your code's *logic* in isolation with mocked dependencies. Smoke tests verify your code's *assumptions about external systems* are correct, against real infrastructure. A mock can't validate SQL syntax, catch a missing env var, or confirm a queue is wired correctly — those need a real environment.
## How many smoke tests should a service have?
As few as possible while still covering its integration points and deployment health. Comprehensiveness is a unit-test goal; for smoke tests, each one should be independently justifiable. If you're adding a smoke test to cover an edge case or error path, it probably belongs in a unit test instead.
## A smoke test needs to check internal state — what do I do?
Prefer making the system expose that state through a real interface (an observability or admin endpoint) that serves operations too, rather than a test-only backdoor. If a hook is truly unavoidable, secure it, ensure it can't be exploited in production, and document it.
## Why poll instead of sleep for async flows?
A fixed sleep is a guess: too short and the test is flaky, too long and every run wastes that time. Polling with an interval and timeout adapts to actual completion time — faster on average and far less flaky.