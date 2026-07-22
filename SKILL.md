# Skill

## Purpose

This file captures recurring user directions, explicit remember-this items, and stable working preferences for work in this repository.

## Workspace / Repo Topology

- `/Users/sodo/gighiveapp` is the repo used for GigHive iPhone app development.
- `/Users/sodo/gighiveapp/gighiveinfra` is effectively a second repo for GigHive infrastructure, PHP, and Ansible work.
- The `gighiveinfra` repo lives on the user's pop-os box and is NFS-mounted into the Mac under the `gighiveapp` directory.
- The user frequently switches between these two repos during normal work.
- When working in this repo, be explicit about which repo a file belongs to before proposing edits, paths, or commands.

## SDLC Environments

Server inventory (`~/scripts/myServers.txt` on pop-os, as of 6/5/26):

| FQDN (alias) | IP | Notes |
|---|---|---|
| `pop-os` | 192.168.1.235 | Host: custom PC; Ansible controller; unit test runner |
| `devvm.gighive.internal` (`gighive2`) | 192.168.1.50 | VirtualBox VM hosted on pop-os; Docker host (apacheWebServer, apacheWebServer_tusd, mysqlServer, ai-worker); Ansible host |
| `lab.gighive.internal` | 192.168.1.233 | Host: gmktech minipc; Ansible host; VirtualBox install |
| `labvm.gighive.internal` (`gighive`) | 192.168.1.252 | VirtualBox VM hosted on lab; Docker containers |
| `staging.gighive.internal` (5TB RAID) | 192.168.1.231 | Host: gmktech minipc; Ansible host; VirtualBox install |
| `stagingvm.gighive.internal` (alias: `gighive.gighive.internal`) | 192.168.1.248 | VirtualBox VM hosted on staging; Docker containers; normal staging install |
| `prod.gighive.internal` | 192.168.1.227 | Host: Orange Pi; Docker containers only; no VirtualBox; not an Ansible host |

Key topology notes:
- Load tests run **from** pop-os (`~/gighive/load_tests/`) targeting `devvm.gighive.internal`.
- The monitor script runs **on** `devvm.gighive.internal` (gighive2); deploy via `scp` from pop-os.
- `~/gighive/` on pop-os is the NFS mount of `/Users/sodo/gighiveapp/gighiveinfra/` on Mac.
- TSV monitor logs land on gighive2 at `~/load_test_runs/`; Python result logs land on pop-os at `~/gighive/load_tests/load_test_runs/` (visible on Mac via NFS).

## MCP Server Environments

MCP config file: `~/.codeium/windsurf/mcp_config.json` on the Mac.

All four servers connect via SSH and run the same MCP server script on the remote host:

| MCP server name | SSH host | Script path |
|---|---|---|
| `dev` | `dev` | `/home/ubuntu/gighive/mcp-server/server.py` (venv) |
| `lab` | `lab` | `/home/ubuntu/gighive/mcp-server/server.py` (venv) |
| `staging` | `staging` | `/home/ubuntu/gighive/mcp-server/server.py` (venv) |
| `prod` | `prod` | `/home/ubuntu/gighive/mcp-server/server.py` (venv) |

The `prod` server maps to the `mcp2_*` tool prefix in Windsurf. Other environments get their own tool prefix when active.

- Prefer querying the matching MCP server directly for environment-specific database and operational checks when that server is exposed in the current session.
- If an expected MCP server is not available as active tools in the current session, tell the user and ask them to verify the SSH host is reachable and the server process is running before falling back to SSH or shell access.

## Most Important Recurring Patterns

- Plan first when requested.
- **ALWAYS ask explicit permission before implementing.** Even when a plan has been discussed, agreed on, and design questions resolved, do NOT begin writing code or making file changes until the user explicitly says to proceed (e.g. "implement it", "do it", "go ahead", "yes"). Confirming a design choice (e.g. answering "from now" to a clarifying question) is NOT permission to implement.
- **HARD RULE: no implementation before explicit approval.** Do not edit code, create files, apply patches, run mutating commands, or otherwise begin implementation work until the user has clearly and directly authorized implementation. If there is any ambiguity, stop and ask.
- Do not implement changes until the user explicitly approves when the request is framed as review, planning, confirmation, or discussion.
- Prefer simple, targeted fixes over broad refactors.
- Debug from concrete evidence such as errors, logs, screenshots, exact file paths, and observed behavior.
- Address root cause rather than symptoms.
- Treat documentation as a first-class deliverable when requested.
- Preserve working behavior and avoid regressions; favor rollback-safe changes.
- Honor exact environment constraints, device baselines, file paths, and deployment details provided by the user.
- For UI issues, reason in terms of the exact visible sequence the user expects.

## Working Style

- Lead with the answer, plan, or diagnosis.
- Keep responses concise but specific.
- Use exact filenames and paths when discussing changes.
- Prefer short lists over long prose.
- Name exactly what changed or will change.
- Be concrete and operational.
- Ask narrow clarifying questions only when needed.
- If the user asks for a plan, provide phased steps, assumptions, and risks.
- If the user asks for confirmation of understanding, summarize scope and constraints without implementing.
- If the user asks to fix a specific issue and the target is clear, implement directly unless they asked to review first.

## Prompt Interpretation Rules

- "Give me a plan" means do not implement yet.
- "Let's review" means summarize and discuss before changing code.
- "Confirm your understanding" means restate scope, assumptions, and intended approach only.
- "Please fix" usually means implementation is expected if the target is clear.
- "Keep it simple" means avoid unnecessary abstraction, refactors, and extra features.
- "Document this" means the documentation itself is part of the required deliverable.

## Debugging Playbook

- Restate the symptom briefly.
- Separate observed behavior from likely cause.
- Inspect the authoritative files and call sites.
- If an error message says a variable is undefined or missing, automatically search the repo for where that variable is defined and where it is consumed.
- Prefer diagnostics first when the root cause is not yet clear.
- When proposing a fix, explain why it addresses the root cause.
- Keep fixes minimal and easy to verify.
- For debugging, include what to check, where to check it, and what outcome to expect.

## Planning Playbook

- Define the goal in one sentence.
- List the files or subsystems likely involved.
- Break the work into a few outcome-oriented phases.
- Call out assumptions, compatibility constraints, risks, and rollback considerations.
- Wait for approval before implementing when the user asks for review first.

## Implementation Cadence

When executing a multi-step plan:

- Execute phases in order — Phase 1 before Phase 2, etc.
- Within each phase, take steps one at a time:
  1. Ask for approval to start the step.
  2. Implement the change (for non-manual items).
  3. Pause for the user to verify (if the step has a verification step).
  4. Move on to the next step only after verification passes.
  5. Once a step is verified as completed, update the .md file to indicate as such.
- Do not batch or skip ahead — each step gets its own approve → implement → verify cycle.
- Manual steps (e.g., running a DDL command, submitting to the App Store) are handed off to the user with clear instructions; wait for confirmation before proceeding.

## Post-Plan Review Ritual

After any implementation plan document (feature, PR, problem, process, refactor, or other) is
drafted, always perform the following checks before presenting it as final:

1. **Logic correctness** — Trace every conditional and state transition. Check for edge cases
   that break stated invariants (e.g., a guard that locks a legitimate user out, a condition
   that evaluates incorrectly on first render, a race condition between async operations).
2. **Internal consistency** — Verify that section names, referenced symbols, file paths, and
   stated behaviors are consistent throughout. Confirm the Testing Checklist covers all code
   paths described in the implementation. Confirm section order follows the SKILL.md format for
   the doc type (feature, refactor, problem, PR).
3. **Coding best practices** — Swift: no force unwraps (RSPEC-6426), no side effects in
   `@ViewBuilder` bodies, computed properties on `View` structs are cheap. PHP: PDO prepared
   statements only, correct `http_response_code` + `exit`, proper try/catch error handling.
4. **Secure coding practices** — No credentials, tokens, or secrets in source code. Sensitive
   data hashed before DB queries (e.g., `hash('sha256', $nonce)`). Input validated before DB
   access. Access control verified before data is returned.
5. **SonarQube violations** — Flag RSPEC-6426 (force unwrap / null dereference), RSPEC-3776
   (cognitive complexity), RSPEC-2635 (sensitive data in SQL), RSPEC-107 (too many parameters).
   Document findings in a "SonarQube / Best-Practice Notes" subsection inside the implementation
   section of the plan doc.
6. **Brittle coding practices** — Scan for duplicated regexes, duplicated auth-resolution logic,
   repeated validation branches, magic strings, and copy-pasted query fragments that should be
   abstracted into one authoritative helper or shared function. Prefer consistent, centralized
   validation/parsing paths over endpoint-by-endpoint inline logic.
7. **Ansible best practices** (when applicable) — All variables in `group_vars`, not hardcoded.
   Idempotent tasks. `become: yes` only where required. Secrets via Vault or env, never
   plaintext. Smoke tests updated when schema or config changes. Do not use `shell` or `command`
   modules where a proper Ansible module exists — prefer non-brittle standard modules (e.g.,
   `mysql_query`, `uri`, `copy`, `template`, `file`) over ad-hoc shell statements.
8. **Completeness check** — Ask: is there anything missing from this plan? Look for unstated
   prerequisites, omitted edge cases, steps assumed but not written down, and follow-on work
   that would block a clean ship if left unaddressed.
9. **Code snippet depth** — Is there enough detail in the code snippets laid out or do we need
   a deeper dive?
10. **Final concerns** — Any last concerns, glaring errors or items missing from the implementation plan?
11. **MySQL 8.4 compatibility** — Double-check that all SQL is compatible with MySQL 8.4.
12. **DDL → create_media_db.sql** — For any changes requiring DDL, is there a step to update `create_media_db.sql` to reflect the schema changes?
13. **Timing issues** — Are there any timing issues with the plan? (e.g., deployment ordering, race conditions, dependent services, DDL before code, backend before client release)
14. **Code reuse** — Are there any opportunities to reuse code already written for this implementation?

## Documentation Playbook

- Save plans, findings, and rationale into `/docs/*.md` when requested.
- Include exact paths, assumptions, and important operational notes.
- Keep documentation aligned with the actual implementation and deployment flow.
- Document reversibility or rollback notes when relevant.

## Documentation Format

- **General standards**
- Lead with a precise title that states the document type and subject.
- Prefer short, clearly named sections over long prose blocks.
- Include exact file paths, endpoint names, commands, and environment details when relevant.
- Make the document operational: explain what changed, why, how to verify it, and any rollback or follow-up implications.
- When a doc is plan-oriented, break the work into phases or milestones.
- When a doc describes implementation, include the exact files or subsystems involved.
- Keep terminology aligned with the product vocabulary actually in use.

- **Feature docs**
- Use the pattern seen in recent docs such as `docs/feature_mcp_server_doc_addition.md` and `docs/feature_completed_import_media_from_zip.md`.
- Preferred outline:
  - `# Feature: <name>`
  - `Status`, `Date`, and optional parent/related feature reference near the top
  - `## Overview`
  - `## Primary Use Case and Scope` or `## Use Cases`
  - `## Design Decisions` / architecture / data flow sections as needed
  - `## Files to Change` — **required** as soon as the feature reaches implementation or planning depth; numbered list where each entry names the file, its repo, and a one-line concrete synopsis of every discrete change made to that file — never a vague placeholder like "all steps above" or "see implementation section".
- Feature docs should explain the user-facing problem, the intended behavior, the chosen architecture, and important constraints or deferred scope.
- For larger features, prefer explicit phase breakdowns and call out shared patterns or reusable infrastructure.

- **Problem / RCA docs**
- Use the pattern seen in recent RCAs such as `docs/problem_iphone_qr_code_redirect.md` and `docs/problem_cloudflare_cached_error_messages.md`.
- Preferred outline:
  - YAML frontmatter `description`
  - `# Problem: <name>`
  - `## Summary`
  - `## Impact`
  - `## Symptoms`
  - chronology or `## Problems Encountered` when the issue unfolded in multiple steps
  - `## Root Cause`
  - `## Resolution`
  - `## Verification`
  - `## Preventative Actions` when relevant
- RCA docs should separate observable symptoms from the actual cause.
- Include exact diagnostics, commands, environment facts, and configuration values that proved or fixed the issue.
- When multiple issues were encountered, document them chronologically with a fix under each.

- **PR docs**
- Use the pattern seen in recent PR docs such as `docs/pr_delete_upload_iphone.md` and `docs/pr_librarianAsset_musicianEvent_completed_implementation.md`.
- Preferred outline depends on doc depth:
  - concise PR/design doc:
    - `# PR` or `# PR / Design Doc: <name>`
    - `## Summary` or `## Proposed change`
    - `## Rationale`
    - `## Constraints / non-goals`
    - `## UX requirements` or `## Agreed Requirements`
    - `## Implementation plan`
    - `## Files to Change` — **required**; numbered list where each entry names the file, its repo, and a one-line concrete synopsis of every discrete change made to that file — never a vague placeholder like "all steps above" or "see implementation section".
    - `## Verification`
  - large implementation PR plan:
    - overview and guiding decisions
    - PR milestone list
    - recommended sequencing
    - per-PR purpose, changes, exact files, and verification
- PR docs should be implementation-oriented, with exact files, concrete milestones, and explicit verification criteria.
- If a change is large or risky, include sequencing, rollback snapshot guidance, and contract/API coordination notes.

- **Refactor docs**
- Use the pattern seen in `docs/refactor_iphone_qr_code_gallery_access_for_all.md` and `docs/refactor_iphone_qr_code_gallery_notifications.md`.
- Preferred section order:
  - `# Refactor: <name>`
  - `## Status — <date>` — one-liner: in progress / complete / pending, with a brief summary
  - `## Rationale` — why the change is necessary or desirable; product and UX reasoning
  - `## Goal` — the change stated as a policy; one sentence + bold policy statement
  - `## Industry Precedent` — comparable systems or prior art that validate the approach
  - `## Decision` — the chosen design, stated as settled fact (not open question)
  - `## Real World Use Cases` — before/after scenario tables with named personas
  - `## Design Principles` — constraints and invariants that must hold after the refactor
  - `## Current State` (or `## Current Auth Model`, etc.) — what the existing code does and why it creates the problem
  - `## Proposed Implementation` — Files Under Change (new/modified) table first, then per-subsystem detail with schema facts, step-by-step changes, and SonarQube / best-practice notes per subsystem
  - `## Wireframe` — ASCII UI sketch when UX is involved
  - `## Files to Change` — numbered list where each entry names the file, its repo, and a one-line concrete synopsis of every discrete change made to that file — never a vague placeholder like "all steps above" or "see implementation section".
  - Supporting analysis sections (e.g., `## Token TTL vs Gallery Expiry`) — alternatives considered and why they were rejected; mark as historical context if decision is already made
  - `## Progress` — **always last**; subsections: Completed / Remaining — This Feature / Remaining — Follow-on Tasks

- **Refactor doc rules**
- Progress always goes at the bottom — the reader should understand the full plan before seeing where work stands.
- State the Decision early and unambiguously; do not let analysis sections downstream look like open questions.
- SonarQube and best-practice notes belong inside the implementation section, scoped per subsystem (PHP, Swift, etc.).
- Follow-on tasks get their own subsection in Progress, not in the main plan body.

- **DDL in implementation docs**
- Whenever an implementation doc (`feature_*.md`, `pr_*.md`, `problem_*.md`, `refactor_*.md`, etc.) includes `ALTER TABLE` or any other DDL that modifies the live database, always include a dedicated section that gives the exact `docker exec` command to run it:

```bash
docker exec -i mysqlServer bash -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" media_db -e "<DDL statement(s) here>"'
```

- The section should note any prerequisite code/config changes that must be deployed first.
- Group related DDL statements (e.g., two `DROP COLUMN` statements on the same table) into a single `docker exec` call.

- **Styling cues repeatedly preferred by the user**
- Put saved analysis into a named doc file when requested rather than leaving it only in chat.
- Use dated/status context near the top when it helps anchor the doc.
- Prefer structured headings and milestone sections over freeform narrative.
- Include assumptions explicitly.
- Include verification steps and expected outcomes, not just proposed changes.

## Project-Specific Preferences

- Code for **iPhone 12 Pro** as the baseline device unless told otherwise. Do not assume any hardware or OS capability newer than iPhone 12 Pro / iOS 14.
- The GigHive iOS app minimum deployment target is **iOS 14.0** (Xcode project confirmed). Never introduce a SwiftUI or UIKit API that requires iOS 15+, 16+, or later without an explicit `@available` guard or explicit user approval.
- **iOS 14 SwiftUI compatibility pitfalls to remember:**
  - `View.bold()` and `View.fontWeight(_:)` are **iOS 16+**. Use `Text.bold()` (iOS 13+) directly on a `Text` value, or bake weight into `Font.system(size:weight:)`.
  - `Font.bold()` / `Font.weight(_:)` instance methods are **iOS 16+**. Use `Font.system(size:weight:)` instead.
  - `.confirmationDialog` is **iOS 15+**; use `.alert` for iOS 14.
  - `NavigationStack` / `NavigationSplitView` are **iOS 16+**; use `NavigationView` for iOS 14.
  - `task(_:)` view modifier is **iOS 15+**; use `.onAppear { Task { ... } }` for iOS 14.
- In GigHive capture workflow, prefer the term `Event` as the general entity.
- Respect app flavor distinctions such as `gighive` and `defaultcodebase`. `defaultcodebase` is a pseudonym for the stormpigs version of gighive.
- **ALL configuration variables — existing and new — must be declared in the appropriate `group_vars` file(s) (`gighive2.yml`, `gighive.yml`, `prod.yml`), never hardcoded in PHP files, Jinja2 templates, or any other file.** The `.env.j2` template injects group_vars into the Docker container environment; any value set there overrides PHP-level fallbacks. If a new variable is added to PHP code with a hardcoded default, it must simultaneously be added to all relevant `group_vars` files.
- Follow existing Ansible and `group_vars` conventions for configuration.
- Be explicit about Ubuntu or tooling compatibility when the user raises environment concerns.

## Debugging Protocol

When a problem arises, **DO NOT SPECULATE**. Follow this process:

1. Build a decision tree of what must be true or false at each layer (network, server, app).
2. Give concrete, copy-pastable commands to test each node.
3. Wait for actual output before concluding anything.
4. Only move to the next layer once the current layer is confirmed.

## Stable Remembered Project Notes

- The active iOS project is `/Users/sodo/gighiveapp/GigHive/`.
- Any guest gallery data that must persist across restarts should be scoped to the event, not to a single nonce.
- The iOS app uses a shared `UploadStateStore` environment object at the app root to preserve upload form and in-flight upload state across navigation.
- Xcode's "All Exceptions" breakpoint can falsely pause on internal AVFoundation exceptions; use an Objective-C exception breakpoint when diagnosing the previously observed frozen audio UI issue.

## Source Notes

This file was consolidated from:

- `gighiveinfra/skill.md`
- `/SKILLS.md`
- remembered project notes available in assistant context
- recurring prompt patterns reflected in `gighiveinfra/user-prompts.md`

This is the canonical skills file and should be updated when new recurring instructions become stable and repeated.
