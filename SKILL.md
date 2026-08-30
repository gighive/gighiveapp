don't fabricate any information. any responses shall be based on known facts and hard data. Challenge my ideas at all times with logical arguments. No one idea is perfect.
Never commit to git. The user commits manually.

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
- **Ansible playbooks are always run from pop-os under the `sodo` user.** Never from the Mac. The playbook command is run in `~/gighive/` on pop-os (e.g. `ansible-playbook -i ansible/inventories/inventory_gighive2.yml ansible/playbooks/site.yml ...`). `repo_root` resolves to `~/gighive/` on pop-os via `playbook_dir | dirname | dirname`.
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

- **HIGHEST PRIORITY — No changes before hard evidence.** Make no code or file changes until hard evidence proving root cause has been explicitly presented to the user. Evidence must be observable and specific: exact log lines, query results, stack traces, or concrete source code references. Do not propose a fix, write a patch, or edit any file until the evidence has been shown and the user has been given the opportunity to evaluate it.
- Plan first when requested.
- **ALWAYS ask explicit permission before implementing.** Even when a plan has been discussed, agreed on, and design questions resolved, do NOT begin writing code or making file changes until the user explicitly says to proceed (e.g. "implement it", "do it", "go ahead", "yes"). Confirming a design choice (e.g. answering "from now" to a clarifying question) is NOT permission to implement.
- **HARD RULE: no implementation before explicit approval.** Do not edit code, create files, apply patches, run mutating commands, or otherwise begin implementation work until the user has clearly and directly authorized implementation. If there is any ambiguity, stop and ask.
- Do not implement changes until the user explicitly approves when the request is framed as review, planning, confirmation, or discussion.
- Prefer simple, targeted fixes over broad refactors.
- Debug from concrete evidence such as errors, logs, screenshots, exact file paths, and observed behavior.
- **Root cause must be proven, not inferred.** Before proposing or implementing a fix, produce observable evidence that identifies the root cause with 100% certainty. A fix is only valid if it follows directly from that evidence by logical extrapolation — not from plausible hypothesis. If evidence is incomplete, say so explicitly and gather more before proceeding.
- Address root cause rather than symptoms.
- Treat documentation as a first-class deliverable when requested.
- Preserve working behavior and avoid regressions; favor rollback-safe changes.
- Honor exact environment constraints, device baselines, file paths, and deployment details provided by the user.
- For UI issues, reason in terms of the exact visible sequence the user expects.

## Working Style

- **Never commit to git. The user commits manually.** Do not run `git commit`, `git push`, or any destructive git command. You may run read-only git commands (`git status`, `git diff`, `git log`) to inform your work. When changes are ready to commit, suggest a commit message and stop there.
- **Never run Ansible playbooks. The user always runs them.** Do not invoke `ansible-playbook` under any circumstances — not via SSH, not locally, not via MCP. Prepare the command and hand it off to the user to execute.
- **Never use the `db_migrations` Ansible role.** The user always applies `ALTER TABLE` commands manually following the `docs/process_backup_alter_backup_rebuild_restore.md` (BABRR) process. Do not add tasks to `db_migrations/tasks/main.yml` or reference that role for schema changes. When a schema change is needed, provide the exact `docker exec` ALTER command(s) for the user to run manually per BABRR Step 2. Note: `ADD COLUMN IF NOT EXISTS` is MySQL-incompatible — use plain `ADD COLUMN` and confirm the column is absent before running.
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
- When doing debugging or diagnostic work, diagnosing the issue shall end only when we have 100% proof of what caused the issue.
- Another way to say it: iterate through diagnostics until the output gives 100% confidence in the root cause.
- When determining root cause, execute the historical antecedent event commands yourself if possible, but only to gather diagnostic information; do not start any containers or rebuild images or anything like that until we've proven historical context.
- When proposing a fix, explain why it addresses the root cause.
- Keep fixes minimal and easy to verify.
- For debugging, include what to check, where to check it, and what outcome to expect.

## apacheWebServer Container — Log Inventory

All logs are inside the running `apacheWebServer` Docker container on the VM host (e.g. `ubuntu@192.168.1.50`). Access via `docker exec apacheWebServer tail -f <path>`.

| Log file | Owned by | What it contains |
|---|---|---|
| `/var/log/apache2/access.log` | www-data | Every HTTP request — method, URI, authenticated user, status code, response size, duration |
| `/var/log/apache2/error.log` | www-data | Apache errors, auth failures (`AH01617` password mismatch, `AH01630` denied by config), rewrite trace output (when `rewrite:trace3` log level active), ModSecurity notices |
| `/var/log/apache2/modsec_audit.log` | www-data | Full ModSecurity audit trail — request/response bodies for triggered rules; useful for diagnosing WAF blocks |
| `/var/log/apache2/other_vhosts_access.log` | www-data | Access log for any VirtualHost without its own `CustomLog` — normally empty in this stack |
| `/var/log/fpm-php.www.log` | www-data | PHP application `error_log()` output from the `www` FPM pool — all `[TAG] message` debug lines land here; **primary PHP debug log** |
| `/var/log/php8.3-fpm.log` | root | PHP-FPM daemon startup/shutdown notices (`NOTICE: fpm is running`, `ready to handle connections`) — not PHP application output |
| `/var/log/php-fpm/www.slow.log` | www-data | Slow request stack traces (only populated when `request_slowlog_timeout` is set in pool config) — normally empty |
| `/var/log/probe_job.log` | www-data | GigHive probe/smoke job output — background job results logged by the application |

Key operational notes:
- **PHP `error_log()` → `/var/log/fpm-php.www.log`** — not to Apache's error.log. Always check this file for PHP-level debug output.
- **`PHP_AUTH_USER` is never set** when PHP is served via `mod_proxy_fcgi` (PHP-FPM). Apache strips the `Authorization` header before forwarding to FPM. Use `SetEnvIf Authorization "(.+)" HTTP_AUTHORIZATION=$1` in the Apache config + check `$_SERVER['HTTP_AUTHORIZATION']` in PHP instead.
- **A 401 with no `WWW-Authenticate` header and `content-length: 0`** is PHP calling `http_response_code(401); exit` — not Apache. Check the FPM log and PHP auth paths.
- **A 401 with a `WWW-Authenticate` header** is Apache blocking before PHP is reached — check `error.log` for `AH01617` (password mismatch) or `AH01630` (denied by config).
- **`/etc/apache2/` is read-only** in the container (baked into the image). Live log-level changes via `sed` will fail with "Device or resource busy". Increase verbosity by editing `default-ssl.conf.j2` or `apache2.conf` in the Ansible role and redeploying.

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

## Rules for Technical Implementations

Rules learned from hard failures during implementation. Each rule has a documented root cause; do not treat these as suggestions.

### General — Follow established patterns

Before implementing any fix or new code in PHP, Ansible, Swift, or any other language, inspect existing working code in the same file or role for the pattern already in use (auth handling, command invocation, quoting, module choice, error handling). New code must match that pattern exactly unless there is a documented reason to deviate. Do not introduce a new pattern when a working one already exists in the codebase.

### General — Every solution must have a test

Any fix or new feature documented in a `problem_*.md`, `feature_*.md`, `pr_*.md`, or `refactor_*.md` doc MUST include one or more corresponding tests in `post_build_checks/tasks/main.yml` or the most appropriate Ansible role. A solution without a test is incomplete and must not be marked done. Tests must be permanent (not one-shot), tagged `[smoke]` at minimum, and must exercise the specific behavior the fix addresses.

### General — "must never" statements require a corresponding test

Any statement in a doc that uses the phrase "must never" (or an equivalent strong invariant such as "must not", "never allowed", "always rejected") MUST have a corresponding automated test that proves the invariant holds. The test must be added to `post_build_checks/tasks/main.yml` or `validate_app` (server-side invariants) or noted explicitly as an iOS XCTest (client-side invariants that cannot be exercised via Ansible). A "must never" statement with no corresponding test is a documentation debt that must be resolved before the phase it appears in is marked complete. Each doc's implementation plan must include a dedicated `## Tests` section that lists every test by T-number, what it validates, and where it lives (Ansible role or iOS XCTest).

Before assigning any T-number in a new doc, verify it does not conflict with reservations in any existing planning doc (`feature_*.md`, `refactor_*.md`, `pr_*.md`, `problem_*.md`). T-numbers are a shared namespace across the entire project — a conflict discovered after implementation causes task-name collisions in Ansible output and log disambiguation failures. The safe approach is to grep all `gighiveinfra/docs/*.md` files for the candidate number before using it.

### General — iOS changes require iOS tests following `testing_ios.md`

Any `refactor_*.md`, `pr_*.md`, `problem_*.md`, or `feature_*.md` doc that involves changes to iOS source files (`GigHive/Sources/App/` or any Swift file in the `gighiveapp` repo) MUST include corresponding iOS tests in the doc's `## Tests` section. Those tests must follow the format and methodology defined in `gighiveinfra/docs/testing_ios.md` exactly:

- Sequential test numbers continuing from the last number in `testing_ios.md`'s "What is tested" list
- First-person "I will…" phrasing for the numbered description in the "What is tested" list
- Swift method names following the `testPhaseName_Behaviour` convention
- UI tests placed in `GigHiveUITests.swift` under the appropriate `// MARK: - Phase N` block; unit tests placed in `GigHiveTests.swift` under the same mark
- Credentials listed in the `testing_ios.md` credentials table; new env vars added there before the test is written
- New `accessibilityIdentifier` values registered in the `testing_ios.md` Accessibility Identifiers table before the test that uses them
- New launch arguments documented in the `testing_ios.md` Launch Arguments section before use
- When a phase introduces tests across multiple target files (e.g., both `GigHiveUITests.swift` and `GigHiveTests.swift`), add a `File` column to the test inventory table: `| Test | File | Needs credentials | What it verifies |`; for phases where all tests are in a single file, match the existing `| Test | Needs credentials | What it verifies |` format used in Phases 1–4
- `XCTSkip` (not `XCTFail`) when required env vars are absent, so the suite passes in environments where the credentials are not configured

When a doc includes iOS tests, `testing_ios.md` must be updated in the same change window — it is the canonical registry of all iOS test numbers, method names, env vars, accessibility identifiers, and launch arguments. Do not assign a test number or method name in a doc without first confirming it does not conflict with an existing entry in `testing_ios.md`.

### General — Never hardcode variables or literals

No string literals, numeric values, filesystem paths, URLs, port numbers, or environment-specific values may be hardcoded anywhere in PHP files, Jinja2 templates, Ansible tasks, or any other file. Every such value must come from a `group_vars` variable, a PHP constant defined centrally, or an environment variable injected via `.env.j2`. If a value is deployment-specific (e.g., a path, a hostname, a threshold, a timeout), it belongs in `group_vars`. Use `group_vars` wherever possible.

All configuration variables — existing and new — must be declared in the appropriate `group_vars` file(s) (`gighive2.yml`, `gighive.yml`, `prod.yml`), never hardcoded in PHP files, Jinja2 templates, or any other file. The `.env.j2` template injects group_vars into the Docker container environment; any value set there overrides PHP-level fallbacks. If a new variable is added to PHP code with a hardcoded default, it must simultaneously be added to all relevant `group_vars` files.

### Ansible — Do not use brittle code

No shell commands or regex except in absolute necessity. Use Ansible modules and built-in functions instead of CLI commands. Do not use `shell` or `command` modules where a proper Ansible module exists — prefer non-brittle standard modules (e.g. `mysql_query`, `uri`, `copy`, `template`, `file`) over ad-hoc shell statements.

### Ansible — `community.docker.docker_container_exec`: always use scalar string `command:`

Never use the YAML list form of `command:` with `community.docker.docker_container_exec`. The module serialises a list into the literal string `[php, -l, /path]` and attempts to exec it as a binary name, producing `exec: "[php,": executable file not found`. Always use the scalar shell string form:

```yaml
# Wrong — list form:
command:
  - php
  - -l
  - /var/www/html/src/Services/Foo.php

# Correct — scalar string form (matches project convention):
command: >-
  php -l /var/www/html/src/Services/Foo.php
```

This failure has occurred four separate times across Phases 2, 3, and 5. Before writing any new `docker_container_exec` task, inspect every other exec task in the same file and match the form already in use.

### Ansible — `environment:` on `ansible.builtin.command` does not reach `docker exec`

`environment:` on an `ansible.builtin.command` task sets the variable on the Ansible **controller** process — it is not forwarded into the `docker exec` subprocess inside the container. MySQL (and any other containerised process) will not see the variable. The symptom is `ERROR 1045 (28000): Access denied (using password: NO)`.

The established project pattern — already present throughout `post_build_checks` and `validate_app` — is to pass the password inline inside the shell invocation:

```yaml
# Wrong — sets var on controller, not in container:
- ansible.builtin.command: docker exec -i mysqlServer mysql -uroot ...
  environment:
    MYSQL_PWD: "{{ mysql_root_password }}"

# Correct — password set inside the container's shell process:
- ansible.builtin.command: >-
    docker exec -i {{ mysql_container_name }}
    sh -c "MYSQL_PWD={{ mysql_root_password | quote }} mysql -uroot media_db -sN -e 'SELECT ...'"
```

Before writing a new MySQL exec task, inspect an existing working task in the same file and copy the pattern exactly.

### Ansible — `uri` module cannot send raw binary bodies

Ansible serialises all task parameters as UTF-8 JSON before executing modules. Binary bytes containing surrogate characters (e.g. `\xac`) cause `'utf-8' codec can't encode character '\udcac': surrogates not allowed` before the HTTP request is even sent. This means `uri` with a `b64decode`-generated body is structurally broken for binary payloads — no workaround exists within the `uri` module.

For binary smoke test payloads (e.g. a WAV file sent as a tus PATCH body), use `docker exec` into the container and pipe through `base64 -d` into `curl --data-binary @-`:

```yaml
- name: Write b64 payload and send binary PATCH via curl inside container
  ansible.builtin.command: >-
    docker exec {{ apache_container_name }}
    sh -c "printf '%s' '{{ payload_b64 }}' > /tmp/payload.b64 &&
           base64 -d /tmp/payload.b64 |
           curl -s -X PATCH {{ tus_url }} --data-binary @- -H 'Content-Type: application/offset+octet-stream'"
```

Clean up temp files afterward with `failed_when: false` so a cleanup failure never masks the real result.

### Ansible — `set_fact` self-reference: split into two sequential tasks

Ansible evaluates **all keys** in a single `set_fact` task simultaneously using variable state from *before* the task runs. A key that references another key being set in the same task will produce `'tus_payload_b64' is undefined`. The fix is always to split into two sequential tasks:

```yaml
# Wrong — tus_payload_b64 is not yet defined when tus_payload is evaluated:
- set_fact:
    tus_payload_b64: "{{ 'audio/wav' | b64encode }}"
    tus_payload: "{{ tus_payload_b64 | b64decode }}"

# Correct — two sequential tasks:
- set_fact:
    tus_payload_b64: "{{ 'audio/wav' | b64encode }}"

- set_fact:
    tus_payload: "{{ tus_payload_b64 | b64decode }}"
```

### Ansible — install-channel guards: check which channels a block actually executes on

Any block placed inside a channel conditional (e.g. `if [[ "${GIGHIVE_INSTALL_CHANNEL:-full}" == "quickstart" ]]`) will **not** execute on a `full` install — which is the default for dev, lab, staging, and prod. Before wrapping any task or block in a channel guard, explicitly confirm whether it must run on all channels or only one. If it must run on all channels, place it outside the guard.

Similarly, MySQL configuration prerequisites (e.g. `innodb_lock_wait_timeout`) must be in place *before* the DDL or code that depends on them is deployed. When adding a new MySQL `[mysqld]` setting as part of a feature, add it to `z-custommysqld.cnf` in the same change window as the DDL — never after.

### PHP refactors — audit every call site when a constructor signature changes

When a constructor or function signature changes during a refactor (e.g. dependency injection is added), every call site in the codebase must be located and updated — not just the files touched in the same change. Callers that follow a different auth path (e.g. Basic Auth vs token auth) may not be exercised by the automated smoke test and will only surface as a `500` under the specific flow that hits the outdated call site.

Before marking a constructor-signature refactor complete:
1. `grep -r "new ClassName(" src/ api/` to find every instantiation.
2. Confirm each call site passes the new required arguments.
3. Add a smoke test that exercises the specific auth path most likely to be skipped by existing tests (e.g. a token-authenticated guest path when the existing tests only cover Basic Auth).

---

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
   Any new feature or fix must come bundled with tests so the feature or fix can be validated.
   Normally we do this in either post_build_checks or validate_app ansible roles.
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
6a. **Hardcoded path strings** — Search the changed files (and any file in the same role or subsystem) for hardcoded filesystem paths, container paths, URL prefixes, and directory names that should instead come from a group_var, env var, or PHP constant. A hardcoded path is any string literal that encodes a deployment-specific location, e.g. `/var/www/html/video`, `/home/ubuntu/audio`, `/tmp/tus-staging`, `/var/log/probe_job.log`. For each one found: (a) identify the authoritative variable or constant that should provide the value, (b) flag it in the plan doc, and (c) require that the implementation uses the variable/constant instead of the literal. Do not approve a plan as final if it introduces new hardcoded paths or leaves existing ones unresolved.
7. **Ansible best practices** (when applicable) — All variables in `group_vars`, not hardcoded.
   Idempotent tasks. `become: yes` only where required. Secrets via Vault or env, never
   plaintext. Smoke tests updated when schema or config changes. Do not use `shell` or `command`
   modules where a proper Ansible module exists — prefer non-brittle standard modules (e.g.,
   `mysql_query`, `uri`, `copy`, `template`, `file`) over ad-hoc shell statements.
   **New/modified PHP endpoints**: for each new or modified endpoint under `/admin/` or `/api/`,
   add a corresponding `[smoke]` 401 auth-check task to `post_build_checks/tasks/main.yml`
   using the `uri` module — pattern: unauthenticated `GET /path → status_code: 401`. This proves
   the file landed in the webroot after deploy and is htpasswd-protected. Two tasks per endpoint
   are sufficient; no credentials, no request body, non-destructive on every run.
8. **Completeness check** — Ask: is there anything missing from this plan? Look for unstated
   prerequisites, omitted edge cases, steps assumed but not written down, and follow-on work
   that would block a clean ship if left unaddressed.
8a. **Follow-on task review** — For every task listed as a follow-on item (i.e., not explicitly
   scoped into the current implementation), evaluate whether it can reasonably be included in
   the current change window. No deferral by default — if a follow-on task is small enough,
   low-risk enough, or tightly coupled enough to be done now, include it in the current plan.
   Only defer what genuinely cannot be done now, and state the concrete reason why.
9. **Code snippet depth** — Is there enough detail in the code snippets laid out or do we need
   a deeper dive?
10. **Final concerns** — Any last concerns, glaring errors or items missing from the implementation plan?
11. **MySQL 8.4 compatibility** — Double-check that all SQL is compatible with MySQL 8.4.
12. **DDL → create_media_db.sql + live ALTER/CREATE command** — For any schema change requiring DDL, does the plan include both: (a) an update to `create_media_db.sql` so new environments get the schema from first bootstrap, and (b) the exact live SQL command to apply the same change on existing environments via `docker exec -i mysqlServer ...` against the MySQL container?
13. **Timing issues** — Are there any timing issues with the plan? (e.g., deployment ordering, race conditions, dependent services, DDL before code, backend before client release)
14. **Code reuse** — Are there any opportunities to reuse code already written for this implementation?
15. **Full execution trace** — Do a full final trace of every execution path: normal flow, error flow, recovery/reconnect flow, and any race conditions or timing edge cases. Confirm each path reaches a clean terminal state with no locked UI, no double-execution, and no leaked flags or storage keys.
16. **Resiliency, security, and operability** — Across three lenses:
    - **Resiliency:** Are there single points of failure with no recovery path? Missing health checks? Queues or tables that grow unbounded without a cleanup mechanism? Failure modes that silently succeed but corrupt state (e.g., partial writes, orphaned resources)?
    - **Security:** Are there attack surfaces not yet addressed — rate limiting gaps, input validation that fires too late (after data is already received), privilege escalation paths, predictable identifiers, or modsecurity/WAF rules that must be updated for new endpoints?
    - **Operability:** Is there enough observability to diagnose failures in production (structured logging, metrics, queue depth monitoring)? Are there missing admin tools, unclear runbooks, or operational states (e.g., stuck jobs, orphan blobs, log file growth) that would be difficult to detect or recover from without prior planning?
17. **Jekyll / Liquid syntax safety** — Scan every markdown doc produced or modified by the plan for two classes of Liquid syntax error. Jekyll parses Liquid **before** it processes Markdown, so fenced code blocks (` ``` `) offer **no protection** — Liquid tags inside a code block are still executed.

    **Error class 1 — unprotected `{{ }}` variable tags** (e.g. `{{ my_var }}`): throws `Liquid syntax error: Variable '...' was not properly terminated`.
    - **In prose / inline code**: wrap with `{% raw %}...{% endraw %}` inline, e.g. `` `{% raw %}{{ my_var }}{% endraw %}` ``.
    - **Inside a fenced code block**: place `{% raw %}` on the line immediately before the opening ` ``` ` fence and `{% endraw %}` on the line immediately after the closing ` ``` ` fence. Do not place either tag inside the fence.

    **Error class 2 — bare `{% if %}`, `{% for %}`, `{% unless %}` control tags in prose** (e.g. referencing `` `{% if gighive_auth_mode == 'oidc' %}` `` in a sentence without a matching `{% endif %}`): throws `Liquid syntax error: 'if' tag was never closed`. Fix: wrap the inline tag reference with `{% raw %}...{% endraw %}`, e.g. `` `{% raw %}{% if gighive_auth_mode == 'oidc' %}{% endraw %}` ``.

    **To check a doc before committing**, run the following script against the file:

    ```python
    import re
    path = "docs/your-file.md"  # replace with actual path
    with open(path) as f:
        lines = f.readlines()
    in_raw = False
    depth = 0
    unclosed_ifs = []
    unprotected_vars = []
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if "{% raw %}" in stripped:
            in_raw = True
        if "{% endraw %}" in stripped:
            in_raw = False
            continue
        if in_raw:
            continue
        if "{{" in line:
            unprotected_vars.append((i, line.rstrip()))
        tags = re.findall(r'\{%-?\s*(if|elsif|else|endif|for|endfor|unless|endunless)\b', line)
        for tag in tags:
            if tag in ('if', 'for', 'unless'):
                depth += 1
                unclosed_ifs.append((i, line.rstrip()))
            elif tag in ('endif', 'endfor', 'endunless'):
                if unclosed_ifs:
                    unclosed_ifs.pop()
                depth -= 1
    if unprotected_vars:
        print("=== Unprotected {{ }} ===")
        for lineno, text in unprotected_vars:
            print(f"  {lineno}: {text}")
    if unclosed_ifs:
        print("=== Unclosed {% if/for %} tags ===")
        for lineno, text in unclosed_ifs:
            print(f"  {lineno}: {text}")
    if not unprotected_vars and not unclosed_ifs:
        print("Clean.")
    ```

    Any line printed by this script is unprotected and must be fixed using the appropriate pattern above before the doc is committed.

## Documentation Playbook

- Save plans, findings, and rationale into `/docs/*.md` when requested.
- Include exact paths, assumptions, and important operational notes.
- Keep documentation aligned with the actual implementation and deployment flow.
- Document reversibility or rollback notes when relevant.

## Documentation Format

- **General standards**
- Lead with a precise title that states the document type and subject.
- **Elevator Pitch rule** — Every `feature_*`, `pr_*`, and `refactor_*` doc must open with `## Elevator Pitch` as its first section (immediately after the title and status/date block, before any other section). Write one short paragraph in plain, non-technical language explaining why the change is being made and what benefit it delivers — as if speaking to a non-technical stakeholder in 30 seconds. No jargon, no implementation detail, no acronyms unless unavoidable.
- Prefer short, clearly named sections over long prose blocks.
- Include exact file paths, endpoint names, commands, and environment details when relevant.
- **Jekyll/Liquid-safe docs** — In any file under `docs/` that may be built by GitHub Pages/Jekyll, never leave literal `{{ ... }}`, `{{...}}`, `{% ... %}`, or `%}` tokens in prose or code examples. Escape them for display using HTML entities (`&#123;&#123;`, `&#125;&#125;`, `&#123;%`, `%&#125;`) so Jekyll renders the text instead of parsing it as Liquid.
- Make the document operational: explain what changed, why, how to verify it, and any rollback or follow-up implications.
- When a doc is plan-oriented, break the work into phases or milestones.
- When a doc describes implementation, include the exact files or subsystems involved.
- Keep terminology aligned with the product vocabulary actually in use.

- **Implementation sections** — applies to `feature_*`, `pr_*`, `problem_*`, and `refactor_*` docs wherever a multi-step implementation plan appears.
- The implementation section is the execution blueprint. A developer who has never seen the codebase should be able to read a phase, execute Step 1, verify it, execute Step 2, and so on — without needing to ask a single clarifying question.
- **Divide the work into phases.** Each phase has a single goal that can be stated in one sentence. Phases must be executable in sequence — Phase 2 never starts until Phase 1 is verified complete.
- **Open each phase with its goal.** One sentence. What problem does this phase solve? Completing it should leave the system in a clean, shippable intermediate state.
- **Put supporting context before the steps.** Design decisions, SQL sketches, dependency notes, and option comparisons go before the step list. Steps should never reference concepts that haven't been explained earlier in the same phase section.
- **List every action as a numbered step using `- [ ] **Step N**`.** Each step is one discrete, verifiable unit of work — one file change, one DDL command, one smoke test addition. If a step cannot be verified on its own, it is too coarse and should be split. If two items are always done together, they belong in one step. Completed steps use `[x]`; incomplete steps use `[ ]`.
- **State blockers explicitly.** If a step cannot begin until a decision is made or a prior phase is verified, say so in plain language before the step list — not buried inside a step.
- **End each phase with a horizontal rule (`---`).** This visually separates phases and makes it easy to scan the document for where one phase ends and the next begins.

- **Feature docs**
- Use the pattern seen in recent docs such as `docs/feature_mcp_server_doc_addition.md` and `docs/feature_completed_import_media_from_zip.md`.
- Preferred outline:
  - `# Feature: <name>`
  - `Status`, `Date`, and optional parent/related feature reference near the top
  - `## Elevator Pitch` — one short non-technical paragraph; required
  - `## Overview`
  - `## Primary Use Case and Scope` or `## Use Cases`
  - `## Design Decisions` / architecture / data flow sections as needed
  - `## UX Considerations` (optional) — placed after `## Design Decisions` and before `## UX Wireframe` when present; use this section to document UX trade-offs, multi-option decisions, and what the user experiences across different flows (e.g. happy path vs error path vs recovery path). Not a substitute for the wireframe — the wireframe shows states, this section explains the reasoning behind them.
  - `## UX Wireframe` (required when the feature has user-visible changes) — ASCII wireframe placed after `## UX Considerations` when present, otherwise after `## Design Decisions`; rules:
    - Show every distinct UI state the user can encounter: default, alternate selection, in-progress, done, and error at minimum; add disabled/unavailable states when applicable.
    - For each state, show the exact button label and whether it is enabled or disabled — button state and label changes are first-class citizens of the wireframe.
    - Annotate what is new or changed from the existing UI with `← NEW` or `← changed` inline comments.
    - Label each state block clearly (e.g. `STATE A — ...`, `STATE B — ...`) so implementation steps can reference them by name.
    - Use a single fenced code block with plain text box-drawing characters (`┌`, `─`, `│`, `└`, `◉`, `○`, `✓`, `✗`, `↻`).
  - `## Files Under Change` — **required** as soon as the feature reaches implementation or planning depth; numbered list (not a table) where each entry names the file, its repo, and a one-line concrete synopsis of every discrete change made to that file — never a vague placeholder like "all steps above" or "see implementation section". Use sub-headings `### New` and `### Modified` when both types are present; add an **Unchanged** line for key files that are explicitly unaffected.
- Feature docs should explain the user-facing problem, the intended behavior, the chosen architecture, and important constraints or deferred scope.
- For larger features, prefer explicit phase breakdowns and call out shared patterns or reusable infrastructure.

- **Problem / RCA docs**
- Use the pattern seen in recent RCAs such as `docs/problem_iphone_qr_code_redirect.md` and `docs/problem_cloudflare_cached_error_messages.md`.
- Preferred outline:
  - YAML frontmatter `description`
  - `# Problem: <name>`
  - `## Business Summary` — **required**; placed immediately after the title, before all other sections; three sentences maximum; plain non-technical language describing what is broken, who is affected, and what the fix is — as if explaining to a non-technical stakeholder in 30 seconds. No jargon, no stack traces, no code references. State the symptom the user sees, the underlying cause in one phrase, and the fix in one phrase (e.g. "The server was not returning a security token after upload. The upload system was updated to a new file-transfer method but the token step was not carried over. Two targeted server changes restore the token and fix the response format.").
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
    - `## Elevator Pitch` — one short non-technical paragraph; required
    - `## Summary` or `## Proposed change`
    - `## Rationale`
    - `## Constraints / non-goals`
    - `## UX requirements` or `## Agreed Requirements` — use `## UX Considerations` instead when the goal is to document trade-offs and multi-option decisions rather than requirements
    - `## Implementation plan`
    - `## Files Under Change` — **required**; numbered list (not a table) where each entry names the file, its repo, and a one-line concrete synopsis of every discrete change made to that file — never a vague placeholder like "all steps above" or "see implementation section".
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
  - `## Elevator Pitch` — one short non-technical paragraph; required
  - `## Rationale` — why the change is necessary or desirable; product and UX reasoning
  - `## Goal` — the change stated as a policy; one sentence + bold policy statement
  - `## Industry Precedent` — comparable systems or prior art that validate the approach
  - `## Decision` — the chosen design, stated as settled fact (not open question)
  - `## Benefits / Potential Drawbacks` — two-column list of concrete benefits and honest trade-offs or risks of the chosen approach; required for any refactor that involves a meaningful architectural choice
  - `## Real World Use Cases` — before/after scenario tables with named personas
  - `## Design Principles` — constraints and invariants that must hold after the refactor
  - `## Current State` (or `## Current Auth Model`, etc.) — what the existing code does and why it creates the problem
  - `## Proposed Implementation` — Files Under Change numbered list (new/modified) first, then per-subsystem detail with schema facts, step-by-step changes, and SonarQube / best-practice notes per subsystem
  - `## UX Considerations` (optional) — placed after `## Proposed Implementation` and before `## Wireframe` when present; use when there are meaningful UX trade-offs, multi-option decisions, or non-obvious user flows to explain (e.g. what the user sees in a recovery path, why one display option was chosen over another). Distinct from the wireframe: the wireframe shows states, this section explains the reasoning.
  - `## Wireframe` — ASCII UI sketch when UX is involved
  - `## Files Under Change` — numbered list (not a table) where each entry names the file, its repo, and a one-line concrete synopsis of every discrete change made to that file — never a vague placeholder like "all steps above" or "see implementation section".
  - Supporting analysis sections (e.g., `## Token TTL vs Gallery Expiry`) — alternatives considered and why they were rejected; mark as historical context if decision is already made
  - `## Progress` — **always last**; subsections: Completed / Remaining — This Feature / Remaining — Follow-on Tasks

- **Refactor doc rules**
- Progress always goes at the bottom — the reader should understand the full plan before seeing where work stands.
- State the Decision early and unambiguously; do not let analysis sections downstream look like open questions.
- SonarQube and best-practice notes belong inside the implementation section, scoped per subsystem (PHP, Swift, etc.).
- Follow-on tasks get their own subsection in Progress, not in the main plan body.

- **DDL in implementation docs**
- Whenever an implementation doc (`feature_*.md`, `pr_*.md`, `problem_*.md`, `refactor_*.md`, etc.) includes any DDL that changes schema on an existing environment (`ALTER TABLE`, `CREATE TABLE`, `CREATE INDEX`, `DROP INDEX`, etc.), always do both:
  1. update `create_media_db.sql` so fresh environments bootstrap with the new schema, and
  2. include a dedicated section that gives the exact `docker exec` command to apply the equivalent live SQL against the MySQL container on existing environments:

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
- Follow existing Ansible and `group_vars` conventions for configuration.
- Be explicit about Ubuntu or tooling compatibility when the user raises environment concerns.

## Debugging Protocol

When a problem arises, **DO NOT SPECULATE**. I want concrete evidence for our course of action.  Follow this process:

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
