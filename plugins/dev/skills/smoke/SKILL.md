---
name: smoke
description: >-
  Use this skill when designing, writing, auditing, or reviewing smoke tests —
  end-to-end tests that exercise integration points and configuration against a
  real (deployed or local) environment. Apply it whenever the work involves
  deciding what a smoke test should cover, whether existing smoke tests follow
  good practice, or how smoke coverage differs from unit coverage.
  Also covers classifying which environments a smoke test may run in — the
  live/internal/external/test_only markers and the criteria behind them.
  Triggers: smoke test, smoke tests, smoke coverage, post-deployment test,
  integration smoke, design smoke tests, audit smoke tests, live-environment test,
  pytest.mark.live, smoke tier, which environment should this test run in.
---

!`"${CLAUDE_PLUGIN_ROOT}/scripts/inline-doc.sh" "${CLAUDE_PLUGIN_ROOT}/docs/smoke-tests.md"`

---

Apply the smoke test principles above to whatever the user is working on. Depending on the context, this typically means one of:

- **Designing** new smoke tests for a feature, service, or codebase area — identify integration points and configuration needing coverage, propose complete flow tests rather than fragmented operations, and account for deployment contexts (isolated vs live environments).
- **Classifying** a smoke test's environment tier — apply the criteria in "Choosing where a test runs" to decide whether it earns `live`, and say why. Every smoke test needs this decision made explicitly; an unmarked test runs at the CI gate only and is indistinguishable from one nobody classified.
- **Auditing** existing smoke tests — evaluate each against the principles, then flag tests to consolidate into complete flows, tests that merely duplicate unit coverage (eliminate them), missing integration coverage, cleanup/determinism issues, and tests inappropriate for live environments. Propose specific improvements with rationale.

Infer which from the conversation. If it's genuinely ambiguous, ask the user what they want to focus on.
