# Lessons from today's install (2026-04-22)

On 2026-04-22 we installed three Spark modules from scratch on a clean macOS
machine: `spark-intelligence-builder`, `spark-telegram-bot`, and
`vibeship-spawner-ui`. This document captures what hurt and what those pains
imply for Spark's official installer. Use it as a litmus test: any future
install design that re-introduces one of these pains has a problem.

## 1. Three repos, no entry point

**What happened.** The user manually downloaded three GitHub zip archives. There
was no single command, no installer, no awareness of what depended on what.
Discoverability was zero — without asking Claude, the user wouldn't have known
`spark-telegram-bot` was redundant given `spark-intelligence-builder`'s built-in
Telegram channel.

**Implication.** Spark needs **one front door**. `brew install spark` (or
`curl -fsSL sparkswarm.ai/install | sh`) installs a small CLI. Everything else is
discovered and installed *through* that CLI, never by manual zip downloads.

## 2. Three runtimes with no version pinning

**What happened.** Python venv setup, Node version check, and pip vs npm vs npm
audit all surfaced as user-visible decisions. The user happened to have Node 22
and Python 3.14 installed by luck. A user without a working Python toolchain
would have hit a wall before installing anything.

**Implication.** The installer must **own runtime acquisition**. Detect missing
Python/Node/Bun, offer to install them via the OS-native package manager
(Homebrew, apt, winget), and pin to versions known to work with the manifest's
declared `runtime.version`. Users should never see "your Python is too old."

## 3. Two `.env.example` files with overlapping vars and stale refs

**What happened.** `vibeship-spawner-ui/.env.example` and
`spark-telegram-bot/.env.example` both ask for `ANTHROPIC_API_KEY`. Both still
reference `MIND_API_URL` (Mind V5, which has been deprecated/removed). Setting
up either required reading 30+ env var comments, half of which referred to
systems no longer in scope.

**Implication.** Per-module `.env` files are the wrong abstraction. **One
config wizard** asks the user once for each secret/setting, then writes the
right values to the right places automatically. Stale env vars should be
removed from manifests, not "left for the user to figure out."

The wizard should also be **secret-aware**: detect that Claude Code is
installed locally and OAuth-authenticated → don't ask for `ANTHROPIC_API_KEY`
at all. Reduce questions by inferring what's already true.

## 4. Stale paths in committed config files

**What happened.** Several `CLAUDE.md` files reference `C:/Users/USER/Desktop/`
paths from their original Windows authors. On a Mac these references silently
make doc commands fail or send users to non-existent directories.

**Implication.** Module authors should reference paths via env vars
(`$SPARK_HOME`, `$MODULE_HOME`) — never hard-coded absolute paths. The
installer should set those env vars and the manifest should declare which
ones a module reads. A linter on `spark.toml` can flag any module shipping
hard-coded user-specific paths in tracked files.

## 5. Wrong content committed to a load-bearing file

**What happened.** `vibeship-spawner-ui/README.md` is, line for line, the
Supabase CLI's README. Anyone landing on the repo for the first time sees
content that has nothing to do with Spawner UI.

**Implication.** Spark's module CI should run a basic sanity check on
`README.md` and `spark.toml` before a module can be added to the registry:
README's first heading should match the module's declared name, manifest
should validate against schema, healthcheck should actually run.

## 6. No single status command

**What happened.** `spark-intelligence` has a `doctor` command. Spawner UI has
nothing. The Node bot has nothing. To know what's working, the user has to
inspect each module's logs, config, and process state separately.

**Implication.** `spark status` is mandatory. It shows ✓/✗ for every installed
module, calls each module's declared `healthcheck` command, and tells the user
*how to fix* anything red. No silent failures, no manual log digging.

## 7. Two parallel Telegram gateways with no documentation that they're parallel

**What happened.** `spark-intelligence-builder` and `spark-telegram-bot` both
own Telegram ingress, with no contract between them and no doc explaining the
overlap. The user had to ask Claude whether they connected. They don't.

**Implication.** When two modules provide the same capability (e.g.
`telegram.gateway`), the installer should detect the conflict and refuse to
enable both with the same bot token. Module manifests must declare what
capabilities they `provides`, and `spark install` should warn on overlap with
clear options ("you already have telegram.gateway from `spark-intelligence`;
disable that first, or use a different bot token").

## 8. Cost gotchas hidden in user-global config

**What happened.** The user's `~/.claude/settings.json` has
`"model": "opus[1m]"`. A trivial smoke test against `claude -p` cost $0.12 due
to 1M-context cache write pricing. A user wiring spawner-ui to `claude -p`
without overriding the model would see surprising bills.

**Implication.** When Spark configures any LLM-calling module, surface the
likely per-call cost during setup based on the inherited model. Offer a sane
default (e.g. `sonnet` for spawner-style fan-out). Treat user-global LLM
config as untrusted input — show it back, confirm, override per-module if
needed.

## 9. No "what depends on what" map

**What happened.** It took reading 4 READMEs, 1 `CLAUDE.md`, and asking Claude
direct questions to figure out: spark-telegram-bot needs Spawner UI; Spawner UI
doesn't need anything; spark-intelligence is fully standalone.

**Implication.** Modules should declare their dependencies in `spark.toml`
under `needs.modules`. The installer renders a dependency graph during install
and on `spark status --graph`. The web/dashboard installer shows it visually
during onboarding so users understand the shape before they pick.

---

## What a "good" install would have looked like today

```bash
$ brew install spark
$ spark setup
  → Claude Code detected, OAuth authenticated — will use it for LLM calls
  ? Telegram bot token (skip with enter): ●●●●●●●
  ? Discord bot token (skip with enter):
  → Installing spark-intelligence (Python module via uv)...
  → Installing spawner-ui (Node module via bun)...
  ✓ Doctor: 2/2 modules healthy
$ spark start
  → spark-intelligence: telegram polling @SparkAGI_bot
  → spawner-ui: http://localhost:5173 (claude -p, OAuth)
$ spark status
  ✓ spark-intelligence  v0.4.0   telegram online, 0 jobs queued
  ✓ spawner-ui          v0.0.1   http://localhost:5173, claude-cli ready
```

Three commands. Zero `.env` editing. Zero "which port does what." Zero stale
references to Mind V5 or Windows paths. The user never types `pip install`,
never makes a venv decision, never sees a vulnerability count.

That's the bar.
