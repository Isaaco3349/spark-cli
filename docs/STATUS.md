# Spark CLI — Status Audit

**As of:** 2026-04-22
**Scope:** the `spark-cli` spike at `C:\Users\USER\Desktop\spark-cli`
**Source of truth:** `src/spark_cli/cli.py` (1255 LOC) + `tests/test_cli.py` (491 LOC)
**Test state:** 27/27 passing (including uncommitted WIP)

This document exists because the previous session's terminal exited mid-work.
It's a ground-truth check against the v1 design before we continue.

---

## TL;DR

The spike **covers the full install → setup → start → status → stop → uninstall
lifecycle** for modules declared in a local `registry.json`. It is behind the
v1 design on three fronts: (1) **no interactive wizard**, (2) **no OS
keychain** for secrets, (3) **no git-based fetch** — registry entries still
point at local paths.

The uncommitted WIP is the **ready-check + pid-liveness** feature. It is
complete and green; just not committed.

**Recommended next cut:** commit the WIP, then ship the interactive
`spark setup` wizard. That's the single highest-impact gap vs the v1 design.

---

## ✅ Built and shipped (committed)

Tracked through 11 commits on `master`. Behavior covered by tests unless noted.

| Area | What works | Code | Test |
|---|---|---|---|
| Manifest parsing | `spark.toml` → `Module` dataclass with typed accessors | `cli.py:30-123` | ✓ via fixtures |
| Registry | Local `registry.json` with modules + bundles | `cli.py:126-128`, `registry.json` | `test_resolve_bundle_names_reads_registry_bundle` |
| `list` | Lists discovered modules w/ version/kind/plane/blessed/installed | `cli.py:386-397` | — |
| `install <module>` | By registry name or local path, with `[install.dev].commands` execution | `cli.py:697-737` | `test_resolve_install_target_*`, `test_execute_install_commands_*` |
| `install <bundle>` | Resolves bundle, enforces single telegram ingress owner | `cli.py:702-721` | `test_detect_ingress_owner_*` |
| Capability conflict guard | Blocks double-ownership of `telegram.ingress` | `cli.py:312-326` | `test_detect_capability_conflicts_*` |
| `setup <bundle>` | Manifest-driven secret collection, generates per-module env, routes telegram secret only to gateway | `cli.py:740-787` | `test_build_module_envs_routes_*`, `test_collect_secret_*` |
| Managed `.env` block | Idempotent `# --- spark-cli managed start/end ---` block in module `.env` | `cli.py:337-383` | `test_update_env_file_*`, `test_remove_managed_env_block_*` |
| Generic secret input | `--secret KEY=VALUE` + legacy `--bot-token` flags | `cli.py:157-212` | `test_collect_secret_values_*` |
| `status` + `--json` | Per-module healthcheck; dep-aware repair hints | `cli.py:814-886` | `test_build_module_repair_hints_*`, `test_build_status_repair_hints_*` |
| `doctor` + `--json` | Diagnostic-mode wrapper around status | `cli.py:889-896` | — |
| `update [target]` | Re-runs install commands, runs `post_install` hook, re-syncs env | `cli.py:1134-1157` | `test_install_module_record_*` (provenance) |
| `uninstall [target]` | `pre_uninstall` hook → stop pid → delete generated env → strip managed block → `post_uninstall` | `cli.py:1160-1191` | `test_update_setup_state_after_uninstall_*` |
| `uninstall --force` | Bypasses dependency protection | `cli.py:1168-1169` | `test_detect_uninstall_blockers_*` |
| `start [target]` | Topological order by `needs.modules`; pid tracking in `~/.spark/state/pids.json` | `cli.py:1090-1104` | `test_resolve_start_modules_orders_*` |
| `stop [target]` | Reverse-topological stop using dependents graph | `cli.py:1115-1131` | `test_resolve_stop_module_names_*` |
| Install provenance | `installed.json` tracks `installed_via`, `bundle_provenance`, `last_install`/`last_update` | `cli.py:412-461` | `test_install_module_record_writes_provenance_metadata` |
| Per-module process logs | `~/.spark/logs/<module>/process.log` (written during `start`) | `cli.py:1055-1058` | — |
| Output summarization | Strips npm `> ...` prefix lines in healthcheck detail | `cli.py:800-811` | `test_summarize_command_output_*` |
| Windows process groups | `DETACHED_PROCESS` + `taskkill /T /F` | `cli.py:1060-1062`, `cli.py:1108-1112` | — |

---

## 🟡 Uncommitted WIP (green, just not committed)

Files with changes: `src/spark_cli/cli.py` (+76 / -7), `tests/test_cli.py` (+33).

- `pid_is_running(pid)` — checks process liveness via `os.kill(pid, 0)`.
  If a pid in `pids.json` is stale (process died), `start_module` drops it
  and launches fresh. Test: `test_pid_is_running_detects_current_process`.
- `ready_timeout_seconds(module)` — reads `[healthcheck].timeout_seconds`
  with sensible default (10s). Test: `test_ready_timeout_seconds_*`.
- `wait_for_ready_check(module)` — polls `[run.default].ready_check`
  until the deadline. HTTP URLs use `urllib.request`; anything else runs
  as a shell command. Test: `test_wait_for_ready_check_runs_shell_*`.
- `start_module` now **returns `bool`** (ready/not) and `cmd_start`
  propagates an error exit code if any module fails its ready check.
- Removed unused `import shlex`.

**All 27 tests pass with these changes in place.** Safe to commit as-is.

---

## ❌ Not built (v1 design gaps)

Mapped to the design docs you pasted (now persisted under `docs/design/`).

### High-value, small lift

1. **Interactive `spark setup` wizard.** Today, setup requires `--secret
   key=value` flags. No TTY prompts, no bundle picker, no Claude-Code
   auto-detection. Closes 6 of 11 rows in the user-flows friction map.
   — `design-v1 §spark setup flow`, `user-flows §5`.
2. **`spark logs <module> [--follow]`.** Logs already land in
   `~/.spark/logs/<name>/process.log` during `start`. Just needs tail.
   — `design-v1 §CLI surface`.
3. **Runtime detection** (`uv` / `bun` / `node` / Claude Code CLI) during
   setup, with Homebrew/winget pointers when missing.
   — `lessons §2`.

### Medium lift

4. **OS keychain secrets storage.** Manifests already declare
   `storage = "keychain"` (see `spark-telegram-bot` bot_token and
   webhook_secret). Today the CLI writes everything as plaintext env
   files in `~/.spark/config/modules/*.env`. Python has `keyring` stdlib
   → Windows Credential Manager on this box.
   — `design-v1 §Secrets handling`.
5. **`spark secrets set/list/rotate`** — keychain-backed CLI surface.
   — `design-v1 §CLI surface`.
6. **`spark config get/set <key>`** — writes user-level
   `~/.spark/config.toml`.
   — `design-v1 §CLI surface`.

### Larger scope

7. **Git-based fetch.** `registry.json` currently points at local paths
   on this machine. Real installer has to `git clone --depth=1`.
   — `design-v1 §Decision 2`.
8. **Capability resolver for `needs.capabilities`.** We detect conflicts
   today (multiple `telegram.ingress` owners) but don't *resolve* needs
   — e.g. a module declaring `needs.capabilities = ["memory.store"]`
   won't get auto-wired to whichever installed module provides it.
   — `user-flows §6`.
9. **Runtime version range enforcement** from `[runtime].version`
   (semver range checking).
10. **Schema version field** (`schema = 1` in `spark.toml`) — for future
    migrations.
11. **Trust prompt** for installing from arbitrary git URLs before
    running any `[hooks]`.
    — `design-v1 §Open question 5`.
12. **`--resume`** for failed installs (idempotent step replay).
13. **`spark search`** (registry discovery).
14. **`spark dashboard`** (SvelteKit foreground app).
15. **`spark init <name>`** (scaffolder for new modules).
16. **`spark login` + license verification + Pro tier gating.**
    — `design-v1 §Licensing & Spark Pro`.
17. **Telemetry opt-in prompt.**

---

## ❓ Unsure — needs a check before acting

1. **Are the three downstream manifests correct and realistic?**
   I read `spark-intelligence-builder/spark.toml` and `spawner-ui/spark.toml`
   — both valid. I read the top of `spark-telegram-bot/spark.toml`; haven't
   seen its full bottom half. Should confirm `[run.default]`, `[hooks]`,
   and `[healthcheck]` blocks are wired.
2. **Does `npm run health:spark` actually exist in spawner-ui?** The
   manifest declares it; if the script isn't in `package.json`, `status`
   will always show red for spawner-ui.
3. **Does `python -m spark_intelligence.cli doctor` still exist?** The
   builder manifest declares it as the healthcheck. If the CLI renamed
   it, we'd see a false red in `status`.
4. **Is `~/.spark/state/installed.json` currently in a consistent state?**
   It lists all three modules with only basic fields (no `installed_via`,
   no `bundle_provenance`). That shape predates commit `bb850aa`. If a
   user re-runs `install`, the record gets upgraded in place — confirmed
   by reading `install_module_record` (`cli.py:421-461`). Not broken, but
   means current state is from an older format.
5. **Does the `spark` binary on PATH point at this spike or another
   tool?** README notes a conflict and suggests `spark-local`. Haven't
   checked the resolved PATH on this box.

None of these are blockers for the wizard work, but #2 and #3 are worth
running before demoing `status` to anyone.

---

## Recommendation

Two commits in order:

**Commit A — "Wait for ready check and detect stale pids."** Lands the
current WIP. Pure cleanup. Trivial review.

**Commit B — "Add interactive spark setup wizard."** New `--interactive`
default for `setup`. Detect Claude Code OAuth state, `uv`, `bun`, `node`.
Prompt for each `[needs.secrets]` the bundle declares, deduped. Fall back
to non-interactive when `--secret` flags are supplied or stdin isn't a
TTY (keeps the test suite running under pytest).

Secondary, same branch if time allows:
- `spark logs <module> [--follow]` — 30-line add.
- Keychain storage for secrets marked `storage = "keychain"` in their
  manifest block, with the generated env files referencing an indirect
  lookup instead of plaintext.

Defer to next branch: git-based fetch, capability resolver, license /
Pro, dashboard, `init`.
