# Subagent Rules

Applies only to delegated workers in isolated Git worktrees. Workers inherit `AGENTS.md` context; this file narrows execution for fast, low-conflict parallel development.

The orchestrator owns planning, integration, broad testing, and releases. A subagent owns a scoped change, minimal verification, and a clean handoff.

## 1. Task Packet

```yaml
objective: concrete outcome
worktree: assigned worktree path
branch: dedicated branch
owned_paths:
  - paths or scope within the worker may modify, usually anything within the project's folder that it owns is acceptable
acceptance_criteria:
  - observable completion conditions, minimal tests for compiling/syntax

# Optional defaults
role: ui | backend | data | review | other
read_paths: [root project and any subfolders/contents within the project's directory, other cli files or necessary packaging/web search is allowed. reading should be properly scoped and intentional]
write_paths: [root project and any subfolders/contents within the project's directory]
constraints: [if executing removals, move things to trash -- no rm -rf or other permanent removal execution. permanent removals will be taken care of by the user. let it be known at the handoff stage if anything needs removal]
verification: none | compile | runtime | smoke  # default: smoke
handoff: commit | patch | summary               # default: commit
```

Omitted write permissions are denied. Stop only when ambiguity affects behavior, architecture, or ownership; otherwise follow the closest existing pattern.

## 2. Execution

Before editing:

1. Confirm the worktree, branch, and `git status`.
2. Read every file you will modify.
3. Read the nearest implementation, types, and configuration needed for the change.
4. Search the web for proper resources and context given the repository/prompt
5. If an implementation already exists and is open source or free, let the user know and incorporate that online package, library or other resource to save costs

While editing:

- Modify only `owned_paths`.
- Keep every changed line tied to the objective.
- Prefer the smallest complete local change.
- Reuse existing components, utilities, types, dependencies, and conventions.
- Avoid broad refactors, cleanup, dependency upgrades, formatting passes, and speculative abstractions.
- Do not change shared schemas, lockfiles, generated files, migrations, routing, authentication, or global configuration unless explicitly assigned.
- Do not add documentation, helpers, examples, or tests unless explicitly required.
- If a necessary edit falls outside ownership, stop and report the exact path and reason.

Do not scan the repository or narrate routine work.

## 3. Verification

Use the cheapest credible check:

- `none`: inspect the diff for text, comments, static content, or non-executable changes.
- `compile`: run the narrowest relevant syntax, type, lint, build, or compile command.
- `runtime`: run the changed script, service, command, or entry point far enough to catch immediate failure.
- `smoke`: exercise one minimal happy path using an existing command or manual check.

Rules:

- Do not run broad unit, integration, end-to-end, or repository-wide suites.
- Do not create a new test harness or add regression tests unless explicitly assigned.
- Do not repeat overlapping checks without a reason.
- Scope commands to the changed package, file, or target when possible.
- Run `git diff --check` before handoff for code changes.
- Report blocked verification with the command, failure, and whether it appears pre-existing.

Integration, cross-worktree validation, and broad regression testing belong to the orchestrator that follows `AGENTS.md` or larger integration manager.

## 4. Git Discipline

- Work only in the assigned worktree and branch.
- Never stage, revert, overwrite, or commit another worker's changes.
- Check `git status` before editing and before handoff.
- Inspect the final diff before returning it.
- Default to one concise commit after verification.
- Do not merge, rebase, cherry-pick, push, tag, release, delete worktrees, or rewrite history unless explicitly assigned.

## 5. Communication

Report during execution only when there is:

- material ambiguity,
- a scope collision,
- a blocked dependency,
- a verification failure,
- or a discovery that changes the implementation decision.

Do not provide command transcripts, long plans, or routine progress narration.

## 6. Handoff

Return exactly:

```text
Status: complete | blocked | partial
Outcome: one sentence describing the implemented behavior
Files: changed paths only
Verification: commands and results, or "not run" with reason
Commit: hash, or "not committed"
Risks: remaining issue, assumption, or "none"
Integration: exact cherry-pick, conflict, configuration, or follow-up needed
```

## 7. Stop Conditions

Stop without speculative edits when:

- the request conflicts with the existing architecture,
- acceptance criteria cannot be satisfied,
- required files are outside `owned_paths`,
- credentials, secrets, production access, or destructive operations are required,
- shared or generated artifacts create likely merge conflicts,
- or the assigned model or tool cannot complete the task reliably. if this occurs suggest a more capable model for completion

Return the smallest concrete decision the orchestrator must make.

## 8. Default Role Set: use if unassigned

- **UI:** Preserve existing components, tokens, responsiveness, and accessibility. Do not redesign adjacent surfaces.
- **Backend:** Preserve authorization, validation, persistence, errors, and observability. Do not change public contracts or database structure unless assigned.
- **Data:** Preserve schemas and migration conventions. Do not backfill or rewrite shared data unless assigned.
- **Review:** Inspect only the supplied diff or commit range. Report correctness, security, regression, and integration risks in priority order.
- **Integrator:** Resolve conflicts, run batch-level verification, and merge verified commits. Do not silently change feature behavior.
