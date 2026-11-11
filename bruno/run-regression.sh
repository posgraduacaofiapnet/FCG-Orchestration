#!/usr/bin/env bash
# Run the Bruno collection (asserts + scripts) against Docker or AWS.
# Requires Node/npm. Uses npx @usebruno/cli.
#
#   ./bruno/run-regression.sh
#   ./bruno/run-regression.sh AWS
#   ./bruno/run-regression.sh Docker
set -euo pipefail

ENV_NAME="${1:-AWS}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRUNO_CLI_VERSION="${BRUNO_CLI_VERSION:-4.3.0}"

echo "Running Bruno collection against env: $ENV_NAME"
cd "$SCRIPT_DIR"
npx --yes "@usebruno/cli@${BRUNO_CLI_VERSION}" run . -r \
  --env "$ENV_NAME" \
  --sandbox developer \
  --reporter-html bruno-report.html

echo ""
echo "HTML report: $SCRIPT_DIR/bruno-report.html"
