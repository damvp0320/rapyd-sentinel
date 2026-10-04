#!/usr/bin/env bash
# Renders the gateway manifest templates (*.tpl) into <outdir>, injecting the backend NLB hostname.
# Usage: scripts/render-gateway.sh <backend-nlb-hostname> <outdir>
set -euo pipefail

if [[ $# -ne 2 || -z "$1" ]]; then
  echo "usage: $0 <backend-nlb-hostname> <outdir>" >&2
  exit 1
fi

export BACKEND_HOST="$1"
SRC="$(cd "$(dirname "$0")/../k8s/gateway" && pwd)"
OUT="$2"
mkdir -p "$OUT"

for tpl in "$SRC"/*.tpl; do
  # Only substitute BACKEND_HOST so nginx variables such as $host are left untouched.
  envsubst '${BACKEND_HOST}' < "$tpl" > "$OUT/$(basename "${tpl%.tpl}")"
done
cp "$SRC"/*.yaml "$OUT"/
echo "rendered to $OUT"
