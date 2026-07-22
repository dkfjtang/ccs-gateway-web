# Release Gate Speedups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the existing release path intact while adding faster local gate entry points and timing visibility.

**Architecture:** Add one Node-based gate profile planner/executor for `quick`, `standard`, and `release`; keep `release` as a thin wrapper over the existing full PowerShell release gate with no skip flags. Add elapsed-time reporting to existing PowerShell gates without changing their validation semantics.

**Tech Stack:** Node.js ESM, Vitest, PowerShell, existing cargo/pnpm/Docker gate scripts.

---

### Task 1: Gate Profile Planner

**Files:**
- Create: `scripts/release-gate-profiles.mjs`
- Test: `tests/scripts/releaseGateProfiles.test.ts`

- [ ] **Step 1: Write failing tests**

Add Vitest coverage for release, quick, standard, and unknown mode behavior.

- [ ] **Step 2: Run tests to verify red**

Run:

```powershell
pnpm exec vitest run tests/scripts/releaseGateProfiles.test.ts
```

Expected: fail because `scripts/release-gate-profiles.mjs` does not exist.

- [ ] **Step 3: Implement minimal planner/executor**

Create `scripts/release-gate-profiles.mjs` with exported planning helpers and a CLI.

- [ ] **Step 4: Run tests to verify green**

Run the focused Vitest test and expect pass.

### Task 2: Package Entrypoints

**Files:**
- Modify: `package.json`
- Test: `tests/scripts/releaseGateProfiles.test.ts`

- [ ] Add and verify `gate:quick`, `gate:standard`, and `gate:release`.

### Task 3: Gate Timing Output

**Files:**
- Modify: `scripts/verify-ccs-3-16-2-release-gate.ps1`
- Modify: `scripts/verify-local-overlays.ps1`
- Modify: `scripts/verify-token-cost-savers.ps1`
- Test: `tests/scripts/releaseGateProfiles.test.ts`

- [ ] Add static test expectations for elapsed timing output.
- [ ] Add stopwatch timing to each gate wrapper without changing command semantics.

### Task 4: Documentation

**Files:**
- Modify: `docs/ccs-fork-overlay-ledger.md`

- [ ] Document the new entrypoints and their boundaries.

### Task 5: Expert Review And Final Verification

**Files:**
- Review all changed files.

- [ ] Request expert review.
- [ ] Run focused verification:

```powershell
pnpm exec vitest run tests/scripts/releaseGateProfiles.test.ts
node scripts/release-gate-profiles.mjs quick --print
node scripts/release-gate-profiles.mjs standard --print
node scripts/release-gate-profiles.mjs release --print
git diff --check
```
