# T03 Collaboration Artifact Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make T03 «Продуктовая фича» artifact-driven: roles exchange only declared predecessor artifacts.

**Architecture:** Keep `task_dependencies` and task-level `artifact_versions` for inter-task work. Add immutable slot-artifact versions and a direct-predecessor `collaboration_context` to the existing TaskContext bridge.

**Tech Stack:** TypeScript, Fastify, better-sqlite3 migrations, Vitest, Python TaskContext bridge.

**Spec:** [T03 design](T03-ARTIFACT-CONTRACT-DESIGN.md)

## Global Constraints

- Canonical server source is `/home/maksim/Проекты/New-Todoist/server` on `.110`.
- Run tests with `PATH=/home/maksim/.nvm/versions/node/v22.23.1/bin:$PATH`.
- Preserve old plans and `POST /api/task-role-slots/:slotId/result`.
- Do not change iOS, `task_dependencies`, template auto-selection, T04 or T05.

## Review Focus

- Invalid/rejected/revision-requested artifacts never open a successor.
- Disabled H1/D1 leaves no edge blocking V1.
- Context excludes transitive and unrelated slots, chats and credentials.
- New version preserves prior versions; legacy free-text slots keep working.

---

### Task 1: Add node and edge artifact contracts

**Files:**

- Modify: `/home/maksim/Проекты/New-Todoist/server/src/migrations.ts`
- Modify: `/home/maksim/Проекты/New-Todoist/server/src/routes/task-collaboration-plans.ts`
- Test: `/home/maksim/Проекты/New-Todoist/server/test/task-collaboration-plans.test.ts`

**Produces:** `ArtifactContract` on a node and `artifact_key` on an edge.

- [ ] Write failing route tests that create an `output_artifact` and verify it is returned; cover duplicate/invalid keys and an edge key not produced by its source.

```ts
output_artifact: {
  key: "feature_spec", type: "specification", format: "json",
  required_fields: ["scope", "acceptance_criteria"],
}
```

- [ ] Run `npm test -- task-collaboration-plans.test.ts`; expect failure because contract fields are absent.
- [ ] Add migration `075_collaboration_plan_artifact_contract`: nullable node output-contract storage and nullable edge artifact key, preserving historic plan rows.
- [ ] Extend `NodeInput`, `EdgeInput`, `parseGraph` and `present`. For plans with contracts, every edge key must equal the output key of `from_slot_key`.
- [ ] Re-run focused tests and `npm run build`, then commit:

```bash
git add server/src/migrations.ts server/src/routes/task-collaboration-plans.ts server/test/task-collaboration-plans.test.ts
git commit -m "feat: declare collaboration plan artifacts"
```

### Task 2: Version slot artifacts and gate successors

**Files:**

- Modify: `/home/maksim/Проекты/New-Todoist/server/src/migrations.ts`
- Modify: `/home/maksim/Проекты/New-Todoist/server/src/routes/task-role-slots.ts`
- Test: `/home/maksim/Проекты/New-Todoist/server/test/task-role-slots.test.ts`

**Consumes:** Task 1 contracts. **Produces:** latest valid artifact version for Task 3.

- [ ] Write red tests for valid submission, payload-field rejection without state change, revision version 2, `artifact_ready` evidence requirement, and owner acceptance.

```ts
await app.inject({
  method: "POST", url: `/api/task-role-slots/${analysisSlot.id}/artifact`,
  headers: { authorization: analystAuth },
  payload: {
    summary: "Согласован scope",
    payload: { scope: "…", acceptance_criteria: ["…"] },
    evidence: [{ path: "docs/feature-spec.md" }],
  },
});
```

- [ ] Run `npm test -- task-role-slots.test.ts`; expect `/artifact` missing.
- [ ] Create `role_slot_artifact_versions` with unique `(slot_id, version_no)`, key/type/format, summary, payload JSON, evidence JSON, status, creator and timestamp.
- [ ] Add submit, accept, revision-request and reject endpoints. Assigned role submits from `active`; owner/orchestrator decides. Retain `/result` for nodes without a contract.
- [ ] Change `canBecomeReady`: `submitted` requires newest submitted/accepted artifact; `artifact_ready` additionally requires evidence; `accepted` requires newest accepted artifact. Log every lifecycle/gate event.
- [ ] Run `npm test -- task-role-slots.test.ts task-collaboration-plans.test.ts` plus `npm run build`, then commit.

```bash
git add server/src/migrations.ts server/src/routes/task-role-slots.ts server/test/task-role-slots.test.ts
git commit -m "feat: version collaboration slot artifacts"
```

### Task 3: Pass direct slot artifacts into TaskContext v1

**Files:**

- Create: `/home/maksim/Проекты/New-Todoist/server/src/runtime/collaborationPlanContext.ts`
- Modify: `/home/maksim/Проекты/New-Todoist/server/src/runtime/inProcessRun.ts`
- Modify: `/home/maksim/Проекты/New-Todoist/server/src/runtime/taskContextBridge.ts`
- Modify: `/home/maksim/Проекты/New-Todoist/server/scripts/task_context_bridge.py`
- Test: `/home/maksim/Проекты/New-Todoist/server/test/collaborationPlanContext.test.ts`
- Test: `/home/maksim/Проекты/New-Todoist/server/test/inProcessRun.test.ts`
- Test: `/home/maksim/Проекты/New-Todoist/server/test/taskContextBridge.test.ts`

**Produces:** isolated `collaboration_context` in the existing launch packet.

- [ ] Write red tests proving V1 receives direct A1/H1/D1 artifacts in stable edge order and excludes unrelated/transitive slots.
- [ ] Run `npm test -- collaborationPlanContext.test.ts`; expect missing builder.
- [ ] Implement the builder output below and call it only for `input.slotId` in `runRoleInProcess`.

```ts
type CollaborationPlanContext = {
  status: "ok" | "empty" | "unavailable";
  plan_id: string | null;
  revision: number | null;
  slot_key: string | null;
  predecessor_artifacts: Array<{
    slot_key: string; artifact_key: string; summary: string;
    payload: Record<string, unknown>; evidence: unknown[];
  }>;
};
```

- [ ] Extend `LaunchContextInput` and Python bridge; serialize this section separately from dependency and knowledge context. Log `collaboration_context_used` with plan revision and source artifact ids.
- [ ] Capture bridge input in tests to prove there is no chat/credential leak. Run `npm test -- collaborationPlanContext.test.ts inProcessRun.test.ts taskContextBridge.test.ts` and `npm run build`, then commit.

```bash
git add server/src/runtime/collaborationPlanContext.ts server/src/runtime/inProcessRun.ts server/src/runtime/taskContextBridge.ts server/scripts/task_context_bridge.py server/test/collaborationPlanContext.test.ts server/test/inProcessRun.test.ts server/test/taskContextBridge.test.ts
git commit -m "feat: pass plan artifacts into role context"
```

### Task 4: Materialize explicit T03 proposals

**Files:**

- Modify: `/home/maksim/Проекты/New-Todoist/server/src/routes/task-collaboration-plans.ts`
- Test: `/home/maksim/Проекты/New-Todoist/server/test/task-collaboration-plans.test.ts`

- [ ] Write red tests for `profile: "product_feature"` and explicit `include_architecture`, `include_design`, `include_qa` booleans.
- [ ] Verify baseline A1→V1; optional combinations have no dangling edges; contracts and gates match the approved diagram.
- [ ] Run `npm test -- task-collaboration-plans.test.ts`; expect unknown profile.
- [ ] Add T03 builder: A1/V1 always; optional H1/D1/Q1 only when requested; A1/H1/D1 → V1 use `accepted`, V1 → Q1 uses `artifact_ready`.
- [ ] Leave `profile: auto` untouched. Run focused plan/slot tests and commit.

```bash
git add server/src/routes/task-collaboration-plans.ts server/test/task-collaboration-plans.test.ts
git commit -m "feat: propose product feature collaboration plans"
```

### Task 5: Verify server flow and record evidence

**Files:**

- Modify: `/Users/max/Проекты/TaskFlowNativeBuild/docs/2026-09-29-collaboration-plan-templates/HANDOFF-T03-CONTRACT.md`
- Modify: `/Users/max/Проекты/TaskFlowNativeBuild/docs/2026-09-29-collaboration-plan-templates/t03-product-feature/T03-ARTIFACT-CONTRACT-DESIGN.md`

- [ ] Run `npm run build` and full `npm test` on `.110` under Node 22.
- [ ] On the Vitest database only, approve a T03 A1/H1/D1/V1/Q1 graph, accept A1/H1/D1, prove V1 receives exactly their artifacts, submit V1 with evidence, and prove Q1 starts without owner acceptance.
- [ ] Record migration id, commands, test counts and known gaps; do not claim real-model or iOS verification unless separately performed.
- [ ] Run `git diff --check` in both repositories and commit documentation evidence separately.

## Plan Self-Review

- Tasks 1–2 implement the contract, validation, versions and gates.
- Task 3 covers context isolation and prompt delivery.
- Task 4 creates T03 without unapproved automatic classification.
- Task 5 requires complete regression evidence and an isolated end-to-end flow.
