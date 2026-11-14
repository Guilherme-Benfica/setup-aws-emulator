#!/usr/bin/env bash
# Exits 0 when the emulator on EMULATOR_PORT answers its health check. Used by the
# Windows awsemu, inside WSL, so no certificate path has to cross into Windows.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port="${EMULATOR_PORT:-9297}"
ca="$(emulator_home)/.aws/emulator/${port}/ca.pem"
[[ -f "${ca}" ]] && curl -sf --cacert "${ca}" "https://127.0.0.1:${port}/__admin/health" >/dev/null
