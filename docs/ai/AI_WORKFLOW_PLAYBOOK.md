# AI Workflow Playbook
Date: 2026-02-20

## Core AI Commands & Skills

### 1. Start Task
**Goal**: Safely begin working on a new feature, enforcing design and discovery before coding. Enforces Correct-by-Construction (CbC) throughout the execution phase.
**Workflow Steps**:
1. **Task description first**: Check if the user's message already contains a task description. If yes, try to match it to a roadmap item and confirm. If no description, show the roadmap (if present) and ask the user to pick one or describe a new task.
2. **Discovery Q&A**: Interactively gather the context of the feature from the user.
3. **Planning & Constraints**: Draft a detailed, hierarchical implementation plan directly inside the active session memory, anchored to the system architecture.
4. **Architectural Shifts (ADRs)**: Flag and document significant changes.
5. **Schema Mapping**: Map any database changes.
6. **Type Definition Gate (Features only)**: Before writing any tests, define all domain types — Value Objects (Ruby) or Branded Types (TypeScript). No raw primitive types for domain concepts. Awaits explicit user approval.
7. **Execution**: Loop through a strict CbC+TDD cycle step-by-step: write failing test using approved types → apply CbC generation constraints → run `<reflection>` self-critique gate → write minimum implementation → pass test.

### 2. Finish Branch
**Goal**: Safely finalize a branch before opening a PR, ensuring all tests pass and docs are up-to-date.

Finishing a branch runs a code review (guided by `docs/ai/code_review_prompt.md`), then a compliance and traceability audit against deterministic standards. The AI waits for you to push and paste any CI or BugBot feedback, loops on fixes until CI is green, and only then proceeds to final spackle: running sync-docs to update any docs that need changes (using both the branch diff and the active task session — session is semantically analyzed so domain, decisions, data semantics, and conventions are pushed to the right docs), harvesting new rules from diff, review_ledger, and task session into architecture docs and .cursorrules, ensuring CHANGELOG is updated for user-facing changes, updating `docs/ROADMAP.md` to mark the completed item as done, and outputting the PR description in a code block. The AI never auto-commits or auto-pushes; it provides the exact `git push` command for you to run.

### 3. Status Check
**Goal**: Understand blocking issues and re-hydrate the AI's state.
**Workflow Action**: The AI reads `.agenticguild/current_state.md`, the active session memory plan, the git state, and `docs/ROADMAP.md` (if present) to output a macro/micro status report including a roadmap summary (done, in progress, pending) and identify exactly what is blocking progress.

### Skills Index
| Skill | Triggers | Purpose |
|-------|----------|---------|
| start-task | start task, new feature, bugfix, build a | Discovery, planning, and strict TDD loop |
| finish-branch | finish branch, open a PR | Code review, compliance audit, CI loop, docs sync, rule harvest, PR description |
| code-review | code review, run code review, review my changes | Project-specific static analysis and fix loop |
| status-check | status check, where are we, blocked | Rehydrate context and diagnose blockers |
| process-feedback | pasting CI logs, Bugbot comments, SonarQube errors | Interrupt subroutine: fix code, log diagnosis to short-term memory, resume previous task |
| harvest-rules | harvest rules, update docs | Extract new patterns from diff, review_ledger, and task session into docs and .cursorrules |
| audit-compliance | audit compliance, run audit | IV&V audit against deterministic standards |
| sync-docs | sync docs, sync project docs | Keep docs in sync with branch diff and task session (semantic analysis → SPEC, SCHEMA_REFERENCE, ADRs, .cursorrules, etc.) |
| pr-description | PR description, draft PR | Output PR description in a code block |
| roadmap-manage | roadmap, manage roadmap, add to roadmap | Add, prioritize, catalog roadmap items |
| roadmap-consult | roadmap status, what's pending, roadmap consult | Read-only view of done/pending/priorities |

## Memory & State Management (Agent RAM)

agentic:guild utilizes a hidden `.agenticguild/` folder to survive long conversations and tangents. 

* **To Resume Work:** If you get distracted by a tangent or start a new chat window, simply tell the AI: **"Resume Task"** or **"Where were we?"**. The AI will read `.agenticguild/current_state.md` and immediately pick up on the exact phase and step you left off on.
* **To Log Debt:** The AI will automatically log technical debt or blocked tasks into `.agenticguild/pending_refactors.md` and `.agenticguild/blocker_log.md` instead of forgetting them.
