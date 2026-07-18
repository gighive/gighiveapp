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

## Most Important Recurring Patterns

- Plan first when requested.
- **ALWAYS ask explicit permission before implementing.** Even when a plan has been discussed, agreed on, and design questions resolved, do NOT begin writing code or making file changes until the user explicitly says to proceed (e.g. "implement it", "do it", "go ahead", "yes"). Confirming a design choice (e.g. answering "from now" to a clarifying question) is NOT permission to implement.
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
  - `## Files to Change` — **required** as soon as the feature reaches implementation or planning depth; summary table listing every affected file, its repo, and the nature of the change
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
    - `## Files to Change` — **required**; summary table of every affected file, its repo, and the nature of the change
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
  - `## Proposed Implementation` — Changes at a Glance table first, then per-subsystem detail with schema facts, step-by-step changes, and SonarQube / best-practice notes per subsystem
  - `## Wireframe` — ASCII UI sketch when UX is involved
  - `## Files to Change` — summary table of all affected files and repos
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
