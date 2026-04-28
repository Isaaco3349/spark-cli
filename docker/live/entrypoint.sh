#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[spark-live] %s\n' "$*"
}

die() {
  log "ERROR: $*"
  exit 2
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    die "$name is required. Set it as a platform secret/env var, not in the image."
  fi
}

provider="${SPARK_LLM_PROVIDER:-}"
if [ -z "$provider" ]; then
  die "SPARK_LLM_PROVIDER is required. Good VPS/Railway choices: zai, openai, openrouter, kimi, huggingface, minimax, anthropic with API key."
fi

require_env TELEGRAM_BOT_TOKEN
require_env TELEGRAM_ADMIN_IDS

export SPARK_SPAWNER_PORT="${SPARK_SPAWNER_PORT:-${PORT:-5173}}"
export SPARK_SPAWNER_HOST="${SPARK_SPAWNER_HOST:-0.0.0.0}"

setup_args=(
  setup
  telegram-starter
  --non-interactive
  --run-install-commands
  --bot-token
  "@env:TELEGRAM_BOT_TOKEN"
  --admin-telegram-ids
  "$TELEGRAM_ADMIN_IDS"
  --llm-provider
  "$provider"
  --spawner-ui-url
  "http://127.0.0.1:${SPARK_SPAWNER_PORT}"
)

case "$provider" in
  zai)
    require_env ZAI_API_KEY
    setup_args+=(--zai-api-key "@env:ZAI_API_KEY")
    ;;
  openai)
    require_env OPENAI_API_KEY
    setup_args+=(--openai-api-key "@env:OPENAI_API_KEY")
    if [ -n "${OPENAI_BASE_URL:-}" ]; then
      setup_args+=(--openai-base-url "$OPENAI_BASE_URL")
    fi
    ;;
  openrouter)
    require_env OPENROUTER_API_KEY
    setup_args+=(--openrouter-api-key "@env:OPENROUTER_API_KEY")
    ;;
  kimi)
    require_env KIMI_API_KEY
    setup_args+=(--kimi-api-key "@env:KIMI_API_KEY")
    ;;
  huggingface)
    require_env HF_TOKEN
    setup_args+=(--huggingface-api-key "@env:HF_TOKEN")
    ;;
  minimax)
    require_env MINIMAX_API_KEY
    setup_args+=(--minimax-api-key "@env:MINIMAX_API_KEY")
    ;;
  anthropic)
    require_env ANTHROPIC_API_KEY
    setup_args+=(--anthropic-api-key "@env:ANTHROPIC_API_KEY")
    ;;
  lmstudio)
    setup_args+=(--lmstudio-base-url "${LMSTUDIO_BASE_URL:-http://host.docker.internal:1234/v1}" --lmstudio-model "${LMSTUDIO_MODEL:-local-model}")
    ;;
  ollama)
    setup_args+=(--ollama-url "${OLLAMA_URL:-http://host.docker.internal:11434}" --ollama-model "${OLLAMA_MODEL:-llama3.2:3b}")
    ;;
  codex)
    die "codex OAuth is interactive and is not supported in a headless VPS/Railway container. Use openai with OPENAI_API_KEY, or run Spark locally after codex login."
    ;;
  *)
    die "Unsupported SPARK_LLM_PROVIDER '$provider'."
    ;;
esac

if [ -n "${SPARK_MODEL:-}" ]; then
  case "$provider" in
    zai) setup_args+=(--zai-model "$SPARK_MODEL") ;;
    openai) setup_args+=(--openai-model "$SPARK_MODEL") ;;
    openrouter) setup_args+=(--openrouter-model "$SPARK_MODEL") ;;
    kimi) setup_args+=(--kimi-model "$SPARK_MODEL") ;;
    huggingface) setup_args+=(--huggingface-model "$SPARK_MODEL") ;;
    minimax) setup_args+=(--minimax-model "$SPARK_MODEL") ;;
    anthropic) setup_args+=(--anthropic-model "$SPARK_MODEL") ;;
    lmstudio) setup_args+=(--lmstudio-model "$SPARK_MODEL") ;;
    ollama) setup_args+=(--ollama-model "$SPARK_MODEL") ;;
  esac
fi

cleanup() {
  log "Stopping Spark Live..."
  spark live stop >/dev/null 2>&1 || true
}
trap cleanup TERM INT

log "Configuring Spark in ${SPARK_HOME} with provider '${provider}'..."
spark "${setup_args[@]}"

if [ "${SPARK_LIVE_SKIP_UPDATE:-0}" != "1" ]; then
  log "Refreshing installed modules to the image registry pins..."
  spark update --skip-dirty
fi

log "Starting Spark Live on Spawner ${SPARK_SPAWNER_HOST}:${SPARK_SPAWNER_PORT}..."
spark live start

log "Spark Live is running. Combined logs follow."
spark live logs --follow --lines 80 &
log_pid="$!"
wait "$log_pid"
