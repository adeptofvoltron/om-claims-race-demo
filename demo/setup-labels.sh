#!/usr/bin/env bash
# Creates (or updates) every label configured in .ai/agentic.config.json.
# A missing in-progress label blocks every claim, so run this before any scenario.
. "$(dirname "$0")/lib.sh"
config="$DEMO_ROOT/.ai/agentic.config.json"
for group in pipeline:0e8a16 category:d73a4a meta:fbca04 priority:5319e7 risk:b60205; do
  name=${group%%:*}; color=${group#*:}
  jq -r --arg g "$name" '.labels[$g][]' "$config" | while IFS= read -r label; do
    gh label create "$label" --repo "$REPO" --color "$color" --description "$name label" --force >/dev/null
    echo "label: $label"
  done
done
