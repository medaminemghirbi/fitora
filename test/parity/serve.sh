#!/usr/bin/env bash
# Both apps as the parity suite needs them (MIGRATION_AUDIT §12.1): one Rails
# server on :3100 serving the API (for Angular) and the web UI, against the
# parity database, with the clock stopped; the Angular app on :4300 in its e2e
# configuration (API on :3100). Ctrl-C stops both.
#
#   test/parity/serve.sh            # reseeds the parity database first
#   SKIP_SEED=1 test/parity/serve.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

export DATABASE_URL="${PARITY_DATABASE_URL:-postgres:///backend_parity_demo}"
export FITORA_FROZEN_TIME="${FITORA_FROZEN_TIME:-2026-10-14T10:00:00+01:00}"
export DISABLE_RACK_ATTACK=1 FRONTEND_ORIGINS=http://localhost:4300 FRONTEND_URL=http://localhost:4300

[ -n "${SKIP_SEED:-}" ] || bin/rails db:prepare parity:seed
npm run build --silent
npm run build:css --silent

(cd ../frontend && npx ng serve --configuration e2e --port 4300) &
ANGULAR=$!
trap 'kill $ANGULAR 2>/dev/null || true' EXIT
bin/rails server -p 3100 -P tmp/pids/parity.pid
