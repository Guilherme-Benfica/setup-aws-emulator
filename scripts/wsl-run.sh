#!/usr/bin/env bash
# Runs the emulator in the foreground for the Windows awsemu, inside WSL. Paths arrive
# through WSLENV already translated (USERPROFILE, AWSEMU_LOG), so names with non-ASCII
# characters never pass through a Windows console code page.
set -euo pipefail

args=(-p "${EMULATOR_PORT:-9297}")
if [[ "${EMULATOR_TELEMETRY:-off}" == off ]]; then
  args+=(--telemetry off)
fi
HOME="${USERPROFILE:?}" exec aws-emulator "${args[@]}" >>"${AWSEMU_LOG:?}" 2>&1
