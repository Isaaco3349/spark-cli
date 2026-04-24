# Spark Onboarding Contract v1

This is the product contract for the default Spark install. If a fresh user
runs the official installer and provides a Telegram bot token plus one LLM
gateway, Spark should start with a coherent local ecosystem, not five cloned
repos the user has to connect by hand.

## One Front Door

The public entrypoints are:

- macOS/Linux/WSL: `scripts/install.sh`
- Windows PowerShell: `scripts/install.ps1`

Both installers must:

1. Install into a local prefix, defaulting to `~/.spark`.
2. Own the Node runtime so Spawner and Telegram are not blocked by stale system
   Node versions.
3. Install Spark CLI into an isolated Python virtualenv.
4. Write a wrapper that exports `SPARK_HOME` to the same prefix.
5. Run `spark setup telegram-starter` by default.

## Default Starter Stack

`spark setup` defaults to `telegram-starter`, which is the blessed five-module
Spark body:

- `spark-researcher`
- `spark-intelligence-builder`
- `domain-chip-memory`
- `spawner-ui`
- `spark-telegram-bot`

The installer must clone missing registry modules, validate every
`spark.toml`, enforce capability conflicts, install the batch in dependency
order, write module records, and generate per-module env files.

## Gateway Wiring

Setup owns the first wiring pass:

- `spark-telegram-bot` receives Telegram token/admin configuration.
- `spark-telegram-bot` receives `SPARK_BUILDER_REPO` so it can find Builder.
- `spark-telegram-bot` receives `SPAWNER_UI_URL`.
- `spawner-ui` receives `MISSION_CONTROL_WEBHOOK_URLS`.
- Telegram, Spawner, and Builder receive the selected LLM gateway settings.

LLM provider setup is intentionally explicit:

- `--llm-provider zai --zai-api-key ...` for Z.AI GLM coding endpoint.
- `--llm-provider openai --openai-api-key ...`.
- `--llm-provider anthropic --anthropic-api-key ...`.
- `--llm-provider ollama --ollama-url ... --ollama-model ...`.

If no cloud provider is selected, setup defaults to Ollama. `spark status` must
surface the configured provider and repair hints for missing cloud keys.

## Definition of Ready

A starter install is ready when all of these pass:

1. `python -m pytest tests/test_cli.py -q`.
2. WSL/macOS/Linux installer smoke with `--skip-setup`.
3. WSL/macOS/Linux sandbox setup smoke with `SPARK_HOME` under a temp prefix,
   local registry overrides, and `--skip-install-commands`.
4. Windows installer static contract test.
5. `spark status --json` returns five installed modules and includes the LLM
   provider setup state.

## Known Next Gaps

- LLM API keys should move from generated env files into manifest-declared
  keychain secrets once Telegram, Spawner, and Builder all declare the same LLM
  secret contract.
- The Spawner provider registry should consume installer-generated provider
  env directly instead of relying on UI/local-storage configuration.
- The default install should eventually offer a guided first-agent prompt after
  setup, then run `spark start` and prove Telegram ingress with a local smoke.
