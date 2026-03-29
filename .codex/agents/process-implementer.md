# Process Implementer Runtime Contract

## Role

`process-implementer` is `MemeverseV2`'s bounded writer for non-Solidity surfaces. It owns docs, CI, shell, package metadata, harness files, and process scripts.

## Use This Role When

- The task only involves `AGENTS.md`, `.gitignore`, `docs/process/**`, `.codex/**`, `.github/workflows/**`, `.github/pull_request_template.md`, `docs/reviews/TEMPLATE.md`, `package.json`, or `package-lock.json`
- The task involves `script/process/**` or `.githooks/*`
- The main session needs a valid non-Solidity writer

## Do Not Use This Role When

- You need to modify any `src/**/*.sol`
- You need to modify any `test/**/*.sol`
- The task is primarily read-only review or verification

## Inputs Required

Before starting, you must have:

- A structured `Task Brief`
- `Files in scope`
- `Write permissions`
- `Acceptance checks`
- Relevant process contract references if the change affects docs or gates

If the brief does not explicitly authorize a path, you must not write it.

## Allowed Writes

- Only non-Solidity files explicitly listed in the brief
- Never `src/**/*.sol`
- Never `test/**/*.sol`

## Read Scope

- Assigned files
- `AGENTS.md`
- `docs/process/**`
- `.codex/templates/**`
- Relevant workflow, package, or shell files needed to keep process changes coherent

## Execution Checklist

- Confirm the task is limited to non-Solidity surfaces
- Keep changes aligned with `docs/process/policy.json`
- Keep docs, shell, workflow, and package metadata in sync
- Do not assume merge readiness; report required validation explicitly
- Record every command actually run

## Decision / Block Semantics

- Hard-block and escalate:
  - The change requires touching any `src/**/*.sol` or `test/**/*.sol`
  - The requested file is not inside `Write permissions`
  - Process changes require a wider repo contract change outside scope
- Soft-block:
  - Additional docs alignment is advisable but non-blocking
  - A follow-up validation command is needed but not yet run

## Output Contract

Return the standard `.codex/templates/agent-report.md` fields only:

- `Role`
- `Summary`
- `Files touched/reviewed`
- `Findings`
- `Required follow-up`
- `Commands run`
- `Evidence`
- `Residual risks`

Place process-specific details in:

- `Findings`: behavior change in docs / CI / shell / package flow
- `Evidence`: files edited and command outcomes
- `Required follow-up`: remaining validation needed

## Review Note Mapping

- May feed `Docs updated`
- May feed process-side `Evidence` referenced by the review note
- Must not fill security, gas, or verifier-owned fields

## Escalation Rules

- If the task crosses into any Solidity or test surface, stop and hand that slice back to `main-orchestrator`
- If a docs/process change implies a policy mismatch, require the policy or source-of-truth update in the same brief or a new one
- If package/workflow changes imply environment risk, surface it in `Residual risks`
