#!/usr/bin/env bash
# Starts AWS Emulator in the background and waits for its health check.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port="${EMULATOR_PORT:-9297}"
telemetry="${EMULATOR_TELEMETRY:-off}"
timeout="${EMULATOR_WAIT_TIMEOUT:-60}"

if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
  echo "::error::port must be a number, got: ${port}"
  exit 1
fi
if ! [[ "${timeout}" =~ ^[0-9]+$ ]]; then
  echo "::error::wait-timeout must be a number of seconds, got: ${timeout}"
  exit 1
fi

args=(-p "${port}")
case "${telemetry}" in
  off) args+=(--telemetry off) ;;
  on) ;;
  *)
    echo "::error::telemetry must be \"on\" or \"off\", got: ${telemetry}"
    exit 1
    ;;
esac

home="$(emulator_home)"
emulator_dir="${home}/.aws/emulator/${port}"
ca_bundle="${emulator_dir}/ca.pem"
health_url="https://127.0.0.1:${port}/__admin/health"
log_file="${RUNNER_TEMP:-/tmp}/aws-emulator-${port}.log"

HOME="${home}" nohup aws-emulator "${args[@]}" >"${log_file}" 2>&1 &
pid=$!

ready=0
for ((i = 0; i < timeout; i++)); do
  if [[ -f "${ca_bundle}" ]] && curl -sf --cacert "${ca_bundle}" "${health_url}" >/dev/null; then
    ready=1
    break
  fi
  if ! kill -0 "${pid}" 2>/dev/null; then
    echo "::error::AWS Emulator exited during startup. Log:"
    cat "${log_file}"
    exit 1
  fi
  sleep 1
done

if [[ "${ready}" != 1 ]]; then
  echo "::error::AWS Emulator did not pass its health check within ${timeout} seconds. Log:"
  cat "${log_file}"
  exit 1
fi

echo "AWS Emulator is healthy at https://127.0.0.1:${port} (pid ${pid})"

{
  echo "endpoint=https://127.0.0.1:${port}"
  echo "ca-bundle=$(runner_path "${ca_bundle}")"
  echo "log-file=$(runner_path "${log_file}")"
} >>"${GITHUB_OUTPUT}"
