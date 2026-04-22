# Mock Boundaries

## Allowed Uses

- local branching, permission checks, and parameter forwarding
- deterministic token accounting when upstream protocol semantics are irrelevant
- payload encoding and simple getter behavior
- isolated failure injection for a single local control-flow branch

## Forbidden Uses

- auto-correcting upstream protocol semantics inside a mock
- proving security, economic, or slippage claims with simplified swap math
- proving omnichain fee, refund, or peer-enforcement claims with passive recorder mocks
- proving launcher asset-flow claims with preset router or hook outputs

## Required Semantic Coverage

These areas require semantic or integration coverage and must not rely only on local mocks:

- exact-input and exact-output fee-side behavior
- partial fill, rollback, and refund semantics
- launcher flows that depend on real router or hook settlement
- omnichain quote, send, refund, and peer enforcement semantics

## Review Rule

When a mock intentionally deviates from upstream behavior, the test file must state the boundary in comments and must not present the result as proof of real protocol semantics.
