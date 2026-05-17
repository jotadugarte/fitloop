# agentic:guild Sync Registry

This file is the **single source of truth** for all file mappings between the agentic:guild global repository and destination projects. It is consumed by:

- **`sync.sh`** — fetches this file first via `curl`, then drives all downloads from it. No hardcoded file lists in the script.
- **`update-agentic-guild` skill** — reads this from the cloned repo at `.agenticguild/tmp_update` to drive the AI merge workflow.

## Strategies

| Strategy | Behavior |
|:---------|:---------|
| `merge`  | Always apply the latest upstream version. For `sync.sh`: always overwrite. For `update-agentic-guild`: additive changes are applied automatically; conflicting changes trigger the Interactive Conflict Resolution Protocol. |
| `init`   | Only write if the file does **not** already exist locally. These files contain project-specific content that must be protected from upstream overwrites. |

> **Special files not in this registry** (they require custom logic beyond a simple copy):
> - `templates/core/AGENTIC_GUILD_RULES.md` → `.cursorrules` (prepend/merge logic — handled by dedicated step in both `sync.sh` and the skill)
> - `templates/git-hooks/pre-commit-logic.sh` → `.git/hooks/pre-commit` (install/append logic — handled by dedicated step in both)

---

## File Map

<!-- SYNC_REGISTRY [START] -->
| Upstream Source | Local Destination | Strategy |
|:---|:---|:---|
| skills/hello/SKILL.md | .cursor/skills/hello/SKILL.md | merge |
| skills/start-task/SKILL.md | .cursor/skills/start-task/SKILL.md | merge |
| skills/finish-branch/SKILL.md | .cursor/skills/finish-branch/SKILL.md | merge |
| skills/status-check/SKILL.md | .cursor/skills/status-check/SKILL.md | merge |
| skills/harvest-rules/SKILL.md | .cursor/skills/harvest-rules/SKILL.md | merge |
| skills/code-review/SKILL.md | .cursor/skills/code-review/SKILL.md | merge |
| skills/audit-compliance/SKILL.md | .cursor/skills/audit-compliance/SKILL.md | merge |
| skills/sync-docs/SKILL.md | .cursor/skills/sync-docs/SKILL.md | merge |
| skills/pr-description/SKILL.md | .cursor/skills/pr-description/SKILL.md | merge |
| skills/roadmap-manage/SKILL.md | .cursor/skills/roadmap-manage/SKILL.md | merge |
| skills/roadmap-consult/SKILL.md | .cursor/skills/roadmap-consult/SKILL.md | merge |
| skills/update-agentic-guild/SKILL.md | .cursor/skills/update-agentic-guild/SKILL.md | merge |
| skills/explore-task/SKILL.md | .cursor/skills/explore-task/SKILL.md | merge |
| skills/process-feedback/SKILL.md | .cursor/skills/process-feedback/SKILL.md | merge |
| playbooks/AI_WORKFLOW_PLAYBOOK.md | docs/ai/AI_WORKFLOW_PLAYBOOK.md | merge |
| playbooks/EXPECTED_PROJECT_STRUCTURE.md | docs/ai/EXPECTED_PROJECT_STRUCTURE.md | merge |
| playbooks/SYNC_REGISTRY.md | docs/ai/SYNC_REGISTRY.md | merge |
| package.json | .agenticguild/source_package.json | merge |
| templates/adr/0000-ADR-TEMPLATE.md | docs/core/ADRs/0000-ADR-TEMPLATE.md | merge |
| templates/pr/PULL_REQUEST_TEMPLATE.md | .github/PULL_REQUEST_TEMPLATE.md | merge |
| templates/core/SPEC.md | docs/core/SPEC.md | init |
| templates/core/SYSTEM_ARCHITECTURE.md | docs/core/SYSTEM_ARCHITECTURE.md | init |
| templates/core/deterministic_coding_standards.md | docs/core/deterministic_coding_standards.md | init |
| templates/core/TESTING_STRATEGY_MATRIX.md | docs/core/TESTING_STRATEGY_MATRIX.md | init |
| templates/core/DATA_FLOW_MAP.md | docs/core/DATA_FLOW_MAP.md | init |
| templates/core/ROADMAP.md | docs/ROADMAP.md | init |
| templates/core/memory_scaffold/current_state.md | .agenticguild/current_state.md | init |
| templates/core/memory_scaffold/blocker_log.md | .agenticguild/blocker_log.md | init |
| templates/core/memory_scaffold/pending_refactors.md | .agenticguild/pending_refactors.md | init |
| templates/core/memory_scaffold/task_template.md | .agenticguild/active_sessions/task_template.md | init |
| templates/CbC_GENERATION_PROMPT.md | .cursor/templates/CbC_GENERATION_PROMPT.md | merge |
<!-- SYNC_REGISTRY [END] -->


