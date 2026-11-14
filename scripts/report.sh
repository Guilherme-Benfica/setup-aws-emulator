#!/usr/bin/env bash
# Writes the AWS Emulator report for the end of a job: where the log is, and how to tell
# an emulator limitation (NotImplemented, HTTP 501) from a bug in your code.
# Usage: report.sh [PORT]. Prints the report, adds it to the job summary, and sets the
# log-file and artifact-name outputs.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port="${1:-9297}"
log="$(work_dir "${port}")/emulator.log"

report="$(
  echo "### AWS Emulator report (port ${port})"
  echo
  if [[ -f "${log}" ]]; then
    echo "- Emulator log: \`$(windows_path "${log}")\`, also uploaded as an artifact."
  else
    echo "- No emulator log found for port ${port}."
  fi
  # The emulator logs every state-changing operation (target emulator::audit) with its
  # outcome. List the ones it refused: often an emulator gap rather than a bug.
  if [[ -f "${log}" ]]; then
    refused="$(grep '"target":"emulator::audit"' "${log}" | grep -v '"outcome":"\(created\|updated\|deleted\|ok\|succeeded\)"' |
      sed -n 's/.*"operation":"\([^"]*\)".*"outcome":"\([^"]*\)".*/\1 (\2)/p' | sort | uniq -c | sort -rn || true)"
    total="$(grep -c '"target":"emulator::audit"' "${log}" || true)"
    echo "- State-changing operations: ${total}."
    if [[ -n "${refused}" ]]; then
      echo "- Not completed by the emulator (count, operation, outcome):"
      while read -r count rest; do echo "  - ${count}× \`${rest%% *}\` ${rest#* }"; done <<<"${refused}"
    fi
  fi
  echo "- A call that fails with \`NotImplemented\` (HTTP 501, \"scaffolded but not implemented in this emulator\")"
  echo "  uses an operation AWS Emulator does not support yet. That is an emulator limitation, not a bug in your code."
  echo "  Coverage grows with every release: https://github.com/aws/aws-emulator/releases"
)"

echo "${report}"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "${report}" >>"${GITHUB_STEP_SUMMARY}"
fi
if [[ -f "${log}" ]]; then
  set_output log-file "$(windows_path "${log}")"
fi
set_output artifact-name "aws-emulator-log-${GITHUB_JOB:-job}-${RUNNER_OS:-os}-${port}-${GITHUB_RUN_ATTEMPT:-1}-${RANDOM}"
